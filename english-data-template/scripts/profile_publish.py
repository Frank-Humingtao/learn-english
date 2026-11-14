#!/usr/bin/env python3
"""Recompute the Learner Profile and publish it to the public `english-profile` repo.

Runs in GitHub Actions inside the private `english-data` repo (see
.github/workflows/publish-profile.yml). Standard library only.

  build    run the Profile Engine CLI over all Observations and (re)write the public files
           (summary.json, words.tsv, recent.json, history.json, README.md) in --profile-dir
  report   create / update / skip the Progress Report issue and close superseded ones
  dry-run  build + report against a local fixture repo; nothing touches GitHub

Report rule (decide_report): a Progress Report is created after the first Vocabulary Test of a
day, the same day's report is updated by later tests that day, review-only syncs never create
or update one, and every other open report is closed (kept, not deleted).

Privacy: public files and reports carry dates, never times of day, and nothing that reveals how much
the Learner reviews (no Observation counts, no review dates).
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from obs_io import load_observations, parse_ts, streak, test_days  # noqa: E402,F401

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

SCHEMA_VERSION = 3  # 2: focus_targets removed (ADR 0002); 3: words.tsv `se`, vocab_size core/tail
LABEL = "progress-report"
PROFILE_REPO = "english-profile"
TITLE_RE = re.compile(r"^Progress Report (\d{4}-\d{2}-\d{2})\b")
STATE_RE = re.compile(r"<!-- progress-report-state: (\{.*?\}) -->")
RECENT_DAYS = 7
MAX_NEWLY_MASTERED = 30
CURVE_POINTS = 60


# --- time ---------------------------------------------------------------------

def tzinfo(name):
    if not name or name == "UTC" or ZoneInfo is None:
        return dt.timezone.utc
    return ZoneInfo(name)


def local_date(t, tz):
    """Aware datetime -> 'YYYY-MM-DD' in the Learner's time zone."""
    return t.astimezone(tzinfo(tz)).date().isoformat()


def tests_digest(times):
    """Opaque watermark of a day's test answers: changes when a test answer is added, reveals no time."""
    stamps = sorted(t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f") for t in times)
    return hashlib.sha256("\n".join(stamps).encode()).hexdigest()[:16]


# --- report decision ------------------------------------------------------------

class Decision:
    """What to do with Progress Report issues after one sync.

    action: "create" | "update" | "none"; date: report day (YYYY-MM-DD); target: issue number
    to update; close: open report issues to close; state: watermark kept (hidden) in the report
    body so a later run knows which tests it has already reported — the report's date and an opaque
    digest of that day's test answers, never a time of day.
    """

    def __init__(self, action, date=None, target=None, close=(), state=None):
        self.action, self.date, self.target = action, date, target
        self.close, self.state = list(close), state

    def __repr__(self):
        return "Decision(%r, date=%r, target=%r, close=%r)" % (self.action, self.date, self.target, self.close)


def state_marker(state):
    return "<!-- progress-report-state: %s -->" % json.dumps(state, sort_keys=True, separators=(",", ":"))


def report_state(body):
    m = STATE_RE.search(body or "")
    if not m:
        return {}
    try:
        return json.loads(m.group(1))
    except ValueError:
        return {}


def report_date(issue):
    m = TITLE_RE.match(issue.get("title") or "")
    return m.group(1) if m else None


def decide_report(observations, reports, tz):
    """Pure decision from all Observations (dicts with ts/source) and the existing
    progress-report issues (dicts with number/title/state/body).

    Stateless across runs on purpose: the watermark lives in the latest report, so a run that
    was skipped (concurrency keeps only one pending run) loses nothing.
    """
    reports = [r for r in reports if report_date(r)]
    latest = max(reports, key=lambda r: (report_date(r), r["number"]), default=None)
    tests = [t for t in (o.get("_t") or parse_ts(o.get("ts")) for o in observations if o.get("source") == "test") if t]
    open_reports = [r["number"] for r in reports if r.get("state") == "open"]

    def others(keep):
        return [n for n in open_reports if n != keep]

    def on(day):
        return [t for t in tests if local_date(t, tz) == day]

    def state(day):
        return {"date": day, "tests": tests_digest(on(day))}

    if not tests:
        return Decision("none", close=others(latest["number"] if latest else None))
    newest_day = local_date(max(tests), tz)
    if latest is None:
        return Decision("create", newest_day, None, open_reports, state(newest_day))
    keep, day = latest["number"], report_date(latest)
    if newest_day > day:  # the first test of a new day
        return Decision("create", newest_day, None, open_reports, state(newest_day))
    # Same day: update when that day's tests changed since the report was written. Older days'
    # late-synced tests and review-only syncs never touch a report. A hand-made issue without a
    # watermark is only superseded by a later day's test.
    mark = report_state(latest.get("body"))
    if mark.get("date") == day and mark.get("tests") != tests_digest(on(day)):
        return Decision("update", day, keep, others(keep), state(day))
    return Decision("none", close=others(keep))


# --- inputs ---------------------------------------------------------------------

def read_words(path):
    """words.tsv -> {lemma: {"band", "p", "rank"}}; {} if missing. Columns by header name, so
    files of any schema version (with or without `se`) read the same."""
    if not os.path.exists(path):
        return {}
    words = {}
    with open(path, encoding="utf-8") as f:
        header = next(f, "").rstrip("\n").split("\t")
        try:
            band, p, rank = header.index("band"), header.index("p"), header.index("rank")
        except ValueError:
            return {}
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) == len(header):
                words[cols[0]] = {"band": cols[band], "p": float(cols[p]), "rank": int(cols[rank])}
    return words


