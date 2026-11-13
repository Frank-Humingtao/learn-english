# 调研：如何准确测量 Learner 的词汇量与逐词掌握概率

前置调研：[02-adaptive-vocab-test](02-adaptive-vocab-test.md)（本篇不重复其中内容，只做深入和补充）
调研日期：2026-11-13

## 问题

系统现在只有一个目的：定期、准确地测量一位 Learner 的英语词汇。这位 Learner 是成年中文母语者，通过了大学英语考试，借助翻译能慢速阅读英文网页。测量结果发布给外部 agent。Learner Profile 里不仅要有总词汇量，还要有**每个词被认识的概率**，agent 用它来计算 Coverage。Baseline Test 不超过 15 分钟，之后的短测不超过 10 分钟，多次测试的证据要累积起来。另外，墨墨背单词每天的逐词复习反馈可以作为额外证据。

当前实现只有一次 Baseline Test 的数据：17 分钟作答 710 题，估计 6385 词族，95% 区间 3326–9443。区间太宽，掌握曲线也太平：1k 89%，2k 57%，到 25k 还有约 14%。伪词误报 11/170，释义核验 28/30 答对。

本次要回答：

1. 现有词汇量测试实际能达到多高的个人精度（SEM、重测信度），代价是多长的测试？各有什么已知局限？
2. 怎样预测单个 Learner 对**没测过的词**的掌握情况？能做到多准？除词频外，哪些特征有用，尤其是对按考试大纲学词的中国学习者？
3. 自适应选题、停止规则、测试长度与精度的关系；"总量"和"逐词"两个目标在选题上是否冲突？
4. Yes/No 自报的偏差怎样校正？中国/EFL 学习者过度自报的证据？核验题的比例和位置怎么定？
5. 只有一个 Learner 时，怎样评估准确度？10–15 分钟的测试能现实地做到多精确？
6. 各种题型在每题耗时、每题信息量和体验上的取舍。
7. 墨墨这类间隔重复 App 的复习数据能怎样充当证据，有哪些偏差？

---

## 0. 先诊断：现有结果为什么区间宽、曲线平

这一节是根据本项目的模型公式和数据做的**数学推断**，不是文献结论。后文的建议以此为出发点。

