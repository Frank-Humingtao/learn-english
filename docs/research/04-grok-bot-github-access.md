# 调研：Grok Bot 如何读取 / 写回 GitHub

调研日期：2026-11-11。这个领域变化很快（xAI 在 2026 年 5–10 月连续发布了 Connectors、Automations、Grok Bot），下面每条结论都标了来源；未标日期的官方文档页按"2026-11-11 抓取时的内容"理解。

## 问题

Grok（xAI）及其 bot/agent 产品能否读取 GitHub 公开仓库的 issue 和文件？靠什么机制？能否定时自动运行？能否写回 GitHub？做不到的话有哪些替代方案？

## 先厘清："Grok" 现在是三个不同的产品

| 产品 | 是什么 | 入口 |
|---|---|---|
| **Grok（聊天应用）** + Connectors + Automations | grok.com / iOS / Android 上的对话助手，可接外部服务，可定时跑任务 | grok.com |
| **Grok Bot** | 常驻的 agent 产品：每个 Bot 有自己的身份、记忆、云端电脑（浏览器 + 命令行 + 文件系统）、工具和 Routines | x.ai/bot，账号与计费走 Cursor 体系 |
| **xAI API** | 开发者 API（Responses API），带服务端工具 web_search、x_search、Remote MCP 等 | api.x.ai |

- Grok Bot 由 SpaceX Super Intelligence LLC 出品，定位为"persistent AI agents"，每个 Bot 有自己的 identity、memory、runtime、tools、computer，Routines 可以按计划或事件触发（2026-09-03）。来源：https://x.ai/news/designing-grok-bot
- Grok Bot 运行在"a persistent cloud computer with a browser, command line, and filesystem"。来源：https://docs.x.ai/grok-bot/computer-and-apps

学习者说的"Grok Bot"最可能就是第二个产品；下面三个都评估一遍。

## 1. Grok 聊天应用：Connectors + Automations

### 读取 GitHub
- 2026-05-06 上线 Connectors，GitHub 是其中之一，官方描述是连接"your repositories, issues, and pull requests"，用于"search code, summarize PRs, review changes"——全部是读取/分析类描述，没有提到写操作（同一公告里 SharePoint、Outlook 等则明确写了能写）。来源：https://x.ai/news/grok-connectors
- 文档把 GitHub 列为 Catalog connector（预配置的 OAuth 连接器），覆盖"Repositories, issues, pull requests, and code in GitHub"，所有 Grok 用户都可用；页面没有说明读写权限。来源：https://docs.x.ai/grok/connectors
- 另外支持 Custom MCP connector（自己提供公网可达的 MCP 服务器）。来源同上。

### 定时运行
- 2026-07-16 发布 Automations（由早期的 Tasks 演进而来）：可按 Once / daily / weekdays / weekly / monthly / yearly 定时运行，或者按邮件触发；**定时 Automations 对所有用户免费**，邮件触发需要 SuperGrok。可以用 `@` 引用 connector，让每次运行都用上它。结果可通过邮件或 App 通知推送。来源：https://x.ai/news/grok-automations

### 写回 GitHub
- 官方资料都**没有**说明 Grok 应用的 GitHub connector 能创建 issue、发评论或提交文件。来源：https://x.ai/news/grok-connectors 、https://docs.x.ai/grok/connectors
- 社区报告（非官方，2026-08-31 至 11-06）：iOS 上 GitHub connector 出现"Authorization header is badly formatted"；有用户报告私有仓库返回 404、而公开仓库正常；工作人员 2026-11-06 回复称新版本在设置时会要求填入 personal access token (PAT)。来源：https://forum.cursor.com/t/grokbot-and-github/170137

**结论**：Grok 应用可以"每天定时读公开仓库最新的 Progress Report issue → 生成推荐 → 推送到我的邮箱/通知"，**但不能可靠地写回仓库**。

## 2. Grok Bot（agent 产品）

