# 调研：词频词表与词典数据来源

对应 ticket：[01-word-frequency-sources](../issues/01-word-frequency-sources.md)
调研日期：2026-11-11

## 问题

1. 用哪份词频表作为 Vocabulary Test 和 Word Band 的基础？规模、覆盖面、授权、获取方式。
2. 哪些词典数据可用于个人项目，提供英文释义、中文释义、例句、发音？
3. 词形归并用哪种口径（lemma / flemma / word family）？

约束：单个中文母语 Learner；数据存放在**公开** GitHub 仓库，所以"能否再分发"是硬条件。

---

## 一、词频表

### 1. BNC/COCA word family lists（Paul Nation）

- **规模**：共 29 个列表：25 个按频率和分布范围排序的 1000 词族列表（1k–25k），另有 4 个补充列表：专有名词、边缘词（脏话、感叹词、字母）、透明复合词、缩略词。[Nation 2018 说明 PDF](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **口径**：Bauer & Nation Level 6 词族，即包含 Level 2–6 的全部屈折和派生词缀。同一作者另有 "Level 3 partial" 版本，只保留屈折加 un-、-ly、-er、-th 四个词缀，介于 flemma 和词族之间。[同上](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **构造**：前 2000 词族来自一个专门构建的 1000 万 token 语料库，其中 600 万是英美口语和影视，因此 hello、dad、bye 这类口语高频词能进入 1k。3k 以后按 Mark Davies 提供的 COCA/BNC 排名排序。[同上](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **质量**：Dang & Webb (2016) 的比较研究显示，这套列表在口语和书面语文本上都表现良好。[同上](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **获取**：每个 1000 级有单独的 PDF，前 10,000 个 headword 有 ZIP 下载。纯文本族表（UTF-8，Range 或 AntWordProfiler 格式）可通过官网的 word family finder 应用下载。原来的 Range 程序已不再提供，作者推荐改用 AntWordProfiler。[Nation 词表页](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-lists)、[说明 PDF](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **授权**：官网和说明 PDF 都**没有写明许可证**，只给出 APA 引用格式（Nation, 2017, Version 1.0.0）。可以免费下载，但能否在公开仓库再分发并不明确。[说明 PDF](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)
- **与测试的关系**：Nation 的 Vocabulary Size Test 就是按 BNC 词族频率级（Level 6）抽样的，有 14k 版（140 题）和两个平行的 20k 版（各 100 题），还有包括汉语在内的双语版。作者声明研究用途无需许可。[VST 说明 PDF](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)
- **与 Coverage 的关系**：Nation (2006) 用 BNC 词族列表估算，书面文本达到 98% 覆盖需要 8,000–9,000 词族，口语需要 6,000–7,000 词族。[Nation 2006 原文 PDF](https://www.wgtn.ac.nz/__data/assets/pdf_file/0018/1626120/2006-How-large-a-vocab.pdf)

### 2. COCA 词频表（wordfrequency.info，Mark Davies）

- **内容**：前 60,000 个 lemma，带词性，分 8 个主要文体；约 100 个子文体的频率；60k lemma 的全部词形；另有一份 219,000 词的未 lemma 化全表。[wordfrequency.info](https://www.wordfrequency.info/)
- **免费部分**：每份列表的前 5,000 条，以及每隔 10 条取一条的样本。[同上](https://www.wordfrequency.info/)
- **价格**：20k 为学术 $135 / 商业 $225；60k 为学术 $195 / 商业 $295。没有个人许可档。[购买页](https://www.wordfrequency.info/purchase.asp)
- **授权**：页面没有说明再分发条款。付费数据默认不应放进公开仓库。[购买页](https://www.wordfrequency.info/purchase.asp)
- **结论**：数据质量最好，但付费且不可公开，不适合本项目的公开仓库。

### 3. NGSL / NAWL 系列（Browne 等）

- **NGSL 1.2**（2023 年 4 月）：2,809 词，号称平均覆盖一般英语文本 92% 以上（Harry Potter 93%、TOEIC 94%、许多电视剧 95%）。[NGSL 页](https://www.newgeneralservicelist.com/new-general-service-list)
- **系列列表**：NAWL（学术）、TSL（TOEIC，1,250 词）、BSL（商务）、NGSL-Spoken 等。[官网首页](https://www.newgeneralservicelist.com/)
- **授权**：CC BY-SA 4.0，可商用，可再分发（需署名并以相同协议共享）。[NGSL 页](https://www.newgeneralservicelist.com/new-general-service-list)
- **获取**：提供 CSV、TXT、XLSX，包括 lemmatized 列表和英文释义；另有一份 "31k research file"。[同上](https://www.newgeneralservicelist.com/new-general-service-list)
- **结论**：授权最干净，但核心表只有约 2.8k 词，无法区分 3k 以上的 Learner。可以作为"高频核心"的参照标签，不能作为全量骨架。

### 4. SUBTLEX-US（Brysbaert & New）

- **规模**：基于 8,388 部美国电影和电视剧字幕，约 5,100 万词；74,286 个词形（其中 60,384 个频次大于 1）。[SUBTLEX-US 页](https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus)
- **字段**：FREQcount、CDcount（出现该词的影片数，即分布广度）、SUBTLWF（每百万词频次）、Lg10WF、Zipf 值，以及词性信息。[同上](https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus)
- **口径**：词形（word form），**不做 lemma 化**。[同上](https://www.ugent.be/pp/experimentele-psychologie/en/research/documents/subtlexus)
- **授权**：页面没有写明许可证。wordfreq 转述的条件是"注明 SUBTLEX 作者并说明数据可免费获取"。[wordfreq README](https://github.com/rspeer/wordfreq)
- **结论**：最能反映口语和影视词汇，适合"看视频"场景的辅助信号；但它是词形频率，需要自己归并。

### 5. wordfreq（rspeer）

- **数据来源**：英语综合了 Wikipedia、字幕（OpenSubtitles、SUBTLEX）、新闻、Google Books、OSCAR 网页、Twitter、Reddit。提供 Zipf 频率。[wordfreq README](https://github.com/rspeer/wordfreq)
- **状态**：已进入 sunset，数据停在约 2021 年，作者表示"不太可能再更新"。[同上](https://github.com/rspeer/wordfreq)
- **授权**：代码为 Apache；部分数据为 CC BY-SA 4.0；Google Books 和 SUBTLEX 各有署名要求。README 明确说**不允许把 wordfreq 转成 CSV**，理由是 CSV 无法携带署名条款。[同上](https://github.com/rspeer/wordfreq)
- **口径**：只做分词，不做 lemma 化。[同上](https://github.com/rspeer/wordfreq)
- **结论**：不适合导出成文件放进仓库。最多在 Python 构建脚本里查询，用作 BNC/COCA 未收录词的后备排序。

### 6. ECDICT 自带的频率字段

ECDICT（见第二部分）每个词条带两个排名字段：`bnc` 是 BNC 语料排名，`frq` 是当代语料排名（作者描述为"近 20 年"）。作者保留两者，是因为像 quay、Taliban 这样的词在两个语料中排名差异很大。词条还带有 `tag` 考试标签（zk 中考、gk 高考、cet4、cet6、ky 考研、toefl、ielts、gre）和 `oxford`（是否属于 Oxford 3000）。授权为 MIT。[ECDICT README](https://github.com/skywind3000/ECDICT)

这些字段对中国学习者特别有用：考试标签可以作为 Vocabulary Test 的先验，例如可以大致假设 Learner 已掌握 cet4 范围内的词，再用测试校准。

---

## 二、词典数据（释义、中文、例句、发音）

| 来源 | 英文释义 | 中文释义 | 例句 | 发音 | 规模 | 授权 |
|---|---|---|---|---|---|---|
| **ECDICT** | 有（`definition`） | 有（`translation`） | **无**（README 标注"待添加"） | IPA 有；音频"待添加" | 默认 csv 约 76 万条 | **MIT** |
| **Wiktextract / kaikki.org**（英文版 Wiktionary） | 有（`senses[].glosses`） | 部分有（`translations` 中的中文条目） | 有（`senses[].examples`） | IPA 有；音频有（`ogg_url`、`mp3_url`） | 英语词条约 140 万个词形 | Wiktionary 文本为 **CC BY-SA 4.0 + GFDL** |
| **Open English WordNet** | 有（synset 释义） | 无 | 部分有 | 无 | 120,068 个 synset，153,261 个词条 | **CC BY 4.0** |
| **Tatoeba** | — | — | 有，带中英互译句对 | 部分句子有音频，授权逐条不同 | — | 句子为 **CC BY 2.0 FR**（部分为 CC0） |

来源细节：

- **ECDICT**：字段包括 `word`、`phonetic`、`definition`、`translation`、`pos`、`collins`、`oxford`、`tag`、`bnc`、`frq`、`exchange`（时态、复数等变形）、`detail`、`audio`。提供 CSV、SQLite、MySQL 格式，附带 `stardict.py` 工具。还有一份 `lemma.en.txt`：从 BNC 约 1 亿 token 生成的"词形 → lemma"映射（例如 gave→give、teeth→tooth），作者称能覆盖约 95% 的情况，其余用后缀规则兜底。[ECDICT README](https://github.com/skywind3000/ECDICT)
- **Wiktextract**：每个词条的 JSON 包括 `senses`（含 `glosses` 和 `examples`）、`sounds`（含 `ipa`、`audio`、`ogg_url`、`mp3_url`）、`translations`（含 `code`、`lang`、`word`、`sense`）和 `forms`。代码是 MIT 授权，README 没有说明提取出的数据用什么协议。[wiktextract README](https://github.com/tatuylonen/wiktextract)
  - kaikki.org 的英语专用 JSONL 约 3.2GB，已被标注为 deprecated，基于 2026-10-01 的 enwiktionary dump。[kaikki English](https://kaikki.org/dictionary/English/index.html)
  - 原始全量数据为 24.8GB（压缩后 2.9GB），通常每周更新；另有约 94.2 万个音频文件的批量包，不会自动更新。[kaikki rawdata](https://kaikki.org/dictionary/rawdata.html)
  - 数据源 Wiktionary 的文本授权为 CC BY-SA 4.0 + GFDL 双授权，要求署名并以相同协议共享；词条中引用的外部素材（例如音频）另有各自的条款。[Wiktionary:Copyrights](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)
- **Open English WordNet**：派生自 Princeton WordNet，CC BY 4.0，提供 JSON API。[en-word.net](https://en-word.net/)
- **Tatoeba**：句子导出为 CC BY 2.0 FR，另有一份单独的 CC0 子集。音频授权由贡献者逐条选择，导出中 license 字段为空的音频**不可在 Tatoeba 以外使用**。数据每周六更新。[Tatoeba downloads](https://tatoeba.org/en/downloads)
- **发音兜底**：iOS 自带的 `AVSpeechSynthesizer` 可以离线朗读任意单词，没有授权问题，可以作为 Wiktionary 音频缺失时的后备。[Apple 文档](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)

---

## 三、词形归并口径

三种常见口径：

- **lemma**：同词性的屈折形式合并，例如 give / gave / given。
- **flemma**：跨词性的屈折形式合并，例如 walk (n.) 和 walk (v.) 算一个。
- **word family**：再加上派生词，例如 Level 6 下 happy、unhappy、happiness 算一个。

Nation 本人也承认，文本分析该用哪个层级仍有争论，所以他另外制作了 Level 3 partial 版本。[说明 PDF](https://vuw-web.matrix.squiz.cloud/__data/assets/pdf_file/0004/1689349/Information-on-the-BNC_COCA-word-family-lists-20180705.pdf)

对本系统的取舍：

- **Card 和 Word Band 按 lemma 粒度最合适**。原因有两个：词典数据（ECDICT、Wiktionary）都以 lemma 为词条；而且中文母语者常常认识 happy 却不认识 happiness 的用法，按词族一刀切会高估 Mastered。
- **Vocabulary Test 的抽样分层和对外报告的"词汇量"按 Level 6 word family 最合适**。原因同样有两个：VST 和 98% Coverage 的研究结论（8–9k 词族）都建立在这个口径上，只有用同一口径，报告的数字才能和文献对照。[VST 说明](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)、[Nation 2006](https://www.wgtn.ac.nz/__data/assets/pdf_file/0018/1626120/2006-How-large-a-vocab.pdf)
- **计算文本 Coverage 的流程**：分词 → 用 ECDICT `lemma.en.txt` 把词形还原为 lemma → 判断 lemma 是否属于 Mastered。专有名词、边缘词、透明复合词、缩略词可以参照 Nation 的 4 个补充列表，默认算作"已知"，这与 VST 不计这几类词的做法一致。[VST 说明](https://www.wgtn.ac.nz/lals/resources/paul-nations-resources/vocabulary-tests/the-vocabulary-size-test/Vocabulary-Size-Test-information-and-specifications.pdf)

---

## 推荐

**推荐组合：BNC/COCA 25k 词族表（分层骨架）+ ECDICT（主词典、lemma 映射和频率后备）+ Wiktextract（例句和音频）+ Tatoeba（中英例句，可选）。内部以 lemma 为单位，报告时折算为 word family。**

1. **频率骨架：BNC/COCA Level 6 word family lists（1k–25k）。**
   - Vocabulary Test 按 1000 级分层抽样，"词汇量"按词族数报告，和 VST 以及 98% Coverage 文献同一口径。
   - 1k–2k 包含口语高频词，比纯 BNC 更适合视频场景。
   - **注意授权**：没有明确许可证。建议在公开仓库里只放"lemma → 频率级"这类派生的最小数据并注明出处，原始族表由构建脚本从官网下载；或者写信向 Nation 确认后再提交原文件。
2. **主词典：ECDICT（MIT）。**
   - 一份数据同时提供 IPA、英文释义、中文释义、变形（`exchange`）、考试标签、`bnc`/`frq` 排名，以及 `lemma.en.txt` 词形还原表。
   - 授权最宽松，可以直接放进公开仓库和 App。
   - 对 BNC/COCA 未收录的词，用 ECDICT 的 `frq` 排名作为后备的远近判断。
3. **例句和发音：Wiktextract / kaikki.org（CC BY-SA 4.0）。**
   - 只抽取目标词表（约 2.5 万 lemma）对应的 `examples`、`ipa`、`mp3_url`，不搬运整份 3GB 数据。
   - 仓库需要注明来源，并让这部分派生数据保持 CC BY-SA。
   - 音频缺失时用 iOS `AVSpeechSynthesizer` 兜底。
4. **中文语境例句（可选）：Tatoeba 中英句对（CC BY 2.0 FR，或只用 CC0 子集）。** 不使用未声明授权的音频。
5. **不推荐**：
   - COCA 付费表：付费，且不能放进公开仓库。
   - wordfreq：已停更，且明确禁止导出为 CSV。
   - 只用 NGSL：仅 2.8k 词，区分不了中高级水平。
   - NGSL 可以作为"核心高频"标签（CC BY-SA）；SUBTLEX-US 可以作为"视频常用度"辅助信号，二者都不作为主骨架。

### 待确认的问题

- 能否在公开 GitHub 仓库中再分发 BNC/COCA 族表原文件，需要向 Paul Nation 确认，或者改为构建时下载。
- 混入 CC BY-SA 的 Wiktionary 派生数据后，仓库整体的许可证怎么写：代码 MIT，数据目录单独标注 CC BY-SA。
- Vocabulary Test 是直接采用 Nation VST 的现成题目（包括 Mandarin 双语版），还是按 BNC/COCA 分层自动生成题目？这会影响 ticket 中"测试设计"相关的决策。
