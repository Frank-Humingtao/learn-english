# 06: 报告与公开档案升级（schema 3）

Status: ready-for-agent

**What to build:** 让 Recommendation Agent 拿到更详细的数据，并保持只有一个固定读取地址。

- `summary.json` 和 Progress Report 的 JSON：新增 ≤14k / >14k 两段词汇量及区间、lemma 数、各频段掌握率；`schema_version` 升到 3。
- `words.tsv` 新增标准误一列。
- 报告正文的中文摘要保持简短，并说明两段总数的含义，以及词族口径偏高这一点。
- 发布流水线的 dry-run 测试和隐私测试照常通过：公开数据里只有日期，没有作答时间。

**Blocked by:** 02

## Comments
