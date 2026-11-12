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
FIXTURE_REPO = os.path.join(HERE, "fixtures", "english-data")
FAKE_ENGINE = os.path.join(HERE, "fixtures", "fake_engine.py")


def obs(ts, source="test", lemma="apple", result="yes"):
    return {"ts": ts, "lemma": lemma, "source": source, "result": result}


def report(number, date, state="open", last_test_ts=None):
    body = "summary"
    if last_test_ts:
        body += "\n" + pp.state_marker({"last_test_ts": last_test_ts})
    return {"number": number, "title": "Progress Report %s · 约 100 词族" % date, "state": state, "body": body}


class DecideReportTests(unittest.TestCase):
    def test_first_test_ever_creates_a_report(self):
        d = pp.decide_report([obs("2026-11-12T01:00:00Z")], [], TZ)
        self.assertEqual(d.action, "create")
        self.assertEqual(d.date, "2026-11-12")
        self.assertEqual(d.close, [])

    def test_first_test_of_a_new_day_creates_and_closes_the_previous_report(self):
        observations = [obs("2026-11-11T01:00:00Z"), obs("2026-11-12T01:00:00Z")]
        reports = [report(7, "2026-11-11", last_test_ts="2026-11-11T01:00:00Z"),
                   report(3, "2026-11-09", state="closed", last_test_ts="2026-11-09T01:00:00Z")]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.date, d.close), ("create", "2026-11-12", [7]))
        self.assertEqual(d.last_test_ts, "2026-11-12T01:00:00Z")

    def test_second_test_on_the_same_day_updates_that_days_report(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T09:30:00.250Z")]
        reports = [report(8, "2026-11-12", last_test_ts="2026-11-12T01:00:00Z")]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.date, d.target, d.close), ("update", "2026-11-12", 8, []))
        self.assertEqual(d.last_test_ts, "2026-11-12T09:30:00Z")

    def test_review_only_sync_does_nothing(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-13T02:00:00Z", source="review", result="good"),
                        obs("2026-11-13T02:01:00Z", source="verify", result="correct")]
        reports = [report(8, "2026-11-12", last_test_ts="2026-11-12T01:00:00Z")]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.close), ("none", []))

    def test_review_only_history_never_creates_a_first_report(self):
        d = pp.decide_report([obs("2026-11-12T01:00:00Z", source="review", result="good")], [], TZ)
        self.assertEqual(d.action, "none")

    def test_day_boundary_follows_the_learners_time_zone(self):
        # 2026-11-12T17:00Z is already 11-13 01:00 in Shanghai: a new day, so a new report.
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T17:00:00Z")]
        reports = [report(8, "2026-11-12", last_test_ts="2026-11-12T01:00:00Z")]
        self.assertEqual(pp.decide_report(observations, reports, TZ).action, "create")
        self.assertEqual(pp.decide_report(observations, reports, "UTC").action, "update")

    def test_only_one_report_stays_open(self):
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-12T05:00:00Z")]
        reports = [report(8, "2026-11-12", last_test_ts="2026-11-12T01:00:00Z"), report(5, "2026-11-10"),
                   report(2, "2026-11-01")]
        d = pp.decide_report(observations, reports, TZ)
        self.assertEqual((d.action, d.target, sorted(d.close)), ("update", 8, [2, 5]))
        # Even a review-only sync repairs a second open report left behind by a failed run.
        d2 = pp.decide_report([obs("2026-11-12T01:00:00Z")], reports, TZ)
        self.assertEqual((d2.action, sorted(d2.close)), ("none", [2, 5]))

    def test_late_sync_of_an_older_test_does_not_reopen_the_past(self):
        # A test done offline on 11-11 arrives after the 11-12 report exists.
        observations = [obs("2026-11-12T01:00:00Z"), obs("2026-11-11T03:00:00Z")]
        reports = [report(8, "2026-11-12", last_test_ts="2026-11-12T01:00:00Z")]
        self.assertEqual(pp.decide_report(observations, reports, TZ).action, "none")


