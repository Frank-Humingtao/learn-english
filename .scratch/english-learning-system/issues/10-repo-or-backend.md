# 仓库作为真相源还是需要后端

Type: grilling
Status: resolved
Assignee: humingtao
Blocked by: 05, 07
Part of: ../map.md

## Question

在调研和数据模型的基础上，仓库能否可靠地作为唯一真相源？如果不能，需要什么样的后端（自建、BaaS、iCloud/CloudKit 加定时同步到 GitHub 等），成本多少，仓库降级为只读镜像后哪些设计要改？

### 来自「调研：iPhone 上的 Git 同步可行性」的补充

- 派生数据（Learner Profile、Progress Report）只能由一个写入方生成，候选是 GitHub Action 或 Mac 端脚本。要规定每个写入方只能写哪些文件。
- 原型阶段要实测：`expectedHeadOid` 与分支 head 不一致时，`createCommitOnBranch` 返回什么错误。
- 公开仓库与隐私：已定为两个仓库，私有 `english-data` 和公开 `english-profile`（见「学习档案的数据模型与文件布局」）。本票要评估的是这套双仓库结构是否可靠。

## Answer

- **不买后端**：私有仓库 `english-data` 是唯一真相源，按最终一致理解；App 本地数据库只是工作副本，App 显示的状态以设备本地重算为准。以后若做网页版且需要实时多端同步，再重新评估后端。
- **双仓库结构可靠**：写冲突和速率限额已被现有设计化解——iPhone 只往 `observations/iphone/` 追加，并在会话结束或回到前台时批量提交一次；派生数据只由 Actions 写；复习时间线只在私有仓库。
- **写入方与文件划分**：
  - iPhone：只写 `english-data/observations/iphone/*.jsonl`。
  - Actions（在 `english-data` 中运行）：只写 `english-data/fsrs/params.json`，以及 `english-profile` 的 `profile/*`、`README.md` 和 Progress Report issue。
- **未同步数据兜底**：前台或会话结束时自动同步；界面常驻「未同步 N 条」；依赖 iPhone 的 iCloud 整机备份。不另做 CloudKit 备份。最坏情况丢失一次学习的数据。
- **两个令牌分开**：
  - iPhone：fine-grained PAT，只授权 `english-data` 的 Contents 读写，存 Keychain。
  - Actions：fine-grained PAT，只授权 `english-profile` 的 Contents 和 Issues 写，存在 `english-data` 的 Secrets，有效期取最长。
  - 任一令牌失效或过期，App 和 Actions 都要显式报错，不能静默停止同步。
- **实现细节（agent 决定）**：
  - `english-data` 的 `observations/` 有 push 即触发重算；用 concurrency group 串行排队，不并发；每次从全部原始记录重算，跳过中间某次也无妨。
  - `expectedHeadOid` 与 head 不一致时，拉取最新 head 后重试；因为只追加自己的文件，重试基本不会冲突。具体错误格式留到原型阶段实测（已记到「App 的屏幕与流程原型」）。
- 不新增 ADR：本票延续 [ADR 0001](../../../docs/adr/0001-append-only-observations-and-two-repos.md)，没有新的难以撤销的取舍。
