# 02: 创建仓库与令牌

Status: resolved

**What to build:** 让后续的同步和发布有真实的落脚点。这一步需要学习者本人在 GitHub 上操作，agent 提供逐步清单（可以用 `wizard` skill 生成交互式向导）。

- 建私有仓库 `english-data` 和公开仓库 `english-profile`。
- 建两个 fine-grained PAT：
  - iPhone 用：只授权 `english-data`，Contents 读写。
  - Actions 用：只授权 `english-profile`，Contents 和 Issues 写，有效期取最长。
- Actions 用的令牌存进 `english-data` 的 Secrets；iPhone 用的令牌由学习者在 App 里粘贴，不写进任何文件。
- 在 `english-profile` 建 `progress-report` label。

**Blocked by:** None (can start immediately)


- [x] 两个仓库都已存在，可见性正确
- [x] 两个令牌的授权范围与上面一致，没有多余权限
- [x] Actions 令牌已存进 `english-data` 的 Secrets
- [x] `progress-report` label 已创建
- [x] 令牌值没有出现在任何聊天记录、文件或提交里

## Comments

**2026-11-13 · 已完成（学习者本人操作，agent 只读核实）**

用向导 `tools/setup-wizard/ticket02.sh` 完成。核实结果：

- `Frank-Humingtao/english-data`：PRIVATE，默认分支 `main`（带 README 初始提交，main 一开始就有 head，可用于 `expectedHeadOid`）。
- `Frank-Humingtao/english-profile`：PUBLIC，默认分支 `main`（带 README 初始提交）。
- label `progress-report` 已在 `english-profile` 创建。
- Secret `PROFILE_TOKEN` 已存进 `english-data` 的 Actions secrets（工单 06 的工作流用 `secrets.PROFILE_TOKEN`）。
- 令牌（学习者截图确认，两者都是 No expiration，都没有 user permissions）：
  - `english-iphone`：只授权 `english-data`；Metadata 只读 + Contents 读写。由学习者存在密码管理器里，之后在 App 设置里粘贴。
  - `english-actions-profile`：只授权 `english-profile`；Metadata 只读 + Contents 和 Issues 读写。
- 令牌值没有出现在聊天、文件、提交或日志里：secret 通过 `gh secret set` 从剪贴板/stdin 写入，每次写完都清空了剪贴板。

给工单 05 的提示：真实环境已具备。实测 `expectedHeadOid` 冲突时，需要学习者在本机用 `english-iphone` 令牌运行测试，令牌不要交给 agent。
