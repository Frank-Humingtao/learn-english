"""The summary Word Planning reads instead of the raw Observations (same fixture as test_validate)."""
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import summary  # noqa: E402
from common import load_context  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures")
REPO = os.path.join(FIXTURES, "repo")
WORDS = os.path.join(FIXTURES, "words.tsv")
NOW = "2026-11-13T07:30:00+08:00"


class SummaryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = summary.build(load_context(REPO, WORDS, NOW))

    def test_settings_and_wishes(self):
        self.assertEqual(self.s["daily_new_limit"], 6)
        self.assertEqual(self.s["pending_wishes"], ["ambiguous"])
        self.assertEqual(self.s["skipped_wishes"], ["the"])

    def test_candidates_are_bucketed_wish_then_fuzzy_then_target(self):
        c = self.s["candidates"]
        self.assertEqual([x["lemma"] for x in c["wish"]], ["ambiguous"])
        fuzzy = [x["lemma"] for x in c["fuzzy"]]
        # Target, no card, 0.3 <= P <= 0.7, by frequency rank
        self.assertEqual(fuzzy, ["adapt", "adequate", "affect", "effect", "analyse", "anticipate", "apparent",
                                 "assert", "assess", "bias", "commence", "compile"])
        target = [x["lemma"] for x in c["target"]]
        self.assertEqual(target, ["advocate", "arbitrary", "assume", "attain", "authority", "brief", "capable",
                                  "cease", "coherent", "concede"])

    def test_candidate_details(self):
        assess = next(x for x in self.s["candidates"]["fuzzy"] if x["lemma"] == "assess")
        self.assertEqual(assess, {"lemma": "assess", "p": 0.69, "rank": 260,
                                  "tests": "11-01 test:no, 11-01 verify:wrong"})

    def test_candidate_pool_is_capped(self):
        s = summary.build(load_context(REPO, WORDS, NOW), max_candidates=5)
        c = s["candidates"]
        self.assertEqual([x["lemma"] for x in c["wish"] + c["fuzzy"] + c["target"]],
                         ["ambiguous", "adapt", "adequate", "affect", "effect"])
        self.assertEqual(s["pool_size"], 23)

    def test_due_reviews_next_seven_days(self):
        due = self.s["due_next_7_days"]
        self.assertEqual(due["by_day"], {"2026-11-13": 1, "2026-11-14": 1, "2026-11-15": 1, "2026-11-16": 0,
                                         "2026-11-17": 0, "2026-11-18": 0, "2026-11-19": 0})
        self.assertEqual(due["total"], 3)

    def test_leeches(self):
        self.assertEqual(self.s["leeches"], [{"lemma": "absorb", "lapses": 8, "since": "2026-11-11"}])

    def test_active_cards_struggling_first(self):
        cards = self.s["active_cards"]
        self.assertEqual([c["lemma"] for c in cards], ["allocate", "abandon", "acquire"])
        self.assertEqual(cards[0]["ratings"], [1, 1, 0, 0])
        self.assertEqual(cards[0]["due"], "2026-11-07")

    def test_previous_plan_remaining(self):
        prev = self.s["previous_plan"]
        self.assertEqual(prev["path"], "plan/2026-11-10.json")
        self.assertEqual(prev["daily_new"], 2)
        self.assertEqual(prev["remaining"], ["adapt", "adequate", "advocate"])
        self.assertEqual(prev["days_left"], 1.5)

    def test_command_line_prints_json(self):
        script = os.path.join(os.path.dirname(HERE), "summary.py")
        r = subprocess.run([sys.executable, script, "--repo", REPO, "--words", WORDS, "--now", NOW],
                           capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(r.stdout)["daily_new_limit"], 6)


if __name__ == "__main__":
    unittest.main()
