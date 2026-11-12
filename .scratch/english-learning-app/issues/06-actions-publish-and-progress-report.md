# 06: Actions 重算、公开看板与 Progress Report

**What to build:** 私有仓库收到新的 Observation 后，GitHub Actions 自动重算 Learner Profile，更新公开仓库 `english-profile` 的档案文件和 README 看板；当天第一次测试后，自动发一份 Progress Report issue。外部 AI 工具从一个固定地址就能读到最新一份。

- 触发：`english-data` 的 `observations/` 有 push 时。用 concurrency group 串行执行，每次从全部 Observation 重算。
- 用 Profile Engine 命令行生成并提交到 `english-profile`：
  - `summary.json`：词汇量及区间、三类词数、更新时间；
  - `words.tsv`：lemma、Word Band、P、词频排名；
  - `recent.json`：近期新掌握的词，以及 `focus_targets`（有 Study Plan 时原样照抄，没有时先留空）；
  - `README.md` 看板：词汇量曲线、三类词数、近一周新掌握的词、最近测试日期和连续天数、最新报告链接，并注明数据来源与许可（派生数据 CC BY 4.0）。
- Progress Report：
  - 当天第一次测试同步后，发新 issue，标题 `Progress Report YYYY-MM-DD · 约 N 词族`，带 `progress-report` label；
  - 正文是中文摘要加 JSON 块，字段为 `schema_version`、`generated_at`、`profile_commit`、`vocab_size`（含区间和变化）、`band_counts`、`newly_mastered`（≤30）、`focus_targets`（≤50）、`words_tsv_url`（固定到 `profile_commit`）；
  - 同日再测只更新当天这份；发新报告时关闭上一份但保留；只复习不发；
  - 正文不含内容偏好和复习明细。
- 令牌失效时工作流显式失败。

**Blocked by:** 01, 05

**Status:** ready-for-agent

- [ ] 在夹具仓库上 dry-run，生成的文件内容符合上面的规定
- [ ] 发报告的判定有测试：当天第一次测试才发、同日只更新、只复习不发、关闭上一份
- [ ] 真实仓库端到端：iPhone 做完一次短测，几分钟内公开仓库的档案和看板更新，并出现一份打开的 Progress Report
- [ ] 筛选"打开且带 `progress-report`"的 issue 列表始终只有一份
- [ ] 公开仓库里看不到任何复习时间线
