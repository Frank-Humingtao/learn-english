# 01: 离线评测

Status: ready-for-agent

**What to build:** 一个能重复运行的离线评测：给定一份 Observation 和一个模型版本，输出一组准确度指标，并和"只用词频"的对照模型并排比较。之后每次改模型都先跑它。

- 数据来源：
  - Learner 的真实 Observation（从本机 `english-data` 读取，不入本仓库）；
  - 已知真实知识状态的模拟学习者，包括诚实作答和会虚报两种。
- 指标（定义和初始阈值见 [调研 07 §E](../../english-learning-system/research/07-accurate-vocab-measurement.md)）：
  - 留出 log loss、Brier、AUC：每场测试前用历史数据预测本场真词，事后对照；
  - 校准误差 ECE（10 个分箱）；
  - 总数 95% 区间半宽；
  - 折半一致性：同一场奇偶题分别估计；
  - 重测一致性；
  - 模拟学习者的真实值是否落在区间内。
- 形式：`profile-engine` 新增一个 `eval` 子命令，或者另做一个同包的可执行文件，输出一份 JSON 和一张人能读的表格。
- 对现有模型跑一次，把结果作为基线记录在本票的 Comments 里。

**Blocked by:** —

## Comments
