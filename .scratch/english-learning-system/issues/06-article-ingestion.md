# 调研：文章入库方式与个人使用的版权边界

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

推荐的文章分散在各种网页上，怎样把它们以统一形式送进 App：类 Readwise Reader 的稍后读服务（Readwise Reader、Instapaper、Wallabag 等）的 API 能否直接复用？自己抓取正文（如 Mozilla Readability）并存储时，存链接、存摘要、存全文各有什么版权风险（个人使用、仓库公开的前提下）？GitHub issue 或公开仓库适不适合承载文章内容还是只适合承载链接？给出推荐做法。

## Answer

公开仓库或 issue 只放“链接 + 元数据 + 派生数据”，包括标题、作者、站点、字数、Coverage、Target 词表，以及 agent 用自己的话写的推荐理由。第三方全文不放进公开仓库：这属于向公众提供作品，触及信息网络传播权，有 DMCA 下架风险，严重时可能连累整个仓库。
全文在 App 设备端处理：用 WKWebView 加载原页面，注入 Mozilla Readability 提取正文，再经 DOMPurify 清洗后渲染，只缓存在本地。这属于个人学习使用，风险低。
如果想省事，可以用 Readwise Reader 代替（Reader Only 方案 $7.99/月）：agent 调 `POST /api/v3/save` 传入 URL，App 用 `list?withHtmlContent=true` 拉取正文。Instapaper（需要订阅、审批 key、交出密码）和 Wallabag（需要自托管）都不推荐。
CC 许可或公有领域的文章可以例外放全文，但要署名。
[调研笔记](../research/06-article-ingestion.md)
