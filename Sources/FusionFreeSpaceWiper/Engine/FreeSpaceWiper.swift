//
//  FreeSpaceWiper.swift
//  Fusion Free Space Wiper
//
//  The overwrite engine. It fills filesystem-allocatable free space on ONE
//  selected, writable, mounted data volume by creating app-owned temporary files
//  inside a marked session directory, then removing them. It never formats,
//  repartitions, erases devices, or deletes user files.
//
//  Concurrency model: runs on a private serial DispatchQueue (a background
//  worker). Progress is delivered on DispatchQueue.main. No async/await is used
//  so the binary back-deploys cleanly to macOS 10.15.
//
//  Safety invariants enforced on every chunk:
//    * The target volume UUID still matches what the user confirmed.
//    * We never write past the configured reserve (and never below the 10 GiB
//      hard floor). We re-read statfs before each chunk.
//    * All writes stay inside the session directory; files are 0600, O_NOFOLLOW.
//

import Foundation

public protocol FreeSpaceWiperDelegate: AnyObject {
    func wiperDidUpdate(progress: WipeProgress)
    func wiperDidLog(_ line: String)
    func wiperDidFinish(result: WipeResult)
}

public final class FreeSpaceWiper {

    // Public control flags (thread-safe via the lock).
    private let lock = NSLock()
    private var _cancelRequested = false
    private var _pauseRequested = false

    public weak var delegate: FreeSpaceWiperDelegate?

    private let queue = DispatchQueue(label: "com.local.fusionfreespacewiper.worker")
    private let inspector = VolumeInspector()
    private let sessions = SessionManager()
    private let rollingRate = RollingRate(window: 3.0)

    public init() {}

    // MARK: - Control

    public func requestCancel() {
        lock.lock(); _cancelRequested = true; _pauseRequested = false; lock.unlock()
    }
    public func requestPause() {
        lock.lock(); _pauseRequested = true; lock.unlock()
    }
    public func requestResume() {
        lock.lock(); _pauseRequested = false; lock.unlock()
    }
    private var cancelRequested: Bool { lock.lock(); defer { lock.unlock() }; return _cancelRequested }
    private var pauseRequested: Bool { lock.lock(); defer { lock.unlock() }; return _pauseRequested }

    // MARK: - Dry run (no writes)

    public struct DryRunEstimate {
        public var writableBytes: Int64
        public var totalBytesToWrite: Int64     // across all passes
        public var reserveBytes: Int64
        public var passes: Int
        public var optimisticSeconds: Double
        public var pessimisticSeconds: Double
    }

    /// Estimate writable bytes and a wide, honest time range. Does not write.
    public func dryRun(config: WipeConfiguration) -> DryRunEstimate? {
        guard let stats = POSIX.statfsFor(path: config.targetMountPath) else { return nil }
        var writable = max(0, stats.availableBytes - config.reserveBytes)
        // Test Mode: the writable estimate is capped by the strict test limit.
        if let cap = config.maxWriteBytes { writable = min(writable, cap) }
        let total = writable * Int64(config.mode.passCount)
        // Wide throughput band for a Fusion Drive: HDD tier ~40 MB/s worst case,
        // SSD tier ~450 MB/s best case. Deliberately uncertain.
        let optimistic = Double(total) / (450.0 * 1_000_000.0)
        let pessimistic = Double(total) / (40.0 * 1_000_000.0)
        return DryRunEstimate(writableBytes: writable, totalBytesToWrite: total,
                              reserveBytes: config.reserveBytes, passes: config.mode.passCount,
                              optimisticSeconds: optimistic, pessimisticSeconds: pessimistic)
    }

    // MARK: - Run

    /// Begin a wipe on the worker queue. Returns immediately.
    public func start(config: WipeConfiguration) {
        lock.lock(); _cancelRequested = false; _pauseRequested = false; lock.unlock()
        queue.async { [weak self] in
            self?.run(config: config)
        }
    }

    private func log(_ s: String) {
        DispatchQueue.main.async { [weak self] in self?.delegate?.wiperDidLog(s) }
    }
    private func emit(_ p: WipeProgress) {
        DispatchQueue.main.async { [weak self] in self?.delegate?.wiperDidUpdate(progress: p) }
    }
    private func finish(_ r: WipeResult) {
        DispatchQueue.main.async { [weak self] in self?.delegate?.wiperDidFinish(result: r) }
    }

