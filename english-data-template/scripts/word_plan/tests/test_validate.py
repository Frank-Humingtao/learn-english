"""Validator rules, each with a passing and a failing fixture.

Fixture learner (tests/fixtures): cards on abandon, absorb (Leech), accurate (首评太简单),
acquire, allocate; Mastered: the, house, apple; pending 想学: ambiguous (abandon already has a
card, the is Mastered); daily limit 6; 23 eligible Target words without a card.
"""
import copy
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import validate  # noqa: E402
from common import load_context  # noqa: E402

FIXTURES = os.path.join(HERE, "fixtures")
REPO = os.path.join(FIXTURES, "repo")
WORDS = os.path.join(FIXTURES, "words.tsv")
NOW = "2026-11-13T07:30:00+08:00"

ELIGIBLE = ("adapt adequate advocate affect effect analyse anticipate apparent arbitrary assert "
            "assess assume attain authority bias brief capable cease coherent commence compile concede").split()


def valid_plan():
    words = ["ambiguous"] + ELIGIBLE[:13]  # 14 = daily_new 2 x 7
    return {
        "schema_version": 1,
        "generated_at": "2026-11-13T07:30:00+08:00",
        "daily_new": 2,
        "new_words": [{"lemma": w, "note": "测试答错且高频"} for w in words],
        "focus_targets": ["allocate", "abandon", "ambiguous"],
        "summary": "本期排 14 词，每天 2 个。",
        "instruction": None,
    }


class ValidatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ctx = load_context(REPO, WORDS, NOW)

    def codes(self, plan):
        text = plan if isinstance(plan, str) else json.dumps(plan, ensure_ascii=False)
        return {e.code for e in validate.validate(text, self.ctx)}

    def assertPasses(self, plan):
        self.assertEqual(self.codes(plan), set())

    def assertFails(self, plan, code):
        self.assertIn(code, self.codes(plan))

    # JSON valid, fields present
    def test_valid_plan_passes(self):
        self.assertPasses(valid_plan())

    def test_invalid_json_fails(self):
        self.assertFails('{"schema_version": 1,', "json")

    def test_missing_field_fails(self):
        p = valid_plan()
        del p["focus_targets"]
        self.assertFails(p, "fields")

    def test_wrong_field_type_fails(self):
        p = valid_plan()
        p["new_words"][0] = "ambiguous"
        self.assertFails(p, "fields")

    def test_instruction_may_be_a_string(self):
        p = valid_plan()
        p["instruction"] = "这周出差，少排点"
        self.assertPasses(p)

    def test_empty_summary_fails(self):
        p = valid_plan()
        p["summary"] = " "
        self.assertFails(p, "fields")

    # daily_new within the limit
    def test_daily_new_within_limit_passes(self):
        p = valid_plan()
        p["daily_new"] = 3
        p["new_words"] += [{"lemma": w, "note": ""} for w in ELIGIBLE[13:20]]  # 21 = 3 x 7
        self.assertPasses(p)

    def test_daily_new_above_limit_fails(self):
        p = valid_plan()
        p["daily_new"] = 7
        self.assertFails(p, "daily-new")

    def test_daily_new_zero_fails(self):
        p = valid_plan()
        p["daily_new"] = 0
        self.assertFails(p, "daily-new")

    # lemma in the word list
    def test_distant_word_in_lexicon_passes(self):
        p = valid_plan()
        p["new_words"].append({"lemma": "obfuscate", "note": "学习者要求"})
        self.assertPasses(p)

    def test_unknown_lemma_fails(self):
        p = valid_plan()
        p["new_words"].append({"lemma": "flibbertigibbet", "note": ""})
        self.assertFails(p, "unknown-lemma")

    # no duplicates
    def test_duplicate_lemma_fails(self):
        p = valid_plan()
        p["new_words"].append(copy.deepcopy(p["new_words"][3]))
        self.assertFails(p, "duplicate")

    # not a word that already has a card (incl. 首评太简单 and Leech)
    def test_word_with_card_fails(self):
        for lemma in ["abandon", "accurate", "absorb"]:
            p = valid_plan()
            p["new_words"].append({"lemma": lemma, "note": ""})
            self.assertFails(p, "has-card")

    # not Mastered
    def test_mastered_word_fails(self):
        p = valid_plan()
        p["new_words"].append({"lemma": "house", "note": ""})
        self.assertFails(p, "mastered")

    # every pending 想学 word is planned
    def test_missing_wish_fails(self):
        p = valid_plan()
        p["new_words"][0] = {"lemma": ELIGIBLE[13], "note": ""}
        self.assertFails(p, "wish-missing")

    # at least daily_new x 7 words, unless the pool is short
    def test_too_few_words_fails(self):
        p = valid_plan()
        p["new_words"].pop()
        self.assertFails(p, "too-few")

    def test_short_pool_whole_pool_passes(self):
        p = valid_plan()
        p["daily_new"] = 6  # needs 42, only 23 eligible words exist
        p["new_words"] = [{"lemma": w, "note": ""} for w in ["ambiguous"] + ELIGIBLE]
        self.assertPasses(p)

    def test_short_pool_partial_fails(self):
        p = valid_plan()
        p["daily_new"] = 6
        p["new_words"] = [{"lemma": w, "note": ""} for w in ["ambiguous"] + ELIGIBLE[:-1]]
        self.assertFails(p, "too-few")

    # focus_targets <= 50
    def test_fifty_focus_targets_passes(self):
        p = valid_plan()
        p["focus_targets"] = (ELIGIBLE * 3)[:50]
        self.assertPasses(p)

    def test_fifty_one_focus_targets_fails(self):
        p = valid_plan()
        p["focus_targets"] = (ELIGIBLE * 3)[:51]
        self.assertFails(p, "focus-targets")

    # note <= 40 characters
    def test_forty_char_note_passes(self):
        p = valid_plan()
        p["new_words"][1]["note"] = "易" * 40
        self.assertPasses(p)

    def test_forty_one_char_note_fails(self):
        p = valid_plan()
        p["new_words"][1]["note"] = "易" * 41
        self.assertFails(p, "note-length")


class CommandLineTests(unittest.TestCase):
    def run_cli(self, plan, tmp_name):
        path = os.path.join(FIXTURES, tmp_name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(plan, f, ensure_ascii=False)
        self.addCleanup(os.remove, path)
        script = os.path.join(os.path.dirname(HERE), "validate.py")
        return subprocess.run([sys.executable, script, "--repo", REPO, "--words", WORDS, "--now", NOW, path],
                              capture_output=True, text=True)

    def test_exit_zero_when_valid(self):
        r = self.run_cli(valid_plan(), "tmp-valid.json")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_exit_one_with_readable_errors(self):
        p = valid_plan()
        p["new_words"].append({"lemma": "house", "note": "易" * 41})
        r = self.run_cli(p, "tmp-invalid.json")
        self.assertEqual(r.returncode, 1)
        self.assertIn("house", r.stdout)
        self.assertIn("[mastered]", r.stdout)
        self.assertIn("[note-length]", r.stdout)


if __name__ == "__main__":
    unittest.main()
