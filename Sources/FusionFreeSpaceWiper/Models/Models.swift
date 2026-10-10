//
//  Models.swift
//  Fusion Free Space Wiper
//
//  Plain value types shared across the engine and UI. No AppKit dependency here
//  so the engine can be unit-tested without a running NSApplication.
//
//  Target: macOS 10.15 (Catalina), x86_64. Swift 5 language mode, no concurrency
//  runtime features (async/await) so the binary back-deploys cleanly to 10.15.
//

import Foundation

// MARK: - Byte constants (all arithmetic is explicit and 64-bit)

public enum Bytes {
    public static let KiB: Int64 = 1024
    public static let MiB: Int64 = 1024 * 1024
    public static let GiB: Int64 = 1024 * 1024 * 1024
}

/// Decimal (SI) byte constants used for Test Mode targets. The specification
/// defines the 100 MB test as exactly 100,000,000 bytes, so Test Mode uses
/// decimal units throughout for its limit and its MB/s throughput display.
public enum DecimalBytes {
    public static let MB: Int64 = 1_000_000
    public static let GB: Int64 = 1_000_000_000
}

/// The three fixed Test Mode sizes. The `bytes` value is the STRICT maximum
/// overwrite payload the engine is permitted to write for that test.
public enum TestSize: String, CaseIterable {
    case mb100
    case gb1
    case gb10

    public var bytes: Int64 {
        switch self {
        case .mb100: return 100 * DecimalBytes.MB   // 100,000,000
        case .gb1:   return 1 * DecimalBytes.GB     // 1,000,000,000
        case .gb10:  return 10 * DecimalBytes.GB    // 10,000,000,000
        }
    }

    public var shortLabel: String {
        switch self {
        case .mb100: return "100 MB"
        case .gb1:   return "1 GB"
        case .gb10:  return "10 GB"
        }
    }

    public var menuTitle: String {
        switch self {
        case .mb100: return "100 MB — Quick Test"
        case .gb1:   return "1 GB — Standard Test"
        case .gb10:  return "10 GB — Extended Test"
        }
    }

    public var subtitle: String {
        switch self {
        case .mb100: return "Recommended first test. Verifies file creation, actual writing, progress and cleanup."
        case .gb1:   return "Recommended after the 100 MB test succeeds. Longer run gives more meaningful write-speed and ETA."
        case .gb10:  return "Optional final check before a full wipe. Same production write loop, stopped after 10 GB."
        }
    }
}

// MARK: - Wipe mode

/// The overwrite strategy. Deliberately conservative defaults. None of these
/// modes claim physical-sector sanitization; see README for the honest threat model.
public enum WipeMode: String, CaseIterable {
    /// Single pass of 0x00. Default. Fast, low wear.
    case zeroSinglePass
    /// Single pass of a non-cryptographic pseudorandom pattern. Avoids any
    /// possible zero-block elision by the filesystem.
    case randomSinglePass
    /// Advanced: 0x00, then 0xFF, then pseudorandom, over the SAME files in place.
    case threePass

    public var displayName: String {
        switch self {
        case .zeroSinglePass:   return "Single pass — zeros (0x00)"
        case .randomSinglePass: return "Single pass — pseudorandom pattern"
        case .threePass:        return "Three passes — 0x00, 0xFF, pseudorandom (advanced)"
        }
    }

    public var passCount: Int {
        switch self {
        case .zeroSinglePass, .randomSinglePass: return 1
        case .threePass:                         return 3
        }
    }

    /// Pattern for a given zero-based pass index.
    public func pattern(forPass pass: Int) -> FillPattern {
        switch self {
        case .zeroSinglePass:   return .fixed(0x00)
        case .randomSinglePass: return .pseudorandom
        case .threePass:
            switch pass {
            case 0:  return .fixed(0x00)
            case 1:  return .fixed(0xFF)
            default: return .pseudorandom
            }
        }
    }
}

public enum FillPattern: Equatable {
    case fixed(UInt8)
    case pseudorandom
}

// MARK: - Volume information (read-only snapshot)

public struct VolumeInfo {
    public var name: String
    public var mountPath: String
    public var volumeUUID: String?
    public var filesystemType: String        // e.g. "apfs", "hfs"
    public var totalCapacity: Int64
    public var availableCapacity: Int64       // available to this process (important-usage)
    public var freeCapacityRaw: Int64         // statfs f_bavail * f_frsize
    public var isInternal: Bool?
    public var isRemovable: Bool?
    public var isReadOnly: Bool
    public var isBrowsable: Bool

    // Best-effort, may be nil/unknown. Never used to make destructive decisions.
    public var fusionDriveState: TriState
    public var snapshotState: TriState
    public var encryptionState: TriState

