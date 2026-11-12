# 总规格：个人英语学习系统

Status: ready-for-agent

来源：[地图](map.md) 的全部已关闭票，以及 [GLOSSARY.md](../../GLOSSARY.md)、[ADR 0001](../../docs/adr/0001-append-only-observations-and-two-repos.md)。下文的术语（Learner、Observation、Learner Profile、Word Band、Mastered / Target / Distant、Coverage、Vocabulary Test、Baseline Test、Card、Study Plan、Word Planning、Leech、Progress Report）都按术语表的定义使用。

## Problem Statement

Learner 通过过大学英语考试，但读英文网页要靠翻译，硬读速度大约只有读中文的 1/20，也没有信心和外国人交流。Learner 不清楚自己的真实词汇量，现有的背单词 App 也不知道 Learner 到底认识哪些词、该学哪些词。阅读和视频推荐因此要么太简单，要么太难，做不到"可理解性输入"。

Learner 想要三样东西：
- 一个能精确测出自己词汇水平的工具；
- 一套只学"正好该学"的词的卡片学习方式；
- 一份长期可追踪、外部 AI 工具能直接读懂的学习档案，让这些工具据此给 Learner 推荐合适的文章和视频。

## Solution

一个只给 Learner 自己用的 iPhone App，加两个 GitHub 仓库，再加一个在 Mac 上定时运行的 Claude skill：

- **iPhone App**（SwiftUI，中文界面）：
  - 第一次使用时做约 30 分钟的 Baseline Test，之后每一两天做 3 到 5 分钟的短测，词汇量估计滚动更新。
  - 用 FSRS 调度复习 Card，只给 Target 词发卡。
  - 所有作答都记成 Observation，先存在本地，再批量同步到 GitHub。
- **私有仓库 `english-data`**：存只追加的 Observation 和 Study Plan，是唯一的真相源，不另设后端。
- **公开仓库 `english-profile`**：存 GitHub Actions 从 Observation 重算出来的 Learner Profile、README 看板，以及每天第一次测试后自动发布的 Progress Report issue。
- **选词规划 skill `word-plan`**：每天在 Mac 上由 Claude 运行一次，读私有仓库，写出 Study Plan，决定"接下来学哪些词、按什么顺序学"。"AI 按水平定制"就落在这里。

本系统做到发布公开可读的 Progress Report 为止。谁读报告、怎么推荐、推荐结果送到哪里，都在本系统之外。

## User Stories

**首次启动**
1. 作为 Learner，我想在第一次打开 App 时看到一个简短的欢迎页，这样我知道这个 App 会做什么。
2. 作为 Learner，我想在首次启动时粘贴一个 GitHub fine-grained PAT，这样 App 能把我的学习记录同步到私有仓库。
3. 作为 Learner，我想能跳过粘贴 PAT、稍后在设置里补上，这样没准备好令牌也能先开始学。
4. 作为 Learner，我想在首次启动时被引导去做 Baseline Test，这样系统从一开始就有可靠的水平估计。
5. 作为 Learner，我想 Baseline Test 能中途退出，下次从断点继续，这样 30 分钟不必一次做完。

**Vocabulary Test**
6. 作为 Learner，我想在"测试"标签里随时开始一次 3 到 5 分钟的短测，这样我能每一两天更新一次水平估计。
7. 作为 Learner，我想当天已经测过还能再测一次，这样我有空时可以多给系统一些证据。
8. 作为 Learner，我想测试主要是"认识 / 不认识"的快速判断题，这样几分钟内就能答上百个词。
9. 作为 Learner，我想测试里混入假词，这样系统能发现我是不是在瞎点"认识"。
10. 作为 Learner，我想在 Yes/No 题后答几道中文四选一释义题（带"不认识"选项），这样系统能核实我说认识的词是不是真认识。
11. 作为 Learner，我想每次测试抽的都是我没测过、难度又正好在我边界附近的词，这样每次测试都在提供新信息，而不是重复同一批题。
12. 作为 Learner，我想每次测试里有少量已 Mastered 的词被抽查，这样忘掉的词能回到 Target，测试模型也能自我校验。
13. 作为 Learner，我想测完看到结果页，包括估计词汇量及范围、较上次的变化、新发现的 Target 词数、抽查对错和假词误认数，这样我能直观看到自己的变化。
14. 作为 Learner，我想测试中途能用左上角的 ✕ 退出，这样被打断也不会卡住。
15. 作为 Learner，我想每次测试都在全部历史作答的基础上更新估计，而不是每次从头算，这样估计越来越稳。

