# Design — Materialize the setup snapshot + structural drift guard as authority

**Date:** 2026-07-01
**Issue:** #74
**Status:** Approved (design), pending implementation
**Related:** ADR-0036 (snapshot install), PR #72 (snapshot feature), PR #75 (setup fail-closed guard)

## Problem

`setup/snapshot/` (ADR-0036) shipped as a raw **seed** and cannot be
materialized, so `migrations/check-snapshot-parity.sh` is permanently red and
`/setup-agenticapps-workflow` can only install a known-incorrect baseline.

Two root causes:

1. **The seed lags reality.** `setup/snapshot/` was seeded from `templates/` +
   `skill/SKILL.md`, which themselves lag migrations (0015 ts-declare-first,
   0023 injection-defense) and even older ones — the snapshot's
   `claude-settings.json` is missing the `multi-ai-review-gate.sh` binding
   (migrations 0005/0016), carries template-only keys (`_comment`,
   `_enforcement_contract`), and its `planning-config.json` lacks the `.workflow`
   block and uses the stale `observability:scan` key (end-state is
   `add-observability:scan`).

2. **The intended honesty mechanism is impossible.** `bin/build-snapshot.sh`
   replays the chain via
   `vendor/agenticapps-shared/migrations/lib/apply.sh` — a file that exists in
   **no ref** of `agenticapps-shared` and was never authored. A deterministic
   shell `apply.sh` is infeasible anyway: the chain includes `AskUserQuestion`
   (0000-baseline) and agent-only delegation (0023 → `/injection-guard init`).
   Prose migrations cannot be replayed by a shell script.

## Decision (approach B)

Abandon the shell-replay mechanism. Make the **structural** parity check the
authoritative, CI-runnable honesty guard, and bring the snapshot to the true
latest end-state.

- **Regeneration is agent-assisted, not a shell replay.** Snapshot artifacts are
  derived from their sources of truth (`templates/` + `skill/SKILL.md` + each
  migration's documented end-state + the guard's factiv-derived invariants), not
  by executing `apply.sh`.
- **`check-snapshot-parity.sh` (structural layer) is the authority.** It runs in
  CI with no scaffolder/agent/network, validating the snapshot against end-state
  invariants. "Green" means "matches latest end-state."

Rejected: authoring `apply.sh` (approach A) — infeasible for prose/agent/
`AskUserQuestion` migrations, and cross-repo.

## Components

### 1. Materialize the snapshot to green
Bring every `setup/snapshot/` file to the real latest end-state so
`check-snapshot-parity.sh` passes with zero FAILs. Known deltas:

- `claude-settings.json`: add the `multi-ai-review-gate.sh` Stop/PreToolUse
  binding; remove template-only `_comment` and `_enforcement_contract` keys.
- `planning-config.json`: add the `.workflow` block; rename `observability:scan`
  → `add-observability:scan`.
- Reconcile all other files (hooks, scripts, skill SKILL.md @ 2.1.0,
  workflow.md, reference block, ADR template, VERSION) against their source of
  truth; confirm hook presence + hashes and the 0015/0023 feature markers.

Source of truth precedence: the guard's asserted invariants (factiv-derived) →
`templates/` latest → migration end-state prose. Where `templates/` itself lags,
fix the snapshot to the end-state the guard/migrations require (do **not** widen
scope to also re-sync `templates/` unless a snapshot file has no other source).

### 2. Fix `bin/build-snapshot.sh`
Remove the `apply.sh` dependency (it must never reference a non-existent file).
Repurpose as a **deterministic assembler**: copy the mechanically-sourced
artifacts from `templates/` + `skill/SKILL.md` into `setup/snapshot/`, stamp
`VERSION` from `skill/SKILL.md`, then run `check-snapshot-parity.sh` and report
residual drift for agent/manual attention (the end-state files that aren't
mechanically derivable). `--check` mode = assemble to a temp dir + diff, no
write. Exit non-zero on any residual drift.

### 3. Amend docs
- `docs/decisions/0036-snapshot-install.md`: the authoritative guard is the
  CI-runnable structural check, not a shell replay; record that `apply.sh` was
  rejected as infeasible for prose migrations, and that regeneration is
  agent-assisted.
- `setup/snapshot/MANIFEST.md`: flip the "⚠️ Seed vs verified" section to
  **verified**; document the regeneration procedure (component 2 + agent step).

### 4. Strengthen the structural guard (only as needed)
Ensure `check-snapshot-parity.sh` is comprehensive enough to be authoritative.
It already checks: required files, VERSION stamp, JSON validity, settings hook
bindings, planning-config key shape, hook presence + hashes, and 0015/0023
feature markers. Add any missing end-state invariant surfaced while
materializing (component 1). Keep it scaffolder-free and network-free so CI runs
it unchanged.

### 5. CI wiring
Add `.github/workflows/ci.yml` (the `.github/` dir does not exist yet) running,
on every PR + push to `main`:
- `bash migrations/run-tests.sh` (existing suite; expects PASS, FAIL=0)
- `bash migrations/check-snapshot-parity.sh` (drift guard; must exit 0)

Runner: `ubuntu-latest` with `bash`, `jq`, `git` (no scaffolder/GSD/gstack — the
structural layer does not need them; the full-replay layer is gone).

## Integration with PR #75

PR #75 (setup fail-closed guard) is complementary and must ship with or before
this work: once the snapshot is green, the guard passes and setup proceeds
normally; the guard remains a permanent safety net. Resolution: rebase this
branch onto #75 (or merge #75 first, then rebase), so the final PR contains both
the guard and the green snapshot. The guard is **not** removed.

## Testing

- `bash migrations/check-snapshot-parity.sh` exits **0** (was 1).
- `bash migrations/run-tests.sh` stays green (PASS ≥ 153, FAIL = 0).
- `bash bin/build-snapshot.sh --check` exits 0 against the materialized snapshot
  (no residual drift), and references no missing file.
- CI workflow validated (locally simulate the two commands; confirm YAML parses).
- Spot-check: the setup skill's Step-5 post-checks would pass against the green
  snapshot (settings.json valid + bindings present, planning-config `.workflow`
  present, 0015/0023 markers present).

## Out of scope (YAGNI)

- No `apply.sh` / deterministic shell replay engine.
- No changes to the `update` (migration) path.
- No reshaping of existing migrations.
- No broad `templates/` re-sync beyond what a snapshot file with no other source
  requires.

## Done when

- `check-snapshot-parity.sh` is green and CI enforces it on every PR.
- `build-snapshot.sh` references no missing file and regenerates/validates the
  snapshot honestly.
- ADR-0036 + MANIFEST reflect the structural-guard authority; #75 guard retained.
- Issue #74 closed.
