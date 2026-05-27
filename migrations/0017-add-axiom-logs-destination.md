---
id: 0017
slug: add-axiom-logs-destination
title: "Add Axiom as logs destination (spec §10.8 multi-destination materialisation)"
from_version: 1.15.0
to_version: 1.16.0
applies_to:
  - "<wrapper-dir>/index.{ts,go}"                  # wrapper entry file: inline-Sentry → registry-dispatched (Step 2)
  - "<wrapper-dir>/destinations/"                  # registry + sentry + axiom adapters materialised in (Step 2)
  - CLAUDE.md                                      # observability: block v0.3.0 → v0.4.0 multi-destination (Step 2, anchor-managed)
  - .claude/skills/agentic-apps-workflow/SKILL.md  # version 1.15.0 → 1.16.0 (Step 3)
requires:
  - file: templates/.claude/scripts/migrate-0017-axiom-destination.sh
    install: "vendored in the scaffolder repo; symlinked into $HOME via the same install pattern as add-observability/"
    verify: "test -x $HOME/.claude/skills/agenticapps-workflow/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
  - file: templates/.claude/scripts/migrate-0017-old-wrappers/
    install: "vendored OLD (v0.4.x) wrapper bytes the engine uses as the token-extraction guide; ships with the engine"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/templates/.claude/scripts/migrate-0017-old-wrappers/ts-react-vite/lib-observability.ts"
optional_for:
  - projects without a materialised add-observability wrapper (pre-init)
---

# Migration 0017 — Add Axiom as logs destination

Brings EXISTING downstream projects — which carry the OLD inline-Sentry
observability wrapper (add-observability v0.4.x, the shape that shipped on
`main` before Phase 21) — UP TO the new role-based destination form:
`destinations/{registry,sentry,axiom}.*` + a registry-dispatched wrapper that
routes `logEvent` → the LOGS destination (Axiom by default) and `captureError`
→ the ERRORS destination (Sentry, never Axiom). Sentry-only keeps working for
projects that skip this migration; nothing dual-ships.

This is the HIGHEST-RISK migration in the workflow because it **rewrites the
project's observability wrapper**. The consent / refuse semantics are therefore
non-negotiable: a hand-modified wrapper is NEVER silently overwritten, and a
"failed" run leaves the repo byte-unchanged. To make those semantics testable
end-to-end, the apply is delegated to a vendored executable engine —
`templates/.claude/scripts/migrate-0017-axiom-destination.sh` — rather than to
prose interpretation (the engine is exercised by `test_migration_0017()` in
`migrations/run-tests.sh` against the fixtures under
`migrations/test-fixtures/0017/`). The migration runner invokes the engine;
this markdown documents its contract.

## Pre-flight (hard aborts on failure — ZERO writes)

The engine performs all of the following before mutating anything:

```bash
ENGINE="$HOME/.claude/skills/agenticapps-workflow/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$HOME/.claude/skills/agenticapps-workflow/add-observability/templates"
HASHES="$HOME/.claude/skills/agenticapps-workflow/migrations/test-fixtures/0017/known-wrapper-hashes.json"

bash "$ENGINE" --templates-dir "$TEMPLATES" --hashes "$HASHES"
#   add --allow-partial to opt into applying clean roots while skipping dirty ones.
```

1. **Workflow version gate.** `.claude/skills/agentic-apps-workflow/SKILL.md`
   `version:` must be in `1.12.0`–`1.15.x` (or already `1.16.0` for a clean
   re-run). Anything else → ABORT exit 3, zero writes.
2. **`jq` present** (the engine parses `known-wrapper-hashes.json`). Absent →
   ABORT exit 3.
3. **At least one materialised wrapper.** The engine scans for wrapper entry
   files (`…/observability/index.ts`, `…/_shared/observability/index.ts`,
   `…/observability/observability.go`). If none exist the project is pre-init:
   the engine prints a notice, still bumps the version (the project is on the
   1.16.0 track), and exits 0.
