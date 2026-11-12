# 调研：Grok Bot 如何读取 GitHub

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

Grok（xAI）及其 bot/agent 产品目前能否读取 GitHub 公开仓库的 issue 和文件？是靠联网浏览、API 工具还是集成？能否定时自动运行？能否写回 GitHub（提交文件或发评论）？若 Grok 做不到，有哪些可替代的 agent 方案（如 GitHub Actions 里跑 LLM、其他带定时任务的 agent）？结论要能支撑「进度汇报 issue 的格式」与「推荐回流 App 的格式」两张票。

## Answer

- Grok 应用（Connectors + 免费的定时 Automations）能定时读取公开 issue 并把推荐推送到邮箱/通知，但官方没有支持写回 GitHub。
- Grok Bot（付费 agent，自带云端浏览器和命令行，支持 Routines）理论上能用 PAT 写回，但 GitHub 集成在 2026-08～11 认证 bug 很多，无人值守写操作还要过 30 分钟就过期的审批，不适合当主链路。
- 推荐：用 GitHub Actions（issue 事件 + cron）读取 Progress Report，调用 xAI API（grok + web_search）生成推荐，用 `GITHUB_TOKEN`（issues: write）以"Markdown + JSON 块"评论的形式写回；GitHub Models 已于 2026-07-30 下线，不能当免费替代。
- 对下游的约束：issue 正文必须自包含，用固定 label 标出最新一份；推荐写回用 workflow 校验过的 JSON schema。

[调研笔记](../research/04-grok-bot-github-access.md)
