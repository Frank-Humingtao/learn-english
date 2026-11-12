# 调研：词频词表与词典数据来源

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

该用哪份英语词频表作为词汇量测试和 Word Band 的基础（如 COCA、BNC/COCA 合并表、NGSL/NAWL、SUBTLEX 等）？各自的规模、覆盖面、授权和获取方式如何？有哪些可用于个人项目的词典数据能提供英文释义、中文释义、例句和发音（如 ECDICT、Wiktionary/Wiktextract、WordNet）？词形归并（lemma/word family）用哪种口径？给出推荐组合及理由。

## Answer

- 频率骨架用 Paul Nation 的 BNC/COCA 25k 词族表（Level 6）。Vocabulary Test 按 1000 级分层抽样，词汇量按词族数报告，与 VST 和 98% Coverage 文献口径一致。该表没有明确许可证，公开仓库里只放派生数据，或由构建脚本下载原表。
- 主词典用 ECDICT（MIT）。它同时提供 IPA、英文和中文释义、变形、考试标签、bnc/frq 排名，以及 lemma.en.txt 词形还原表。
- 例句和发音从 Wiktextract/kaikki 抽取（CC BY-SA 4.0，需署名），中英例句可选 Tatoeba（CC BY 2.0 FR），音频缺失时用 iOS TTS 兜底。
- 口径：Card 和 Word Band 按 lemma 计，对外报告折算为 word family。不选 COCA 付费表（不可公开）、wordfreq（已停更，禁止导出 CSV），也不单用 NGSL（仅 2.8k 词）。

[调研笔记](../research/01-word-frequency-sources.md)
