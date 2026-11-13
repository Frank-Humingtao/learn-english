# Issue tracker: GitHub Issues

Issues for this repo live in GitHub Issues on `Frank-Humingtao/learn-english`. Use the `gh` CLI for every operation.

Specs and design material stay as files in the repo: specs under `.scratch/<feature-slug>/spec.md`, research and prototypes next to them. `.scratch/english-learning-app/issues/` holds the original tickets 01–10 (all resolved). It is a read-only archive: do not add new tickets there.

The repo is public, so issue text is public. Never put tokens, personal data or the Learner's raw results in an issue.

## Conventions

- One issue per piece of work. Write the body in Chinese: a `## 要做的` section, `## 完成标准` with checkboxes, and pointers to files (paths) instead of copying content.
- Triage state is a label (see `triage-labels.md`). Exactly one triage label per open issue.
- Discussion and results go in issue comments (`gh issue comment`).
- Code changes go on a branch off `main` and a PR whose body says `Closes #N`.

## When a skill says "publish to the issue tracker"

`gh issue create --repo Frank-Humingtao/learn-english -t "<title>" -F <body-file> -l <triage-label>`

## When a skill says "fetch the relevant ticket"

`gh issue view <N> --repo Frank-Humingtao/learn-english --comments`. The user will normally pass the issue number.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a parent issue with one **child** issue per ticket.

- **Map**: an issue labelled `map` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: an issue whose body starts with `Map: #<map>`, a `Type:` line (`research`/`prototype`/`grilling`/`task`) and the question.
- **Blocking**: a `Blocked by: #N, #N` line in the body. A ticket is unblocked when every issue it lists is closed.
- **Frontier**: open, unblocked child issues with no assignee, lowest number first.
- **Claim**: assign yourself (`gh issue edit <N> --add-assignee @me`) before any work.
- **Resolve**: comment the answer under an `## Answer` heading, close the issue, then add a context pointer (gist + link) to the map issue's Decisions-so-far.
