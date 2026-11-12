# 进度汇报 issue 的格式

Type: grilling
Status: resolved
Assignee: humingtao
Blocked by: 04, 07
Part of: ../map.md

## Question

Progress Report 这一 issue 里放什么，怎样用最少的信息让外部 agent 做出定量推荐？尤其是如何表达「最近学的词」和 Target 词？多久发一次、如何命名、旧的 issue 怎么处理？

### 来自「调研：Grok Bot 如何读取 GitHub」的补充

- 读取方是 GitHub Actions：由 issue 事件和定时任务触发，调用 xAI API。报告格式要让工作流直接解析，建议用"Markdown 加 JSON 块"。
- 仓库连续 60 天没有活动时，定时工作流会被自动停用。需要确认发 Progress Report 是否算作活动。

## Answer

- **系统的终点**：本系统只负责发布一份谁都能公开读取的 Progress Report，不指定读取方，也不和读取方交互。谁来读、怎么做推荐、推荐送到哪里，都由学习者在本系统之外自行搭建。票 04 设想的主链路（Actions 调用 xAI API 并写回评论）不再属于本系统。
- **什么时候发**：每次 Vocabulary Test 同步后，Actions 重算学习档案，当天第一次测试就自动发一份新报告。同一天再测只更新这一份，不新开。只复习不测试时不发。
- **旧报告**：发新报告时，Actions 自动关闭上一份，保留不删，上一份下面的推荐评论也一起保留。任何时候只有一份报告是打开的。
- **怎么找到最新一份**：每份都带 label `progress-report`。固定地址是 `english-profile` 仓库里筛选"打开且带 `progress-report`"的 issue 列表，README 看板上也放这个链接。任何外部工具配置这一个地址就行。
- **标题**：`Progress Report YYYY-MM-DD · 约 N 词族`。只给人看，机器不靠标题解析。
- **正文**：先用几行中文 Markdown 写给学习者看，再放一个 JSON 块（键用英文），读完这一页就能判断水平：
  - `schema_version`、`generated_at`（重算时间，不含学习时段）、`profile_commit`；
  - `vocab_size`：词族数、95% 区间、与上一份相比的变化；
  - `band_counts`：Mastered、Target、Distant 三类各多少词；
  - `newly_mastered`：自上一份以来新变成 Mastered 的词，最多 30 个；
  - `focus_targets`：当前重点 Target 词，最多 50 个，原样照抄 `recent.json`（怎么选由「Target 词的选取与排序」决定）；
  - `words_tsv_url`：链接到 `profile_commit` 那次提交的 `words.tsv`，算 Coverage 时用。完整词表太大，不放进正文。
- **不放进报告的**：学习者的内容偏好（话题、要文章还是视频、单次时长等）属于读取方自己的配置；Coverage 目标值同理；历史曲线已在 README 看板上；复习明细不放，因为会暴露学习时间线。
- **60 天停用问题**：本系统不依赖读取侧的定时任务，这个问题不存在。另外每次重算都会往 `english-profile` 提交，只要一两天测一次，仓库就一直有活动。
