# 仓库作为真相源还是需要后端

Type: grilling
Status: open
Assignee:
Blocked by: 05, 07
Part of: ../map.md

## Question

在调研和数据模型的基础上，仓库能否可靠地作为唯一真相源？如果不能，需要什么样的后端（自建、BaaS、iCloud/CloudKit 加定时同步到 GitHub 等），成本多少，仓库降级为只读镜像后哪些设计要改？

### 来自「调研：iPhone 上的 Git 同步可行性」的补充

- 派生数据（Learner Profile、Progress Report）只能由一个写入方生成，候选是 GitHub Action 或 Mac 端脚本。要规定每个写入方只能写哪些文件。
- 原型阶段要实测：`expectedHeadOid` 与分支 head 不一致时，`createCommitOnBranch` 返回什么错误。
- 公开仓库与隐私：已定为两个仓库，私有 `english-data` 和公开 `english-profile`（见「学习档案的数据模型与文件布局」）。本票要评估的是这套双仓库结构是否可靠。
