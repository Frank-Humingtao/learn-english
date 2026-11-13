# Issue tracker: GitHub Issues

Issues live only on GitHub: `Frank-Humingtao/learn-english`. Use the `gh` CLI. Don't create local ticket files; there is no `.scratch/`.

Specs and research notes are kept in the repo:

- Specs: `docs/specs/<feature>.md`
- Research notes: `docs/research/NN-<slug>.md`
- Decisions: `docs/adr/`

## Conventions

- One issue per ticket. Its title starts with the feature and number, e.g. `测量 02：重写模型`.
- The body links the spec (`docs/specs/...`) and lists `Blocked by: #N` when it depends on another issue.
- Triage state is a label (see `triage-labels.md`).
- Discussion and results go in issue comments. A PR that finishes a ticket says `Closes #N`.

## When a skill says "publish to the issue tracker"

`gh issue create --repo Frank-Humingtao/learn-english --title ... --body ... --label ...`

## When a skill says "fetch the relevant ticket"

`gh issue view <N> --repo Frank-Humingtao/learn-english --comments`

## Wayfinding operations

Used by `/wayfinder`.

- **Map**: a GitHub issue labelled `map` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: an issue whose body links the map issue; the question is in the body.
- **Blocking**: a `Blocked by: #N, #N` line in the body. A ticket is unblocked when every issue it lists is closed.
- **Frontier**: open, unblocked issues with no assignee; lowest number wins.
- **Claim**: assign yourself (`gh issue edit <N> --add-assignee @me`) before any work.
- **Resolve**: comment the answer, close the issue, then add a pointer (gist + link) to the map issue's Decisions-so-far.
