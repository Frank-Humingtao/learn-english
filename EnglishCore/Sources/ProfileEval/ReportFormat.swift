import Foundation

extension EvalReport {
    /// Pretty JSON with sorted keys (byte-identical for the same report).
    public func json() throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return String(decoding: try e.encode(self), as: UTF8.self) + "\n"
    }

    /// Markdown tables: one column per model, targets from research 07 §E.
    public func table() -> String {
        var s = "### 数据\n\n"
        s += "词库 `\(lexicon)` · \(observations) 条 Observation · 可评分真词作答 \(scorableItems) 条\n\n"
        s += "| 场次 | 开始 (UTC) | Yes/No 真词 | 核验 | 伪词 | 伪词误认率 |\n|---|---|---|---|---|---|\n"
        for x in sessions {
            s += "| \(x.id) | \(x.start.prefix(16)) | \(x.yesNo) | \(x.verify) | \(x.pseudowords) | \(pct(x.falseAlarmRate)) |\n"
        }
        s += "\n同词重测（≤7 天、不同场次的 Yes/No）：\(wordRetest.pairs) 对"
        if let a = wordRetest.agreement { s += "，一致率 \(pct(a))" }
        s += "\n\n### 指标\n\n"
        s += "| 指标 | 目标 | " + models.map(\.model).joined(separator: " | ") + " |\n"
        s += "|---|---|" + models.map { _ in "---|" }.joined() + "\n"
        func row(_ name: String, _ target: String, _ f: (ModelReport) -> String) {
            s += "| \(name) | \(target) | " + models.map(f).joined(separator: " | ") + " |\n"
        }
        func predictionRows(_ label: String, _ get: (ModelReport) -> PredictionReport?) {
            let n = models.compactMap { get($0)?.all.n }.first.map { "n=\($0)" } ?? "n=0"
            row("\(label) log loss (\(n))", "优于词频基线", { num(get($0)?.all.logLoss) })
            row("\(label) Brier", "优于词频基线", { num(get($0)?.all.brier) })
            row("\(label) AUC", "≥ .80", { num(get($0)?.all.auc) })
            row("\(label) ECE", "≤ .05", { num(get($0)?.all.ece) })
            row("\(label) 平均预测 / 实际", "接近", {
                guard let a = get($0)?.all else { return "–" }
                return "\(pct(a.meanPredicted)) / \(pct(a.observedRate))"
            })
            row("\(label) Yes/No log loss · AUC", "", { m in
                guard let y = get(m)?.yesNo else { return "–" }
                return "\(num(y.logLoss)) · \(num(y.auc)) (n=\(y.n))"
            })
            row("\(label) 核验 log loss · AUC", "", { m in
                guard let v = get(m)?.verify else { return "–" }
                return "\(num(v.logLoss)) · \(num(v.auc)) (n=\(v.n))"
            })
        }
        predictionRows("留出(按场次)", \.holdout)
        predictionRows("交叉验证(按词)", \.crossValidation)
        row("词族总数 [95%]", "", { interval($0.families) })
        row("词族区间半宽", "基线后 ≤ ±20%", { $0.families.map { "±" + pct($0.relativeHalfWidth) } ?? "–" })
        row("词族 ≤14k [95%]", "", { interval($0.coreFamilies) })
        row("词族 ≤14k 区间半宽", "", { $0.coreFamilies.map { "±" + pct($0.relativeHalfWidth) } ?? "–" })
        row("词族 >14k [95%]", "", { interval($0.tailFamilies) })
        row("lemma 总数 [95%]", "", { interval($0.lemmas) })
        row("lemma 区间半宽", "基线后 ≤ ±20%", { $0.lemmas.map { "±" + pct($0.relativeHalfWidth) } ?? "–" })
        for (k, h) in (models.first?.splitHalf ?? []).enumerated() {
            row("折半 \(h.session.prefix(15))… 词族 A / B", "差值在合并区间内", { m in
                guard k < m.splitHalf.count else { return "–" }
                let r = m.splitHalf[k]
                return "\(int(r.familiesA.estimate)) / \(int(r.familiesB.estimate)) \(r.consistent ? "✓" : "✗")"
            })
        }
        for (k, h) in (models.first?.retest ?? []).enumerated() {
            row("重测 \(h.sessionA.prefix(15))… → \(h.sessionB.prefix(15))… 词族", "差值在合并区间内", { m in
                guard k < m.retest.count else { return "–" }
                let r = m.retest[k]
                return "\(int(r.familiesA.estimate)) → \(int(r.familiesB.estimate)) \(r.consistent ? "✓" : "✗")"
            })
        }
        if models.contains(where: { $0.simulation != nil }) {
            func simRows(_ label: String, _ get: @escaping (SimulationReport) -> SimulationSummary) {
                row("模拟\(label) 真值落在区间内（词族 / lemma）", "≈ 95%", { m in
                    guard let x = m.simulation.map(get) else { return "–" }
                    return "\(pct(x.familyCoverage)) / \(pct(x.lemmaCoverage)) (\(x.learners) 人)"
                })
                row("模拟\(label) 词族相对误差 · 偏差", "", { m in
                    guard let x = m.simulation.map(get) else { return "–" }
                    return "\(pct(x.meanAbsRelativeErrorFamilies)) · \(signedPct(x.meanRelativeBiasFamilies))"
                })
            }
            simRows("（全部）", \.all)
            simRows("（诚实）", \.honest)
            simRows("（虚报）", \.overclaiming)
            row("模拟 词族区间半宽（平均）", "", { m in m.simulation.map { "±" + pct($0.all.meanRelativeHalfWidthFamilies) } ?? "–" })
            row("模拟 逐词 P_know vs 真值 log loss · ECE", "", { m in
                guard let x = m.simulation?.all else { return "–" }
                return "\(num(x.meanKnowledgeLogLoss)) · \(num(x.meanKnowledgeECE))"
            })
        }
        return s
    }
}

private func num(_ x: Double?) -> String {
    guard let x, x.isFinite else { return "–" }
    return String(format: "%.3f", x)
}

private func pct(_ x: Double?) -> String {
    guard let x, x.isFinite else { return "–" }
    return String(format: "%.1f%%", x * 100)
}

private func signedPct(_ x: Double) -> String {
    String(format: "%+.1f%%", x * 100)
}

private func int(_ x: Double) -> String { String(Int(x.rounded())) }

private func interval(_ i: Interval?) -> String {
    guard let i else { return "–" }
    return "\(int(i.estimate)) [\(int(i.low)), \(int(i.high))]"
}
