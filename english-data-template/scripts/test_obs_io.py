"""Tests for obs_io.py. Run: python3 -I english-data-template/scripts/test_obs_io.py"""
import datetime as dt
import json
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import obs_io  # noqa: E402

# Shared with EnglishCore's CardReplayFixtureTests: Swift and Python must both produce expected.json.
CARD_REPLAY = os.path.join(HERE, "..", "..", "EnglishCore", "Fixtures", "card-replay")


@unittest.skipUnless(os.path.isdir(CARD_REPLAY), "runs inside the learn-english code repo")
class CardReplayFixtureTests(unittest.TestCase):
    def test_replay_matches_the_shared_fixture(self):
        with open(os.path.join(CARD_REPLAY, "expected.json"), encoding="utf-8") as f:
            expected = json.load(f)
        tmp = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(tmp, "observations", "iphone"))
            shutil.copy(os.path.join(CARD_REPLAY, "observations.jsonl"),
                        os.path.join(tmp, "observations", "iphone", "2026-11.jsonl"))
            observations = obs_io.load_observations(tmp)
        finally:
            shutil.rmtree(tmp)
        cards = obs_io.replay_cards(observations, obs_io.parse_ts(expected["as_of"]),
                                    lapses=expected["leech_lapses"],
                                    cooldown=dt.timedelta(days=expected["leech_cooldown_days"]))

        def ts(t):
            return obs_io.iso_utc(t) if t else None

        got = [{"lemma": c.lemma, "active": c.active, "paused": c.paused, "lapses": c.lapses,
                "first_ease": c.first_ease, "leech_since": ts(c.leech_since), "reset_at": ts(c.reset_at),
                "reintroduced": c.reintroduced} for c in sorted(cards.values(), key=lambda c: c.lemma)]
        self.assertEqual(got, expected["cards"])


class ReadingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, rel, text):
        path = os.path.join(self.tmp, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def test_malformed_lines_and_timestamps_are_skipped_and_the_rest_sorted(self):
        self.write("observations/iphone/2026-11.jsonl",
                   '{"ts":"2026-11-02T00:00:00Z","lemma":"b","source":"test","result":"yes"}\n'
                   "not json\n[1]\n"
                   '{"ts":"yesterday","lemma":"x","source":"test","result":"yes"}\n'
                   '{"ts":"2026-11-01T00:00:00.5+08:00","lemma":"a","source":"review","result":"good"}\n')
        self.assertEqual([o["lemma"] for o in obs_io.load_observations(self.tmp)], ["a", "b"])

    def test_a_broken_newest_plan_falls_back_to_the_previous_one(self):
        self.write("plan/2026-11-08.json", '{"daily_new": 5}')
        self.write("plan/2026-11-09.json", "{broken")
        self.write("plan/notes.json", "{}")
        self.assertEqual(obs_io.latest_plan(self.tmp), ("plan/2026-11-08.json", {"daily_new": 5}))
        self.assertEqual(obs_io.latest_plan(os.path.join(self.tmp, "none")), (None, None))

    def test_rating_comes_from_the_result_else_the_revlog_ease(self):
        self.assertEqual(obs_io.rating_of({"result": "hard", "review": {"ease": 4}}), 2)
        self.assertEqual(obs_io.rating_of({"result": "?", "review": {"ease": 3}}), 3)
        self.assertIsNone(obs_io.rating_of({"result": "maybe"}))

    def test_streak_counts_test_and_review_days(self):
        utc = dt.timezone.utc
        obs = [{"source": s, "_t": dt.datetime(2026, 11, d, 9, tzinfo=utc)}
               for s, d in (("test", 5), ("review", 6), ("verify", 7), ("wish", 8), ("setting", 9))]
        days = obs_io.study_days(obs, utc)
        self.assertEqual(days, ["2026-11-05", "2026-11-06", "2026-11-07"])
        self.assertEqual(obs_io.streak(days, "2026-11-08"), 3)
        self.assertEqual(obs_io.streak(days, "2026-11-09"), 0)


if __name__ == "__main__":
    unittest.main()
