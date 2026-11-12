/// Renders the derived profile files published to `english-profile`.
///
/// Output is byte-for-byte deterministic across platforms: fixed key order, fixed decimal
/// formatting done with integer arithmetic (no locale- or libc-dependent printf), rows in
/// rank order, "\n" line endings.
public enum ProfileFiles {
    public static let schemaVersion = 1

    /// `summary.json`: vocabulary size with interval, Word Band counts, level mastery, update time.
    public static func summaryJSON(_ p: LearnerProfile) -> String {
        func estimate(_ e: Estimate) -> String {
            "{\"estimate\": \(Int(e.estimate.rounded())), \"low\": \(Int(e.low.rounded())), \"high\": \(Int(e.high.rounded()))}"
        }
        let levels = p.levelMastery.map {
            "    {\"level\": \($0.level), \"families\": \($0.families), \"mastery\": \(fixed($0.mastery, 4))}"
        }.joined(separator: ",\n")
        let c = p.config
        return """
        {
          "schema_version": \(schemaVersion),
          "updated_at": \(quote(p.asOf)),
          "lexicon_version": \(quote(p.lexicon.version)),
          "vocab_size": {
            "families": \(estimate(p.vocabulary.families)),
            "lemmas": \(estimate(p.vocabulary.lemmas))
          },
          "band_counts": {"mastered": \(p.bandCounts.mastered), "target": \(p.bandCounts.target), "distant": \(p.bandCounts.distant)},
          "level_mastery": [
        \(levels)
          ],
          "observations": {"total": \(p.stats.total), "evidence": \(p.stats.used), "pseudowords": \(p.stats.pseudo), "false_alarms": \(p.stats.falseAlarms), "out_of_lexicon": \(p.stats.outOfLexicon), "invalid": \(p.stats.invalid)},
          "model": {"theta": \(fixed(p.theta, 4)), "slope": \(fixed(p.slope, 4)), "false_alarm_rate": \(fixed(p.falseAlarmRate, 4)), "half_life_days": \(fixed(c.halfLifeDays, 1)), "mastered_threshold": \(fixed(c.masteredThreshold, 2)), "target_window": \(c.targetWindow)}
        }

        """
    }

    /// `words.tsv`: lemma, Word Band, P, frequency rank; one row per lemma in rank order.
    public static func wordsTSV(_ p: LearnerProfile) -> String {
        var out = "lemma\tband\tp\trank\n"
        for (i, e) in p.lexicon.entries.enumerated() {
            out += "\(e.lemma)\t\(p.bands[i].rawValue)\t\(fixed(p.probabilities[i], 4))\t\(e.rank)\n"
        }
        return out
    }

    /// Formats `x` with exactly `digits` decimals, rounding half away from zero.
    public static func fixed(_ x: Double, _ digits: Int) -> String {
        guard x.isFinite else { return "0" }
        var scale = 1.0
        for _ in 0..<digits { scale *= 10 }
        let scaled = Int64((abs(x) * scale).rounded(.toNearestOrAwayFromZero))
        let negative = x < 0 && scaled != 0
        var unit: Int64 = 1
        for _ in 0..<digits { unit *= 10 }
        let whole = scaled / unit, frac = scaled % unit
        var s = (negative ? "-" : "") + String(whole)
        if digits > 0 {
            let f = String(frac)
            s += "." + String(repeating: "0", count: digits - f.count) + f
        }
        return s
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    let hex = String(ch.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }
}
