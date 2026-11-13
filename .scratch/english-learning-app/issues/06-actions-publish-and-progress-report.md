# 06: Actions 重算、公开看板与 Progress Report

Status: resolved

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


- [x] 在夹具仓库上 dry-run，生成的文件内容符合上面的规定
- [x] 发报告的判定有测试：当天第一次测试才发、同日只更新、只复习不发、关闭上一份
- [ ] 真实仓库端到端：iPhone 做完一次短测，几分钟内公开仓库的档案和看板更新，并出现一份打开的 Progress Report
- [ ] 筛选"打开且带 `progress-report`"的 issue 列表始终只有一份
- [ ] 公开仓库里看不到任何复习时间线

## Comments

**已完成（agent）**

- 全部放在 `english-data-template/`，复制进私有仓库 `english-data` 即可：
  - `.github/workflows/publish-profile.yml`：`observations/**` 推到 main 时触发（也可手动），`concurrency: publish-profile`、不取消。owner 一律取 `github.repository_owner`。
    1. 先检查 `PROFILE_TOKEN`：未设置或访问 `english-profile` 不是 200 就报 `::error::` 并失败。
    2. Profile Engine：按仓库变量 `ENGINE_REPO`（默认 `<owner>/learn-english`）、`ENGINE_REF`（默认 `main`，建议固定到 tag）稀疏检出代码仓库，在 `swift:6.0` 容器里构建 `--static-swift-stdlib` 的 `profile-engine`。词库用 `build_lexicon.py --download` 在 job 内构建。二者按引擎 commit 存进 Actions cache。BNC/COCA 和 ECDICT 原文件放在 `$RUNNER_TEMP`，构建完立即删除。Wiktextract 用空占位文件跳过，不下载：例句和音频只给 App 用，不影响档案，但 Actions 端 `lexicon_version` 因此和 App 的不同（排名完全相同）。代码仓库是私有的话，再加一个只读 secret `ENGINE_TOKEN`。
    3. 检出 `english-profile` → `scripts/profile_publish.py build` → 有变化就提交并推送 → `report --commit <sha>` 发报告。
  - `scripts/profile_publish.py`（只用标准库）：
    - `build`：引擎用 `--as-of 现在` 运行，原样写出 `summary.json` 和 `words.tsv`。
      - `recent.json`：`newly_mastered` 由本次和上次发布的 `words.tsv` 对比得出，每项 `{lemma, rank, date}`，保留 7 天，首次运行只当基线。`focus_targets` 照抄最新的 `plan/YYYY-MM-DD.json`，没有计划时为 `[]`，`focus_targets_from` 记下来源。
      - `history.json`：每天一条词汇量，用来画曲线。
      - `README.md`：Mermaid `xychart-beta` 曲线、三类词、近一周新掌握的词、最近测试日期、连续天数、固定报告地址（打开且带 `progress-report` 的 issue 列表和对应 API URL），以及 CC BY 4.0 和数据来源。
    - `report`：`decide_report(observations, reports, tz)` 是纯函数。只看 `source == "test"` 的记录，"当天"按 `REPORT_TZ`（默认 Asia/Shanghai）计算。最新一份报告的正文里藏一个水位 `<!-- progress-report-state: {"last_test_ts": …} -->`，比它新的测试才算新测试：
      - 新测试落在新的一天 → create；
      - 和最新报告同一天 → update；
      - 没有新测试（只复习）→ none；
      - 迟到的旧日测试 → none；
      - 每种情况都关闭除目标外所有打开的报告。先建新的再关旧的。
      - 不依赖 push 的 diff，所以 concurrency 丢掉排队中的 run 也不会漏判。
      - 正文是中文摘要加 JSON 块（规定的 8 个字段，`vocab_size` 含 `low/high/change`，`newly_mastered` ≤30，`focus_targets` ≤50，`words_tsv_url` 是固定到 `profile_commit` 的 raw 链接），不含复习明细，也不含想学和偏好。401/403 和缺令牌时抛 `TokenError` 并给出明确信息。
    - `dry-run`：用本地 `issues.json` 代替 GitHub Issues，把档案写到 `<out>/english-profile`（下次运行时作为上一次的状态），判定结果写到 `report-decision.json`。
  - 测试：`python3 -I english-data-template/scripts/test_profile_publish.py`，共 15 个。
    - 判定：首次测试、隔天新建并关闭旧的、同日更新、只复习不发、时区换日、只留一份打开、迟到的旧测试。
    - 夹具仓库 `scripts/fixtures/english-data`（Observation 来自 EnglishCore 的夹具，另有两份计划）上的整条流水线，引擎用 `fixtures/fake_engine.py`：文件内容、同日更新、只复习不动 issue、隔天新建并关闭旧的、公开输出里没有任何复习时间戳和复习字段、没有计划时 `focus_targets` 为空。
    - 令牌缺失和 401。
  - 用真实的 `profile-engine` 加夹具词库手动 dry-run 过两天的数据，结果正确。`.github/workflows/englishcore.yml` 新增 `publish-dry-run` job，在 Linux 上跑同样的测试和真实引擎 dry-run。

**安装**：把 `english-data-template/.github/` 和 `english-data-template/scripts/profile_publish.py` 复制进 `english-data`。在 Secrets 里加 `PROFILE_TOKEN`；代码仓库名不是 `learn-english`，或者想固定版本时，再设变量 `ENGINE_REPO` 和 `ENGINE_REF`。`english-profile` 需要已经有初始提交（checkout 空仓库会失败）。

**未验证 / 留给人（需要 02 的真实仓库）**

- 真实仓库端到端（第 3 个框）。第一次 run 词库缓存未命中，要额外花几分钟构建。
- "只有一份打开"（第 4 个框）和"看不到复习时间线"（第 5 个框）：dry-run 测试里都成立，但要在真实仓库上确认。注意 `english-profile` 的提交时间本身会暴露同步时间，不过不含任何逐词的复习记录。
- workflow 本身没在 GitHub 上跑过（docker 构建步骤、`find` 二进制路径、Actions cache）。
