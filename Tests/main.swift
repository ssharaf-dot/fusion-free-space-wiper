//
//  EngineTests.swift
//  Fusion Free Space Wiper — standalone test runner
//
//  Compiled together with the Models + Engine sources (no UI, no app main) into a
//  command-line binary. Pure-logic tests always run. Integration tests that need a
//  real writable volume run only when FFSW_TEST_MOUNT points at a disposable,
//  mounted test volume (the run_tests.sh script creates and destroys a sparse
//  disk image for this). We NEVER touch the developer's startup disk.
//
//  Exit code 0 = all passed, 1 = one or more failures.
//

import Foundation

var failures = 0
var passes = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { passes += 1; print("  ok   \(msg)") }
    else { failures += 1; print("  FAIL \(msg)") }
}
func section(_ s: String) { print("\n== \(s) ==") }

// MARK: - Pure unit tests

func testReserveMath() {
    section("Reserve policy arithmetic")
    // 1 TB drive → 10% = 100 GiB > 20 GiB floor.
    let oneTB = 1000 * Bytes.GiB
    check(ReservePolicy.recommendedReserve(totalCapacity: oneTB) == Int64(Double(oneTB) * 0.10),
          "1 TB → 10% reserve")
    // Small drive → 20 GiB floor dominates, but never below 10 GiB hard min.
    let small = 50 * Bytes.GiB
    check(ReservePolicy.recommendedReserve(totalCapacity: small) == 20 * Bytes.GiB, "50 GiB → 20 GiB floor")
    // Clamp never returns below hard minimum.
    check(ReservePolicy.clamp(1 * Bytes.GiB) == 10 * Bytes.GiB, "clamp below floor → 10 GiB")
    check(ReservePolicy.clamp(40 * Bytes.GiB) == 40 * Bytes.GiB, "clamp above floor preserved")
}

func testTestSizeConstants() {
    section("Test size constants (exact decimal bytes)")
    check(TestSize.mb100.bytes == 100_000_000, "100 MB == 100,000,000")
    check(TestSize.gb1.bytes == 1_000_000_000, "1 GB == 1,000,000,000")
    check(TestSize.gb10.bytes == 10_000_000_000, "10 GB == 10,000,000,000")
    // Config.test wires the cap through.
    let c = WipeConfiguration.test(targetMountPath: "/", expectedVolumeUUID: nil, expectedVolumeName: "x",
                                   reserveBytes: 10 * Bytes.GiB, size: .mb100)
    check(c.maxWriteBytes == 100_000_000, "config.maxWriteBytes == 100 MB")
    check(c.isTest && c.sessionKind == "test" && c.fileExtension == "wipe", "test config flags")
}

func testByteText() {
    section("Byte / duration formatting")
    check(ByteText.format(1024) == "1.00 KiB", "1024 → 1.00 KiB")
    check(ByteText.format(0) == "0 B", "0 → 0 B")
    check(ByteText.duration(65) == "1m 05s", "65s → 1m 05s")
    check(ByteText.duration(nil) == "—", "nil duration → —")
}

func testPRNGDeterminism() {
    section("PRNG determinism")
    var a = XorShift64(seed: 12345), b = XorShift64(seed: 12345)
    check(a.next() == b.next() && a.next() == b.next(), "same seed → same stream")
    var c = XorShift64(seed: 999)
    check(c.next() != a.next(), "different seed → different stream (very likely)")
}