4. **All-clean gate (review #7).** Hand-modified detection (Step 1) runs across
   **all** discovered roots BEFORE any write. If ANY root is hand-modified, the
   DEFAULT behaviour is to ABORT with **zero writes to any root** (exit 2),
   listing every offender plus the clean roots that *would* have migrated.
   Proceed-and-skip-the-dirty-ones is opt-in only via `--allow-partial`, which
   makes partial application a deliberate operator choice and prints a post-run
   applied-vs-skipped summary.

## Steps

### Step 1 — hand-modified detection (§10.7; broadened, review #1)

The engine content-hashes **every file it will rewrite** — at minimum the
wrapper entry file — and compares against the per-stack, per-version baseline in
`migrations/test-fixtures/0017/known-wrapper-hashes.json` (sha256 of the
**canonical / structurally-masked** form of the OLD scaffolded wrapper; see that
file's sibling `HASHING-NOTE.md`).

- A real materialised wrapper has the generator tokens substituted
  (`{{SERVICE_NAME}}`, `{{DESTINATION}}`, the sample rates, the env-var
  identifiers, `{{REDACTED_KEYS}}`, Go `{{PACKAGE_NAME}}`), so its bytes never
  match the raw template. The engine **canonicalises** the candidate by
  **structural masking** — replacing the substituted VALUE at every known token
  site (anchored on the `const NAME =` / interface field / `package` / header /
  array-literal it sits in) with a fixed placeholder, applying the identical
  mask to the template, then hashing. A genuinely un-modified-but-substituted
  wrapper canonicalises to the recorded baseline regardless of its values and is
  classified CLEAN. The same masking program is shared by the baseline
  regenerator (`regen-hashes.sh`) so the two cannot drift.
- Masking is purely structural: any byte **outside** a recognised token site —
  an added import, an altered function body, an extra statement inside the
  redacted-keys array, even a tweak to the non-token text on a token-bearing
  line — survives into the canonical form and changes the digest. An
  unrecognised shape never collapses onto the baseline, so it is treated as
  hand-modified — **fail-closed, never silently overwritten**.
- CLAUDE.md and `.dev.vars` are edited only inside the anchor-managed
  `observability:` range / by appendation (migration 0014 idiom), so they don't
  need a per-file hash — but the `observability:` block must be present and in a
  recognised shape; a block hand-edited away from the known v0.3.0 form causes
  the CLAUDE.md rewrite to no-op rather than clobber.
- Any hash mismatch ⇒ that module-root is classified **dirty** and refused.
- A root that already carries `destinations/registry.ts` / `destinations.go` /
  a `buildRegistry` import is classified **already-applied** and skipped
  (idempotency).

### Step 1a — refuse-path UX (review #1)

For every dirty root the engine, regardless of mode:

1. Prints the would-be diff (the user's wrapper vs the known baseline template).
2. Auto-generates `<module-root>/.observability-0017.patch` capturing that diff.
3. Prints recovery guidance: **stash** the wrapper changes → **re-run 0017** on
   the now-clean wrapper → **re-apply** the `.patch` onto the migrated wrapper.

The default run then exits non-zero (2) having written nothing but the recovery
patch artefacts; `--allow-partial` proceeds to apply the clean roots.

### Step 2 — apply (clean roots only)

For each clean root the engine:

- Recovers the project's real generator-token values (service name, sample
  rates, redacted-keys list, env-var names, Go package) from its existing
  wrapper, using the OLD (v0.4.x) template under
  `templates/.claude/scripts/migrate-0017-old-wrappers/<stack>/` as the
  line-by-line alignment guide, then **materialises** those values into the
  v1.16.0 wrapper template AND the `destinations/{registry,sentry,axiom}.ts`
  (TS) / `destinations.go` (go-fly-http) adapters. It never copies the
  templates verbatim — a verbatim copy leaves `{{TOKENS}}` that do not compile.
  The rewrite is inline-Sentry → registry-dispatched (public interface
  byte-identical per §10.1; only internals move) and the project's values are
  PRESERVED (a customised `TRACE_SAMPLE_RATE` is not reset to a default).
- **Token-free guard (toolchain-independent):** if any `{{token}}` survives
  substitution in the staged wrapper or adapters, the root is refused with ZERO
  writes — a raw template can never ship even where no compiler is available.
- Merges Axiom env rows (`AXIOM_TOKEN`, `AXIOM_DATASET`, `OBS_DESTINATIONS`)
  into a co-located `env-additions.md` and/or `.dev.vars` when present
  (idempotent — skipped if `AXIOM_TOKEN` already there).
- Rewrites the CLAUDE.md `observability:` block to the v0.4.0 multi-destination
  shape (anchor-managed range; stub written to a new CLAUDE.md if absent):

  ```yaml
  observability:
    spec_version: 0.4.0
    destinations: { errors: sentry, logs: axiom, analytics: none }
    policy: <stack-path>/observability/policy.md
    enforcement: { baseline: .observability/baseline.json }
  ```

- **Smoke-build (FATAL)** with `tsc --noEmit` (TS) / `go build ./...` (Go) when
  the toolchain is present: a failed build rolls the root back (restore the
  entry file, remove created adapters) and the run exits non-zero. An absent
  toolchain is a non-fatal skip — the token-free guard above already guarantees
  no raw template shipped.

### Step 3 — version bump

`.claude/skills/agentic-apps-workflow/SKILL.md` `version: 1.15.0 → 1.16.0`,
**only when at least one root actually migrated.** A run that migrates zero
roots — every clean root failed the token-free guard / smoke build, or
`--allow-partial` skipped all dirty roots — leaves the version untouched: a repo
must never claim 1.16.0 with un-migrated wrappers. (The genuine no-wrapper and
all-already-applied paths bump earlier, per Skip cases.) `implements_spec` stays
`0.4.0` (the wrapper runtime contract §10.1–10.7 is unchanged; the
multi-destination shape is a §10.8 project-metadata concern).

**Idempotency:** `grep -q '^version: 1.16.0$'` — re-bumping is a no-op.

## Rollback

```bash
# Per migrated module-root:
rm -rf <wrapper-dir>/destinations/                       # TS adapters
rm -f  <wrapper-dir>/destinations.go                     # Go adapter
git restore <wrapper-dir>/index.{ts,go}                  # wrapper entry file
git restore CLAUDE.md                                    # observability: block
sed -i.bak 's/^version: 1\.16\.0$/version: 1.15.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

**Caveat:** rollback may lose Axiom env vars added between apply and rollback
(`AXIOM_TOKEN`/`AXIOM_DATASET`). Re-paste them from your secrets manager.

## Verify / Post-checks

```bash
# Adapters present + wrapper dispatches via the registry (per migrated root):
test -f <wrapper-dir>/destinations/registry.ts || test -f <wrapper-dir>/destinations.go
grep -q 'buildRegistry' <wrapper-dir>/index.{ts,go}

# CLAUDE.md carries the v0.4.0 multi-destination block:
grep -q 'spec_version: 0.4.0' CLAUDE.md
grep -q 'destinations:.*errors: sentry.*logs: axiom' CLAUDE.md

# Version bumped:
grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# /add-observability scan reports clean (no inline @sentry/* in app code).
```

## Skip cases

- **Unsupported stack** (wrapper shape the engine can't classify): the root is
  left untouched and reported as skipped.
- **No wrapper (pre-init):** version bump only, exit 0.
- **Hand-modified:** refused with diff + `.observability-0017.patch` (exit
  non-zero; default mode writes nothing else).
- **Apply/smoke failure on a clean root:** the root is rolled back (token-free
  guard refuses pre-write with zero writes; a smoke-build failure restores the
  entry + removes created adapters) and the run exits non-zero. Other roots and
  the version bump are unaffected unless every root failed.

## Notes

- **Why an executable engine, not pure prose.** The other CLAUDE.md/skill
  migrations (0014/0015) are prose the update agent interprets, and their
  harness only probes idempotency-check correctness. 0017's risk is in the
  *apply* (overwriting a wrapper) and in *refusing correctly*, so — following
  the precedent of migrations 0005/0006/0010, which ship executable artefacts —
  the apply is a script the harness runs end-to-end. The 10 fixtures assert the
  full behaviour, including the "writes nothing on refuse / default-abort" gate,
  (07) that a realistically-substituted unmodified wrapper canonicalises CLEAN
  and auto-applies token-free with its values preserved, (08) that an
  anchor-wrapped clean wrapper applies, (09) that an all-dirty `--allow-partial`
  run migrates zero roots and does NOT bump the version, and (10) that a clean
  cf-worker applies with each env var landing at its own site (no signature
  collapse in the InitEnv block).
- **Version coverage of the hash baseline.** Only add-observability v0.4.x
  wrapper shapes are baselined (the shape every `from_version: 1.15.0` project
  carries). v0.3.x is documented as out-of-scope in `HASHING-NOTE.md`.
  `ts-cloudflare-pages` has no baseline because it shipped no wrapper before
  1.16.0 — a cf-pages project has nothing to migrate here.
- **Apply order.** Runs after 0016 (ascending id order is automatic in the
  migration runner). No manual sequencing needed.
