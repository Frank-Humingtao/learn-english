# 02: 创建仓库与令牌

**What to build:** 让后续的同步和发布有真实的落脚点。这一步需要学习者本人在 GitHub 上操作，agent 提供逐步清单（可以用 `wizard` skill 生成交互式向导）。

- 建私有仓库 `english-data` 和公开仓库 `english-profile`。
- 建两个 fine-grained PAT：
  - iPhone 用：只授权 `english-data`，Contents 读写。
  - Actions 用：只授权 `english-profile`，Contents 和 Issues 写，有效期取最长。
- Actions 用的令牌存进 `english-data` 的 Secrets；iPhone 用的令牌由学习者在 App 里粘贴，不写进任何文件。
- 在 `english-profile` 建 `progress-report` label。

**Blocked by:** None (can start immediately)

**Status:** ready-for-human

- [ ] 两个仓库都已存在，可见性正确
- [ ] 两个令牌的授权范围与上面一致，没有多余权限
- [ ] Actions 令牌已存进 `english-data` 的 Secrets
- [ ] `progress-report` label 已创建
- [ ] 令牌值没有出现在任何聊天记录、文件或提交里
