# 08: 选词规划 skill 与计划同步

**What to build:** Mac 上的 Claude 每天定时运行一次选词规划 skill `word-plan`，根据学习者的测试和复习表现写出 Study Plan 并提交到私有仓库；App 拉取最新计划作为新卡来源，在"学习"标签显示计划摘要，计划停更或用完时给出提醒。

- skill 放在 `english-data` 仓库里。定时：Claude 桌面 App 定时任务每天 07:30，在 Mac 上本地 clone 的 `english-data` 里运行；也可手动 `/word-plan [临时要求]`。
- 汇总脚本：把全部 Observation、最新的 `words.tsv`、上一份计划、设置和"想学"记录汇总成一份精简摘要，Claude 只读这份摘要。摘要包括约 400 个预分桶候选词（附 P、词频、测试历史、4 档评分计数）、活跃卡近期表现、未来 7 天到期数、Leech 清单、未排的"想学"词、每日上限、上一份计划剩余量。
- 选词准则：先排"想学"词，再排似懂非懂的词（P 在 0.3 到 0.7，或复习常评"模糊"），最后排其他 Target 词，同级高频优先；偏离要在说明里写理由；易混词至少间隔几天；在上限内按复习积压决定每天实际新词数。
- 输出 `plan/YYYY-MM-DD.json`：`schema_version`、`generated_at`、`daily_new`、`new_words`（有序，每项 lemma 和 note）、`focus_targets`（≤50）、`summary`（1 到 3 句中文）、`instruction`。选词说明用中文，每条不超过 40 字，不编造词义。
- 校验脚本：JSON 合法；lemma 都在词表里且不重复，不是已建卡或已掌握的词；"想学"词全部排入；条数 ≥ 每日数 × 7（候选不足时例外）；`focus_targets` ≤ 50；说明 ≤ 40 字。不合格时最多修正 2 次，仍不合格就不提交，以失败结束。
- 提交：先 pull --rebase，只 add 本次的计划文件，提交说明首行写摘要，push 被拒时 rebase 后重试一次。
- App：同步时拉取最新计划，替换 07 的示例计划；"学习"标签显示计划摘要；计划超过 3 天没更新或剩余新词不够 2 天时显示黄字提醒；计划用完时只做复习，并显示"学习计划已用完，去跑一次选词规划"。
- Actions 生成 `recent.json` 时，`focus_targets` 照抄最新计划。

**Blocked by:** 05, 07

**Status:** ready-for-agent

- [ ] 校验脚本对每条规则都有合格和不合格的夹具测试
- [ ] 在真实 `english-data` 上手动运行 `/word-plan` 一次，生成并提交一份合格计划
- [ ] 定时任务已配置，失败时桌面 App 有通知
- [ ] App 拉到新计划后按它出新卡，摘要显示正确
- [ ] 黄字提醒和"计划已用完"在对应条件下出现，平时不显示
