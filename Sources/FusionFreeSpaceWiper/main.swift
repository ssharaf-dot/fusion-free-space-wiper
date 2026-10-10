//
//  main.swift
//  Fusion Free Space Wiper
//
//  Programmatic AppKit entry point (no storyboard / xib) so the app builds and
//  runs identically whether produced by Xcode or by the plain-toolchain build
//  script. Targets macOS 10.15, x86_64.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
