//
//  MainWindowController.swift
//  Fusion Free Space Wiper 2.0  (REDESIGN-SPEC implementation)
//
//  Left sidebar (Clean · Check · Recover) + global disk card; white main area with
//  per-flow step headers and footer actions. Plain AppKit, light/Aqua only.
//  Engines are unchanged; all changes here are display-side (§6).
//

import AppKit

final class MainWindowController: NSWindowController, FreeSpaceWiperDelegate, NSWindowDelegate {

    // Engines / services
    private let inspector = VolumeInspector()
    private let sessions = SessionManager()
    private let recovery = RecoveryTester()
    private let reporter = ReportWriter()
    private let wiper = FreeSpaceWiper()
    private let photorec = PhotoRecRunner()
    private let testdisk = TestDiskRunner()
    private let sleepAssertion = SleepAssertion()
    private let prefs = PreferencesStore.shared

    // State
    private enum Tool { case clean, check, recover }
    private var tool: Tool = .clean
    private var volumes: [VolumeInfo] = []
    private var selectedVolume: VolumeInfo?
    private var selectedTestSize: TestSize = .mb100
    private var selectedWipeMode: WipeMode = .zeroSinglePass
    private var reserveGB: Double = 20
    private var wipeChecks = [false, false, false, false]
    private var confirmTyped = ""
    private var lastResult: WipeResult?
    private var lastRecovery: RecoveryTestReport?
    private var plannedTotalBytes: Int64 = 0
    private var mapReserveFraction: CGFloat = 0
    private var activeRunIsTest = false
    private var currentTestSize: TestSize = .mb100
    private var isRunning = false
    private var isPaused = false

    // PhotoRec state
    private var auditDestination: String?
    private var auditImagePath: String?
    private var auditRunning = false

    // Chrome
    private let mainScroll = NSScrollView()
    private var rowClean: SidebarRow!
    private var rowCheck: SidebarRow!
    private var rowRecover: SidebarRow!
    private let diskNameLabel = NSTextField(labelWithString: "—")
    private let diskFreeLabel = NSTextField(labelWithString: "—")
    private let diskBar = DiskBarView()
    private let diskBadgeHost = NSView()

