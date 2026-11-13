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

**Status:** resolved

- [x] 校验脚本对每条规则都有合格和不合格的夹具测试
- [x] 在真实 `english-data` 上手动运行 `/word-plan` 一次，生成并提交一份合格计划
- [ ] 定时任务已配置，失败时桌面 App 有通知
- [x] App 拉到新计划后按它出新卡，摘要显示正确
- [x] 黄字提醒和"计划已用完"在对应条件下出现，平时不显示

## Comments

**已完成（agent）**

- `english-data-template/`（复制进私有仓库 `english-data` 的文件）：
  - `.claude/skills/word-plan/SKILL.md`：只能手动或定时任务调用（`disable-model-invocation`），`$ARGUMENTS` 是临时要求，原样写进 `instruction`。步骤：`git pull --rebase` → 汇总 → 选词 → 写 `plan/<今天>.json` → 校验（最多修 2 次，仍不过就还原文件、以 `word-plan 失败：` 结束）→ 只 add 计划文件、首行写摘要、push 被拒 rebase 后重试一次。选词准则、说明写法、`focus_targets`、`daily_new` 的定法都在 skill 里。
  - `.claude/settings.json`：无人值守运行需要的最小权限（git pull/add plan/commit/push、两个脚本、写 `plan/`）。
  - `scripts/word_plan/`（Python 3.9+ 标准库，macOS 自带的 python3 就能跑）：`common.py` 读 Observation、`words.tsv`、`plan/`，卡片规则照 CardLedger（有 review 即有卡、8 次"忘了"成 Leech、30 天或 relearn 重置、首评太简单暂停）；`summary.py` 输出摘要（`now`、每日上限、未排想学词、`pool_size`、约 400 个分桶候选 wish/fuzzy/target、活跃卡 4 档计数、未来 7 天到期、Leech、上一份计划剩余），`--out` 写文件；`validate.py` 每条问题一行 `[code] 消息`，退出码 0/1。
  - `words.tsv` 默认从 `https://raw.githubusercontent.com/<origin 的 owner>/english-profile/main/words.tsv` 下载，也可 `--words 路径或URL`。
  - 测试：`python3 -m unittest discover -s english-data-template/scripts/word_plan/tests`，33 个，夹具在 `tests/fixtures/`。校验规则（json、fields、daily-new、unknown-lemma、duplicate、has-card、mastered、wish-missing、too-few 含候选不足例外、focus-targets、note-length）各有合格和不合格用例。CI：`.github/workflows/word-plan.yml`（Python 3.9）。
  - 补充的规则：`daily_new` 必须在 1 到每日上限之间（`daily-new`）；Mastered 的想学词不要求排入，摘要里列为 `skipped_wishes`。易混词间隔只靠提示约束（skill 要求相隔至少 3 天的位置）。
- `EnglishCore`：
  - `StudyPlan.instruction` 改成 `String?`（定时运行写 `null`，原来解码会失败）。
  - `PlanStatus`（StudyComposer）：`current / missing / usedUp / stale(days) / runningLow(remaining)`，优先级 用完 > 停更 > 不够 2 天。剩余 = 计划里还能出新卡的词（无卡、非 Mastered、在词库），每天 = min(计划 daily_new, 上限)。`StudySession.planStatus` 在 compose 时算好。10 个新测试。
  - `GitHubClient.listDirectory` 和 `latestStudyPlan(repo)`：列 `plan/`，取文件名日期最大的 `YYYY-MM-DD.json` 读出来。3 个新测试，假 GitHub 支持目录列表。
- App（只做追加）：`StudyFlow/PlanStore.swift` 存最新计划（Application Support `study-plan.json`，离线可用，解码失败保留旧计划）；`SyncModel` 每次同步推完 outbox 后拉最新计划（`onStudyPlan` 回调，失败不改同步状态）；`AppModel` 加 `plans` 一行；`studyPlan` 改读 `plans.plan`，07 的示例计划只在 DEBUG + `LE_SAMPLE_PLAN=1` 且还没拉到计划时使用。"学习"标签：摘要放在今日新词数下方，下面一行黄字（深黄色 + 警告图标）：`学习计划 N 天未更新，去检查选词规划` / `学习计划只剩 N 个新词，不够 2 天，去检查选词规划` / `学习计划已用完，去跑一次选词规划` / `还没有学习计划，去跑一次选词规划`；平时不显示。
- 模拟器验证（新建 LE-ticket08，用完已删除；`App/scripts/fake-github.py` 新增 `--seed DIR`，把 `DIR/plan/*.json` 当作 Mac 提交的文件，支持目录列表）：放两份计划 11-10 和 11-13，App 拉到 11-13 那份，显示其摘要和"新词 4"，无黄字；先自动做一次短测，再自动学习：新卡按计划顺序出（authority 太简单 → 补 continent，complex、symptom、respective），SQLite 里的 review 行与计划顺序一致。然后换服务器上的计划重开 App：35 词当天计划无提示；5 天前的计划显示"4 天未更新"；剩 7 词（每天 4）显示"只剩 7 个新词"；全部已建卡显示"学习计划已用完"，新词 0、只剩复习。

**未验证 / 留给人（需要 02 的真仓库）**

- 真实 `/word-plan` 运行（第二个框）：
  1. 把 `english-data-template/.claude/` 和 `english-data-template/scripts/word_plan/`（可不带 `tests/`）复制到 Mac 上 clone 的 `english-data` 根目录，提交推送。
  2. 确认 `english-profile` 上已有 `words.tsv`（06 的流水线发布；在那之前可用 `profile-engine profile` 本地生成，跑 skill 时说明 `--words` 路径）。
  3. 确认这个 clone 里 `git push` 不需要交互（SSH 或 `gh auth setup-git`）。
  4. 在 clone 根目录启动 Claude Code，输入 `/word-plan`（可带一句要求）。成功时会推送 `plan/YYYY-MM-DD.json`；iPhone 上点"立即同步"后"学习"标签显示新摘要。
- 定时任务（第三个框）：Claude 桌面 App → 定时任务 → 新建：每天 07:30，工作目录选上面的 clone，提示词 `/word-plan`，模型默认即可；macOS 设置里允许 Claude 发通知。验证失败通知：把 clone 的 origin 暂时改成不存在的地址后"立即运行"一次，应收到失败通知，App 里几天后出现黄字；改回 origin。
- 06 的 `recent.json` 照抄最新计划的 `focus_targets`：属于 06 的流水线。合并后看过代码：`profile_publish.py` 的 `latest_plan` 取 `plan/` 中文件名日期最大的一份（与 App 同一规则），原样写 `focus_targets`；真实仓库上随 06 的端到端一起确认。
- 观察到的现象（不属于本票）：全新安装、没做过测试只做复习时，Profile 会把几乎所有词判为 Mastered，计划立刻显示"已用完"。正常流程先做基准测试（04）就不会出现。

2026-11-13：在真实 english-data 上手动跑通 `/word-plan`（plan/2026-11-13.json，80 词，daily_new 10），手机「学习」页能看到。候选池混入大量派生词和方言缩写，需和分档阈值一起调。定时任务待配置。
