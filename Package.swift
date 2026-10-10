// swift-tools-version:5.3
//
// Package.swift — lets you open this folder directly in Xcode
// (File ▸ Open ▸ select the FusionFreeSpaceWiper folder) and Build/Run.
//
// NOTE: For the shippable Catalina .app + .dmg (x86_64, deployment target 10.15),
// use ./build.sh — that is the authoritative, verified build path. This package is
// provided so the code opens and compiles in Xcode; `swift run` also works.
//
import PackageDescription

let package = Package(
    name: "FusionFreeSpaceWiper",
    platforms: [ .macOS(.v10_15) ],
    targets: [
        .target(
            name: "FusionFreeSpaceWiper",
            path: "Sources/FusionFreeSpaceWiper",
            exclude: ["Resources/Info.plist"]
        )
    ]
)
