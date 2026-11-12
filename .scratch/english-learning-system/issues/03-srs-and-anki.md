# 调研：间隔重复算法与 Anki 卡组格式

Type: research
Status: resolved
Assignee:
Blocked by: 
Part of: ../map.md

## Question

FSRS 是否适合作为卡片调度算法，在 Swift/iOS 上有哪些现成实现及其授权？Anki 的 .apkg/.colpkg 格式结构如何，导入共享卡组需要解析什么、有哪些坑？AnkiWeb 上是否有高质量、可用于个人使用的英语词汇卡组（附中文释义更好）？卡片复习记录如何与 Learner Profile 的 Word Band 相互映射？

## Answer

- 调度用 FSRS-6，实现用官方 swift-fsrs（MIT，SPM，iOS 14+，2026-05 起支持 v6）。起步用默认参数，期望保留率 0.9。复习记录积累到几百条后，在 GitHub Actions 里用 py-fsrs（MIT）训练参数，再写回仓库。
- 复习记录直接存 swift-fsrs 的 Codable `ReviewLog`，字段与 Anki revlog 对齐（ease 1–4、毫秒时间戳），方便以后导出到 Anki 或训练参数。
- Word Band 映射：只给 Target 词发卡。stability ≥ 90 天（可调）升为 Mastered；lapses ≥ 8 次（Anki 的 leech 线）降为 Distant 并暂停卡片。Vocabulary Test 的结论优先于卡片状态。
- AnkiWeb 共享卡组只授予「个人学习」许可，内容不能进公开仓库。候选里中文释义最全的是「17641 COCA words」，但只作为设备本地的可选补充；Card 的主内容仍来自 ECDICT 和 Wiktextract。
- Anki 导入放在 MVP 之后，只导入笔记内容，不导入调度。首版只支持旧格式包（schema 11、JSON、无 zstd）；新版 `anki21b` 需要 zstd 和 protobuf。解析时要先找 anki21b 再找 anki21，否则会读到「请升级」的占位集合。

[调研笔记](../research/03-srs-and-anki.md)
