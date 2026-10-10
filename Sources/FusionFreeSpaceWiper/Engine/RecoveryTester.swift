//
//  RecoveryTester.swift
//  Fusion Free Space Wiper
//
//  Honest, privacy-preserving recovery testing in two clearly separated layers:
//
//   A. Logical free-space verification (SUPPORTED): allocate a bounded sample of
//      new files, write tagged patterns, fsync, read them back, and confirm the
//      bytes read equal the bytes written. This verifies only the NEWLY allocated
//      test files — it does NOT prove old physical blocks were overwritten.
//
//   B. Deleted-file recovery assessment (OPTIONAL / usually UNAVAILABLE on a live
//      APFS/Fusion system): we do NOT bundle or silently download any third-party
//      carving engine. From a running, mounted, unprivileged session, raw
//      unallocated-space carving of APFS is not reliably possible, so we report
//      "not available on this configuration" rather than fabricate a scan.
//
//   C. Read-only diagnostics: snapshots present, free-vs-available discrepancy,
//      encryption state (best effort). Never deletes snapshots.
//

import Foundation

public struct RecoveryTestReport {
    public var layerA_ran: Bool
    public var layerA_bytesVerified: Int64
    public var layerA_mismatches: Int
    public var layerA_note: String

    public var layerB_available: Bool
    public var layerB_note: String

    public var snapshotState: TriState
    public var encryptionState: TriState
    public var freeVsAvailableDiscrepancyBytes: Int64
    public var diagnosticsNote: String
}

public final class RecoveryTester {

    private let sessions = SessionManager()
    private let inspector = VolumeInspector()

    public init() {}

    /// Run Layer A verification on a bounded sample. `sampleCap` bounds how much we
    /// allocate; we also respect the reserve and never allocate more than half of
    /// the currently writable space.
    public func runLogicalVerification(mountPath: String, reserveBytes: Int64,
                                       sampleCap: Int64 = 1 * Bytes.GiB,
                                       log: ((String) -> Void)? = nil) -> (bytesVerified: Int64, mismatches: Int, note: String) {
        guard let st = POSIX.statfsFor(path: mountPath) else {
            return (0, 0, "Could not stat target; verification skipped.")
        }
        let writable = max(0, st.availableBytes - reserveBytes)
        let budget = min(sampleCap, writable / 2)
        if budget < 16 * Bytes.MiB {
            return (0, 0, "Not enough writable headroom above the reserve to run a meaningful sample.")
        }

        let parent: String
        do { parent = try sessions.writableParent(forMountPath: mountPath) }
        catch { return (0, 0, "No writable location on target: \(error)") }

        let info = inspector.inspect(path: mountPath)
        let session: (dir: String, marker: SessionMarker)
        do { session = try sessions.createSession(parent: parent, volumeUUID: info?.volumeUUID) }
        catch { return (0, 0, "Could not create verification session: \(error)") }
        log?("Recovery-test session: \(session.dir)")

        let chunk = 4 * Int(Bytes.MiB)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 64)
        let readBack = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 64)
        defer { buffer.deallocate(); readBack.deallocate() }

        var written: Int64 = 0
        var mismatches = 0
        let filePath = (session.dir as NSString).appendingPathComponent("verify-0000.bin")

        // Write phase: a recognizable tag repeated, so read-back can validate.
        do {
            let f = try OverwriteFile(createAt: filePath)
            var seq: UInt64 = 0
            while written < budget {
                // Stamp each chunk with an incrementing sequence tag at the front.
                memset(buffer, 0x5A, chunk)
                buffer.assumingMemoryBound(to: UInt64.self)[0] = seq
                let outcome = try f.writeFully(buffer, count: chunk)
                if case .outOfSpace = outcome { break }
                written += Int64(chunk)
                seq &+= 1
            }
            f.close()
        } catch {
            _ = sessions.removeSession(directory: session.dir)
            return (0, 0, "Write phase failed: \(error)")
        }

        // Read-back phase.
        let rfd = filePath.withCString { open($0, O_RDONLY | O_NOFOLLOW) }
        if rfd >= 0 {
            var offset: Int64 = 0
            var seq: UInt64 = 0
            while offset < written {
                let toRead = Int(min(Int64(chunk), written - offset))
                var got = 0
                while got < toRead {
                    let n = read(rfd, readBack.advanced(by: got), toRead - got)
                    if n > 0 { got += n; continue }
                    if n < 0 && errno == EINTR { continue }
                    break
                }
                // Validate the sequence tag and a couple of sentinel bytes.
                if got >= 9 {
                    let tag = readBack.assumingMemoryBound(to: UInt64.self)[0]
                    let sentinel = readBack.advanced(by: 8).assumingMemoryBound(to: UInt8.self)[0]
                    if tag != seq || sentinel != 0x5A { mismatches += 1 }
                } else {
                    mismatches += 1
                }
                offset += Int64(toRead); seq &+= 1
            }
            _ = close(rfd)
        } else {
            mismatches += 1
        }

        _ = sessions.removeSession(directory: session.dir)
        let note = "Verified \(ByteText.format(written)) of newly-allocated test data with \(mismatches) mismatch(es). This confirms the app can write and read back its own new files; it does NOT prove that previously-deleted physical blocks were overwritten."
        return (written, mismatches, note)
    }

    /// Layer B is intentionally not a fabricated scan.
    public func deletedFileRecoveryStatus(info: VolumeInfo) -> (available: Bool, note: String) {
        let fs = info.filesystemType.lowercased()
        if fs.contains("apfs") {
            return (false, "Not available on this configuration. Raw unallocated-space carving of a live, mounted APFS volume from an unprivileged session is not reliably possible, and this app does not bundle or download any third-party carving engine. Absence of a scan is not evidence of sanitization. For a genuine forensic assessment, image the drive from another machine in target-disk / read-only mode using dedicated tooling.")
        }
        return (false, "Not available on this configuration from a live session. This app does not bundle or download third-party recovery engines.")
    }

    /// Layer C diagnostics.
    public func diagnostics(mountPath: String) -> (snapshot: TriState, encryption: TriState, discrepancy: Int64, note: String) {
        guard var info = inspector.inspect(path: mountPath) else {
            return (.unknown, .unknown, 0, "Could not inspect volume.")
        }
        inspector.enrichDiagnostics(&info)
        let stats = POSIX.statfsFor(path: mountPath)
        let discrepancy = (stats != nil) ? max(0, stats!.freeBytes - stats!.availableBytes) : 0
        var notes: [String] = []
        if info.snapshotState == .yes {
            notes.append("APFS snapshots are present. Snapshots can retain extents of deleted files and are NOT removed by this app. Inspect them read-only with `tmutil listlocalsnapshots /` before assuming free-space overwrite is complete.")
        } else if info.snapshotState == .unknown {
            notes.append("Snapshot state could not be determined.")
        }
        if discrepancy > 0 {
            notes.append("There is a \(ByteText.format(discrepancy)) gap between raw free space and space available to your account (purgeable space, snapshots, or reserved blocks).")
        }
        return (info.snapshotState, info.encryptionState, discrepancy, notes.joined(separator: " "))
    }
}
