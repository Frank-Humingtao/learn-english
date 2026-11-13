# 02: 重写 Profile Engine 模型

Status: ready-for-agent

**What to build:** 按 [调研 07 §A、§C](../../english-learning-system/research/07-accurate-vocab-measurement.md) 重写模型，在 01 的评测上明显优于现有模型和只用词频的对照模型。

- 认识和作答分成两层：P_know(w) = σ(θ − b_w)；作答层带漏答率 s 和误报率 f。猜测率不计入词汇量。
- 难度 b_w = β·特征 + u_w，u_w 的方差从数据中估计。特征：多来源词频、prevalence 或 AoA（有可用的开放数据时才加），以及 ECDICT 考纲标签。考纲标签按"最早出现的考试级别"编码。β 的维度要少，并加正则化。
- 用留出 log loss 检验考纲标签和其他特征是否有用，没用的特征去掉。
- 四选一核验题自带猜测参数，进入同一个似然。场次层面的质量门槛只降权，不丢弃。
- 输出：
  - 逐词 P_know 及其标准误；
  - lemma 数和词族数；
  - ≤14k 和 >14k 两段总数；
  - 各频段掌握率。
- App 本地和 Actions 用的仍是同一份实现。AppParityTests 和 golden 文件同步更新。
- 在 Comments 里贴出新旧模型的评测对比。

**Blocked by:** 01

## Comments
