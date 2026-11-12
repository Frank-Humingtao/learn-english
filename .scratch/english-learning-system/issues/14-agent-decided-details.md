# 迷雾收尾：由 agent 自行决定的技术细节

Type: task
Status: resolved
Assignee: humingtao
Blocked by: 
Part of: ../map.md

## Question

地图「Not yet specified」剩下 6 项迷雾。学习者的偏好是：技术细节交给 agent 决定，只有影响功能的选择才拿出来讨论。逐项判断每一项该怎么处理：自己定下、移出范围，还是需要讨论。

## Answer

逐项判断后，6 项都不需要再讨论，处理如下。只有第 2 项里"卡片不配图"一条学习者能直接看到，单独标出，随时可以推翻。

1. **技术栈细节**（自己定）
   - 本地存储用 SQLite，通过 GRDB.swift 访问。它是本地工作副本，Observation 写入 outbox 表后再批量提交。
   - 不引入第三方 GitHub 客户端库，直接用 URLSession 调 GraphQL `createCommitOnBranch` 和 REST Contents API 读文件。
   - 实测 `expectedHeadOid` 与 head 不一致时返回什么错误，属于实现阶段的第一个验证任务：先写一个最小的提交脚本跑一次，按实际返回的错误写重试逻辑（拉取最新 head 后重试一次，仍失败就留在 outbox）。
2. **卡片内容生成**（自己定，一条可见）
   - 释义、音标、考试标签来自 ECDICT；例句和真人发音来自 Wiktextract，没有就用 iOS 自带 TTS 朗读。
   - 测试里中文四选一的干扰项从 ECDICT 中同词性、词频相近的其他词的中文释义里随机抽取，不用 AI 生成，也就不会编造词义。
   - App 不接 AI；选词说明由「选词规划」skill 生成，已在「选词规划 skill 的设计」定下。
   - **可见的选择：第一版卡片不配图**（百词斩那种图片记忆不做）。原因是没有可靠的免费、可授权图库能覆盖上万个词。以后想加，可以单独开票。
3. **隐私与备份**（自己定）
   - 异地备份：GitHub 本身就是一份异地副本；Mac 上给「选词规划」用的本地 clone 是第二份。不再另做备份。
   - 绝不能入库的数据：PAT 和任何令牌、真实姓名、邮箱、设备标识、位置。Observation 只记词、时间、结果、反应时和会话编号。
4. **与网页版的格式兼容**（移出）：网页版已在范围外。现有格式（JSONL、JSON、TSV，按写入方分目录）本身不绑 iOS，不需要再加约束。
5. **中国大陆网络可达性**（自己定）：文章阅读已移出范围，只剩 GitHub API。App 本地优先，GitHub 暂时连不上只会推迟同步，界面显示"离线"和"未同步 N 条"。App 不内置代理，走系统网络（学习者自己的代理或 VPN）。
6. **数据许可与仓库许可证**（自己定）
   - BNC/COCA 原表不进任何仓库，构建时由脚本从官网下载。公开仓库只放派生的 `words.tsv`（lemma、Word Band、P、词频排名），并在 README 注明数据来源。
   - Wiktextract（CC BY-SA）内容只打包进 App，不进公开仓库，在 App 的"关于"页署名。
   - 公开仓库 `english-profile` 的派生数据用 CC BY 4.0；代码（App、Actions、skill）用 MIT。