func tmpDir() -> String {
    let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
    let d = (base as NSString).appendingPathComponent("ffsw-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

func testSessionLifecycle() {
    section("Session create / find / remove")
    let sm = SessionManager()
    let parent = tmpDir()
    defer { try? FileManager.default.removeItem(atPath: parent) }

    guard let created = try? sm.createSession(parent: parent, volumeUUID: "TEST-UUID", kind: "test") else {
        check(false, "createSession succeeded"); return
    }
    check(FileManager.default.fileExists(atPath: created.dir), "session dir exists")
    // 0700 permissions
    if let attrs = try? FileManager.default.attributesOfItem(atPath: created.dir),
       let perm = attrs[.posixPermissions] as? NSNumber {
        check(perm.int16Value == 0o700, "session dir is 0700")
    } else { check(false, "could read permissions") }

    // Add a payload file, then find + remove.
    let payload = (created.dir as NSString).appendingPathComponent("test-part-0001.wipe")
    FileManager.default.createFile(atPath: payload, contents: Data(repeating: 0, count: 1024))
    let stale = sm.findStaleSessions(parents: [parent])
    check(stale.count == 1 && stale[0].isOwnerProcessAlive, "find sees our live session")
    let rm = sm.removeSession(directory: created.dir)
    check(rm.success && rm.leftovers.isEmpty, "removeSession cleans payload + dir")
    check(!FileManager.default.fileExists(atPath: created.dir), "session dir gone")
}

func testSymlinkAttack() {
    section("Symlink / path-substitution protection")
    let sm = SessionManager()
    let parent = tmpDir()
    defer { try? FileManager.default.removeItem(atPath: parent) }

    // A canary OUTSIDE any session dir that must never be deleted/followed.
    let canary = (parent as NSString).appendingPathComponent("CANARY.txt")
    FileManager.default.createFile(atPath: canary, contents: Data("precious".utf8))

    let created = try! sm.createSession(parent: parent, volumeUUID: nil, kind: "test")
    // Plant a symlink inside the session dir pointing at the canary.
    let link = (created.dir as NSString).appendingPathComponent("evil-link")
    try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: canary)

    let rm = sm.removeSession(directory: created.dir)
    // The symlink must be left as a leftover (not followed), so removal is not a
    // clean success, and the canary must still exist with intact content.
    check(!rm.success, "removeSession refuses to follow symlink (not a clean success)")
    check(FileManager.default.fileExists(atPath: canary), "canary still exists")
    check((try? String(contentsOfFile: canary, encoding: .utf8)) == "precious", "canary content intact")

    // Manual cleanup for the test.
    try? FileManager.default.removeItem(atPath: link)
    _ = sm.removeSession(directory: created.dir)
}

func testMarkerRequiredForRemoval() {
    section("Removal requires a valid marker")
    let sm = SessionManager()
    let parent = tmpDir()
    defer { try? FileManager.default.removeItem(atPath: parent) }
    // A look-alike directory WITHOUT a marker must never be removed.
    let fake = (parent as NSString).appendingPathComponent(".FusionFreeSpaceWiper-test-notours")
    try? FileManager.default.createDirectory(atPath: fake, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: (fake as NSString).appendingPathComponent("x.wipe"), contents: Data([1,2,3]))
    let rm = sm.removeSession(directory: fake)
    check(!rm.success, "no-marker dir is NOT removed")
    check(FileManager.default.fileExists(atPath: fake), "no-marker dir still present")
}

// MARK: - Integration (needs a disposable mounted volume)

final class Collector: FreeSpaceWiperDelegate {
    var result: WipeResult?
    var maxLogicalSeen: Int64 = 0
    var done = false
    var cancelAt: Int64? = nil
    weak var engine: FreeSpaceWiper?
    func wiperDidUpdate(progress: WipeProgress) {
        maxLogicalSeen = max(maxLogicalSeen, progress.logicalBytesWritten)
        if let c = cancelAt, progress.logicalBytesWritten >= c { engine?.requestCancel() }
    }
    func wiperDidLog(_ line: String) {}
    func wiperDidFinish(result: WipeResult) { self.result = result; self.done = true }
}

func runEngine(_ cfg: WipeConfiguration, cancelAt: Int64? = nil, timeout: TimeInterval = 120) -> (Collector, FreeSpaceWiper) {
    let engine = FreeSpaceWiper()
    let col = Collector()
    col.engine = engine
    col.cancelAt = cancelAt
    engine.delegate = col
    engine.start(config: cfg)
    let deadline = Date().addingTimeInterval(timeout)
    while !col.done && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return (col, engine)
}

func countPayloadLeftovers(inParent parent: String) -> Int {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent) else { return 0 }
    return entries.filter { $0.hasPrefix(".FusionFreeSpaceWiper-") }.count
}

