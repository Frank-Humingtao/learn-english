# 调研：间隔重复算法与 Anki 卡组格式

来源工单：[03-srs-and-anki](../issues/03-srs-and-anki.md)
调研日期：2026-11-11

## 问题

FSRS 能不能用来调度卡片？Swift/iOS 上有哪些现成实现，授权是什么？Anki 的 .apkg/.colpkg 格式是什么结构，导入共享卡组要解析哪些内容、会遇到哪些坑？AnkiWeb 上有没有高质量、可以个人使用的英语词汇卡组（最好带中文释义）？卡片的复习记录怎样与 Learner Profile 的 Word Band 互相映射？

## 一、FSRS 是否适合

### 1. 模型

- FSRS 用 DSR 三个量描述每张卡（[ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS)）：
  - **Retrievability (R)**：此刻能回忆起来的概率。
  - **Stability (S)**：R 从 100% 降到 90% 所需的天数。
  - **Difficulty (D)**：影响每次复习后 S 增长的快慢。
- R 每天都在变，D 和 S 只在复习后更新。用户设定「期望保留率」后，算法据此排期；70%–97% 都算合理（同上）。
- 评分分四档：1 again、2 hard、3 good、4 easy（[The Algorithm](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)）。
- FSRS-6 的遗忘曲线是 `R(t,S) = (1 + factor·t/S)^(−w20)`，其中 `factor = 0.9^(−1/w20) − 1`，保证 R(S,S)=90%。模型共 21 个参数，文档给出了默认值，w20 默认取 0.1542（同上）。
- 排期间隔由「把期望保留率代入 R 再解出 t」得到（同上）。由此推出 `I = S/factor · (r^(−1/w20) − 1)`；r=0.9 时 I=S（这一步是本文推导）。

### 2. 效果与成熟度

- 官方基准 srs-benchmark 覆盖约 1 万个 Anki 用户集合、约 3.5 亿条复习记录（[srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark)）。
  - 不计同日复习时，FSRS-6 的 log loss 是 0.3460，RMSE(bins) 是 0.0653。
  - 同口径下 FSRS-5 是 0.3561 / 0.0742，FSRS v4 是 0.3726 / 0.0838（同上）。
  - 表中已经出现 FSRS-7 的变体，但还没有成为主流实现（同上）。
  - README 的文字表格里没有 SM-2 的数值。