class DryRunPipelineTests(unittest.TestCase):
    """Whole pipeline against a fixture english-data repo; GitHub replaced by a local issues file."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.data = os.path.join(self.tmp, "english-data")
        shutil.copytree(FIXTURE_REPO, self.data)
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
        self.assertEqual(self.profile("words.tsv").splitlines()[0], "lemma\tband\tp\trank")

        recent = json.loads(self.profile("recent.json"))
        self.assertEqual(recent["focus_targets"], ["additional", "anybody", "naturally", "anywhere", "presentation"])
        self.assertEqual(recent["newly_mastered"], [])  # first run is the baseline

        readme = self.profile("README.md")
        for needle in ("```mermaid", "xychart-beta", "已掌握", "近一周新掌握的词", "最近测试日期：2026-11-05",
                       "连续测试天数", "label%3Aprogress-report", "CC BY 4.0", "数据来源"):
            self.assertIn(needle, readme)

        [r] = self.open_reports()
        fam = summary["vocab_size"]["families"]["estimate"]
        self.assertEqual(r["title"], "Progress Report 2026-11-05 · 约 %d 词族" % fam)
        j = self.report_json(r)
        self.assertEqual(sorted(j), ["band_counts", "focus_targets", "generated_at", "newly_mastered",
                                     "profile_commit", "schema_version", "vocab_size", "words_tsv_url"])
        self.assertEqual(j["vocab_size"]["estimate"], fam)
        self.assertIn("low", j["vocab_size"])
        self.assertIn("change", j["vocab_size"])
        self.assertEqual(j["words_tsv_url"],
                         "https://raw.githubusercontent.com/someone/english-profile/%s/words.tsv" % j["profile_commit"])
        self.assertEqual(j["band_counts"], summary["band_counts"])

    def test_same_day_test_updates_next_day_test_creates_review_only_does_nothing(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        [first] = self.open_reports()

        # Same (Shanghai) day, second test: the same issue is updated, nothing new opens.
        self.append({"ts": "2026-11-05T13:00:00Z", "lemma": "weekly", "source": "test", "result": "yes"})
        self.run_pipeline("2026-11-05T13:05:00Z")
        [again] = self.open_reports()
        self.assertEqual(again["number"], first["number"])
        self.assertEqual(len(self.issues()), 1)

        # Review-only sync the next day: no new report, nothing edited.
        self.append({"ts": "2026-11-06T01:00:00Z", "lemma": "naturally", "source": "review", "result": "good"})
        before = self.issues()
        self.run_pipeline("2026-11-06T01:05:00Z")
        self.assertEqual(self.issues(), before)
        self.assertIn("naturally", [e["lemma"] for e in json.loads(self.profile("recent.json"))["newly_mastered"]])

        # Next day's first test: a new report, the previous one closed but kept.
        self.append({"ts": "2026-11-06T02:00:00Z", "lemma": "anywhere", "source": "test", "result": "yes"})
        self.run_pipeline("2026-11-06T02:05:00Z")
        [latest] = self.open_reports()
        self.assertNotEqual(latest["number"], first["number"])
        self.assertTrue(latest["title"].startswith("Progress Report 2026-11-06 · 约 "))
        closed = [i for i in self.issues() if i["number"] == first["number"]]
        self.assertEqual(closed[0]["state"], "closed")
        j = self.report_json(latest)
        self.assertEqual(set(j["newly_mastered"][:2]), {"anywhere", "naturally"})
        self.assertLessEqual(len(j["newly_mastered"]), 30)
        self.assertGreater(j["vocab_size"]["change"], 0)

    def test_public_output_has_no_review_timeline_or_preferences(self):
        self.run_pipeline("2026-11-05T12:00:00Z")
        public = "".join(self.profile(n) for n in os.listdir(os.path.join(self.out, "english-profile")))
        public += json.dumps(self.issues(), ensure_ascii=False)
        with open(os.path.join(FIXTURE_REPO, "observations", "iphone", "2026-11.jsonl")) as f:
            review_ts = [json.loads(l)["ts"] for l in f if '"review"' in l]
        self.assertTrue(review_ts)
        for ts in review_ts:
            self.assertNotIn(ts, public)
            self.assertNotIn(ts[:16], public)
        for word in ("review", "ease", "ivl", "wish", "想学", "偏好"):
            self.assertNotIn('"%s"' % word, public)

    def test_focus_targets_empty_without_a_study_plan(self):
        shutil.rmtree(os.path.join(self.data, "plan"))
        self.run_pipeline("2026-11-05T12:00:00Z")
        self.assertEqual(json.loads(self.profile("recent.json"))["focus_targets"], [])
        self.assertEqual(self.report_json(self.open_reports()[0])["focus_targets"], [])


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


if __name__ == "__main__":
    unittest.main()
