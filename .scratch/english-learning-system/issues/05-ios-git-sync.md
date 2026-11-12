# 调研：iPhone 上的 Git 同步可行性

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

iOS App 读写 GitHub 仓库有哪些方式：App 内嵌 Git（libgit2/SwiftGit2 等）还是调用 GitHub REST/GraphQL API（Contents API、Git Data API）？各自在离线学习、冲突处理、高频提交（每次复习都要记录）、API 速率限制、认证（fine-grained token、GitHub App）方面的表现如何？有没有已经这样做的 iOS App 可以参考？给出「仓库作为唯一真相源」是否可靠的初步判断与主要风险。

## Answer

- 不在 App 里内嵌 libgit2：SwiftGit2 没有 push，SwiftGitX 还不成熟，冲突处理也得自己写。改用 GraphQL `createCommitOnBranch`，带上 `expectedHeadOid` 做乐观并发控制，一次提交多个文件。
- App 采用本地优先：每次复习只写本地 SQLite 和待提交队列（outbox），在会话结束或 App 进入前台时批量提交。如果每张卡都提交一次，会撞上 GitHub 每小时约 500 次内容写入的次级限额。
- 复习记录写成按月拆分的追加式 JSONL。派生出来的 Learner Profile 和 Progress Report 只由一个写入方生成，iPhone 不直接改。
- 认证用 fine-grained PAT（只授权这一个仓库，Contents 读写），存进 Keychain。iOS 后台任务的运行时机由系统决定，不能依赖后台同步。
- 初步判断：仓库可以作为「最终一致的持久化真相源」，但不能当实时后端。主要风险是公开仓库暴露学习数据隐私，其次是离线期间本地未同步的数据可能丢失，以及多个写入方之间的冲突。
- 参考的现有 App 有 GitSync（基于 libgit2）和 Working Copy（提供 Shortcuts 动作）。

[调研笔记](../research/05-ios-git-sync.md)
