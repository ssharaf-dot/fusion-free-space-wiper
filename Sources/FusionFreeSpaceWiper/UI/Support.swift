//
//  Support.swift
//  Fusion Free Space Wiper
//
//  Cross-cutting UI services: preferences, a no-idle-sleep power assertion,
//  AC/battery detection, a completion alert, and the Help / About windows.
//  All APIs used here exist on macOS 10.15.
//

import AppKit
import IOKit.pwr_mgt
import IOKit.ps

// MARK: - Preferences (UserDefaults-backed)

final class PreferencesStore {
    static let shared = PreferencesStore()
    private let d = UserDefaults.standard

    private enum Key {
        static let testSize = "pref.defaultTestSize"
        static let reserveGiB = "pref.defaultReserveGiB"   // 0 == use recommended
        static let confirmName = "pref.alwaysConfirmName"
        static let sound = "pref.finishSound"
    }

    var defaultTestSize: TestSize {
        get { TestSize(rawValue: d.string(forKey: Key.testSize) ?? "") ?? .mb100 }
        set { d.set(newValue.rawValue, forKey: Key.testSize) }
    }
    /// 0 means "use the recommended reserve for the volume".
    var defaultReserveGiB: Double {
        get { d.object(forKey: Key.reserveGiB) == nil ? 0 : d.double(forKey: Key.reserveGiB) }
        set { d.set(newValue, forKey: Key.reserveGiB) }
    }
    var alwaysConfirmName: Bool {
        get { d.object(forKey: Key.confirmName) == nil ? true : d.bool(forKey: Key.confirmName) }
        set { d.set(newValue, forKey: Key.confirmName) }
    }
    var finishSound: Bool {
        get { d.object(forKey: Key.sound) == nil ? true : d.bool(forKey: Key.sound) }
        set { d.set(newValue, forKey: Key.sound) }
    }
}

// MARK: - Power management

/// Holds a "no idle sleep" assertion so the Mac doesn't sleep mid-run.
final class SleepAssertion {
    private var id: IOPMAssertionID = 0
    private var active = false
    func begin(reason: String) {
        guard !active else { return }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            reason as CFString, &id)
        active = (r == kIOReturnSuccess)
    }
    func end() {
        if active { IOPMAssertionRelease(id); active = false }
    }
}

enum PowerInfo {
    enum Source { case ac, battery, unknown }
    /// Current power source. Desktops (no battery) report .ac.
    static func current() -> Source {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? else {
            return .unknown
        }
        if type == kIOPMACPowerKey { return .ac }
        if type == kIOPMBatteryPowerKey { return .battery }
        return .unknown
    }

    /// True if this Mac has an internal battery — i.e. it is a laptop. Used to warn
    /// that closing the lid will sleep the Mac and interrupt a run.
    static func hasBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for s in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, s)?.takeUnretainedValue() as? [String: Any],
               let type = desc[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                return true
            }
        }
        return false
    }

    /// Opens the Energy/Battery settings pane so the user can adjust sleep themselves.
    /// This only *opens* the pane — the app never changes power settings itself.
    static func openEnergySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.energysaver",
            "x-apple.systempreferences:com.apple.preference.battery",
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
    }
}

// MARK: - Completion alert (sound + Dock attention; no deprecated APIs)

enum Notifier {
    static func finished(success: Bool) {
        if PreferencesStore.shared.finishSound {
            NSSound(named: success ? "Glass" : "Basso")?.play()
        }
        // Bounce the Dock icon if the app is in the background.
        NSApp.requestUserAttention(.informationalRequest)
    }
}

// MARK: - Dock progress

enum DockProgress {
    static func set(percent: Int?) {
        if let p = percent { NSApp.dockTile.badgeLabel = "\(p)%" }
        else { NSApp.dockTile.badgeLabel = nil }
        NSApp.dockTile.display()
    }
}

// MARK: - Help window