    private func run(config: WipeConfiguration) {
        let started = Date()
        let sessionIDHolder = SessionIDHolder()
        var passResults: [PassResult] = []
        var errors: [String] = []
        var reserveBreached = false
        var totalLogical: Int64 = 0
        var zeroElisionSuspected = false

        func fail(_ message: String, cleanupDir: String?) {
            errors.append(message)
            log("ERROR: \(message)")
            var cleanupOK = true
            var leftovers: [String] = []
            if let dir = cleanupDir {
                let r = sessions.removeSession(directory: dir)
                cleanupOK = r.success; leftovers = r.leftovers
            }
            let result = WipeResult(status: .failed, sessionID: sessionIDHolder.value,
                                    startedAt: started, finishedAt: Date(), mode: config.mode,
                                    reserveBytes: config.reserveBytes, passes: passResults,
                                    totalLogicalBytesWritten: totalLogical,
                                    totalPhysicalBytesConsumed: 0, reserveBreached: reserveBreached,
                                    cleanupSucceeded: cleanupOK, leftoverFiles: leftovers,
                                    zeroElisionSuspected: zeroElisionSuspected,
                                    errors: errors, cancelled: false)
            finish(result)
        }

        // --- Preparing -----------------------------------------------------
        emit(WipeProgress(phase: .preparing, currentPass: 0, totalPasses: config.mode.passCount,
                          logicalBytesWritten: 0, physicalBytesConsumed: 0, throughputBytesPerSec: 0,
                          freeBytesRemaining: 0, reserveBytes: config.reserveBytes,
                          elapsed: 0, estimatedRemaining: nil, note: "Validating target"))

        // Re-inspect the volume and verify identity.
        guard let info = inspector.inspect(path: config.targetMountPath) else {
            fail("Could not inspect target volume at \(config.targetMountPath).", cleanupDir: nil); return
        }
        if info.isReadOnly {
            fail(WipeError.targetIsReadOnlyOrRemovable(config.targetMountPath).description, cleanupDir: nil); return
        }
        if let expected = config.expectedVolumeUUID, let actual = info.volumeUUID, expected != actual {
            fail(WipeError.volumeIdentityMismatch(expected: expected, actual: actual).description, cleanupDir: nil); return
        }
        log("Target verified: \(info.name) [\(info.filesystemType)] UUID \(info.volumeUUID ?? "unknown")")

        // Baseline free space.
        guard let baseStats = POSIX.statfsFor(path: config.targetMountPath) else {
            fail("statfs failed on target.", cleanupDir: nil); return
        }
        let baselineAvailable = baseStats.availableBytes
        if baselineAvailable <= config.reserveBytes {
            fail(WipeError.insufficientSpaceForReserve.description, cleanupDir: nil); return
        }

        // Create session directory.
        let parent: String
        do { parent = try sessions.writableParent(forMountPath: config.targetMountPath) }
        catch { fail("\(error)", cleanupDir: nil); return }

        let sessionDir: String
        do {
            let created = try sessions.createSession(parent: parent, volumeUUID: info.volumeUUID, kind: config.sessionKind)
            sessionDir = created.dir
            sessionIDHolder.value = created.marker.sessionID
            log("Session directory: \(sessionDir)")
        } catch {
            fail("\(error)", cleanupDir: nil); return
        }

        // The planned total governs the progress bar and ETA. For Test Mode this is
        // the strict test limit; for production it is the writable space above the
        // reserve. Progress ALWAYS reflects real successful writes divided by this.
        let plannedTotal: Int64 = {
            if let cap = config.maxWriteBytes { return cap }
            return max(1, baselineAvailable - config.reserveBytes)
        }()
        rollingRate.reset()

        // --- Writing -------------------------------------------------------
        let chunkSize = Int(min(config.chunkSize, config.maxBytesPerFile))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: 64)
        defer { buffer.deallocate() }
        var prng = XorShift64(seed: UInt64(bitPattern: Int64(Date().timeIntervalSince1970.bitPattern)) ^ 0x9E3779B97F4A7C15)

        let writeStart = Date()
        var globalLogical: Int64 = 0
        let writingNote = config.isTest ? "Writing test data…" : "Overwriting free space"

