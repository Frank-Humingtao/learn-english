"""Tests for obs_io.py. Run: python3 -I english-data-template/scripts/test_obs_io.py"""
import datetime as dt
import os
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import obs_io  # noqa: E402

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

    def test_streak_counts_test_days_only(self):
        utc = dt.timezone.utc
        obs = [{"source": s, "_t": dt.datetime(2026, 11, d, 9, tzinfo=utc)}
               for s, d in (("test", 5), ("spotcheck", 6), ("verify", 7), ("review", 8), ("wish", 9))]
        days = obs_io.test_days(obs, utc)
        self.assertEqual(days, ["2026-11-05", "2026-11-06", "2026-11-07"])
        self.assertEqual(obs_io.streak(days, "2026-11-08"), 3)
        self.assertEqual(obs_io.streak(days, "2026-11-09"), 0)


if __name__ == "__main__":
    unittest.main()
