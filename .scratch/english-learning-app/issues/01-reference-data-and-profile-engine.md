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

**Status:** resolved

- [x] 构建脚本能从零生成词库；命令行能查到任意词的释义、音标、词频排名、例句；词库带版本号
- [x] BNC/COCA 原表和 Wiktextract 原始内容都不进入仓库
- [x] 用夹具 Observation 测试：P 随证据单调变化、Word Band 边界正确、ΣP 与区间、衰减效果、word family 折算、Coverage
- [x] 模拟学习者测试：已知 θ 的模拟学习者做若干次短测作答后，估计词汇量落在真实值的误差范围内
- [ ] 命令行在 macOS 和 Linux 上对同一夹具输出完全相同的 `summary.json` 和 `words.tsv`

## Comments

**已完成（agent）**

- `tools/lexicon-build/build_lexicon.py`（`python3 -I tools/lexicon-build/build_lexicon.py --download`）：下载 BNC/COCA basewords 1.3.0（Word Family Finder）、ECDICT `ecdict.csv` + `lemma.en.txt`、kaikki 英语 Wiktextract 到 gitignored 的 `tools/lexicon-build/cache/`，输出 `meta.json`（版本号 `lex-<内容哈希>`）、`words.tsv`、`forms.tsv`、`supplementary.txt`。全量结果：25,000 词族、43,028 lemma、42,938 个词形映射。单元测试 `tools/lexicon-build/test_build_lexicon.py`。
  - 从零构建已实测（空 cache + `--download`）。Wiktextract 全文件 3.4GB，本机下载需约 2 小时，所以只用前 21,000 行（约 600MB）验证了流式抽取：3,816 个 lemma 有例句、5,531 个有音频。全量跑只是时间问题，不用改代码。没有例句的词由 App 端兜底。
  - lemma 排名按「1000 词族级别 → 词形合计频次」排序；词族排名按「级别 → 词族总频次」排序。补充表 31–35（专名、边缘词、复合词、缩略词）只用于 Coverage，一律算作认识。
  - 仓库里只提交了 `EnglishCore/Fixtures/lexicon/`，这是 `--sample-every 50 --wiktextract-limit 19000` 生成的切片，取 1/50 的词族，补充表也按 1/50 抽样，保留真实排名。原表和 Wiktextract 原文都不入库。
- `EnglishCore/`（Swift package，零第三方依赖）：`CoreModels`（Observation JSONL 格式、跨平台 ISO 8601 解析）、`Lexicon`（加载与词形还原查询）、`ProfileEngine`（纯计算）、`ProfileEngineCLI` + 可执行文件 `profile-engine`，子命令有 `profile`、`lookup`、`coverage`、`version`。
  - 模型：`P = σ(θ − slope·ln(rank/1000) + u_w)`。θ 和 slope 对全部按时间衰减后的证据做 MAP 拟合（默认半衰期 180 天，可调）。观测到的词另有自己的偏差 u_w，作为直接证据。Yes/No 题按 `g + (1−g−s)σ` 建模，猜测率 g 由假词误认率估计，失误率 s 默认 0.03。
  - 证据权重：「太简单」首评 4 倍，释义核验 1.5 倍。
  - 词族 P 取族内各 lemma 的最大值。95% 区间 = θ/slope 参数不确定性（delta 法）+ Bernoulli 方差。
  - 活跃卡由 review 记录推出：首评 easy 或忘了 ≥8 次的不算。调用方也可以直接传入活跃卡集合。
- 测试（`swift test --package-path EnglishCore`，31 个）：证据单调性、复习四档、「太简单」首评、假词纠偏、衰减及其可调性、ΣP 与区间收窄、词族折算、Word Band 边界与阈值可调、频段掌握率、Coverage（词形还原、专名、越界词），以及 4 个已知 θ 的模拟学习者（基线 150 题 + 10 次短测，含 25% 假词、3% 失误）。模拟学习者的估计误差都在 15% 以内，真值落在 95% 区间内。
- 确定性：输出不用 Foundation 日期 API 和 printf，小数用整数运算定长格式化，行按 rank 排序，键顺序固定，换行为 `\n`。`EnglishCore/Fixtures/expected/` 是 macOS 上生成的金标准，`CLITests` 逐字节比对。

**未验证**

- Linux 一致性：本机没有 docker 或 Linux。已新增 `.github/workflows/englishcore.yml`，在 `swift:6.0` 容器里跑同一个金标准测试，CI 变绿即可勾选。剩余风险是 libm 的 exp/log 在 glibc 和 Darwin 上最后一位可能不同，极少数情况下第 4 位小数会翻转；遇到时可以改为输出 3 位小数。

- Orchestrator (2026-11-13): resolved on `integration/english-learning-app`. The macOS/Linux parity box stays open until `.github/workflows/englishcore.yml` runs green on GitHub (no Linux runner locally). Code-review fixes (merge 20572db) pinned lexicon sources and made the lexicon version independent of Wiktextract columns.
