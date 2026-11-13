---
name: word-plan
description: 选词规划：读学习记录摘要，写出新的 Study Plan 到 plan/ 并提交推送。用法 /word-plan [临时要求]
disable-model-invocation: true
---

# word-plan（选词规划）

You are doing **Word Planning** for the single Learner (see the App repo's GLOSSARY): choose and order the Target words they start next, and write them as a Study Plan. The iPhone App takes new cards only from the newest `plan/YYYY-MM-DD.json`, so a missing or broken plan means no new cards.

Run unattended. Ask nothing; decide, write, validate, commit. The run is either **committed** (a valid plan is pushed) or **failed** (nothing committed, last message starts with `word-plan 失败：` and the reason).

Instruction from the Learner for this run (may be empty): `$ARGUMENTS`

## Steps

Work in the root of this `english-data` clone.

1. **Sync.** `git pull --rebase`. Done when it succeeds; if it fails, end **failed**.
2. **Summarise.** `python3 scripts/word_plan/summary.py --out "$TMPDIR/word-plan-summary.json"` and read that file in full. It is the only learner data you read: leave `observations/` alone. Done when you know: the daily limit, every pending 想学 word, `pool_size`, the due reviews per day, and how much of the previous plan is left. If the script fails (e.g. `words.tsv` cannot be downloaded), end **failed**.
3. **Plan.** Apply *Choosing words* below. Done when you have `daily_new`, an ordered `new_words` list of at least `daily_new × 7` words (or the whole pool when `pool_size` is smaller), a note for each, `focus_targets`, and the summary.
4. **Write** `plan/<today>.json` (today = the date part of the summary's `now`; a rerun on the same day overwrites it) in the *Plan file* format.
5. **Validate.** `python3 scripts/word_plan/validate.py plan/<today>.json`. Done when it prints `OK`. On errors, fix exactly what each `[code]` line names and validate again, at most 2 fixes. Still failing after the second fix: restore the file (`git checkout -- plan/<today>.json` if it was tracked, otherwise delete it) and end **failed** quoting the validator output.
6. **Commit.** `git add plan/<today>.json` (that file only), then `git commit` with the summary as the first line and, after a blank line, `word-plan: N words, daily_new D` plus the instruction if any. `git push`; if rejected, `git pull --rebase` and push once more. A second rejection ends **failed**.
7. **Report** in Chinese: the summary, the file path, and the commit hash.

## Choosing words

**Order** (`new_words` is the order the App teaches them):

1. Every word in `pending_wishes` (想学), first. Mandatory.
2. `candidates.fuzzy`: 似懂非懂, P between 0.3 and 0.7; higher frequency (lower `rank`) first. Words the tests got wrong recently move up.
3. `candidates.target`: the other Target words, by frequency.

Deviate when you have a reason (e.g. a word that pairs with a struggling card, a topic the instruction asks for); put the reason in that word's note. Keep confusable words (affect/effect, adapt/adopt, a word and its derivative) at least 3 days apart: at least `3 × daily_new` positions apart in `new_words`. Words of the previous plan that are still in `previous_plan.remaining` can stay, at their new rank.

**`daily_new`**: between 1 and `daily_new_limit`. Start from the limit and go lower when reviews pile up: the more `due_next_7_days.total` exceeds about `5 × daily_new_limit`, or the more `active_cards` show recent 忘了/模糊, the fewer new words. Follow the Learner's instruction when it asks for fewer or more (within the limit).

**`focus_targets`** (≤ 50): the words the Learner is working on now. First `active_cards` that are struggling (recent 忘了 or 模糊, low stability), worst first; then fill to 50 with the first words of `new_words`.

**Notes** (`note`, Chinese, ≤ 40 characters, may be empty): only these three kinds of content:
- why now: 「测试答错且高频」「想学」「复习常评模糊的 X 的同族词」;
- confusables: 「易与 effect 混」;
- a memory hook you are certain of.

The card already shows the dictionary definition and examples, so leave meanings out. Write only what you are sure of; when unsure about a meaning, etymology or collocation, leave it out.

**Summary** (`summary`): 1–3 Chinese sentences on what this plan does and why, e.g. 「本期排 70 词，复习积压较多，每天建议 8 个；优先补测试中答错的高频词。」 It is shown in the App under today's new-card count and is the commit message's first line.

## Plan file

```json
{
  "schema_version": 1,
  "generated_at": "2026-11-13T07:30:00+08:00",
  "daily_new": 8,
  "new_words": [
    {"lemma": "ambiguous", "note": "想学"},
    {"lemma": "adequate", "note": "测试答错且高频"}
  ],
  "focus_targets": ["allocate", "abandon", "ambiguous"],
  "summary": "本期排 70 词……",
  "instruction": null
}
```

- `generated_at`: the summary's `now`, verbatim.
- `lemma`: exactly as in the summary (lowercase lemma from `words.tsv`).
- `instruction`: the Learner's instruction above, verbatim; `null` when empty.
