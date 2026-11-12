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
"""
import argparse
import datetime as dt
import glob
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

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

SCHEMA_VERSION = 1
LABEL = "progress-report"
PROFILE_REPO = "english-profile"
TITLE_RE = re.compile(r"^Progress Report (\d{4}-\d{2}-\d{2})\b")
STATE_RE = re.compile(r"<!-- progress-report-state: (\{.*?\}) -->")
RECENT_DAYS = 7
MAX_NEWLY_MASTERED = 30
MAX_FOCUS_TARGETS = 50
CURVE_POINTS = 60
TS_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$")


# --- time ---------------------------------------------------------------------

def parse_ts(ts):
    """ISO 8601 -> aware UTC datetime; None if malformed."""
    m = TS_RE.match(ts or "")
    if not m:
        return None
    y, mo, d, h, mi, s, frac, off = m.groups()
    micro = int((frac or "0")[:6].ljust(6, "0"))
    t = dt.datetime(int(y), int(mo), int(d), int(h), int(mi), int(s), micro, tzinfo=dt.timezone.utc)
    if off and off != "Z":
        sign = 1 if off[0] == "+" else -1
        t -= sign * dt.timedelta(hours=int(off[1:3]), minutes=int(off[-2:]))
    return t


def tzinfo(name):
    if not name or name == "UTC" or ZoneInfo is None:
        return dt.timezone.utc
    return ZoneInfo(name)


def local_date(t, tz):
    """Aware datetime -> 'YYYY-MM-DD' in the Learner's time zone."""
    return t.astimezone(tzinfo(tz)).date().isoformat()


