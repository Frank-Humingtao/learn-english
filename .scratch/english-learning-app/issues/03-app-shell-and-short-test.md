# 03: App 骨架与短测

**What to build:** 学习者打开 App，看到"学习 / 测试 / 进度 / 设置"四个标签，能在"测试"标签完成一次完整的 3 到 5 分钟短测，并看到本地算出的结果。这是 App 的主干。

- SwiftUI App 壳：底部标签栏四个标签，测试和复习是全屏流程（以原型 `.scratch/english-learning-system/prototypes/11-app-screens/` 的方案 A 为准）。
- Test Engine：
  - 在 P≈0.5 附近随机抽从未测过的真词；
  - 每次现生成假词，约占 Yes/No 题的四分之一；
  - 约 10% 的题抽查 Mastered 词；
  - 另有 5 到 8 道中文四选一释义核验题，从答"认识"的词里抽，带"不认识"选项，干扰项取自词典中同词性、词频相近的其他词的中文释义。
- 每作答一题就写一条 Observation 到本地 SQLite（通过 GRDB），字段是 lemma、时间、来源、结果、反应时、会话编号，并标出假词。
- 结果页：估计词汇量及范围、较上次的变化、新发现的 Target 词数、抽查对错、假词误认数。数字由 Profile Engine 在本机计算。
- 测试流程左上角 ✕ 可以退出；当天已测过也能再测。

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] 在模拟器里能从"测试"标签完整做完一次短测并看到结果页
- [ ] 选题测试：题目集中在 P≈0.5 附近、不重复已测词、假词和抽查比例正确、干扰项来自同词性同频段
- [ ] 每题作答都落成一条本地 Observation，退出 App 后仍在
- [ ] 结果页数字与对同一组 Observation 运行 Profile Engine 命令行的结果一致
