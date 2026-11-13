"""Reading english-data, shared by profile_publish.py, fsrs_train.py and word_plan/ (Python 3.9+, stdlib only).

  parse_ts           ISO 8601 -> aware UTC datetime, None if malformed
  load_observations  every Observation under observations/**/*.jsonl, oldest first; malformed lines and
                     timestamps are skipped (one bad line never blocks a run)
  latest_plan        newest readable plan/YYYY-MM-DD.json (a broken newest plan falls back to the previous)
  rating_of          a review's rating as Anki ease 1-4
  replay_cards       card states from review / relearn Observations: first rating, lapses since (re)start,
                     Leech, the 30-day Leech cooldown, 重新学

replay_cards mirrors EnglishCore's `CardReplay` (CoreModels/CardReplay.swift) rule for rule; both are
checked against the same fixture, EnglishCore/Fixtures/card-replay/ (test_obs_io.py, CardReplayFixtureTests).
"""
import datetime as dt
import glob
import json
import os
import re

RATINGS = ("again", "hard", "good", "easy")  # Anki ease 1..4
LEECH_LAPSES = 8
LEECH_COOLDOWN = dt.timedelta(days=30)
# Sources that make a day a study day (连续学习天数), same as ProgressPage.studySources in the App.
STUDY_SOURCES = ("test", "spotcheck", "verify", "review")
PLAN_NAME = re.compile(r"^\d{4}-\d{2}-\d{2}\.json$")
TS_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$")


def parse_ts(ts):
    """ISO 8601 (`Z` or offset, optional fraction; no zone = UTC) -> aware datetime keeping the given
    offset; None if malformed."""
    m = TS_RE.match(ts.strip()) if isinstance(ts, str) else None
    if not m:
        return None
    y, mo, d, h, mi, s, frac, off = m.groups()
    zone = dt.timezone.utc
    if off and off != "Z":
        sign = 1 if off[0] == "+" else -1
        zone = dt.timezone(sign * dt.timedelta(hours=int(off[1:3]), minutes=int(off[-2:])))
    try:
        return dt.datetime(int(y), int(mo), int(d), int(h), int(mi), min(int(s), 59),
                           int((frac or "0")[:6].ljust(6, "0")), tzinfo=zone)
    except ValueError:
        return None


def iso_utc(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_observations(data_dir):
    """All Observations (dicts) under <data>/observations/**/*.jsonl, oldest first (ties keep file
    order). Each gets `_t`, its parsed time. Lines that are not JSON objects with a valid `ts` are skipped."""
    out = []
    for path in sorted(glob.glob(os.path.join(data_dir, "observations", "**", "*.jsonl"), recursive=True)):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(o, dict):
                    continue
                t = parse_ts(o.get("ts"))
                if t is None:
                    continue
                o["_t"] = t
                out.append(o)
    out.sort(key=lambda o: o["_t"])
    return out


def latest_plan(data_dir):
    """(path relative to data_dir, parsed JSON) of the newest readable plan/YYYY-MM-DD.json, or (None, None).
    A newest plan that is not valid JSON is skipped in favour of the previous one."""
    plan_dir = os.path.join(data_dir, "plan")
    names = sorted(n for n in os.listdir(plan_dir) if PLAN_NAME.match(n)) if os.path.isdir(plan_dir) else []
    for name in reversed(names):
        try:
            with open(os.path.join(plan_dir, name), encoding="utf-8") as f:
                return "plan/" + name, json.load(f)
        except ValueError:
            continue
    return None, None


def rating_of(o):
    """Ease 1 (again) .. 4 (easy) of a review Observation: from `result`, else `review.ease`; None if invalid."""
    if o.get("result") in RATINGS:
        return RATINGS.index(o["result"]) + 1
    ease = (o.get("review") or {}).get("ease")
    return ease if ease in (1, 2, 3, 4) else None


class CardHistory:
    """One card as replayed from Observations (no scheduler state)."""

    def __init__(self, lemma, started_at):
        self.lemma = lemma
        self.started_at = started_at  # first review, or the last restart
        self.reviews = []  # [(time, ease)] since the (re)start
        self.lapses = 0  # 忘了 since the (re)start
        self.paused = None  # None | "first_easy" | "leech"
        self.leech_since = None
        self.reintroduced = False
        self.reset_at = None
        self.generation = 0  # restarts so far: a restarted card is a new card for FSRS

    @property
    def first_ease(self):
        return self.reviews[0][1] if self.reviews else None

    @property
    def first_review(self):
        return self.reviews[0][0] if self.reviews else None

    @property
    def is_new(self):
        return not self.reviews

    @property
    def active(self):
        return bool(self.reviews) and self.paused is None

    def restart(self, at):
        self.started_at, self.reviews, self.lapses, self.paused = at, [], 0, None
        self.leech_since, self.reintroduced, self.reset_at = None, True, at
        self.generation += 1


def replay_cards(observations, as_of, lapses=LEECH_LAPSES, cooldown=LEECH_COOLDOWN, on_review=None):
    """lemma -> CardHistory from review / relearn Observations (dicts with `_t`) up to `as_of`.

    Same rules as CardReplay in EnglishCore: invalid ratings are ignored; a Leech whose cooldown has
    passed by the next event (or by as_of) restarts at leech_since + cooldown; relearn restarts an
    existing card; the first rating since (re)start being easy pauses the card; the `lapses`-th
    again since (re)start makes it a Leech. `on_review(o, card)` is called for every replayed review.
    """
    events = []
    for i, o in enumerate(observations):
        t = o.get("_t") or parse_ts(o.get("ts"))
        if t is None or t > as_of or o.get("source") not in ("review", "relearn"):
            continue
        if o.get("source") == "review" and rating_of(o) is None:
            continue
        events.append((t, i, o))
    events.sort(key=lambda e: (e[0], e[1]))

    def cool_down(c, t):
        if c.leech_since is not None and t - c.leech_since >= cooldown:
            c.restart(c.leech_since + cooldown)

    cards = {}
    for t, _, o in events:
        lemma = o.get("lemma")
        if o.get("source") == "relearn":
            if lemma in cards:
                cool_down(cards[lemma], t)
                cards[lemma].restart(t)
            continue
        ease = rating_of(o)
        c = cards.get(lemma)
        if c is None:
            c = cards[lemma] = CardHistory(lemma, t)
        cool_down(c, t)
        if not c.reviews and ease == 4:
            c.paused = "first_easy"
        c.reviews.append((t, ease))
        if ease == 1:
            c.lapses += 1
            if c.lapses >= lapses and c.leech_since is None:
                c.leech_since, c.paused = t, "leech"
        if on_review is not None:
            on_review(o, c)
    for c in cards.values():
        cool_down(c, as_of)
    return cards


def study_days(observations, tz):
    """Local dates (YYYY-MM-DD in tz) with any test or review answer."""
    return sorted({o["_t"].astimezone(tz).date().isoformat() for o in observations
                   if o.get("source") in STUDY_SOURCES and o.get("_t")})


def streak(days, today):
    """连续学习天数: consecutive dates in `days` ending today or yesterday (0 once a full day is missed)."""
    have = set(days)
    d = dt.date.fromisoformat(today)
    if d.isoformat() not in have:
        d -= dt.timedelta(days=1)
    n = 0
    while d.isoformat() in have:
        n += 1
        d -= dt.timedelta(days=1)
    return n
