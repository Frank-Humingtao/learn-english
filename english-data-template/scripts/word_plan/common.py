"""Learner state shared by the word-plan summary and validator (Python 3 stdlib only).

Reads the raw inputs of Word Planning:
  - every Observation under `observations/**/*.jsonl` of an `english-data` clone,
  - the latest `words.tsv` (lemma, Word Band, P, frequency rank) published to `english-profile`,
  - the Study Plans under `plan/YYYY-MM-DD.json`.
Card rules mirror the App's StudyComposer (CardLedger): a lemma with any review Observation has a
card; 8 "忘了" since the card (re)started make it a Leech, paused until a `relearn` Observation or
30 days later; a first rating of 太简单 pauses the card.
"""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional

LEECH_LAPSES = 8
LEECH_COOLDOWN = timedelta(days=30)
DEFAULT_DAILY_NEW_LIMIT = 10
TARGET, MASTERED = "Target", "Mastered"
EASE_NAMES = ("again", "hard", "good", "easy")
PLAN_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})\.json$")


def parse_ts(s: str) -> datetime:
    """ISO 8601 with `Z` or an offset, optional fractional seconds; returns an aware datetime."""
    s = s.strip().replace("Z", "+00:00")
    m = re.match(r"^(.*T\d{2}:\d{2}:\d{2})(\.\d+)?(.*)$", s)
    if m and m.group(2):  # Python 3.9 only accepts 3 or 6 fractional digits
        frac = (m.group(2)[1:] + "000000")[:6]
        s = f"{m.group(1)}.{frac}{m.group(3)}"
    d = datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


@dataclass
class Word:
    lemma: str
    band: str
    p: float
    rank: int


@dataclass
class Card:
    lemma: str
    ratings: List[int] = field(default_factory=lambda: [0, 0, 0, 0])  # again/hard/good/easy, all time
    recent: List[int] = field(default_factory=lambda: [0, 0, 0, 0])  # last 14 days
    lapses: int = 0  # 忘了 since the card (re)started
    first_ease: Optional[int] = None
    first_review: Optional[datetime] = None
    last_review: Optional[datetime] = None
    due: Optional[datetime] = None
    stability: Optional[float] = None
    leech_since: Optional[datetime] = None
    reset_at: Optional[datetime] = None

    @property
    def paused(self) -> Optional[str]:
        if self.leech_since is not None:
            return "leech"
        if self.first_ease == 4 and self.reset_at is None:
            return "easy"
        return None


@dataclass
class Plan:
    path: str
    data: dict

    @property
    def lemmas(self) -> List[str]:
        return [w.get("lemma") for w in self.data.get("new_words", []) if isinstance(w, dict)]


@dataclass
class Context:
    now: datetime
    words: Dict[str, Word]
    observations: List[dict]
    cards: Dict[str, Card]
    pending_wishes: List[str]  # 想学 words with no card yet, oldest first (Mastered ones excluded)
    skipped_wishes: List[str]  # 想学 words that are Mastered or not in words.tsv
    daily_new_limit: int
    previous_plan: Optional[Plan]

    def is_mastered(self, lemma: str) -> bool:
        w = self.words.get(lemma)
        return w is not None and w.band == MASTERED

    def eligible(self, lemma: str) -> bool:
        """May be planned as a new card: in the word list, no card, not Mastered."""
        return lemma in self.words and lemma not in self.cards and not self.is_mastered(lemma)

    @property
    def pool(self) -> List[str]:
        """Words Word Planning should choose from: pending 想学 words, then Target words without a card."""
        seen = set(self.pending_wishes)
        rest = [w.lemma for w in sorted(self.words.values(), key=lambda w: w.rank)
                if w.band == TARGET and w.lemma not in seen and self.eligible(w.lemma)]
        return list(self.pending_wishes) + rest

    def remaining_in(self, plan: Plan) -> List[str]:
        """Words of a plan the App can still turn into new cards."""
        seen, out = set(), []
        for lemma in plan.lemmas:
            if lemma not in seen and self.eligible(lemma):
                seen.add(lemma)
                out.append(lemma)
        return out


# ---------------------------------------------------------------- loading