- **逐词偏差 u_w ~ N(0, 2.5²) 把群体曲线压平了。** 对 logistic 函数在正态随机效应上取期望，有一个常用近似：E[σ(a+u)] ≈ σ(a / √(1+πs²/8))。s = 2.5 时分母约为 1.86，也就是说，对**没观测过的词**，有效斜率只剩原来的 54% 左右。这正是"1k 只有 89%、25k 还有 14%"的形状：难度先验太宽，模型对所有没测过的词都预测得接近 0.5 附近的中间值。
- **把猜测参数 g 加进了"认识概率"。** g 本来描述的是**作答过程**（不认识也答 yes 的概率），不是知识。若对 2.5 万个词族都加上 g ≈ 11/170 ≈ 6.5%，仅这一项就会给总量多加约 0.065 × (25,000 − 已知词数) ≈ 1,200 个词族。报告给 agent 的 P(认识) 应该是去掉作答噪声之后的知识概率。
- **区间宽的主要来源不是 θ，而是外推。** 710 题里约 530 个真词，按 Rasch 信息量 Σp(1−p) 粗算，θ 的标准误只有约 0.1 logit。但总量是对 2.5 万个词求和，其中 10k–25k 有 1.5 万个词。这一段 P 的微小误差（每 1% 约 150 个词族）由 slope 和 ln(rank) 的外推决定，而选题集中在 P≈0.5 附近，几乎没有低频段的数据来约束这个外推。
- **释义核验 28/30 并不等于 93% 真认识。** 四选一有猜中的可能。Stoeckel 等人汇总的数据显示，对"回忆式测试中不会"的词，四选一能答对 13.9%–62.7%（[Stoeckel, McLean & Nation 2020，表 1](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。按 observed = k + (1−k)·r 反推，r 取 0.25（瞎猜）到 0.627 时，真正能回忆出意思的比例 k 约为 82%–91%。而且 30 题本身的 95% 区间就有 ±10 个百分点（同上，表 10 的同类计算）。

---

## 1. 现有测试的精度证据与局限

### 1.1 一个总的警告：群体信度高 ≠ 个人估计准

- Stoeckel、McLean 和 Nation 的综述结论是：现有的 size 和 levels 测试"lack the needed precision"，既不足以估计学习者认识多少词，也不足以判定某个频段是否掌握，最多适合用于排序和分组（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。
- 他们指出三类误差来源（同上）：
  1. **题型**：四选一会高估。表 2 显示，对 140 题的 VST 来说，一个回忆水平为 2,000 词的学习者，按普通 MC 计分可能被估为 9,524 词。
  2. **计数单位**：用一个词形代表整个 WF6 词族会高估。只认识词根时，1k 级的"可用覆盖"约为 67%；加上 Level 2 词缀后约为 87.9%（引 Brown 2018）。他们建议改用 lemma 计数。
  3. **抽样**：频段内各词难度差异很大，小样本代表不了整个频段。Gyllstad et al. (2019) 用 3k 级全部 1,000 词做回忆测试后发现：20 题测试的 95% 区间最多宽达 400 词；30、50、100 题时分别为 326、248、172 词（转引自同上）。
- 因此，内部一致性信度（α、Rasch person reliability）只说明"测到的这些词测得稳"，不说明"整个频段估得准"（同上）。

### 1.2 各测试一览

| 测试 | 形式与长度 | 报告的信度/精度 | 已知局限 |
|---|---|---|---|
| VST（含普通话双语版） | 四选一，100–140 题，30–40 分钟（见 [02](02-adaptive-vocab-test.md)） | Rasch 信度约 .96（见 02）；Ehara 的 100 名日本学习者数据中 α = .91，θ 与 TOEIC 显著相关（[Ehara 2018](https://aclanthology.org/L18-1076.pdf)） | 猜测导致高估，见表 2（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。普通话版：Zhao & Ji 对 177 名中国大学生做了 Rasch 验证，能区分水平，但第 7、8 级的一些借词对中国学习者有问题，作者建议谨慎使用（只核对到摘要，[DOI](https://doi.org/10.1177/0033688216639761)）。抽样率不足、与回忆测试的分数有差距（[Gyllstad, Vilkaitė & Schmitt 2015](https://eprints.nottingham.ac.uk/32284)） |
| Updated VLT | 匹配题，每级 30 题，5 级共 150 题 | Rasch person reliability .96，separation ≥ 4.7；日、西、中三组之间只有 10/900 个 DIF 实例，中日之间只有 credible、amateur 两词（[Webb, Sasao & Ballance 2017](https://www.lextutor.ca/tests/webb_sasao_ballance_2017.pdf)） | 每级 30 题时，即使拿到满分，95% 区间也是 884–1,000 词（[Stoeckel et al. 2020 表 10](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)） |
| LexTALE | 60 项 Yes/No（40 真词 + 20 伪词） | 原始研究中，与 QPT 的相关在荷兰组为 r = .60，韩国组为 .30（转引自下一格的复制研究） | **对中国学习者效度弱**：266 名 L1 中文学习者，与 QPT 的相关 r = .36；中级组 r = .12，不显著（[Puig-Mayenco et al. 2023 接收稿](https://ira.lib.polyu.edu.hk/bitstream/10397/97162/1/Chaouch-Orozco_LexTALE_Measure_L2.pdf)） |
| Yes/No + 伪词（Meara 一系） | 每题约 2 秒（见 02） | 本身信度高：Stubbe 数据中 120 个真词的 α = .93。但与翻译测试的相关只有 .60（[Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)） | 自报。被试答 yes 的词，平均只能给出一半的正确释义（Stubbe & Yokomitsu 2012，转引自同上）。详见 §4 |
| BRAVE（myvocab.info） | Yes/No CAT，约 35–40 题、约 2 分钟；穿插伪词，答"认识"后可能被追问四选一释义 | 停止目标约 0.4 logit；B2 及以上的 SEM 为 **600–700 词族**；与 IELTS/TOEFL/剑桥考试的相关 ρ ≈ .57–.70（[BRAVE 研究页](https://myvocab.info/en/research)） | 只有 600 多个词的难度由作答数据标定，其余用机器学习从 BNC、COCA、SUBTLEX、prevalence、AoA、GSE 等预测；**伪词和释义核验只用来标记"结果不可信"，不修正分数**（[How it works](https://myvocab.info/en/howitworks)）。验证论文仍在准备中，未经同行评审 |
| Duolingo English Test | 综合 CAT，含 Yes/No 词汇题 | 认证考试的中位长度 17 分钟，信度 .96，SEM 5.5；练习版中位 8 分钟，信度 .80，SEM 9.8；30 天内的重测信度 .84，重考平均提高 1–3 分（效应量 0.10）（[Settles 2016 DRR-16-02](https://s3.amazonaws.com/duolingo-papers/reports/DRR-16-02.pdf)） | 测的是总体水平而不是词汇量，题库不公开；Yes/No 题的设计见 02 和 [Settles et al. 2020](https://aclanthology.org/2020.tacl-1.17.pdf) |
| testyourvocab | 自报勾选，两阶段约 160 词 | 官方称误差约 ±10%（见 02） | 没有核验 |

**小结**：在 10–15 分钟内，**已发表**的个人精度最好的是 BRAVE 自称的约 ±600–700 词族（1 SEM），也就是 95% 区间约 ±1,200–1,400。它的做法与本项目非常接近：Yes/No、伪词、四选一核验、用特征预测难度。DET 的"8 分钟→信度 .80、17 分钟→.96"是"长度换精度"的一个实测参照。

---

## 2. 对单个 Learner 的逐词预测

### 2.1 能预测到多准

- **Ehara et al. 2012**：15 名日本学习者，每人对 11,999 个词做 5 级自评，共 179,985 个数据点。只有自评为 5 才算"认识"。
  - 预测没见过的 2,000 个词（out-of-sample）时，只用多语料词频特征的 Rasch 型基线准确率为 66.32%，共享难度模型为 77.67%，个人化模型为 77.81%。
  - 对已有他人数据的词（in-matrix），准确率为 83.40%。（[Ehara et al. 2012](https://aclanthology.org/C12-1049.pdf)）
- **"个人特异词"有规律**（同上，表 4）：差异最大的词是产品名（twitter、kindle）、母语中的外来语（waltz、asphalt、gadget）、与熟词同音或形近的词（rink/link、hearth/health、parson/person），以及兴趣领域的词（音乐、编程）。
- **Ehara et al. 2014**：同样 15 名学习者、8,000 个词。每人只测 10–50 个词，用来预测其余全部词。最好的抽样方法，10 个词时准确率 75.2%，50 个词时 76.4%；启发式的"按 BNC 频段抽样"从 64.2% 升到 74.8%（[Ehara et al. 2014 表 1](https://2014.emnlp.org/papers/pdf/EMNLP2014143.pdf)）。**在 50 个样本之后，准确率基本封顶在 75%–78%。**
- **Ehara 2018**：只靠 word2vec 词向量预测 VST 题目的 IRT 难度，RMSE 为 3.6（难度范围约 ±5），作者的结论是"很难"（[Ehara 2018](https://aclanthology.org/L18-1076.pdf)）。
- **Duolingo SLAM 2018**：任务是根据学习历史预测逐词作答对错，属于另一类问题。英语赛道最好的 AUC 为 .861，基线为 .774。混合效应分析显示，**用户之间的 AUC 标准差达 ±.086**；RNN 和树集成（GBDT）显著优于线性/IRT 类模型（[Settles et al. 2018](https://aclanthology.org/W18-0506.pdf)）。
- **Duolingo HLR**：预测间隔复习中的一次回忆，AUC 只有 .54 左右，MAE 为 .128（基线 .175）。作者解释，低 AUC 一部分源于任务本身噪声大，一部分源于平均回忆率高达 .859 造成的范围限制（[Settles & Meeder 2016 表 2](https://aclanthology.org/P16-1174.pdf)）。

**结论（有证据）**：对没测过的词，现实的上限是**准确率约 75%–85%**，或在更多历史数据下 **AUC 约 .80–.86**。逐词概率的价值主要在于**汇总**：计算一篇文本的 Coverage 时，各词的误差会相互抵消一部分。单个词的 P 不能当作确定判断。

### 2.2 哪些特征决定 L2 的词难度

- **Hashimoto & Egbert 2019**（*Language Learning*）：403 名、36 种母语的学习者，Yes/No 测试。COCA 词频排名是最强的预测因子；最佳模型还包括两个 range 指标、上下文区分度、义项数、正字法邻居数，合计 R² = .37（摘要见 [DOI](https://doi.org/10.1111/lang.12353)；变量构成转引自 [Canning et al. 2024](https://doi.org/10.14746/ssllt.38492)）。
- **Vitta et al. 2023**（概念性复制，日语和阿拉伯语学习者）：理论驱动的模型解释了 52% 的方差，其中约 34% 来自**单词命名反应时**和**习得年龄（AoA）**这两个基于母语者常模的变量（转引自 [Canning et al. 2024](https://doi.org/10.14746/ssllt.38492)）。另一个二手摘要给出的是 marginal R² = .22、conditional R² = .40，两处来源不一致，未核对原文。
- **Canning, McLean & Vitta 2024**：2,999 名日本大学生，VST 的 80 个词，模型 R² = .55。显著的预测因子是词频（β = −.28）、**借词/同源状态**（β = −.24）和 **prevalence**（β = .22）；AoA 和多义性在相关分析中达到阈值，但在回归中不显著（[Canning et al. 2024](https://doi.org/10.14746/ssllt.38492)）。作者提出要区分"绝对复杂度"（词本身的属性）和"相对复杂度"（取决于学习者的母语或经历，比如借词）。
- **母语差异真实存在，但幅度有限**：Updated VLT 的 DIF 分析里，中日学习者只有 2 个词显著不同（[Webb et al. 2017](https://www.lextutor.ca/tests/webb_sasao_ballance_2017.pdf)）。Stoeckel 等人认为，按回忆数据标定的 IRT 难度可能需要分母语组来做（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。
- **中国学习者与教材/大纲**：
  - Sun & Dang 2020 分析了 273,094 词的中国高中英语教材语料：1k 词在教材中覆盖得不错，**2k 和 3k 词族明显代表不足**。在 265 名学生里，大多数只掌握了 1k，或者一个频段都没有掌握（[Sun & Dang 2020](https://eprints.whiterose.ac.uk/161721/)；只核对到摘要层面）。
  - 这次**没有找到**直接检验"中高考/四六级大纲标签能预测中国学习者认识哪些词"的一手研究。不过上述证据一致说明，难度取决于"学习者的实际接触"，而不只是语料词频。对中国学习者来说，大纲就是接触的主要来源。这和日本学习者的借词效应同属"相对复杂度"。这一点是**推断**，需要用本项目自己的数据来检验（见建议 §B）。
- **BRAVE 的难度来源**：BNC、COCA、SUBTLEX-US、enTenTen、word prevalence、VXGL、AoA 常模，加上 GSE Teacher Toolkit（[myvocab.info](https://myvocab.info/en/howitworks)）。GSE 是"按教学等级标注的词表"，作用与 ECDICT 的考试标签相当。

---

## 3. 自适应选题、停止规则与长度—精度关系

### 3.1 θ 的精度很容易达到，总量的精度不容易

- Rasch 模型下，SE(θ) = 1/√Σp(1−p)。题目都选在 P≈0.5 时，每题提供 0.25 的信息，100 题就能把 SE 降到 0.2 logit。这就是 CAT "最大信息量选题"的依据（见 02 中的 DET 和 catsim）。
- 但**总量 = Σ_w P(w)**，它的误差主要来自**难度曲线在各频段的形状**，而不是 θ。这正是 Stoeckel 等人强调的"样本能否代表整个词群"问题（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。只在 P≈0.5 附近选题，θ 能估得很准，但对远端频段的掌握率几乎没有约束。

### 3.2 估总量时应该怎样分配样本：分层抽样 + Neyman 分配

- 估计总体总量时，固定样本量下方差最小的分配是 Neyman 分配：n_h ∝ N_h·S_h，即样本量正比于"层的大小 × 层内标准差"（[SAS SURVEYSELECT 文档](https://support.sas.com/documentation/cdl/en/statug/65328/HTML/default/statug_surveyselect_details21.htm)）。对二值的"认识/不认识"，S_h = √(p_h(1−p_h))，所以 p≈0.5 的频段最该多抽，但 p≈0.05 的大尾巴（1.5 万词）因为 N_h 大，也不能不抽。
- **示意计算（推断）**：假设掌握率剖面为 1k .97、2k .90、3k .80、4k .65、5k .50、6k .40、7k .30、8k .25、9k .20、10k .15、11–14k 各 .10、15–25k 各 .05，总量约 6,070。如果直接用**核验过的真实知识**（没有自报噪声）做纯分层估计，不借助任何模型：

  | 每级样本 | 总样本 | 总量 95% 区间半宽 |
  |---|---|---|
  | 10 | 250 | ±990 |
  | 20 | 500 | ±700 |
  | 40 | 1,000 | ±500 |
  | 80 | 2,000 | ±350 |

  Yes/No 有自报噪声，实际需要的样本更多；用词特征模型在频段之间"借力"，需要的样本会更少。这张表说明：**±10% 级别的总量精度，需要上千个经过偏差校正的观测**，只能靠多次测试累积，单次 15 分钟达不到。

### 3.3 "总量""逐词"和"θ"三个目标在选题上的冲突

- **θ 精度**：选 P≈0.5 的词（最大信息）。
- **总量精度**：按 Neyman 分配做分层抽样，并覆盖长尾。
- **逐词精度（对 Coverage 有用的那部分）**：选"模型最不确定、而且在 agent 会推荐的文本里出现频率高"的词。Ehara 2014 表明，选题方式对小样本下的逐词准确率影响很大：10 个样本时，好的抽样比启发式抽样高 11 个百分点（[Ehara et al. 2014](https://2014.emnlp.org/papers/pdf/EMNLP2014143.pdf)）。
- 三者确实冲突。这次没有找到在三者之间做最优折中的一手文献。下文 §B 的配比是**推断**。

### 3.4 停止规则与长度

- BRAVE 用 0.4 logit 作为停止阈值，99.3% 的场次在达到最大长度之前就停了（[BRAVE](https://myvocab.info/en/research)）。DET 练习版 8 分钟、信度 .80，认证版 17 分钟、信度 .96（[DRR-16-02](https://s3.amazonaws.com/duolingo-papers/reports/DRR-16-02.pdf)）。
- 本项目有固定的时间预算（10/15 分钟），证据又跨场次累积。所以**按时间停止**更合适，不必按 SE 停止。每场的价值在于给累积后验增加了多少信息，而不是单场本身达到多少精度（推断）。

---

## 4. Yes/No 自报的偏差校正

### 4.1 公式校正基本无效，回归和题目分析有效

- 常见的校正公式有 h − f、cfg、Δm 和 I_SDT（Huibregtse, Admiraal & Meara 2002，[DOI](https://doi.org/10.1191/0265532202lt229oa)）。I_SDT 的完整公式这次仍未在一手来源中核实。
- **Mochida & Harrington 2006** 用 VLT 作为效标，比较了这几种公式，相关系数差别不大，并没有明显胜过原始 hit 数（原文付费，转述自 [Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)；原文：[DOI](https://doi.org/10.1191/0265532206lt321oa)）。
- **Stubbe & Stewart 2012**：69 名日本大学生，120 个真词 + 32 个伪词，然后做同一批词的 L2→L1 翻译测试（[Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)）：
  - 只用 yes 数预测翻译分时 R² = .356；把**伪词误报数作为第二个回归变量**之后 R² = .452。得到的公式是"真认识数 = 8.14 + 0.41×yes 数 − 1.94×误报数"。
  - 做题目分析之后：保留与翻译结果 phi 相关最高的 40 个真词，以及 9 个"有效伪词"（point-biserial −.22 到 −.42；其余 23 个伪词平均只有 −.03，几乎没有预测力），R² 升到 .591。
  - 有些词的自报几乎没有效度，比如 convenience 被和外来语 konbini 混淆，overall 被按字面理解。
- **伪词误报能否代表真词虚报？** 证据相互矛盾：
  - Stubbe 2012（*Language Testing* 29(4)）发现，高水平组的误报率反而略高（4.28% 对 3.96%），误报率与虚报率不一致（只见到摘要片段，二手）。
  - Zhang, Liu & Ai 2020（*Language Testing*，105 名大学生，Jianda Liu 是中国学者，被试很可能是中国学生，未核实）发现，**当伪词与真词的词汇属性匹配时**，误报与真词猜测的相关 > .80，校正后的分数与翻译测试的相关 > .70；伪词的正字法邻居数会影响误报率（只见到摘要片段，二手；原文 [DOI](https://doi.org/10.1177/0265532219862265)）。
  - 合起来看：**伪词质量决定伪词是否有用。**
- **Yes/No 主要测的是"认得词形"，不是"知道意思"**：Lee et al. 2024 做了题目层面的分析，认为 Yes/No 主要依赖 form recognition，较少依赖 meaning recall（[Lee et al. 2024](https://doi.org/10.1017/S1366728924001007)，马来语，L1/L2 各 80 人）。

### 4.2 过度自报的幅度，以及中国学习者的情况

- 日本学习者答 yes 的词，平均只有一半能写出正确译义（Stubbe & Yokomitsu 2012，转引自 [Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)）。Waring & Takaki 2003 报告，从再认测试换成翻译测试，分数下降 70%（同上转引）。
- 有研究者直接丢弃误报率超过 10% 的问卷，比如 Schmitt, Jiang & Grabe 2011 用的阈值是 30 个伪词中超过 3 个（同上转引）。本项目这位 Learner 的误报率是 11/170 ≈ 6.5%，高于日本大学生的 3.7%–4.7%（[Stubbe et al. JALT 2010](https://jalt-publications.org/proceedings/articles/1121-who-check-more-pseudowords-low-level-or-high-level-students)），但低于 10% 的丢弃线。
- **中国学习者**：这次没有找到专门量化中国 EFL 学习者"Yes/No 虚报率"的一手研究。间接证据是，LexTALE（Yes/No 形式）在中国中级学习者中几乎不能预测总体水平（r = .12，[Puig-Mayenco et al. 2023](https://ira.lib.polyu.edu.hk/bitstream/10397/97162/1/Chaouch-Orozco_LexTALE_Measure_L2.pdf)）。可能的来源是"四六级词表里见过的词形 ≠ 知道意思"，以及形近词混淆（Ehara 2012 中的 hearth/health 一类）。这是**推断**。

### 4.3 核验题的比例和位置

- BRAVE 在学习者答"认识"后**当场**以一定概率追问四选一（[BRAVE](https://myvocab.info/en/howitworks)），但不公开追问概率。
- 题型顺序有影响：先做再认题会同时暴露词形和意思，从而影响之后对同一个词的回忆测试（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）。所以，被四选一核验过的词，之后**不能再当作"未接触过的新证据"**。
- 关于"事先告诉被试会被核验能否降低误报"，只在二手综述里看到不同研究之间的比较：有核验警告时误报为 4.4%–8.7%，没有警告时平均 17%。这些数字来自不同样本，没有找到随机对照的一手研究，**未核实**。
- 这次**没有找到**比较"当场核验"和"结束时集中核验"的一手研究。

---

## 5. 只有一个 Learner 时怎样评估准确度

文献里的效度证据大多是**群体相关**（例如 θ 与 TOEIC、IELTS 的相关），对单个 Learner 帮助有限。可用于单人评估的方法如下：

1. **效标：意义回忆**。综述一致认为，与阅读最相关的知识层次是 meaning recall，并主张用它作为效标；自动评分可以把 L1 作答和一个可接受译文库比对（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)，引 Aviad-Levitzky et al. 2019 的 [CATSS](https://lexisite.com/catss/catss-info)）。做法：随机抽一批词，让 Learner 写中文意思，作为"真值"。
2. **留出预测（held-out）**：用其余全部 Observation 拟合模型，预测留出词的结果，计算 log loss、Brier、AUC 和校准误差（ECE）。这和 Ehara、SLAM、HLR 的评估方式相同（[Ehara 2012](https://aclanthology.org/C12-1049.pdf)，[Settles et al. 2018](https://aclanthology.org/W18-0506.pdf)，[Settles & Meeder 2016](https://aclanthology.org/P16-1174.pdf)）。
3. **重测和折半**：同一场里奇偶题分开各估一次总量，或者在相隔较短的两场之间比较。DET 的参照：30 天内重测 .84，练习效应很小（[DRR-16-02](https://s3.amazonaws.com/duolingo-papers/reports/DRR-16-02.pdf)）。单人场景下不能算相关系数，应检查"两次估计之差是否落在合并区间之内"。
4. **外部测试**：比如做一次官方 VST 普通话版。但四选一本身就会高估（§1），只能作为"上界"参照，不能当真值。
5. **现实精度（综合 §1 和 §3，推断）**：一次 15 分钟的 Baseline Test，加上良好的难度先验，可以期望约 ±15%–20%（95%）；累积 4–6 次短测（约 1,000 个经过校正的观测）之后，可以达到约 ±10%。逐词预测的现实目标是留出 AUC ≥ .80。

---

## 6. 题型的取舍

| 题型 | 每题耗时 | 测到的知识 | 信息量/偏差 | 体验 |
|---|---|---|---|---|
| Yes/No | 本 Learner 实测约 1.4 秒（710 题/17 分钟）；文献约 2 秒（见 02） | 主要是词形识别（[Lee et al. 2024](https://doi.org/10.1017/S1366728924001007)） | 单题信息量低，有系统性虚报（§4） | 最快；伪词过多会让人沮丧（见 02） |
| 分级自报（如 3 级：不认识 / 见过不确定 / 认识） | 略多于 Yes/No（无文献数据） | 自报的"程度" | Ehara 2012 用 5 级自评，只把第 5 级当"认识"（[Ehara 2012](https://aclanthology.org/C12-1049.pdf)）；Culligan 比较了 Yes/No、VKS、VLT 三种格式估计的词难度（[Culligan 2015](https://journals.sagepub.com/doi/10.1177/0265532215572268)，只见到摘要） | 能把"模糊"单独分出来，便于对接墨墨的 VAGUE |
| 中文四选一（双语 MC） | 约 18 秒（VST 规格，见 02） | 意义再认 | 对回忆层次不会的词，有 41.9%–62.7% 被答对（[Stoeckel et al. 2020 表 1](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)） | 熟悉，但会暴露答案，有学习效应 |
| 序列选择（serial MC） | 无数据 | 意义再认 | 高估降到 13.9%（Stoeckel & Sukigara 2018，同上表 1） | 逐个判断选项 |
| 加"不知道"选项 | 无数据 | — | 能减少猜测，但不同学习者使用这个选项的方式不一致，分数难以比较（同上，引 Zhang 2013、Stoeckel et al. 2016） | — |
| 意义回忆（写中文） | 无一手数据，推断约 8–15 秒 | 与阅读最相关 | 没有猜测；需要自动评分和同义词库（同上） | 最费力，适合作为少量效标题 |
| 听音识词 | — | 听觉词汇 | 存在 LVLT 这类听力词汇测试（McLean, Kramer & Beglar 2015，*Language Teaching Research*，只见到摘要级信息）；CATSS 测四种强度（[CATSS](https://lexisite.com/catss/catss-info)） | 与视频推荐有关，但不是当前目标 |

---

## 7. 墨墨等间隔重复 App 的复习数据

- **墨墨自己公开的数据和模型**：[SSP-MMC](https://github.com/maimemo/ssp-mmc)（MIT 许可；KDD 2022，[DOI](https://doi.org/10.1145/3534678.3539081)）。
  - 数据集是约 2.2 亿条复习日志，字段包括用户、单词、复习次数 `i`、难度 `d`、历史间隔 `t_history`、历史结果 `r_history`、距上次复习的间隔 `delta_t`、回忆概率 `p_recall`。
  - 模型（DHP/HLR）以"半衰期"作为记忆状态。README 没有说明 `r` 和 App 内"认识/模糊/忘记"的对应关系。
- **Duolingo HLR**：用复习计数和时间间隔预测回忆概率，MAE 比 Leitner 低 45% 以上，但逐次 AUC 只有约 .54（[Settles & Meeder 2016](https://aclanthology.org/P16-1174.pdf)）。可见 SRS 日志更擅长估计"平均遗忘速率"，不擅长预测某一次复习的成败。
- **"学习者自己标注生词"作为知识证据**：Shin & Park 用约 100 万 TOEIC 学习者的生词本做"预测学习者认识哪些词"的推荐任务（[Shin & Park 2021](https://arxiv.org/abs/2112.13808)；页面上没有给出效果数字）。
- **已知偏差**（文献 + 推断）：
  1. **选择偏差**：词来自用户选的词书（多半就是考试词表），不是随机样本，不能直接拿来估计频段掌握率。只能作为这些词自己的 Observation 进入模型，并在模型里控制考试标签。
  2. **学习效应**：被复习的词会因复习而变熟。复习反馈反映的是"复习后的状态"，带有时间戳，需要随时间衰减（半衰期思路，[SSP-MMC](https://github.com/maimemo/ssp-mmc)、[HLR](https://aclanthology.org/P16-1174.pdf)）。
  3. **自评偏差**：FAMILIAR、VAGUE 等是自评，和 Yes/No 一样会虚报（§4）。
  4. **情境线索**：App 里可能有例句或之前的记忆痕迹，回忆比冷启动测试容易（推断）。
- **最有价值的是"首次见到时的反馈"**：在学习之前，它相当于一道免费的 Yes/No（或分级自报）题（推断）。

---

## 对本项目的建议

标注说明：**[证据]** 表示有一手文献直接支持；**[推断]** 表示由文献和本项目数据推导、尚待验证。

### A. 模型结构

1. **把知识和作答分开（[证据]+[推断]）**。知识层：P_know(w) = σ(θ − b_w)。作答层：P(yes | 认识) = 1 − s，P(yes | 不认识) = f_w。f_w 不是常数，取决于词形熟悉度：在考试词表中见过、与熟词形近、是常见词缀组合等。**报告给 agent 的只是 P_know**，g/f_w 不能计入总量。依据：校正公式无效，而回归和题目分析有效（[Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)）；伪词质量决定其是否有用（Zhang et al. 2020，二手）；形近混淆现象（[Ehara 2012](https://aclanthology.org/C12-1049.pdf)）。
2. **难度先验用词特征回归，代替"ln(rank) + 很宽的 u_w"（[证据]）**：
   b_w = β·特征 + u_w，u_w 的方差从数据中估计（预计远小于 2.5²）。特征按证据强度排列：
   - 多来源词频，如 BNC/COCA 族级、ECDICT `frq`/`bnc`、SUBTLEX [证据]；
   - word prevalence [证据]；
   - AoA [证据]；
   - **ECDICT 考试标签**：按"最早出现的考试级别"编码为有序变量（zk < gk < cet4 < cet6 < ky < toefl/ielts < gre），同时保留 one-hot [推断：属于对中国学习者的"相对复杂度"变量，对应日本学习者的借词效应，见 [Canning et al. 2024](https://doi.org/10.14746/ssllt.38492)]；
   - 词长、义项数、正字法邻居数 [证据：[Hashimoto & Egbert 2019](https://doi.org/10.1111/lang.12353) 的变量]。

   特征权重的初值可以参考 BRAVE 的做法（[myvocab.info](https://myvocab.info/en/howitworks)）。只有一个 Learner，**无法从他人数据学到题目参数**，所以 β 必须从这一个人的数千个 Observation 里估计。β 的维度要少，并加正则化 [推断]。
3. **验证考试标签（[推断]，可检验）**：在模型里加入和去掉考试标签各拟合一次，比较留出 log loss。如果考试标签的作用超过词频，说明 Learner 的知识按大纲分布，选题和先验都应按标签分层。
4. **计数单位**：内部用 lemma；对 agent 报告时，同时给出 lemma 数和折算的词族数，并说明词族口径偏高（[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)）[证据]。

### B. 题型、配比与长度

5. **Baseline Test（15 分钟）[推断，参照 BRAVE/DET/Stubbe]**：
   - 约 450 个 Yes/No 条目，伪词约 15%。DET 的下限是 ≥15%（见 02），并且伪词要**与真词的长度、频率形态和正字法邻居数匹配**，用过后做题目分析，淘汰无效伪词。
   - 约 30 道**当场**核验：学习者答 yes 之后，以约 10% 的概率立刻追问。题型用中文四选一加"不认识"选项，或者序列选择。
   - 约 10 道意义回忆（写中文）作为效标，答案用词典义项和 LLM 判分。
6. **短测（10 分钟）**：约 300 个 Yes/No + 约 20 道核验 + 约 5 道回忆 [推断]。
7. **真词的选题配比 [推断]**：
   - 约 40% 用于**总量**：25 个频段按 Neyman 分配做分层随机抽样，用当前的 p_h 计算（[SAS 文档](https://support.sas.com/documentation/cdl/en/statug/65328/HTML/default/statug_surveyselect_details21.htm)）；
   - 约 40% 用于**逐词**：选模型最不确定、且按参考语料 token 频率加权的词（依据 [Ehara et al. 2014](https://2014.emnlp.org/papers/pdf/EMNLP2014143.pdf)：选题方式影响逐词准确率）；
   - 约 15% 用于 **θ**：选 P≈0.5 的词；
   - 约 5% 是**复测集**：从此前测过的词中随机抽取，用于估计重测一致性和遗忘。
8. 被核验过的词（已经看过释义）此后只作为"学习后状态"的证据 [证据：[Stoeckel et al. 2020](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf) 关于题型顺序的论述]。

### C. 偏差校正

9. 核验数据是估计 P(认识 | yes) 的主要依据。四选一的结果要按 r ∈ [0.25, 0.63] 去掉猜中成分；更好的做法是把核验结果也写进同一个似然，题型自带猜测参数 [证据：[Stoeckel et al. 2020 表 1](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0005/1881968/2020-Stoeckel-McLean-Nation.pdf)]。
10. 场次层面的质量门槛：伪词误报 > 10%，或核验失败率显著高于历史水平时，该场降权而不是直接丢弃 [证据：Schmitt et al. 2011 的 10% 丢弃线，转引自 [Stubbe & Stewart 2012](https://teval.jalt.org/sites/default/files/SRB-16-2-Full.pdf)；"降权"是推断]。
11. 反应时作为辅助的降权信号（见 02；Pellicer-Sánchez & Schmitt 2012 的结论这次仍未核到原文，[DOI](https://doi.org/10.1177/0265532212438053)）[推断]。

### D. 引入墨墨证据

> **已否决（2026-11-13）**：Learner 决定本系统完全不接入墨墨数据（不作证据、不作验证集），墨墨数据由 Recommendation Agent 自行读取。本节仅作记录。

12. 墨墨反馈作为 Observation 写入，但标注 `source = maimemo`，使用**自己的作答参数**（自己的 s、f，以及 FAMILIAR/VAGUE/FORGET/WELL_FAMILIAR 各自的阈值），不和测试题共用参数。参数用"墨墨反馈 vs 测试核验结果"的重叠词来校准 [推断]。
13. 首次反馈当作学习前的自报证据。后续反馈按时间衰减（半衰期），只影响该词的当前 P_know，不参与估计频段掌握率的分层 [推断，依据 §7 的选择偏差和学习效应]。

### E. 输出与评估协议（每次改模型都按这套跑）

14. 输出：总量（lemma 和词族）及 95% 区间；分成 ≤14k 和 >14k 两部分报告，因为长尾对 Coverage 影响小，却占了总量误差的大头 [推断，见 §0、§3.2]；还有逐词 P_know 及其标准误。
15. **指标和阈值**（阈值都是 [推断] 的初始目标，之后按数据调整）：

| 指标 | 怎么算 | 目标 |
|---|---|---|
| 留出 log loss / Brier | 每次测试前，用历史数据预测本场真词，事后对照（包括核验和回忆） | 优于"只用词频"的基线；log loss 逐版本下降 |
| 留出 AUC | 同上 | ≥ .80（文献上限约 .78–.86，见 §2.1） |
| 校准（ECE，10 个分箱） | 预测 P_know 与核验/回忆结果对比 | ≤ .05 |
| 总量区间半宽 | 后验 95% 区间 | Baseline 后 ≤ ±20%；累积约 1,000 个校正观测后 ≤ ±10% |
| 折半一致性 | 同一场奇偶题分别估计总量 | 差值落在合并区间之内 |
| 重测一致性 | 两场间隔 ≤ 7 天，在复测集上比较 | 同词作答一致率，以及总量差落在区间之内的比例 ≥ 95% |
| Coverage 误差 | 若干篇参考网页，用回忆测试抽查 Coverage 的真值，与预测的 token 加权 Coverage 比较 | 绝对误差 ≤ 2 个百分点 |

16. **证据强度汇总**：
    - 一手文献直接支持（**[证据]**）：自报会系统性虚报；四选一会高估；只靠词频预测难度不够；小样本的频段区间很宽；逐词预测的上限约 75%–85%；SRS 日志适合估计遗忘速率。
    - 推断（**[推断]**）：考试标签对这位 Learner 的预测力；选题配比；各项阈值；墨墨证据的建模方式。这些都应该用上面的评估协议逐条检验。

## 未核实与开放问题

- I_SDT 的完整公式；Mochida & Harrington 2006、Stubbe 2012、Zhang et al. 2020、Pellicer-Sánchez & Schmitt 2012 的原文结果。这次都只核对到摘要或二手转述。
- Vitta et al. 2023 的 R² 在不同二手来源里不一致（.52 与 marginal .22）。
- Tseng 2016（*Computers & Education* 97）的 CAT 词汇量测试，以及 Mizumoto et al. 2019 的 WPLT-CAT 题量和精度，这次没有拿到原文数字。
- 没有找到"考试大纲标签预测中国学习者词知识"和"中国学习者 Yes/No 虚报率"的一手研究，需要用本项目自己的数据回答。
