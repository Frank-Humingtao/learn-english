# 选词规划 skill 的设计

Type: grilling
Status: open
Assignee:
Blocked by: 12
Part of: ../map.md

## Question

「Target 词的选取与排序」定下：选词由一个新写的 Claude skill `word-plan`（选词规划）完成，在 Claude 桌面 App 里每天定时跑一次，写出 Study Plan 到 `english-data/plan/`。这个 skill 具体怎么设计？

- 它读哪些输入（测试与复习记录、`words.tsv`/学习档案、设置、「想学」记录、上一份计划），读多少历史才够又不撑爆上下文。
- 选词与排序的判断准则写成什么样的提示：似懂非懂、词频、复习积压、顽固词、手动加词的优先级。
- 选词说明的写法与质量要求（长度、中英、不得编造词义），以及与卡片主内容（词典释义、例句）的分工。
- `focus_targets` 的挑选思路。
- 输出文件的校验：lemma 必须在词表里、条数不超上限、JSON 合法；不合格时怎么办。
- 本机定时任务的配置（需要 Mac 开机、本地 clone `english-data`、提交权限），以及运行失败时学习者怎么知道。
