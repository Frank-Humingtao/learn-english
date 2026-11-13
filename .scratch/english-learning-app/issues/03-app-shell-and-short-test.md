# 03: App 骨架与短测

Status: resolved

**What to build:** 学习者打开 App，看到"学习 / 测试 / 进度 / 设置"四个标签，能在"测试"标签完成一次完整的 3 到 5 分钟短测，并看到本地算出的结果。这是 App 的主干。

- SwiftUI App 壳：底部标签栏四个标签，测试和复习是全屏流程（以原型 `.scratch/english-learning-system/prototypes/11-app-screens/` 的方案 A 为准）。
- Test Engine：
  - 在 P≈0.5 附近随机抽从未测过的真词；
  - 每次现生成假词，约占 Yes/No 题的四分之一；
  - 约 10% 的题抽查 Mastered 词；
  - 另有 5 到 8 道中文四选一释义核验题，从答"认识"的词里抽，带"不认识"选项，干扰项取自词典中同词性、词频相近的其他词的中文释义。
- 每作答一题就写一条 Observation 到本地 SQLite（通过 GRDB），字段是 lemma、时间、来源、结果、反应时、会话编号，并标出假词。
- 结果页：估计词汇量及范围、较上次的变化、新发现的 Target 词数、抽查对错、假词误认数。数字由 Profile Engine 在本机计算。
- 测试流程左上角 ✕ 可以退出；当天已测过也能再测。

**Blocked by:** 01


- [x] 在模拟器里能从"测试"标签完整做完一次短测并看到结果页
- [x] 选题测试：题目集中在 P≈0.5 附近、不重复已测词、假词和抽查比例正确、干扰项来自同词性同频段
- [x] 每题作答都落成一条本地 Observation，退出 App 后仍在
- [x] 结果页数字与对同一组 Observation 运行 Profile Engine 命令行的结果一致

## Comments

**已完成（agent）**

- `EnglishCore` 新增纯逻辑目标 `TestEngine`（`swift test` 共 14 个新测试）：
  - `TestSession(lexicon:profile:history:config:sessionID:seed:)`：开局按当前 Profile 一次性定好 Yes/No 题（`TestConfig.short` = 80 题：52 真词 + 20 假词 + 8 抽查），真词取「从未有过 test/spotcheck/verify/review 证据、|P−0.5| 最小的 3 倍候选」里随机抽（Randomesque）。Yes/No 做完后，从本次答「认识」的词里抽 6 道中文四选一（UI 另加「不认识」）。`answer(_:rtMs:at:)` 每题返回一条 Observation（lemma、ts、source、result、rt_ms、session、pseudo、lexicon）。会话可 Codable 编码，供 04 断点续测。种子固定则题目固定。
  - 假词：类 Wuggy 规则（`Pseudowords`），把真词切成辅音/元音簇，替换 1–2 个同类、同位置且相邻簇组合在词库里出现过的簇；排除词库词、所有词形、补充表和历史上用过的假词。
  - 释义核验：`MeaningChecks.gloss` 从 ECDICT 中文释义取首个非领域行，词性来自行首缩写（词库 `pos` 列为空）；干扰项取同词性、频率排名最近的 8 个词中随机 3 个。
  - `TestResult`：对「历史 + 本次」跑 `ProfileEngine.compute`（与 CLI 默认参数一致）给出词族估计和 95% 区间、较测前的变化（测前无证据时为空）、新发现 Target 词（本次答不认识/核验错或不认识、且测后为 Target 的词）、抽查对错、假词误认。测试里写出 JSONL 后调用 `profile-engine profile` 逐项比对。
- `App/`（手写 Xcode 工程，objectVersion 77 文件夹同步，无需改 pbxproj 就能加文件；依赖本地 `EnglishCore` 和 GRDB 7）：四个标签、测试全屏流程、✕ 随时退出、当天可再测、结果页。GRDB 库在 `Application Support/LearnEnglish/learn-english.sqlite`，表 `observation`，迁移只追加。
  - 词库在构建时由 `App/scripts/bundle-lexicon.sh` 拷进包：有 `tools/lexicon-build/out`（全量，gitignored）就用全量，否则用 fixture 切片。本次全量构建没有下载 Wiktextract（放了空文件），所以没有例句和音频，不影响测试。
  - 注意：`CoreModels.Observation` 和 Swift 的 `Observation` 模块同名，用 `@Observable` 的文件不能 `import CoreModels`，改用 `CoreTypes.swift` 里的 `LearnerObservation` 别名。
- 模拟器验证（iPhone 17，iOS 27）：DEBUG 环境变量 `LE_TAB=test`、`LE_START_TEST=1`、`LE_AUTOPLAY=1`、`LE_AUTOPLAY_STOP_AT=N` 用来自动答题（走与按钮相同的 `TestFlowModel.answer`）。完整一次是 86 条（52 真词 + 20 假词 + 8 抽查 + 6 核验），全部落库；杀掉 App 后用 sqlite3 读出 171 条（两次中途退出 + 一次完整），重启后「测试」标签显示「✓ 今天已测 / 再测一次」和上次结果。把库导出成 JSONL 后运行 `profile-engine profile --lexicon tools/lexicon-build/out`，得到 3189 [2111, 4267]、false_alarms 4，与结果页一致（3,189，2,111–4,267；本次假词误认 2/20，前一场 2/20）。

**未验证**

- 模拟器控制权限没有拿到，所以按钮点击（认识/不认识、选项、✕）是通过 autoplay 调用同一个 model 方法验证的，没有实际点屏幕；中途退出是直接结束进程，而不是点 ✕。人工在模拟器里点一遍即可确认。

- 2026-11-13：按 [ADR 0002](../../../docs/adr/0002-measure-only-no-study-or-planning.md)，其中与卡片学习、Leech、Study Plan 相关的部分已删除，其余仍有效。