        for passIndex in 0..<config.mode.passCount {
            if cancelRequested { break }
            let pattern = config.mode.pattern(forPass: passIndex)
            fillBuffer(buffer, count: chunkSize, pattern: pattern, prng: &prng)
            log("Pass \(passIndex + 1)/\(config.mode.passCount): \(describe(pattern))")

            var passBytes: Int64 = 0
            var fileIndex = 0
            var stop = false
            var passError: String? = nil

            while !stop {
                if cancelRequested { break }
                // Handle pause.
                while pauseRequested && !cancelRequested {
                    emit(progressSnapshot(phase: .writing, pass: passIndex + 1, total: config.mode.passCount,
                                          logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                                          mount: config.targetMountPath, since: writeStart, planned: plannedTotal, note: "Paused"))
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if cancelRequested { break }

                // STRICT WRITE LIMIT (Test Mode): stop as soon as the successfully
                // written byte count reaches the configured cap, BEFORE opening a
                // new file.
                if let cap = config.maxWriteBytes, globalLogical >= cap { stop = true; break }

                // Reserve check BEFORE opening/writing the next chunk.
                guard let st = POSIX.statfsFor(path: config.targetMountPath) else {
                    passError = "statfs failed mid-write."; break
                }
                let available = st.availableBytes
                if available - config.reserveBytes < Int64(chunkSize) {
                    // Not enough room for even one more chunk without crossing reserve.
                    if available < config.reserveBytes { reserveBreached = true }
                    stop = true
                    break
                }

                // Create a brand-new file inside our own session directory. O_CREAT|
                // O_TRUNC|O_NOFOLLOW: never follows a symlink, never appends to an
                // existing user file. File name uses the configured base/extension.
                let filePath = (sessionDir as NSString)
                    .appendingPathComponent(String(format: "%@%04d.%@", config.fileBaseName, fileIndex, config.fileExtension))

                let file: OverwriteFile
                do { file = try OverwriteFile(createAt: filePath) }
                catch { passError = "\(error)"; break }

                // For pass > 0 we overwrite the SAME set of files in place. On the
                // first pass we create them. Either way we write up to maxBytesPerFile.
                var fileBytes: Int64 = 0
                while fileBytes < config.maxBytesPerFile {
                    if cancelRequested { break }
                    while pauseRequested && !cancelRequested { Thread.sleep(forTimeInterval: 0.2) }
                    if cancelRequested { break }

                    // ---- STRICT WRITE LIMIT enforcement, lowest level ----
                    // remainingAllowed = testLimit - actualSuccessfullyWritten.
                    // nextWriteSize = min(normalChunk, remainingAllowed). When the
                    // cap is reached we stop immediately and proceed to flush/verify.
                    var thisChunk = chunkSize
                    if let cap = config.maxWriteBytes {
                        let remainingAllowed = cap - globalLogical
                        if remainingAllowed <= 0 { stop = true; break }
                        if remainingAllowed < Int64(thisChunk) { thisChunk = Int(remainingAllowed) }
                    }

                    guard let st2 = POSIX.statfsFor(path: config.targetMountPath) else {
                        passError = "statfs failed mid-write."; break
                    }
                    let avail2 = st2.availableBytes
                    if avail2 - config.reserveBytes < Int64(thisChunk) {
                        if avail2 < config.reserveBytes { reserveBreached = true }
                        stop = true
                        break
                    }

                    // Refresh pseudorandom content periodically so it is not a single
                    // repeating block (still non-cryptographic; that is fine for an
                    // overwrite pattern, as the README explains).
                    if pattern == .pseudorandom && (fileBytes % (64 * Int64(chunkSize)) == 0) {
                        fillBuffer(buffer, count: chunkSize, pattern: pattern, prng: &prng)
                    }

                    let outcome: OverwriteFile.WriteOutcome
                    do { outcome = try file.writeFully(buffer, count: thisChunk) }
                    catch { passError = "\(error)"; break }

                    switch outcome {
                    case .wroteAll(let n):
                        fileBytes += Int64(n); passBytes += Int64(n); globalLogical += Int64(n)
                        rollingRate.add(bytes: Int64(n))
                    case .outOfSpace(let n):
                        fileBytes += Int64(n); passBytes += Int64(n); globalLogical += Int64(n)
                        rollingRate.add(bytes: Int64(n))
                        stop = true
                    }

                    // Cap reached exactly: stop now, before any further write.
                    if let cap = config.maxWriteBytes, globalLogical >= cap { stop = true }

                    // Throttled progress (~ every chunk is fine at 8 MiB granularity).
                    emit(progressSnapshot(phase: .writing, pass: passIndex + 1, total: config.mode.passCount,
                                          logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                                          mount: config.targetMountPath, since: writeStart, planned: plannedTotal, note: writingNote))
                    if stop { break }
                }

                file.close()   // F_FULLFSYNC best-effort
                if passError != nil { break }
                fileIndex += 1
                if cancelRequested { break }
                if let cap = config.maxWriteBytes, globalLogical >= cap { stop = true }
            }

            totalLogical = globalLogical
            passResults.append(PassResult(passIndex: passIndex + 1, pattern: describe(pattern),
                                          bytesWritten: passBytes, error: passError))
            if let e = passError { errors.append("Pass \(passIndex + 1): \(e)") }
            if cancelRequested { break }
            if passError != nil { break }
            if let cap = config.maxWriteBytes, globalLogical >= cap { break }
        }

        // --- Flushing ------------------------------------------------------
        // All OverwriteFile handles were flushed (F_FULLFSYNC best-effort) and
        // closed at the end of each file above. We report flush completion only
        // when no write/IO error occurred.
        emit(progressSnapshot(phase: .flushing, pass: config.mode.passCount, total: config.mode.passCount,
                              logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                              mount: config.targetMountPath, since: writeStart, planned: plannedTotal,
                              note: config.isTest ? "Flushing data…" : "Flushing"))
        let flushCompleted = errors.isEmpty

        // --- Verify written amount ----------------------------------------
        emit(progressSnapshot(phase: .verifying, pass: config.mode.passCount, total: config.mode.passCount,
                              logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                              mount: config.targetMountPath, since: writeStart, planned: plannedTotal,
                              note: config.isTest ? "Verifying written amount…" : "Verifying"))

        // Measure physical consumption honestly: baseline available minus current
        // available (bounded at 0). If we wrote a lot of zeros but little space was
        // consumed, we flag possible zero-block elision / compression.
        var physicalConsumed: Int64 = 0
        if let nowStats = POSIX.statfsFor(path: config.targetMountPath) {
            physicalConsumed = max(0, baselineAvailable - nowStats.availableBytes)
        }
        if config.mode == .zeroSinglePass && globalLogical > 4 * Bytes.GiB {
            if physicalConsumed < globalLogical / 2 {
                zeroElisionSuspected = true
                log("NOTE: Physical space consumed (\(ByteText.format(physicalConsumed))) is well below zeros written (\(ByteText.format(globalLogical))). Possible zero-block elision/compression — see report caveats.")
            }
        }

        // --- Cleanup -------------------------------------------------------
        emit(progressSnapshot(phase: .cleaningUp, pass: config.mode.passCount, total: config.mode.passCount,
                              logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                              mount: config.targetMountPath, since: writeStart, planned: plannedTotal,
                              note: config.isTest ? "Cleaning temporary files…" : "Removing temporary files"))
        let cleanup = sessions.removeSession(directory: sessionDir)
        if cleanup.success { log("Cleanup complete. All app-owned temporary files removed.") }
        else { log("Cleanup incomplete. Leftover items: \(cleanup.leftovers.joined(separator: ", "))") }

        // --- Verify cleanup ------------------------------------------------
        emit(progressSnapshot(phase: .verifying, pass: config.mode.passCount, total: config.mode.passCount,
                              logical: globalLogical, base: baselineAvailable, reserve: config.reserveBytes,
                              mount: config.targetMountPath, since: writeStart, planned: plannedTotal,
                              note: config.isTest ? "Verifying cleanup…" : "Verifying cleanup"))
        let sessionDirGone = !FileManager.default.fileExists(atPath: sessionDir)
        let cleanupVerified = cleanup.success && cleanup.leftovers.isEmpty && sessionDirGone
        let freeAfter = POSIX.statfsFor(path: config.targetMountPath)?.availableBytes ?? 0
        log("Free before: \(ByteText.format(baselineAvailable)); free after cleanup: \(ByteText.format(freeAfter)).")

        let cancelled = cancelRequested
        let status: WipeStatus
        if !errors.isEmpty && globalLogical == 0 { status = .failed }
        else if cancelled || reserveBreached || !cleanup.success || !errors.isEmpty { status = .incomplete }
        else { status = .completedWithLimitations }

        var result = WipeResult(status: status, sessionID: sessionIDHolder.value,
                                startedAt: started, finishedAt: Date(), mode: config.mode,
                                reserveBytes: config.reserveBytes, passes: passResults,
                                totalLogicalBytesWritten: globalLogical,
                                totalPhysicalBytesConsumed: physicalConsumed,
                                reserveBreached: reserveBreached,
                                cleanupSucceeded: cleanup.success, leftoverFiles: cleanup.leftovers,
                                zeroElisionSuspected: zeroElisionSuspected,
                                errors: errors, cancelled: cancelled)
        result.isTest = config.isTest
        result.configuredMaxWriteBytes = config.maxWriteBytes
        result.flushCompleted = flushCompleted
        result.cleanupVerified = cleanupVerified
        result.freeBytesBefore = baselineAvailable
        result.freeBytesAfterCleanup = freeAfter

        let finalNote = config.isTest
            ? (cancelled ? "Test stopped." : (result.testPassed ? "Test complete." : "Test did not complete successfully."))
            : status.displayName
        emit(WipeProgress(phase: cancelled ? .cancelled : .finished, currentPass: config.mode.passCount,
                          totalPasses: config.mode.passCount, logicalBytesWritten: globalLogical,
                          physicalBytesConsumed: physicalConsumed, throughputBytesPerSec: 0,
                          freeBytesRemaining: freeAfter,
                          reserveBytes: config.reserveBytes, elapsed: Date().timeIntervalSince(writeStart),
                          estimatedRemaining: 0, note: finalNote))
        finish(result)
    }