    public init(name: String, mountPath: String, volumeUUID: String?, filesystemType: String,
                totalCapacity: Int64, availableCapacity: Int64, freeCapacityRaw: Int64,
                isInternal: Bool?, isRemovable: Bool?, isReadOnly: Bool, isBrowsable: Bool,
                fusionDriveState: TriState = .unknown,
                snapshotState: TriState = .unknown,
                encryptionState: TriState = .unknown) {
        self.name = name
        self.mountPath = mountPath
        self.volumeUUID = volumeUUID
        self.filesystemType = filesystemType
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.freeCapacityRaw = freeCapacityRaw
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isReadOnly = isReadOnly
        self.isBrowsable = isBrowsable
        self.fusionDriveState = fusionDriveState
        self.snapshotState = snapshotState
        self.encryptionState = encryptionState
    }
}

/// Honest three-valued logic for facts we cannot always determine from a live,
/// unprivileged, running macOS session.
public enum TriState: Equatable {
    case yes
    case no
    case unknown

    public var label: String {
        switch self {
        case .yes:     return "Yes"
        case .no:      return "No"
        case .unknown: return "Unknown / not determinable"
        }
    }
}

// MARK: - Reserve policy

public struct ReservePolicy {
    /// Hard floor. The app will never write past leaving at least this much free.
    /// This is a `var` ONLY so the test harness can lower it when exercising the
    /// engine on a small disposable disk image; the shipping application never
    /// mutates it, so in normal use the floor is a firm 10 GiB.
    public static var hardMinimum: Int64 = 10 * Bytes.GiB
    /// Absolute default floor before percentage.
    public static let defaultFloor: Int64 = 20 * Bytes.GiB
    /// Fraction of total capacity to reserve.
    public static let capacityFraction: Double = 0.10

    /// Conservative default reserve: max(20 GiB, 10% of capacity), never below 10 GiB.
    public static func recommendedReserve(totalCapacity: Int64) -> Int64 {
        let byFraction = Int64(Double(totalCapacity) * capacityFraction)
        let base = max(defaultFloor, byFraction)
        return max(base, hardMinimum)
    }

    /// Clamp a user-supplied reserve so it can never go below the hard minimum.
    public static func clamp(_ requested: Int64) -> Int64 {
        return max(requested, hardMinimum)
    }
}

// MARK: - Wipe configuration

public struct WipeConfiguration {
    public var targetMountPath: String
    public var expectedVolumeUUID: String?
    public var expectedVolumeName: String
    public var mode: WipeMode
    public var reserveBytes: Int64
    public var chunkSize: Int64
    public var maxBytesPerFile: Int64

    /// STRICT maximum overwrite payload the engine may write, in bytes, summed
    /// across all passes. `nil` means "no explicit cap — governed only by the
    /// safety reserve" (production full-wipe). Test Mode sets this to the exact
    /// test size. The engine enforces it at the lowest level of the write loop:
    /// before every write it computes `min(chunkSize, cap - bytesWrittenSoFar)`.
    public var maxWriteBytes: Int64?

    /// Marks this as a Test Mode run (affects session naming and reporting only;
    /// the actual write/flush/cleanup code path is identical to production).
    public var isTest: Bool

    /// Session directory kind label and temp-file naming.
    public var sessionKind: String       // "test" or "wipe"
    public var fileBaseName: String      // e.g. "test-part-" or "overwrite-"
    public var fileExtension: String     // e.g. "wipe" or "bin"

    public init(targetMountPath: String,
                expectedVolumeUUID: String?,
                expectedVolumeName: String,
                mode: WipeMode,
                reserveBytes: Int64,
                chunkSize: Int64 = 8 * Bytes.MiB,
                maxBytesPerFile: Int64 = 2 * Bytes.GiB,
                maxWriteBytes: Int64? = nil,
                isTest: Bool = false) {
        self.targetMountPath = targetMountPath
        self.expectedVolumeUUID = expectedVolumeUUID
        self.expectedVolumeName = expectedVolumeName
        self.mode = mode
        self.reserveBytes = ReservePolicy.clamp(reserveBytes)
        self.chunkSize = chunkSize
        self.maxBytesPerFile = maxBytesPerFile
        self.maxWriteBytes = maxWriteBytes
        self.isTest = isTest
        self.sessionKind = isTest ? "test" : "wipe"
        self.fileBaseName = isTest ? "test-part-" : "overwrite-"
        self.fileExtension = isTest ? "wipe" : "bin"
    }

    /// Convenience constructor for a Test Mode run of a given size.
    public static func test(targetMountPath: String, expectedVolumeUUID: String?,
                            expectedVolumeName: String, reserveBytes: Int64, size: TestSize) -> WipeConfiguration {
        return WipeConfiguration(targetMountPath: targetMountPath,
                                 expectedVolumeUUID: expectedVolumeUUID,
                                 expectedVolumeName: expectedVolumeName,
                                 mode: .zeroSinglePass,
                                 reserveBytes: reserveBytes,
                                 maxWriteBytes: size.bytes,
                                 isTest: true)
    }
}

// MARK: - Live progress

public struct WipeProgress {
    public var phase: Phase
    public var currentPass: Int          // 1-based for display
    public var totalPasses: Int
    public var logicalBytesWritten: Int64
    public var physicalBytesConsumed: Int64   // measured via statfs delta (honest)
    public var throughputBytesPerSec: Double
    public var freeBytesRemaining: Int64
    public var reserveBytes: Int64
    public var elapsed: TimeInterval
    public var estimatedRemaining: TimeInterval?
    public var note: String

