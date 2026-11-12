# 原始记录只追加，派生档案统一重算，并拆成私有和公开两个仓库

学习数据分两层存放：

- **原始记录（Observation）**：只追加，永不改写，存放在私有仓库 `english-data`，按写入方和月份拆成 JSONL 文件。
- **学习档案（Learner Profile）**：由 GitHub Actions 从原始记录重算出来，然后发布到公开仓库 `english-profile`。这一层包括 Word Band、词汇量估计、README 看板和 Progress Report。

iPhone 只追加原始记录，不直接修改派生文件。

之所以这样设计：

- **修改可以重来**：阈值和算法（Rasch 参数、Word Band 划分、FSRS 版本）以后一定会调整。只要原始记录在，重算一遍就行，历史不会丢失。
- **不会写冲突**：只有一个写入方生成派生数据，iPhone 和 Actions 不会争着改同一个文件。
- **隐私**：每条复习记录都带精确时间戳，放进公开的 Git 历史，就等于公开了每天几点学、学了多久，而且以后很难彻底删除。外部 agent 做推荐只需要派生档案。

## Considered Options

- **一个公开仓库**：最简单。被否决，因为它会长期暴露学习时间线。
- **全部私有，只公开 Progress Report 的 issue**：被否决。这样外部 agent 和人工浏览都拿不到 `words.tsv`，也拿不到看板，无法计算 Coverage。
- **iPhone 直接维护派生档案**：被否决。会和 Actions 抢着写同一个文件，而且阈值一改，历史状态就无法重算。

## Consequences

- 从私有仓库发布到公开仓库，需要一个有跨仓库写权限的 token，放在私有仓库的 Secrets 里。
- 派生档案的更新会滞后于 iPhone 的提交，延迟取决于 Actions 何时触发。App 显示自己的状态时，要以设备本地重算的结果为准。
