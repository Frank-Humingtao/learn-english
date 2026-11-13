# 09: 进度标签

Status: resolved

**What to build:** 学习者在"进度"标签看到自己的长期变化：估计词汇量和曲线、三类词、各频段掌握率、连续学习天数，以及 Leech 清单；还能一键打开公开看板和最新的 Progress Report。

- 估计词汇量（词族数）及误差范围、随时间变化的曲线。
- Mastered / Target / Distant 三类词数的条形图；各词频段掌握率。
- 连续学习天数、最近测试日期。
- Leech 清单，每个词带"重新学"按钮。
- 外链：公开看板、最新 Progress Report（筛选打开且带 `progress-report` 的 issue 列表）。
- 所有数字由本机 Profile Engine 重算，页面注明公开看板会稍有滞后。

**Blocked by:** 06, 07


- [x] 用夹具 Observation 预置数据时，进度页各项数字与 Profile Engine 命令行一致
- [x] 曲线能反映多次测试的变化
- [x] Leech 清单里点"重新学"后，该词出现在当天新卡最前面
- [ ] 两个外链都能打开正确的页面

## Comments

**已完成（agent）**

- `EnglishCore/Sources/StudyComposer/ProgressPage.swift`：纯逻辑，放在 StudyComposer 里是因为要用 `CardLedger`，这样就不用改 Package.swift 和 pbxproj。
  - `ProgressPage.report`：用 `CardLedger.activeCards` 计算 Profile，修掉了 07 留下的缺口：重新学之后的词、冷却 30 天后回来的 Leech，不再按旧的"忘了"次数来判断。同时给出 Leech 清单和连续测试天数。
  - `ProgressPage.curve`：每次测试会话结束时，用截至当时的 Observation 重算一次词汇量（`asOf` 设为会话结束时间）。会话按 `session` 区分，没有 `session` 就按日期。传入 `reusing:` 后，会话 id 和结束时间都没变的点直接复用，只算新的会话。
  - `ProgressPage.testActivity`：最近测试日期和连续测试天数。规则与公开看板 `profile_publish.py` 的 `streak` 相同：只看 `source == test`，算到今天或昨天为止。
  - 测试 `StudyComposerTests/ProgressTests.swift`，共 5 个：
    - 用夹具 Observation 时，`summaryJSON` 与金标准逐字节一致（金标准就是 `profile-engine profile` 的输出）。
    - 曲线每次测试一个点，随测试上升，与截至当时的重算结果一致，缓存能复用。
    - 夹具数据的曲线有 3 个点。
    - 连续天数。
    - 重新学后的 Leech 计入 Target。
- App：
  - `AppModel.load` 和 `recomputeProfile` 改为调用 `AppModel.computeProfile`（在 `Tabs/AppModel+Progress.swift`），得到带 ledger 活跃卡的 Profile。
  - `Tabs/ProgressTab.swift`，从上到下依次是：
    - 词汇量、95% 区间，以及 Swift Charts 曲线（带区间阴影，在后台计算并缓存）。
    - 三类词的条形图和数字。
    - 各频段掌握率柱状图。
    - 连续测试天数和最近测试日期。
    - Leech 清单：每行一个"重新学"按钮，点了调用 `AppModel.relearn`，然后重算 Profile。
    - 外链"公开看板"和"最新 Progress Report"，页脚注明公开看板会稍有滞后。
  - owner：优先用同步时从令牌得到的 `sync.repoOwner`。没有令牌时，进度页显示"GitHub 用户名"输入框，值存在 UserDefaults 的 `progress.publicOwner`。
  - DEBUG 钩子：`LE_TAB=progress`；`LE_SEED_OBSERVATIONS=<jsonl 路径>`，只导入一次；`LE_RELEARN=<lemma>`。
- 模拟器验证（新建 LE-ticket09，iPhone 17）：导入夹具 Observation，加上 ivy 的 8 次"忘了"和今天的一次短测。
  - 进度页显示 49 [33–65]，三类词 41 / 25 / 859，和对同一份文件运行 `profile-engine profile` 的结果一致。
  - 曲线有 4 个点；连续 1 天，最近测试 2026-11-13。
  - Leech 清单里有 ivy。点"重新学"后清单变空，开始学习时 ivy 是第一张新卡。
  - 设置 owner 后，点"最新 Progress Report"会跳转到 Safari。

**未验证**

- 第 4 个框：两个链接的 URL 按 06 号票的 README 格式拼出，也确认会在 Safari 打开。但要等 02 号票建好真实的 `english-profile` 仓库，才能确认打开的是正确页面。
- 活跃卡改用 ledger 后，如果有词被"重新学"过，或者 Leech 冷却到期，App 的 Target 数会和 Actions 端稍有差别，因为 CLI 不认识 relearn。要完全一致，`profile-engine` 得能接受传入的活跃卡；这次没有改 CLI。

- 2026-11-13：按 [ADR 0002](../../../docs/adr/0002-measure-only-no-study-or-planning.md)，其中与卡片学习、Leech、Study Plan 相关的部分已删除，其余仍有效。
