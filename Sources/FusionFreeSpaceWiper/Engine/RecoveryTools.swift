//
//  RecoveryTools.swift
//  Fusion Free Space Wiper
//
//  Thin, honest wrappers that drive the bundled PhotoRec and TestDisk (GPL,
//  CGSecurity) for the Audit and Recover tabs. Everything here is READ-ONLY with
//  respect to the source disk — PhotoRec only ever reads the source and writes
//  recovered files into a SEPARATE destination the user chooses; TestDisk is used
//  only in read-only list mode from the app (interactive recovery is launched in
//  Terminal with the user's consent).
//
//  Raw block devices require root, so device scans are run via a native macOS
//  administrator prompt (`osascript … with administrator privileges`). Disk images
//  need no privileges.
//

import Foundation

enum RecoveryToolLocator {
    /// Locate a bundled tool (photorec/testdisk/fidentify) inside the app, with a
    /// dev fallback to a local build directory.
    static func url(_ name: String) -> URL? {
        if let res = Bundle.main.resourceURL {
            let u = res.appendingPathComponent("recovery/\(name)")
            if FileManager.default.isExecutableFile(atPath: u.path) { return u }
        }
        // Dev fallback: ./build/FusionFreeSpaceWiper.app/…/recovery
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/FusionFreeSpaceWiper.app/Contents/Resources/recovery/\(name)")
        if FileManager.default.isExecutableFile(atPath: dev.path) { return dev }
        return nil
    }
    static var photorecAvailable: Bool { url("photorec") != nil }
    static var testdiskAvailable: Bool { url("testdisk") != nil }
}

/// Runs a shell command, optionally as root via a native admin prompt.
enum PrivilegedRunner {
    /// Run `command` (a /bin/sh script body). If `asRoot`, prompt for admin via
    /// osascript. Returns (exitOK, combinedOutput). Blocks — call off the main thread.
    static func run(_ command: String, asRoot: Bool) -> (ok: Bool, output: String) {
        if asRoot {
            // Write the command to a temp script to avoid AppleScript quoting hell.
            let tmp = NSTemporaryDirectory() + "ffsw-recovery-\(UUID().uuidString).sh"
            try? ("#!/bin/sh\n" + command + "\n").write(toFile: tmp, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(atPath: tmp) }
            let apple = "do shell script \"/bin/sh \(tmp)\" with administrator privileges"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", apple]
            return runProcess(p)
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", command]
            return runProcess(p)
        }
    }

    private static func runProcess(_ p: Process) -> (ok: Bool, output: String) {
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return (false, "Failed to launch: \(error.localizedDescription)") }
        let oData = out.fileHandleForReading.readDataToEndOfFile()
        let eData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let combined = (String(data: oData, encoding: .utf8) ?? "") + (String(data: eData, encoding: .utf8) ?? "")
        return (p.terminationStatus == 0, combined)
    }
}

// MARK: - PhotoRec (audit / recover)

public struct AuditSummary {
    public var totalFiles: Int
    public var perType: [(ext: String, count: Int)]   // sorted desc
    public var destination: String
    public var bytesRecovered: Int64
    public var logTail: String
    public var cancelled: Bool
    public var error: String?
}

public final class PhotoRecRunner {

    public init() {}

    public var isAvailable: Bool { RecoveryToolLocator.photorecAvailable }