    // Running dashboard refs
    private var runTitleLabel = NSTextField(labelWithString: "")
    private var runEyebrow = NSTextField(labelWithString: "")
    private let runStageRow = StageRowView()
    private var runPct = NSTextField(labelWithString: "0%")
    private var runEta = NSTextField(labelWithString: "—")
    private var runCaption = NSTextField(labelWithString: "")
    private let runBlockMap = BlockMapView()
    private var runSpeed = NSTextField(labelWithString: "—")
    private var runElapsed = NSTextField(labelWithString: "—")
    private var pauseResumeBtn: PillButton!

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Fusion Free Space Wiper"
        window.minSize = NSSize(width: 1040, height: 720)
        self.init(window: window)
        window.delegate = self
        wiper.delegate = self
        buildChrome()
        window.center()
        reloadVolumes()
        selectTool(.clean)
    }

    // MARK: - Chrome: sidebar + main

    private func buildChrome() {
        guard let window = window else { return }
        let content = NSView(); content.wantsLayer = true
        content.layer?.backgroundColor = Tok.white.cgColor

        let sidebar = buildSidebar()
        mainScroll.hasVerticalScroller = true; mainScroll.drawsBackground = false
        mainScroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(sidebar); content.addSubview(mainScroll)
        window.contentView = content
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 256),
            mainScroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            mainScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainScroll.topAnchor.constraint(equalTo: content.topAnchor),
            mainScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func buildSidebar() -> NSView {
        let bar = NSView(); bar.translatesAutoresizingMaskIntoConstraints = false; bar.wantsLayer = true
        bar.layer?.backgroundColor = Tok.surface.cgColor
        let border = NSView(); border.translatesAutoresizingMaskIntoConstraints = false; border.wantsLayer = true
        border.layer?.backgroundColor = Tok.hairline.cgColor
        bar.addSubview(border)

        let appName = UI.text("Fusion", Ty.f(18, .bold), Tok.ink)
        let appSub = UI.text("Free Space Wiper", Ty.caption, Tok.steel)
        let brand = UI.vstack([appName, appSub], spacing: 1)

        let workflow = UI.eyebrow("Workflow")
        rowClean = SidebarRow(number: 1, title: "Clean", subtitle: "Overwrite free space", target: self, action: #selector(tapClean))
        rowCheck = SidebarRow(number: 2, title: "Check", subtitle: "What's recoverable · PhotoRec", target: self, action: #selector(tapCheck))
        rowRecover = SidebarRow(number: 3, title: "Recover", subtitle: "Partitions · TestDisk", target: self, action: #selector(tapRecover))

        diskNameLabel.font = Ty.f(14, .semibold); diskNameLabel.textColor = Tok.ink
        diskFreeLabel.font = Ty.caption; diskFreeLabel.textColor = Tok.steel
        diskBar.translatesAutoresizingMaskIntoConstraints = false
        diskBar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        diskBadgeHost.translatesAutoresizingMaskIntoConstraints = false
        let changeLink = PillButton("Change disk", style: .link, target: self, action: #selector(pickDisk))
        let diskInner = UI.vstack([UI.eyebrow("Disk"), diskNameLabel, diskBar, diskFreeLabel, diskBadgeHost, changeLink], spacing: 6)
        let diskCard = makeCard(diskInner, padding: 14)
        diskCard.layer?.backgroundColor = Tok.white.cgColor

        let reportsLink = PillButton("Reports & diagnostics", style: .link, target: self, action: #selector(goReports))
        let helpLink = PillButton("Help", style: .link, target: self, action: #selector(menuHelp))

        let top = UI.vstack([brand, workflow, rowClean, rowCheck, rowRecover], spacing: 10)
        [rowClean, rowCheck, rowRecover].forEach { $0.widthAnchor.constraint(equalToConstant: 224).isActive = true }
        diskCard.widthAnchor.constraint(equalToConstant: 224).isActive = true

        bar.addSubview(top); bar.addSubview(diskCard)
        let footer = UI.vstack([reportsLink, helpLink], spacing: 4); bar.addSubview(footer)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: bar.topAnchor), border.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: bar.trailingAnchor), border.widthAnchor.constraint(equalToConstant: 1),
            top.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            top.topAnchor.constraint(equalTo: bar.topAnchor, constant: 22),
            footer.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            footer.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -18),
            diskCard.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            diskCard.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),
        ])
        return bar
    }

    private func show(_ content: NSView) {
        let flipped = FlippedView(); flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: flipped.leadingAnchor, constant: 40),
            content.trailingAnchor.constraint(equalTo: flipped.trailingAnchor, constant: -40),
            content.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 30),
            content.bottomAnchor.constraint(lessThanOrEqualTo: flipped.bottomAnchor, constant: -30),
        ])
        mainScroll.documentView = flipped
        flipped.widthAnchor.constraint(equalTo: mainScroll.widthAnchor).isActive = true
        mainScroll.documentView?.scroll(.zero)
    }

    private func footerBar(_ views: [NSView]) -> NSView {
        let line = NSView(); line.translatesAutoresizingMaskIntoConstraints = false; line.wantsLayer = true
        line.layer?.backgroundColor = Tok.hairline.cgColor; line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let row = UI.hstack([UI.spacer()] + views, spacing: 12)
        return UI.vstack([line, row], spacing: 16)
    }

    // MARK: - Tool switching

    @objc private func tapClean() { if !lockedDuringRun() { selectTool(.clean) } }
    @objc private func tapCheck() { if !lockedDuringRun() { selectTool(.check) } }
    @objc private func tapRecover() { if !lockedDuringRun() { selectTool(.recover) } }
    private func lockedDuringRun() -> Bool { isRunning }

    private func selectTool(_ t: Tool) {
        tool = t
        rowClean.setSelected(t == .clean); rowCheck.setSelected(t == .check); rowRecover.setSelected(t == .recover)
        switch t { case .clean: cleanHome(); case .check: checkSetup(); case .recover: recoverHome() }
    }

    private func updateSidebarLock() { rowCheck.isEnabled = !isRunning; rowRecover.isEnabled = !isRunning }

    private func refreshDiskCard() {
        guard let v = selectedVolume else { return }
        diskNameLabel.stringValue = v.name
        diskFreeLabel.stringValue = "\(UI.gb(v.freeCapacityRaw)) free of \(UI.gb(v.totalCapacity))"
        let used = Double(v.totalCapacity - v.freeCapacityRaw), rsv = Double(reserveBytes()), free = Double(v.freeCapacityRaw)
        diskBar.set(filesFrac: CGFloat(used), overwriteFrac: CGFloat(max(0, free - rsv)), reserveFrac: CGFloat(min(free, rsv)))
        diskBadgeHost.subviews.forEach { $0.removeFromSuperview() }
        let b: NSView
        if TestHistory.shared.quickTestPassed { b = badge("Tested · ready", fill: Tok.greenSoft, textColor: Tok.greenDark) }
        else if TestHistory.shared.quickTestFailed { b = badge("Test failed", fill: Tok.warningBg, textColor: Tok.warningText) }
        else { b = badge("Not tested", fill: Tok.warningBg, textColor: Tok.warningText) }
        b.translatesAutoresizingMaskIntoConstraints = false
        diskBadgeHost.addSubview(b)
        NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: diskBadgeHost.leadingAnchor),
            b.topAnchor.constraint(equalTo: diskBadgeHost.topAnchor), b.bottomAnchor.constraint(equalTo: diskBadgeHost.bottomAnchor),
            b.trailingAnchor.constraint(lessThanOrEqualTo: diskBadgeHost.trailingAnchor)])
    }

    // MARK: - CLEAN · Home (§4.1)

    private func cleanHome() {
        refreshDiskCard()
        let passed = TestHistory.shared.quickTestPassed
        let eyebrow = UI.eyebrow("1 · Clean")
        let heading = UI.homeHeading("Wipe deleted files from free space")
        let intro = UI.body("Overwrite the empty space on your disk so previously-deleted files are harder to recover. Your current files, apps and macOS are never touched.")

        let recTitle: String; let recBody: String; let primary: PillButton; let secondary: PillButton
        if passed {
            recTitle = "Your Mac is ready to wipe"
            let est = estimateText(forBytes: writableBytes())
            recBody = "Based on your test speed, a full wipe takes about \(est ?? "a while")."
            primary = PillButton("Set up wipe", style: .primary, target: self, action: #selector(goWipeAction))
            secondary = PillButton("Run a longer test", style: .link, target: self, action: #selector(goTestSizeAction))
        } else {
            recTitle = "Recommended next step: run a 100 MB safety test"
            recBody = "It exercises the real engine for ~30 seconds so you can trust a full wipe."
            primary = PillButton("Start safety test", style: .primary, target: self, action: #selector(startQuickTest))
            secondary = PillButton("Choose test size", style: .link, target: self, action: #selector(goTestSizeAction))
        }
        let recInner = UI.vstack([
            UI.text(recTitle, Ty.heading5, Tok.white),
            UI.text(recBody, Ty.bodySmall, Tok.onDarkMuted, maxWidth: 420),
            UI.hstack([primary, secondary], spacing: 12),
        ], spacing: 12)
        let recCard = makeCard(recInner, dark: true, padding: 24)

        let steps = [("100 MB test", passed),
                     ("Optional 1 GB / 10 GB", TestHistory.shared.outcome(.gb1)?.passed == true || TestHistory.shared.outcome(.gb10)?.passed == true),
                     ("Wipe free space", lastResult?.isTest == false && lastResult != nil),
                     ("Check again", false)]
        var checkViews: [NSView] = [UI.text("The safe path", Ty.f(13, .semibold), Tok.ink)]
        for (name, done) in steps {
            let mark = UI.text(done ? "✓" : "○", Ty.f(13, .bold), done ? Tok.greenDark : Tok.hairlineStrong)
            checkViews.append(UI.hstack([mark, UI.text(name, Ty.bodySmall, done ? Tok.ink : Tok.steel)], spacing: 8))
        }
        let pathCard = makeCard(UI.vstack(checkViews, spacing: 8), padding: 18)
        pathCard.layer?.backgroundColor = Tok.surface.cgColor
        let topRow = UI.hstack([recCard, pathCard], spacing: 16, alignment: .top)
        recCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true

        let wipeBadge = passed ? badge("Ready", fill: Tok.greenSoft, textColor: Tok.greenDark) : badgeWarning("Run the safety test first")
        let quietWipe = makeCard(UI.vstack([
            UI.hstack([UI.cardTitle("Wipe free space"), wipeBadge], spacing: 8),
            UI.small("Overwrite all free space except a safety reserve.", color: Tok.steel),
            PillButton("Set up wipe", style: .secondary, target: self, action: #selector(goWipeAction)),
        ], spacing: 10), padding: 18)
        let quietCheck = makeCard(UI.vstack([
            UI.cardTitle("Not sure what's recoverable?"),
            UI.small("Scan a disk to see what a recovery tool could still find.", color: Tok.steel),
            PillButton("Go to Check", style: .secondary, target: self, action: #selector(tapCheck)),
        ], spacing: 10), padding: 18)
        let quietRow = UI.hstack([quietWipe, quietCheck], spacing: 16, alignment: .top); quietRow.distribution = .fillEqually

        show(UI.vstack([eyebrow, heading, intro, topRow, quietRow], spacing: 20))
    }

    // MARK: - CLEAN · Test flow

    @objc func goTestSize() { selectedTestSize = prefs.defaultTestSize; testSizeScreen() }
    @objc private func goTestSizeAction() { selectTool(.clean); goTestSize() }
    @objc private func startQuickTest() { selectedTestSize = .mb100; startTest() }

    private var sizeCards: [RadioCard] = []
    private weak var runBtnRef: PillButton?
    private func testSizeScreen() {
        let header = flowHeader(back: ("Clean", self, #selector(backToCleanHome)), steps: ["Choose size", "Run", "Result"], active: 0)
        let eyebrow = UI.eyebrow("1 · Clean")
        let heading = UI.heading("Choose a safety test size")
        let intro = UI.body("Bigger tests exercise the engine longer and give a better read on write speed. Start with 100 MB.")
        sizeCards = []
        func mk(_ size: TestSize, _ title: String, _ desc: String, rec: Bool) -> RadioCard {
            let b = rec ? badgeRecommended() : nil
            let c = RadioCard(value: TestSize.allCases.firstIndex(of: size)!, title: title, desc: desc, badgeView: b, target: self, action: #selector(testSizeTapped(_:)))
            sizeCards.append(c); return c
        }
        let c1 = mk(.mb100, "100 MB · Quick test", "Fastest check that writing, progress and cleanup all work. ~30 sec.", rec: true)
        let c2 = mk(.gb1, "1 GB · Standard", "A longer run for a more meaningful speed and time estimate.", rec: false)
        let c3 = mk(.gb10, "10 GB · Extended", "Optional final rehearsal before a full wipe. Same code path, stopped at 10 GB.", rec: false)
        [c1,c2,c3].forEach { $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true }

        let whatInner = UI.vstack([
            UI.cardTitle("What will happen"),
            UI.small("1.  Write a small amount of temporary data into free space.", color: Tok.slate),
            UI.small("2.  Flush it and verify the exact amount written.", color: Tok.slate),
            UI.small("3.  Delete it and confirm the space is returned.", color: Tok.slate),
            UI.text("Your files are not modified.", Ty.f(13, .semibold), Tok.greenDark),
        ], spacing: 8)
        let whatCard = makeCard(whatInner, padding: 18); whatCard.layer?.backgroundColor = Tok.surface.cgColor

        let body = UI.hstack([UI.vstack([c1,c2,c3], spacing: 10), whatCard], spacing: 20, alignment: .top)
        let runBtn = PillButton("Run \(selectedTestSize.shortLabel) test", style: .primary, target: self, action: #selector(startTest))
        runBtnRef = runBtn
        let footer = footerBar([PillButton("Back", style: .secondary, target: self, action: #selector(backToCleanHome)), runBtn])
        updateSizeSelection()
        show(UI.vstack([header, eyebrow, heading, intro, body, footer], spacing: 18))
    }
    @objc private func testSizeTapped(_ sender: RadioCard) { selectedTestSize = TestSize.allCases[sender.value]; updateSizeSelection(); runBtnRef?.title = "Run \(selectedTestSize.shortLabel) test" }
    private func updateSizeSelection() { for c in sizeCards { c.setSelected(c.value == TestSize.allCases.firstIndex(of: selectedTestSize)) } }
    @objc private func backToCleanHome() { selectTool(.clean) }

    @objc func startTest() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        if !preRunPowerChecksPass() { return }
        let cfg = WipeConfiguration.test(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID,
                                         expectedVolumeName: v.name, reserveBytes: reserveBytes(), size: selectedTestSize)
        currentTestSize = selectedTestSize; activeRunIsTest = true
        plannedTotalBytes = selectedTestSize.bytes; mapReserveFraction = 0
        beginRun(isTest: true)
        wiper.start(config: cfg)
    }

    // MARK: - CLEAN · Wipe flow

    @objc func goWipeAction() {
        selectTool(.clean)
        if !TestHistory.shared.quickTestPassed {
            let a = NSAlert(); a.messageText = TestHistory.shared.quickTestFailed ? "The 100 MB test failed" : "Testing recommended"
            a.informativeText = TestHistory.shared.quickTestFailed ? "The last 100 MB test did not pass. Consider resolving that first." : "We recommend running at least the 100 MB test before a full wipe."
            a.alertStyle = TestHistory.shared.quickTestFailed ? .critical : .warning
            a.addButton(withTitle: "Go to test"); a.addButton(withTitle: "Proceed anyway"); a.addButton(withTitle: "Cancel")
            switch a.runModal() { case .alertFirstButtonReturn: goTestSize(); return; case .alertSecondButtonReturn: break; default: return }
        }
        wipeOptions()
    }

    private var modeCards: [RadioCard] = []
    private weak var reserveFieldRef: NSTextField?
    private weak var reserveBarRef: DiskBarView?
    private weak var reserveLegendRef: NSTextField?
    private func wipeOptions() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        let header = flowHeader(back: ("Clean", self, #selector(backToCleanHome)), steps: ["Options", "Confirm", "Run", "Result"], active: 0)
        let eyebrow = UI.eyebrow("1 · Clean")
        let heading = UI.heading("Wipe options")
        let intro = UI.body("A single zero pass is the sensible default. More passes add time and disk wear with no guarantee on SSD/Fusion.")
        modeCards = []
        func mk(_ m: WipeMode, _ title: String, _ desc: String, def: Bool) -> RadioCard {
            let c = RadioCard(value: WipeMode.allCases.firstIndex(of: m)!, title: title, desc: desc,
                              badgeView: def ? badge("Default", fill: Tok.greenSoft, textColor: Tok.greenDark) : nil,
                              target: self, action: #selector(modeTapped(_:)))
            modeCards.append(c); return c
        }
        let m1 = mk(.zeroSinglePass, "One pass · zeros", "Fast, low wear.", def: true)
        let m2 = mk(.randomSinglePass, "One pass · random", "Avoids any zero-block elision.", def: false)
        let m3 = mk(.threePass, "Three passes", "More time & wear, no extra guarantee.", def: false)
        let modeRow = UI.hstack([m1,m2,m3], spacing: 12, alignment: .top); modeRow.distribution = .fillEqually

        let field = NSTextField(string: String(format: "%.0f", reserveGB))
        field.translatesAutoresizingMaskIntoConstraints = false; field.widthAnchor.constraint(equalToConstant: 80).isActive = true
        field.target = self; field.action = #selector(reserveEdited(_:)); reserveFieldRef = field
        let reserveBar = DiskBarView(); reserveBar.translatesAutoresizingMaskIntoConstraints = false
        reserveBar.heightAnchor.constraint(equalToConstant: 22).isActive = true; reserveBarRef = reserveBar
        let legend = UI.small("", color: Tok.steel); reserveLegendRef = legend
        let reserveInner = UI.vstack([
            UI.cardTitle("Safety reserve"),
            UI.hstack([UI.body("Keep free", color: Tok.slate), field, UI.body("GB", color: Tok.slate)], spacing: 8),
            reserveBar, legend,
            UI.small("Never below 10 GB. The app re-checks space before every write and never fills the disk.", color: Tok.steel),
        ], spacing: 10)
        let reserveCard = makeCard(reserveInner, padding: 20); reserveCard.layer?.backgroundColor = Tok.surface.cgColor
        updateReserveBar()

        let footer = footerBar([PillButton("Back", style: .secondary, target: self, action: #selector(backToCleanHome)),
                                PillButton("Continue", style: .primary, target: self, action: #selector(goWipeConfirm))])
        updateModeSelection()
        _ = v
        show(UI.vstack([header, eyebrow, heading, intro, UI.text("Method", Ty.f(13, .semibold), Tok.slate), modeRow, reserveCard, footer], spacing: 18))
    }
    @objc private func modeTapped(_ s: RadioCard) { selectedWipeMode = WipeMode.allCases[s.value]; updateModeSelection() }
    private func updateModeSelection() { for c in modeCards { c.setSelected(c.value == WipeMode.allCases.firstIndex(of: selectedWipeMode)) } }
    @objc private func reserveEdited(_ s: NSTextField) { reserveGB = max(10, Double(s.stringValue) ?? reserveGB); updateReserveBar(); refreshDiskCard() }
    private func updateReserveBar() {
        guard let v = selectedVolume else { return }
        let used = Double(v.totalCapacity - v.freeCapacityRaw), free = Double(v.freeCapacityRaw), rsv = Double(reserveBytes())
        reserveBarRef?.set(filesFrac: CGFloat(used), overwriteFrac: CGFloat(max(0, free - rsv)), reserveFrac: CGFloat(min(free, rsv)))
        reserveLegendRef?.stringValue = "Your files \(UI.gb(v.totalCapacity - v.freeCapacityRaw)) (untouched)   ·   Will be overwritten \(UI.gb(Int64(max(0, free - rsv))))   ·   Reserve \(UI.gb(reserveBytes()))"
    }

    private var confirmField: NSTextField?
    private var confirmBoxes: [NSButton] = []
    private var overwriteBtnRef: PillButton?
    @objc private func goWipeConfirm() {
        guard let v = selectedVolume else { return }
        let header = flowHeader(back: ("Options", self, #selector(wipeOptionsBack)), steps: ["Options", "Confirm", "Run", "Result"], active: 1)
        let eyebrow = UI.eyebrow("1 · Clean")
        let heading = UI.heading("Confirm the wipe")
        confirmBoxes = []
        let items = ["I have a current backup.", "The Mac is plugged into power.", "No Time Machine or other disk-heavy task is running.", "I understand this is not a certified erase."]
        var checkViews: [NSView] = [UI.cardTitle("Before you start")]
        for (i, it) in items.enumerated() {
            let cb = NSButton(checkboxWithTitle: it, target: self, action: #selector(confirmBoxToggled))
            cb.state = wipeChecks[i] ? .on : .off; cb.tag = i; cb.translatesAutoresizingMaskIntoConstraints = false
            confirmBoxes.append(cb); checkViews.append(cb)
        }
        if v.snapshotState == .yes {
            checkViews.append(warningPanel(title: "APFS snapshots detected", body: "They can retain pieces of deleted files and are not removed by this app, so the wipe may be incomplete. See Reports & diagnostics."))
        }
        let typeField = NSTextField(string: ""); typeField.placeholderString = v.name
        typeField.translatesAutoresizingMaskIntoConstraints = false; typeField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        typeField.target = self; typeField.action = #selector(confirmTypedChanged(_:)); confirmField = typeField
        checkViews.append(UI.text("Type “\(v.name)” to confirm", Ty.f(13, .semibold), Tok.ink))
        checkViews.append(typeField)
        let leftCard = makeCard(UI.vstack(checkViews, spacing: 10), padding: 20)

        let est = estimateText(forBytes: writableBytes()) ?? "—"
        let summary = UI.vstack([
            UI.cardTitle("Summary"),
            kv("Disk", v.name), kv("Method", selectedWipeMode.displayName), kv("Overwrite size", UI.gb(writableBytes())),
            kv("Reserve", UI.gb(reserveBytes())), kv("Estimated time", est),
        ], spacing: 8)
        let rightCard = makeCard(summary, padding: 20); rightCard.layer?.backgroundColor = Tok.surface.cgColor
        let body = UI.hstack([leftCard, rightCard], spacing: 16, alignment: .top)

        let overwrite = PillButton("Overwrite free space", style: .orange, target: self, action: #selector(startWipe))
        overwriteBtnRef = overwrite
        let footer = footerBar([PillButton("Back", style: .secondary, target: self, action: #selector(wipeOptionsBack)), overwrite])
        show(UI.vstack([header, eyebrow, heading, body, footer], spacing: 18))
        updateOverwriteGate()
    }
    @objc private func wipeOptionsBack() { wipeOptions() }
    @objc private func confirmBoxToggled(_ s: NSButton) { if s.tag >= 0 && s.tag < 4 { wipeChecks[s.tag] = s.state.isOn }; updateOverwriteGate() }
    @objc private func confirmTypedChanged(_ s: NSTextField) { confirmTyped = s.stringValue; updateOverwriteGate() }
    private func updateOverwriteGate() {
        let allChecked = wipeChecks.allSatisfy { $0 }
        let nameOK = confirmTyped == (selectedVolume?.name ?? "\u{0}")
        overwriteBtnRef?.isEnabled = allChecked && nameOK
    }

    @objc func startWipe() {
        guard let v = selectedVolume else { return }
        if !preRunPowerChecksPass() { return }
        let cfg = WipeConfiguration(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID,
                                    expectedVolumeName: v.name, mode: selectedWipeMode, reserveBytes: reserveBytes())
        activeRunIsTest = false
        let writable = wiper.dryRun(config: cfg)?.writableBytes ?? writableBytes()
        plannedTotalBytes = max(1, writable)
        mapReserveFraction = CGFloat(Double(reserveBytes()) / Double(max(1, writable + reserveBytes())))
        beginRun(isTest: false)
        wiper.start(config: cfg)
    }

    // MARK: - Running dashboard (§4.3)

    private func beginRun(isTest: Bool) {
        isRunning = true; isPaused = false; updateSidebarLock()
        let steps = isTest ? ["Choose size", "Run", "Result"] : ["Options", "Confirm", "Run", "Result"]
        let active = isTest ? 1 : 2
        let header = flowHeader(back: nil, steps: steps, active: active)
        runEyebrow = UI.eyebrow(isTest ? "Step 2 of 3 · Run" : "Step 3 of 4 · Run")
        runTitleLabel = UI.text(isTest ? "Running \(currentTestSize.shortLabel) safety test" : "Wiping free space on \(selectedVolume?.name ?? "disk")", Ty.heading3, Tok.ink)

        pauseResumeBtn = PillButton("Pause", style: .secondary, target: self, action: #selector(togglePause))
        let stop = PillButton("Stop & clean up", style: .link, target: self, action: #selector(stopRun))
        stop.attributedTitle = NSAttributedString(string: "Stop & clean up", attributes: [.foregroundColor: Tok.orangeDark, .font: Ty.button])
        let controls: [NSView] = isTest ? [stop] : [pauseResumeBtn, stop]

        runPct = UI.text("0%", Ty.heroPct, Tok.white)
        runEta = UI.text("—", Ty.heroETA, Tok.white)
        runCaption = UI.text("", Ty.bodySmall, Tok.onDarkMuted, maxWidth: 560)
        runBlockMap.translatesAutoresizingMaskIntoConstraints = false
        runBlockMap.heightAnchor.constraint(equalToConstant: 150).isActive = true
        runBlockMap.update(fraction: 0, reserveFraction: mapReserveFraction)
        runStageRow.setCurrent(0)
        let heroL = UI.vstack([UI.text("Progress", Ty.eyebrow, Tok.onDarkMuted), runPct], spacing: 2)
        let heroR = UI.vstack([UI.text("Time remaining", Ty.eyebrow, Tok.onDarkMuted), runEta], spacing: 2); heroR.alignment = .trailing
        let hero = UI.hstack([heroL, UI.spacer(), heroR], spacing: 20, alignment: .top)
        let scaleNote = UI.text("Each tile ≈ a slice of free space, not a physical location.", Ty.caption, Tok.onDarkMuted)
        let panelInner = UI.vstack([runStageRow, hero, runCaption, runBlockMap, legendDark(), scaleNote], spacing: 14)
        let panel = makeCard(panelInner, dark: true, padding: 24)

        runSpeed = UI.text("—", Ty.f(17, .semibold), Tok.ink)
        runElapsed = UI.text("—", Ty.f(17, .semibold), Tok.ink)
        let stats = UI.hstack([statCard("Current speed", runSpeed), statCard("Elapsed", runElapsed), statCardText("Your files", "Untouched", Tok.greenDark)], spacing: 12, alignment: .top)
        stats.distribution = .fillEqually

        let titleRow = UI.hstack([UI.vstack([runEyebrow, runTitleLabel], spacing: 2), UI.spacer()] + controls, spacing: 12, alignment: .top)
        show(UI.vstack([header, titleRow, panel, stats], spacing: 18))
        sleepAssertion.begin(reason: "Overwriting free space")
        refreshDiskCard()
    }
    private func legendDark() -> NSView {
        func chip(_ c: NSColor, _ t: String) -> NSView {
            let d = NSView(); d.translatesAutoresizingMaskIntoConstraints = false; d.wantsLayer = true; d.layer?.backgroundColor = c.cgColor; d.layer?.cornerRadius = 3
            d.widthAnchor.constraint(equalToConstant: 11).isActive = true; d.heightAnchor.constraint(equalToConstant: 11).isActive = true
            return UI.hstack([d, UI.text(t, Ty.caption, Tok.onDarkMuted)], spacing: 6)
        }
        return UI.hstack([chip(Tok.green, "Overwritten"), chip(Tok.hairlineDark, "To do"), chip(Tok.onDarkMuted, "Reserve")], spacing: 16)
    }
    private func statCard(_ title: String, _ valueLabel: NSTextField) -> NSView {
        makeCard(UI.vstack([UI.text(title.uppercased(), Ty.eyebrow, Tok.steel), valueLabel], spacing: 4), padding: 14)
    }
    private func statCardText(_ title: String, _ value: String, _ color: NSColor) -> NSView {
        makeCard(UI.vstack([UI.text(title.uppercased(), Ty.eyebrow, Tok.steel), UI.text(value, Ty.f(17, .semibold), color)], spacing: 4), padding: 14)
    }

    @objc private func togglePause() {
        if isPaused { wiper.requestResume(); isPaused = false; pauseResumeBtn.title = "Pause" }
        else { wiper.requestPause(); isPaused = true; pauseResumeBtn.title = "Resume" }
    }
    @objc private func stopRun() {
        if activeRunIsTest { wiper.requestCancel(); return }
        let a = NSAlert(); a.messageText = "Stop the overwrite?"; a.informativeText = "The app stops writing and cleans up its temporary files. Your existing files are untouched."
        a.addButton(withTitle: "Stop"); a.addButton(withTitle: "Keep going")
        if a.runModal() == .alertFirstButtonReturn { wiper.requestCancel() }
    }

    // MARK: - Delegate

    func wiperDidUpdate(progress p: WipeProgress) {
        let frac = plannedTotalBytes > 0 ? min(1.0, Double(p.logicalBytesWritten)/Double(plannedTotalBytes)) : 0
        runPct.stringValue = "\(Int(frac*100))%"
        runBlockMap.update(fraction: CGFloat(frac), reserveFraction: mapReserveFraction)
        runStageRow.setCurrent(stageIndex(p.phase))
        if p.phase == .writing { runEta.stringValue = p.estimatedRemaining == nil ? "Calculating…" : hms(p.estimatedRemaining!) }
        else { runEta.stringValue = "—" }
        if activeRunIsTest {
            runCaption.stringValue = "\(UI.gb(p.logicalBytesWritten)) of \(currentTestSize.shortLabel) written"
        } else {
            runCaption.stringValue = "\(UI.gb(p.logicalBytesWritten)) of ~\(UI.gb(plannedTotalBytes)) overwritten · \(UI.gb(p.freeBytesRemaining)) free remaining"
        }
        runSpeed.stringValue = decRate(p.throughputBytesPerSec)
        runElapsed.stringValue = hms(p.elapsed)
        window?.title = "Fusion Free Space Wiper — \(activeRunIsTest ? "Testing" : "Wiping") \(Int(frac*100))%"
        DockProgress.set(percent: Int(frac*100))
    }
    func wiperDidLog(_ line: String) {}
    func wiperDidFinish(result: WipeResult) {
        lastResult = result; isRunning = false; isPaused = false
        sleepAssertion.end(); DockProgress.set(percent: nil); window?.title = "Fusion Free Space Wiper"
        updateSidebarLock(); refreshDiskCard()
        Notifier.finished(success: result.isTest ? result.testPassed : (result.status == .completedWithLimitations))
        if result.isTest { testResult(result) } else { wipeResult(result) }
    }
    private func stageIndex(_ ph: WipeProgress.Phase) -> Int {
        switch ph { case .preparing: return 0; case .writing: return 1; case .flushing: return 2; case .verifying: return 3; case .cleaningUp, .finished, .cancelled: return 4; default: return 0 }
    }

    // MARK: - Results

    private func testResult(_ r: WipeResult) {
        if r.isTest && !r.cancelled { TestHistory.shared.record(currentTestSize, outcome: TestOutcome(passed: r.testPassed, date: Date(), averageThroughput: r.averageThroughput, bytesWritten: r.totalLogicalBytesWritten)) }
        let header = flowHeader(back: nil, steps: ["Choose size", "Run", "Result"], active: 2)
        let passed = r.testPassed, cancelled = r.cancelled
        let markColor = cancelled ? Tok.warningText : (passed ? Tok.greenDark : Tok.warningText)
        let markText = cancelled ? "■" : (passed ? "✓" : "⚠")
        let title = cancelled ? "Test stopped safely" : (passed ? "\(currentTestSize.shortLabel) safety test passed" : "Test did not complete")
        let mark = UI.text(markText, Ty.f(40, .bold), markColor)
        let bigTitle = UI.text(title, Ty.heading3, markColor)
        let details = makeCard(UI.vstack([
            kv("Target write", UI.gb(r.configuredMaxWriteBytes ?? 0)), kv("Actual written", UI.gb(r.totalLogicalBytesWritten)),
            kv("Flush completed", r.flushCompleted ? "Yes" : "No"), kv("Temporary files removed", r.cleanupSucceeded ? "Yes" : "No"),
            kv("Cleanup verified", r.cleanupVerified ? "Yes" : "No"), kv("Average speed", decRate(r.averageThroughput)),
            kvColored("Your files modified", "No", Tok.greenDark),
        ], spacing: 8), padding: 20)

        var right: [NSView] = []
        if passed {
            let est = estimateText(forBytes: writableBytes()) ?? "a while"
            let recInner = UI.vstack([UI.text("Wipe free space", Ty.heading5, Tok.white),
                                      UI.text("Full wipe takes about \(est).", Ty.bodySmall, Tok.onDarkMuted),
                                      PillButton("Set up wipe", style: .primary, target: self, action: #selector(goWipeAction))], spacing: 10)
            right.append(makeCard(recInner, dark: true, padding: 20))
            let more = makeCard(UI.vstack([UI.cardTitle("Want more confidence?"),
                UI.hstack([PillButton("Run 1 GB", style: .secondary, target: self, action: #selector(run1GB)),
                           PillButton("Run 10 GB", style: .secondary, target: self, action: #selector(run10GB))], spacing: 8)], spacing: 10), padding: 18)
            right.append(more)
        } else if !cancelled {
            right.append(makeCard(UI.vstack([UI.cardTitle("Try again"), UI.small(r.failingStage ?? "", color: Tok.steel),
                PillButton("Try again", style: .primary, target: self, action: #selector(goTestSize))], spacing: 10), padding: 18))
        }
        let body = UI.hstack([details, UI.vstack(right, spacing: 14)], spacing: 16, alignment: .top)
        let footer = footerBar([PillButton("Save report…", style: .link, target: self, action: #selector(saveReportHTML)),
                                PillButton("Back to Clean", style: .secondary, target: self, action: #selector(backToCleanHome))])
        show(UI.vstack([header, UI.hstack([mark, bigTitle], spacing: 14), body, footer], spacing: 18))
    }
    @objc private func run1GB() { selectedTestSize = .gb1; startTest() }
    @objc private func run10GB() { selectedTestSize = .gb10; startTest() }

    private func wipeResult(_ r: WipeResult) {
        let header = flowHeader(back: nil, steps: ["Options", "Confirm", "Run", "Result"], active: 3)
        let ok = r.status == .completedWithLimitations && !r.cancelled
        let mark = UI.text(r.cancelled ? "■" : "✓", Ty.f(40, .bold), r.cancelled ? Tok.warningText : Tok.greenDark)
        let title = UI.text(r.cancelled ? "Wipe stopped safely" : "Free-space overwrite complete", Ty.heading3, r.cancelled ? Tok.warningText : Tok.greenDark)
        let sub = UI.body(ok ? "Completed with limitations (see report). Not a certified erase." : "Finished: \(r.status.displayName).")
        let details = makeCard(UI.vstack([
            kv("Data written", UI.gb(r.totalLogicalBytesWritten)), kv("Physical consumed", UI.gb(r.totalPhysicalBytesConsumed)),
            kv("Cleanup", r.cleanupVerified ? "Complete (verified)" : (r.cleanupSucceeded ? "Complete" : "Incomplete")),
            kv("Snapshots present", (lastRecovery?.snapshotState ?? selectedVolume?.snapshotState ?? .unknown).label),
            kvColored("Your files modified", "No", Tok.greenDark),
        ], spacing: 8), padding: 20)
        let recInner = UI.vstack([UI.text("Check what's left", Ty.heading5, Tok.white),
            UI.text("Scan the disk to see if anything is still recoverable.", Ty.bodySmall, Tok.onDarkMuted),
            PillButton("Go to Check", style: .primary, target: self, action: #selector(tapCheck))], spacing: 10)
        let recCard = makeCard(recInner, dark: true, padding: 20)
        let limits = limitsPanel(title: "What this can't tell you", body: "Free-space overwrite can't reach SSD/Fusion controller-hidden cells, and APFS snapshots can retain old data. A clean result is not proof of irrecoverability.")
        let footer = footerBar([PillButton("Save report…", style: .link, target: self, action: #selector(saveReportHTML)),
                                PillButton("Back to Clean", style: .secondary, target: self, action: #selector(backToCleanHome))])
        show(UI.vstack([header, UI.hstack([mark, title], spacing: 14), sub, UI.hstack([details, recCard], spacing: 16, alignment: .top), limits, footer], spacing: 18))
    }

    // MARK: - CHECK (§4.7 / §4.8)

    private let auditResultHost = NSView()
    private var auditStartBtn: PillButton?
    private func checkSetup() {
        refreshDiskCard()
        let eyebrow = UI.eyebrow("2 · Check")
        let heading = UI.homeHeading("See what's still recoverable")
        let intro = UI.body("Runs the bundled PhotoRec read-only and reconstructs any files it can find into a folder you choose — what someone attempting recovery would get.")
        let srcText = auditImagePath != nil ? "Image: \((auditImagePath! as NSString).lastPathComponent)" : "Disk: \(selectedVolume?.name ?? "—")"
        let scanCard = makeCard(UI.vstack([
            UI.hstack([numCircle(1), UI.cardTitle("Scan this")], spacing: 8),
            UI.small(srcText, color: Tok.slate),
            UI.hstack([PillButton("Change disk", style: .secondary, target: self, action: #selector(pickDisk)),
                       PillButton("Use a disk image…", style: .secondary, target: self, action: #selector(pickAuditImage))], spacing: 8),
        ], spacing: 10), padding: 18)
        let destValid = auditDestination != nil && destinationIsDifferentDisk()
        let destBadge: NSView = auditDestination == nil ? badgeNeutral("Choose a folder") : (destValid ? badge("Different disk", fill: Tok.greenSoft, textColor: Tok.greenDark) : badge("Same disk, not allowed", fill: Tok.warningBg, textColor: Tok.warningText))
        let destCard = makeCard(UI.vstack([
            UI.hstack([numCircle(2), UI.cardTitle("Save recovered files to")], spacing: 8),
            UI.hstack([UI.mono(auditDestination ?? "—", 12, color: Tok.slate), destBadge], spacing: 8),
            PillButton("Choose folder…", style: .secondary, target: self, action: #selector(pickAuditDestination)),
        ], spacing: 10), padding: 18)
        let cards = UI.hstack([scanCard, destCard], spacing: 16, alignment: .top); cards.distribution = .fillEqually
        let limits = limitsPanel(title: "What this can't tell you", body: "This reads host-accessible space only. SSD/Fusion controllers keep hidden cells no software can read, so a clean result is not proof nothing is recoverable.")
        let start = PillButton("Start audit", style: .primary, target: self, action: #selector(startAudit))
        start.isEnabled = !auditRunning && (selectedVolume != nil || auditImagePath != nil) && destValid
        auditStartBtn = start
        auditResultHost.translatesAutoresizingMaskIntoConstraints = false
        let footer = footerBar([UI.text("macOS will ask for your administrator password.", Ty.caption, Tok.steel), start])
        show(UI.vstack([eyebrow, heading, intro, cards, limits, footer, auditResultHost], spacing: 18))
    }
    private func numCircle(_ n: Int) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.wantsLayer = true; v.layer?.backgroundColor = Tok.surfaceSoft.cgColor; v.layer?.cornerRadius = 11
        let l = UI.text("\(n)", Ty.f(12, .bold), Tok.slate); l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
        NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant: 22), v.heightAnchor.constraint(equalToConstant: 22),
            l.centerXAnchor.constraint(equalTo: v.centerXAnchor), l.centerYAnchor.constraint(equalTo: v.centerYAnchor)])
        return v
    }
    private func destinationIsDifferentDisk() -> Bool {
        guard let dest = auditDestination else { return false }
        if auditImagePath != nil { return true }
        guard let v = selectedVolume, let ds = POSIX.statfsFor(path: dest), let ss = POSIX.statfsFor(path: v.mountPath) else { return true }
        return ds.mountedOn != ss.mountedOn
    }
    @objc private func pickAuditImage() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowedFileTypes = ["dmg","img","iso","dd","raw","sparseimage"]
        if p.runModal() == .OK, let u = p.url { auditImagePath = u.path; selectedVolume = nil; checkSetup() }
    }
    @objc private func pickAuditDestination() {
        let p = NSOpenPanel(); p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        if p.runModal() == .OK, let u = p.url { auditDestination = u.path; checkSetup() }
    }
    @objc private func startAudit() {
        guard let dest = auditDestination else { return }
        let target: String; let isDevice: Bool
        if let img = auditImagePath { target = img; isDevice = false }
        else if let v = selectedVolume { guard let raw = POSIX.rawDeviceNode(forPath: v.mountPath) else { alert("No device", "Could not resolve the device node."); return }; target = raw; isDevice = true }
        else { return }
        auditRunning = true; checkSetup()
        setAuditResult(UI.body("Scanning \(target)… \(isDevice ? "You'll be asked for your admin password. " : "")This can take a long time."))
        photorec.audit(target: target, isDevice: isDevice, destination: dest) { [weak self] s in
            guard let self = self else { return }; self.auditRunning = false; self.checkSetup(); self.presentAuditSummary(s)
        }
    }
    private func setAuditResult(_ v: NSView) {
        auditResultHost.subviews.forEach { $0.removeFromSuperview() }; v.translatesAutoresizingMaskIntoConstraints = false; auditResultHost.addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: auditResultHost.leadingAnchor), v.trailingAnchor.constraint(lessThanOrEqualTo: auditResultHost.trailingAnchor),
            v.topAnchor.constraint(equalTo: auditResultHost.topAnchor), v.bottomAnchor.constraint(equalTo: auditResultHost.bottomAnchor)])
    }
    private func presentAuditSummary(_ s: AuditSummary) {
        if let e = s.error { setAuditResult(warningPanel(title: "Audit did not complete", body: e)); return }
        if s.cancelled { setAuditResult(UI.body("Audit cancelled.")); return }
        let none = s.totalFiles == 0
        let count = UI.text("\(s.totalFiles)", NSFont.monospacedDigitSystemFont(ofSize: 80, weight: .medium), none ? Tok.greenDark : Tok.orangeDark)
        let label = UI.text(none ? "No recoverable files found" : "recoverable files found", Ty.heading5, Tok.ink)
        let dest = UI.small("Recovered to: \(s.destination) · \(UI.gb(s.bytesRecovered))", color: Tok.steel)
        var views: [NSView] = [UI.hstack([count, UI.vstack([label, dest], spacing: 2)], spacing: 16, alignment: .centerY)]
        if !s.perType.isEmpty {
            let bars = TypeBarsView(); bars.translatesAutoresizingMaskIntoConstraints = false
            bars.set(s.perType.prefix(8).map { TypeBarsView.Row(label: $0.ext, count: $0.count) })
            views.append(UI.text("By file type", Ty.f(13, .semibold), Tok.slate)); views.append(bars)
        }
        views.append(limitsPanel(title: "Keep in mind", body: none ? "Nothing was carved from reachable space — reassuring, but not proof (SSD-hidden cells, snapshots)." : "These are files a recovery tool could reconstruct. Run a wipe, or use FileVault / full erase for guarantees."))
        setAuditResult(UI.vstack(views, spacing: 14))
    }

    // MARK: - RECOVER (§4.9)

    private let tdOutputHost = NSView()
    private func recoverHome() {
        refreshDiskCard()
        let eyebrow = UI.eyebrow("3 · Recover")
        let heading = UI.homeHeading("Analyse and recover partitions")
        let intro = UI.body("Runs the bundled TestDisk to analyse a disk's partitions read-only. For hands-on partition repair / undelete, launch the interactive tool in Terminal.")
        let dev = selectedVolume.flatMap { POSIX.rawDeviceNode(forPath: $0.mountPath) } ?? "—"
        let analyze = PillButton("Analyse partitions", style: .primary, target: self, action: #selector(analyzeTD))
        let row = UI.hstack([analyze, badge("Read-only", fill: Tok.greenSoft, textColor: Tok.greenDark), UI.spacer(), UI.mono(dev, 12, color: Tok.steel)], spacing: 10)
        tdOutputHost.translatesAutoresizingMaskIntoConstraints = false
        let cmd = testdisk.interactiveCommand(target: dev) ?? "sudo testdisk <device>"
        let handsOn = makeCard(UI.vstack([UI.cardTitle("Need hands-on recovery?"),
            UI.mono(cmd, 12, color: Tok.ink),
            PillButton("Open in Terminal…", style: .secondary, target: self, action: #selector(launchTD))], spacing: 10), padding: 18)
        handsOn.layer?.backgroundColor = Tok.surface.cgColor
        show(UI.vstack([eyebrow, heading, intro, row, tdOutputHost, handsOn], spacing: 18))
    }
    @objc private func analyzeTD() {
        guard let v = selectedVolume, let raw = POSIX.rawDeviceNode(forPath: v.mountPath) else { alert("No disk", "Choose a disk first."); return }
        setTD(UI.body("Analysing \(raw)… you'll be asked for your admin password."))
        testdisk.listPartitions(target: raw, isDevice: true) { [weak self] text in
            let (scroll, tv) = UI.logView(); tv.string = text; tv.textColor = Tok.white; scroll.heightAnchor.constraint(equalToConstant: 280).isActive = true
            let dark = makeCard(scroll, dark: true, padding: 12)
            self?.setTD(dark)
        }
    }
    @objc private func launchTD() {
        guard let v = selectedVolume, let raw = POSIX.rawDeviceNode(forPath: v.mountPath), let cmd = testdisk.interactiveCommand(target: raw) else { alert("Unavailable", "Select a disk first."); return }
        let a = NSAlert(); a.messageText = "Open TestDisk in Terminal"; a.informativeText = "Terminal will run:\n\n\(cmd)\n\nTestDisk is interactive and can modify partitions — proceed carefully."
        a.addButton(withTitle: "Open Terminal"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            let script = "tell application \"Terminal\" to do script \"\(cmd.replacingOccurrences(of: "\"", with: "\\\""))\"\ntell application \"Terminal\" to activate"
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]; try? p.run()
        }
    }
    private func setTD(_ v: NSView) {
        tdOutputHost.subviews.forEach { $0.removeFromSuperview() }; v.translatesAutoresizingMaskIntoConstraints = false; tdOutputHost.addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: tdOutputHost.leadingAnchor), v.trailingAnchor.constraint(equalTo: tdOutputHost.trailingAnchor),
            v.topAnchor.constraint(equalTo: tdOutputHost.topAnchor), v.bottomAnchor.constraint(equalTo: tdOutputHost.bottomAnchor)])
    }

    // MARK: - Reports & diagnostics (§4.10)

    @objc func goReports() {
        if lockedDuringRun() { return }
        rowClean.setSelected(false); rowCheck.setSelected(false); rowRecover.setSelected(false)
        let eyebrow = UI.eyebrow("Reports & diagnostics")
        let heading = UI.homeHeading("Reports & diagnostics")
        func row(_ title: String, _ sub: String, _ btn: PillButton) -> NSView {
            UI.hstack([UI.vstack([UI.text(title, Ty.f(14, .semibold), Tok.ink), UI.small(sub, color: Tok.steel)], spacing: 2), UI.spacer(), btn], spacing: 12)
        }
        let r1 = row("Last report", "Save the JSON / HTML report of the last operation.", PillButton("Save report…", style: .secondary, target: self, action: #selector(saveReportHTML)))
        let r2 = row("Diagnostics & recovery check", "Snapshots, encryption, free-vs-available gap.", PillButton("Run diagnostics", style: .secondary, target: self, action: #selector(runDiagnostics)))
        let r3 = row("Leftover files", "Remove app-owned files from an interrupted run.", PillButton("Clean up…", style: .secondary, target: self, action: #selector(cleanupStale)))
        let r4 = row("Energy settings", "Open macOS energy/battery settings.", PillButton("Open…", style: .secondary, target: self, action: #selector(openEnergy)))
        let list = makeCard(UI.vstack([r1, hairline(), r2, hairline(), r3, hairline(), r4], spacing: 14), padding: 20)
        let about = makeCard(UI.vstack([UI.cardTitle("About"),
            UI.small("Fusion Free Space Wiper \(AppInfo.version) — Intel · macOS 10.15+", color: Tok.slate),
            UI.small("Developed by Sunaz Sharaf · Recovery engine: PhotoRec & TestDisk © CGSecurity (GPL)", color: Tok.steel),
            UI.small("© 2026 Sunaz Sharaf · GNU GPL v2+ · No network · Local only", color: Tok.steel)], spacing: 6), padding: 18)
        about.layer?.backgroundColor = Tok.surface.cgColor
        show(UI.vstack([eyebrow, heading, list, about], spacing: 18))
    }
    private func hairline() -> NSView { let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; v.wantsLayer = true; v.layer?.backgroundColor = Tok.hairline.cgColor; v.heightAnchor.constraint(equalToConstant: 1).isActive = true; return v }
    @objc func goAdvanced() { goReports() }
    @objc private func runDiagnostics() {
        guard let v = selectedVolume else { noVolumeAlert(); return }
        let d = recovery.diagnostics(mountPath: v.mountPath)
        if lastRecovery == nil { lastRecovery = emptyRecovery() }
        lastRecovery?.snapshotState = d.snapshot; lastRecovery?.encryptionState = d.encryption; lastRecovery?.diagnosticsNote = d.note
        alert("Diagnostics", "Snapshots: \(d.snapshot.label)\nEncryption: \(d.encryption.label)\nFree/available gap: \(UI.gb(d.discrepancy))\n\n\(d.note.isEmpty ? "No snapshots detected." : d.note)")
    }
    @objc func cleanupStale() {
        var parents = Set<String>([NSHomeDirectory()])
        for v in volumes where !v.isReadOnly { if let p = try? sessions.writableParent(forMountPath: v.mountPath) { parents.insert(p) } }
        let stale = sessions.findStaleSessions(parents: Array(parents)).filter { !$0.isOwnerProcessAlive }
        if stale.isEmpty { alert("No leftover files", "No app-owned leftover sessions were found."); return }
        let total = stale.reduce(Int64(0)) { $0 + $1.totalBytes }
        let a = NSAlert(); a.messageText = "Clean up leftover files"; a.informativeText = "\(stale.count) session(s) totalling \(UI.gb(total)) can be removed."
        a.addButton(withTitle: "Remove"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { for s in stale { _ = sessions.removeSession(directory: s.directory) }; alert("Done", "Cleanup complete.") }
    }
    @objc private func openEnergy() { PowerInfo.openEnergySettings() }
    @objc func saveReportHTML() { saveReport(json: false) }
    @objc func saveReportJSON() { saveReport(json: true) }
    private func saveReport(json: Bool) {
        guard let v = selectedVolume, let result = lastResult else { alert("Nothing to save", "Run a test or wipe first."); return }
        let cfg = WipeConfiguration(targetMountPath: v.mountPath, expectedVolumeUUID: v.volumeUUID, expectedVolumeName: v.name, mode: result.mode, reserveBytes: result.reserveBytes)
        let report = reporter.buildReport(volume: v, config: cfg, result: result, recovery: lastRecovery)
        let panel = NSSavePanel(); panel.nameFieldStringValue = json ? "FusionFreeSpaceWiper-Report.json" : "FusionFreeSpaceWiper-Report.html"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self = self else { return }
            do { if json { try self.reporter.jsonData(report).write(to: url) } else { try self.reporter.htmlString(report).data(using: .utf8)?.write(to: url) } }
            catch { self.alert("Save failed", "\(error)") }
        }
    }

    // MARK: - Menu hooks
    @objc func goHome() { selectTool(.clean) }
    @objc func showAbout() { AboutPanel.show() }
    @objc func menuHelp() { HelpWindowController.shared.present() }
    @objc func showHelp() { HelpWindowController.shared.present() }
    @objc func showPreferences() { PreferencesWindowController.shared.present() }

    // MARK: - Disk picking

    @objc private func pickDisk() {
        reloadVolumes()
        let a = NSAlert(); a.messageText = "Choose a disk"; a.informativeText = "Pick the disk to work with."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        for v in volumes { popup.addItem(withTitle: "\(v.name) — \(v.mountPath)") }
        if let idx = volumes.firstIndex(where: { $0.mountPath == selectedVolume?.mountPath }) { popup.selectItem(at: idx) }
        a.accessoryView = popup; a.addButton(withTitle: "Use"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn, popup.indexOfSelectedItem >= 0, popup.indexOfSelectedItem < volumes.count {
            var v = volumes[popup.indexOfSelectedItem]; inspector.enrichDiagnostics(&v); selectedVolume = v; auditImagePath = nil
            applyRecommendedReserve(for: v); selectTool(tool)
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
        a.informativeText = "A previous session appears to have been interrupted. \(stale.count) session(s) totalling \(UI.gb(total)) can be removed."
        a.addButton(withTitle: "Remove now"); a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { for s in stale { _ = sessions.removeSession(directory: s.directory) } }
    }

    // MARK: - Power / helpers

    private func preRunPowerChecksPass() -> Bool {
        let onBattery = PowerInfo.current() == .battery
        let laptop = PowerInfo.hasBattery()
        guard onBattery || laptop else { return true }
        let a = NSAlert()
        if onBattery {
            a.messageText = "Running on battery"
            a.informativeText = "This can take a while and uses a lot of disk activity. Plug into power before continuing.\n\nNote: this is a laptop — closing the lid will put it to sleep and interrupt the run."
            a.alertStyle = .warning
        } else {
            a.messageText = "This looks like a laptop"
            a.informativeText = "Closing the lid will put the Mac to sleep and interrupt the run (including cleanup). Keep the lid open and stay on power."
            a.alertStyle = .informational
        }
        a.addButton(withTitle: "Continue"); a.addButton(withTitle: "Open Energy Settings…"); a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: PowerInfo.openEnergySettings(); return false
        default: return false
        }
    }

    private func reloadVolumes() {
        volumes = inspector.mountedVolumes().filter { $0.isBrowsable }
        if selectedVolume == nil || !volumes.contains(where: { $0.mountPath == selectedVolume?.mountPath }) {
            if var v = volumes.first(where: { $0.mountPath == "/" }) ?? volumes.first { inspector.enrichDiagnostics(&v); selectedVolume = v; applyRecommendedReserve(for: v) }
        }
    }
    private func applyRecommendedReserve(for v: VolumeInfo) {
        if prefs.defaultReserveGiB > 0 { reserveGB = max(10, prefs.defaultReserveGiB) }
        else { reserveGB = (Double(ReservePolicy.recommendedReserve(totalCapacity: v.totalCapacity)) / 1_000_000_000).rounded() }
    }
    private func reserveBytes() -> Int64 { ReservePolicy.clamp(Int64(reserveGB * 1_000_000_000)) }
    private func writableBytes() -> Int64 { max(0, (selectedVolume?.freeCapacityRaw ?? 0) - reserveBytes()) }
    private func bestTestSpeed() -> Double? {
        TestSize.allCases.compactMap { TestHistory.shared.outcome($0) }.filter { $0.passed && $0.averageThroughput > 0 }.map { $0.averageThroughput }.max()
    }
    private func estimateText(forBytes b: Int64) -> String? {
        guard let s = bestTestSpeed(), s > 0 else { return nil }
        let secs = Double(b) / s
        if secs < 90 { return "~\(Int(secs.rounded())) sec" }
        if secs < 5400 { return "~\(Int((secs/60).rounded())) min" }
        return "~\(String(format: "%.1f", secs/3600)) hr"
    }
    private func hms(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "—" }
        let s = Int(t.rounded()); return String(format: "%02d:%02d:%02d", s/3600, (s%3600)/60, s%60)
    }
    private func decRate(_ bps: Double) -> String { bps <= 0 ? "—" : UI.gb(Int64(bps)) + "/s" }
    private func kv(_ k: String, _ v: String) -> NSView { UI.hstack([UI.text(k, Ty.bodySmall, Tok.steel), UI.spacer(), UI.text(v, Ty.f(13, .semibold), Tok.ink)], spacing: 12) }
    private func kvColored(_ k: String, _ v: String, _ c: NSColor) -> NSView { UI.hstack([UI.text(k, Ty.bodySmall, Tok.steel), UI.spacer(), UI.text(v, Ty.f(13, .semibold), c)], spacing: 12) }
    private func emptyRecovery() -> RecoveryTestReport { RecoveryTestReport(layerA_ran: false, layerA_bytesVerified: 0, layerA_mismatches: 0, layerA_note: "Not run.", layerB_available: false, layerB_note: "Not run.", snapshotState: .unknown, encryptionState: .unknown, freeVsAvailableDiscrepancyBytes: 0, diagnosticsNote: "") }
    private func noVolumeAlert() { alert("No disk selected", "Use ‘Change disk’ in the sidebar.") }
    private func alert(_ t: String, _ m: String) { let a = NSAlert(); a.messageText = t; a.informativeText = m; a.runModal() }

    func windowWillClose(_ n: Notification) { wiper.requestCancel(); sleepAssertion.end(); DockProgress.set(percent: nil) }
}
