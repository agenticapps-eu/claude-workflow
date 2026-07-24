# Session Handoff — 2026-07-24 (bind OpenSpec v1 — prompt 01, claude host)

## Status: COMPLETE on branch `feat/bind-openspec-v1` (6 commits). NOT pushed, no PR.
Suite 186 PASS / 0 FAIL · snapshot parity PASS · all 4 acceptance criteria verified.

## Accomplished
Ran `agenticapps-workflow-core/prompts/01-host-bind-openspec.md` with `{{HOST}}=claude`.
Mirrors the `opencode-workflow` precedent (its 6 commits `52da974..cee1a8d`).

- **§18 gate** — ported canonical `gate/openspec-change-gate.sh` from workflow-core into
  `bin/`, plus `run-plan-review.sh` (producer), `bin/git-hooks/pre-commit`, and
  `.github/workflows/openspec-gate.yml`. Verified against every row of §18's truth table.
- **GitNexus removed** from every live surface (payload, settings bindings, `.gitnexus/`).
- **Gates collapsed** onto the §17 lifecycle in `templates/config-hooks.json`; PreToolUse
  rebound from `multi-ai-review-gate.sh` to an `openspec-change-gate.sh` shim.
- **Instruction surface retargeted** — `skill/SKILL.md` → 3.0.0 / spec 1.0.0, new
  `docs/WORKFLOW.md`, `CLAUDE.md` Development Workflow section.
- **Migration 0032** (2.9.0 → 3.0.0) + 5 fixtures + an apply-parity guard.
- **install.sh** gained `--dry-run`; setup/update skills are OpenSpec-aware.
- **ADR-0044**, CHANGELOG 3.0.0, GSD binding standard marked SUPERSEDED.

## Decisions
- **Historical migrations retained, their TESTS retired.** 0005/0007/0016/0026/0031 lost
  their subject. Deleting the docs would break replay for pre-3.0.0 repos; stubbing the
  payload (the 0011/SPLIT-03 precedent) would only test the stub. Each now asserts two
  invariants: the doc is on disk, and no payload ships. A revert fails the suite.
- **`setup/SKILL.md` KEEPS the §11 anchor alternation** (`^## ` OR `gitnexus:start`).
  Dead for us, load-bearing for any consumer installed before 3.0.0 — dropping it would
  recreate migration 0029's data-loss bug on repos least likely to notice.
- **0001 + 0027 made shape/version tolerant** rather than retired: their gates still
  exist, just relocated. 0027 sources its section from the LIVE scaffolder, so pinning
  the version there would break replay on every future spec bump.
- **0032 does not touch `.planning/`** — phases→capabilities is many-to-one and a wrong
  merge writes a false promise into the spec slot. Supervised job, not a script.
- **0032 does not strip a consumer's `gitnexus:start` region** — §11-adjacent surgery,
  and inert once the engine is gone.

## Files modified
62 files, +2553/−2292. Highlights:
- `bin/{openspec-change-gate,run-plan-review}.sh`, `bin/git-hooks/pre-commit` — NEW
- `templates/config-hooks.json` — hooks tree → §17 `lifecycle` block
- `templates/.claude/hooks/openspec-change-gate.sh` — NEW shim; `multi-ai-review-gate.sh` deleted
- `migrations/0032-bind-openspec-v1.md` + `test-fixtures/0032/**` — NEW
- `migrations/run-tests.sh` — `retired_migration` helper, 0032 harness, tolerant predicates
- `migrations/check-snapshot-parity.sh` — gitnexus checks INVERTED (absence asserted)
- `skill/SKILL.md`, `CLAUDE.md`, `docs/WORKFLOW.md`, `setup/SKILL.md`, `update/SKILL.md`,
  `install.sh`, `docs/decisions/0044-*.md`, `CHANGELOG.md`

## Next session: start here
Push `feat/bind-openspec-v1` and open a PR to main, then run `/gsd-review` (codex) on the
diff before merging — memory `gsd-review-non-skippable` applies, and this is the largest
migration in the chain. Use neutral correctness framing, not security framing
(`codex-review-cyber-filter`), and pipe `< /dev/null` (`codex-exec-stdin-hang`). After
merge, `git pull` the local scaffolder clone at `~/.claude/skills/agenticapps-workflow`
(`local-scaffolder-clone`), then repeat prompt 01 for the remaining hosts —
`codex-workflow` and `pi-agentic-apps-workflow` (opencode is already done).

## Open questions
1. **The gate is installed but this repo has no `openspec/` slot yet.** `install.sh` would
   create it; I did not run a non-dry-run install. Dogfooding it here means this repo's own
   future changes go through propose→validate→review — worth doing deliberately, not by
   accident mid-PR.
2. `.planning/` (35 phase dirs) still needs the supervised Tier-2 fold into
   `openspec/specs/` capabilities. Explicitly out of 0032's scope.
3. opencode + pi hook surfaces remain UNCONFIRMED upstream (wiring.md); irrelevant to the
   claude host but blocks completing prompt 01 for pi.
4. Two informational preflight-audit failures pre-date this work (`0008` coverage endpoint,
   `0011` observability path) — not counted in suite totals, unchanged by this branch.
