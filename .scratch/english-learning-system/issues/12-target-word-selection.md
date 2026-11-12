# Target 词的选取与排序

Type: grilling
Status: open
Assignee:
Blocked by: 07
Part of: ../map.md

## Question

Target 里可能有一两千个词。每次学习时，由 AI 决定引入哪些新词、按什么顺序复习。这和推荐阅读与视频是同一套"按水平定制"的思路，只是落在 App 内的卡片上。

具体要回答：
- 每天引入多少新词，挑哪些。依据可以是词频、"似懂非懂"程度、即将推荐的文章或视频里会出现的词。
- AI 和 FSRS 如何分工：FSRS 管"什么时候复习"，AI 管"学什么、先学什么"。
- 顽固词（忘了 8 次以上）怎么处理。
- 由谁来跑这套规划：设备端、Actions，还是外部 agent。规划结果存在哪里。

### 来自「进度汇报 issue 的格式」的补充

- Progress Report 的 `focus_targets` 最多放 50 个词，原样照抄 `recent.json`。这张票的规划结果要能产出这份按优先级排好的列表。
- 报告另有 `newly_mastered`（自上一份以来新掌握的词，最多 30 个），由 Word Band 的变化直接算出，不归这张票管。
- 系统不再接收推荐结果，所以「即将推荐的文章或视频里会出现的词」不能作为选词依据。