### 能力
- 云端电脑自带浏览器和命令行；文件、浏览器会话、登录状态在任务之间保留。Apps 提供对 Gmail、Slack、X 等服务的结构化访问，"An app can only do what the authorized account can already do"。来源：https://docs.x.ai/grok-bot/computer-and-apps
- FAQ：Grok Bot 能使用很多基于浏览器的工具，包括没有专门 connector 的服务；部分网站会屏蔽云端电脑的流量。来源：https://docs.x.ai/grok-bot/faq
- 由此推断：公开仓库的 issue 页面不需要登录，Bot 用浏览器或命令行（如 `curl` 调 GitHub REST API）就能读到。GitHub 未认证请求限额为每 IP 60 次/小时，读一个 issue 完全够用。来源：https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api

### GitHub 集成
- 官方 Grok Bot 文档没有单独的 GitHub app 说明页（docs.x.ai/llms.txt 的索引里没有 GitHub 相关页面）。来源：https://docs.x.ai/llms.txt 、https://docs.x.ai/grok-bot/computer-and-apps
- Routines 的事件触发器明确包含"a GitHub, Linear, Sentry, or PagerDuty event"，但没有列出具体是哪些 GitHub 事件。来源：https://docs.x.ai/grok-bot/skills-routines-and-automations 、https://cursor.com/help/grok-bot/routines
- 工程类使用场景说 Bot 会"watch PRs"、在"a PR is ready to merge"时提醒你，说明它确实能操作 PR 类工作流。来源：https://x.ai/bot/guides/engineering
- 社区帖子显示 GitHub connector/plugin 的认证问题很多（401、已下架的 plugin 卸载不掉、机器账号无法接受仓库邀请等，2026-08 到 11 月）。来源：https://forum.cursor.com/t/grok-bot-delisted-github-plugin-48677658-cant-be-uninstalled-or-reconfigured-and-shows-connected-with-0-tools-after-a-401/172955 、https://forum.cursor.com/t/grok-bot-github-connector-cant-accept-repository-invitations-for-a-bot-machine-account/177184
- 可行的写回路径（推断，未实测）：把一个**只授权本仓库**的 fine-grained PAT 存进 Vault 的 secret（"Stored securely, never shown to your Bot"，Shell 可以使用但不会显示），让 Bot 在命令行里调 GitHub REST API 发评论（`POST /repos/{owner}/{repo}/issues/{issue_number}/comments`）或提交文件。来源：https://docs.x.ai/grok-bot/vault 、https://docs.github.com/en/rest/issues/comments

### 定时运行与无人值守的写操作
- Routines 支持用自然语言设定计划（如"every weekday at 8:00 AM"），在云端运行，电脑合上也照常执行；间隔至少 5 分钟，每个 Bot 最多 50 个 routine。来源：https://docs.x.ai/grok-bot/skills-routines-and-automations
- 文档建议"发送、购买、删除、发布、修改生产系统"之前先要求审批。审批机制：Auto Review 逐个检查动作；routine 发起的审批卡片 **30 分钟后过期**，过期就不执行；可以用"Always allow next time"为以后的运行保存一条放行规则。来源：https://docs.x.ai/grok-bot/approvals-security-and-privacy
- 意思是：写回 GitHub 第一次很可能需要人工点批准，配好 Allow 规则后才能真正无人值守。

### 费用
- 没有长期免费档。X Subscription 的 Premium / Super / Ultra，或 Cursor 的 Pro 及以上，或绑定 SuperGrok / X Premium+ 才包含 Grok Bot；免费试用是一次性的用量额度。来源：https://cursor.com/help/grok-bot/plans 、https://docs.x.ai/grok-bot/faq

**结论**：Grok Bot 能读、能定时、**理论上**能写回（命令行 + PAT），但需要付费订阅，GitHub 集成目前问题较多、文档也不全，写操作还要过审批。

## 3. xAI API + GitHub Actions（自己搭）