final class HelpWindowController: NSWindowController {
    static let shared = HelpWindowController()
    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Fusion Free Space Wiper Help"
        self.init(window: w)
        let (scroll, tv) = UI.logView()
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.string = HelpWindowController.text
        tv.textContainerInset = NSSize(width: 16, height: 14)
        w.contentView = NSView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: w.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor),
        ])
    }
    func present() { showWindow(nil); window?.center(); window?.makeKeyAndOrderFront(nil) }

    static let text = """
    FUSION FREE SPACE WIPER — HELP

    WHAT IT DOES
    Fills the empty (free) space on a disk with overwrite data, then deletes it, so
    previously-deleted files are harder to recover. It never touches your current
    files, apps or macOS, and it is NOT a certified or forensic erase.

    THE GUIDED FLOW
    • Home — pick what to do. The app always opens here.
    • Test Mode — runs the REAL engine but stops after a strict limit (100 MB / 1 GB /
      10 GB). Use it to prove everything works before a full wipe.
    • Full Free-Space Wipe — overwrites all free space except a safety reserve.
    • Advanced — reports, diagnostics and leftover-file cleanup.
    The step dots at the top show where you are; the Home button returns you here.

    WHICH MACS BENEFIT
    • Spinning hard drives (HDD): works well.
    • Fusion Drive (HDD + SSD): partly — the HDD portion benefits. The honest sweet spot.
    • Pure SSD / flash: limited value (wear-leveling / TRIM). Use FileVault, or erase the
      whole disk before selling, instead.

    SAFETY
    • A safety reserve (default max(20 GiB, 10% of capacity), never below 10 GiB) is always
      kept free. The app re-checks space before every write and never fills the disk.
    • Only files the app itself creates are ever written or deleted.
    • A full wipe asks you to type the disk name to confirm.
    • The Mac is kept awake during a run; running on battery triggers a warning.

    THE HONEST LIMITATIONS
    • Cannot guarantee deleted data is unrecoverable, especially on SSD/Fusion.
    • Does not remove APFS snapshots (it detects and warns; never deletes them).
    • "No files recovered" is not proof that nothing is recoverable.
    """
}

// MARK: - About

enum AboutPanel {
    static func show() {
        let credits = NSMutableAttributedString()
        let body: [(String, String)] = [
            ("Developed by", "Sunaz Sharaf"),
            ("Dependencies", "None — no third-party code"),
            ("Privacy", "No network · No telemetry · Local only"),
            ("Source", "github.com/ssharaf-dot/fusion-free-space-wiper"),
        ]
        let p = NSMutableParagraphStyle(); p.alignment = .center
        for (k, v) in body {
            credits.append(NSAttributedString(string: "\(k): ", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: p]))
            credits.append(NSAttributedString(string: "\(v)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: p]))
        }
        credits.append(NSAttributedString(string: "\nNot a certified or forensic erase. On Fusion/SSD drives, overwriting free space cannot guarantee deleted data is unrecoverable.",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: p]))

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Sunaz Sharaf · MIT License",
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Preferences window

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reserveField = NSTextField(string: "")
    private let confirmCheck = NSButton(checkboxWithTitle: "Always confirm a full wipe by typing the disk name", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle: "Play a sound when a run finishes", target: nil, action: nil)

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Preferences"
        self.init(window: w)
        build()
    }

    private func build() {
        let prefs = PreferencesStore.shared
        for s in TestSize.allCases { sizePopup.addItem(withTitle: s.shortLabel) }
        sizePopup.selectItem(withTitle: prefs.defaultTestSize.shortLabel)
        reserveField.stringValue = prefs.defaultReserveGiB > 0 ? String(format: "%.0f", prefs.defaultReserveGiB) : ""
        reserveField.placeholderString = "Recommended"
        reserveField.translatesAutoresizingMaskIntoConstraints = false
        reserveField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        confirmCheck.state = prefs.alwaysConfirmName ? .on : .off
        soundCheck.state = prefs.finishSound ? .on : .off

        let rows = UI.vstack([
            UI.hstack([UI.label("Default test size:"), sizePopup]),
            UI.hstack([UI.label("Default safety reserve (GiB):"), reserveField]),
            confirmCheck, soundCheck,
            UI.multiline("Leave the reserve blank to use the recommended value for each disk. The reserve never drops below 10 GiB.", size: 11),
        ], spacing: 14)
        let save = FancyButton("Save", kind: .primary, target: self, action: #selector(save))
        let container = UI.vstack([rows, UI.hstack([NSView(), save])], spacing: 18)
        let content = NSView()
        content.addSubview(container)
        window?.contentView = content
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
        ])
    }

    @objc private func save() {
        let prefs = PreferencesStore.shared
        if let t = TestSize.allCases.first(where: { $0.shortLabel == sizePopup.titleOfSelectedItem }) { prefs.defaultTestSize = t }
        prefs.defaultReserveGiB = Double(reserveField.stringValue) ?? 0
        prefs.alwaysConfirmName = confirmCheck.state.isOn
        prefs.finishSound = soundCheck.state.isOn
        window?.close()
    }

    func present() { showWindow(nil); window?.center(); window?.makeKeyAndOrderFront(nil) }
}
