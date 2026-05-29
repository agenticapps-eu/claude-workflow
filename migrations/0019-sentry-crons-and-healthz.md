---
id: 0019
slug: sentry-crons-and-healthz
title: Sentry Crons heartbeats (withCronMonitor) + /healthz convention
from_version: 1.17.0
to_version: 1.18.0
applies_to:
  - "<wrapper-dir>/cron-monitor.ts"                # NEW (TS stacks: worker, pages, supabase-edge)
  - "<wrapper-dir>/cron_monitor.go"                # NEW (go-fly-http)
  - "<wrapper-dir>/healthz-snippet.ts"             # NEW (TS stacks; copy-only)
  - "<wrapper-dir>/healthz_snippet.go"             # NEW (go-fly-http; copy-only)
  - "<wrapper-dir>/middleware.{ts,go}"             # NO CHANGE — wrapper interface frozen
  - "<wrapper-dir>/_middleware.ts"                 # NO CHANGE — cf-pages frontmatter
  - "<wrapper-dir>/lib-observability.ts"           # NO CHANGE
  - "<wrapper-dir>/observability.go"               # NO CHANGE
  - CLAUDE.md observability block                  # NO CHANGE (G6)
  - .claude/skills/agentic-apps-workflow/SKILL.md  # version 1.17.0 → 1.18.0
requires:
  - file: templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
    install: "vendored in the scaffolder repo; symlinked into $HOME via the same install pattern as add-observability/"
    verify: "test -x $HOME/.claude/skills/agenticapps-workflow/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
optional_for:
  - ts-react-vite-only projects (browser bundle has no scheduled handlers; full skip per CONTEXT D10)
  - projects without scheduled handlers (cparx-shape — wrapper still applies; exports just unused)
  - projects without a materialised add-observability wrapper (pre-init)
---

# Migration 0019 — Sentry Crons heartbeats + `/healthz` convention

Brings projects from AgenticApps workflow `v1.17.0` to `v1.18.0` by **additively**
installing the new `withCronMonitor` wrapper and the copy-only `healthz-snippet`
into every materialised observability wrapper that already carries the v0.5.x
shape (lib-observability + middleware + destinations registry). The migration
mirrors 0017's safety conventions — style-insensitive content-hash refuse on
hand-modified wrappers — but is **strictly additive**: it never edits an existing
wrapper file, never touches CLAUDE.md, and never bumps the spec.

This is a lower-risk migration than 0017 (which rewrote the wrapper entry file
inline-Sentry → registry-dispatched). 0019 only **copies new sibling files**
into the wrapper directory; existing v1.17.0 exports stay byte-identical
(CONTEXT G2, PLAN R11). The high-risk piece preserved from 0017 is the
**hand-modified refuse**: a wrapper whose middleware / lib-observability /
observability.go has drifted from the known v1.17.0 baseline is treated as
operator-owned and refused. See ADR-0028 for the design rationale.

To make the consent / refuse semantics testable end-to-end, the apply is
delegated to a vendored executable engine —
`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` — which is
exercised by `test_migration_0019()` in `migrations/run-tests.sh` against the
fixtures under `migrations/test-fixtures/0019/`. The migration runner invokes
the engine; this markdown documents its contract.

## Pre-flight (hard aborts on failure — ZERO writes)

The engine performs all of the following before mutating anything:

```bash
ENGINE="$HOME/.claude/skills/agenticapps-workflow/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$HOME/.claude/skills/agenticapps-workflow/add-observability/templates"

bash "$ENGINE" --templates-dir "$TEMPLATES"
#   add --dry-run to preview without writing.
#   add --allow-partial to opt into applying clean roots while skipping dirty ones.
```

1. **Workflow version gate.** `.claude/skills/agentic-apps-workflow/SKILL.md`
   `version:` must be in `1.17.0` (or already `1.18.0` for a clean re-run).
   Anything else → ABORT exit 3, zero writes.
2. **Templates dir present.** `--templates-dir` must point at the scaffolder's
   `add-observability/templates/` tree (where the per-stack `cron-monitor.ts`
   / `cron_monitor.go` / `healthz-snippet.ts` / `healthz_snippet.go` source
   files live). Absent → ABORT exit 3.
3. **At least one materialised wrapper or react-vite-only.** The engine scans
   for wrapper directories (canonical materialised paths the generator uses).
   If none exist the project is pre-init: the engine prints a notice, bumps the
   version (the project is on the 1.18.0 track), and exits 0.
