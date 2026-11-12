/// Minimal, platform-independent ISO 8601 parsing (no Foundation date APIs, so
/// macOS and Linux agree bit for bit).
public enum Timestamp {
    /// Seconds since 1970-01-01T00:00:00Z, or nil if `s` is not
    /// `YYYY-MM-DDTHH:MM:SS[.fff](Z|±HH:MM)`.
    public static func epochSeconds(_ s: String) -> Double? {
        let b = Array(s.utf8)
        guard b.count >= 20 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            guard from + len <= b.count else { return nil }
            var v = 0
            for i in from..<(from + len) {
                let c = b[i]
                guard c >= 48 && c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            return v
        }
        guard let y = num(0, 4), b[4] == 45, let mo = num(5, 2), b[7] == 45, let d = num(8, 2),
              b[10] == 84 || b[10] == 32, let h = num(11, 2), b[13] == 58, let mi = num(14, 2),
              b[16] == 58, let sec = num(17, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, sec < 61
        else { return nil }
        var i = 19
        var frac = 0.0
        if i < b.count && b[i] == 46 {
            i += 1
            var scale = 0.1
            while i < b.count, b[i] >= 48 && b[i] <= 57 {
                frac += Double(b[i] - 48) * scale
                scale /= 10
                i += 1
            }
        }
        guard i < b.count else { return nil }
        var offset = 0
        if b[i] == 90 { // Z
            guard i + 1 == b.count else { return nil }
        } else if b[i] == 43 || b[i] == 45 {
            guard i + 6 == b.count, let oh = num(i + 1, 2), b[i + 3] == 58, let om = num(i + 4, 2)
            else { return nil }
            offset = (oh * 60 + om) * 60 * (b[i] == 43 ? 1 : -1)
        } else {
            return nil
        }
        let days = daysFromCivil(y, mo, d)
        let whole = days * 86400 + h * 3600 + mi * 60 + sec - offset
        return Double(whole) + frac
    }

    /// `YYYY-MM-DDTHH:MM:SS.mmmZ` for seconds since the epoch (UTC, sub-millisecond truncated).
    public static func iso(_ epochSeconds: Double) -> String {
        let ms = Int((epochSeconds * 1000).rounded(.down))
        let secs = ms >= 0 ? ms / 1000 : (ms - 999) / 1000
        let days = secs >= 0 ? secs / 86400 : (secs - 86399) / 86400
        let sod = secs - days * 86400
        let (y, m, d) = civilFromDays(days)
        func pad(_ v: Int, _ w: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, w - s.count)) + s
        }
        return "\(pad(y, 4))-\(pad(m, 2))-\(pad(d, 2))T\(pad(sod / 3600, 2)):\(pad(sod / 60 % 60, 2)):"
            + "\(pad(sod % 60, 2)).\(pad(ms - secs * 1000, 3))Z"
    }

    /// Howard Hinnant's civil_from_days.
    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    /// Howard Hinnant's days_from_civil.
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
