#!/usr/bin/env python3
"""Train personal FSRS-6 parameters from the Learner's own review Observations.

Run by .github/workflows/train-fsrs.yml inside english-data:

  fsrs_train.py check --data . [--github-output $GITHUB_OUTPUT]   # stdlib only: train or skip?
  fsrs_train.py train --data . [--now ISO]                          # needs requirements-fsrs.txt

Only Observations with `source == "review"` are trained on (never tests, spot checks, wishes or
settings). Cards come from the shared card replay (obs_io.replay_cards): a lemma is one card until
it restarts (重新学, or a Leech's 30-day cooldown), after which its reviews belong to a new card.
The rating is the `result` string, falling back to the revlog `ease` (1 again .. 4 easy).
Malformed lines are skipped.

Thresholds:
  MIN_REVIEWS = 600   below this the run is skipped (exit 0). FSRS docs say optimisation
                      needs "several hundred" reviews; py-fsrs' optimizer itself silently
                      returns the defaults below 512 cross-day reviews, so 600 review
                      Observations (some are same-day learning steps) is the floor.
  RETRAIN_EVERY = 200 after the first training, retrain only once this many new reviews
                      have arrived since the `review_count` recorded in the params file.
If the optimizer still returns the defaults (too few cross-day reviews), nothing is written.

Output: fsrs/params.json
  {"format": 1, "algorithm": "FSRS-6", "w": [21 floats, w[20] = decay], "decay": w[20],
   "review_count": N, "trained_at": "YYYY-MM-DDTHH:MM:SSZ", "optimizer": "py-fsrs X.Y.Z"}
The App reads it on sync and falls back to FSRS-6 defaults when it is absent or invalid.
"""
import argparse
import collections
import datetime as dt
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from obs_io import iso_utc, load_observations, parse_ts, rating_of, replay_cards  # noqa: E402

PARAMS_PATH = os.path.join("fsrs", "params.json")
MIN_REVIEWS = 600
RETRAIN_EVERY = 200
PINNED_FSRS = "6.3.2"  # keep in sync with requirements-fsrs.txt
FORMAT = 1

ReviewRow = collections.namedtuple("ReviewRow", "card_id rating review_datetime review_duration")
Decision = collections.namedtuple("Decision", "train reason")


def load_card_events(data_dir):
    """Review and relearn Observations under observations/**.jsonl, oldest first (bad lines skipped)."""
    return [o for o in load_observations(data_dir) if o.get("source") in ("review", "relearn")]


def load_reviews(data_dir):
    """All review Observations under observations/**.jsonl, oldest first (bad lines skipped)."""
    return [o for o in load_card_events(data_dir) if o.get("source") == "review"]


def review_log_rows(observations):
    """Review (and relearn) Observations -> optimizer rows. Card ids are 1, 2, ... in order of first
    review; a card restarted by 重新学 or the Leech cooldown gets a new id."""
    times = [t for t in (o.get("_t") or parse_ts(o.get("ts")) for o in observations) if t]
    if not times:
        return []
    ids, out = {}, []

    def add(o, card):
        card_id = ids.setdefault((card.lemma, card.generation), len(ids) + 1)
        duration = o.get("rt_ms")
        if duration is None:
            duration = (o.get("review") or {}).get("time")
        out.append(ReviewRow(card_id, rating_of(o), card.reviews[-1][0], duration))

    replay_cards(observations, max(times), on_review=add)
    return out


def read_params(data_dir):
    try:
        with open(os.path.join(data_dir, PARAMS_PATH), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def valid_params(p):
    return (isinstance(p, dict) and isinstance(p.get("w"), list) and len(p["w"]) == 21
            and isinstance(p.get("review_count"), int))


def decide(review_count, previous):
    if review_count < MIN_REVIEWS:
        return Decision(False, "%d review Observations, need %d: keep default parameters" % (review_count, MIN_REVIEWS))
    if not valid_params(previous):
        return Decision(True, "%d review Observations, no usable params yet" % review_count)
    new = review_count - previous["review_count"]
    if new < RETRAIN_EVERY:
        return Decision(False, "%d new reviews since last training, retrain after %d" % (new, RETRAIN_EVERY))
    return Decision(True, "%d new reviews since last training" % new)


def optimize(rows):
    """Runs the py-fsrs optimizer; returns 21 weights, or None if it fell back to the defaults."""
    from fsrs import Optimizer, Rating, ReviewLog
    from fsrs.scheduler import DEFAULT_PARAMETERS

    logs = [ReviewLog(card_id=r.card_id, rating=Rating(r.rating), review_datetime=r.review_datetime,
                      review_duration=r.review_duration) for r in rows]
    w = [float(x) for x in Optimizer(logs).compute_optimal_parameters()]
    if w == [float(x) for x in DEFAULT_PARAMETERS]:
        return None
    return w


def installed_fsrs_version():
    from importlib.metadata import version
    return version("fsrs")


def train(data_dir, now):
    events = load_card_events(data_dir)
    reviews = [o for o in events if o.get("source") == "review"]
    d = decide(len(reviews), read_params(data_dir))
    print(d.reason)
    if not d.train:
        return None
    w = optimize(review_log_rows(events))
    if w is None:
        print("optimizer returned the defaults (too few cross-day reviews): nothing written")
        return None
    w = [round(x, 6) for x in w]
    params = {"format": FORMAT, "algorithm": "FSRS-6", "w": w, "decay": w[20], "review_count": len(reviews),
              "trained_at": iso_utc(now), "optimizer": "py-fsrs " + installed_fsrs_version()}
    path = os.path.join(data_dir, PARAMS_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(params, f, indent=2)
        f.write("\n")
    print("wrote %s (%d reviews)" % (PARAMS_PATH, len(reviews)))
    return params


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="decide whether to train (standard library only)")
    c.add_argument("--data", default=".")
    c.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT"))
    t = sub.add_parser("train", help="train and write fsrs/params.json")
    t.add_argument("--data", default=".")
    t.add_argument("--now", help="override the trained_at time (ISO 8601)")
    a = ap.parse_args(argv)

    if a.cmd == "check":
        n = len(load_reviews(a.data))
        d = decide(n, read_params(a.data))
        print(d.reason)
        if a.github_output:
            with open(a.github_output, "a") as f:
                f.write("train=%s\nreview_count=%d\n" % ("true" if d.train else "false", n))
        return 0

    now = parse_ts(a.now) if a.now else dt.datetime.now(dt.timezone.utc)
    train(a.data, now)
    return 0


if __name__ == "__main__":
    sys.exit(main())