**卡片学习**
16. 作为 Learner，我想在"学习"标签看到今天到期的卡片数和"开始复习"按钮，这样我知道今天要做多少。
17. 作为 Learner，我想每次先复习、再学新卡，中间有一页"复习完成，开始 N 个新词？"让我可以停下，这样复习不会被新词挤掉。
18. 作为 Learner，我想卡片正面显示词、音标和发音，这样我先尝试回忆。
19. 作为 Learner，我想点一下翻面，看到英文释义、例句、中文释义和选词说明，这样我能确认并加深记忆。
20. 作为 Learner，我想用"忘了 / 模糊 / 想起 / 太简单"四个按钮评分，并在按钮下看到下次间隔，这样我的反馈能驱动复习调度。
21. 作为 Learner，我想新卡第一次就评"太简单"时，卡片直接暂停、当天再从计划里补一张，这样不在已认识的词上浪费时间。
22. 作为 Learner，我想复习做完后看到完成页，这样我知道今天的任务结束了。
23. 作为 Learner，我想一个词只有一张卡（不按义项拆），卡面样式参考成熟的背单词 App，这样学起来熟悉、不费解。
24. 作为 Learner，我想有一个"加词"入口，把我在别处遇到、想学的词加进来，这样下一份 Study Plan 一定会安排它。
25. 作为 Learner，我想一个词在复习中被推到 Mastered 后，卡片自动暂停，这样学会的词不再占用时间。

**Leech**
26. 作为 Learner，我想忘了 8 次以上的卡片自动暂停，这样我不被一个词反复折磨。
27. 作为 Learner，我想在"进度"页看到 Leech 清单，并能手动点"重新学"，这样我能决定什么时候再挑战它们。
28. 作为 Learner，我想 Leech 在 30 天后自动重新引入一次，排在当天新卡最前面，这样它们不会被永远遗忘。

**Study Plan 与 Word Planning**
29. 作为 Learner，我想由 Claude 每天根据我的测试和复习表现挑选、排序新词，而不是套固定公式，这样学的词真正贴合我的水平。
30. 作为 Learner，我想 Word Planning 优先安排我手动加的词，其次是似懂非懂的高频词，再其次是其他 Target 词，这样最有价值的词先学。
31. 作为 Learner，我想易混词（如 affect 和 effect）不排在同一天，这样不会互相干扰。
32. 作为 Learner，我想每个新词都附一句不超过 40 字的中文选词说明（为什么现在学、易混词、记忆提示），且不编造词义，这样我知道为什么要学它。
33. 作为 Learner，我想在设置里填每日新词上限，Word Planning 在上限内根据复习积压决定实际数量，这样学习量可控。
34. 作为 Learner，我想每份 Study Plan 至少排够 7 天，这样偶尔漏跑一天也不会断粮。
35. 作为 Learner，我想在"学习"标签看到当前计划的 1 到 3 句中文摘要，这样我知道这一期的重点。
36. 作为 Learner，我想在 Mac 上输入 `/word-plan` 加一句临时要求（如"这周出差，少排点"）手动运行，这样我能临时调整。
37. 作为 Learner，我想计划超过 3 天没更新、或剩余新词不够 2 天时，"学习"标签显示一行黄字提醒，这样定时任务停了我能马上发现。
38. 作为 Learner，我想计划用完时只做复习，并看到"学习计划已用完，去跑一次选词规划"，这样系统不会塞给我未经规划的词。
39. 作为 Learner，我想 Word Planning 输出不合格（词不在词表、条数不够、JSON 不合法）时宁可不提交，这样 App 不会读到坏计划。

