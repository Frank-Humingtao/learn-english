# 调研：iPhone 上的 Git 同步可行性

来源工单：[05-ios-git-sync](../issues/05-ios-git-sync.md)
调研日期：2026-11-11

## 问题

iOS App 读写 GitHub 仓库有哪些方式：App 内嵌 Git（libgit2 / SwiftGit2 等），还是调用 GitHub REST/GraphQL API（Contents API、Git Data API）？这两类方式在离线学习、冲突处理、高频提交（每次复习都要记录）、API 速率限制、认证（fine-grained token、GitHub App）上各自表现如何？有没有已经这样做的 iOS App 可以参考？「仓库作为唯一真相源」是否可靠？

## 1. 两条技术路线

### 1A. App 内嵌 Git（本地 clone + commit + push）

- **libgit2**：C 实现的 Git 库，仍在活跃维护，最近一次 push 是 2026-10（[repo](https://github.com/libgit2/libgit2)）。README 里有专门的 iOS 交叉编译章节，用 iOS cmake toolchain 构建（[README#ios](https://github.com/libgit2/libgit2#ios)）。许可证是 GPLv2 加 Linking Exception，闭源 App 也可以链接（[README#license](https://github.com/libgit2/libgit2#license)）。
- **SwiftGit2**：libgit2 的 Swift 绑定，最后一次提交是 2025-09（[repo](https://github.com/SwiftGit2/SwiftGit2)）。`Repository.swift` 只公开了 `clone`、`fetch`、`add`、`commit`、`checkout`、`status` 等方法，**没有 push 和 merge**（[Repository.swift](https://github.com/SwiftGit2/SwiftGit2/blob/master/SwiftGit2/Repository.swift)）。所以要么自己用 C API 补上，要么换一个库。
- **SwiftGitX**：较新的 libgit2 封装，支持 SPM 和 async/await，最近一次 push 是 2025-12（[repo](https://github.com/ibrahimcetin/SwiftGitX)）。源码里有 `Repository+push.swift` 和 push 测试（[源码树](https://github.com/ibrahimcetin/SwiftGitX/tree/main/Sources/SwiftGitX/Repository)），但 star 数只有 160 左右，版本还是 0.x，成熟度有限。
- **objective-git**：官方的 ObjC 绑定，2023-09 以后就没有 push 了（[repo](https://github.com/libgit2/objective-git)），不建议采用。

**这条路线的特点**
- 离线：天然支持。本地有完整仓库，离线时照常 commit，联网后再 push。
- 冲突：要自己做 fetch、merge 或 rebase。libgit2 提供 merge 原语，但冲突解决的 UI 和策略都得自己写。
- 高频提交：本地 commit 没有成本，push 可以批量做。GitHub 建议单个仓库每分钟不超过 6 次 push（[Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits)）。
- 速率限制：Git 协议的 push 和 fetch 不走 REST 的点数配额（REST 的限制见下文）。
- 代价：要编译 libgit2、OpenSSL/mbedTLS、libssh2 三套 C 依赖，二进制体积和维护负担都偏大。冲突处理也是一个相当完整的子系统。

### 1B. 调用 GitHub API（不在本地保存 Git 仓库）

- **Contents API**（`PUT /repos/{owner}/{repo}/contents/{path}`）：一次请求提交一个文件。更新文件时必须带上被替换 blob 的 `sha`。响应码里有 409 Conflict，422 表示 "Validation failed, or the endpoint has been spammed"。文档还明确要求不要同时调用这个接口和 Delete 接口："the concurrent requests will conflict… You must use these endpoints serially"。读取方面，1 MB 以内的文件支持全部功能，1–100 MB 只能用 raw 或 object 媒体类型（[Contents API](https://docs.github.com/en/rest/repos/contents?apiVersion=2022-11-28)）。
- **Git Database API**（blobs → trees → commits → refs）：可以把多个文件放进一个原子 commit。`base_tree` 会保留没有列出的文件（[Trees](https://docs.github.com/en/rest/git/trees?apiVersion=2022-11-28)）。更新 ref 时，`force=false` 只允许 fast-forward，"make sure you're not overwriting work"，可以拿来做乐观并发控制（[Refs](https://docs.github.com/en/rest/git/refs?apiVersion=2022-11-28)）。每次提交需要 3–4 个写请求。
- **GraphQL `createCommitOnBranch`**：一次 mutation 就能提交多文件的增加和删除。必填参数 `expectedHeadOid` 是「提交前分支 head 应当处于的 commit」，相当于自带 compare-and-swap。生成的 commit 会被 GitHub 自动签名（[GraphQL commits 参考](https://docs.github.com/en/graphql/reference/commits)）。文档没有写 head 不匹配时具体返回什么错误，需要实测确认。

**这条路线的特点**
- 离线：API 本身无法离线。App 必须在本地自建存储和待提交队列（outbox），联网后再回放。
- 冲突：可以用 `expectedHeadOid` 或 fast-forward-only 的 ref 更新发现冲突。发现后重新拉取最新内容，在本地合并，再重试。
- 速率限制（[REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)）：
  - 主限额：PAT 和用户令牌合计每小时 5,000 次请求。
  - 次级限额：并发不超过 100；产生内容的请求大约**每分钟 80 次、每小时 500 次**；REST 每分钟 900 点，大多数写请求每次 5 点；GraphQL 每分钟 2,000 点。
  - 文档特别说明，次级限额可能不经通知就调整，而且无法查询当前状态。
- 估算：如果每次复习都立即提交一次，按 Contents API 计算，每小时最多约 500 次；按 Git Database API（每次提交 4 个写请求）计算，每小时只有约 125 次。专注复习时一小时 200 张卡很常见，会**超出或逼近次级限额**，另外每张卡还要等一次网络往返。如果改成每 N 张卡或每次会话结束时批量提交一次，用量就远低于限额。

## 2. 认证

- **Fine-grained PAT**：只能属于一个所有者，可以限定到单个仓库，`Contents` 权限分 read 和 write 两档。有效期可以设为永不过期，但可能被策略限制。每个用户最多 50 个（[Managing PATs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)）。单用户场景下最简单：在 App 里粘贴一次，存进 Keychain。Keychain 的用法属于常规 iOS 实践，本次没有单独核对 Apple 文档。
- **GitHub App 用户令牌**：
  - 有效期：access token 默认 8 小时，refresh token 6 个月（[Generating a user access token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)）。
  - 客户端密钥：device flow 的轮询请求只需要 `client_id`，所以原生 App 不必内置 client secret（同一页面）。
  - PKCE：2025-07 起 GitHub 支持 PKCE，并建议使用（[changelog](https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/)）。
  - 评价：更规范，但要实现刷新令牌的逻辑。半年没打开 App，refresh token 就会过期，需要重新授权。
- 不论用哪种方式，都**不能**把令牌打包进 App，也不能写进仓库。

## 3. 后台同步的限制（iOS）

- `BGAppRefreshTask` 何时运行"由系统决定"，每次最多约 30 秒。静默推送超过每小时 3 次会被系统限流（[Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)）。
- 结论：**不能指望后台按时同步**。同步应该放在 App 进入前台或会话结束时触发，再用 `beginBackgroundTask` 争取几秒钟，让请求发完（同一页面）。

## 4. 可以参考的现有 App

- **Working Copy**（iOS 上的 Git 客户端）：
  - 提供 Shortcuts 动作，包括 Commit、Pull、Push 和 Sync Repository。Sync Repository "commits everything modified, pulls and then pushes"。
  - 支持可选的 Background Sync，文档说明它依赖定位权限，耗电也更多。
  - 仓库会暴露给 Files App（[Working Copy 手册](https://workingcopy.app/manual/)）。
  - 手册没有写明底层用的是哪个 Git 引擎（未核实）。
  - 可以借鉴的思路：自己的 App 只读写 Working Copy 暴露的文件夹，由 Working Copy 和 Shortcuts 负责 Git。代价是多依赖一个付费第三方 App，自动化也更脆弱。
- **GitSync**（Android 和 iOS，开源）：Flutter 应用，Git 引擎用的是 Rust `git2`（即 libgit2）的 vendored 版本（[Cargo.toml](https://github.com/ViscousPot/GitSync/blob/main/rust/Cargo.toml)）。支持 fetch、pull、commit、push、移动端冲突解决、断网恢复后自动重试，可以通过 iOS 快捷指令或自动化触发同步（[README](https://github.com/ViscousPot/GitSync)）。它证明了「iOS 上内嵌 libgit2 做双向同步」能做出来并上架 App Store。
- **Obsidian Git 插件**：移动端用的是 isomorphic-git（纯 JS 实现）。作者明确写了移动端"very unstable"，而且有内存和仓库大小方面的限制，并推荐改用 GitSync（[README](https://github.com/denolehov/obsidian-git#mobile-support-experimental)）。这是一个反面教训：移动端的 Git 实现质量直接决定同步是否可靠。

## 5. 仓库规模

- GitHub 建议仓库磁盘占用不超过 10 GB，单个对象建议不超过 1 MB（硬上限 100 MB），单次 push 上限 2 GB（[Repository limits](https://docs.github.com/en/repositories/creating-and-managing-repositories/repository-limits)）。
- 估算：每次复习一个 commit，一年下来大约有几万个 commit，对 GitHub 来说问题不大，但历史会很嘈杂。如果所有复习记录都写进同一个大 JSON 文件，每次提交都会生成一个新的完整 blob，仓库会膨胀。建议按天或按月拆成追加式（append-only）的 JSONL 文件。

## 6. 对比小结

| 维度 | 内嵌 libgit2 | GitHub API（GraphQL `createCommitOnBranch`） |
|---|---|---|
| 离线 | 天然支持 | 需要自建本地存储和 outbox |
| 冲突 | 完整的 merge/rebase，要自己实现 | 用 `expectedHeadOid` 做 CAS，发现冲突后在应用层合并重试 |
| 高频写 | 本地 commit 免费，批量 push | 必须批量，否则会撞上每小时约 500 次的次级限额 |
| 依赖和体积 | C 库交叉编译，体积大 | 只需要 URLSession，很轻 |
| 实现成本 | 高 | 低到中 |
| 认证 | HTTPS 加 PAT | PAT 或 GitHub App 令牌 |

## 推荐

1. **采用本地优先（local-first）架构**。App 内的 SQLite 或 SwiftData 是运行时的工作副本，每次复习只写本地，并记入 outbox。GitHub 仓库是**持久化的规范存储**，不承担在线数据库的角色。
2. **同步方式选 GraphQL `createCommitOnBranch`，不内嵌 libgit2**。单用户、数据量小、需求简单时，API 路线最轻。会话结束或 App 进入后台时，把 outbox 合成**一个**多文件 commit 一次提交，用 `expectedHeadOid` 防止覆盖。如果 head 不匹配，就拉取最新内容，在本地合并后重试。
3. **数据格式要设计成几乎不会冲突**。
   - 复习记录写成追加式的事件日志，例如 `reviews/2026/2026-11.jsonl`。可以考虑按设备或写入方分文件，这样合并只是拼接。
   - Learner Profile 和 Progress Report 这类派生数据**只能由一个写入方**生成，例如 GitHub Action 或 Mac 端脚本，iPhone 不直接改。
4. **认证先用只授权单个仓库、只有 Contents read/write 的 fine-grained PAT，存进 Keychain**。等以后需要多设备或更规范的授权时，再迁移到 GitHub App 的 device flow 或 PKCE。
5. **不依赖 iOS 后台同步**。在前台和会话结束时同步，并在界面上显示「未同步 N 条」。

## 初步判断：仓库作为唯一真相源

**有条件可行。** 前提是把「真相源」理解为「最终一致的持久化规范存储」，而不是「每次复习都实时写入的在线后端」。按上面的推荐架构，单用户场景下是可靠的。

**主要风险**
- **公开仓库的隐私问题**：完整的学习记录、生词和时间戳都会公开，而且一旦进入 Git 历史，就很难彻底删除。建议重新评估是否改用私有仓库，或者只公开派生出来的 Progress Report。
- **次级速率限额不透明**：限额可能随时调整，也无法查询（[REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)）。每次复习都直接提交必然会出问题，必须批量。
- **两个真相并存的窗口期**：离线期间本地数据比仓库新。如果设备丢失，或者 App 被删时还有没同步的 outbox，这部分数据就会丢失。需要同步状态提示，可能还需要 iCloud 或本地备份兜底。
- **多个写入方导致冲突**：iPhone、Mac 脚本和 GitHub Action 如果同时改同一个文件，就会冲突。需要严格划分「谁写哪个文件」。
- **令牌生命周期**：PAT 过期，或 GitHub App 的 refresh token 半年后失效，都会让同步悄悄中断。需要显式的错误提示。
- **`createCommitOnBranch` 的冲突错误格式文档里没有写**，需要在原型阶段实测。
