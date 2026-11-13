# 10: 个人化 FSRS 参数

Status: wontfix

**What to build:** 复习记录攒够几百条后，GitHub Actions 用学习者自己的数据训练 FSRS 参数，写回私有仓库；App 同步到新参数后改用它调度，让复习间隔更贴合学习者的记忆。

- Actions 在 `english-data` 中用 py-fsrs 训练，只用来源为 review 的 Observation（不用测试和抽查）。复习条数低于门槛时跳过。
- 参数写入 `english-data` 的 FSRS 参数文件，保留权重和 decay，便于以后升级算法。
- App 同步时读取参数文件，存在就改用个人参数，否则继续用默认参数。

**Blocked by:** 06, 07


- [x] 复习条数不足门槛时，工作流跳过训练、不报错
- [x] 用夹具复习记录训练出的参数文件格式正确，并能被 swift-fsrs 读入
- [x] App 拿到个人参数后，同一张卡的下次间隔与用默认参数时不同，且与 swift-fsrs 用该参数的计算一致
- [x] 训练只使用复习记录

## Comments

**已完成（agent）**

- `english-data-template/`：
  - `scripts/fsrs_train.py` 有两个子命令：
    - `check`：只用标准库，判断要不要训练，把 `train=` 和 `review_count=` 写进 `$GITHUB_OUTPUT`。
    - `train`：调用 py-fsrs 的 `Optimizer` 训练。
    - 只读 `source == "review"` 的 Observation。每个 lemma 算一张卡。评分取 `review.ease`，没有这个字段时按 result 字符串换算。
  - 门槛：
    - 复习 Observation 少于 **600** 条时跳过，正常退出（exit 0）。原因是 py-fsrs 的优化器在跨天复习少于 512 条时会悄悄返回默认值，而复习里有一部分是当天的学习步。
    - 已经训练过之后，要再新增 **200** 条复习才重新训练。
    - 优化器仍然返回默认值时，不写文件。
  - 输出 `fsrs/params.json`：`{"format":1,"algorithm":"FSRS-6","w":[21 个],"decay":w[20],"review_count":N,"trained_at":"…Z","optimizer":"py-fsrs 6.3.2"}`。
  - `scripts/requirements-fsrs.txt` 固定版本：`fsrs[optimizer]==6.3.2`、`torch==2.15.0`，torch 从 CPU wheel 源安装。
  - `.github/workflows/train-fsrs.yml`：单独的工作流，每天 19:30 UTC 运行，也可以手动触发。
    - 先跑 check，需要训练时才安装 torch。
    - 用 `GITHUB_TOKEN`（contents: write）只提交 `fsrs/params.json`，推送前先 rebase。
    - 提交的路径不在 `observations/**` 下，所以不会触发 06 号票的 publish-profile。
  - 测试：`python3 -I english-data-template/scripts/test_fsrs_train.py`。
    - 覆盖：门槛以下跳过（check 和 train 都不报错、不写文件）、只加载复习记录、评分换算、重新训练的条件。
    - 用一个模拟学习者实际训练：1227 条复习，混进测试、抽查、想学、设置和 relearn 记录。检查输出文件的格式；混不混这些非复习记录，训练结果完全相同。
    - 没装 py-fsrs 时训练测试自动跳过。`englishcore.yml` 新增 `fsrs-train` job，装好依赖后跑全部测试。
- EnglishCore `StudyComposer`：
  - 新增 `PersonalFSRSParams`：`repoPath = "fsrs/params.json"`。读入时校验：format 为 1、21 个有限数、w[0..3] > 0、decay 在 [0.1, 0.8] 之间。
  - 新增 `FSRSConfig.resolved(paramsFile:)`：只替换权重，期望保留率和学习步不变。文件缺失或无效时用默认值。
  - `PersonalParamsTests` 用上面真实训练出的参数文件测试：
    - 同一张卡（新卡评"太简单"，到期后评"想起"），默认参数下次间隔 39 天，个人参数 18 天，和 py-fsrs 6.3.2 算出的一样。
    - 四个按钮的间隔都和直接调用 swift-fsrs 的结果一致。
    - 8 种缺失或无效的文件都回退到默认值。
- App：
  - 新增 `Sync/FSRSParamsStore.swift`，把参数文件缓存在 UserDefaults 的 `fsrs.params`。
  - `SyncModel.syncNow` 推送完后用 `readFile(…, ref: main)` 读参数文件。返回 404 时清掉缓存、回到默认值；网络或令牌出错时保留原来的缓存。
  - `AppModel.studyComposer` 从 static let 改成计算属性，读 `sync.fsrsParams.config`。
  - `fake-github.py` 支持 `ref=main`；手动放进 DIR 的文件当作仓库里的文件返回。
- 模拟器验证：新建 LE-ticket10，用完已删除。假服务器上放了 `fsrs/params.json`，App 启动同步时请求 `GET …/fsrs/params.json?ref=main` 返回 200，App 的 UserDefaults 里存下了这个文件。

**未验证**

- 工作流没在真实 GitHub 上跑过，需要 02 号票的真实仓库：setup-python、CPU 版 torch 的安装、推送权限都还没确认。
- 卡片按钮下方的间隔变化没有截图：这次模拟器数据里没有到期的卡。这一点由 Core 测试覆盖。
- 训练时用 lemma 作卡片 ID，没有按 Leech 重置把一张卡的历史拆开，影响很小。

- 2026-11-13：按 [ADR 0002](../../../docs/adr/0002-measure-only-no-study-or-planning.md) 作废。系统只做词汇测量，背词交给墨墨背单词；本票的代码已删除（commit a2ca384）。