def read_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def write_json(path, data):
    write_text(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


# --- derived public files -------------------------------------------------------

def newly_mastered(prev_words, words, prev_entries, today):
    """Words that became Mastered within the last 7 days, newest first then by rank.

    Diffing against the previously published words.tsv; with no previous file (first run) the
    whole current Mastered set is the baseline, not "new".
    """
    cutoff = (dt.date.fromisoformat(today) - dt.timedelta(days=RECENT_DAYS - 1)).isoformat()
    entries = {}
    for e in prev_entries:
        w = words.get(e.get("lemma"))
        if w and w["band"] == "Mastered" and e.get("date", "") >= cutoff:
            entries[e["lemma"]] = {"lemma": e["lemma"], "rank": w["rank"], "date": e["date"]}
    if prev_words:
        for lemma, w in words.items():
            if w["band"] == "Mastered" and prev_words.get(lemma, {}).get("band") != "Mastered" \
                    and lemma not in entries:
                entries[lemma] = {"lemma": lemma, "rank": w["rank"], "date": today}
    return sorted(entries.values(), key=lambda e: (-int(e["date"].replace("-", "")), e["rank"], e["lemma"]))


def upsert_history(history, today, summary):
    """history.json: one entry per day with the vocabulary size (word families) — the README curve."""
    fam = summary["vocab_size"]["families"]
    entry = {"date": today, "families": fam["estimate"], "low": fam["low"], "high": fam["high"]}
    keep = [{k: h[k] for k in ("date", "families", "low", "high") if k in h}
            for h in history if h.get("date") != today]
    return sorted(keep + [entry], key=lambda h: h["date"])


def reports_url(owner):
    return "https://github.com/%s/%s/issues?q=is%%3Aissue+is%%3Aopen+label%%3A%s" % (owner, PROFILE_REPO, LABEL)


def reports_api_url(owner):
    return "https://api.github.com/repos/%s/%s/issues?labels=%s&state=open" % (owner, PROFILE_REPO, LABEL)


def raw_url(owner, name):
    return "https://raw.githubusercontent.com/%s/%s/main/%s" % (owner, PROFILE_REPO, name)


def readme_url(owner):
    return "https://github.com/%s/%s#readme" % (owner, PROFILE_REPO)


def research_url(owner, name):
    return "https://github.com/%s/learn-english/blob/main/docs/research/%s" % (owner, name)


def interval(e):
    """'**3,832** 个（2,778–4,885）'"""
    return "**{:,}** 个（{:,}–{:,}）".format(e["estimate"], e["low"], e["high"])


def render_readme(summary, history, last_test, owner):
    """The public README: a self-contained explanation of the vocabulary report (what each field
    means, how it is measured, how it compares with common tests) plus a short current snapshot."""
    vs = summary["vocab_size"]
    fam, lem = vs["families"], vs["lemmas"]
    core, tail = vs.get("core"), vs.get("tail")
    levels = summary.get("level_mastery", [])
    bands = summary["band_counts"]
    n_lemmas = bands["mastered"] + bands["target"] + bands["distant"]
    n_families = sum(l["families"] for l in levels)
    n_levels = max([l["level"] for l in levels] + [0])
    ratio = lem["estimate"] / fam["estimate"] if fam["estimate"] else 0
    points = history[-CURVE_POINTS:]
    lines = [
        "# 英语词汇量报告",
        "",
        "一位中国成年英语学习者的英语词汇量报告，每次测试后自动重算并更新。本仓库的文件由程序生成，请勿手改。",
        "",
        "## 当前快照",
        "",
        "- 词族：约 %s，括号内为 95%% 区间" % interval(fam),
    ]
    if core and tail:
        lines.append("  - 前 14k 词族（BNC/COCA 1–14 级）%s，14k 以外 %s" % (interval(core["families"]),
                                                                    interval(tail["families"])))
    lines += [
        "- lemma：约 %s" % interval(lem),
        "- 各频段掌握率：%s" % " · ".join("%dk %d%%" % (l["level"], round(l["mastery"] * 100))
                                      for l in levels[:5]),
        "- 最近测试日期：%s" % (last_test or "暂无"),
        "",
    ]
    if points:
        lines += [
            "```mermaid",
            "xychart-beta",
            '  title "词族数"',
            "  x-axis [%s]" % ", ".join('"%s"' % h["date"][5:] for h in points),
            '  y-axis "词族" 0 --> %d' % max([h["high"] for h in points] + [10]),
            "  line [%s]" % ", ".join(str(h["families"]) for h in points),
            "```",
            "",
        ]
    lines += [
        "最新的 Progress Report（简短摘要）：[打开且带 `%s` label 的 issue](%s)，始终只有一份。"
        % (LABEL, reports_url(owner)),
        "",
        "## 参数说明",
        "",
        "所有区间都是 **95% 区间**。`p` 是\"认识这个词的意思\"的概率，已扣除猜测（见测量方法）。",
        "",
        "### `summary.json`",
        "",
        "| 键 | 含义 |",
        "| --- | --- |",
        "| `schema_version` | 格式版本，当前为 %d |" % SCHEMA_VERSION,
        "| `updated_at` | 最近一次测试的日期（YYYY-MM-DD） |",
        "| `lexicon_version` | 所用词表的版本；变化时逐词数据可能整体移动 |",
        "| `vocab_size.families` | 认识的词族数：`{estimate, low, high}`，即估计值和 95%% 区间。一个词族的 `p` 取其成员 lemma 中最大的 `p`，再对全部 %s 个词族求和 |"
        % "{:,}".format(n_families),
        "| `vocab_size.lemmas` | 认识的 lemma 数：全部 %s 个 lemma 的 `p` 之和，格式同上 |" % "{:,}".format(n_lemmas),
        "| `vocab_size.core` | 只算 BNC/COCA 1–14 级（最常用的 14,000 个词族）：`families`、`lemmas` 两项，格式同上 |",
        "| `vocab_size.tail` | 只算 15–%d 级（14k 以外的长尾），格式同上；主要靠外推，区间宽 |" % n_levels,
        "| `band_counts` | 三类词（Word Band）各有多少个 lemma：`mastered`、`target`、`distant` |",
        "| `level_mastery` | 每个 BNC/COCA 千词级一项：`level`（第几个 1000 词族）、`families`（该级词族数）、`mastery`（该级词族 `p` 的平均值，即该级认识比例的估计，0–1） |",
        "",
        "三类词（按 lemma 划分）：",
        "",
        "- **Mastered**：`p` ≥ 0.9，已经可靠地认识；",
        "- **Target**：`p` < 0.9，且词频排名 ≤ 估计的 lemma 数 + 2000，处在已知范围的边缘；",
        "- **Distant**：其余，目前离已知范围较远。",
        "",
        "### `words.tsv`",
        "",
        "每个 lemma 一行，按词频排名排序，制表符分隔：",
        "",
        "| 列 | 含义 |",
        "| --- | --- |",
        "| `lemma` | 词的基本形式（如 *run* 代表 runs、ran、running） |",
        "| `band` | 三类词之一：`Mastered` / `Target` / `Distant` |",
        "| `p` | 认识这个词意思的概率，0–1 |",
        "| `se` | `p` 的标准误。测过的词小；没测过、靠模型外推的词大 |",
        "| `rank` | 词频排名，1 为最常用 |",
        "",
        "### 其他文件",
        "",
        "- `history.json`：每天一条 `{date, families, low, high}`，即当天的词族数及 95% 区间（上面的曲线）。",
        "- `recent.json`：`newly_mastered` 是近 7 天新进入 Mastered 的词 `{lemma, rank, date}`，`date` 为发现的日期。",
        "",
        "### 版本与读取地址",
        "",
        "- `schema_version` 在文件格式不兼容地变化时加一（3：`words.tsv` 增加 `se`，`vocab_size` 增加 `core` / `tail`）。",
        "- `lexicon_version` 标识词表；同一版本下的 `rank` 和词族划分不变。",
        "- 固定地址（始终指向最新版本）：",
    ]
    lines += ["  - `%s`" % raw_url(owner, n) for n in ("summary.json", "words.tsv", "history.json", "recent.json")]
    lines += [
        "",
        "## 测量方法",
        "",
        "这里的做法不是常见的标准化测试，读数字前需要知道它怎么来的：",
        "",
        "- **题型**：Yes/No 自报。屏幕上出现一个词，回答认识或不认识。题目中混入约 15% 的伪词（拼写像英语、但不存在的词）。答\"认识\"的真词，约 10% 会当场追问一道中文释义四选一，带\"不认识\"选项。",
        "- **选题**：按词频段分层抽样，覆盖到 %d 级的长尾，并多选当前最不确定的词。多次测试的证据累积起来一起计算，越测区间越窄；旧证据随时间慢慢降权，异常的场次（伪词误认或释义答错过多）降权。" % n_levels,
        "- **模型（两层）**：",
        "  - 知识层：每个词有一个难度，由词频排名（取对数）和考纲级别（中考、高考、四级、六级、考研、托福/雅思、GRE 中最早收录的一级）回归得出，并允许单个词偏离回归值；学习者有一个能力值。两者之差给出认识的概率。",
        "  - 作答层：单独刻画\"认识却答不认识\"（漏答）、\"不认识却答认识\"（误认，由伪词估计，真词略高）和四选一的猜中。",
        "  - 所以 `p` 是\"认识\"本身的概率，猜中和误认已扣除。测过的词，`p` 结合了它自己的作答；没测过的词，`p` 来自回归。",
        "- **`se` 与区间**：由拟合参数的不确定性传播得到。测过的词 `se` 小；远离测过区域、靠外推的词 `se` 大。总数的区间还包含\"哪些词恰好认识\"的随机性。",
        "- **词表**：BNC/COCA 词族表（Paul Nation，%d 级、每级 1000 个词族），加上从词族成员到 lemma 的映射，共 %s 个 lemma。" % (n_levels, "{:,}".format(n_lemmas)),
        "",
        "## 和常见测试怎么对照",
        "",
        "下面只给大致方向，不能精确换算。",
        "",
        "- **计数口径差别很大**：同一个人，词族数 < lemma 数 < 单词形式数。本报告里 lemma 数约为词族数的 %.1f 倍；把屈折变化和派生词都算作不同的词，数字还会更大。比较前先确认对方用的是哪种口径。" % ratio,
        "- **词族口径偏宽**：一个词族里只要认识任一成员就算认识整个词族，所以词族数会高于\"整个词族都会\"的真实数量。",
        "- **VST**（Vocabulary Size Test，四选一，按词族计，测到 14k 或 20k）：四选一会因猜测而高估，文献中回忆水平约 2,000 词的学习者可被估到 9,000 以上。本报告扣除了猜测、只算认识意思，所以同一个人的 `vocab_size.families` 通常**低于** VST 分数；与 14k 版对照时用 `vocab_size.core.families`。",
        "- **LexTALE**（60 项 Yes/No，含伪词）：给出的是正确率百分比，用来粗分总体水平，不是词汇量，无法与本报告的数字换算；它对中国学习者的效度也偏弱。",
        "- **testyourvocab**（自报勾选，无核验，按词典词条计）：口径接近 lemma 或更宽，应对照 `vocab_size.lemmas`。它不校正虚报，本报告用伪词和释义核验校正，所以本报告的数字通常**更低**。",
        "- **14k 以外**（`vocab_size.tail`）直接测到的词很少，主要靠外推，误差大；跨测试比较时以 `core` 为主。",
        "",
        "依据见调研：[自适应词汇测试](%s)、[准确的词汇量测量](%s)。" % (
            research_url(owner, "02-adaptive-vocab-test.md"), research_url(owner, "07-accurate-vocab-measurement.md")),
        "",
        "## 隐私",
        "",
        "公开数据只有日期，没有作答时间，也没有原始作答记录。",
        "",
        "## 数据来源与许可",
        "",
        "本仓库的派生数据以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布。"
        "词表与词频排名来自 BNC/COCA word family lists（Paul Nation）和 ECDICT（MIT）。",
        "",
    ]
    return "\n".join(lines)


def run_engine(engine, lexicon, data_dir, out_dir):
    # No --as-of: like the App, the engine measures decay to the latest Observation, so the App and
    # Actions publish the same profile from the same Observations (summary.json's updated_at is a date).
    cmd = [engine, "profile", "--lexicon", lexicon, "--observations",
           os.path.join(data_dir, "observations"), "--out", out_dir]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    sys.stderr.write(r.stderr)
    if r.returncode != 0:
        raise SystemExit("profile-engine failed (exit %d)" % r.returncode)
    sys.stderr.write(r.stdout)


def build(data_dir, profile_dir, engine, lexicon, now, tz, owner):
    """Recompute from all Observations and rewrite the public files in profile_dir."""
    os.makedirs(profile_dir, exist_ok=True)
    today = local_date(now, tz)
    prev_words = read_words(os.path.join(profile_dir, "words.tsv"))
    prev_recent = read_json(os.path.join(profile_dir, "recent.json"), {})
    history = read_json(os.path.join(profile_dir, "history.json"), [])

    tmp = tempfile.mkdtemp(prefix="profile-")
    try:
        run_engine(engine, lexicon, data_dir, tmp)
        for name in ("summary.json", "words.tsv"):
            shutil.copyfile(os.path.join(tmp, name), os.path.join(profile_dir, name))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    summary = read_json(os.path.join(profile_dir, "summary.json"), None)
    words = read_words(os.path.join(profile_dir, "words.tsv"))
    observations = load_observations(data_dir)
    warn_lexicon_mismatch(observations, lexicon)
    recent = {
        "schema_version": SCHEMA_VERSION,
        "updated_at": today,
        "newly_mastered": newly_mastered(prev_words, words, prev_recent.get("newly_mastered", []), today),
    }
    history = upsert_history(history, today, summary)
    zone = tzinfo(tz)
    tests = sorted({o["_t"].astimezone(zone).date().isoformat() for o in observations if o.get("source") == "test"})
    write_json(os.path.join(profile_dir, "recent.json"), recent)
    write_json(os.path.join(profile_dir, "history.json"), history)
    write_text(os.path.join(profile_dir, "README.md"),
               render_readme(summary, history, tests[-1] if tests else None, owner))
    return {"summary": summary, "recent": recent, "history": history, "observations": observations}


def warn_lexicon_mismatch(observations, lexicon):
    """The App stamps each Observation with its bundled lexicon version; if the latest one differs from
    the lexicon this run built, the two sides may disagree, so say so in the workflow log."""
    try:
        with open(os.path.join(lexicon, "meta.json"), encoding="utf-8") as f:
            version = json.load(f).get("version")
    except (OSError, ValueError):
        return
    stamped = [o["lexicon"] for o in observations if o.get("lexicon")]
    if stamped and version and stamped[-1] != version:
        sys.stderr.write("::warning::latest Observation used lexicon %s but this run built %s\n"
                         % (stamped[-1], version))


# --- Progress Report --------------------------------------------------------------

def render_report(decision, built, commit, owner, now):
    """(title, body) of the Progress Report for decision.date. Level only: no content
    preferences, no review details."""
    summary, recent, history = built["summary"], built["recent"], built["history"]
    fam = summary["vocab_size"]["families"]
    before = [h for h in history if h["date"] < decision.date]
    change = fam["estimate"] - before[-1]["families"] if before else 0
    nm = [e["lemma"] for e in recent["newly_mastered"]][:MAX_NEWLY_MASTERED]
    bands = summary["band_counts"]
    data = {
        "schema_version": SCHEMA_VERSION,
        "date": decision.date,
        "profile_commit": commit,
        "vocab_size": {"unit": "word_families", "estimate": fam["estimate"], "low": fam["low"],
                       "high": fam["high"], "change": change},
        "band_counts": {"mastered": bands["mastered"], "target": bands["target"], "distant": bands["distant"]},
        "newly_mastered": nm,
        "words_tsv_url": "https://raw.githubusercontent.com/%s/%s/%s/words.tsv" % (owner, PROFILE_REPO, commit),
    }
    title = "Progress Report %s · 约 %d 词族" % (decision.date, fam["estimate"])
    sign = "+" if change >= 0 else ""
    lines = [
        "## 摘要",
        "",
        "- 词汇量约 **%d** 词族（95%% 区间 %d–%d），%s。" % (
            fam["estimate"], fam["low"], fam["high"], "较上次 %s%d" % (sign, change) if before else "首份记录"),
        "- 已掌握 %d · 学习目标 %d · 暂不考虑 %d。" % (bands["mastered"], bands["target"], bands["distant"]),
        "- 近一周新掌握 %d 个词%s" % (len(recent["newly_mastered"]),
                                 "：" + "、".join(nm[:10]) + ("……" if len(nm) > 10 else "") + "。" if nm else "。"),
        "- 逐词数据：[words.tsv](%s)（固定到本次档案提交）。各参数的含义见 [README](%s)。"
        % (data["words_tsv_url"], readme_url(owner)),
        "",
        "```json",
        json.dumps(data, ensure_ascii=False, indent=2),
        "```",
        "",
        state_marker(decision.state),
        "",
    ]
    return title, "\n".join(lines)


class FileIssues:
    """Issue store backed by a local JSON file (dry-run stand-in for GitHub Issues)."""

    def __init__(self, path):
        self.path = path
        self.items = read_json(path, [])

    def _save(self):
        write_json(self.path, self.items)

    def ensure_label(self):
        pass

    def list_reports(self):
        return [dict(i) for i in self.items if LABEL in i["labels"]]

    def create(self, title, body):
        n = max([i["number"] for i in self.items] + [0]) + 1
        self.items.append({"number": n, "title": title, "body": body, "state": "open", "labels": [LABEL]})
        self._save()
        return n

    def _get(self, number):
        return next(i for i in self.items if i["number"] == number)

    def update(self, number, title, body):
        self._get(number).update(title=title, body=body, state="open")
        self._save()

    def close(self, number):
        self._get(number)["state"] = "closed"
        self._save()


class TokenError(SystemExit):
    pass


class GitHubIssues:
    """Issues REST API of <owner>/english-profile. Fails loudly on an invalid token."""

    def __init__(self, owner, token, api="https://api.github.com", repo=PROFILE_REPO):
        if not token:
            raise TokenError("PROFILE_TOKEN is not set: add it under english-data → Settings → Secrets → Actions")
        self.base = "%s/repos/%s/%s" % (api.rstrip("/"), owner, repo)
        self.token = token

    def _call(self, method, path, body=None, allow404=False):
        req = urllib.request.Request(self.base + path, method=method,
                                     data=None if body is None else json.dumps(body).encode())
        req.add_header("Authorization", "Bearer " + self.token)
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("X-GitHub-Api-Version", "2022-11-28")
        req.add_header("User-Agent", "english-data-publish")
        if body is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            detail = e.read()[:500]
            e.close()
            if e.code == 404 and allow404:
                return None
            if e.code in (401, 403):
                raise TokenError("PROFILE_TOKEN rejected by GitHub (HTTP %d on %s %s): expired, revoked, or "
                                 "missing Issues write on %s" % (e.code, method, path, self.base))
            raise SystemExit("GitHub API %s %s failed: HTTP %d %s" % (method, path, e.code, detail))

    def ensure_label(self):
        if self._call("GET", "/labels/" + LABEL, allow404=True) is None:
            self._call("POST", "/labels", {"name": LABEL, "color": "0e8a16",
                                           "description": "Learner Profile snapshot"})

    def list_reports(self):
        seen, out = set(), []
        queries = ["?labels=%s&state=open&per_page=100&page=%d" % (LABEL, p) for p in range(1, 11)]
        # The newest closed reports too (the latest one may have been closed by hand).
        queries.insert(0, "?labels=%s&state=all&sort=created&direction=desc&per_page=30" % LABEL)
        for i, q in enumerate(queries):
            page = self._call("GET", "/issues" + q) or []
            for it in page:
                if "pull_request" not in it and it["number"] not in seen:
                    seen.add(it["number"])
                    out.append({"number": it["number"], "title": it["title"], "state": it["state"],
                                "body": it.get("body") or ""})
            if i > 0 and len(page) < 100:
                break
        return out

    def create(self, title, body):
        return self._call("POST", "/issues", {"title": title, "body": body, "labels": [LABEL]})["number"]

    def update(self, number, title, body):
        self._call("PATCH", "/issues/%d" % number, {"title": title, "body": body, "state": "open"})

    def close(self, number):
        self._call("PATCH", "/issues/%d" % number, {"state": "closed", "state_reason": "completed"})


def publish_report(store, observations, built, commit, owner, now, tz):
    """Apply decide_report to an issue store. Returns the Decision."""
    store.ensure_label()
    decision = decide_report(observations, store.list_reports(), tz)
    if decision.action != "none":
        title, body = render_report(decision, built, commit, owner, now)
        if decision.action == "create":
            decision.target = store.create(title, body)
        else:
            store.update(decision.target, title, body)
    for n in decision.close:  # after creating, so there is never a moment with none open
        store.close(n)
    return decision


def tree_digest(directory):
    h = hashlib.sha1()
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            h.update(name.encode() + b"\0")
            with open(path, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


def dry_run(data_dir, out_dir, engine, lexicon, now, tz, owner):
    """Whole pipeline without GitHub: profile files land in <out>/english-profile (reused as the
    previous state on the next dry run), issues in <out>/issues.json, the decision in
    <out>/report-decision.json."""
    profile_dir = os.path.join(out_dir, PROFILE_REPO)
    built = build(data_dir, profile_dir, engine, lexicon, now, tz, owner)
    commit = tree_digest(profile_dir)  # stands in for the english-profile commit sha
    d = publish_report(FileIssues(os.path.join(out_dir, "issues.json")), built["observations"], built, commit,
                       owner, now, tz)
    write_json(os.path.join(out_dir, "report-decision.json"),
               {"action": d.action, "date": d.date, "issue": d.target, "closed": d.close})
    return d


# --- CLI ----------------------------------------------------------------------------

def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("build", "report", "dry-run"):
        s = sub.add_parser(name)
        s.add_argument("--data", required=True, help="english-data checkout")
        s.add_argument("--owner", required=True, help="GitHub owner of english-profile")
        s.add_argument("--now", help="ISO 8601 (default: current time)")
        s.add_argument("--tz", default=os.environ.get("REPORT_TZ") or "UTC", help="Learner's time zone")
        if name in ("build", "dry-run"):
            s.add_argument("--engine", required=True, help="profile-engine executable")
            s.add_argument("--lexicon", required=True, help="built lexicon directory")
        if name in ("build", "report"):
            s.add_argument("--profile-dir", required=True, help="english-profile checkout")
        if name == "report":
            s.add_argument("--commit", required=True, help="english-profile commit the report points at")
            s.add_argument("--api", default=os.environ.get("GITHUB_API_URL") or "https://api.github.com")
        if name == "dry-run":
            s.add_argument("--out", required=True, help="output directory (no GitHub calls)")
    a = p.parse_args(argv)
    now = parse_ts(a.now) if a.now else dt.datetime.now(dt.timezone.utc)
    if now is None:
        p.error("bad --now")

    if a.command == "build":
        build(a.data, a.profile_dir, a.engine, a.lexicon, now, a.tz, a.owner)
    elif a.command == "report":
        built = {
            "summary": read_json(os.path.join(a.profile_dir, "summary.json"), None),
            "recent": read_json(os.path.join(a.profile_dir, "recent.json"), None),
            "history": read_json(os.path.join(a.profile_dir, "history.json"), []),
        }
        store = GitHubIssues(a.owner, os.environ.get("GH_TOKEN"), a.api)
        d = publish_report(store, load_observations(a.data), built, a.commit, a.owner, now, a.tz)
        print("progress report: %s %s issue=%s closed=%s" % (d.action, d.date or "-", d.target, d.close))
    else:
        d = dry_run(a.data, a.out, a.engine, a.lexicon, now, a.tz, a.owner)
        print("dry run: %s %s issue=%s closed=%s → %s" % (d.action, d.date or "-", d.target, d.close, a.out))


if __name__ == "__main__":
    main()