    /// Carve `target` (a device path like /dev/rdisk0s2, or a disk-image path),
    /// recovering into `destination`. Device scans need root (asRoot=true triggers
    /// the admin prompt). Completion is delivered on the main thread.
    public func audit(target: String, isDevice: Bool, destination: String,
                      completion: @escaping (AuditSummary) -> Void) {
        guard let pr = RecoveryToolLocator.url("photorec") else {
            DispatchQueue.main.async {
                completion(AuditSummary(totalFiles: 0, perType: [], destination: destination,
                                        bytesRecovered: 0, logTail: "", cancelled: false,
                                        error: "PhotoRec is not bundled with this build."))
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
            let recup = (destination as NSString).appendingPathComponent("recovered")
            let logPath = (destination as NSString).appendingPathComponent("photorec.log")
            // Carve everything, whole media, write to `recup`.
            let cmd = "cd \(sh(destination)) && \(sh(pr.path)) /log /d \(sh(recup)) /cmd \(sh(target)) partition_none,fileopt,everything,enable,search >/dev/null 2>&1 || true"
            let result = PrivilegedRunner.run(cmd, asRoot: isDevice)

            // Parse photorec.log for the per-type and total lines.
            let log = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? result.output
            let summary = Self.parse(log: log, destination: destination)
            var s = summary
            if !result.ok && summary.totalFiles == 0 && summary.error == nil {
                // If osascript was cancelled, the admin prompt was dismissed.
                if result.output.contains("User canceled") || result.output.contains("-128") {
                    s.cancelled = true
                } else if log.isEmpty {
                    s.error = "PhotoRec did not produce a log. It may have been denied disk access."
                }
            }
            DispatchQueue.main.async { completion(s) }
        }
    }

    private static func parse(log: String, destination: String) -> AuditSummary {
        var total = 0
        var perType: [(String, Int)] = []
        for line in log.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Total:") {
                // "Total: 513 files found"
                let nums = t.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                if let n = nums.first { total = n }
            } else if t.contains(" recovered"), let colon = t.firstIndex(of: ":") {
                // "jpg: 12/14 recovered"  → ext=jpg, count=12
                let ext = String(t[..<colon]).trimmingCharacters(in: .whitespaces)
                let rest = String(t[t.index(after: colon)...])
                let nums = rest.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                if let n = nums.first, !ext.isEmpty, ext.count <= 12 { perType.append((ext, n)) }
            }
        }
        perType.sort { $0.1 > $1.1 }
        // Measure recovered bytes (best effort).
        var bytes: Int64 = 0
        let recupBase = (destination as NSString).appendingPathComponent("recovered")
        let fm = FileManager.default
        if let base = try? fm.contentsOfDirectory(atPath: destination) {
            for d in base where d.hasPrefix("recovered") {
                let dir = (destination as NSString).appendingPathComponent(d)
                if let e = fm.enumerator(atPath: dir) {
                    for case let f as String in e {
                        let p = (dir as NSString).appendingPathComponent(f)
                        if let a = try? fm.attributesOfItem(atPath: p), let sz = a[.size] as? Int64 { bytes += sz }
                    }
                }
            }
        }
        _ = recupBase
        return AuditSummary(totalFiles: total, perType: perType.map { (ext: $0.0, count: $0.1) },
                            destination: destination, bytesRecovered: bytes, logTail: String(log.suffix(1200)),
                            cancelled: false, error: nil)
    }
}

// MARK: - TestDisk (read-only partition analysis + guided launch)

public final class TestDiskRunner {
    public init() {}
    public var isAvailable: Bool { RecoveryToolLocator.testdiskAvailable }

    /// Read-only partition listing via `testdisk /list`. Device needs root.
    public func listPartitions(target: String, isDevice: Bool, completion: @escaping (String) -> Void) {
        guard let td = RecoveryToolLocator.url("testdisk") else {
            DispatchQueue.main.async { completion("TestDisk is not bundled with this build.") }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let tmpLog = NSTemporaryDirectory() + "ffsw-testdisk-\(UUID().uuidString).log"
            let cmd = "\(sh(td.path)) /log /debug /list \(sh(target)) >/dev/null 2>&1 || true; cat \(sh(tmpLog)) 2>/dev/null || true"
            // testdisk writes testdisk.log in cwd; capture it.
            let cmd2 = "cd \(sh(NSTemporaryDirectory())) && \(sh(td.path)) /list \(sh(target)) 2>&1 | cat; echo '---'; cat testdisk.log 2>/dev/null | tail -60"
            _ = cmd; _ = tmpLog
            let r = PrivilegedRunner.run(cmd2, asRoot: isDevice)
            let text = r.output.isEmpty ? "No output (TestDisk may have been denied disk access, or the scan was cancelled)." : r.output
            DispatchQueue.main.async { completion(Self.strip(text)) }
        }
    }

    /// Build the command a user would run to drive TestDisk interactively in Terminal.
    public func interactiveCommand(target: String) -> String? {
        guard let td = RecoveryToolLocator.url("testdisk") else { return nil }
        return "sudo \(td.path) \(target)"
    }

    private static func strip(_ s: String) -> String {
        // Remove ANSI/ncurses escape sequences for readable display.
        let pattern = "\u{1B}\\[[0-9;?]*[A-Za-z]"
        if let re = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(s.startIndex..., in: s)
            return re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        return s
    }
}

/// Minimal single-argument shell quoting.
private func sh(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
