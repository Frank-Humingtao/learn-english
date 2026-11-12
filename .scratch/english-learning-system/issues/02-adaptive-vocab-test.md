# 调研：自适应词汇量测试方法

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

有哪些成熟、可复现的词汇量估算方法（如 Vocabulary Size Test、Vocabulary Levels Test、testyourvocab 的方法、基于 IRT 的自适应测试、Yes/No 测试加伪词纠偏）？如何从词频分层的大题库里自适应抽样，在 3 到 5 分钟内估出总词汇量和各频段掌握率？如何在一两天测一次的频率下做到题目不重复、结果滚动更新而非每次从头估？如何识别猜测和过度自信？哪些方法的题库或参数公开可用？

## Answer

- 题型：每次约 80 个 Yes/No 条目（约 60 真词 + 约 20 伪词），外加 5–8 道中文四选一释义核验（从答 yes 的词里抽，带"不认识"选项），合计 3–5 分钟。完整的 VST 每题约 18 秒，放不进这个时间。
- 模型：Rasch 型 `P(认识) = σ(θ − δ_w)`，δ_w 由词频排名回归得到。总词汇量 = ΣP，频段掌握率 = 段内 P 均值，Word Band 按 P 阈值划分。
- 自适应与滚动：在 P≈0.5 附近用 Randomesque 抽从未测过的词，伪词每次现生成（Wuggy）。每次测完用全部历史作答（带时间衰减）重新拟合，不从头估。
- 纠偏：伪词 false alarm（Ag/Δm）、核验失败率、反应时、person-fit 四者叠加。Meara 发现单靠伪词不足以识别虚报。
- 公开资源：VST（含普通话双语版，可做冷启动基线）、Updated VLT 掌握线、Ehara 2018 数据、Brysbaert prevalence（CC BY 4.0）、catsim。Duolingo 和 testyourvocab 的题库不公开。

[调研笔记](../research/02-adaptive-vocab-test.md)
