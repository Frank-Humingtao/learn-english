"""Tests for fsrs_train.py.

Run: python3 -I english-data-template/scripts/test_fsrs_train.py
The decision tests need only the standard library. The training test needs the pinned
optimizer (`pip install -r english-data-template/scripts/requirements-fsrs.txt`) and is
skipped without it.
"""
import datetime as dt
import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fsrs_train as ft  # noqa: E402

try:
    import fsrs  # noqa: F401
    HAVE_FSRS = True
except ImportError:
    HAVE_FSRS = False

NOW = dt.datetime(2026, 11, 13, 4, 0, tzinfo=dt.timezone.utc)


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (t.microsecond // 1000)


def review(t, lemma, ease, rt_ms=1500):
    result = {1: "again", 2: "hard", 3: "good", 4: "easy"}[ease]
    return {"lemma": lemma, "result": result, "rt_ms": rt_ms, "session": "s", "source": "review", "ts": iso(t),
            "review": {"ease": ease, "ivl": 1, "last_ivl": 0, "type": 1, "time": rt_ms}}


def noise(t, i):
    """Observations that are not reviews: tests, spot checks, wishes, settings, relearn."""
    return [
        {"lemma": "w%d" % i, "result": "yes", "source": "test", "ts": iso(t)},
        {"lemma": "w%d" % i, "result": "no", "source": "spotcheck", "ts": iso(t)},
        {"lemma": "w%d" % i, "result": "add", "source": "wish", "ts": iso(t)},
        {"lemma": "w%d" % i, "result": "reset", "source": "relearn", "ts": iso(t)},
        {"lemma": "daily_new_limit", "result": "12", "source": "setting", "ts": iso(t)},
    ]


def write_repo(root, observations):
    """Spread Observations over observations/<device>/YYYY-MM.jsonl like the App does."""
    files = {}
    for o in observations:
        files.setdefault(os.path.join(root, "observations", "iphone", o["ts"][:7] + ".jsonl"), []).append(o)
    for path, rows in files.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            for o in sorted(rows, key=lambda o: o["ts"]):
                f.write(json.dumps(o, sort_keys=True, separators=(",", ":")) + "\n")


def simulated_learner(cards=160, days=150, seed=7):
    """A deterministic learner whose memory decays faster than FSRS defaults assume.

    Each card is first seen on a random day, then reviewed whenever it is due; recall is drawn
    from a forgetting curve with half the default stability, so trained weights must move.
    """
    rng = random.Random(seed)
    start = NOW - dt.timedelta(days=days)
    out = []
    for c in range(cards):
        lemma = "word%03d" % c
        t = start + dt.timedelta(days=rng.randrange(0, 30), hours=rng.randrange(0, 12))
        stability = None
        last = None
        while t < NOW:
            if stability is None:
                ease = rng.choice([1, 3, 3, 3, 4])
                stability = {1: 0.3, 3: 1.2, 4: 4.0}[ease]
            else:
                elapsed = (t - last).total_seconds() / 86400
                recall = (1 + elapsed / (9 * stability)) ** -1
                if rng.random() < recall:
                    ease = 4 if rng.random() < 0.1 else (2 if rng.random() < 0.15 else 3)
                    stability *= 1.8 if ease == 2 else (3.5 if ease == 4 else 2.5)
                else:
                    ease = 1
                    stability = max(0.3, stability * 0.3)
            out.append(review(t, lemma, ease, rt_ms=rng.randrange(800, 6000)))
            last = t
            t = t + dt.timedelta(days=max(1, round(stability * 1.5)), minutes=rng.randrange(0, 120))
    return out


class LoadReviewsTests(unittest.TestCase):
    def test_only_review_observations_are_loaded(self):
        t = NOW - dt.timedelta(days=3)
        rows = [review(t, "apple", 3), review(t + dt.timedelta(days=1), "apple", 1)] + noise(t, 1)
        with tempfile.TemporaryDirectory() as root:
            write_repo(root, rows)
            reviews = ft.load_reviews(root)
        self.assertEqual([(r["lemma"], r["review"]["ease"]) for r in reviews], [("apple", 3), ("apple", 1)])

    def test_review_logs_group_by_lemma_and_take_the_rating_from_the_revlog(self):
        t = NOW - dt.timedelta(days=3)
        rows = [review(t, "apple", 3, rt_ms=900), review(t, "pear", 4), review(t + dt.timedelta(days=2), "apple", 2)]
        logs = ft.review_log_rows(rows)
        self.assertEqual([(l.card_id, l.rating, l.review_duration) for l in logs],
                         [(1, 3, 900), (2, 4, 1500), (1, 2, 1500)])
        self.assertEqual(logs[2].review_datetime, t + dt.timedelta(days=2))

    def test_a_review_without_revlog_falls_back_to_the_result_string(self):
        row = {"lemma": "apple", "result": "hard", "source": "review", "ts": "2026-11-01T00:00:00Z"}
        self.assertEqual(ft.review_log_rows([row])[0].rating, 2)


class DecideTests(unittest.TestCase):
    def test_too_few_reviews_skips_without_error(self):
        d = ft.decide(review_count=ft.MIN_REVIEWS - 1, previous=None)
        self.assertFalse(d.train)
        self.assertIn("%d" % (ft.MIN_REVIEWS - 1), d.reason)

    def test_enough_reviews_and_no_params_yet_trains(self):
        self.assertTrue(ft.decide(review_count=ft.MIN_REVIEWS, previous=None).train)

    def test_retrains_only_after_enough_new_reviews(self):
        previous = {"w": [0.1] * 21, "review_count": 1000}
        self.assertFalse(ft.decide(review_count=1000 + ft.RETRAIN_EVERY - 1, previous=previous).train)
        self.assertTrue(ft.decide(review_count=1000 + ft.RETRAIN_EVERY, previous=previous).train)

    def test_unreadable_previous_params_are_retrained(self):
        self.assertTrue(ft.decide(review_count=ft.MIN_REVIEWS, previous={"w": "junk"}).train)

    def test_check_command_below_threshold_writes_train_false_and_exits_zero(self):
        t = NOW - dt.timedelta(days=10)
        rows = [review(t + dt.timedelta(days=i), "apple", 3) for i in range(5)] + noise(t, 1)
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as tmp:
            write_repo(root, rows)
            out = os.path.join(tmp, "github_output")
            code = ft.main(["check", "--data", root, "--github-output", out])
            with open(out) as f:
                written = f.read()
            self.assertFalse(os.path.exists(os.path.join(root, ft.PARAMS_PATH)))
        self.assertEqual(code, 0)
        self.assertIn("train=false", written)
        self.assertIn("review_count=5", written)

    def test_train_command_below_threshold_is_a_no_op(self):
        t = NOW - dt.timedelta(days=10)
        with tempfile.TemporaryDirectory() as root:
            write_repo(root, [review(t, "apple", 3)])
            code = ft.main(["train", "--data", root])
            self.assertEqual(code, 0)
            self.assertFalse(os.path.exists(os.path.join(root, ft.PARAMS_PATH)))


@unittest.skipUnless(HAVE_FSRS, "py-fsrs optimizer not installed (requirements-fsrs.txt)")
class TrainTests(unittest.TestCase):
    def test_training_on_fixture_reviews_writes_a_params_file(self):
        reviews = simulated_learner()
        self.assertGreaterEqual(len(reviews), ft.MIN_REVIEWS)
        rows = reviews + [o for i in range(40) for o in noise(NOW - dt.timedelta(days=i + 1), i)]
        with tempfile.TemporaryDirectory() as root:
            write_repo(root, rows)
            code = ft.main(["train", "--data", root, "--now", "2026-11-13T04:00:00Z"])
            with open(os.path.join(root, ft.PARAMS_PATH)) as f:
                params = json.load(f)
        self.assertEqual(code, 0)
        self.assertEqual(params["format"], 1)
        self.assertEqual(params["algorithm"], "FSRS-6")
        self.assertEqual(len(params["w"]), 21)
        self.assertEqual(params["decay"], params["w"][20])
        self.assertEqual(params["review_count"], len(reviews))  # noise Observations are not counted
        self.assertEqual(params["trained_at"], "2026-11-13T04:00:00Z")
        self.assertEqual(params["optimizer"], "py-fsrs " + ft.PINNED_FSRS)
        from fsrs.scheduler import DEFAULT_PARAMETERS
        self.assertNotEqual(params["w"], [round(x, 6) for x in DEFAULT_PARAMETERS])
        # The learner forgets faster than the defaults assume: initial "good" stability drops.
        self.assertLess(params["w"][2], DEFAULT_PARAMETERS[2])

    def test_non_review_observations_do_not_change_the_result(self):
        reviews = simulated_learner(cards=120, seed=11)
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            write_repo(a, reviews)
            write_repo(b, reviews + [o for i in range(30) for o in noise(NOW - dt.timedelta(days=i + 1), i)])
            ft.main(["train", "--data", a, "--now", "2026-11-13T04:00:00Z"])
            ft.main(["train", "--data", b, "--now", "2026-11-13T04:00:00Z"])
            with open(os.path.join(a, ft.PARAMS_PATH)) as fa, open(os.path.join(b, ft.PARAMS_PATH)) as fb:
                self.assertEqual(json.load(fa), json.load(fb))


if __name__ == "__main__":
    unittest.main()
