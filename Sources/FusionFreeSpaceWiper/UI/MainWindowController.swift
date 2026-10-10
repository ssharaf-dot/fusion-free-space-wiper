//
//  MainWindowController.swift
//  Fusion Free Space Wiper
//
//  Guided, single-window interface. The app always opens on Home; a persistent
//  top bar (Home button · step indicator · Advanced) keeps the user oriented.
//  Both Test Mode and Full Wipe drive the SAME engine (FreeSpaceWiper); Test
//  Mode merely passes a strict maxWriteBytes cap.
//

import AppKit

final class MainWindowController: NSWindowController, FreeSpaceWiperDelegate, NSWindowDelegate {

    // Engine + services
    private let inspector = VolumeInspector()
    private let sessions = SessionManager()
    private let recovery = RecoveryTester()
    private let reporter = ReportWriter()
    private let wiper = FreeSpaceWiper()
    private let sleepAssertion = SleepAssertion()
    private let prefs = PreferencesStore.shared

    // State
    private var volumes: [VolumeInfo] = []
    private var selectedVolume: VolumeInfo?
    private var selectedTestSize: TestSize = .mb100
    private var selectedWipeMode: WipeMode = .zeroSinglePass
    private var reserveGiB: Double = 20
    private var lastResult: WipeResult?
    private var lastRecovery: RecoveryTestReport?
    private var plannedTotalBytes: Int64 = 0
    private var mapReserveFraction: CGFloat = 0
    private var activeRunIsTest = false
    private var currentTestSize: TestSize = .mb100

    // Chrome
    private let stepIndicator = StepIndicator()
    private var homeButton: FancyButton!
    private var advancedButton: FancyButton!
    private let scroll = NSScrollView()