**进度**
40. 作为 Learner，我想在"进度"标签看到估计词汇量（词族数）、误差范围和随时间的曲线，这样我看得到长期进步。
41. 作为 Learner，我想看到 Mastered、Target、Distant 三类各有多少词，以及各词频段的掌握率，这样我知道自己卡在哪个层次。
42. 作为 Learner，我想看到连续学习天数和最近测试日期，这样我能保持节奏。
43. 作为 Learner，我想"进度"页的数字由手机本地重算，并注明公开看板会稍有滞后，这样我看到的永远是最新状态。
44. 作为 Learner，我想从"进度"页直接打开公开看板和最新的 Progress Report，这样我能看到外部工具看到的内容。

**同步与报错**
45. 作为 Learner，我想每作答一题都先存在本地，这样离线也能正常测试和复习。
46. 作为 Learner，我想在一次测试或复习结束时、以及 App 回到前台时自动同步，这样我不用手动操心。
47. 作为 Learner，我想全部同步时界面上什么都不显示，有未同步记录时右上角出现"未同步 N 条"、点一下立即同步，这样平时界面干净，出问题时又看得见。
48. 作为 Learner，我想令牌未设置、过期或被撤销时，每个页面顶部常驻红条，写明原因并说明"记录都还在本机"，点红条进设置，这样我不会在不知情时丢同步。
49. 作为 Learner，我想换好令牌后未同步的记录自动补交，这样不用重做任何事。
50. 作为 Learner，我想断网只显示灰色的"离线中，联网后自动同步"而不算错误，这样在地铁里学习不被打扰。
51. 作为 Learner，我想在设置里看到同步状态、未同步条数、上次成功同步时间和仓库名，并有"立即同步"按钮，这样我能自己排查。
52. 作为 Learner，我想在设置里替换 PAT 并看到令牌有效期，这样到期前我能提前换。
53. 作为 Learner，我想在设置里"重做 Baseline Test"，这样隔了很久之后能重新校准。
54. 作为 Learner，我想万一手机丢失，靠 iCloud 整机备份最多只丢一次学习的数据，这样我不用另做备份。

**仓库、看板与 Progress Report**
55. 作为 Learner，我想所有原始记录都在私有仓库里只追加、永不改写，这样阈值或算法改了也能从头重算，历史不丢。
56. 作为 Learner，我想复习时间线只留在私有仓库，这样别人看不到我每天几点学了多久。
57. 作为 Learner，我想公开仓库的 README 自动显示词汇量曲线、三类词数、近一周新掌握的词、最近测试日期和连续天数，这样在 GitHub 上一眼看到进度。
58. 作为外部 AI 工具，我想通过一个固定地址（打开且带 `progress-report` label 的 issue 列表）找到唯一一份最新的 Progress Report，这样我只需配置一次。
59. 作为外部 AI 工具，我想报告里有一个结构化 JSON 块，包含词汇量及区间、三类词数、新掌握的词（≤30）、重点 Target 词（≤50）和固定到某次提交的 `words.tsv` 链接，这样我能定量地挑选内容。
60. 作为外部 AI 工具，我想下载 `words.tsv`（每个 lemma 的 Word Band、认识概率和词频排名），这样我能算出任意文章对 Learner 的 Coverage。
61. 作为 Learner，我想每天第一次测试后自动发一份新报告、同一天再测只更新这一份、只复习不发，这样报告既及时又不刷屏。
62. 作为 Learner，我想发新报告时上一份自动关闭但保留，这样历史可查，当前却只有一份。
63. 作为 Learner，我想报告里不含我的内容偏好和复习明细，这样它只描述我的水平，不暴露隐私。
64. 作为 Learner，我想积累了几百条复习后，系统用我的数据训练个人化的 FSRS 参数，这样复习间隔更贴合我的记忆。

## Implementation Decisions

