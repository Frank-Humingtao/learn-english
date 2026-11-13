#!/usr/bin/env python3
"""Validates a Study Plan written by the word-plan skill.

usage: python3 scripts/word_plan/validate.py [--repo DIR] [--words PATH_OR_URL] [--now ISO] PLAN.json

Exit 0 when the plan is valid; exit 1 and one line per problem (`[code] message`) otherwise.
Rules:
  json           the file is valid JSON
  fields         schema_version 1, generated_at ISO 8601, daily_new int, new_words [{lemma, note}],
                 focus_targets [str], summary non-empty str, instruction str or null
  daily-new      1 <= daily_new <= 每日新词上限 (latest setting Observation)
  unknown-lemma  every new_words lemma is in words.tsv
  duplicate      no lemma twice
  has-card       no word that already has a card (incl. paused: 太简单 / Leech)
  mastered       no Mastered word
  wish-missing   every pending 想学 word is planned
  too-few        at least daily_new x 7 words, or the whole pool when the pool is smaller
  focus-targets  at most 50 focus_targets
  note-length    every note at most 40 characters
Confusable-word spacing is left to the prompt, not checked here.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from typing import List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Context, load_context, parse_ts  # noqa: E402

MAX_FOCUS = 50
MAX_NOTE = 40
DAYS = 7


@dataclass
class Problem:
    code: str
    message: str

    def __str__(self):
        return f"[{self.code}] {self.message}"


def validate(text: str, ctx: Context) -> List[Problem]:
    try:
        plan = json.loads(text)
    except ValueError as e:
        return [Problem("json", f"not valid JSON: {e}")]
    problems = check_fields(plan)
    if problems:
        return problems

    out: List[Problem] = []
    daily = plan["daily_new"]
    if not 1 <= daily <= ctx.daily_new_limit:
        out.append(Problem("daily-new", f"daily_new {daily} must be between 1 and the limit {ctx.daily_new_limit}"))

    lemmas = [w["lemma"] for w in plan["new_words"]]
    seen = set()
    for i, w in enumerate(plan["new_words"]):
        lemma, where = w["lemma"], f"new_words[{i}] {w['lemma']!r}"
        if lemma in seen:
            out.append(Problem("duplicate", f"{where} appears more than once"))
        seen.add(lemma)
        if lemma not in ctx.words:
            out.append(Problem("unknown-lemma", f"{where} is not in words.tsv"))
        elif lemma in ctx.cards:
            out.append(Problem("has-card", f"{where} already has a card"))
        elif ctx.is_mastered(lemma):
            out.append(Problem("mastered", f"{where} is Mastered"))
        if len(w["note"]) > MAX_NOTE:
            out.append(Problem("note-length", f"{where} note has {len(w['note'])} characters (max {MAX_NOTE})"))

    missing = [w for w in ctx.pending_wishes if w not in seen]
    if missing:
        out.append(Problem("wish-missing", f"想学 words not planned: {', '.join(missing)}"))

    pool = ctx.pool
    planned = len([l for l in set(lemmas) if ctx.eligible(l)])
    needed = min(daily * DAYS, len(pool))
    if planned < needed:
        out.append(Problem("too-few", f"{planned} plannable words; need {needed} "
                                      f"(daily_new {daily} x {DAYS}, pool {len(pool)})"))

    if len(plan["focus_targets"]) > MAX_FOCUS:
        out.append(Problem("focus-targets", f"{len(plan['focus_targets'])} focus_targets (max {MAX_FOCUS})"))
    return out


def check_fields(plan) -> List[Problem]:
    def bad(msg):
        return [Problem("fields", msg)]

    if not isinstance(plan, dict):
        return bad("top level must be an object")
    required = ["schema_version", "generated_at", "daily_new", "new_words", "focus_targets", "summary", "instruction"]
    missing = [k for k in required if k not in plan]
    if missing:
        return bad(f"missing fields: {', '.join(missing)}")
    if plan["schema_version"] != 1:
        return bad("schema_version must be 1")
    if parse_ts(str(plan["generated_at"])) is None:
        return bad("generated_at must be ISO 8601 with a time zone")
    if type(plan["daily_new"]) is not int:
        return bad("daily_new must be an integer")
    nw = plan["new_words"]
    if not isinstance(nw, list) or not all(
            isinstance(w, dict) and isinstance(w.get("lemma"), str) and isinstance(w.get("note"), str) for w in nw):
        return bad("new_words must be a list of {\"lemma\": str, \"note\": str}")
    if not isinstance(plan["focus_targets"], list) or not all(isinstance(x, str) for x in plan["focus_targets"]):
        return bad("focus_targets must be a list of strings")
    if not isinstance(plan["summary"], str) or not plan["summary"].strip():
        return bad("summary must be a non-empty string")
    if plan["instruction"] is not None and not isinstance(plan["instruction"], str):
        return bad("instruction must be a string or null")
    return []


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plan")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--words", help="words.tsv path or URL (default: english-profile of origin's owner)")
    ap.add_argument("--now", help="ISO 8601 time to evaluate at (default: now)")
    args = ap.parse_args(argv)
    ctx = load_context(args.repo, args.words, args.now)
    with open(args.plan, encoding="utf-8") as f:
        problems = validate(f.read(), ctx)
    for p in problems:
        print(p)
    if not problems:
        print("OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