    // MARK: - Helpers

    private func progressSnapshot(phase: WipeProgress.Phase, pass: Int, total: Int, logical: Int64,
                                  base: Int64, reserve: Int64, mount: String, since: Date,
                                  planned: Int64, note: String) -> WipeProgress {
        let elapsed = Date().timeIntervalSince(since)
        // "Current speed" is a rolling average over a short window so it does not
        // jump wildly; fall back to the cumulative average until the window fills.
        let rolling = rollingRate.bytesPerSecond()
        let cumulative = elapsed > 0.001 ? Double(logical) / elapsed : 0
        let throughput = rolling > 0 ? rolling : cumulative
        let available = POSIX.statfsFor(path: mount)?.availableBytes ?? 0

        // ETA is based on remaining bytes to the PLANNED total (test limit or
        // writable-above-reserve), divided by current throughput. If we do not yet
        // have enough data (too little elapsed / no throughput), we return nil so
        // the UI can show "Calculating…" instead of a misleading value.
        var eta: TimeInterval? = nil
        if throughput > 1 && elapsed > 1.0 {
            let remainingToPlanned = max(0, planned - logical)
            eta = Double(remainingToPlanned) / throughput
        }
        return WipeProgress(phase: phase, currentPass: pass, totalPasses: total,
                            logicalBytesWritten: logical,
                            physicalBytesConsumed: max(0, base - available),
                            throughputBytesPerSec: throughput, freeBytesRemaining: available,
                            reserveBytes: reserve, elapsed: elapsed, estimatedRemaining: eta, note: note)
    }

