# 学习档案的数据模型与文件布局

Type: grilling
Status: resolved
Assignee: humingtao
Blocked by: 01, 02, 03
Part of: ../map.md

## Question

Learner Profile 在仓库里具体存成什么：每个词的 Word Band、测试结果、卡片复习记录分别用什么文件和格式？如何同时支撑 App 的读写、GitHub 上的人类浏览、外部 agent 的读取，以及计算任意文本的 Coverage？

### 来自「调研：词频词表与词典数据来源」的补充

- 计数口径：Card 和 Word Band 按 lemma 计，对外报告的词汇量折算成 word family（BNC/COCA Level 6）。
- 测试题目来源未定：可以直接用 Nation 现成的 VST 题目（有 Mandarin 双语版，个人 App 使用的条款不明），也可以按 BNC/COCA 分层自动出题。

### 来自「调研：iPhone 上的 Git 同步可行性」的补充

- 复习日志的文件格式：候选方案是按月拆分的追加式 JSONL，并考虑按写入方拆分文件以避免冲突。

### 来自「调研：自适应词汇量测试方法」的补充

- 测试结果的"词—状态"历史和卡片复习记录要共用一份数据模型。遗忘的时间衰减参数也在这里定。
- 计数单位要统一：测试按哪个口径计，要和词频表的选择一致（见「调研：词频词表与词典数据来源」）。
- "Yes/No 加抽样核验"这个组合没有成套的一手验证文献，是推断出来的设计。模型里要支持定期抽查 Mastered 词，用来自我验证。
- 可选的冷启动：先做一次约 30 分钟的完整 VST 作为基线。

### 来自「调研：间隔重复算法与 Anki 卡组格式」的补充

- 卡片和 Word Band 的升降规则：初值是 stability ≥ 90 天升为 Mastered，lapses ≥ 8 降为 Distant，冲突时以 Vocabulary Test 的结论为准。90 天没有外部依据，要定下来，并决定是否改用 retrievability 作门槛。
- 测试判定"认识"时，是否往卡片上记一条复习？如果记，ReviewLog 要标明来源，免得把 FSRS 的训练数据带偏。
- 数据格式要保留 FSRS 的 `w` 参数和 `decay`，以便将来升级到 FSRS-7 之类的新版本。
- 复习时间线本身就是隐私，和公开还是私有的问题相关（见「仓库作为真相源还是需要后端」）。

## Answer

- **两层数据**：原始记录（Observation）只追加，永不改写。学习档案（Learner Profile）由 GitHub Actions 从原始记录统一重算，iPhone 不直接改。
- **两个仓库**：
  - 私有 `english-data`：`observations/<写入方>/YYYY-MM.jsonl`（如 `observations/iphone/2026-11.jsonl`）、`fsrs/params.json`，以及重算并发布的工作流。
  - 公开 `english-profile`：`profile/summary.json`（估计词汇量含误差范围、各分类词数、更新时间）、`profile/words.tsv`（lemma、Word Band、P、词频排名，用于算 Coverage）、`profile/recent.json`（最近新掌握的词、当前重点 Target 词）、自动生成的 `README.md` 看板（词汇量曲线、各分类词数、近一周新掌握词、最近测试日期与连续天数）。Progress Report 的 issue 和推荐回流也在这个仓库。
  - 词典、词频表等参考数据打包进 App 和 Actions，仓库只记版本。
- **Observation 字段**：`ts`、`lemma`（伪词也记并标明）、`source`（test / review / spotcheck）、`result`、`rt_ms`、`session`。复习记录另附与 Anki revlog 对齐的 FSRS 字段。
- **计数单位**：一个 lemma 一张卡，不按义项拆分，对外报告折算成 word family。卡片样式参考成熟的 Anki 卡组和 App，不在这里创新。
- **Word Band**：只由认识概率 P 和词频决定，阈值都是可调参数。
  - Mastered：P ≥ 0.9。
  - Target：P < 0.9，且词频排名在当前估计词汇量往外约 2000 词以内；有活跃卡片的词也算 Target。
  - Distant：P < 0.9，且词频排名在上述范围之外。
- **测试与复习的数据用法**：两者进同一份日志并标明来源。FSRS 只用复习记录训练；词汇量模型两种记录都用。较早的作答随时间降低权重，衰减速度是可调参数。
- **退出与抽查**：复习把 P 推过 0.9 就变成 Mastered，卡片暂停。不另设"记忆稳定 90 天"的规则。忘了 8 次以上的标为顽固词，交给「Target 词的选取与排序」处理。每次短测约 10% 的题抽查已 Mastered 的词，答错就回到 Target，同时用来验证测试模型。
- **起步**：第一次做约 30 分钟的 Baseline Test（Nation VST 中英双语版），之后用 3 到 5 分钟的短测滚动更新。

相关 ADR：[0001 原始记录只追加，派生档案统一重算，并拆成私有和公开两个仓库](../../../docs/adr/0001-append-only-observations-and-two-repos.md)
