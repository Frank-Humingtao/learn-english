# 调研：自适应词汇量测试方法

对应工单：[02-adaptive-vocab-test](https://github.com/Frank-Humingtao/learn-english/blob/e948511/.scratch/english-learning-system/issues/02-adaptive-vocab-test.md)
调研日期：2026-11-11

问题：有哪些成熟、可复现的词汇量估算方法？怎样在 3 到 5 分钟内，从按词频分层的大题库里自适应抽样，估出总词汇量和各频段掌握率？一两天测一次时，怎样做到题目不重复、结果滚动更新？怎样识别猜测和过度自信？哪些题库或参数是公开的？

---

## 1. 现有方法一览

### 1.1 Vocabulary Size Test（VST，Nation & Beglar 2007；Nation 2012）

- **版本**：14,000 版有 140 道四选一题，每 1000 词族一个 level，每 level 10 题。两个平行的 20,000 版各 100 题，每 level 5 题。A、B 两版的均值和标准差没有显著差异，可以互换使用。[VST 说明与规格 PDF](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)
- **抽样基础**：BNC（后来是 BNC/COCA）的词族频率表，按 1000 分级。同上。
- **计分**：答对数乘以每题代表的词族数（140 题版 ×100，100 题版 ×200）。计分时**忽略 level**。规格书明确说，因为每 level 题量太少，这个测试"do not reliably measure how well each level is known"，只有总分有意义。同上。
- **不做猜测校正，也不设"不知道"选项**：作者认为四选一允许部分知识和有根据的猜测，所以分数是"slightly generous estimate"。规格书引用了一项未发表研究：加入"I don't know"选项并配上错答惩罚之后，分数会下降，并且更接近回忆式测试的分数。也就是说，测试从"宽松"变成了"严格"。同上。
- **双语版**：对低水平学习者，作者建议优先用双语版。Elgort 发现双语版的分数大约高 10%，原因是选项是母语词，绕开了英文释义里的难语法。官方提供 **Mandarin（普通话）双语版**。[Paul Nation 词汇测试页](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests)；[普通话版 PDF](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-size-test-Mandarin.pdf)；[规格书](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)
- **耗时**：140 题约 40 分钟，100 题约 30 分钟，即每题约 17–18 秒。**完整的 VST 放不进 3–5 分钟。**同上。
- **其他性质**：Rasch 分析显示测试接近单维，信度约 .96；题目可以混排，不必按频率排序，以免学习者在后段放弃。同上。
- **许可**：研究用途无需授权，注明出处即可。同上。

### 1.2 Vocabulary Levels Test（VLT / Updated VLT / NVLT）

- 测各个 1000 级（1k–5k）"掌握了没有"，适合 5000 词以下的 EFL 学习者。[Paul Nation 词汇测试页](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests)
- **Updated VLT**（Webb, Sasao & Ballance 2017）每 level 30 题，基于 BNC/COCA 列表。作者建议的掌握线是：1k–3k 用 **29/30**，4k–5k 用 **24/30**。之前 Schmitt 等人用过 26/30，也有人用 24/30，作者认为这些切点"arbitrary"。[Webb, Sasao & Ballance 2017 PDF](https://www.lextutor.ca/tests/webb_sasao_ballance_2017.pdf)
- 研究用途无需授权。[Paul Nation 词汇测试页](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests)
- 对本项目的启发：频段掌握率要靠**每段约 30 个样本**才能说"掌握"。单次 3–5 分钟的测试做不到，必须跨多次累积（见 §3）。

### 1.3 Yes/No（checklist）测试 + 伪词纠偏（Meara 一系）

- **形式**：屏幕上混着真词和伪词，学习者只需判断"认识/不认识"。产出两个指标：hit（真词答 yes）和 false alarm（伪词答 yes）。如果真词是从某个词表随机抽取的，校正后的 hit rate 就可以当作对整张词表掌握率的估计。[Meara 1994](https://www.lognostics.co.uk/vlibrary/meara1994a.pdf)
- **速度**：Meara & Jones 的计算机版大约 10 分钟测约 300 个词（约 2 秒一个），覆盖的词汇量最高到 10,000。同上。**这是唯一能在 3–5 分钟里拿到上百个样本的格式。**
- **计分公式**（Meara 1991 文稿，h = hit rate，f = false alarm rate）：
  - 判别指数 `Ag = 0.5 + (h − f)(1 + h − f) / (4h(1 − f))`
  - 词汇量估计 Δm：找出 f=0 时能得到同样 Ag 的 h，再乘以词表大小
  - 作者的常规做法是真词与伪词 2:1。Ag 低于约 0.7 时接近瞎猜，按 0 处理。[Meara 1991 "Scoring a YES/NO vocabulary test"](https://lognostics.co.uk/vlibrary/meara1991.doc)
  - 注：这个公式是工具从文档提取文本后重建的，原文例子里有一处数值不一致，实现前要核对原文。Meara 本人后来承认 1992 年的公式有数学错误，被 Beeckmans et al. 2001、Huibregtse et al. 2002 等指出。之后 Huibregtse, Admiraal & Meara 2002（*Language Testing* 19:227–245）提出了同时校正猜测和反应风格的 I_SDT。I_SDT 的公式这次没有在一手来源里核实。
- **已知问题**（Meara 1994）：
  1. 随机生成的"等价"试卷均值差异显著，分数对 false alarm 很敏感，hit 低的人尤其明显；
  2. 有 5–10% 的人 f > h，得到负分；
  3. 一项针对阿拉伯语学习者的研究发现，**false alarm 数和"真词答 yes 但其实不认识"的次数并不相关**。这说明单靠伪词不足以纠正过度自信。[Meara 1994](https://www.lognostics.co.uk/vlibrary/meara1994a.pdf)
  4. 加伪词会压低学习者的积极性（"总在答 NO 很沮丧"），所以伪词比例不宜过高。同上。
- **其他纠偏思路**：Pellicer-Sánchez & Schmitt 2012（*Language Testing* 29(4):489–509，[DOI](https://doi.org/10.1177/0265532212438053)）提出用**反应时**代替伪词来识别过度估计，前提是快速回答更可能是真的认识（这里只核对到摘要）。
- **LexTALE**（Lemhöfer & Broersma 2012）：60 个固定条目（40 真词 + 20 伪词），按正确率百分比计分，有英、荷、德三种在线版，用来快速测高水平学习者的总体水平。它只有一套固定题，不适合重复测。[LexTALE 官网](https://www.lextale.com/)

### 1.4 testyourvocab（现归 Preply）

- 两步：先用 40 个词做粗筛，再出约 120 个靠近估计水平的词，分四栏，从易到难。学习者勾选认识的词。词频依据 Kilgarriff 的 BNC 分析，计数单位是词典 headword。[Preply/testyourvocab 说明](https://preply.com/en/learn/english/test-your-vocab)
- **没有伪词或释义核验**，完全靠自报。官方给出的误差约 **±10%**，并提醒查过题目里的词之后再测会"artificially high"。没有公开最终换算公式。同上。
- 对本项目的启发：两阶段的"粗定位 + 在边界附近密集取样"值得借鉴；没有核验，是它对单个学习者不够精确的主要原因。

### 1.5 基于 IRT 的自适应测试（CAT）——Duolingo English Test 的做法

- **模型**：Rasch，`p_i(θ) = 1 / (1 + exp(δ_i − θ))`，能力和题目难度在同一刻度上。作者解释，选 Rasch 而不是 2PL/3PL，是因为额外参数难以准确估计。[Settles, LaFlair & Hagiwara 2020, TACL](https://aclanthology.org/2020.tacl-1.17.pdf)
- **流程**：先用 MLE 得到暂定的 θ̂，再按 θ̂ 选下一题的难度，循环直到停止条件。开局有一个 calibration 阶段：前四题依次从由易到难的难度箱里抽取。同上。
- **Yes/No 题的难度从哪来**：不做人工预测，而是用特征回归预测每个词的难度。特征包括字符长度、字符级语言模型的 log-likelihood 和 Fisher score，作为词频的代理，这样伪词也能算出难度。作者引用 Culligan 2015：字符长度和语料词频能显著预测 IRT 难度。同上。
- **伪词怎么生成**：在英文词典上训练字符级 LSTM 生成伪词，滤掉真词，再人工删掉太像真词或不妥的。**每道 yes/no 题至少含 15% 真词和 15% 伪词**，真词和伪词从同一难度箱里抽。同上。
- **计分**：yes/no 题按 signal detection 的 d′/AUC 打出 0–1 的"软"分数，代入广义的 Rasch 似然（相当于最小化交叉熵）。同上。
- **验证**：用 2018 年 21,351 场考试事后拟合 Rasch，得到的 θ 与模型分数的 Spearman ρ = .96。同上。
- 题库和参数**不公开**。

### 1.6 开源 CAT 组件

- [catsim](https://github.com/douglasrizzo/catsim)（BSD-3-Clause，Python）提供 logistic IRT、能力估计器、选题器和停止规则。选题器包括 MaxInfo（带 `r_max` 曝光上限）、Urry（选难度最接近 θ 的题）、**Randomesque**（从信息量最高的 n 道题里随机抽，Kingsbury 1989 默认 n=5）、α-stratified 等。[catsim 选题文档](https://douglasrizzo.com.br/catsim/selection.html)

---

## 2. 公开可用的题库、数据与参数

| 资源 | 内容 | 许可/可用性 | 用途 |
|---|---|---|---|
| VST 14k / 20k A,B，**普通话双语版** | 四选一题目和答案 | 研究免授权，需署名（[来源](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)） | 首次基线校准；核验题的题型模板 |
| Updated VLT、NVLT | 1k–5k 每级 30 题 | Updated VLT 研究免授权（[来源](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests)） | 频段掌握线参考 |
| Ehara 2018 数据集 | 100 名日本学习者 × 100 道 VST 题的作答，α = .91，含 IRT 分析 | "freely available"（[论文](https://aclanthology.org/L18-1076.pdf)，[数据页](http://yoehara.com/esl-vocabulary-dataset/)） | 东亚学习者的 VST 题目难度先验；也可验证"难度≈f(词频)"的映射 |
| Brysbaert et al. 2019 word prevalence | 61,858 个英语词的"知道该词的人口比例"，22 万人众包 | CC BY 4.0（[NoRaRe](https://norare.clld.org/contributions/Brysbaert-2019-Prevalence)） | 对词频以外的难度先验做补充（母语者数据，需谨慎） |
| Wuggy | 伪词生成器，支持英语 | MIT（[repo](https://github.com/WuggyCode/wuggy)） | 生成源源不断、不重复的伪词 |
| LexTALE | 60 个固定条目 | 官网提供下载（[来源](https://www.lextale.com/)） | 可选的一次性外部效度对照 |
| Duolingo DET、testyourvocab | 方法有公开描述 | 题库和参数不公开 | 只借鉴设计 |

---

## 3. 针对本项目的设计推导

### 3.1 为什么必须是"Yes/No 为主 + 少量释义核验"

- 3–5 分钟的预算：VST 四选一每题约 18 秒，只能做 10–16 题（[规格书](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)）；Yes/No 约 2 秒一题，能做 90–150 题（[Meara 1994](https://www.lognostics.co.uk/vlibrary/meara1994a.pdf)）。
- 但 Yes/No 只测"认得词形"，而且光靠伪词纠偏不可靠（见 §1.3 的已知问题 3）。所以要在学习者答了 yes 的真词里**抽几个做释义核验**：四选一的中文释义，模仿 VST 双语版。核验失败率就是对"yes 里有多少是虚报"的**直接估计**，可以用来折减所有 yes 的权重。
- 这次没有找到"Yes/No + 抽样核验"作为成套方法的一手文献。它是根据 Meara 1994 的发现和 VST 的格式推出来的设计，属于待验证的推断。

### 3.2 模型：每个词一个"认识概率"，总量 = 概率之和

- 用 Rasch 型模型（[Settles et al. 2020](https://aclanthology.org/2020.tacl-1.17.pdf)）：`P(认识 w) = σ(θ − δ_w)`。δ_w 不靠人工标定，而是取词频排名的函数，例如 `δ_w = α + β·log(rank_w)`；也可以加入词长、Ehara 数据和 prevalence 作为先验（依据：Culligan 2015 发现词频和词长能预测难度，转引自 Settles et al. 2020）。
- **总词汇量** = 频率表上所有词的 P 之和。直接测过的词用观测结果替代模型预测。这和 VST 的"每题代表 100/200 个词族"本质相同，只是换成了连续模型。
- **各频段掌握率** = 该段词 P 的均值，再用该段的实测数据做校正。可以参照 Updated VLT 的切点：1k–3k ≥ 29/30 算掌握，4k 以上 ≥ 24/30（[Webb et al. 2017](https://www.lextutor.ca/tests/webb_sasao_ballance_2017.pdf)）。
- **映射到 Word Band**（建议，未经验证）：P ≥ 约 0.9 或核验通过 → Mastered；P 大约在 0.3–0.8 → Target；P < 约 0.2 → Distant。阈值以后用数据调整。

### 3.3 选题：在边界附近密集取样，题目不重复

- 每次测试的开局：先用上次的 θ 定位。这相当于 testyourvocab 的第一步和 DET 的 calibration 阶段，只是不必每次重做。
- 选题时只考虑**从未测过的词**，选 `P ≈ 0.5`（信息量最大）附近的词，并用 **Randomesque**（[catsim](https://douglasrizzo.com.br/catsim/selection.html)）在若干最佳候选里随机抽，避免总抽到同一批词。另外留大约 10–20% 的题量随机撒到远离边界的频段，用来发现"冷门但认识"的词。VST 规格书提醒过，学习者常会因为借词、爱好、专业而认识低频词（[规格书](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)）。
- 词表很大（几万词），每次只测几十个真词，所以一两年内都不必复用。复测已测过的词只为两件事：检查遗忘，以及 Target 词学习后的确认。这和 SRS 的衔接放到工单 03 处理。
- **伪词每次都现生成**（Wuggy / 字符模型），用过就不再用，避免学习者记住"这个是假的"。比例取 20–25%，介于 DET 的 ≥15%（[Settles](https://aclanthology.org/2020.tacl-1.17.pdf)）和 Meara 的 33%（[Meara 1991](https://lognostics.co.uk/vlibrary/meara1991.doc)）之间，以兼顾学习者的积极性（[Meara 1994](https://www.lognostics.co.uk/vlibrary/meara1994a.pdf)）。

### 3.4 滚动更新而不是从头估

- 把所有历史作答（词、时间、答案、反应时、是否核验）存进仓库。每次测试后，用**全部历史**重新拟合 θ，旧作答按时间衰减权重以反映遗忘；或者把上次的后验当作先验，再适当放大方差做贝叶斯更新。这是 IRT 的似然可以按作答相乘的直接推论（[Settles et al. 2020 式(2)](https://aclanthology.org/2020.tacl-1.17.pdf)）。
- 这样单次只有几十个样本也不要紧。频段掌握率的精度会随着累积提高，弥补了 VST 规格书指出的"每 level 题量不足"（[规格书](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)）。
- 量级估算：每次约 60 个真词，每两天测一次，一年能直接观测约 1 万个词。高频段很快就全部测到，模型推断主要用在低频段。

### 3.5 识别猜测与过度自信（多信号叠加）

1. **伪词 false alarm 率**：按 Meara 的 Ag/Δm 或 I_SDT 校正。Ag < 0.7 时，整场测试标为不可信（[Meara 1991](https://lognostics.co.uk/vlibrary/meara1991.doc)）。
2. **释义核验失败率**：直接估计 yes 中的虚报比例。这是弥补伪词不足的主要手段（依据：[Meara 1994](https://www.lognostics.co.uk/vlibrary/meara1994a.pdf) 的已知问题 3）。
3. **反应时**：答 yes 很慢的视为"不确定"，给予较低权重（Pellicer-Sánchez & Schmitt 2012，[DOI](https://doi.org/10.1177/0265532212438053)）。
4. **Person-fit / 不一致**：低频词答 yes、同时高频词答 no 的模式异常，即在 Rasch 模型下的残差大。这时触发复测或核验。
5. 核验题**提供"不认识"选项**：本系统的目标是挑出要学的词，而不是对部分知识宽松给分。VST 规格书指出，设"不知道"选项会让测试更接近回忆式的"严格"测量（[规格书](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)）。这里刻意偏离了 VST 的默认做法。

---

## 4. 推荐

1. **题型**：每次 3–5 分钟，约 80 个 Yes/No 条目（约 60 真词 + 约 20 伪词，约 2.5–3 分钟），加 5–8 道中文四选一释义核验（约 1.5–2 分钟），核验题从本次答 yes 的真词里抽，带"不认识"选项。
2. **模型**：Rasch 型 `P(认识 w) = σ(θ − δ_w)`，δ_w 由词频排名（可加词长）回归得到，不做人工标定。总词汇量 = Σ P，频段掌握率 = 段内 P 均值，Word Band 按 P 阈值划分（初值 0.9 / 0.2，之后再调）。
3. **自适应**：上次的 θ 定位 → 在 P≈0.5 附近用 Randomesque 抽未测过的词，并留 10–20% 随机探测远频段；伪词每次现生成（Wuggy，MIT）、用过不再用。
4. **滚动**：保存全部原始作答，每次用全部历史（带时间衰减）重新拟合，不从头估。
5. **纠偏**：伪词 Ag/Δm、核验失败率折减、反应时降权、person-fit 异常，四者叠加；Ag < 0.7 的场次标为不可信，不计入。
6. **冷启动**（可选）：第一次做一遍官方 **VST 普通话双语版**（约 30 分钟，研究/个人用免授权），作为基线和外部校准；之后只用自建的 Yes/No 题库。
7. **可直接复用的公开资源**：VST/Updated VLT 题目（格式与掌握线）、Ehara 2018 数据（难度先验）、Brysbaert prevalence（CC BY 4.0）、Wuggy、catsim（BSD-3）。Duolingo 和 testyourvocab 的题库都不公开，只借鉴设计。

## 5. 未核实项与开放问题

- I_SDT 和 Ag 的精确公式需要对照原文核实（Huibregtse et al. 2002 是付费文献；Meara 1991 的文本提取有误差）。
- "Yes/No + 抽样释义核验"这种组合没有找到成套的一手验证文献，属于推断，需要用自己的数据检验：比如每隔几周抽查一批 Mastered 词，看核验通过率。
- 计数单位（词族 / lemma / headword）会影响总量的数字。VST 按词族计，testyourvocab 按词典 headword 计，要和工单 01 选定的词频表保持一致。
- 释义核验的干扰项由谁生成（LLM？双语词典？），以及中文释义的质量控制。
- 时间衰减（遗忘）的参数怎么设，以及和 SRS（工单 03）怎么共享同一份"词—状态"数据。