- Responses API 提供服务端工具：`web_search`（可以搜索并浏览网页，`allowed_domains` 最多 5 个，能限定只在 github.com 上浏览）、`x_search`、Remote MCP 等。来源：https://docs.x.ai/developers/tools/web-search 、https://docs.x.ai/developers/tools/overview
- Remote MCP：在 `tools` 里加 `{"type":"mcp","server_url":...,"server_label":...}`，可带 `authorization` token，只支持 Streaming HTTP / SSE。可以接 GitHub 的 MCP 服务器，但对本项目来说多余。来源：https://docs.x.ai/developers/tools/remote-mcp
- 价格：grok-4.7 每 1M token 输入 $2 / 输出 $6；grok-4.3 输入 $1.25 / 输出 $2.50（2026-11 抓取）。来源：https://docs.x.ai/developers/models
- GitHub Actions：`schedule`（POSIX cron，最短 5 分钟，只在默认分支运行，高峰期可能延迟或丢弃；**公开仓库 60 天没有活动会自动停用**），`issues`（`opened` / `edited` 等事件），`workflow_dispatch`（手动触发）。来源：https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- 公开仓库使用标准 GitHub-hosted runner 免费。来源：https://docs.github.com/en/billing/concepts/product-billing/github-actions
- 工作流内置的 `GITHUB_TOKEN` 可以用 `permissions: { contents: read, issues: write }` 这样的写法限定权限，用来发评论或开 issue（需要提交文件时用 `contents: write`）；限额 1,000 次/小时/仓库。来源：https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token 、https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- 流程：workflow 用 `gh`/REST 读取最新的 Progress Report issue → 把正文作为 prompt 调用 xAI API（开 `web_search` 找文章/视频）→ 把结构化推荐作为评论写回，或提交成 `recommendations/*.json`。API key 存在仓库 Secrets 里。全程确定性、可审计，Grok 不需要"自己会用 GitHub"。
- **注意**：GitHub Models（以前可以在 Actions 里用 `models: read` 免费调用 LLM）**已于 2026-07-30 完全下线**，不能再作为免费替代方案。来源：https://github.blog/changelog/2026-07-30-github-models-is-now-retired/

## 方案对比

| 方案 | 读公开 issue | 定时 | 写回仓库 | 成本 | 可靠性 |
|---|---|---|---|---|---|
| Grok 应用 + Automations | 能（浏览 / GitHub connector） | 能，免费 | 官方未支持 | 免费 | 中（connector 有 bug） |
| Grok Bot + Routines | 能（浏览器 / 命令行 / plugin） | 能 | 可以（PAT + 命令行），需要配审批 | 付费订阅 | 中低（GitHub 集成不稳定、文档不全） |
| GitHub Actions + xAI API | 能（`GITHUB_TOKEN`） | 能（cron + issue 事件） | 能（`issues: write` / `contents: write`） | Actions 免费 + API 按 token 计费 | 高 |

## 推荐

1. **主方案：GitHub Actions + xAI API（grok 模型 + `web_search`）**。由仓库里的 workflow 负责"读 issue"和"写回"，Grok 只负责"读一段 Progress Report 文本 → 输出推荐"。触发方式用 `issues: [opened, edited]` 加每周一次 `schedule` 兜底（注意 60 天无活动会被停用）。写回格式建议：**在 Progress Report issue 下发一条评论**，正文是人能读的 Markdown，里面嵌一个固定标记的 JSON 代码块（供 App 解析）；或者提交 `recommendations/latest.json`。这样「推荐回流 App 的格式」可以完全由我们自己定义。
2. **零成本备选：Grok 应用的 Automations**。每天/每周定时让 Grok 打开公开 issue 的 URL 并给出推荐，结果推送到邮箱，由人手动或者 App 再导入。不能写回仓库。
3. **Grok Bot 暂不推荐作为主链路**：需要付费，GitHub 集成在 2026-08～11 有大量认证 bug，无人值守写操作要过 30 分钟过期的审批。等官方出 GitHub app 文档后再评估。

对两张下游票的约束：
- **「进度汇报 issue 的格式」**：issue 正文必须**自包含**（不依赖附件、链接跳转或者需要登录才能看的内容），因为不管哪个方案，agent 拿到的都只是 issue 正文这段纯文本。建议固定标题（如 `Progress Report`）+ 固定 label，方便 workflow 用 `gh issue list --label` 找到"最新一份"；正文 Markdown 加一个机器可读的 JSON 块（词汇量估计、Word Band 分布、Target 词样本、Coverage 目标）。
- **「推荐回流 App 的格式」**：定义成 JSON schema（标题、URL、类型 article/video、预估 Coverage、推荐理由、生成时间、对应的 report issue 号），由 workflow 校验 schema 后再写回，不合规就不写入。
