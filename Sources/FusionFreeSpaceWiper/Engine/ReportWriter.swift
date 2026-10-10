//
//  ReportWriter.swift
//  Fusion Free Space Wiper
//
//  Produces a JSON report and a human-readable HTML report. It reports the honest
//  status (completed-with-limitations / incomplete / failed), never a certificate
//  of irrecoverability. It records no filenames of user data, no passwords, and no
//  drive serial numbers by default.
//

import Foundation

public struct FullReport: Codable {
    public var appName: String
    public var appVersion: String
    public var generatedAt: String
    public var osVersion: String

    public var volumeName: String
    public var mountPath: String
    public var volumeUUID: String?
    public var filesystemType: String
    public var fusionDrive: String
    public var snapshotState: String
    public var encryptionState: String

    public var requestedMode: String
    public var requestedPasses: Int
    public var reserveBytes: Int64
    public var reserveHuman: String

    public var status: String
    public var cancelled: Bool
    public var reserveBreached: Bool
    public var totalLogicalBytesWritten: Int64
    public var totalLogicalHuman: String
    public var totalPhysicalBytesConsumed: Int64
    public var totalPhysicalHuman: String
    public var zeroElisionSuspected: Bool
    public var cleanupSucceeded: Bool
    public var leftoverFileCount: Int

    public struct Pass: Codable {
        public var index: Int
        public var pattern: String
        public var bytesWritten: Int64
        public var bytesHuman: String
        public var error: String?
    }
    public var passes: [Pass]

    public var recovery_layerA_bytesVerified: Int64
    public var recovery_layerA_mismatches: Int
    public var recovery_layerA_note: String
    public var recovery_layerB_available: Bool
    public var recovery_layerB_note: String
    public var diagnosticsNote: String

    public var errors: [String]
    public var limitations: [String]
}

public final class ReportWriter {

    public init() {}

    public static let standardLimitations: [String] = [
        "This tool overwrote accessible filesystem free space only. It did not and cannot guarantee that every formerly-used physical block on the HDD or SSD tier of a Fusion Drive was overwritten.",
        "SSD wear-leveling, over-provisioning, TRIM, and remapped/spare blocks may retain copies of old data that host writes cannot reach.",
        "APFS copy-on-write, compression, clones, and zero-block handling mean logical writes do not map one-to-one to physical blocks.",
        "APFS snapshots (Time Machine local snapshots included) can retain deleted-file extents and were NOT removed by this app.",
        "fsync / F_FULLFSYNC ask the drive to flush buffers; they do not force specific physical cells to be rewritten.",
        "Recovery testing here verifies only newly-allocated test files. No recovered files is NOT proof of irrecoverability.",
        "This is an 'accessible free-space overwrite', not a certified, forensic, or permanent erase."
    ]

    public func buildReport(volume: VolumeInfo, config: WipeConfiguration, result: WipeResult,
                            recovery: RecoveryTestReport?) -> FullReport {
        let passes = result.passes.map {
            FullReport.Pass(index: $0.passIndex, pattern: $0.pattern, bytesWritten: $0.bytesWritten,
                            bytesHuman: ByteText.format($0.bytesWritten), error: $0.error)
        }
        let df = ISO8601DateFormatter()
        return FullReport(
            appName: AppInfo.name,
            appVersion: AppInfo.version,
            generatedAt: df.string(from: Date()),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            volumeName: volume.name,
            mountPath: volume.mountPath,
            volumeUUID: volume.volumeUUID,
            filesystemType: volume.filesystemType,
            fusionDrive: volume.fusionDriveState.label,
            snapshotState: (recovery?.snapshotState ?? volume.snapshotState).label,
            encryptionState: (recovery?.encryptionState ?? volume.encryptionState).label,
            requestedMode: config.mode.displayName,
            requestedPasses: config.mode.passCount,
            reserveBytes: config.reserveBytes,
            reserveHuman: ByteText.format(config.reserveBytes),
            status: result.status.displayName,
            cancelled: result.cancelled,
            reserveBreached: result.reserveBreached,
            totalLogicalBytesWritten: result.totalLogicalBytesWritten,
            totalLogicalHuman: ByteText.format(result.totalLogicalBytesWritten),
            totalPhysicalBytesConsumed: result.totalPhysicalBytesConsumed,
            totalPhysicalHuman: ByteText.format(result.totalPhysicalBytesConsumed),
            zeroElisionSuspected: result.zeroElisionSuspected,
            cleanupSucceeded: result.cleanupSucceeded,
            leftoverFileCount: result.leftoverFiles.count,
            passes: passes,
            recovery_layerA_bytesVerified: recovery?.layerA_bytesVerified ?? 0,
            recovery_layerA_mismatches: recovery?.layerA_mismatches ?? 0,
            recovery_layerA_note: recovery?.layerA_note ?? "Not run.",
            recovery_layerB_available: recovery?.layerB_available ?? false,
            recovery_layerB_note: recovery?.layerB_note ?? "Not run.",
            diagnosticsNote: recovery?.diagnosticsNote ?? "",
            errors: result.errors,
            limitations: ReportWriter.standardLimitations
        )
    }

