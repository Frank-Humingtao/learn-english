#!/usr/bin/env python3
"""Condenses everything Word Planning needs into one small JSON document.

usage: python3 scripts/word_plan/summary.py [--repo DIR] [--words PATH_OR_URL] [--now ISO] [--max-candidates N] [--out FILE]

Reads all Observations, the latest words.tsv, the previous Study Plan, settings and 想学 records;
prints (or writes to --out) JSON with:
  now                local time with offset; use it as the plan's generated_at, its date as the file name
  daily_new_limit    每日新词上限 (latest setting Observation, default 10)
  pending_wishes     想学 words without a card (must all be planned); skipped_wishes: Mastered / unknown ones
  pool_size          words that may be planned (pending 想学 + Target words without a card)
  candidates         ~400 pre-bucketed words: wish, fuzzy (Target, 0.3 <= P <= 0.7), target (other Target);
                     each by frequency rank with P, rank and the latest test answers
  active_cards       unpaused cards, struggling first: all-time and 14-day [again, hard, good, easy] counts
  due_next_7_days    reviews due per local day (overdue counted today)
  leeches            paused Leeches
  previous_plan      latest plan/ file and the words of it the App can still use
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import timedelta
from typing import Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import TARGET, Context, load_context  # noqa: E402

FUZZY_LOW, FUZZY_HIGH = 0.3, 0.7
TEST_SOURCES = ("test", "spotcheck", "verify")
MAX_TESTS_SHOWN = 6
MAX_ACTIVE_CARDS = 150


def build(ctx: Context, max_candidates: int = 400) -> dict:
    tz = ctx.now.tzinfo

    def day(t):
        return t.astimezone(tz).strftime("%Y-%m-%d")

    tests: Dict[str, List[str]] = {}
    for o in ctx.observations:
        if o.get("source") in TEST_SOURCES and not o.get("pseudo"):
            tests.setdefault(o["lemma"], []).append(f"{day(o['_t'])[5:]} {o['source']}:{o['result']}")

    def candidate(lemma):
        w = ctx.words[lemma]
        out = {"lemma": lemma, "p": round(w.p, 2), "rank": w.rank}
        if lemma in tests:
            out["tests"] = ", ".join(tests[lemma][-MAX_TESTS_SHOWN:])
        return out

    pool = ctx.pool
    wishes = set(ctx.pending_wishes)
    buckets = {"wish": [], "fuzzy": [], "target": []}
    for lemma in pool:
        w = ctx.words[lemma]
        if lemma in wishes:
            buckets["wish"].append(lemma)
        elif w.band == TARGET and FUZZY_LOW <= w.p <= FUZZY_HIGH:
            buckets["fuzzy"].append(lemma)
        else:
            buckets["target"].append(lemma)
    budget = max_candidates
    candidates = {}
    for name in ("wish", "fuzzy", "target"):
        chosen = buckets[name] if name == "wish" else buckets[name][:max(0, budget)]
        budget -= len(chosen)
        candidates[name] = [candidate(l) for l in chosen]

    active = [c for c in ctx.cards.values() if c.paused is None and not ctx.is_mastered(c.lemma)]
    rank = {l: w.rank for l, w in ctx.words.items()}
    active.sort(key=lambda c: (-c.recent[0], -c.recent[1], rank.get(c.lemma, 10 ** 9), c.lemma))
    active_cards = []
    for c in active[:MAX_ACTIVE_CARDS]:
        row = {"lemma": c.lemma, "ratings": c.ratings, "recent": c.recent,
               "due": day(c.due) if c.due else None, "last": day(c.last_review)}
        if c.stability is not None:
            row["stability"] = round(c.stability, 1)
        if c.lemma in ctx.words:
            row["p"] = round(ctx.words[c.lemma].p, 2)
        active_cards.append(row)

    today = ctx.now.astimezone(tz)
    by_day = {(today + timedelta(days=i)).strftime("%Y-%m-%d"): 0 for i in range(7)}
    first = min(by_day)
    for c in active:
        if c.due is None:
            continue
        d = max(day(c.due), first)
        if d in by_day:
            by_day[d] += 1

    leeches = [{"lemma": c.lemma, "lapses": c.lapses, "since": day(c.leech_since)}
               for c in sorted(ctx.cards.values(), key=lambda c: (c.leech_since or ctx.now, c.lemma))
               if c.paused == "leech"]

    previous = None
    if ctx.previous_plan:
        p = ctx.previous_plan
        remaining = ctx.remaining_in(p)
        daily = p.data.get("daily_new") or 0
        previous = {"path": p.path, "generated_at": p.data.get("generated_at"), "daily_new": daily,
                    "total": len(p.lemmas), "remaining": remaining,
                    "days_left": round(len(remaining) / daily, 1) if daily else None,
                    "summary": p.data.get("summary")}

    return {
        "now": ctx.now.isoformat(timespec="seconds"),
        "daily_new_limit": ctx.daily_new_limit,
        "pending_wishes": ctx.pending_wishes,
        "skipped_wishes": ctx.skipped_wishes,
        "pool_size": len(pool),
        "candidates": candidates,
        "active_cards": active_cards,
        "due_next_7_days": {"by_day": by_day, "total": sum(by_day.values())},
        "leeches": leeches,
        "previous_plan": previous,
    }


def dumps(obj) -> str:
    """Pretty JSON, but every list item that is an object stays on one line (fewer tokens to read)."""
    def enc(x, indent):
        pad = "  " * indent
        if isinstance(x, dict):
            if not x:
                return "{}"
            items = [f"{pad}  {json.dumps(k)}: {enc(v, indent + 1)}" for k, v in x.items()]
            return "{\n" + ",\n".join(items) + f"\n{pad}}}"
        if isinstance(x, list) and any(isinstance(i, dict) for i in x):
            rows = [f"{pad}  {json.dumps(i, ensure_ascii=False)}" for i in x]
            return "[\n" + ",\n".join(rows) + f"\n{pad}]"
        return json.dumps(x, ensure_ascii=False)
    return enc(obj, 0)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--words", help="words.tsv path or URL (default: english-profile of origin's owner)")
    ap.add_argument("--now", help="ISO 8601 time (default: now, local time zone)")
    ap.add_argument("--max-candidates", type=int, default=400)
    ap.add_argument("--out", help="write here instead of stdout")
    args = ap.parse_args(argv)
    now = args.now
    if now is None:
        from datetime import datetime
        now = datetime.now().astimezone().isoformat()
    text = dumps(build(load_context(args.repo, args.words, now), args.max_candidates))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
