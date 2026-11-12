# 地图：个人英语学习系统

Label: wayfinder:map

## Destination

一份可直接拆成实现任务的**总规格**，覆盖三块：
1. iPhone App 做什么。
2. 仓库的数据结构，以及仓库能否可靠地作为真相源。
3. 对外发布的接口：一份谁都能公开读取的 Progress Report（加上派生档案文件）。系统到此为止，谁来读、怎么推荐、推荐送到哪里都在系统之外。

## Notes

- **领域**：单一学习者的词汇测量与学习。术语以根目录 `GLOSSARY.md` 为准（Learner Profile、Word Band、Mastered / Target / Distant、Coverage、Vocabulary Test、Card、Progress Report）。
- **grilling 票**：调用 Skill `grilling` 和 `domain-modeling`；**prototype 票**：调用 Skill `prototype`；**research 票**：调用 Skill `research`，结论写到 `.scratch/english-learning-system/research/`。
- **学习者背景**：通过过大学英语考试，但阅读英文网页靠翻译，硬读速度约为中文的 1/20，缺乏口语信心。实际水平交给词汇量测试来确认。
- **常设偏好**：
  - 只给本人使用，只做 iPhone；数据格式不要绑死 iOS（以后可能有网页版）。
  - 两个仓库：原始记录放私有仓库，派生档案和 Progress Report 放公开仓库；都不放个人隐私（见「学习档案的数据模型与文件布局」）。
  - 先假设仓库是真相源，由「仓库作为真相源还是需要后端」一票验证；需要时可以购买后端服务。
  - 创新集中在"AI 按水平定制"上：测准水平、按水平推荐内容、按水平选卡。卡片本身的设计参考成熟的 Anki 卡组和 App，不在这里创新。
  - 卡片用现成的间隔重复算法，格式尽量与 Anki 互通；形式参考墨墨背单词、百词斩。界面中文，卡片以英文释义加例句为主，中文释义可见。
  - 词汇量测试频繁进行（一两天一次），每次 3 到 5 分钟，抽不同的词，结果滚动更新档案。
  - Progress Report 每次发一个新 issue，信息尽量少，外部 agent 只看最新一个。
  - 本系统的终点是发布一份公开可读的 Progress Report；谁来读、怎么推荐、推荐送到哪里，由学习者在系统之外自行搭建，与本系统不交互。
  - grilling 时只问流程、工具和接口方案的选择，实现细节由 agent 自行决定并记录。
- **追踪器**：目前用本地 markdown（`.scratch/`），等 GitHub 仓库建好再迁移到 issue。

## Decisions so far

