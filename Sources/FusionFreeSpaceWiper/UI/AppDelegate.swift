//
//  AppDelegate.swift
//  Fusion Free Space Wiper
//
//  Builds the full macOS menu bar (, File, Edit, View, Go, Window, Help) and
//  owns the main guided window. Menu actions forward to the window controller.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainController: MainWindowController?
    private var controller: MainWindowController { mainController! }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Light-only design (§0): force Aqua so Catalina Dark Mode doesn't half-apply.
        NSApp.appearance = NSAppearance(named: .aqua)
        buildMenu()
        let c = MainWindowController()
        mainController = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        c.promptStaleSessionsAtLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu construction

    private func item(_ title: String, _ sel: Selector?, _ key: String = "", target: AnyObject? = nil,
                      modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        if !key.isEmpty { mi.keyEquivalentModifierMask = modifiers }
        mi.target = target
        return mi
    }

    private func buildMenu() {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(item("About \(AppInfo.name)", #selector(aboutAction), target: self, modifiers: []))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Preferences…", #selector(prefsAction), ",", target: self))
        appMenu.addItem(.separator())
        let services = NSMenu(); let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; NSApp.servicesMenu = services; appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(AppInfo.name)", #selector(NSApplication.hide(_:)), "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option])
        appMenu.addItem(hideOthers)
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(AppInfo.name)", #selector(NSApplication.terminate(_:)), "q"))
        appItem.submenu = appMenu

        // File
        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("New Test…", #selector(newTestAction), "n", target: self))
        file.addItem(item("Start Full Wipe…", #selector(startWipeAction), "", target: self))   // no shortcut (destructive)
        file.addItem(.separator())
        file.addItem(item("Save Report…", #selector(saveReportAction), "s", target: self))
        file.addItem(item("Clean Up Leftover Files…", #selector(cleanupAction), "", target: self))
        file.addItem(.separator())
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        fileItem.submenu = file

        // Edit
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        editItem.submenu = edit

        // View
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(item("Home", #selector(homeAction), "1", target: self))
        view.addItem(item("Advanced", #selector(advancedAction), "2", target: self))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))
        viewItem.submenu = view

        // Go
        let goItem = NSMenuItem(); main.addItem(goItem)
        let go = NSMenu(title: "Go")
        go.addItem(item("Home", #selector(homeAction), "", target: self))
        go.addItem(item("Run a Test", #selector(newTestAction), "", target: self))
        go.addItem(item("Wipe Free Space", #selector(startWipeAction), "", target: self))
        go.addItem(item("Advanced", #selector(advancedAction), "", target: self))
        goItem.submenu = go

        // Window
        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""))
        windowItem.submenu = window
        NSApp.windowsMenu = window

        // Help
        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(item("\(AppInfo.name) Help", #selector(helpAction), "?", target: self))
        help.addItem(item("Safety & Limitations…", #selector(helpAction), "", target: self))
        help.addItem(.separator())
        help.addItem(item("View Source on GitHub", #selector(sourceAction), "", target: self))
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    // MARK: - Forwarded actions

    @objc private func aboutAction() { controller.showAbout() }
    @objc private func prefsAction() { controller.showPreferences() }
    @objc private func helpAction() { controller.showHelp() }
    @objc private func homeAction() { controller.goHome() }
    @objc private func advancedAction() { controller.goAdvanced() }
    @objc private func newTestAction() { controller.goTestSize() }
    @objc private func startWipeAction() { controller.goWipeAction() }
    @objc private func saveReportAction() { controller.saveReportHTML() }
    @objc private func cleanupAction() { controller.cleanupStale() }
    @objc private func sourceAction() { if let u = URL(string: AppInfo.repositoryURL) { NSWorkspace.shared.open(u) } }
}
