# 01: 参考词库与 Profile Engine

**What to build:** 构建一份带版本号的只读词库，供 App 和 Actions 共用；再写一个纯计算的 Profile Engine，它读全部 Observation，算出 Learner Profile。这是整个系统的核心，iPhone 本地和 GitHub Actions 调用的是同一份实现。

- 词库：构建脚本合并 ECDICT（释义、音标、考试标签、lemma 映射）、BNC/COCA 25k 词族表（词频分层，构建时从官网下载，不入任何仓库）和 Wiktextract（例句、真人发音），产出一个可打包的只读词库，并带版本号。
- Profile Engine：
  - 模型：Rasch 型 `P(认识) = σ(θ − δ_w)`，δ_w 由词频等特征回归得到。每次用全部历史重新拟合，较早的作答按可调的衰减速度降权。
  - 证据：测试、抽查、复习都算。复习中"忘了"算不认识，其余三档算认识；新卡首评"太简单"算强"认识"证据。
  - 输出：每个 lemma 的 P；总词汇量 = ΣP，带 95% 区间，按 word family 报告；各频段掌握率。
  - Word Band 划分（阈值可调）：Mastered 是 P ≥ 0.9；Target 是 P < 0.9 且词频在当前词汇量往外约 2000 词以内，有活跃 Card 的词也算 Target；其余为 Distant。
  - Coverage：给一段文本，先做词形还原，再算已认识词的占比。
- 以 Swift package 形式提供，附一个命令行入口，能在 Linux 上运行，输出 `summary.json` 和 `words.tsv`。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] 构建脚本能从零生成词库；命令行能查到任意词的释义、音标、词频排名、例句；词库带版本号
- [ ] BNC/COCA 原表和 Wiktextract 原始内容都不进入仓库
- [ ] 用夹具 Observation 测试：P 随证据单调变化、Word Band 边界正确、ΣP 与区间、衰减效果、word family 折算、Coverage
- [ ] 模拟学习者测试：已知 θ 的模拟学习者做若干次短测作答后，估计词汇量落在真实值的误差范围内
- [ ] 命令行在 macOS 和 Linux 上对同一夹具输出完全相同的 `summary.json` 和 `words.tsv`