4. **All-clean gate (PLAN R08 — codex HIGH-severity binding).** Hand-modified
   detection runs across **all** discovered roots BEFORE any write. If ANY
   root is hand-modified, the DEFAULT behaviour is to ABORT with **zero writes
   to any root** (exit 2), listing every offender plus the clean roots that
   *would* have migrated. Proceed-and-skip-the-dirty-ones is opt-in only via
   `--allow-partial`. A single-pass loop is insufficient — a project with two
   wrapper roots where root #1 is clean and root #2 is dirty would partially
   apply (writing #1 then refusing #2) which violates atomicity.

## Steps

### Step 1 — hand-modified detection (CONTEXT D8; mirrors 0017 PR #47)

The engine content-hashes the **existing v1.17.0 wrapper files** in each
materialised wrapper root and compares against the per-stack baseline of
known v1.17.0 hashes baked into the engine (computed at engine-build time from
the scaffolder's own template tree). The set of fingerprinted files per stack:

| Stack | Fingerprinted files |
|---|---|
| `ts-cloudflare-worker` | `lib-observability.ts`, `middleware.ts` |
| `ts-cloudflare-pages`  | `lib-observability.ts`, `_middleware.ts` |
| `ts-supabase-edge`     | `index.ts`, `middleware.ts` |
| `go-fly-http`          | `observability.go`, `middleware.go` |

- A real materialised wrapper has the generator tokens substituted
  (`{{SERVICE_NAME}}`, sample rates, env-var identifiers, `{{REDACTED_KEYS}}`,
  Go `{{PACKAGE_NAME}}`), so its bytes never match the raw template. The
  engine **canonicalises** the candidate by **structural masking** — replacing
  the substituted VALUE at every known token site with a fixed placeholder,
  applying the identical mask to the template, then hashing. A genuinely
  un-modified-but-substituted wrapper canonicalises to the recorded baseline
  regardless of its values and is classified CLEAN. The masking program (awk)
  is copied verbatim from 0017's `canonicalize_awk` so the two engines share
  one canonicalisation surface.
- **Style is normalised before masking** (mirrors 0017 PR #47): the candidate
  is first folded to one canonical style — single→double quotes, trailing
  semicolons and commas dropped, whitespace runs collapsed. Without this, a
  downstream `.prettierrc` would defeat every masking rule and a clean wrapper
  would be wrongly refused.
- Any hash mismatch ⇒ that wrapper root is classified **dirty** and refused.
- A root that already carries `cron-monitor.ts` / `cron_monitor.go` is
  classified **already-applied** and skipped (idempotency).
- A `ts-react-vite` stack is classified **unsupported** and skipped silently
  (CONTEXT D10: browser bundle has no scheduled handlers).

### Step 1a — refuse-path UX (mirrors 0017 Step 1a)

For every dirty root the engine, regardless of mode:

1. Prints the would-be diff (the user's wrapper file vs the known baseline).
2. Auto-generates `<wrapper-dir>/.observability-0019.patch` capturing the
   would-be ADDITIONS (cron-monitor.* + healthz-snippet.*), so the operator
   can manually splice them after resolving the drift.
3. Prints recovery guidance: **stash / revert** the wrapper drift → **re-run
   0019** on the now-clean wrapper → **inspect** the patch artefacts only if
   merging custom changes back.

The default run then exits non-zero (2) having written nothing but the recovery
patch artefacts; `--allow-partial` proceeds to apply the clean roots.

### Step 2 — apply (clean roots only; 2-pass atomic per PLAN R08)

The engine is structured as **two passes** with an all-clean gate between
them. This is binding under PLAN R08:

**Pass 1 — classify.** Every discovered wrapper root is classified into one
of four buckets:

- `CLEAN`: known-good v1.17.0 canonical hash, no `cron-monitor.*` present.
- `DIRTY`: hand-modified (hash mismatch).
- `ALREADY`: `cron-monitor.*` already present (idempotent re-run).
- `UNSUPPORTED`: react-vite, or wrapper shape the engine can't classify.

**All-clean gate.** If `DIRTY_DIRS` is non-empty, the default mode emits
patch artefacts for every dirty root AND every clean root (so the operator
has the full would-be context) and exits 2 with ZERO files copied.
`--allow-partial` falls through to Pass 2 with the clean roots only.

**Pass 2 — apply.** For each clean root, the engine copies the four new files
from the scaffolder source into the wrapper directory:

| Stack | Files copied |
|---|---|
| `ts-cloudflare-worker` | `cron-monitor.ts`, `healthz-snippet.ts` |
| `ts-cloudflare-pages`  | `cron-monitor.ts`, `healthz-snippet.ts` |
| `ts-supabase-edge`     | `cron-monitor.ts`, `healthz-snippet.ts` (CONTEXT D5b: same files as worker) |
| `go-fly-http`          | `cron_monitor.go`, `healthz_snippet.go` |

The copy is **token-substituted** for `go-fly-http` only (Go package name
must match the surrounding wrapper's `package` declaration). TS stacks copy
verbatim — the new files contain no generator tokens that need
re-materialisation (CONTEXT G1: importable in isolation, no service name in
the source).

The engine does **NOT**:

- Rewrite CLAUDE.md or any `observability:` block (CONTEXT G6).
- Modify any existing v1.17.0 wrapper file (CONTEXT G2 byte-identical;
  PLAN R11 filename-allowlist invariant).
- Merge any new env rows (`SENTRY_CRON_MONITOR_SLUG_*` is operator-supplied
  per-handler; the runbook documents the naming convention).

### Step 3 — version bump

`.claude/skills/agentic-apps-workflow/SKILL.md` `version: 1.17.0 → 1.18.0`,
**only when at least one root actually migrated** OR the no-wrapper /
all-already-applied / react-vite-only paths fired (in which case the project
is genuinely on the 1.18.0 track). A run that migrated zero clean roots
because `--allow-partial` skipped all dirty roots leaves the version
untouched: a repo must never claim 1.18.0 with un-migrated wrappers.

**Idempotency:** `grep -q '^version: 1.18.0$'` — re-bumping is a no-op.

## Rollback

```bash
# Per migrated module-root:
rm -f <wrapper-dir>/cron-monitor.ts <wrapper-dir>/healthz-snippet.ts        # TS
rm -f <wrapper-dir>/cron_monitor.go <wrapper-dir>/healthz_snippet.go        # Go

# Version bump:
sed -i.bak 's/^version: 1\.18\.0$/version: 1.17.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md && \
  rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

No env vars, no CLAUDE.md edits — rollback is a clean file delete.

## Verify / Post-checks

```bash
# New files present (per migrated root):
test -f <wrapper-dir>/cron-monitor.ts    || test -f <wrapper-dir>/cron_monitor.go
test -f <wrapper-dir>/healthz-snippet.ts || test -f <wrapper-dir>/healthz_snippet.go

# Existing v1.17.0 wrapper files UNCHANGED (CONTEXT G2):
git diff --quiet -- <wrapper-dir>/lib-observability.ts \
                    <wrapper-dir>/middleware.ts \
                    <wrapper-dir>/_middleware.ts \
                    <wrapper-dir>/observability.go \
                    <wrapper-dir>/index.ts 2>/dev/null

# Syntactic validation (toolchain-permitting):
tsc --noEmit 2>/dev/null     # TS stacks
go build ./... 2>/dev/null   # Go stack

# Version bumped:
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Skip cases

- **Unsupported stack** (`ts-react-vite`, or shape engine can't classify):
  the root is left untouched, reported as skipped. CONTEXT D10.
- **Project without scheduled handlers** (cparx-shape — a Worker with no
  `scheduled` export): the wrapper still receives `cron-monitor.ts` /
  `healthz-snippet.ts`, but the exports are simply unused. Per CONTEXT
  optional_for — the migration applies; downstream code adopts opportunistically.
- **No wrapper (pre-init):** version bump only, exit 0.
- **Hand-modified:** refused with diff + `.observability-0019.patch` (exit
  non-zero; default mode writes nothing else, including no copies into clean
  sibling roots).
- **Already-applied:** `cron-monitor.*` already exists → skipped silently;
  version bumped if all roots are in the already-applied / unsupported set.

## Notes

- **Why an executable engine, not pure prose.** Same precedent as 0017: the
  hand-modified-refuse semantics and the 2-pass atomic gate are testable
  end-to-end only when the apply is a deterministic script the harness can
  exercise against fixtures. The 6 fixtures (`01-fresh-apply`,
  `02-already-applied`, `03-hand-modified-refuse`,
  `04-no-scheduled-handlers-project`, `05-multi-module-root`,
  `06-mixed-clean-dirty-refuses-all`, `07-react-vite-only`) assert the full
  behaviour, including the atomic refusal property under R08/R09.
- **No baseline-hash JSON file.** Unlike 0017 (which carries
  `migrations/test-fixtures/0017/known-wrapper-hashes.json`), 0019 bakes the
  known v1.17.0 hashes directly into the engine. v1.17.0 is a single point in
  time — the scaffolder's own template tree at the migration's source commit
  IS the baseline — and re-computing at engine start (against
  `$TEMPLATES_DIR/<stack>/<file>`) gives the same answer as a baked-in JSON
  with one fewer file to keep in sync.
- **Mirror, not fork, 0017's canonicaliser.** The `canonicalize_awk` function
  is copied verbatim from 0017's engine. Any future refinement to the
  canonicaliser should land in 0017 first and be back-ported here, not
  diverged.
- **Apply order.** Runs after 0018 (ascending id order is automatic in the
  migration runner). No manual sequencing needed.
- **No spec change.** `implements_spec` stays `0.4.0` on `agentic-apps-workflow`
  and `0.3.2` on `add-observability`. Cron-heartbeat behaviour is host
  discretion under §10.6 + §10.7; mandating it across all destinations is a
  separate future §10.x conversation (CONTEXT N1).
