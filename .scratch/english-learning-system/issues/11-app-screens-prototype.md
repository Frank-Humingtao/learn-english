# App 的屏幕与流程原型

Type: prototype
Status: open
Assignee:
Blocked by: 07
Part of: ../map.md

## Question

词汇量测试、卡片学习、进度查看（以及推荐入口）这几个界面应该长什么样、怎么流转？做一个粗略原型来对照，确认第一版 App 的屏幕清单与核心交互。


### 来自「进度汇报 issue 的格式」的补充

- 推荐和阅读已移出系统范围，App 里不做「推荐入口」。屏幕清单只含词汇量测试、卡片学习、进度查看。

### 来自「仓库作为真相源还是需要后端」的补充

- 界面要常驻显示「未同步 N 条」，令牌失效或过期时要有明确的错误提示（不能静默停止同步）；需要一个粘贴 PAT 的设置入口。
- 原型阶段实测：`createCommitOnBranch` 的 `expectedHeadOid` 与分支 head 不一致时返回什么错误。
