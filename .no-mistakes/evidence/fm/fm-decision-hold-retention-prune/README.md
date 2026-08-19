# Retention-safe captain decisions - test evidence

Incident: resolving more than `done_keep` captain decisions and then closing the
scout pruned the earliest resolved decision records out of `data/backlog.md`, so
`fm-decision-hold verify` could no longer find its inventory and
`bin/fm-teardown.sh` refused the teardown.

All runs use the tracked `.tasks.toml` (`done_keep = 10`). Nothing raises or
overrides that value.

| Evidence | What it shows |
| --- | --- |
| `teardown-before-fix.txt` | Same operator scenario on the pristine base commit: 12 answered decisions, scout closed, 3 oldest resolved records archived, `verify` reports them absent, `bin/fm-teardown.sh` REFUSED, scout state kept. |
| `teardown-after-fix.txt` | Identical scenario on this branch: same pruning, same archive bytes, `verify` passes, `bin/fm-teardown.sh` completes and clears the scout. |
| `regression-fails-before-fix.txt` | The new colocated regression run against base-commit code: fails with the exact incident message. |
| `decision-hold-suite-fixed.txt` | `tests/fm-decision-hold-lifecycle.test.sh` on this branch, 22/22. |
| `teardown-refusal-still-holds.txt` | Gate not weakened: an archived record closed outside the script still fails `verify`, teardown still REFUSES, report and state preserved, no close path or `repair` can invent an answer, reopen refused, archive bytes unchanged. |
| `teardown-suite.txt` | `tests/fm-teardown.test.sh` (teardown refusal contract). |

The `done-archive.md` sha256 is identical in the before-fix and after-fix runs
(`82c99995...`), so the fix changes only what the gate reads, never what pruning writes.
