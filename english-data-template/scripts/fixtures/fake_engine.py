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
json.dump({"schema_version": 1, "updated_at": last[:10],
           "vocab_size": {"families": {"estimate": n * 10, "low": n * 8, "high": n * 12}},
           "band_counts": {"mastered": n, "target": len(seen) - n, "distant": 0}},
          open(os.path.join(out, "summary.json"), "w"))
with open(os.path.join(out, "words.tsv"), "w") as f:
    f.write("lemma\tband\tp\trank\n")
    for lemma, rank in sorted(seen.items(), key=lambda kv: kv[1]):
        f.write("%s\t%s\t%s\t%d\n" % (lemma, "Mastered" if lemma in known else "Target",
                                      "0.9500" if lemma in known else "0.5000", rank))