    private func fillBuffer(_ buffer: UnsafeMutableRawPointer, count: Int, pattern: FillPattern, prng: inout XorShift64) {
        switch pattern {
        case .fixed(let byte):
            memset(buffer, Int32(byte), count)
        case .pseudorandom:
            let words = count / 8
            let p = buffer.assumingMemoryBound(to: UInt64.self)
            for i in 0..<words { p[i] = prng.next() }
            // tail
            var rem = count - words * 8
            if rem > 0 {
                var w = prng.next()
                let tail = buffer.advanced(by: words * 8).assumingMemoryBound(to: UInt8.self)
                var idx = 0
                while rem > 0 { tail[idx] = UInt8(truncatingIfNeeded: w); w >>= 8; rem -= 1; idx += 1 }
            }
        }
    }

    private func describe(_ pattern: FillPattern) -> String {
        switch pattern {
        case .fixed(let b): return String(format: "fixed 0x%02X", b)
        case .pseudorandom: return "pseudorandom"
        }
    }
}

/// Small mutable holder so nested closures can set the session id.
private final class SessionIDHolder { var value: String = "" }

/// Rolling throughput over a short time window so "current speed" is stable.
final class RollingRate {
    private struct Sample { var t: TimeInterval; var bytes: Int64 }
    private var samples: [Sample] = []
    private let window: TimeInterval
    private let lock = NSLock()

    init(window: TimeInterval) { self.window = window }

    func reset() { lock.lock(); samples.removeAll(); lock.unlock() }

    func add(bytes: Int64) {
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        samples.append(Sample(t: now, bytes: bytes))
        let cutoff = now - window
        while let first = samples.first, first.t < cutoff { samples.removeFirst() }
        lock.unlock()
    }

    func bytesPerSecond() -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let first = samples.first, let last = samples.last else { return 0 }
        let span = last.t - first.t
        let total = samples.reduce(Int64(0)) { $0 + $1.bytes }
        // Only report once we have a little history; otherwise 0 (caller falls back).
        if span < 0.4 { return 0 }
        return Double(total) / span
    }
}

/// Non-cryptographic PRNG. Perfectly adequate for an overwrite pattern; the
/// README states plainly that overwrite randomness need not be cryptographic.
public struct XorShift64 {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed }
    public mutating func next() -> UInt64 {
        var x = state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        state = x
        return x
    }
}
