# 04: 首次启动与 Baseline Test

**What to build:** 第一次打开 App 时，学习者依次看到欢迎页、粘贴 PAT（可以跳过），然后被引导做约 30 分钟的 Baseline Test。基线测试可以中途退出，下次从断点继续。

- 首次启动三步：欢迎页 → 粘贴 GitHub fine-grained PAT（存进 Keychain，可跳过，稍后在设置里补）→ 基线测试介绍。
- Baseline Test 与短测共用测试流程，区别只在题量和时长。
- 断点续测：退出后再进入，从上次停下的地方继续，已答的题不丢。
- 设置页提供"重做 Baseline Test"。

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] 全新安装后首次启动依次出现三步，之后再打开不再出现
- [ ] 跳过 PAT 后能正常使用测试
- [ ] PAT 只存在 Keychain，不出现在 SQLite、日志或任何文件里
- [ ] 基线测试做到一半退出，重新进入后从断点继续，Observation 无重复、无丢失
- [ ] 设置里"重做 Baseline Test"可用