<!-- 每张已关闭的票一行：[票名](链接)：一句话要点 -->
- [调研：文章入库方式与个人使用的版权边界](issues/06-article-ingestion.md)：公开仓库只放链接、元数据和派生数据，第三方全文不入库；App 端用 WKWebView 加 Readability 提取正文并只缓存在本地；Readwise Reader 作为可选的付费代管方案。**（推荐和阅读已移出范围，见「进度汇报 issue 的格式」；只有「公开仓库不放第三方全文」仍有效。）**
- [调研：词频词表与词典数据来源](issues/01-word-frequency-sources.md)：BNC/COCA 25k 词族表（Nation）做分层骨架；ECDICT（MIT）做主词典；例句和音频取自 Wiktextract（CC BY-SA）；Card 与 Word Band 按 lemma 计，对外词汇量折算成 word family。
- [调研：iPhone 上的 Git 同步可行性](issues/05-ios-git-sync.md)：本地优先，复习先写本地 outbox，在会话结束或回到前台时用 GraphQL `createCommitOnBranch` 批量提交，不内嵌 libgit2；认证用只授权本仓库的 fine-grained PAT，存在 Keychain；仓库可作最终一致的真相源，不能当实时后端。
- [调研：Grok Bot 如何读取 GitHub](issues/04-grok-bot-github-access.md)：主链路是 GitHub Actions（issue 事件加定时触发）读取 Progress Report，调用 xAI API（grok 加 web_search）生成推荐，再用 `GITHUB_TOKEN` 写回 issue 评论；Grok 应用的免费定时 Automations 只能读不能写，作零成本备选；付费的 Grok Bot 与 GitHub 集成不稳定，暂不用。**（已被「进度汇报 issue 的格式」取代：读取方和推荐不属于本系统，本系统只提供公开可读的报告。）**
- [调研：自适应词汇量测试方法](issues/02-adaptive-vocab-test.md)：用 Yes/No 真词题加每次现生成的伪词（约 80 条），再加 5 到 8 道中文四选一释义核验，每次 3 到 5 分钟；按 Rasch 模型在 P≈0.5 附近抽从未测过的词，每次用全部历史作答重新拟合，不从头估；总词汇量取 ΣP，Word Band 按 P 阈值划分。
- [调研：间隔重复算法与 Anki 卡组格式](issues/03-srs-and-anki.md)：调度用 FSRS-6（官方 swift-fsrs，MIT），默认参数、期望保留率 0.9，攒够复习后在 Actions 里用 py-fsrs 训练参数；ReviewLog 字段与 Anki revlog 对齐；只给 Target 词发卡；AnkiWeb 共享卡组只在设备本地用，不进公开仓库；Anki 导入放到首版之后。**（顽固词「降为 Distant」已被「Target 词的选取与排序」取代：暂停卡片，Word Band 仍只由 P 决定。）**
- [学习档案的数据模型与文件布局](issues/07-learner-profile-model.md)：原始记录只追加，学习档案由 Actions 统一重算；私有 `english-data` 存原始记录，公开 `english-profile` 存派生档案、看板、Progress Report；一词一卡；Word Band 由认识概率 P（≥0.9 为 Mastered）加词频窗口划分；第一次做 30 分钟基线测试。
- [进度汇报 issue 的格式](issues/08-progress-report-format.md)：当天第一次测试后由 Actions 自动发一份（同日只更新，只复习不发），上一份自动关闭，只有最新一份是打开的；正文是中文摘要加 JSON（词汇量与区间、三类词数、新掌握词 ≤30、重点 Target ≤50、固定到某次提交的 `words.tsv` 链接），不含偏好；不指定读取方，本系统到发布报告为止。
- [仓库作为真相源还是需要后端](issues/10-repo-or-backend.md)：不买后端，私有 `english-data` 作最终一致的唯一真相源；iPhone 只追加自己的 observations 文件并按会话批量提交，派生数据只由 Actions 写；未同步数据靠「未同步 N 条」提示加 iCloud 整机备份兜底；iPhone 与 Actions 各用一个只授权单仓库的 fine-grained PAT，失效时显式报错。
- [App 的屏幕与流程原型](issues/11-app-screens-prototype.md)：用底部标签栏（学习 / 测试 / 进度 / 设置），首次启动依次粘贴 PAT 和做基线测试；测试和复习是全屏流程；卡片评分用 4 档；同步状态平时隐藏，有未同步记录时才显示「未同步 N 条」，令牌出错时全局显示红条，断网只提示离线。
- [Target 词的选取与排序](issues/12-target-word-selection.md)：不用固定算法也不接 API，由新写的 Claude skill「选词规划」（`word-plan`，本机每天定时、可手动）读私有仓库写出 Study Plan（有序新词加选词说明、重点词 ≤50 供 `focus_targets` 照抄）；每日新词数是设置里的上限；先复习后新卡；新卡首评「太简单」即视为认识；顽固词暂停、进度页列出、30 天后或手动重新学；支持手动加词；计划用完只复习不兜底。
- [选词规划 skill 的设计](issues/13-word-plan-skill.md)：用 Claude 桌面 App 的定时任务每天 07:30 跑，也可手动 `/word-plan` 加一句临时要求；skill 放在 `english-data` 仓库里，先用脚本把记录汇总成精简摘要再交给 Claude；选词顺序依次是「想学」、似懂非懂（高频优先）、按词频，易混词不同天；选词说明为中文、不超过 40 字、不编造；`focus_targets` 先放正在学的难卡；输出经脚本校验，最多修 2 次，不过就不提交；计划超过 3 天未更新时 App「学习」标签显示黄字提醒，并附每次的中文摘要。
- [迷雾收尾：由 agent 自行决定的技术细节](issues/14-agent-decided-details.md)：本地存储用 SQLite（GRDB），直接调 GitHub API，不引入客户端库；卡片内容来自 ECDICT 加 Wiktextract，测试干扰项从词典抽取，第一版卡片不配图；令牌和个人信息绝不入库；GitHub 连不上只推迟同步；BNC/COCA 原表不入库，派生数据用 CC BY 4.0，代码用 MIT。

## Not yet specified

<!-- 已清空：剩余迷雾由「迷雾收尾：由 agent 自行决定的技术细节」处理 -->

## Out of scope

- 读取 Progress Report 的外部工具、推荐引擎、推荐结果的去向（学习者自己的阅读工具、B 站收藏夹等）：都由学习者在系统之外搭建，与本系统不交互。本地图只管发布公开可读的 Progress Report。
- 在 App 内阅读文章、看视频，以及付费墙文章的处理：阅读发生在学习者自己的工具里。
- 网页版、iPad 和 Mac 版本。
- 公开发布、多用户、账号体系。