def iso_utc(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --- report decision ------------------------------------------------------------

class Decision:
    """What to do with Progress Report issues after one sync.

    action: "create" | "update" | "none"; date: report day (YYYY-MM-DD); target: issue number
    to update; close: open report issues to close; last_test_ts: watermark kept (hidden) in the
    report body so a later run knows which tests it has already reported.
    """

    def __init__(self, action, date=None, target=None, close=(), last_test_ts=None):
        self.action, self.date, self.target = action, date, target
        self.close, self.last_test_ts = list(close), last_test_ts

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
    tests = [t for t in (parse_ts(o.get("ts")) for o in observations if o.get("source") == "test") if t]
    open_reports = [r["number"] for r in reports if r.get("state") == "open"]

    def others(keep):
        return [n for n in open_reports if n != keep]

    if latest is None:
        new = tests
    else:
        mark = parse_ts(report_state(latest.get("body")).get("last_test_ts"))
        if mark is not None:
            new = [t for t in tests if t > mark]
        else:  # no watermark (hand-made issue): anything after its day is new
            new = [t for t in tests if local_date(t, tz) > report_date(latest)]
    keep = latest["number"] if latest is not None else None
    if not new:  # review-only (or nothing new): never create or update
        return Decision("none", close=others(keep))
    day = local_date(max(new), tz)
    last_ts = iso_utc(max(tests))
    if latest is not None and day == report_date(latest):
        return Decision("update", day, keep, others(keep), last_ts)
    if latest is not None and day < report_date(latest):  # late sync of an older day's test
        return Decision("none", close=others(keep))
    return Decision("create", day, None, open_reports, last_ts)


# --- inputs ---------------------------------------------------------------------

def load_observations(data_dir):
    """All Observations under <data>/observations/**.jsonl (malformed lines skipped)."""
    out = []
    for path in sorted(glob.glob(os.path.join(data_dir, "observations", "**", "*.jsonl"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if isinstance(o, dict):
                    out.append(o)
    return out


def latest_plan(data_dir):
    """(relative path, parsed JSON) of the newest plan/YYYY-MM-DD.json, or (None, None)."""
    plans = sorted(p for p in glob.glob(os.path.join(data_dir, "plan", "*.json"))
                   if re.fullmatch(r"\d{4}-\d{2}-\d{2}\.json", os.path.basename(p)))
    for path in reversed(plans):
        try:
            with open(path, encoding="utf-8") as f:
                return "plan/" + os.path.basename(path), json.load(f)
        except ValueError:
            continue  # a broken plan never blocks publishing; fall back to the previous one
    return None, None


def read_words(path):
    """words.tsv -> {lemma: {"band", "p", "rank"}}; {} if missing."""
    if not os.path.exists(path):
        return {}
    words = {}
    with open(path, encoding="utf-8") as f:
        next(f, None)
        for line in f:
            cols = line.rstrip("\n").split("\t")
            if len(cols) >= 4:
                words[cols[0]] = {"band": cols[1], "p": float(cols[2]), "rank": int(cols[3])}
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


def test_days(observations, tz):
    return sorted({local_date(t, tz) for t in (parse_ts(o.get("ts")) for o in observations
                                               if o.get("source") == "test") if t})


def streak(days, today):
    """Consecutive test days ending today or yesterday (0 once a full day is missed)."""
    if not days:
        return 0
    have = set(days)
    d = dt.date.fromisoformat(today)
    if d.isoformat() not in have:
        d -= dt.timedelta(days=1)
    n = 0
    while d.isoformat() in have:
        n += 1
        d -= dt.timedelta(days=1)
    return n


def upsert_history(history, today, summary):
    fam = summary["vocab_size"]["families"]
    bands = summary["band_counts"]
    entry = {"date": today, "families": fam["estimate"], "low": fam["low"], "high": fam["high"],
             "mastered": bands["mastered"], "target": bands["target"], "distant": bands["distant"]}
    return sorted([h for h in history if h.get("date") != today] + [entry], key=lambda h: h["date"])


def reports_url(owner):
    return "https://github.com/%s/%s/issues?q=is%%3Aissue+is%%3Aopen+label%%3A%s" % (owner, PROFILE_REPO, LABEL)


def reports_api_url(owner):
    return "https://api.github.com/repos/%s/%s/issues?labels=%s&state=open" % (owner, PROFILE_REPO, LABEL)


def render_readme(summary, recent, history, last_test, streak_days, owner):
    fam = summary["vocab_size"]["families"]
    bands = summary["band_counts"]
    points = history[-CURVE_POINTS:]
    lines = [
        "# English Profile",
        "",
        "Learner Profile 看板：由私有仓库的作答记录（Observation）经 GitHub Actions 自动重算，请勿手改。",
        "",
        "## 词汇量",
        "",
        "约 **%d** 词族（95%% 区间 %d–%d）· 更新于 %s" % (fam["estimate"], fam["low"], fam["high"],
                                                summary.get("updated_at", "")),
        "",
        "```mermaid",
        "xychart-beta",
        '  title "词汇量（词族）"',
        "  x-axis [%s]" % ", ".join('"%s"' % h["date"][5:] for h in points),
        '  y-axis "词族" 0 --> %d' % max([h["high"] for h in points] + [10]),
        "  line [%s]" % ", ".join(str(h["families"]) for h in points),
        "```",
        "",
        "## 三类词",
        "",
        "| 已掌握 Mastered | 学习目标 Target | 暂不考虑 Distant |",
        "| ---: | ---: | ---: |",
        "| %d | %d | %d |" % (bands["mastered"], bands["target"], bands["distant"]),
        "",
        "## 近一周新掌握的词",
        "",
    ]
    nm = recent["newly_mastered"]
    if nm:
        lines.append("共 %d 个：%s" % (len(nm), "、".join(e["lemma"] for e in nm[:100])
                                     + ("……" if len(nm) > 100 else "")))
    else:
        lines.append("暂无。")
    lines += [
        "",
        "## 测试",
        "",
        "- 最近测试日期：%s" % (last_test or "暂无"),
        "- 连续测试天数：%d 天" % streak_days,
        "",
        "## 最新 Progress Report",
        "",
        "始终只有一份打开的报告：[打开且带 `%s` label 的 issue](%s)（API：`%s`）。"
        % (LABEL, reports_url(owner), reports_api_url(owner)),
        "",
        "## 文件",
        "",
        "- `summary.json`：词汇量及区间、三类词数、更新时间",
        "- `words.tsv`：lemma、Word Band、P（认识概率）、词频排名",
        "- `recent.json`：近期新掌握的词、当前学习重点 `focus_targets`",
        "- `history.json`：每日词汇量（用于上面的曲线）",
        "",
        "## 数据来源与许可",
        "",
        "本仓库的派生数据以 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) 发布。"
        "词表与词频排名来自 BNC/COCA word family lists（Paul Nation）和 ECDICT（MIT），"
        "Learner Profile 由本人的测试与复习记录计算得出；原始记录不公开。",
        "",
    ]
    return "\n".join(lines)


def run_engine(engine, lexicon, data_dir, out_dir, now):
    # --as-of = publish time, so decay is measured to now and updated_at is not the time of
    # the last (possibly review) Observation.
    cmd = [engine, "profile", "--lexicon", lexicon, "--observations",
           os.path.join(data_dir, "observations"), "--out", out_dir, "--as-of", iso_utc(now)]
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
        run_engine(engine, lexicon, data_dir, tmp, now)
        for name in ("summary.json", "words.tsv"):
            shutil.copyfile(os.path.join(tmp, name), os.path.join(profile_dir, name))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    summary = read_json(os.path.join(profile_dir, "summary.json"), None)
    words = read_words(os.path.join(profile_dir, "words.tsv"))
    observations = load_observations(data_dir)
    plan_path, plan = latest_plan(data_dir)
    recent = {
        "schema_version": SCHEMA_VERSION,
        "updated_at": iso_utc(now),
        "newly_mastered": newly_mastered(prev_words, words, prev_recent.get("newly_mastered", []), today),
        # Copied verbatim from the latest Study Plan (written by word-plan); empty without one.
        "focus_targets": (plan or {}).get("focus_targets", []),
        "focus_targets_from": plan_path,
    }
    history = upsert_history(history, today, summary)
    days = test_days(observations, tz)
    write_json(os.path.join(profile_dir, "recent.json"), recent)
    write_json(os.path.join(profile_dir, "history.json"), history)
    write_text(os.path.join(profile_dir, "README.md"),
               render_readme(summary, recent, history, days[-1] if days else None, streak(days, today), owner))
    return {"summary": summary, "recent": recent, "history": history, "observations": observations}


# --- Progress Report --------------------------------------------------------------

def render_report(decision, built, commit, owner, now):
    """(title, body) of the Progress Report for decision.date. Level only: no content
    preferences, no review details."""
    summary, recent, history = built["summary"], built["recent"], built["history"]
    fam = summary["vocab_size"]["families"]
    before = [h for h in history if h["date"] < decision.date]
    change = fam["estimate"] - before[-1]["families"] if before else 0
    nm = [e["lemma"] for e in recent["newly_mastered"]][:MAX_NEWLY_MASTERED]
    focus = list(recent["focus_targets"])[:MAX_FOCUS_TARGETS]
    bands = summary["band_counts"]
    data = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": iso_utc(now),
        "profile_commit": commit,
        "vocab_size": {"unit": "word_families", "estimate": fam["estimate"], "low": fam["low"],
                       "high": fam["high"], "change": change},
        "band_counts": {"mastered": bands["mastered"], "target": bands["target"], "distant": bands["distant"]},
        "newly_mastered": nm,
        "focus_targets": focus,
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
        "- 当前学习重点 %d 个词。" % len(focus),
        "- 逐词数据：[words.tsv](%s)（固定到本次档案提交）。" % data["words_tsv_url"],
        "",
        "```json",
        json.dumps(data, ensure_ascii=False, indent=2),
        "```",
        "",
        state_marker({"last_test_ts": decision.last_test_ts}),
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