**架构**（见 ADR 0001）
- 两层数据：Observation 只追加，是事实；Learner Profile 是派生数据，随时可从全部 Observation 重算。
- 两个仓库：私有 `english-data` 存输入，公开 `english-profile` 存派生结果。不设后端，`english-data` 是最终一致的唯一真相源，不能当实时后端。
- 写入方各写各的路径，互不冲突：
  - iPhone：只追加 `english-data` 中自己的 Observation 文件（按写入方和月份拆分的 JSONL）。设置项和"想学"也作为 Observation 写入（来源标为 setting / wish）。
  - Word Planning：只在 `english-data` 中新增 Study Plan 文件（每次运行一个按日期命名的文件，同日重跑覆盖当天文件）。Study Plan 是大模型输出，不可复现，因此属于输入而非派生数据。
  - GitHub Actions：只写 `english-data` 的 FSRS 参数文件，以及 `english-profile` 的派生档案、README 和 Progress Report issue。

**模块**
1. **Profile Engine**（核心深模块，纯计算，无 IO）
   - 输入：全部 Observation 加参考数据。输出：Learner Profile。
   - 模型：Rasch 型 `P(认识) = σ(θ − δ_w)`，δ_w 由词频排名等特征回归得到，不人工标定。每次用全部历史重新拟合，较早的作答按可调的衰减速度降权。
   - 证据来源：测试作答、抽查、复习都算证据。复习中"忘了"算作不认识，其余三档算作认识；新卡首评"太简单"算强"认识"证据。
   - 输出内容：每个 lemma 的 P；总词汇量 = ΣP，带 95% 区间，对外折算成 word family（BNC/COCA Level 6 口径）；各频段掌握率。
   - Word Band 划分（阈值均可调）：
     - Mastered：P ≥ 0.9。
     - Target：P < 0.9，且词频排名在当前估计词汇量往外约 2000 词以内；有活跃 Card 的词也算 Target。
     - Distant：其余。
   - 提供 Coverage 计算：给一段文本，先做词形还原，再算已认识词的占比。
   - 同一份实现同时用于 iPhone 本地重算和 Actions 重算，保证两边结果一致。用 Swift package 实现，Actions 在 Linux runner 上以命令行方式调用。
2. **Test Engine**
   - 在 P≈0.5 附近随机抽从未测过的真词。
   - 每次现生成假词，约占 Yes/No 题的四分之一，由类 Wuggy 规则生成。
   - 约 10% 的题抽查 Mastered 词。
   - 另有 5 到 8 道中文四选一释义核验题，从答"认识"的词里抽。干扰项取自词典中同词性、词频相近的其他词的中文释义，不用 AI 生成。
   - 基线测试与短测共用一个流程，区别只在题量和时长。基线测试可断点续测。
   - 纠偏信号：假词误认率、释义核验失败率、反应时、person-fit，叠加使用。
3. **Study Session Composer**
   - 每次学习的组成：先放到期复习，再放新卡。
   - 新卡数量取 Study Plan 建议的每日数和设置上限两者中较小的一个，按计划顺序取词，跳过已有卡、已 Mastered 或已评"太简单"的词。
   - 到期重新引入的 Leech 排在新卡最前面，计入上限。
   - 调度用 swift-fsrs 实现 FSRS-6，期望保留率 0.9。起步用默认参数，之后改用 Actions 训练出的个人参数。数据格式保留 FSRS 的权重和 decay 参数，便于以后升级算法。
   - 复习记录字段与 Anki revlog 对齐。
   - Leech 判定：忘了 8 次以上。判定后暂停，30 天后或手动"重新学"时重置为新卡。Word Band 仍只由 P 决定。
4. **Sync**
   - 本地优先：作答写入本地 SQLite（通过 GRDB）并进入 outbox。
   - 在一次学习结束或 App 回到前台时，用 GitHub GraphQL `createCommitOnBranch` 批量提交，带 `expectedHeadOid` 做乐观并发控制。head 不一致时，拉取最新 head 后重试一次，仍失败就把记录留在 outbox。
   - 读取 Study Plan 用 REST Contents API。不引入第三方 Git 或 GitHub 客户端库。不依赖 iOS 后台任务。
   - 认证用只授权 `english-data` Contents 读写的 fine-grained PAT，存在 Keychain。
   - 状态模型：已同步（不显示）、未同步 N 条、离线（灰色提示）、令牌错误（401，红条）。
