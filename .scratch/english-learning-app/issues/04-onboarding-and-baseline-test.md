# 04: 首次启动与 Baseline Test

Status: resolved

**What to build:** 第一次打开 App 时，学习者依次看到欢迎页、粘贴 PAT（可以跳过），然后被引导做约 30 分钟的 Baseline Test。基线测试可以中途退出，下次从断点继续。

- 首次启动三步：欢迎页 → 粘贴 GitHub fine-grained PAT（存进 Keychain，可跳过，稍后在设置里补）→ 基线测试介绍。
- Baseline Test 与短测共用测试流程，区别只在题量和时长。
- 断点续测：退出后再进入，从上次停下的地方继续，已答的题不丢。
- 设置页提供"重做 Baseline Test"。

**Blocked by:** 03


- [x] 全新安装后首次启动依次出现三步，之后再打开不再出现
- [x] 跳过 PAT 后能正常使用测试
- [x] PAT 只存在 Keychain，不出现在 SQLite、日志或任何文件里
- [x] 基线测试做到一半退出，重新进入后从断点继续，Observation 无重复、无丢失
- [x] 设置里"重做 Baseline Test"可用

## Comments

**已完成（agent）**

- `TestEngine`：新增 `TestConfig.baseline`（680 道 Yes/No + 30 道释义核验，按每题约 2.5 秒算约 30 分钟，假词和抽查比例与短测相同）。另加 `TestSession.replay(_:)`：把已存的本场 Observation 按顺序重新套到「开局时的会话快照」上，遇到第一条对不上的就停。新测试 `ResumeTests`：在第 0/1/37/80/83 题中断后续测，题目和 Observation 序列与一次做完的完全一致，一题一条，无重复、无丢失。
- 断点续测的做法：开局时把 `TestSession`（未作答状态）存进新表 `test_checkpoint`（迁移 `v3-test-checkpoint`，追加在末尾）。进度不另存，以 `observation` 表为准，续测时按 session 取出已答的题 replay，已答的题不会重新写入。完成后写 `completed_at`。
- 令牌存储：合并 05 后统一用 05 的 `Sync/TokenStore.swift`（`readToken` / `saveToken` / `deleteToken`，Keychain）。04 自己那份已删掉，只保留 `Onboarding/PATFormat.swift`，负责格式检查（只接受 `github_pat_` 或 `ghp_` 开头）。`AppModel.tokenStore` 和 `SyncModel` 用的是同一个实例。首次启动保存令牌后调用 `sync.tokenChanged()`（这是给 SyncModel 新加的一个小方法）。Keychain 在卸载后仍会保留，所以全新安装第一次启动时，`AppModel.init` 会在创建 SyncModel 之前删掉旧安装留下的令牌，这样也不会删掉 05 的 DEBUG `LE_GITHUB_TOKEN`。
- 首次启动：`Onboarding/` 下的 `OnboardingModel` 和 `OnboardingView`，作为 `Flow.onboarding` 全屏显示：欢迎 → 粘贴 PAT（可跳过）→ 基线测试介绍（「开始基线测试」或「稍后再做」）。离开第三步时在 UserDefaults 写 `onboarding.completed`。
- 「测试」标签：有未完成的基线测试时显示「已答 N / 约 M 题 · 继续基线测试」；从未做过时显示「开始基线测试」；做完后不再显示。基线测试点 ✕ 会先弹窗确认（「退出后下次从这里继续……」）。结果页标题按测试种类显示。设置页新增「测试 › 重做基线测试」，确认后开始一场新的基线测试，旧记录保留。
- 模拟器验证（新建的 iPhone 17 / iOS 27 模拟器，实际点按屏幕操作）：
  - 全新安装后依次出现三步。用一个测试假令牌点「保存」后显示「令牌已保存到钥匙串」。
  - 在 App 容器里 grep 这个令牌，SQLite、UserDefaults 和其他文件都没有命中，App 日志里也没有。
  - 重新打开 App 后不再出现首次启动流程。
  - 卸载重装后走「先跳过」也能开始基线测试，旧令牌已被清除。
  - 基线测试一共中断两次：手答 3 题后杀进程，autoplay 答到 200 题后再杀进程。每次重开都从断点续上（续测的第一题就是上次停下的那题），最终 710 条 Observation 全部属于同一个 session，`lemma+source` 互不重复，数量等于题目总数，checkpoint 已标为完成。
  - 设置里「重做基线测试」会开始一场新的基线测试。
- 合并 05 后在新模拟器上复测：首次启动保存的令牌能在设置的「GitHub 令牌」里显示为「已保存在钥匙串」。用假令牌同步时显示「令牌无效」，符合预期。迁移顺序是 `v2-outbox` 在前，`v3-test-checkpoint` 在后。
- 修复：`TestFlowModel.start()` 在 await 期间可能被 `.task` 重复调用，导致生成两个 checkpoint。现在加了只启动一次的保护。

**说明**

- 这次模拟器用的是 fixture 词库（这个 worktree 里没有全量词库），已掌握词少，所以抽查只有 23 道（配置是 68 道）。重做时没测过的词也不够，题量降到 600 道。界面上写「约 M 题」就是这个原因，换成全量词库后不会出现。
- 「稍后在设置里补 PAT」用的是 05 设置页里的「保存/替换令牌」。
- PAT 只做格式检查，不在线验证（真实仓库要等 02）。