- Anki 23.10、AnkiMobile 23.10、AnkiWeb 和 AnkiDroid 2.17+ 都已内置 FSRS。默认期望保留率是 90%（[Deck Options › FSRS](https://docs.ankiweb.net/deck-options.html)）。
- 参数优化要读复习历史。复习条数少于「几百条」时，优化出的参数效果不佳；数据不够时直接用默认参数，默认值是用约 1 万用户、数亿条复习拟合出来的（[Deck Options](https://docs.ankiweb.net/deck-options.html)、[ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS)）。
- FSRS 官方建议学习步和重学步都控制在一天以内，例如 10m 或 30m，步数尽量少（[Deck Options](https://docs.ankiweb.net/deck-options.html)）。

**结论**：FSRS 适合。它是 Anki 现行的调度算法之一，开源实现齐全。单个学习者起步时直接用默认参数，攒到几百条以上的复习记录后再考虑优化。

## 二、Swift/iOS 实现及授权

| 实现 | 版本 | 授权 | 说明 |
|---|---|---|---|
| [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)（官方组织） | FSRS-6，兼容 FSRS-5 | MIT（[LICENSE](https://raw.githubusercontent.com/open-spaced-repetition/swift-fsrs/main/LICENSE)） | SPM 包，`iOS 14+`、`swift-tools-version 5.10`（[Package.swift](https://raw.githubusercontent.com/open-spaced-repetition/swift-fsrs/main/Package.swift)）；只有调度器，没有优化器 |
| [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs) | FSRS-6 调度器 + 优化器 | BSD-3-Clause | Anki 本体在用；官方绑定有 C、Python、Node、Dart、PHP，没有 Swift |
| [py-fsrs](https://github.com/open-spaced-repetition/py-fsrs) | FSRS-6 调度器 + 可选优化器（`pip install "fsrs[optimizer]"`） | MIT | 多个 iOS App 自己把它移植成 Swift（[awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs)） |

swift-fsrs 的细节：

- 维护状态：2026-05 合入了 FSRS-6 支持（PR #30）和并发友好改造（PR #33），2026-05-25 迁移到 Swift Testing，目前在活跃维护（[commits](https://github.com/open-spaced-repetition/swift-fsrs/commits/main)）。
  - awesome-fsrs 列表里仍标注它是「v5」，这个标注已经过时（[awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs)）。
  - 仓库没有正式的 Release，只有 tag（[repo](https://github.com/open-spaced-repetition/swift-fsrs)）。
- 用法：用 `FSRS(parameters: .init(w: FSRSDefaults.defaultWv6))` 启用 v6，用 `try fsrs.next(card:now:grade:)` 排下一次复习（[README](https://raw.githubusercontent.com/open-spaced-repetition/swift-fsrs/main/README.md)）。
- 公开方法还有（[FSRS.swift](https://raw.githubusercontent.com/open-spaced-repetition/swift-fsrs/main/Sources/FSRS/Algorithm/FSRS.swift)）：
  - `repeat`：预览四档评分各自的结果。
  - `getRetrievability`
  - `rollback`：撤销一次复习。
  - `forget`
  - `reschedule`：按复习日志重放。
- `Card` 的字段有 `due, stability, difficulty, elapsedDays, scheduledDays, learningSteps, reps, lapses, state, lastReview`。`ReviewLog` 记录 `rating, state, due, stability, difficulty, elapsedDays, lastElapsedDays, scheduledDays, learningSteps, review`（[FSRSModels.swift](https://raw.githubusercontent.com/open-spaced-repetition/swift-fsrs/main/Sources/FSRS/Models/FSRSModels.swift)）。
  - 两者都实现了 `Codable, Sendable`，可以直接编码成 JSON 存进仓库。
  - `Rating` 的取值是 manual=0、again=1、hard=2、good=3、easy=4，和 Anki revlog 的 ease 编码一致（同上）。
- 以后如果要在设备上训练参数：可以把 fsrs-rs 经 UniFFI 或 swift-bridge 桥接进来，已有 App 这样做过（Avorio、Discito，见 [awesome-fsrs](https://github.com/open-spaced-repetition/awesome-fsrs)）。也可以在 GitHub Actions 里用 Python 跑优化器，再把参数写回仓库（这一条是本文的建议）。

## 三、Anki 包格式

### 1. 外层：zip 包

- **.apkg** 导出单个牌组及其子牌组，导入时合并进现有集合，可以选择是否带调度信息和媒体。**.colpkg** 导出整个集合，导入时会替换整个集合（[Exporting](https://docs.ankiweb.net/exporting.html)）。
- 包有三个版本（[meta.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/import_export/package/meta.rs)）：

  | 版本 | 集合文件 | schema | 压缩 |
  |---|---|---|---|
  | Legacy1 | `collection.anki2` | V11 | 无 |
  | Legacy2 | `collection.anki21` | V11 | 无 |
  | Latest | `collection.anki21b` | V18 | zstd |

- 判断版本的方法（同上）：
  - zip 里有 `meta` 条目时，读其中的 protobuf `PackageMetadata` 取版本号。
  - 没有 `meta` 时，看有没有 `collection.anki21`：有就是 Legacy2，没有就是 Legacy1。
- **媒体清单**（[media.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/import_export/package/media.rs)、[colpkg/export.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/import_export/package/colpkg/export.rs)）：
  - 旧版是 zip 内名为 `media` 的 JSON，形如 `{"0": "foo.mp3", ...}`，键是 zip 条目名，值是原始文件名。
  - 新版改成 protobuf `MediaEntries`，带 name、size、sha1，用条目的序号对应 zip 条目名。清单和媒体文件本身都经过 zstd 压缩。
- 导出时勾选「Support older Anki versions」会生成旧格式，体积更大、速度更慢（[Exporting](https://docs.ankiweb.net/exporting.html)）。

### 2. 内层：SQLite 集合

- **schema 11**（[schema11.sql](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/schema11.sql)）：
  - `col` 表里有 `models, decks, dconf, conf, tags`，都是 JSON 文本。
  - 其余是 `notes`、`cards`、`revlog`、`graves` 四张表。
- **schema 15 起**把笔记类型和牌组拆成独立的 `notetypes`、`fields`、`templates`、`decks` 表，配置存在 `config` 等 blob 列里（[schema15_upgrade.sql](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/upgrades/schema15_upgrade.sql)）。
  - 这些 blob 是 protobuf，例如 `NotetypeConfig::decode(...)`（[notetype/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/notetype/mod.rs)）。
  - 当前最高 schema 是 18（[upgrades/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/upgrades/mod.rs)）。
- **字段**：`notes.flds` 用 `\x1f`（Unit Separator）连接各字段（[note/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/note/mod.rs)）。字段名和字段顺序要到笔记类型里查。
- **cards**：`type` 取值 New=0、Learn=1、Review=2、Relearn=3；`queue` 中 −1 表示暂停，−2/−3 表示埋藏（[card/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/card/mod.rs)）。
  - FSRS 状态存在 `cards.data` 的 JSON 里，键名有 `s`（stability）、`d`（difficulty）、`dr`（desired retention）、`decay`、`lrt`（上次复习时间）、`cd`（custom data）（[card/data.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/card/data.rs)）。
- **revlog**（[revlog/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/revlog/mod.rs)）：
  - `id` 是毫秒时间戳，`ease` 是所按的按钮，0 表示手动改期。
  - `ivl` 和 `lastIvl` 为正时单位是天，为负时单位是秒。
  - `factor` 是千分比形式的 ease，FSRS 下改存难度值。`time` 是作答耗时（毫秒）。
  - `type` 的取值：0 学习、1 复习、2 重学、3 筛选、4 手动、5 改期。

### 3. 导入要解析什么、有哪些坑

只想拿到「词 + 释义 + 例句」的话，最少要做这几步：

1. 解压 zip。
2. 判断包的版本。新版要先用 zstd 解压 `collection.anki21b`。
3. 用系统自带的 sqlite3 打开集合。
4. 读笔记类型，拿到字段名和顺序。旧版从 `col.models` 的 JSON 里读，新版要解码 protobuf。
5. 按 `\x1f` 切分 `notes.flds`。

坑：

- **zstd**：Apple 的 Compression 框架不支持 zstd，只有 LZFSE、LZ4、zlib、LZMA、Brotli 等（[compression_algorithm](https://developer.apple.com/documentation/compression/compression_algorithm)）。需要另外引入 zstd，facebook/zstd 自带 SPM 清单，产品名是 `libzstd`（[Package.swift](https://raw.githubusercontent.com/facebook/zstd/dev/Package.swift)）。
- **假的 `collection.anki2`**：新版包里也会写一个 `collection.anki2`，但它只是个占位集合，里面唯一一条笔记提示「版本太新，请升级」（`exporting_colpkg_too_new`，见 [colpkg/export.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/import_export/package/colpkg/export.rs)）。所以解析器必须先找 `anki21b`，再找 `anki21`，最后才用 `anki2`，否则只会读到一张提示卡。
- **protobuf**：新版的笔记类型、字段、模板配置都是 protobuf blob，要从 Anki 的 `.proto` 生成 Swift 代码，或者手写最小解码器。
  - 更省事的做法：用桌面版 Anki 勾选「Support older Anki versions」重新导出，就能拿到 schema 11 的 JSON 版本（[Exporting](https://docs.ankiweb.net/exporting.html)）。
- **字段内容是 HTML**：字段里有 HTML，还会夹带 `[sound:xxx.mp3]` 这类媒体标记。媒体文件在 zip 里用数字命名，要按媒体清单还原文件名（[media.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/import_export/package/media.rs)）。
- **每个卡组的字段名都不一样**：比如有的卡组用中文字段名「英语单词 / 中文释义」，有的用 `word`（见下节样例）。导入时要让用户手动映射字段，或者按卡组写适配器。
- **作者的调度信息**：共享卡组可能带着作者自己的复习进度。Anki 官方建议导入时不要勾选「Import any learning progress」（[Importing packaged decks](https://docs.ankiweb.net/importing/packaged-decks.html)）。本系统只取笔记内容，调度状态由自己的 FSRS 重新开始。
- **重复导入**：Anki 按 guid 匹配笔记，较新的版本会覆盖旧的；如果笔记类型变了就不更新（同上）。本系统应改用 lemma 去重。
- **代码授权**：Anki 源码是 AGPL v3+（见 [note/mod.rs](https://raw.githubusercontent.com/ankitects/anki/main/rslib/src/storage/note/mod.rs) 文件头）。可以参考它的格式自己实现，但不要整段搬代码，以免整个 App 被 AGPL 传染。

## 四、AnkiWeb 共享卡组

### 1. 授权（关键约束）

AnkiWeb 条款规定，下载共享卡组时，作者授予的许可仅限「use the material in your personal studies」，而且 AnkiWeb 不审核卡组内容（[AnkiWeb Terms](https://ankiweb.net/account/terms)）。

本项目的数据仓库是公开的，所以**共享卡组的内容（释义、例句、音频）不能提交进公开仓库**，只能保存在设备本地。这与工单 06 定下的「第三方全文不入库」口径一致。另外，许多中文卡组的内容是从柯林斯、有道等词典搬来的，来源本身的版权也不清楚。

### 2. 候选卡组（在 AnkiWeb 搜索「COCA」得到，[搜索结果](https://ankiweb.net/shared/decks?search=COCA)）

| 卡组 | 规模 / 更新 | 内容 | 备注 |
|---|---|---|---|
| [17641 COCA words](https://ankiweb.net/shared/info/1696986899) | 17,641 条笔记，2019-03-01 | 音标、**中文释义**、中英例句、vocabulary.com 英文简释与扩展、柯林斯释义 | 无音频；评价正面；字段名是中文 |
| [COCA20000 modified](https://ankiweb.net/shared/info/1231131460) | 18,997 条，2025-11-07 | 由 [COCA20000](https://ankiweb.net/shared/info/659656088) 派生，带音频，另加 Gemini 2.5 Flash 生成的中文讲解字段 | 237 MB；AI 生成的内容要抽查 |
| [COCA English Vocabulary Deck](https://ankiweb.net/shared/info/1262027949)（Ecattea） | 5,000 个 lemma，按义项拆卡，2025-06-21 | 例句在正面，Merriam-Webster Learner's 释义在背面，**全英文** | 自称 CC BY-NC-SA 4.0，但没有说明 MW 内容的授权（[GitHub](https://github.com/Ecattea/COCA-English-Anki-Deck)） |
| [anki-english-60k-decks](https://github.com/5mdld/anki-english-60k-decks)（GitHub） | 60k 词，约 66k 张卡 | MW Learner's 释义，AI 生成的简体中文翻译 | 明确声明 MW 内容不在许可范围内；Wiktionary 部分是 CC BY-SA 4.0 |

这些卡组可以当作**个人设备上的内容补充**，或者**拿来参考版式**（「英文释义 + 例句为主，中文可见」与 17641 COCA words 的版式接近）。它们不适合做系统的内容主源。工单 01 已经选定 ECDICT（MIT）和 Wiktextract（CC BY-SA），这些可以合法进入公开仓库，Card 的内容应以它们为准。

## 五、复习记录与 Word Band 的映射（设计建议）

本节是基于上面事实的设计推导，不是外部来源的结论。可以引用的锚点有：

- Anki 把间隔达到 21 天的卡称为 mature，不足 21 天的称为 young（[Getting Started](https://docs.ankiweb.net/getting-started.html)）。
- 卡片遗忘（lapse）累计 8 次后，Anki 会把它标成 leech 并暂停（[Leeches](https://docs.ankiweb.net/leeches.html)）。
- S 的含义是「R 降到 90% 所需天数」（[ABC of FSRS](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/ABC-of-FSRS)）。

**Word Band → Card（发卡）**
- **Target**：只给这一档的词生成 Card，`state=new`。
- **Mastered**：不发卡。
- **Distant**：不发卡；如果已经有卡，就暂停。

**Card → Word Band（升降级，在每次同步或生成 Learner Profile 时计算）**
- **Target → Mastered**：同时满足以下条件时升级。
  - 卡片处于 review 状态。
  - `stability ≥ S_mastered`，建议 S_mastered 起步取 90 天，至少不低于 Anki 的 21 天成熟线。
  - 最近一次评分不是 again。
  - 升级后卡片仍保留，继续低频复习。如果之后遗忘、S 跌回阈值以下，就退回 Target。
- **Target → Distant**：lapses 达到 8 次（对应 Anki 的 leech 线），或者连续几次 again。这类卡先暂停，等下一轮 Vocabulary Test 再评估。
- **Vocabulary Test 的结果优先级更高**：
  - 测试判定为「认识」的 Target 词，可以直接升到 Mastered。也可以给卡片记一次 `easy`，同时在 ReviewLog 里标明来源是测试，以免污染优化器的数据。
  - 测试判定为「不认识」的 Mastered 词，退回 Target 并重新发卡。

**存储**
- 复习记录直接用 swift-fsrs 的 `ReviewLog`（Codable JSON），追加到工单 05 定下的 JSONL 文件里。
- 字段尽量与 Anki revlog 对齐（ease 1–4、毫秒时间戳、作答耗时），方便以后导出到 Anki，或者交给 fsrs-rs、py-fsrs 的优化器训练。
- FSRS 参数 `w` 和期望保留率放在仓库的配置文件里。

## 推荐

1. **调度算法用 FSRS-6，实现用 [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs)**（MIT，iOS 14+，2026-05 起支持 v6，仍在维护）。
   - 起步用默认参数，期望保留率取 0.9，学习步取 1–2 个当天步。
   - 复习记录积累到几百条以上后，在 GitHub Actions 里用 py-fsrs 或 fsrs-rs 的优化器训练参数，再写回仓库。
   - swift-fsrs 只有 tag 没有 Release，建议用 SPM 锁定到具体 commit 或 tag。
2. **Card 内容以 ECDICT 和 Wiktextract 为主源**（与工单 01 一致）。AnkiWeb 共享卡组只作为设备本地的可选补充，内容不进公开仓库，因为 AnkiWeb 只授予个人学习许可。
3. **Anki 导入放在 MVP 之后**，做成「只导入笔记内容，不导入调度」的单向功能。
   - 首版只支持 schema 11 的旧格式包，即在桌面版 Anki 勾选「Support older Anki versions」重新导出，不必处理 zstd 和 protobuf。
   - 以后再引入 `libzstd` 和 protobuf 解码，支持 `anki21b`。
   - 解析顺序必须是 anki21b → anki21 → anki2，否则会读到「请升级」的占位集合。
   - 按 lemma 去重，字段由用户手动映射。
4. **Word Band 映射规则**：只给 Target 词发卡。stability 达到 90 天（可调）就升为 Mastered；lapses 达到 8 次就降为 Distant 并暂停卡片。Vocabulary Test 的结论优先于卡片状态。复习记录与 Anki revlog 字段对齐，方便以后导出或训练参数。
