# Session Handoff — 2026-07-25 (OpenSpec v1 — UNPARKED, ready to merge)

## Status
**PR #95 is OPEN, green, mergeable — waiting only on the owner's call to merge.**
https://github.com/agenticapps-eu/claude-workflow/pull/95
Branch `feat/bind-openspec-v1` · 16 commits · 0 behind main · tree clean, pushed.
Suite 198 PASS / 0 FAIL · CI `gate` + `migrations-and-snapshot` both green.

The park is over. Core published the canonical gate (`ae90483`, core#33,
ADR-0022) and this repo has adopted it. The divergence this branch carried is
closed, not deferred.

## Accomplished this session
- **Re-vendored `bin/openspec-change-gate.sh`** from
  `agenticapps-workflow-core/reference-implementations/openspec-change-gate/`.
  1.1.0 → 1.2.0, byte-identical to core. **28/28** on the conformance harness,
  proven again on the CI runner — was 25/28.
- **Vendored `tools/change-gate-conformance.sh`**; CI scores the gate before
  trusting its verdict. The `gate` job is no longer trivially green.
- **`OPENSPEC_GATE_SELF=claude`** exported by both hook shims, deliberately not
  by `pre-commit`/CI (host-agnostic surfaces — a human commit is not a claude
  review). Matches core's wiring.
- **Parity guard repointed and hardened** — core landed at
  `reference-implementations/`, not the `gate/` path the guard predicted, so it
  would have reported `NOT-PUBLISHED` forever against a canonical copy that
  exists. Now enforces byte-identity, treats a missing canonical as FAIL, and
  also asserts harness parity (a stale harness certifies a stale gate).
- `bin/GATE-DIVERGENCE.md` deleted — the guard fails if the record outlives the
  fork. Reported on #96 and core#34.

## Decisions
- **Re-vendor, never hand-merge** — the three failing rows were exactly what
  re-vendoring closes, and three of the four bypasses core's Stage-2 review
  caught were introduced *by* a hand-merge upstream.
- **Kept the recorded-divergence machinery** in `run-tests.sh` rather than
  deleting it with the record. A future divergence is possible; the escape hatch
  should stay bounded and visible, not be re-invented under pressure.
- **Did not merge #95.** Shipping a breaking 3.0.0 is the owner's call, not a
  step a session should take on its own authority.

## Files modified
- `bin/openspec-change-gate.sh` — re-vendored, 1.2.0
- `tools/change-gate-conformance.sh` — NEW, vendored from core
- `bin/GATE-DIVERGENCE.md` — DELETED (fork closed)
- `templates/.claude/hooks/openspec-change-gate.sh`,
  `setup/snapshot/hooks/openspec-change-gate.sh` — export `OPENSPEC_GATE_SELF`
- `migrations/run-tests.sh` — parity guard repointed + harness parity row
- `.github/workflows/openspec-gate.yml` — conformance step
- `CHANGELOG.md` — gate bullet rewritten; harness entry added

## Next session: start here
**Ask the owner whether to merge #95, then merge it** — nothing technical is
outstanding on the branch. After merging, the fleet work is what remains: three
other hosts still carry the bypassed gate (codex #26, opencode #15 at 16/28, pi
#11 at 18/28), and until every installer writes 1.2.0 the shared
`~/.agenticapps/bin/` path stays last-writer-wins. This host can now only raise
that copy, never lower it, so the hazard is one-directional rather than closed.

## Open questions
1. **Consumer repos get no CI workflow.** Migration 0032 installs the shim and
   the `pre-commit` hook, but not the CI floor — so `--no-verify` bypasses the
   only floor a scaffolded project has. Flagged on core#34 as a gap in the
   vendoring steps (hosts scaffold; the gate has to reach the scaffolded repo).
   Needs its own issue + decision: not every consumer is on GitHub Actions.
2. Should this repo dogfood its own gate (`openspec init` here)? Now partly
   moot — the `gate` CI job does real work via the harness — but the `--ci` mode
   still proves nothing here without an `openspec/` slot.
3. `.planning/` (35 phase dirs) still needs the supervised Tier-2 fold into
   `openspec/specs/`. Explicitly out of 0032's scope.
4. CodeRabbit was rate-limited on every run — its ✅ is not a second opinion.
   Real coverage was codex + gemini + my own pass.
5. Deferred codex findings, all recorded, none blocking: idempotency checks
   describe partial end states · rollback recipes over-delete · `find` errors
   read as "no active change" · no-jq path misses `notebook_path` ·
   newline-in-filename handling · no `timeout` binary on stock macOS.

## Then: remaining hosts
Prompt 01 still to run for `codex-workflow` and `pi-agentic-apps-workflow`
(opencode done). Their hook surfaces are the least-proven: codex's `apply_patch`
matcher and pi's hook mechanism.
