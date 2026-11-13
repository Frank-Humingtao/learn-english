# 05: 同步到私有仓库

**What to build:** 学习者的作答自动同步到私有仓库 `english-data`，界面清楚地显示同步状态：全部同步时什么都不显示，有积压时显示"未同步 N 条"，断网时提示离线，令牌出错时显示红条。

- 本地优先：新 Observation 进 outbox。一次测试或复习结束时、App 回到前台时，自动批量提交，提交到 `observations/iphone/YYYY-MM.jsonl`（只追加）。
- 提交方式：用 GraphQL `createCommitOnBranch`，带 `expectedHeadOid`。head 不一致时拉取最新 head 后重试一次，仍失败就把记录留在 outbox。不引入第三方 Git 或 GitHub 客户端库，也不依赖 iOS 后台任务。
- 第一步先用真实令牌和仓库实测 `expectedHeadOid` 冲突时的错误格式，再据此写死重试判断。
- 同步状态：
  - 已同步：不显示；
  - 未同步 N 条：导航栏右上角显示，点一下立即同步；
  - 离线：灰色"离线中，联网后自动同步"；
  - 令牌错误（未设置、过期、被撤销）：每页顶部常驻红条，写明原因和"记录都还在本机"，点击进设置。
- 设置页：同步状态、未同步条数、上次成功时间、仓库名、"立即同步"按钮；可替换 PAT 并显示令牌有效期。换好令牌后自动补交。

**Blocked by:** 02, 03

**Status:** resolved

- [ ] 冲突错误格式已实测，结果记进本票
- [x] 做完一次短测后，私有仓库出现对应的 JSONL 行，内容与本地一致
- [x] 针对假 GitHub 服务器的测试覆盖：批量提交、head 不一致后重试、401 进入令牌错误、离线、换令牌后补交
- [x] 四种同步状态在界面上按上面的规则显示
- [ ] 飞行模式下学习不受影响，联网后自动补交

## Comments

**已完成（agent）**

- `EnglishCore` 新增目标 `SyncCore`（零第三方依赖，Linux 下用 FoundationNetworking）：
  - `HTTPTransport` 协议是唯一的网络接缝；`URLSessionTransport` 把无网类 URLError 映射成 `TransportError.offline`。
  - `GitHubClient`：GraphQL `tokenInfo()`（viewer login + `GitHub-Authentication-Token-Expiration` 响应头）、`headOid`、`createCommit`（`createCommitOnBranch` + `expectedHeadOid`），REST `readFile(repo, path:, ref:)`（Contents API raw 媒体类型，404 返回 nil）。**08 读 Study Plan 直接用 `readFile`。**
  - `ObservationSyncer.push(_ items: [OutboxItem]) -> PushOutcome`：读 head → 按 `ref=head` 读当月文件 → 只追加远端没有的行 → 一次多文件 commit。head 不一致时从新 head 整套重做一次，再失败返回 `.failed`，记录留在 outbox。因为跳过远端已有的行，响应丢失后的重试不会重复写。
  - 冲突判断只在 `GitHubErrors.isStaleHead(type:message:)` 一处：`type == "STALE_DATA"` 或 message 含 `Expected branch to point to`。**这是按公开报告的格式写的，未实测**（见下）。
  - `SyncState` / `SyncStatus`：已同步（无待传，含离线时）/ 未同步 N / 离线 N / 令牌错误（missing、rejected、expired=401 且已过有效期、noAccess=令牌看不到仓库）。令牌错误优先、常驻；换令牌 `tokenReplaced` 清掉。
  - JSONL 行格式：`JSONEncoder` 紧凑、`sortedKeys`、nil 字段省略，每行一个 Observation，文件 `observations/iphone/YYYY-MM.jsonl`（月份取 UTC `ts` 前 7 位），以 `\n` 结尾。例：`{"lemma":"apple","lexicon":"lex-…","result":"yes","rt_ms":812,"session":"20261112T083000Z-3fa9","source":"test","ts":"2026-11-12T08:30:00.000Z"}`
  - 测试 23 个（`swift test --filter SyncCoreTests`），对着内存假 GitHub（`Tests/SyncCoreTests/FakeGitHub.swift`）：批量一次提交、跨月拆文件、追加保留旧行、head 被别人推进后重试成功、再次被推进则放弃且只重试一次、401、无令牌不发请求、无仓库权限、离线、响应丢失后不重复、换令牌后补交、状态推导、Contents 读文件、令牌有效期。
- `App/`：
  - outbox：迁移 `v2-outbox` 建 `outbox(observation_id)` 表 + `observation` 插入触发器（已有记录全部入队），所以 04/07 的写入路径不需要知道同步。查询在 `Store/OutboxStore.swift`。
  - `Sync/SyncModel.swift`（`AppModel.sync`）：触发点 = `AppModel.sessionEnded()`（测试结果页出现、任何全屏流程关闭；07 学习结束请调它）、回到前台（scenePhase .active）、NWPathMonitor 恢复联网、"立即同步"、换令牌。每批 500 条，用 `beginBackgroundTask` 争取几秒，不依赖 BG 任务。仓库 owner 由令牌的 viewer login 得出，仓库名固定 `english-data`，分支 `main`。
  - `Sync/TokenStore.swift`：最小 `TokenStore` 协议 + `KeychainTokenStore`（service `LearnEnglish.github`，account `english-data-pat`，ThisDeviceOnly）。**04 合并时二选一**；SyncModel 每次同步都从 store 读令牌，04 存进同一个 Keychain 项即可生效（存完调 `sync.syncSoon()`）。
  - UI：`.syncStatusChrome()`（四个标签页各加一行）= 导航栏右上"未同步 N 条"（点一下立即同步）/ 灰色"离线中，联网后自动同步"，以及顶部常驻红条（原因 + "记录都还在本机" + 点进设置）。设置页 `SyncSettingsSection`：状态、未同步条数、上次成功时间、仓库名、立即同步、替换 PAT（先用 GitHub 验证再存）、令牌有效期。
- 模拟器验证（独立模拟器，DEBUG 环境变量 `LE_GITHUB_API`/`LE_GITHUB_TOKEN` 指向本地假服务器 `App/scripts/fake-github.py`）：
  - 完整短测 86 条 → 假仓库 `observations/iphone/2026-11.jsonl` 86 行，与本地 SQLite 逐条（lemma/source/result/ts）一致，outbox 清空。
  - 截图确认：401 → 红条；服务器停掉 → 灰色离线提示；503 → "未同步 5 条"；恢复后自动补交、什么都不显示。

**未验证 / 留给人**

- 冲突错误格式实测（第一个框）：需要 02 的真仓库和令牌。做法：同一 `expectedHeadOid` 连发两次 `createCommitOnBranch`，看第二次的 `errors[0].type/message`，据此收窄 `GitHubErrors.isStaleHead` 并记到这里。
- 真仓库出现 JSONL（第二个框）：只对假服务器验证过，需要 02。
- 飞行模式 + 联网自动补交（最后一个框）：模拟器里用停服务器模拟了离线和恢复后补交；真机飞行模式和 NWPathMonitor 触发需要人在真机上试。
- 点击"未同步 N 条"、红条跳设置、设置页替换令牌没有实际点屏幕（无模拟器点击权限），逻辑都走 `SyncModel` 的同一方法。

2026-11-13：第一次真实 Baseline Test 的 710 条作答全部同步进 english-data，发布工作流按这些记录重算成功。冲突格式实测转到 GitHub issue #5，离线补交转到 #4。
