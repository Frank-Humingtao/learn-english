"""Tests for profile_publish.py. Run: python3 -I english-data-template/scripts/test_profile_publish.py"""
import datetime as dt
import json
import os
import re
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import profile_publish as pp  # noqa: E402

TZ = "Asia/Shanghai"
HERE = os.path.dirname(os.path.abspath(__file__))
# The Observations are EnglishCore's fixture (one copy, shared with the Swift tests).
FIXTURE_OBSERVATIONS = os.path.join(HERE, "..", "..", "EnglishCore", "Fixtures", "observations")
FAKE_ENGINE = os.path.join(HERE, "fixtures", "fake_engine.py")


def obs(ts, source="test", lemma="apple", result="yes"):
    return {"ts": ts, "lemma": lemma, "source": source, "result": result}


def report(number, date, state="open", tests=None):
    """A report issue whose hidden watermark covers the given test times (all on `date`)."""
    body = "summary"
    if tests:
        body += "\n" + pp.state_marker({"date": date, "tests": pp.tests_digest([pp.parse_ts(t) for t in tests])})
    return {"number": number, "title": "Progress Report %s · 约 100 词族" % date, "state": state, "body": body}


class DecideReportTests(unittest.TestCase):
    def test_first_test_ever_creates_a_report(self):
        d = pp.decide_report([obs("2026-11-12T01:00:00Z")], [], TZ)
        self.assertEqual(d.action, "create")
        self.assertEqual(d.date, "2026-11-12")
        self.assertEqual(d.close, [])

    def test_first_test_of_a_new_day_creates_and_closes_the_previous_report(self):
        observations = [obs("2026-11-11T01:00:00Z"), obs("2026-11-12T01:00:00Z")]
        reports = [report(7, "2026-11-11", tests=["2026-11-11T01:00:00Z"]),
                   report(3, "2026-11-09", state="closed", tests=["2026-11-09T01:00:00Z"])]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.date, d.close), ("create", "2026-11-12", [7]))
        self.assertEqual(d.state["date"], "2026-11-12")
        self.assertNotIn("01:00", json.dumps(d.state), "the watermark reveals no time of day")

    def test_second_test_on_the_same_day_updates_that_days_report(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T09:30:00.250Z")]
        reports = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z"])]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.date, d.target, d.close), ("update", "2026-11-12", 8, []))
        # Written back, the new watermark makes the next identical sync a no-op.
        again = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z", "2026-11-12T09:30:00.250Z"])]
        self.assertEqual(pp.decide_report(observations, again, TZ).action, "none")

    def test_review_only_sync_does_nothing(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-13T02:00:00Z", source="review", result="good"),
                        obs("2026-11-13T02:01:00Z", source="verify", result="correct")]
        reports = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z"])]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.close), ("none", []))

    def test_review_only_history_never_creates_a_first_report(self):
        d = pp.decide_report([obs("2026-11-12T01:00:00Z", source="review", result="good")], [], TZ)
        self.assertEqual(d.action, "none")

    def test_day_boundary_follows_the_learners_time_zone(self):
        # 2026-11-12T17:00Z is already 11-13 01:00 in Shanghai: a new day, so a new report.
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T17:00:00Z")]
        reports = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z"])]
        self.assertEqual(pp.decide_report(observations, reports, TZ).action, "create")
        self.assertEqual(pp.decide_report(observations, reports, "UTC").action, "update")

    def test_only_one_report_stays_open(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T05:00:00Z")]
        reports = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z"]), report(5, "2026-11-10"),
                   report(2, "2026-11-01")]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.target, sorted(d.close)), ("update", 8, [2, 5]))
        # Even a review-only sync repairs a second open report left behind by a failed run.
        d2 = pp.decide_report([obs("2026-11-12T01:00:00Z")], reports, TZ)
        self.assertEqual((d2.action, sorted(d2.close)), ("none", [2, 5]))

    def test_late_sync_of_an_older_test_does_not_reopen_the_past(self):
        # A test done offline on 11-11 arrives after the 11-12 report exists.
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-11T03:00:00Z")]
        reports = [report(8, "2026-11-12", tests=["2026-11-12T01:00:00Z"])]
        self.assertEqual(pp.decide_report(observations, reports, TZ).action, "none")