def load_words(spec: Optional[str], repo: str) -> Dict[str, Word]:
    """`spec` is a path or http(s) URL; None means `words.tsv` on `english-profile` of the clone's owner."""
    if spec is None:
        spec = default_words_url(repo)
    if re.match(r"^https?://", spec):
        with urllib.request.urlopen(spec, timeout=60) as r:
            text = r.read().decode("utf-8")
    else:
        with open(spec, encoding="utf-8") as f:
            text = f.read()
    words = {}
    lines = text.splitlines()
    header = lines[0].split("\t") if lines else []
    col = {name: i for i, name in enumerate(header)}
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        lemma = parts[col["lemma"]]
        words[lemma] = Word(lemma, parts[col["band"]], float(parts[col["p"]]), int(parts[col["rank"]]))
    return words


def default_words_url(repo: str) -> str:
    """raw.githubusercontent.com URL of `<owner>/english-profile/main/words.tsv`, owner from `origin`."""
    url = subprocess.run(["git", "-C", repo, "remote", "get-url", "origin"],
                         capture_output=True, text=True, check=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/", url)
    if not m:
        raise SystemExit(f"cannot derive the GitHub owner from origin {url!r}; pass --words")
    return f"https://raw.githubusercontent.com/{m.group(1)}/english-profile/main/words.tsv"


def load_observations(repo: str) -> List[dict]:
    out = []
    for path in sorted(glob.glob(os.path.join(repo, "observations", "**", "*.jsonl"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                    o["_t"] = parse_ts(o["ts"])
                except (ValueError, KeyError):
                    continue
                out.append(o)
    out.sort(key=lambda o: o["_t"])
    return out


def latest_plan(repo: str) -> Optional[Plan]:
    names = sorted(n for n in os.listdir(os.path.join(repo, "plan")) if PLAN_NAME.match(n)) \
        if os.path.isdir(os.path.join(repo, "plan")) else []
    if not names:
        return None
    path = os.path.join(repo, "plan", names[-1])
    try:
        with open(path, encoding="utf-8") as f:
            return Plan(os.path.relpath(path, repo), json.load(f))
    except ValueError:
        return None


def build_cards(observations: List[dict], now: datetime) -> Dict[str, Card]:
    cards: Dict[str, Card] = {}
    recent_from = now - timedelta(days=14)

    def restart(c: Card, at: datetime):
        c.lapses, c.leech_since, c.reset_at = 0, None, at
        c.due = at

    for o in observations:
        src, lemma, t = o.get("source"), o.get("lemma"), o["_t"]
        if src == "relearn" and lemma in cards:
            restart(cards[lemma], t)
            continue
        if src != "review":
            continue
        ease = (o.get("review") or {}).get("ease") or (EASE_NAMES.index(o["result"]) + 1
                                                        if o.get("result") in EASE_NAMES else None)
        if ease not in (1, 2, 3, 4):
            continue
        c = cards.setdefault(lemma, Card(lemma))
        if c.leech_since and t - c.leech_since >= LEECH_COOLDOWN:
            restart(c, c.leech_since + LEECH_COOLDOWN)
        if c.first_ease is None:
            c.first_ease, c.first_review = ease, t
        c.ratings[ease - 1] += 1
        if t >= recent_from:
            c.recent[ease - 1] += 1
        c.last_review = t
        rv = o.get("review") or {}
        c.due = parse_ts(rv["due"]) if rv.get("due") else c.due
        c.stability = rv.get("stability", c.stability)
        if ease == 1:
            c.lapses += 1
            if c.lapses >= LEECH_LAPSES and c.leech_since is None:
                c.leech_since = t
    for c in cards.values():
        if c.leech_since and now - c.leech_since >= LEECH_COOLDOWN:
            restart(c, c.leech_since + LEECH_COOLDOWN)
    return cards


def load_context(repo: str, words_spec: Optional[str], now: Optional[str] = None) -> Context:
    now_dt = parse_ts(now) if now else datetime.now(timezone.utc)
    words = load_words(words_spec, repo)
    observations = [o for o in load_observations(repo) if o["_t"] <= now_dt]
    cards = build_cards(observations, now_dt)

    limit = DEFAULT_DAILY_NEW_LIMIT
    pending, skipped, seen = [], [], set()
    for o in observations:
        if o.get("source") == "setting" and o.get("lemma") == "daily_new_limit":
            try:
                limit = int(o["result"])
            except (ValueError, KeyError):
                pass
        elif o.get("source") == "wish" and o.get("lemma") not in seen:
            lemma = o["lemma"]
            seen.add(lemma)
            if lemma in cards:
                continue
            w = words.get(lemma)
            (pending if w is not None and w.band != MASTERED else skipped).append(lemma)

    return Context(now_dt, words, observations, cards, pending, skipped, limit, latest_plan(repo))
