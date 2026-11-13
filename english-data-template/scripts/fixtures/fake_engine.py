#!/usr/bin/env python3
"""Stand-in for `profile-engine profile` in unit tests: Mastered = any yes/good/easy answer."""
import glob, json, os, sys

args = sys.argv[1:]
obs_dir, out = args[args.index("--observations") + 1], args[args.index("--out") + 1]
seen, known, last = {}, set(), ""
for path in sorted(glob.glob(os.path.join(obs_dir, "**", "*.jsonl"), recursive=True)):
    for line in open(path, encoding="utf-8"):
        try:
            o = json.loads(line)
        except ValueError:
            continue
        if o.get("pseudo") or o.get("source") not in ("test", "review", "verify", "spotcheck"):
            continue
        seen.setdefault(o["lemma"], len(seen) + 1)
        last = max(last, o["ts"])
        if o["result"] in ("yes", "good", "easy", "correct"):
            known.add(o["lemma"])
n = len(known)
os.makedirs(out, exist_ok=True)
est = lambda k: {"estimate": n * k, "low": n * k * 8 // 10, "high": n * k * 12 // 10}
json.dump({"schema_version": 3, "updated_at": last[:10], "lexicon_version": "lex-fake",
           "vocab_size": {"families": est(10), "lemmas": est(20),
                          "core": {"families": est(9), "lemmas": est(18)},
                          "tail": {"families": est(1), "lemmas": est(2)}},
           "band_counts": {"mastered": n, "target": len(seen) - n, "distant": 0},
           "level_mastery": [{"level": lv, "families": 1000, "mastery": round(0.9624 * 0.6626 ** (lv - 1), 4)}
                             for lv in range(1, 26)]},
          open(os.path.join(out, "summary.json"), "w"))
with open(os.path.join(out, "words.tsv"), "w") as f:
    f.write("lemma\tband\tp\tse\trank\n")
    for lemma, rank in sorted(seen.items(), key=lambda kv: kv[1]):
        f.write("%s\t%s\t%s\t%s\t%d\n" % (lemma, "Mastered" if lemma in known else "Target",
                                          "0.9500" if lemma in known else "0.5000", "0.0100", rank))
