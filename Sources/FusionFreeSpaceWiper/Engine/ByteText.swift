//
//  ByteText.swift
//  Fusion Free Space Wiper
//
//  Deterministic byte / duration formatting (binary units) that does not depend
//  on locale-specific ByteCountFormatter behavior, so tests are stable.
//

import Foundation

public enum ByteText {
    public static func format(_ bytes: Int64) -> String {
        if bytes < 0 { return "-" + format(-bytes) }
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
        var value = Double(bytes)
        var i = 0
        while value >= 1024 && i < units.count - 1 { value /= 1024; i += 1 }
        if i == 0 { return "\(bytes) B" }
        return String(format: "%.2f %@", value, units[i])
    }

    public static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 { return "—" }
        return format(Int64(bytesPerSec)) + "/s"
    }

    public static func duration(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "—" }
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, sec) }
        if m > 0 { return String(format: "%dm %02ds", m, sec) }
        return String(format: "%ds", sec)
    }
}
