# 07: 卡片学习

Status: wontfix

**What to build:** 学习者在"学习"标签先复习到期卡片，再学新卡。卡片按 FSRS 调度，用四档评分；学会的词自动退出，反复忘记的词暂停；学习者可以手动加词、在设置里改每日新词上限。这一张先用一份手写的示例 Study Plan 作为新词来源。

- 学习会话：先放到期复习，再放新卡，中间一页"复习完成，开始 N 个新词？"可以停下。新卡数取计划建议的每日数和设置上限两者中较小的一个，按计划顺序取词，跳过已有卡、已 Mastered 或已评"太简单"的词。
- 卡面（一个 lemma 一张卡，第一版不配图）：正面是词、音标、发音（Wiktextract 真人发音，没有就用 iOS TTS）；点击翻面，显示英文释义、例句、中文释义和选词说明（没有说明就不显示）。
- 评分：忘了 / 模糊 / 想起 / 太简单，对应 FSRS 的 Again / Hard / Good / Easy，按钮下显示下次间隔。用 swift-fsrs 实现 FSRS-6，期望保留率 0.9，默认参数。复习记录写成 Observation，FSRS 字段与 Anki revlog 对齐。
- 退出与暂停：
  - 复习把 P 推到 0.9 以上，词变成 Mastered，卡片暂停；
  - 新卡首评"太简单"，卡片暂停，当天从计划里补一张；
  - Leech（忘了 8 次以上）：卡片暂停，30 天后或手动"重新学"时重置为新卡，排在当天新卡最前面并计入上限；Word Band 仍只由 P 决定。
- 加词：一个"加词"入口，写一条来源为 wish 的 Observation。
- 设置里的每日新词上限：写一条来源为 setting 的 Observation。
- 完成页。

**Blocked by:** 03


- [x] 用示例计划在模拟器里完整走一次：复习 → 分隔页 → 新卡 → 完成页
- [x] 会话组装有测试：复习先于新卡、新卡数取较小值、跳过规则、Leech 重新引入的位置和计数
- [x] 四档评分驱动 FSRS 调度，按钮下的间隔与 swift-fsrs 计算一致
- [x] P 过 0.9 后卡片暂停；首评"太简单"后暂停并补卡
- [x] 加词和每日上限都落成只追加的 Observation

## Comments

**已完成（agent）**

- `EnglishCore` 新增纯逻辑目标 `StudyComposer`，依赖 swift-fsrs（`exact: "6.0.0"`，MIT，只用 Foundation）。`swift test` 新增 19 个测试，全部通过。
  - `CardScheduler(config: FSRSConfig)`：包装 swift-fsrs，FSRS-6 默认权重，期望保留率 0.9，学习步 1m/10m，重学步 10m，不加 fuzz。`FSRSConfig` 可以注入（`w` 共 21 个，`w[20]` 是 decay；JSON 键名 `w`、`desired_retention` 等），供 10 号票换成个人参数。
  - `CardLedger`：卡片状态不另存，每次从 review / relearn Observation 用调度器重放得到。包含首评、"忘了"次数、暂停原因（首评太简单 / Leech）和重置时间。`leeches` 给出 Leech 清单（词、次数、开始时间、自动重新引入时间）。"忘了"累计 ≥8 次就成为 Leech；满 30 天或有 `relearn` Observation 时重置为新卡，次数从零重新计。
  - `StudyComposer.compose(...)`：返回 `StudySession`。到期复习排在前面，新卡数 = min(计划 daily_new, 上限) − 今天已开始的卡（首评太简单的不计）。重新引入的 Leech 排在新卡最前面并计入上限。计划词跳过已有卡、Mastered（由调用方传入 `isMastered`，App 里用 Profile 的 Word Band）、不在词库的词。已有卡的词变成 Mastered 后不再出现在复习里（暂停）。
  - `StudySession`：阶段依次是复习 → 分隔页（可 `finish()` 停下）→ 新卡 → 完成。`intervals(at:)` 就是 swift-fsrs `repeat` 的结果。`rate` 返回 review Observation，ReviewLog 按 Anki revlog 对齐：ease 1–4，ivl/last_ivl 正数为天、负数为秒，type 0/1/2，time、stability、difficulty、due。学习步在 20 分钟内到期的卡会在本次会话里再出现。新卡首评太简单时卡片暂停，并从计划里补下一张。
  - `CoreModels` 新增：`ObservationSource.relearn`（result `reset`）、wish 的 result `add`、`SettingKey.dailyNewLimit`（setting Observation 的 lemma 字段写 `daily_new_limit`，result 写数值字符串），以及跨平台的 `Timestamp.iso`。`StudyObservations.wish / dailyNewLimit / relearn` 负责生成这些 Observation，`StudySettings.dailyNewLimit(from:)` 读取最新设置（默认 10）。