5. **App UI**（SwiftUI）
   - 底部标签栏分四个标签：学习、测试、进度、设置。测试和复习都是全屏流程。屏幕清单和交互以原型 `prototypes/11-app-screens/index.html` 的方案 A 为准。
   - 第一版卡片不配图。
   - App 不调用任何 AI 服务。
6. **参考数据构建**
   - 构建脚本合并以下数据，生成一份打包进 App 和 Actions 的只读词库：
     - ECDICT（MIT）：释义、音标、考试标签、lemma 映射；
     - BNC/COCA 25k 词族表：词频分层，构建时从官网下载，不入任何仓库；
     - Wiktextract（CC BY-SA）：例句和真人发音，没有时用 iOS TTS。
   - Observation 和 Learner Profile 只记录所用词库的版本号。
7. **Actions 重算与发布流水线**（在 `english-data` 中运行）
   - `observations/` 有 push 时触发。用 concurrency group 串行执行，每次从全部 Observation 重算。
   - 用 Profile Engine 命令行生成 `english-profile` 的以下内容：
     - `summary.json`：词汇量及区间、三类词数、更新时间；
     - `words.tsv`：lemma、Word Band、P、词频排名；
     - `recent.json`：近期新掌握的词，以及从最新 Study Plan 原样照抄的 `focus_targets`；
     - `README.md` 看板。
   - 发 Progress Report 的规则：
     - 当天第一次测试同步后发新 issue。标题为 `Progress Report YYYY-MM-DD · 约 N 词族`，带 `progress-report` label。
     - 正文是中文摘要加 JSON 块。JSON 字段：`schema_version`、`generated_at`、`profile_commit`、`vocab_size`（含区间和变化）、`band_counts`、`newly_mastered`（≤30）、`focus_targets`（≤50）、`words_tsv_url`（固定到 `profile_commit`）。
     - 同日再测只更新当日这份。发新报告时关闭上一份。只复习不发。
   - 复习积累到几百条后，用 py-fsrs 训练参数，写回 `english-data`。
   - 认证用只授权 `english-profile` 的 Contents 和 Issues 写的 fine-grained PAT，存在 `english-data` 的 Secrets。令牌失效时工作流显式失败。
8. **选词规划 skill `word-plan`**
   - 存放在 `english-data` 仓库内，随数据一起管理版本。
   - 运行方式：每天 07:30 由 Claude 桌面 App 的定时任务在 Mac 上本地 clone 的 `english-data` 里运行，也可手动 `/word-plan [临时要求]`。
   - 输入：汇总脚本先把全部 Observation、最新的 `words.tsv`、上一份计划、设置和"想学"记录汇总成精简摘要，Claude 只读这份摘要。摘要包括：约 400 个预分桶的候选词（附 P、词频、测试历史、4 档评分计数）、活跃卡近期表现、未来 7 天到期数、Leech 清单、未排的"想学"词、每日上限、上一份计划剩余量。
   - 选词优先级：先排"想学"词，再排似懂非懂的词（P 在 0.3 到 0.7 之间，或复习常评"模糊"），最后排其他 Target 词，同级按高频优先。偏离这个顺序时要在选词说明里写明理由。易混词至少间隔几天。
   - 输出：Study Plan 文件，字段为 `schema_version`、`generated_at`、`daily_new`、`new_words`（有序，每项含 lemma 和 note）、`focus_targets`（≤50，先放正在学、近期出错多的卡，不够再用计划中接下来几天的新词补满）、`summary`（1 到 3 句中文）、`instruction`。
   - 校验脚本检查：JSON 合法、lemma 都在词表里且不重复、不是已建卡或已掌握的词、"想学"词全部排入、条数 ≥ 每日数 × 7（候选不足时例外）、`focus_targets` ≤ 50、每条说明 ≤ 40 字。不合格时最多修正 2 次，仍不合格就不提交，以失败结束。
   - 提交流程：先 pull --rebase，只 add 本次写的 Study Plan 文件，提交说明首行写摘要，push 被拒时 rebase 后重试一次。用 Mac 上已有的 git 凭据。