class DryRunPipelineTests(unittest.TestCase):
    """Whole pipeline against a fixture english-data repo; GitHub replaced by a local issues file."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.data = os.path.join(self.tmp, "english-data")
        os.makedirs(self.data)
        shutil.copytree(FIXTURE_OBSERVATIONS, os.path.join(self.data, "observations"))
        self.out = os.path.join(self.tmp, "out")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_pipeline(self, now):
        pp.dry_run(self.data, self.out, FAKE_ENGINE, self.tmp, pp.parse_ts(now), TZ, owner="someone")

    def append(self, *lines):
        with open(os.path.join(self.data, "observations", "iphone", "2026-11.jsonl"), "a") as f:
            for o in lines:
                f.write(json.dumps(o, sort_keys=True, separators=(",", ":")) + "\n")

    def profile(self, name):
        with open(os.path.join(self.out, "english-profile", name), encoding="utf-8") as f:
            return f.read()

    def issues(self):
        with open(os.path.join(self.out, "issues.json"), encoding="utf-8") as f:
            return json.load(f)

    def open_reports(self):
        return [i for i in self.issues() if i["state"] == "open" and "progress-report" in i["labels"]]

    def report_json(self, issue):
        return json.loads(re.search(r"```json\n(.*?)\n```", issue["body"], re.S).group(1))

    def test_first_run_publishes_profile_files_and_one_report(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        summary = json.loads(self.profile("summary.json"))
        self.assertIn("estimate", summary["vocab_size"]["families"])
        self.assertIn("band_counts", summary)
        self.assertIn("updated_at", summary)
        self.assertEqual(self.profile("words.tsv").splitlines()[0], "lemma\tband\tp\tse\trank")
        self.assertEqual(sorted(summary["vocab_size"]["core"]), ["families", "lemmas"])
        self.assertEqual(sorted(summary["vocab_size"]["tail"]["families"]), ["estimate", "high", "low"])

        recent = json.loads(self.profile("recent.json"))
        self.assertNotIn("focus_targets", recent)
        self.assertEqual(recent["newly_mastered"], [])  # first run is the baseline

        readme = self.profile("README.md")
        for needle in ("```mermaid", "xychart-beta", "最近测试日期：2026-11-05", "label%3Aprogress-report",
                       "CC BY 4.0", "数据来源"):
            self.assertIn(needle, readme)

        [r] = self.open_reports()
        fam = summary["vocab_size"]["families"]["estimate"]
        self.assertEqual(r["title"], "Progress Report 2026-11-05 · 约 %d 词族" % fam)
        j = self.report_json(r)
        self.assertEqual(sorted(j), ["band_counts", "date", "newly_mastered",
                                     "profile_commit", "schema_version", "vocab_size", "words_tsv_url"])
        self.assertEqual(j["schema_version"], 3)
        self.assertIn("https://github.com/someone/english-profile#readme", r["body"])
        self.assertEqual(j["vocab_size"]["estimate"], fam)
        self.assertIn("low", j["vocab_size"])
        self.assertIn("change", j["vocab_size"])
        self.assertEqual(j["words_tsv_url"],
                         "https://raw.githubusercontent.com/someone/english-profile/%s/words.tsv" % j["profile_commit"])
        self.assertEqual(j["band_counts"], summary["band_counts"])

    def test_readme_explains_the_report_on_its_own(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        readme = self.profile("README.md")
        sections = ["# 英语词汇量报告", "## 当前快照", "## 参数说明", "## 测量方法", "## 和常见测试怎么对照", "## 隐私"]
        self.assertEqual([s for s in sections if s in readme], sections)
        self.assertEqual(sorted(sections, key=readme.index), sections)
        summary = json.loads(self.profile("summary.json"))
        fam, core = summary["vocab_size"]["families"], summary["vocab_size"]["core"]["families"]
        self.assertIn("词族：约 **%d** 个（%d–%d），括号内为 95%% 区间" % (fam["estimate"], fam["low"], fam["high"]), readme)
        self.assertIn("前 14k 词族（BNC/COCA 1–14 级）**%d** 个" % core["estimate"], readme)
        self.assertIn("1k 96% · 2k 64%", readme)
        # Every published key and column is explained.
        for key in ("schema_version", "updated_at", "lexicon_version", "vocab_size.families", "vocab_size.lemmas",
                    "vocab_size.core", "vocab_size.tail", "band_counts", "level_mastery"):
            self.assertIn("| `%s` |" % key, readme)
        for col in self.profile("words.tsv").splitlines()[0].split("\t"):
            self.assertIn("| `%s` |" % col, readme)
        for needle in ("`history.json`", "`recent.json`", "95% 区间", "p` ≥ 0.9", "+ 2000",
                       "https://raw.githubusercontent.com/someone/english-profile/main/words.tsv",
                       "15–25 级", "全部 25,000 个词族", "伪词", "四选一", "扣除猜测", "考纲", "外推", "BNC/COCA",
                       "VST", "LexTALE", "testyourvocab", "lemma 数约为词族数的 2.0 倍",
                       "docs/research/07-accurate-vocab-measurement.md", "没有作答时间"):
            self.assertIn(needle, readme)
        # A standalone report: nothing about other tools or what to do with the data.
        for word in ("墨墨", "Grok", "推荐", "Recommendation", "agent", "Coverage", "复习"):
            self.assertNotIn(word, readme)

    def test_same_day_test_updates_next_day_test_creates_retired_sources_do_nothing(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        [first] = self.open_reports()

        # Same (Shanghai) day, second test: the same issue is updated, nothing new opens.
        self.append({"ts": "2026-11-05T13:00:00Z", "lemma": "weekly", "source": "test", "result": "yes"})
        self.run_pipeline("2026-11-05T13:05:00Z")
        [again] = self.open_reports()
        self.assertEqual(again["number"], first["number"])
        self.assertEqual(len(self.issues()), 1)

        # A sync with only a retired card-study source (old data) the next day: no new report.
        self.append({"ts": "2026-11-06T01:00:00Z", "lemma": "naturally", "source": "review", "result": "good"})
        before = self.issues()
        self.run_pipeline("2026-11-06T01:05:00Z")
        self.assertEqual(self.issues(), before)

        # Next day's first test: a new report, the previous one closed but kept.
        self.append({"ts": "2026-11-06T02:00:00Z", "lemma": "anywhere", "source": "test", "result": "yes"})
        self.run_pipeline("2026-11-06T02:05:00Z")
        [latest] = self.open_reports()
        self.assertNotEqual(latest["number"], first["number"])
        self.assertTrue(latest["title"].startswith("Progress Report 2026-11-06 · 约 "))
        closed = [i for i in self.issues() if i["number"] == first["number"]]
        self.assertEqual(closed[0]["state"], "closed")
        j = self.report_json(latest)
        self.assertIn("anywhere", j["newly_mastered"])
        self.assertLessEqual(len(j["newly_mastered"]), 30)
        self.assertGreater(j["vocab_size"]["change"], 0)

    def test_public_output_has_no_review_timeline_or_preferences(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        public = "".join(self.profile(n) for n in os.listdir(os.path.join(self.out, "english-profile")))
        public += json.dumps(self.issues(), ensure_ascii=False)
        with open(os.path.join(FIXTURE_OBSERVATIONS, "iphone", "2026-11.jsonl")) as f:
            stamps = [json.loads(l)["ts"] for l in f if l.startswith("{")]
        self.assertTrue(stamps)
        for ts in stamps:  # no Observation time of day, test or review
            self.assertNotIn(ts[:16], public)
        self.assertNotRegex(public, r"T\d{2}:\d{2}", "public files carry dates only")
        for word in ("review", "ease", "ivl", "wish", "想学", "偏好", "observations", "total", "model",
                     "focus_targets_from", "generated_at"):
            self.assertNotIn('"%s"' % word, public)
        history = json.loads(self.profile("history.json"))
        self.assertEqual(sorted(history[0]), ["date", "families", "high", "low"])

class TokenFailureTests(unittest.TestCase):
    """An invalid token must fail the workflow loudly, not silently skip publishing."""

    def test_missing_token_fails(self):
        with self.assertRaises(pp.TokenError):
            pp.GitHubIssues("someone", "")

    def test_rejected_token_fails_with_a_clear_message(self):
        import http.server
        import threading

        class Reject(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b'{"message":"Bad credentials"}')

            def log_message(self, *a):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Reject)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            store = pp.GitHubIssues("someone", "expired", api="http://127.0.0.1:%d" % server.server_port)
            with self.assertRaises(pp.TokenError) as cm:
                store.ensure_label()
            self.assertIn("PROFILE_TOKEN rejected", str(cm.exception))
        finally:
            server.shutdown()
            server.server_close()


class HelperTests(unittest.TestCase):
    def test_streak_counts_consecutive_test_days_up_to_yesterday(self):
        days = ["2026-11-01", "2026-11-03", "2026-11-04", "2026-11-05"]
        self.assertEqual(pp.streak(days, "2026-11-05"), 3)
        self.assertEqual(pp.streak(days, "2026-11-06"), 3)
        self.assertEqual(pp.streak(days, "2026-11-07"), 0)

    def test_retired_review_days_do_not_count(self):
        obs = [{"source": "test", "_t": pp.parse_ts("2026-11-04T01:00:00Z")},
               {"source": "review", "_t": pp.parse_ts("2026-11-05T01:00:00Z")}]
        self.assertEqual(pp.streak(pp.test_days(obs, pp.tzinfo(TZ)), "2026-11-05"), 1)


if __name__ == "__main__":
    unittest.main()
