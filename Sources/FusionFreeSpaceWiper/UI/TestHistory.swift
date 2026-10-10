//
//  TestHistory.swift
//  Fusion Free Space Wiper
//
//  Lightweight, persistent record of pre-wipe test outcomes (informational only).
//  A passed test is NOT treated as an absolute guarantee of production safety.
//

import Foundation

struct TestOutcome {
    var passed: Bool
    var date: Date
    var averageThroughput: Double
    var bytesWritten: Int64
}

final class TestHistory {
    static let shared = TestHistory()
    private let defaults = UserDefaults.standard

    private func key(_ size: TestSize) -> String { "testOutcome.\(size.rawValue)" }

    func record(_ size: TestSize, outcome: TestOutcome) {
        let dict: [String: Any] = [
            "passed": outcome.passed,
            "date": outcome.date.timeIntervalSince1970,
            "rate": outcome.averageThroughput,
            "bytes": outcome.bytesWritten,
        ]
        defaults.set(dict, forKey: key(size))
    }

    func outcome(_ size: TestSize) -> TestOutcome? {
        guard let d = defaults.dictionary(forKey: key(size)) else { return nil }
        guard let passed = d["passed"] as? Bool, let ts = d["date"] as? Double else { return nil }
        return TestOutcome(passed: passed, date: Date(timeIntervalSince1970: ts),
                           averageThroughput: (d["rate"] as? Double) ?? 0,
                           bytesWritten: (d["bytes"] as? Int64) ?? Int64((d["bytes"] as? Int) ?? 0))
    }

    /// Has the 100 MB quick test passed at least once?
    var quickTestPassed: Bool { outcome(.mb100)?.passed == true }
    /// Did the most recent 100 MB test fail?
    var quickTestFailed: Bool { outcome(.mb100)?.passed == false }

    func summaryLine(_ size: TestSize) -> String {
        guard let o = outcome(size) else { return "\(size.shortLabel)   Not Run" }
        let mark = o.passed ? "✓ Passed" : "✗ Failed"
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        let rate = o.averageThroughput > 0 ? " · \(ByteText.rate(o.averageThroughput))" : ""
        return "\(size.shortLabel)   \(mark)   \(df.string(from: o.date))\(rate)"
    }
}