func testIntegration(mount: String) {
    section("Integration on disposable volume: \(mount)")
    // Lower the reserve floor for the disposable image ONLY (the shipping app
    // never does this — the production floor stays 10 GiB). Restored at the end.
    let savedFloor = ReservePolicy.hardMinimum
    ReservePolicy.hardMinimum = 1 * Bytes.GiB
    defer { ReservePolicy.hardMinimum = savedFloor }
    let testReserve = 1 * Bytes.GiB

    let inspector = VolumeInspector()
    guard let info = inspector.inspect(path: mount) else { check(false, "inspect volume"); return }
    print("  volume: \(info.name) fs=\(info.filesystemType) uuid=\(info.volumeUUID ?? "nil") avail=\(ByteText.format(info.freeCapacityRaw))")

    // Canary file OUTSIDE the session directory that must remain byte-identical.
    let canary = (mount as NSString).appendingPathComponent("USER-CANARY.txt")
    let canaryData = Data("do-not-touch-\(UUID().uuidString)".utf8)
    FileManager.default.createFile(atPath: canary, contents: canaryData)
    let before = POSIX.statfsFor(path: mount)?.availableBytes ?? 0

    // --- Strict write-limit test: cap 20 MB, tiny reserve so it can run. ---
    // We construct a low reserve directly (the volume is disposable). The clamp
    // still applies a 10 GiB floor, so the disk image must be > ~10.1 GiB.
    let cap: Int64 = 20_000_000
    let cfg = WipeConfiguration.test(targetMountPath: mount, expectedVolumeUUID: info.volumeUUID,
                                     expectedVolumeName: info.name, reserveBytes: testReserve, size: .mb100)
    var capped = cfg
    capped.maxWriteBytes = cap   // override to 20 MB for speed
    let (col, _) = runEngine(capped)
    guard let r = col.result else { check(false, "engine finished"); return }

    check(r.totalLogicalBytesWritten <= cap, "NEVER exceeded cap (\(r.totalLogicalBytesWritten) <= \(cap))")
    check(r.totalLogicalBytesWritten == cap, "reached exactly the cap")
    check(col.maxLogicalSeen <= cap, "progress never reported beyond cap")
    check(r.flushCompleted, "flush completed")
    check(r.cleanupSucceeded && r.cleanupVerified, "cleanup succeeded and verified")
    check(r.leftoverFiles.isEmpty, "no leftover app-owned files")
    check(countPayloadLeftovers(inParent: mount) == 0, "no session dirs remain on volume")

    // Canary intact.
    let canaryAfter = FileManager.default.contents(atPath: canary)
    check(canaryAfter == canaryData, "user canary file untouched (byte-identical)")

    // Disk space returned. APFS reclaims unlinked space asynchronously, so we
    // settle-poll for a few seconds and allow slack up to the payload size — the
    // spec explicitly says NOT to require byte-for-byte equality. The strong
    // cleanup signals (session dir gone, zero leftovers) are asserted above.
    var after = POSIX.statfsFor(path: mount)?.availableBytes ?? 0
    var waited = 0.0
    while abs(after - before) >= 3_000_000 && waited < 5.0 {
        Thread.sleep(forTimeInterval: 0.3); waited += 0.3
        after = POSIX.statfsFor(path: mount)?.availableBytes ?? 0
    }
    check(abs(after - before) <= cap + 8_000_000,
          "free space returned after cleanup within payload slack (Δ=\(ByteText.format(abs(after - before))), waited \(String(format: "%.1f", waited))s)")

    // --- Volume identity mismatch aborts before writing. ---
    let wrong = WipeConfiguration.test(targetMountPath: mount, expectedVolumeUUID: "WRONG-UUID-0000",
                                       expectedVolumeName: info.name, reserveBytes: testReserve, size: .mb100)
    let (col2, _) = runEngine(wrong)
    check(col2.result?.status == .failed, "identity mismatch → failed")
    check((col2.result?.totalLogicalBytesWritten ?? 1) == 0, "identity mismatch → zero bytes written")

    // --- Reserve guard: reserve above available → refuses. ---
    var hugeReserve = capped
    hugeReserve.reserveBytes = max(before + 5 * Bytes.GiB, 10 * Bytes.GiB)  // more than available
    let (col3, _) = runEngine(hugeReserve)
    check((col3.result?.totalLogicalBytesWritten ?? 1) == 0, "reserve > available → zero bytes written")

    // --- Cancellation mid-run cleans up. ---
    var bigger = cfg
    bigger.maxWriteBytes = 200_000_000   // 200 MB, cancel at ~40 MB
    let (col4, _) = runEngine(bigger, cancelAt: 40_000_000)
    check(col4.result?.cancelled == true, "cancellation observed")
    check(col4.result?.cleanupSucceeded == true, "cleanup after cancel")
    check(countPayloadLeftovers(inParent: mount) == 0, "no session dirs after cancel")

    try? FileManager.default.removeItem(atPath: canary)
}

// MARK: - Main

print("Fusion Free Space Wiper — test runner")
testReserveMath()
testTestSizeConstants()
testByteText()
testPRNGDeterminism()
testSessionLifecycle()
testSymlinkAttack()
testMarkerRequiredForRemoval()

if let mount = ProcessInfo.processInfo.environment["FFSW_TEST_MOUNT"], !mount.isEmpty {
    testIntegration(mount: mount)
} else {
    section("Integration")
    print("  SKIP  (set FFSW_TEST_MOUNT to a disposable mounted volume to run integration tests)")
}

print("\n=====================================")
print("PASSED: \(passes)   FAILED: \(failures)")
print("=====================================")
exit(failures == 0 ? 0 : 1)