**数据与许可**
- 绝不入库：令牌、真实姓名、邮箱、设备标识、位置。Observation 只记 lemma、时间、来源、结果、反应时、会话编号，复习另带 FSRS 字段。
- 公开仓库的派生数据用 CC BY 4.0，并在 README 注明数据来源。代码（App、Actions、skill）用 MIT。Wiktextract 内容只在 App 内使用，并在"关于"页署名。

## Testing Decisions

- **好测试的标准**：只测模块对外的行为（输入 Observation 或作答，输出 Profile、选题、会话组成、文件），不测内部实现。用确定性的随机种子和固定的参考数据切片。
- **主测试接缝：Profile Engine。**
  - 用夹具 Observation 序列测期望的 Learner Profile：P 的单调性、Word Band 边界、ΣP 与区间、衰减效果、word family 折算、Coverage。
  - 用"已知 θ 的模拟学习者"做端到端检验：模拟作答若干次短测后，估计的词汇量应落在真实值的误差范围内。
  - iPhone 和 Actions 共用这一实现，同一组夹具对两边都成立。
- **Test Engine**：用模拟学习者检验选题落在 P≈0.5 附近、不重复已测词、假词比例和抽查比例正确、干扰项来自同词性同频段、断点续测恢复后状态一致。
- **Study Session Composer**：给定卡片状态、计划和设置，检验复习先于新卡、新卡数取两者较小值、跳过规则、Leech 重新引入的位置和计数。
- **Sync**：针对 GitHub API 的假服务器，检验 outbox 批量提交、head 不一致后重试、401 进入令牌错误状态、离线状态、令牌更换后补交。实现阶段的第一项验证任务：用真实令牌和仓库实测 `expectedHeadOid` 冲突时 GraphQL 返回的错误格式，再据此固定重试逻辑。
- **Actions 发布流水线**：以 dry-run 模式在夹具仓库上运行，检验生成的文件内容，以及"当天第一次测试才发报告、同日只更新、只复习不发、关闭上一份"的判定。
- **word-plan 校验脚本**：用合格和不合格的 Study Plan 夹具测试每一条校验规则。
- **App UI**：只对标签结构、同步状态显示和首次启动流程做少量 SwiftUI 预览或 UI 测试，不追求覆盖率。
- 目前仓库里没有代码，也就没有可参照的现有测试，以上即为首批约定。

## Out of Scope

- 读取 Progress Report 的外部工具、推荐引擎，以及推荐结果的去向（学习者的阅读工具、B 站收藏夹等）。
- 在 App 内阅读文章、看视频，以及付费墙文章的处理。
- 网页版、iPad 版和 Mac 版。
- 公开发布、多用户和账号体系。
- Anki 卡组导入（推迟到第一版之后；导入时只取笔记内容，不导入调度）。
- 卡片配图。
- 自建或购买后端、CloudKit 备份。

## Further Notes

- **待验证的设计**："Yes/No 加抽样核验"这个组合没有成套的一手验证文献，是推断出来的设计。用 Mastered 抽查做持续的自我校验，阈值和衰减速度都做成可调参数。
- **阈值未定稿**：Word Band 阈值（0.9 和约 2000 词的窗口）、Leech 的 8 次和 30 天都是初值，需要用真实数据调整。由于 Observation 只追加，调整后重算即可，历史不丢。
- **许可待确认**：BNC/COCA 词表没有明确许可证。目前的做法是只在构建时下载、不入库。如果日后要把原表放进公开仓库，需要先向 Paul Nation 确认。
- **网络**：GitHub 在大陆网络下暂时连不上时，只会推迟同步。App 不内置代理。
- **详细决策与依据**：见地图 Decisions so far 中各票的 Answer 部分，以及 `research/` 下的调研笔记。

实现票：[../english-learning-app/issues/](../english-learning-app/issues/)（10 张）。
