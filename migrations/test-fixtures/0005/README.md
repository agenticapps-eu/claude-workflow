# Migration 0005 test fixtures

11 scenarios that exercise every decision branch of `templates/.claude/hooks/multi-ai-review-gate.sh`. Run via the `test_migration_0005()` stanza in `migrations/run-tests.sh`.

## Layout per fixture

| File | Purpose |
|---|---|
| `stdin.json` | Tool-use JSON piped to the hook's stdin |
| `setup.sh` (optional) | Shell snippet to materialize `.planning/`, symlinks, fake artifacts in `$PWD` (driver chdirs into a fresh tmp dir first) |
| `env` (optional) | Newline-separated `KEY=value` env vars sourced into the hook's environment |
| `expected-exit` | Single integer the hook must exit with |
| `expected-stderr.txt` | Empty file ⇒ no stderr expected; non-empty ⇒ every line must appear in actual stderr in order (strict per codex F1) |

## Scenarios

| # | Name | Tool | Phase state | Override | Expected exit | Notes |
|---|---|---|---|---|---|---|
| 01 | no-active-phase | Edit | no `.planning/current-phase` symlink | — | 0 | Workflow not in active phase |
| 02 | no-plans | Write | phase dir empty | — | 0 | Planning hasn't started |
| 03 | plan-no-reviews | Edit | PLAN.md present, REVIEWS.md missing | — | **2** | The canonical block |
| 04 | plan-with-reviews | Edit | both present, REVIEWS.md ≥ 5 lines | — | 0 | Happy path |
| 05 | stub-reviews | Edit | REVIEWS.md present but 3 lines | — | 0 (warn) | Stub threshold |
| 06 | env-override | Edit | block state | `GSD_SKIP_REVIEWS=1` | 0 | Env escape hatch |
| 07 | sentinel-override | Edit | block state | `multi-ai-review-skipped` file | 0 | Committed-audit-trail escape |
| 08 | planning-artifact-edit | Edit | block state | edit is on a `*PLAN.md` | 0 | Bypass list (chicken-and-egg) |
| 09 | hostile-filename-edit | Edit | block state | filename contains `$(rm -rf …)` | **2** | Hostile string parsed inertly. Marker file `/tmp/HOSTILE_MARKER` must survive. |
| 10 | non-edit-tool | Bash | — | — | 0 | Short-circuit before phase inspection |
| 11 | multiedit-tool | MultiEdit | block state | — | **2** | Proves MultiEdit closure (post-codex B3) |

## Driver expectations

The harness driver (`run-tests.sh` → `test_migration_0005`) must:

1. Create a fresh `mktemp -d` per fixture; cd into it.
2. If `setup.sh` exists, source/execute it from the tmp dir.
3. Source `env` (if present) into the hook invocation environment.
4. Pipe `stdin.json` into `bash <repo>/templates/.claude/hooks/multi-ai-review-gate.sh`.
5. Capture exit code and stderr.
6. Assert exit code matches `expected-exit`.
7. Assert each line of `expected-stderr.txt` (where non-empty) appears in actual stderr in order (`grep -F -q` per line, position-aware).
8. For fixture 09 specifically: also assert `/tmp/HOSTILE_MARKER` still exists post-invocation.
9. Clean up tmp dir.