- App：
  - `StudyFlow/`：`AppModel+Study.swift` 提供 `composeStudy`、`startStudy`、`leeches`、`relearn(_:)`（给 09 号票用）、`addWish`、`setDailyNewLimit`、`studyPlan`。目前读内置的 `sample-plan.json`（08 号票的 schema，35 个词，每天 5 个），08 号票替换 `studyPlan` 即可。
  - `StudyFlowView` / `StudyFlowModel`：卡片正面显示词、音标和发音按钮（有 Wiktextract 音频就用 AVPlayer 播放，没有或失败时用 TTS），点击翻面后显示英文释义、例句、中文和选词说明。四个按钮下显示间隔。另有分隔页和完成页。
  - 学习结束（完成页点"完成"）时走 `dismissFlow()`，它会调用 05 号票的 `sessionEnded()` 触发同步，之后重算 Profile。
  - "学习"标签显示今日复习数、新词数、计划摘要和上限，右上角"+"是加词入口；"设置"里加了"学习 › 每日新词上限"（`StudySettingsSection`）。对共享文件只做了小的追加改动：Flow 加了 `.study`，RootView、SettingsTab 各加一行，pbxproj 加了 StudyComposer 产品（ID 用 `…07A1/07A2`）。
- 模拟器验证（新建的 LE-ticket07，iPhone 17，iOS 27）：DEBUG 环境变量 `LE_SEED_REVIEWS=1` 写入 3 张 5 天前学过的卡，`LE_START_STUDY=1`、`LE_AUTOPLAY=1`（可选 `LE_AUTOPLAY_MS`、`LE_AUTOPLAY_STOP_AT_SEPARATOR`）调用与按钮相同的 model 方法。完整走了一遍：复习 3 张（其中 1 张"忘了"后 10 分钟内在本次再出现）→ 分隔页"开始 5 个新词"（单独截图确认）→ 新卡（第一张评太简单，从计划补一张）→ 完成页（复习 3 / 新学 5 / 太简单 1 / 评分 15）。用 sqlite3 读出的 review 行带有完整的 revlog 字段。

**未验证**

- 和 03 号票一样没有点屏幕：翻面、按钮、加词弹窗、设置里的 Picker 都是经由同一套 model 方法和 Core 测试验证的。人工点一遍即可确认。
- swift-fsrs 在 Linux 上能否编译只看了源码（只 import Foundation），没有实际编译；`.github/workflows/englishcore.yml` 的 CI 会编译到它。
- Profile Engine 自己按全部"忘了"次数推活跃卡，"重新学"之后不会清零（它只影响 Target 窗口外的词是否算 Target）。需要时可以把 `CardLedger.activeCards` 传给 `ProfileEngine.compute(activeCards:)`。

- 2026-11-13：按 [ADR 0002](../../../docs/adr/0002-measure-only-no-study-or-planning.md) 作废。系统只做词汇测量，背词交给墨墨背单词；本票的代码已删除（commit a2ca384）。