    public enum Phase: Equatable {
        case idle
        case preparing
        case writing
        case flushing
        case verifying
        case cleaningUp
        case finished
        case cancelled
        case failed
    }

    public static var idle: WipeProgress {
        WipeProgress(phase: .idle, currentPass: 0, totalPasses: 0,
                     logicalBytesWritten: 0, physicalBytesConsumed: 0,
                     throughputBytesPerSec: 0, freeBytesRemaining: 0,
                     reserveBytes: 0, elapsed: 0, estimatedRemaining: nil, note: "")
    }
}

// MARK: - Result / status

public enum WipeStatus: String {
    case completedWithLimitations
    case incomplete
    case failed

    public var displayName: String {
        switch self {
        case .completedWithLimitations: return "Completed (with limitations)"
        case .incomplete:               return "Incomplete"
        case .failed:                   return "Failed"
        }
    }
}

public struct PassResult {
    public var passIndex: Int            // 1-based
    public var pattern: String
    public var bytesWritten: Int64
    public var error: String?
    public init(passIndex: Int, pattern: String, bytesWritten: Int64, error: String?) {
        self.passIndex = passIndex; self.pattern = pattern
        self.bytesWritten = bytesWritten; self.error = error
    }
}

public struct WipeResult {
    public var status: WipeStatus
    public var sessionID: String
    public var startedAt: Date
    public var finishedAt: Date
    public var mode: WipeMode
    public var reserveBytes: Int64
    public var passes: [PassResult]
    public var totalLogicalBytesWritten: Int64
    public var totalPhysicalBytesConsumed: Int64
    public var reserveBreached: Bool
    public var cleanupSucceeded: Bool
    public var leftoverFiles: [String]
    public var zeroElisionSuspected: Bool
    public var errors: [String]
    public var cancelled: Bool

    // Test Mode context
    public var isTest: Bool = false
    public var configuredMaxWriteBytes: Int64? = nil
    public var flushCompleted: Bool = false
    public var cleanupVerified: Bool = false
    public var freeBytesBefore: Int64 = 0
    public var freeBytesAfterCleanup: Int64 = 0

    public var averageThroughput: Double {
        let elapsed = finishedAt.timeIntervalSince(startedAt)
        return elapsed > 0.001 ? Double(totalLogicalBytesWritten) / elapsed : 0
    }

    /// Did the run reach its configured target (within a tiny tolerance)?
    public var reachedTarget: Bool {
        guard let cap = configuredMaxWriteBytes else { return true }
        return totalLogicalBytesWritten >= cap    // engine clamps exactly to cap
    }

    /// Test Mode pass/fail evaluation. A pass requires: not cancelled, no errors,
    /// target reached, reserve not breached, flush done, cleanup succeeded and
    /// verified with zero leftover app-owned files.
    public var testPassed: Bool {
        guard isTest else { return false }
        return !cancelled && errors.isEmpty && reachedTarget && !reserveBreached
            && flushCompleted && cleanupSucceeded && cleanupVerified && leftoverFiles.isEmpty
    }

    /// Human-readable failing stage for a test that did not pass (nil if passed/cancelled).
    public var failingStage: String? {
        guard isTest, !testPassed, !cancelled else { return nil }
        if !errors.isEmpty { return "Write/flush failed" }
        if reserveBreached && !reachedTarget { return "Unexpected free-space condition (stopped at safety reserve before reaching the test target)" }
        if !reachedTarget { return "Write did not reach the test target" }
        if !flushCompleted { return "Flush failed" }
        if !cleanupSucceeded || !leftoverFiles.isEmpty { return "Cleanup failed" }
        if !cleanupVerified { return "Cleanup verification failed" }
        return "Unknown failure"
    }
}

// MARK: - Errors

public enum WipeError: Error, CustomStringConvertible {
    case volumeIdentityMismatch(expected: String, actual: String)
    case targetNotWritable(String)
    case targetIsReadOnlyOrRemovable(String)
    case cannotCreateSession(String)
    case ioError(String)
    case insufficientSpaceForReserve
    case internalConsistency(String)

    public var description: String {
        switch self {
        case .volumeIdentityMismatch(let e, let a):
            return "Volume identity check failed. Expected UUID \(e) but found \(a). Aborting for safety."
        case .targetNotWritable(let p):
            return "Target directory is not writable: \(p)"
        case .targetIsReadOnlyOrRemovable(let p):
            return "Refusing to operate on a read-only or removable target by default: \(p)"
        case .cannotCreateSession(let m):
            return "Could not create the app-owned session directory: \(m)"
        case .ioError(let m):
            return "I/O error: \(m)"
        case .insufficientSpaceForReserve:
            return "Available space is at or below the configured safety reserve. Nothing to do."
        case .internalConsistency(let m):
            return "Internal consistency error: \(m)"
        }
    }
}
