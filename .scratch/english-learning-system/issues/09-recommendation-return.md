# 推荐回流 App 的格式

Type: grilling
Status: wontfix
Assignee:
Blocked by: 04, 06, 08
Part of: ../map.md

## Question

外部 agent 推荐的视频和文章以什么形式回到 App？视频是否直接复用 B 站收藏夹项目？文章是存链接、存全文还是接入稍后读服务？agent 写回的位置和格式是什么，App 如何读取并标记已读？

### 来自「调研：文章入库方式与个人使用的版权边界」的补充

- Coverage 由谁计算：外部 agent 推荐时就要读全文，App 则是打开后才算。如果由 agent 算，要约定"只用不存"。
- 推荐条目的候选字段：url、title、author、site、published、word_count、coverage、target_words、reason、license。

### 来自「调研：Grok Bot 如何读取 GitHub」的补充

- 写回位置待定：写成 Progress Report issue 的评论，还是提交一个 `recommendations/latest.json`。
- 费用：xAI API 按 token 计费，没有找到免费额度；API key 要放在仓库 Secrets 里。学习者需要确认是否接受。
- `web_search` 能否可靠地估计文章的 Coverage 还不确定，可能需要由我们自己的代码抓取正文后计算。这一点和文章入库的结论相关。

### 来自「进度汇报 issue 的格式」的补充

- 学习者明确：本系统的终点是发布公开可读的 Progress Report。读取方（如 Grok Bot）、推荐怎么做、推荐送到哪个阅读工具，都在本系统之外，与本系统不交互。因此这张票整体超出范围，已改为 `wontfix`（学习者 2026-11-12 确认）。