    public func jsonData(_ report: FullReport) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(report)
    }

    public func htmlString(_ r: FullReport) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        var passRows = ""
        for p in r.passes {
            passRows += "<tr><td>\(p.index)</td><td>\(esc(p.pattern))</td><td>\(esc(p.bytesHuman))</td><td>\(esc(p.error ?? "—"))</td></tr>"
        }
        var limItems = ""
        for l in r.limitations { limItems += "<li>\(esc(l))</li>" }
        var errItems = ""
        if r.errors.isEmpty { errItems = "<li>None</li>" }
        else { for e in r.errors { errItems += "<li>\(esc(e))</li>" } }

        let statusColor: String
        if r.status.contains("Failed") { statusColor = "#b00020" }
        else if r.status.contains("Incomplete") { statusColor = "#b26a00" }
        else { statusColor = "#1a7f37" }

        return """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <title>\(esc(r.appName)) Report</title>
        <style>
          body { font: 14px -apple-system, Helvetica, Arial, sans-serif; margin: 32px; color: #1d1d1f; max-width: 900px; }
          h1 { font-size: 22px; } h2 { font-size: 16px; margin-top: 28px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
          table { border-collapse: collapse; width: 100%; margin-top: 8px; }
          th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #eee; font-size: 13px; }
          .status { display: inline-block; padding: 4px 12px; border-radius: 6px; color: #fff; background: \(statusColor); font-weight: 600; }
          .kv { display: grid; grid-template-columns: 260px 1fr; gap: 4px 12px; margin-top: 8px; }
          .kv div:nth-child(odd) { color: #666; }
          .warn { background: #fff8e1; border: 1px solid #ffe082; padding: 10px 14px; border-radius: 8px; margin-top: 10px; }
          code { background: #f5f5f7; padding: 1px 4px; border-radius: 4px; }
        </style></head><body>
        <h1>\(esc(r.appName)) — Operation Report</h1>
        <p><span class="status">\(esc(r.status))</span></p>
        <div class="kv">
          <div>Generated</div><div>\(esc(r.generatedAt))</div>
          <div>App version</div><div>\(esc(r.appVersion))</div>
          <div>Operating system</div><div>\(esc(r.osVersion))</div>
          <div>Volume</div><div>\(esc(r.volumeName)) (<code>\(esc(r.mountPath))</code>)</div>
          <div>Volume UUID</div><div>\(esc(r.volumeUUID ?? "unknown"))</div>
          <div>Filesystem</div><div>\(esc(r.filesystemType))</div>
          <div>Fusion Drive</div><div>\(esc(r.fusionDrive))</div>
          <div>Snapshots</div><div>\(esc(r.snapshotState))</div>
          <div>Encryption</div><div>\(esc(r.encryptionState))</div>
        </div>

        <h2>Requested operation</h2>
        <div class="kv">
          <div>Mode</div><div>\(esc(r.requestedMode))</div>
          <div>Passes</div><div>\(r.requestedPasses)</div>
          <div>Safety reserve</div><div>\(esc(r.reserveHuman))</div>
        </div>

        <h2>Results</h2>
        <div class="kv">
          <div>Cancelled by user</div><div>\(r.cancelled)</div>
          <div>Reserve breached</div><div>\(r.reserveBreached)</div>
          <div>Total logical bytes written</div><div>\(esc(r.totalLogicalHuman))</div>
          <div>Physical space consumed (measured)</div><div>\(esc(r.totalPhysicalHuman))</div>
          <div>Zero-elision suspected</div><div>\(r.zeroElisionSuspected)</div>
          <div>Cleanup succeeded</div><div>\(r.cleanupSucceeded)</div>
          <div>Leftover app-owned files</div><div>\(r.leftoverFileCount)</div>
        </div>
        <table><thead><tr><th>Pass</th><th>Pattern</th><th>Bytes written</th><th>Error</th></tr></thead>
        <tbody>\(passRows)</tbody></table>

        <h2>Recovery testing</h2>
        <div class="kv">
          <div>Layer A — logical verification</div><div>\(esc(r.recovery_layerA_note))</div>
          <div>Layer A — bytes verified</div><div>\(esc(ByteText.format(r.recovery_layerA_bytesVerified)))</div>
          <div>Layer A — mismatches</div><div>\(r.recovery_layerA_mismatches)</div>
          <div>Layer B — deleted-file recovery</div><div>\(esc(r.recovery_layerB_note))</div>
          <div>Diagnostics</div><div>\(esc(r.diagnosticsNote))</div>
        </div>

        <h2>Errors</h2><ul>\(errItems)</ul>

        <h2>Limitations &amp; honest caveats</h2>
        <div class="warn">This report is <strong>not</strong> a certificate of irrecoverability.</div>
        <ul>\(limItems)</ul>
        </body></html>
        """
    }
}
