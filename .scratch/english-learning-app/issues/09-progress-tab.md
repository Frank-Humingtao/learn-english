# 09: 进度标签

**What to build:** 学习者在"进度"标签看到自己的长期变化：估计词汇量和曲线、三类词、各频段掌握率、连续学习天数，以及 Leech 清单；还能一键打开公开看板和最新的 Progress Report。

- 估计词汇量（词族数）及误差范围、随时间变化的曲线。
- Mastered / Target / Distant 三类词数的条形图；各词频段掌握率。
- 连续学习天数、最近测试日期。
- Leech 清单，每个词带"重新学"按钮。
- 外链：公开看板、最新 Progress Report（筛选打开且带 `progress-report` 的 issue 列表）。
- 所有数字由本机 Profile Engine 重算，页面注明公开看板会稍有滞后。

**Blocked by:** 06, 07

**Status:** ready-for-agent

- [ ] 用夹具 Observation 预置数据时，进度页各项数字与 Profile Engine 命令行一致
- [ ] 曲线能反映多次测试的变化
- [ ] Leech 清单里点"重新学"后，该词出现在当天新卡最前面
- [ ] 两个外链都能打开正确的页面
