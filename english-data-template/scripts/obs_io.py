"""Reading english-data, used by profile_publish.py (Python 3.9+, stdlib only).

  parse_ts           ISO 8601 -> aware UTC datetime, None if malformed
  load_observations  every Observation under observations/**/*.jsonl, oldest first; malformed lines and
                     timestamps are skipped (one bad line never blocks a run)
  test_days, streak  local days with a Vocabulary Test answer, and the 连续天数 ending today or yesterday
"""
import datetime as dt
import glob
import json
import os
import re

# Sources that make a day a test day (连续天数), same as ProgressPage.testSources in the App.
TEST_SOURCES = ("test", "spotcheck", "verify")
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


def test_days(observations, tz):
    """Local dates (YYYY-MM-DD in tz) with any Vocabulary Test answer."""
    return sorted({o["_t"].astimezone(tz).date().isoformat() for o in observations
                   if o.get("source") in TEST_SOURCES and o.get("_t")})


def streak(days, today):
    """连续天数: consecutive dates in `days` ending today or yesterday (0 once a full day is missed)."""
    have = set(days)
    d = dt.date.fromisoformat(today)
    if d.isoformat() not in have:
        d -= dt.timedelta(days=1)
    n = 0
    while d.isoformat() in have:
        n += 1
        d -= dt.timedelta(days=1)
    return n