    // Running-screen references (built once, reused for test + wipe)
    private var runTitle = UI.label("", size: 20, bold: true)
    private let runStage = UI.label("", size: 13, bold: true, color: Palette.blue)
    private let runSpinner = NSProgressIndicator()
    private let runPercent = UI.label("0%", size: 30, bold: true)
    private let runBlockMap = BlockMapView()
    private let runCaption = UI.label("", size: 12, color: .secondaryLabelColor)
    private var runPauseBtn: FancyButton!
    private var runResumeBtn: FancyButton!
    private var runStopBtn: FancyButton!
    private var runningView: NSView?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Fusion Free Space Wiper"
        window.minSize = NSSize(width: 820, height: 600)
        self.init(window: window)
        window.delegate = self
        wiper.delegate = self
        buildChrome()
        window.center()
        reloadVolumes()
        goHome()
    }

    // MARK: - Chrome

    private func buildChrome() {
        guard let window = window else { return }
        let content = NSView()
        content.wantsLayer = true

        // Top bar with vibrancy for a modern frosted look.
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false

        homeButton = FancyButton("􀎞 Home", kind: .ghost, target: self, action: #selector(goHomeAction))
        homeButton.title = "Home"
        homeButton.toolTip = "Return to the start screen"
        advancedButton = FancyButton("Advanced", kind: .ghost, target: self, action: #selector(goAdvancedAction))
        advancedButton.toolTip = "Reports, diagnostics and leftover-file cleanup"

        let barStack = UI.hstack([homeButton, stepIndicator, advancedButton], spacing: 12)
        barStack.translatesAutoresizingMaskIntoConstraints = false
        stepIndicator.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addSubview(barStack)
        NSLayoutConstraint.activate([
            barStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            barStack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            barStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        // keep step indicator centered by letting it stretch
        barStack.setCustomSpacing(12, after: homeButton)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(bar)
        content.addSubview(scroll)
        window.contentView = content
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: 56),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        buildRunningView()
    }

    /// Host a screen's content in the scroll view with padding, flowing top-down.
    private func host(_ content: NSView) {
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: flipped.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: flipped.bottomAnchor, constant: -24),
        ])
        scroll.documentView = flipped
        flipped.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        scroll.documentView?.scroll(.zero)
    }

    private func setSteps(_ labels: [String]?, _ active: Int) {
        if let labels = labels { stepIndicator.set(labels: labels, active: active) }
        else { stepIndicator.clear() }
    }

    // MARK: - Stat tile

    private func statTile(_ key: String, _ value: String) -> NSView {
        let k = UI.label(key.uppercased(), size: 10, color: .secondaryLabelColor)
        let v = UI.label(value, size: 17, bold: true)
        v.identifier = NSUserInterfaceItemIdentifier(key)
        return UI.vstack([k, v], spacing: 2)
    }
    private func setTile(_ container: NSView, key: String, value: String) {
        if let v = container.subviews.first(where: { ($0 as? NSTextField)?.identifier?.rawValue == key }) as? NSTextField {
            v.stringValue = value
        }
    }

    // MARK: - HOME

    @objc private func goHomeAction() { goHome() }
    func goHome() {
        setSteps(nil, 0)
        let v = selectedVolume
        let heading = UI.title("What would you like to do?")
        let sub = UI.multiline("This tool overwrites the empty space on a disk so previously-deleted files are harder to recover — without touching any of your current files. Start with a quick test.", maxWidth: 640)

        // Status card
        let chip = IconChip("💽", tint: Palette.blue, size: 44)
        let diskCol = UI.vstack([UI.label("DISK", size: 10, color: .secondaryLabelColor),
                                 UI.label(v?.name ?? "—", size: 14, bold: true)], spacing: 2)
        let freeCol = UI.vstack([UI.label("FREE SPACE", size: 10, color: .secondaryLabelColor),
                                 UI.label(v != nil ? ByteText.format(v!.freeCapacityRaw) : "—", size: 14, bold: true)], spacing: 2)
        let tested = TestHistory.shared.quickTestPassed
        let testedFailed = TestHistory.shared.quickTestFailed
        let badgeText = tested ? "✓ 100 MB test passed" : (testedFailed ? "✗ 100 MB test failed" : "● Not tested yet")
        let badgeColor: NSColor = tested ? Palette.green : (testedFailed ? Palette.red : Palette.amber)
        let statusCol = UI.vstack([UI.label("SAFETY TEST", size: 10, color: .secondaryLabelColor),
                                   UI.label(badgeText, size: 13, bold: true, color: badgeColor)], spacing: 2)
        let change = FancyButton("Change disk", kind: .ghost, target: self, action: #selector(pickDisk))
        change.toolTip = "Choose a different mounted, writable disk"
        let statusRow = UI.hstack([chip, diskCol, freeCol, statusCol, NSView(), change], spacing: 18)
        let statusCard = card(statusRow, padding: 14)

        // Choice cards
        let testCard = choiceCard(glyph: "🧪", tint: Palette.green, recommended: true,
            title: "Run a Safety Test",
            desc: "Writes a small, capped amount of data (100 MB / 1 GB / 10 GB) using the real engine, then deletes it. Proves everything works before a full wipe. About 30 seconds.",
            go: "Start test →", goColor: Palette.green, action: #selector(goTestAction))
        let wipeCard = choiceCard(glyph: "🧹", tint: Palette.red, recommended: false,
            title: "Wipe Free Space",
            desc: "Overwrites all free space except a safety reserve. Your existing files, apps and macOS are left untouched.",
            go: "Set up wipe →", goColor: Palette.red, action: #selector(goWipeAction),
            lockNote: TestHistory.shared.quickTestPassed ? nil : "🔒 Safety test recommended first")
        let choices = UI.hstack([testCard, wipeCard], spacing: 16, alignment: .top)
        choices.distribution = .fillEqually

        let note = card(UI.multiline("On a Fusion Drive this makes deleted files harder to recover, but can't guarantee they're unrecoverable (SSD wear-leveling, APFS snapshots). This is never a certified erase. See Help for which Macs benefit most.", size: 12, maxWidth: 820), padding: 12)

        // Pre-wipe test history
        let h = TestHistory.shared
        let hist = UI.label("Pre-wipe tests:   " + TestSize.allCases.map { h.summaryLine($0) }.joined(separator: "      "),
                            size: 11, color: .secondaryLabelColor)

        host(UI.vstack([heading, sub, statusCard, choices, note, hist], spacing: 16))
    }

    @objc private func pickDisk() {
        reloadVolumes()
        let heading = UI.title("Choose a disk")
        let sub = UI.multiline("Only writable, mounted disks are shown. Free-space overwriting happens on the disk you pick here.")
        var rows: [NSView] = [heading, sub]
        for (i, v) in volumes.enumerated() {
            let selected = (selectedVolume?.mountPath == v.mountPath)
            let b = FancyButton("\(selected ? "●" : "○")  \(v.name) — \(v.filesystemType) · \(ByteText.format(v.freeCapacityRaw)) free · \(v.mountPath)",
                                kind: .ghost, target: self, action: #selector(chooseDisk(_:)))
            b.tag = i
            b.toolTip = v.mountPath
            rows.append(b)
        }
        rows.append(FancyButton("Back to Home", kind: .ghost, target: self, action: #selector(goHomeAction)))
        host(UI.vstack(rows, spacing: 10))
    }
    @objc private func chooseDisk(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < volumes.count else { return }
        var v = volumes[sender.tag]
        inspector.enrichDiagnostics(&v)
        selectedVolume = v
        applyRecommendedReserve(for: v)
        goHome()
    }

    // MARK: - TEST FLOW

    private let testSteps = ["Size", "Confirm", "Run", "Result"]
    @objc private func goTestAction() { goTestSize() }
    @objc func goTestSize() {
        selectedTestSize = prefs.defaultTestSize
        setSteps(testSteps, 0)
        let heading = UI.title("Choose a test size")
        let sub = UI.multiline("Bigger tests exercise the engine longer and give a better read on write speed. Start with 100 MB.")
        var rows: [NSView] = [heading, sub]
        for size in TestSize.allCases {
            rows.append(optionRow(title: size.menuTitle + (size == .mb100 ? "   ★ recommended" : ""),
                                  desc: size.subtitle, selected: size == selectedTestSize,
                                  action: #selector(chooseTestSize(_:)), tag: TestSize.allCases.firstIndex(of: size)!))
        }
        let cont = FancyButton("Continue", kind: .primary, target: self, action: #selector(goTestConfirm))
        rows.append(UI.hstack([FancyButton("Back", kind: .ghost, target: self, action: #selector(goHomeAction)), cont]))
        host(UI.vstack(rows, spacing: 10))
    }
    @objc private func chooseTestSize(_ sender: NSButton) {
        selectedTestSize = TestSize.allCases[sender.tag]; goTestSize()
    }
    @objc private func goTestConfirm() {
        guard selectedVolume != nil else { noVolumeAlert(); return }
        setSteps(testSteps, 1)
        let heading = UI.title("Ready to run the \(selectedTestSize.shortLabel) test")
        let sub = UI.multiline("Here's exactly what will happen. Nothing is permanent and your files aren't touched.")
        let info = card(UI.vstack([
            kv("Disk", selectedVolume!.name),
            kv("Will write", "~\(selectedTestSize.shortLabel) of temporary data"),
            kv("Then", "Automatically deleted & space returned"),
            kv("Your existing files", "Not modified"),
        ], spacing: 8))
        let run = FancyButton("Run \(selectedTestSize.shortLabel) Test", kind: .green, target: self, action: #selector(startTest))
        host(UI.vstack([heading, sub, info,
                        UI.hstack([FancyButton("Back", kind: .ghost, target: self, action: #selector(goTestSize)), run])], spacing: 14))
    }

    @objc private func startTest() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        if !preRunPowerChecksPass() { return }
        let reserve = currentReserveBytes()
        let cfg = WipeConfiguration.test(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID,
                                         expectedVolumeName: v.name, reserveBytes: reserve, size: selectedTestSize)
        currentTestSize = selectedTestSize
        activeRunIsTest = true
        plannedTotalBytes = selectedTestSize.bytes
        mapReserveFraction = 0
        beginRun(title: "🧪 \(selectedTestSize.shortLabel) TEST", accent: Palette.green, isTest: true)
        wiper.start(config: cfg)
    }

    // MARK: - WIPE FLOW

    private let wipeSteps = ["Options", "Checklist", "Confirm", "Run", "Result"]
    @objc func goWipeAction() {
        // Safety gate
        if !TestHistory.shared.quickTestPassed {
            let a = NSAlert()
            a.messageText = TestHistory.shared.quickTestFailed ? "The 100 MB test failed" : "Testing recommended"
            a.informativeText = TestHistory.shared.quickTestFailed
                ? "The last 100 MB test did not pass. Consider resolving that before a full wipe."
                : "We recommend running at least the 100 MB test before a full free-space wipe."
            a.alertStyle = TestHistory.shared.quickTestFailed ? .critical : .warning
            a.addButton(withTitle: "Go to Test"); a.addButton(withTitle: "Proceed Anyway"); a.addButton(withTitle: "Cancel")
            switch a.runModal() {
            case .alertFirstButtonReturn: goTestSize(); return
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        goWipeOptions()
    }
    @objc func goWipeOptions() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        setSteps(wipeSteps, 0)
        let heading = UI.title("Wipe options")
        let sub = UI.multiline("A single zero pass is the sensible default. More passes add time and disk wear with no guarantee on SSD/Fusion.")
        var rows: [NSView] = [heading, sub]
        for mode in WipeMode.allCases {
            rows.append(optionRow(title: mode.displayName, desc: wipeModeDesc(mode),
                                  selected: mode == selectedWipeMode, action: #selector(chooseWipeMode(_:)),
                                  tag: WipeMode.allCases.firstIndex(of: mode)!))
        }
        let reserveField = NSTextField(string: String(format: "%.0f", reserveGiB))
        reserveField.identifier = NSUserInterfaceItemIdentifier("reserveField")
        reserveField.translatesAutoresizingMaskIntoConstraints = false
        reserveField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        reserveField.target = self; reserveField.action = #selector(reserveEdited(_:))
        reserveField.toolTip = "Space always kept free. Never below 10 GiB."
        rows.append(NSBox.separator())
        rows.append(UI.hstack([UI.label("Keep this much free (safety reserve):"), reserveField, UI.label("GiB")]))
        rows.append(UI.multiline("Recommended \(ByteText.format(ReservePolicy.recommendedReserve(totalCapacity: v.totalCapacity))). Never below 10 GiB. The app re-checks space before every chunk and never fills the disk.", size: 11))
        rows.append(UI.hstack([FancyButton("Back", kind: .ghost, target: self, action: #selector(goHomeAction)),
                               FancyButton("Continue", kind: .primary, target: self, action: #selector(goWipeChecklist))]))
        host(UI.vstack(rows, spacing: 10))
    }
    @objc private func chooseWipeMode(_ sender: NSButton) { selectedWipeMode = WipeMode.allCases[sender.tag]; goWipeOptions() }
    @objc private func reserveEdited(_ sender: NSTextField) { reserveGiB = max(10, Double(sender.stringValue) ?? reserveGiB) }

    private var checklistBoxes: [NSButton] = []
    @objc private func goWipeChecklist() {
        if let f = scroll.documentView?.viewWithTag(0) as? NSTextField { _ = f }
        captureReserveFromField()
        setSteps(wipeSteps, 1)
        let heading = UI.title("Safety checklist")
        let sub = UI.multiline("Please confirm before overwriting free space.")
        checklistBoxes = []
        let items = ["I have a current backup (Time Machine or a clone).",
                     "The Mac is plugged into power.",
                     "No Time Machine backup or other disk-heavy task is running.",
                     "I understand this is not a certified/forensic erase."]
        var rows: [NSView] = [heading, sub]
        for it in items {
            let cb = NSButton(checkboxWithTitle: it, target: nil, action: nil)
            cb.translatesAutoresizingMaskIntoConstraints = false
            checklistBoxes.append(cb); rows.append(cb)
        }
        rows.append(UI.hstack([FancyButton("Back", kind: .ghost, target: self, action: #selector(goWipeOptions)),
                               FancyButton("Continue", kind: .primary, target: self, action: #selector(goWipeConfirm))]))
        host(UI.vstack(rows, spacing: 10))
    }

    private var confirmField: NSTextField?
    @objc private func goWipeConfirm() {
        guard let v = selectedVolume else { return }
        setSteps(wipeSteps, 2)
        let heading = UI.title("Confirm the wipe")
        let sub = UI.multiline("This overwrites all free space on \(v.name) except your \(Int(reserveGiB)) GiB reserve, then cleans up. To be safe, type the disk name to continue.")
        let field = NSTextField(string: "")
        field.placeholderString = v.name
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        confirmField = field
        var rows: [NSView] = [heading, sub, UI.hstack([UI.label("Type “\(v.name)”:"), field])]
        if v.snapshotState == .yes {
            rows.append(card(UI.multiline("⚠ APFS snapshots detected. They can retain pieces of deleted files and are not removed by this app, so the wipe may be incomplete.", size: 12, color: Palette.red), padding: 12))
        }
        rows.append(UI.hstack([FancyButton("Back", kind: .ghost, target: self, action: #selector(goWipeChecklist)),
                               FancyButton("Overwrite Free Space", kind: .danger, target: self, action: #selector(startWipe))]))
        host(UI.vstack(rows, spacing: 14))
    }

    @objc private func startWipe() {
        guard let v = selectedVolume else { return }
        if prefs.alwaysConfirmName, (confirmField?.stringValue ?? "") != v.name {
            alert("Name did not match", "Type the disk's exact name, “\(v.name)”, to confirm. Aborting for safety."); return
        }
        if !preRunPowerChecksPass() { return }
        let reserve = currentReserveBytes()
        let cfg = WipeConfiguration(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID,
                                    expectedVolumeName: v.name, mode: selectedWipeMode, reserveBytes: reserve)
        activeRunIsTest = false
        let est = wiper.dryRun(config: cfg)
        let writable = est?.writableBytes ?? max(1, v.freeCapacityRaw - reserve)
        plannedTotalBytes = max(1, writable)
        mapReserveFraction = CGFloat(Double(reserve) / Double(max(1, writable + reserve)))
        beginRun(title: "🧹 WIPING FREE SPACE", accent: Palette.red, isTest: false)
        wiper.start(config: cfg)
    }

    // MARK: - RUNNING screen (shared)

    private func buildRunningView() {
        runSpinner.style = .spinning
        runSpinner.controlSize = .small
        runSpinner.translatesAutoresizingMaskIntoConstraints = false
        runBlockMap.translatesAutoresizingMaskIntoConstraints = false
        runBlockMap.heightAnchor.constraint(equalToConstant: 132).isActive = true

        runPauseBtn = FancyButton("Pause", kind: .ghost, target: self, action: #selector(pauseRun))
        runResumeBtn = FancyButton("Resume", kind: .ghost, target: self, action: #selector(resumeRun))
        runStopBtn = FancyButton("Stop", kind: .danger, target: self, action: #selector(stopRun))

        let statsRow = UI.hstack([runWrittenTile, runSpeedTile, runElapsedTile, runRemainingTile], spacing: 28, alignment: .top)

        runningView = UI.vstack([
            runTitle,
            UI.hstack([runSpinner, runStage], spacing: 8),
            runPercent,
            runCaption,
            runBlockMap,
            legendRow(),
            statsRow,
            UI.hstack([runPauseBtn, runResumeBtn, runStopBtn], spacing: 10),
        ], spacing: 10)
    }
    // Stat tiles as stored views so we can update them.
    private lazy var runWrittenTile = statTile("Written", "—")
    private lazy var runSpeedTile = statTile("Current speed", "—")
    private lazy var runElapsedTile = statTile("Elapsed", "—")
    private lazy var runRemainingTile = statTile("Est. remaining", "—")

    private func legendRow() -> NSView {
        func chip(_ c: NSColor, _ t: String) -> NSView {
            let dot = NSView(); dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true; dot.layer?.backgroundColor = c.cgColor; dot.layer?.cornerRadius = 3
            dot.widthAnchor.constraint(equalToConstant: 12).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 12).isActive = true
            return UI.hstack([dot, UI.label(t, size: 11, color: .secondaryLabelColor)], spacing: 6)
        }
        return UI.hstack([chip(Palette.blue, "Written"), chip(Palette.tileOff, "Pending"), chip(Palette.amber, "Reserve (kept free)")], spacing: 16)
    }

    private func beginRun(title: String, accent: NSColor, isTest: Bool) {
        runTitle.stringValue = title
        runTitle.textColor = accent
        runStage.stringValue = "Preparing…"
        runStage.textColor = accent
        runPercent.stringValue = "0%"
        runBlockMap.configure(accent: accent)
        runBlockMap.update(fraction: 0, reserveFraction: mapReserveFraction)
        runSpinner.startAnimation(nil)
        runPauseBtn.isHidden = isTest
        runResumeBtn.isHidden = isTest
        runStopBtn.title = isTest ? "Stop & Clean Up" : "Stop"
        setTile(runWrittenTile, key: "Written", value: "—")
        setTile(runSpeedTile, key: "Current speed", value: "—")
        setTile(runElapsedTile, key: "Elapsed", value: "00:00")
        setTile(runRemainingTile, key: "Est. remaining", value: "Calculating…")
        setSteps(isTest ? testSteps : wipeSteps, isTest ? 2 : 3)
        sleepAssertion.begin(reason: "Overwriting free space")
        if let rv = runningView { host(rv) }
    }

    @objc private func pauseRun() { wiper.requestPause() }
    @objc private func resumeRun() { wiper.requestResume() }
    @objc private func stopRun() {
        if activeRunIsTest { wiper.requestCancel(); return }
        let a = NSAlert(); a.messageText = "Stop the overwrite?"
        a.informativeText = "The app stops writing and cleans up its temporary files. Your existing files are untouched."
        a.addButton(withTitle: "Stop"); a.addButton(withTitle: "Keep Going")
        if a.runModal() == .alertFirstButtonReturn { wiper.requestCancel() }
    }

    // MARK: - FreeSpaceWiperDelegate

    func wiperDidUpdate(progress p: WipeProgress) {
        let stage = stageText(p)
        runStage.stringValue = stage
        let frac = plannedTotalBytes > 0 ? min(1.0, Double(p.logicalBytesWritten) / Double(plannedTotalBytes)) : 0
        runPercent.stringValue = "\(Int(frac * 100))%"
        runBlockMap.update(fraction: CGFloat(frac), reserveFraction: mapReserveFraction)
        DockProgress.set(percent: Int(frac * 100))
        if activeRunIsTest {
            runCaption.stringValue = "Writing into free space — \(decMB(p.logicalBytesWritten)) of \(currentTestSize.shortLabel)   ·   each block ≈ a slice of the test"
            setTile(runWrittenTile, key: "Written", value: "\(decMB(p.logicalBytesWritten)) / \(currentTestSize.shortLabel)")
            setTile(runSpeedTile, key: "Current speed", value: decRate(p.throughputBytesPerSec))
        } else {
            runCaption.stringValue = "\(ByteText.format(p.logicalBytesWritten)) of ~\(ByteText.format(plannedTotalBytes)) free space overwritten   ·   \(ByteText.format(p.freeBytesRemaining)) free remaining"
            setTile(runWrittenTile, key: "Written", value: ByteText.format(p.logicalBytesWritten))
            setTile(runSpeedTile, key: "Current speed", value: ByteText.rate(p.throughputBytesPerSec))
        }
        setTile(runElapsedTile, key: "Elapsed", value: ByteText.duration(p.elapsed))
        if p.phase == .writing {
            setTile(runRemainingTile, key: "Est. remaining", value: p.estimatedRemaining == nil ? "Calculating…" : ByteText.duration(p.estimatedRemaining))
        } else {
            setTile(runRemainingTile, key: "Est. remaining", value: "—")
        }
    }

    func wiperDidLog(_ line: String) { /* visible in the report; not shown on the guided screen */ }

    func wiperDidFinish(result: WipeResult) {
        lastResult = result
        runSpinner.stopAnimation(nil)
        sleepAssertion.end()
        DockProgress.set(percent: nil)
        Notifier.finished(success: result.isTest ? result.testPassed : (result.status == .completedWithLimitations))
        if result.isTest { showTestResult(result) } else { showWipeResult(result) }
    }

    // MARK: - RESULT screens

    private func showTestResult(_ r: WipeResult) {
        setSteps(testSteps, 3)
        let passed = r.testPassed
        if r.cancelled { recordTest(r) } else { recordTest(r) }

        let mark = IconChip(r.cancelled ? "■" : (passed ? "✓" : "⚠"),
                            tint: r.cancelled ? Palette.amber : (passed ? Palette.green : Palette.red), size: 62)
        let bigText = r.cancelled ? "Test stopped safely" : (passed ? "\(currentTestSize.shortLabel) TEST PASSED" : "TEST DID NOT COMPLETE")
        let big = UI.label(bigText, size: 22, bold: true, color: r.cancelled ? Palette.amber : (passed ? Palette.green : Palette.red))
        var rows: [NSView] = [UI.hstack([mark, big], spacing: 14)]
        if r.cancelled {
            rows.append(UI.multiline("Test stopped. Temporary files cleaned up: \(r.cleanupVerified ? "yes" : "needs check"). Session files remaining: \(r.leftoverFiles.count)."))
        } else if !passed {
            rows.append(UI.multiline("Failing stage: \(r.failingStage ?? "unknown").", color: Palette.red))
        }
        rows.append(card(resultDetails(r)))

        var nav: [NSView] = [FancyButton("Back to Home", kind: .ghost, target: self, action: #selector(goHomeAction))]
        if passed {
            switch currentTestSize {
            case .mb100: nav.append(FancyButton("Run 1 GB Test", kind: .ghost, target: self, action: #selector(next1GB)))
            case .gb1:   nav.append(FancyButton("Run 10 GB Test", kind: .ghost, target: self, action: #selector(next10GB)))
            case .gb10:  nav.append(FancyButton("Proceed to Wipe →", kind: .primary, target: self, action: #selector(goWipeAction)))
            }
        } else if !r.cancelled {
            nav.append(FancyButton("Clean Up Test Files", kind: .ghost, target: self, action: #selector(goAdvancedAction)))
        }
        rows.append(UI.hstack(nav, spacing: 10))
        host(UI.vstack(rows, spacing: 14))
    }
    @objc private func next1GB() { selectedTestSize = .gb1; goTestConfirm() }
    @objc private func next10GB() { selectedTestSize = .gb10; goTestConfirm() }

    private func showWipeResult(_ r: WipeResult) {
        setSteps(wipeSteps, 4)
        let ok = r.status == .completedWithLimitations && !r.cancelled
        let mark = IconChip(r.cancelled ? "■" : "✓", tint: r.cancelled ? Palette.amber : Palette.green, size: 62)
        let big = UI.label(r.cancelled ? "Wipe stopped safely" : "FREE-SPACE OVERWRITE COMPLETE",
                           size: 20, bold: true, color: r.cancelled ? Palette.amber : Palette.green)
        let subtitle = UI.multiline(ok ? "Completed with limitations (see report). Not a certified erase." : "Finished: \(r.status.displayName). See report for details.")
        let details = card(UI.vstack([
            kv("Data written", ByteText.format(r.totalLogicalBytesWritten)),
            kv("Physical consumed", ByteText.format(r.totalPhysicalBytesConsumed)),
            kv("Cleanup", r.cleanupVerified ? "Complete (verified)" : (r.cleanupSucceeded ? "Complete" : "Incomplete")),
            kv("Snapshots present", (lastRecovery?.snapshotState ?? selectedVolume?.snapshotState ?? .unknown).label),
            kv("Your files modified", "No"),
        ], spacing: 8))
        let nav = UI.hstack([FancyButton("Back to Home", kind: .ghost, target: self, action: #selector(goHomeAction)),
                             FancyButton("View Diagnostics", kind: .ghost, target: self, action: #selector(goAdvancedAction)),
                             FancyButton("Save Report…", kind: .primary, target: self, action: #selector(saveReportHTML))], spacing: 10)
        host(UI.vstack([UI.hstack([mark, big], spacing: 14), subtitle, details, nav], spacing: 14))
    }

    private func resultDetails(_ r: WipeResult) -> NSView {
        UI.vstack([
            kv("Target write", r.configuredMaxWriteBytes != nil ? decMB(r.configuredMaxWriteBytes!) : "—"),
            kv("Actual payload written", decMB(r.totalLogicalBytesWritten)),
            kv("Write completed", r.reachedTarget ? "Yes" : "No"),
            kv("Flush completed", r.flushCompleted ? "Yes" : "No"),
            kv("Temporary files removed", r.cleanupSucceeded ? "Yes" : "No"),
            kv("Cleanup verified", r.cleanupVerified ? "Yes" : "No"),
            kv("Average write speed", decRate(r.averageThroughput)),
            kv("Elapsed", ByteText.duration(r.finishedAt.timeIntervalSince(r.startedAt))),
            kv("Your files modified", "No"),
        ], spacing: 8)
    }

    private func recordTest(_ r: WipeResult) {
        guard r.isTest, !r.cancelled else { return }
        TestHistory.shared.record(currentTestSize, outcome: TestOutcome(passed: r.testPassed, date: Date(),
                                     averageThroughput: r.averageThroughput, bytesWritten: r.totalLogicalBytesWritten))
    }

    // MARK: - ADVANCED

    @objc private func goAdvancedAction() { goAdvanced() }
    func goAdvanced() {
        setSteps(nil, 0)
        let heading = UI.title("Advanced")
        let sub = UI.multiline("The occasional-use extras, kept off the main path.")
        let items: [(String, String, String, Selector)] = [
            ("📄", "Save report", "Save the JSON / HTML report of the last operation.", #selector(saveReportHTML)),
            ("🔍", "Diagnostics & recovery check", "Snapshots, encryption, free-vs-available gap, logical read-back verification.", #selector(runDiagnostics)),
            ("🧯", "Clean up leftover files", "Find and remove any app-owned files from an interrupted run.", #selector(cleanupStale)),
            ("⚡️", "Open Energy settings", "Open macOS energy/battery settings so you can adjust sleep yourself.", #selector(openEnergy)),
            ("ℹ️", "About & honest limitations", "What this tool can and cannot guarantee.", #selector(showAbout)),
        ]
        var rows: [NSView] = [heading, sub]
        for (g, t, d, sel) in items {
            let b = FancyButton("", kind: .ghost, target: self, action: sel)
            b.isHidden = true // we use a custom row instead
            rows.append(advRow(glyph: g, title: t, desc: d, action: sel))
        }
        rows.append(FancyButton("Back to Home", kind: .ghost, target: self, action: #selector(goHomeAction)))
        host(UI.vstack(rows, spacing: 10))
    }

    @objc private func runDiagnostics() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        let d = recovery.diagnostics(mountPath: v.mountPath)
        if lastRecovery == nil { lastRecovery = emptyRecovery() }
        lastRecovery?.snapshotState = d.snapshot
        lastRecovery?.encryptionState = d.encryption
        lastRecovery?.freeVsAvailableDiscrepancyBytes = d.discrepancy
        lastRecovery?.diagnosticsNote = d.note
        let heading = UI.title("Diagnostics")
        let body = card(UI.vstack([
            kv("Snapshots", d.snapshot.label),
            kv("Encryption", d.encryption.label),
            kv("Free/available gap", ByteText.format(d.discrepancy)),
        ], spacing: 8))
        let note = UI.multiline(d.note.isEmpty ? "No snapshots detected; no significant free/available discrepancy." : d.note, size: 12)
        let verifyBtn = FancyButton("Run Layer A read-back verification (writes a small sample)", kind: .ghost, target: self, action: #selector(runLayerA))
        host(UI.vstack([heading, body, note, verifyBtn,
                        FancyButton("Back", kind: .ghost, target: self, action: #selector(goAdvancedAction))], spacing: 12))
    }
    @objc private func runLayerA() {
        guard let v = selectedVolume else { return }
        let r = recovery.runLogicalVerification(mountPath: v.mountPath, reserveBytes: currentReserveBytes())
        if lastRecovery == nil { lastRecovery = emptyRecovery() }
        lastRecovery?.layerA_ran = true; lastRecovery?.layerA_bytesVerified = r.bytesVerified
        lastRecovery?.layerA_mismatches = r.mismatches; lastRecovery?.layerA_note = r.note
        alert("Layer A verification", r.note)
    }
    @objc func cleanupStale() {
        var parents = Set<String>([NSHomeDirectory()])
        for v in volumes where !v.isReadOnly { if let p = try? sessions.writableParent(forMountPath: v.mountPath) { parents.insert(p) } }
        let stale = sessions.findStaleSessions(parents: Array(parents)).filter { !$0.isOwnerProcessAlive }
        if stale.isEmpty { alert("No leftover files", "No app-owned leftover sessions were found."); return }
        let total = stale.reduce(Int64(0)) { $0 + $1.totalBytes }
        let a = NSAlert(); a.messageText = "Clean up leftover files"
        a.informativeText = "\(stale.count) app-owned session(s) totalling \(ByteText.format(total)) can be safely removed."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { for s in stale { _ = sessions.removeSession(directory: s.directory) } ; alert("Done", "Cleanup complete.") }
    }
    @objc private func openEnergy() { PowerInfo.openEnergySettings() }
    @objc func showAbout() { AboutPanel.show() }
    @objc func showHelp() { HelpWindowController.shared.present() }
    @objc func showPreferences() { PreferencesWindowController.shared.present() }

    @objc func saveReportHTML() { saveReport(json: false) }
    @objc func saveReportJSON() { saveReport(json: true) }
    @objc func goTestSizeAction() { goTestSize() }
    private func saveReport(json: Bool) {
        guard let v = selectedVolume, let result = lastResult else { alert("Nothing to save", "Run a test or wipe first."); return }
        let cfg = WipeConfiguration(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID,
                                    expectedVolumeName: v.name, mode: result.mode, reserveBytes: result.reserveBytes)
        let report = reporter.buildReport(volume: v, config: cfg, result: result, recovery: lastRecovery)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = json ? "FusionFreeSpaceWiper-Report.json" : "FusionFreeSpaceWiper-Report.html"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self = self else { return }
            do { if json { try self.reporter.jsonData(report).write(to: url) }
                 else { try self.reporter.htmlString(report).data(using: .utf8)?.write(to: url) } }
            catch { self.alert("Save failed", "\(error)") }
        }
    }

    // MARK: - Launch-time stale prompt

    func promptStaleSessionsAtLaunch() {
        var parents = Set<String>([NSHomeDirectory()])
        for v in inspector.mountedVolumes() where !v.isReadOnly { if let p = try? sessions.writableParent(forMountPath: v.mountPath) { parents.insert(p) } }
        let stale = sessions.findStaleSessions(parents: Array(parents)).filter { !$0.isOwnerProcessAlive }
        guard !stale.isEmpty else { return }
        let total = stale.reduce(Int64(0)) { $0 + $1.totalBytes }
        let a = NSAlert(); a.messageText = "Leftover temporary files found"
        a.informativeText = "A previous session appears to have been interrupted. \(stale.count) app-owned session(s) totalling \(ByteText.format(total)) can be safely removed."
        a.addButton(withTitle: "Remove Now"); a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { for s in stale { _ = sessions.removeSession(directory: s.directory) } }
    }

    // MARK: - Helpers

    private func reloadVolumes() {
        volumes = inspector.mountedVolumes().filter { $0.isBrowsable }
        if selectedVolume == nil || !volumes.contains(where: { $0.mountPath == selectedVolume?.mountPath }) {
            if var v = volumes.first(where: { $0.mountPath == "/" }) ?? volumes.first {
                inspector.enrichDiagnostics(&v); selectedVolume = v; applyRecommendedReserve(for: v)
            }
        }
    }
    private func applyRecommendedReserve(for v: VolumeInfo) {
        if prefs.defaultReserveGiB > 0 { reserveGiB = max(10, prefs.defaultReserveGiB) }
        else { reserveGiB = Double(ReservePolicy.recommendedReserve(totalCapacity: v.totalCapacity)) / Double(Bytes.GiB) }
    }
    private func captureReserveFromField() {
        if let f = (scroll.documentView?.subviews.first?.subviews.compactMap { $0 as? NSTextField }.first(where: { $0.identifier?.rawValue == "reserveField" })) {
            reserveGiB = max(10, Double(f.stringValue) ?? reserveGiB)
        }
    }
    private func currentReserveBytes() -> Int64 { ReservePolicy.clamp(Int64(reserveGiB * Double(Bytes.GiB))) }

    private func preRunPowerChecksPass() -> Bool {
        // Laptop lid caveat + battery warning, declared upfront.
        let onBattery = PowerInfo.current() == .battery
        let laptop = PowerInfo.hasBattery()
        guard onBattery || laptop else { return true }
        let a = NSAlert()
        if onBattery {
            a.messageText = "Running on battery"
            a.informativeText = "This can take a while and uses a lot of disk activity. Plug into power before continuing.\n\nNote: this is a laptop — closing the lid will put it to sleep and interrupt the run (including its cleanup). Keep the lid open."
            a.alertStyle = .warning
        } else {
            a.messageText = "This looks like a laptop"
            a.informativeText = "Closing the lid will put the Mac to sleep and interrupt the run (including its cleanup). Keep the lid open and stay on power. The app keeps the Mac awake while running, but cannot override a closed lid."
            a.alertStyle = .informational
        }
        a.addButton(withTitle: "Continue"); a.addButton(withTitle: "Open Energy Settings…"); a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: PowerInfo.openEnergySettings(); return false
        default: return false
        }
    }

    private func wipeModeDesc(_ m: WipeMode) -> String {
        switch m {
        case .zeroSinglePass:   return "Fast, low wear. Fills free space once with zeros. (Default)"
        case .randomSinglePass: return "Avoids any chance the filesystem skips writing zero blocks."
        case .threePass:        return "Zeros, then ones, then random. More time & wear, no extra guarantee."
        }
    }

    private func kv(_ k: String, _ v: String) -> NSView {
        let kl = UI.label(k, size: 13, color: .secondaryLabelColor)
        let vl = UI.label(v, size: 13, bold: true)
        let row = UI.hstack([kl, NSView(), vl], spacing: 12)
        return row
    }
    private func card(_ content: NSView, padding: CGFloat = 16) -> NSView {
        let c = CardView(padding: padding)
        content.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: c.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -padding),
        ])
        return c
    }
    private func choiceCard(glyph: String, tint: NSColor, recommended: Bool, title: String, desc: String,
                            go: String, goColor: NSColor, action: Selector, lockNote: String? = nil) -> NSView {
        let chip = IconChip(glyph, tint: tint)
        let ttl = UI.label(title, size: 16, bold: true)
        let rec = recommended ? UI.label("  RECOMMENDED", size: 10, bold: true, color: tint) : NSView() as NSView
        let titleRow = UI.hstack([ttl, rec], spacing: 6)
        let d = UI.multiline(desc, size: 12, maxWidth: 360)
        var items: [NSView] = [chip, titleRow, d]
        if let note = lockNote { items.append(UI.label(note, size: 11, color: Palette.amber)) }
        let goLabel = UI.label(go, size: 13, bold: true, color: goColor)
        items.append(goLabel)
        let inner = UI.vstack(items, spacing: 10)
        let c = card(inner, padding: 18)
        let click = NSClickGestureRecognizer(target: self, action: action)
        c.addGestureRecognizer(click)
        return c
    }
    private func optionRow(title: String, desc: String, selected: Bool, action: Selector, tag: Int) -> NSView {
        let b = FancyButton("\(selected ? "●" : "○")  \(title)", kind: .ghost, target: self, action: action)
        b.tag = tag; b.toolTip = desc
        let d = UI.multiline(desc, size: 11, maxWidth: 620)
        return UI.vstack([b, d], spacing: 3)
    }
    private func advRow(glyph: String, title: String, desc: String, action: Selector) -> NSView {
        let chip = IconChip(glyph, tint: Palette.blue, size: 40)
        let t = UI.label(title, size: 14, bold: true)
        let d = UI.multiline(desc, size: 11, maxWidth: 520)
        let text = UI.vstack([t, d], spacing: 2)
        let row = UI.hstack([chip, text], spacing: 13)
        let c = card(row, padding: 14)
        c.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: action))
        return c
    }

    private func stageText(_ p: WipeProgress) -> String {
        if !p.note.isEmpty { return p.note }
        switch p.phase {
        case .preparing: return "Preparing…"
        case .writing: return activeRunIsTest ? "Writing test data…" : "Overwriting free space…"
        case .flushing: return "Flushing data…"
        case .verifying: return "Verifying…"
        case .cleaningUp: return "Cleaning up…"
        case .finished: return "Complete."
        case .cancelled: return "Stopped."
        default: return ""
        }
    }
    private func decMB(_ bytes: Int64) -> String {
        if bytes >= DecimalBytes.GB { return String(format: "%.2f GB", Double(bytes)/Double(DecimalBytes.GB)) }
        return String(format: "%.1f MB", Double(bytes)/Double(DecimalBytes.MB))
    }
    private func decRate(_ bps: Double) -> String { bps <= 0 ? "—" : String(format: "%.0f MB/s", bps/Double(DecimalBytes.MB)) }
    private func emptyRecovery() -> RecoveryTestReport {
        RecoveryTestReport(layerA_ran: false, layerA_bytesVerified: 0, layerA_mismatches: 0, layerA_note: "Not run.",
                           layerB_available: false, layerB_note: "Not run.", snapshotState: .unknown,
                           encryptionState: .unknown, freeVsAvailableDiscrepancyBytes: 0, diagnosticsNote: "")
    }
    private func noVolumeAlert() { alert("No disk selected", "Choose a disk from Home → Change disk.") }
    private func alert(_ title: String, _ text: String) { let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal() }

    func windowWillClose(_ notification: Notification) { wiper.requestCancel(); sleepAssertion.end(); DockProgress.set(percent: nil) }
}
