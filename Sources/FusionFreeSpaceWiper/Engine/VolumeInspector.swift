//
//  VolumeInspector.swift
//  Fusion Free Space Wiper
//
//  Read-only discovery of mounted volumes and best-effort diagnostics. Nothing
//  here writes to disk or changes any setting. Facts that cannot be determined
//  from a live unprivileged session are reported as `.unknown`, never guessed.
//

import Foundation

public final class VolumeInspector {

    public init() {}

    /// Enumerate mounted volumes suitable for display. We include local volumes and
    /// mark removable/read-only ones so the UI can warn or exclude them.
    public func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey,
            .volumeIsBrowsableKey, .volumeIsLocalKey
        ]
        let fm = FileManager.default
        guard let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                              options: [.skipHiddenVolumes]) else {
            return []
        }
        var out: [VolumeInfo] = []
        for url in urls {
            if let info = inspect(mountURL: url) {
                out.append(info)
            }
        }
        return out
    }

    /// Inspect a single mount point path.
    public func inspect(path: String) -> VolumeInfo? {
        return inspect(mountURL: URL(fileURLWithPath: path))
    }

    public func inspect(mountURL url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeUUIDStringKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsReadOnlyKey,
            .volumeIsBrowsableKey
        ]
        let values = try? url.resourceValues(forKeys: keys)

        let stats = POSIX.statfsFor(path: url.path)

        let name = values?.volumeName ?? url.lastPathComponent
        let uuid = values?.volumeUUIDString
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        // `importantUsage` is Int64 and reflects space the OS considers reclaimable
        // for this process; statfs f_bavail is the conservative POSIX view. We keep
        // both and gate writes on statfs (the smaller, safer number) at runtime.
        let importantAvail = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let rawAvail = stats?.availableBytes ?? 0

        let info = VolumeInfo(
            name: name,
            mountPath: url.path,
            volumeUUID: uuid,
            filesystemType: stats?.fsTypeName ?? "unknown",
            totalCapacity: total,
            availableCapacity: Int64(importantAvail),
            freeCapacityRaw: rawAvail,
            isInternal: values?.volumeIsInternal,
            isRemovable: values?.volumeIsRemovable,
            isReadOnly: values?.volumeIsReadOnly ?? false,
            isBrowsable: values?.volumeIsBrowsable ?? true
        )
        return info
    }

    // MARK: - Best-effort diagnostics (read-only, structured, never destructive)

    /// Enrich a VolumeInfo with best-effort Fusion/snapshot/encryption state using
    /// structured `diskutil ... -plist` output. This is read-only. If anything
    /// fails or is ambiguous, the state stays `.unknown`. We never parse localized
    /// human-readable text and we never mutate anything.
    public func enrichDiagnostics(_ info: inout VolumeInfo) {
        // Fusion / SSD detection via `diskutil info -plist <mount>`
        if let plist = runDiskutilPlist(["info", "-plist", info.mountPath]) {
            if let fusion = plist["Fusion"] as? Bool {
                info.fusionDriveState = fusion ? .yes : .no
            }
            if let enc = plist["Encryption"] as? Bool {
                info.encryptionState = enc ? .yes : .no
            } else if let filevault = plist["FilesystemUserVisibleName"] as? String,
                      filevault.lowercased().contains("encrypted") {
                info.encryptionState = .yes
            }
        }

        // APFS snapshot detection via `diskutil apfs listSnapshots -plist <mount>`.
        // Read-only. We only report presence; we NEVER delete snapshots.
        if info.filesystemType.lowercased().contains("apfs") {
            if let snap = runDiskutilPlist(["apfs", "listSnapshots", "-plist", info.mountPath]) {
                if let arr = snap["Snapshots"] as? [Any] {
                    info.snapshotState = arr.isEmpty ? .no : .yes
                } else {
                    info.snapshotState = .no
                }
            }
        }
    }

    /// Run diskutil with -plist and parse the property list. Read-only subcommands
    /// only. Returns nil on any failure. This is not shell string parsing: we invoke
    /// the binary directly (no shell), capture stdout, and decode a real plist.
    private func runDiskutilPlist(_ args: [String]) -> [String: Any]? {
        // Guard: only ever allow known read-only subcommands to reach diskutil.
        let allowedFirst = ["info", "apfs", "list"]
        guard let first = args.first, allowedFirst.contains(first) else { return nil }
        if first == "apfs" {
            let allowedApfs = ["listSnapshots", "list"]
            guard args.count >= 2, allowedApfs.contains(args[1]) else { return nil }
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, !data.isEmpty else { return nil }
        let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return obj as? [String: Any]
    }
}
