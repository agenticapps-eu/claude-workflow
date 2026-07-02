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

## Provenance findings (2026-07-01)

Investigation against a real install (factiv cparx) showed the guard was built
by naïvely diffing factiv's live `.planning/config.json` / `.claude/settings.json`,
so **two of its four failing assertions are the guard's own bug**, not snapshot
staleness:

| Guard assertion | Ground truth | Verdict |
|---|---|---|
| settings.json binds `multi-ai-review-gate.sh` | cparx has it in **settings.json**; template/snapshot lack it | **RIGHT — real gap** (0005/0016) |
| no template-only `_comment`/`_enforcement_contract` | cparx settings.json strips them | **RIGHT — snapshot must be the stripped installed shape** |
| config has `.workflow` block | `.workflow` is **GSD's own config** (`research`/`plan_check`/`verifier`/`code_review`…), written by GSD, not any AgenticApps migration | **WRONG — GSD-owned, not the snapshot's to ship** |
| `add-observability:scan` (not `observability:scan`) | factiv's value is the **stale pre-0022 ref**; 0022 repointed `add-observability`→`observability`; the guard even states the rename direction inverted | **WRONG — enshrines stale factiv state** |

The AgenticApps snapshot legitimately owns only the `hooks` section of
`.planning/config.json`; GSD merges `.workflow` at its own init. The forward-
canonical observability id is `observability:scan` (what the template already
has).

## Components

### 1. Fix the guard's two miscalibrated assertions
In `migrations/check-snapshot-parity.sh`:
- **Remove the `.workflow` requirement** (§3). Replace with a comment: the
  snapshot owns only `hooks`; `.workflow` is GSD-owned and merged at GSD init.
- **Fix the observability assertion** (§3) to accept the current
  `observability:scan` (pass if `observability:scan` OR `add-observability:scan`
  present; the obs repo keeps `add-observability` as an alias). Correct the
  inverted rename comment.

### 2. Fill the two real snapshot gaps (via `templates/`, the source)
- Add the `multi-ai-review-gate.sh` binding to `templates/claude-settings.json`
  (its source), matching the shape migration 0005 installs and verified against
  cparx: a `PreToolUse` entry, `matcher: "Edit|Write|MultiEdit"`, command
  `$CLAUDE_PROJECT_DIR/.claude/hooks/multi-ai-review-gate.sh`.
- The snapshot's `claude-settings.json` is the **installed shape**: template
  settings minus the template-only `_comment`/`_enforcement_contract` keys, plus
  the binding above. This transform is deterministic (`jq`).
- All other snapshot files copy 1:1 from their source (`templates/` +
  `skill/SKILL.md` @ 2.1.0); `planning-config.json` = `templates/config-hooks.json`
  as-is (keeps `observability:scan`, owns only `hooks`).

### 3. Rewrite `bin/build-snapshot.sh` as a deterministic assembler
With the guard corrected, the snapshot is fully mechanically derivable — no
`apply.sh`, no agent. Rewrite `build-snapshot.sh` to:
- copy each `templates/…` + `skill/SKILL.md` source to its snapshot path per the
  MANIFEST mapping,
- produce `claude-settings.json` via the deterministic `jq` transform (strip the
  two template keys; ensure the multi-ai binding present),
- stamp `VERSION` from `skill/SKILL.md`,
- run `check-snapshot-parity.sh` at the end.
`--check` = assemble into a temp dir and diff against `setup/snapshot/`, no
write, non-zero on drift. It must reference no non-existent file.

### 4. Amend docs
- `docs/decisions/0036-snapshot-install.md`: the authoritative guard is the
  CI-runnable structural check, not a shell replay; record that `apply.sh` was
  rejected as infeasible for prose migrations, and that with the guard corrected
  the snapshot is deterministically assembled from `templates/`.
- `setup/snapshot/MANIFEST.md`: flip the "⚠️ Seed vs verified" section to
  **verified**; document the deterministic regeneration procedure (component 3).
- `setup/SKILL.md` Step 4d: the snapshot supplies only the `hooks` section;
  setup must **merge** it into any existing `.planning/config.json` (preserving a
  GSD-written `.workflow` block), not overwrite the file.

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
