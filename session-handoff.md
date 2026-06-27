# Session Handoff — 2026-06-22 (cw 0023 injection-guard migration built; PR pending merge)

## Accomplished
- **Chose option A** (cut a real 2.x-axis migration) and built it:
  `migrations/0023-prompt-injection-defense.md`, `from 2.0.0 -> to 2.1.0`.
  Pre-flight gates on the `injection-guard` skill being installed (no
  auto-install; exit-3 abort with obs `install.sh` pointer). Step 1 **delegates**
  the §14 scaffold to consent-gated `/injection-guard init` (NO inline cp; does
  NOT call obs `migrate-0023.sh` — wrong version axis). Step 2 bumps the installed
  workflow version 2.0.0 → 2.1.0.
- Bumped `skill/SKILL.md` 2.0.0 → 2.1.0 (drift coupling: 0023 is now the
  highest-numbered migration → its `to_version` is the drift target).
- Added test fixtures `migrations/test-fixtures/0023/` (01-bump-when-guard-present,
  02-abort-when-guard-absent, 03-idempotent-reapply) + `test_migration_0023` and a
  dispatcher entry in `migrations/run-tests.sh`, modeled on 0022.
- Deleted the stale `ADD-INJECTION-GUARD-MIGRATION.md` brief (superseded by the
  obs fold-in).
- **Tests green:** full suite `PASS: 153, FAIL: 0`; drift test PASS; 0023 fixtures
  3/3. `gitnexus_detect_changes` = low risk, 0 affected execution flows.

## Decisions
- **Option A over B/C** — only a `from 2.0.0` migration reaches the fleet; every
  live project is at 2.0.0 post-SPLIT, so any `< 2.0.0` tombstone is silently skipped.
- **Delegate, don't inline** — the `injection-guard` skill is the §14 generator;
  the migration just gates + invokes `/injection-guard init`. Keeps cw decoupled
  from §14 asset shapes (they live in obs).
- **Post-check 2 is informational** — if the user declines init's consent gates
  (e.g. non-LLM project), no `injection_guard:` block is written but the version
  still bumps. Declined-state is valid, not a failure.

## Files modified
- `migrations/0023-prompt-injection-defense.md` — new migration (the 2.1.0 release)
- `skill/SKILL.md` — version 2.0.0 → 2.1.0
- `migrations/run-tests.sh` — `test_migration_0023` + dispatcher entry
- `migrations/test-fixtures/0023/**` — 3 fixtures + common-setup.sh
- deleted `ADD-INJECTION-GUARD-MIGRATION.md` (stale brief)
- (pre-existing, NOT in this commit: `.gitignore` understand-anything ignore line)

## Next session: start here
The 0023 migration is built and tested on branch `feat/0023-prompt-injection-defense`.
First action: **commit + open the PR** (if not already done this session), then
merge — that merge IS the claude-workflow 2.1.0 release. After merge, run the
rollout: (1) refresh the **installed** obs clone
`~/.claude/skills/agenticapps-observability` (`git pull` + re-run `install.sh`)
to create the still-missing `~/.claude/skills/injection-guard` symlink — this is
why 0023's preflight-audit verify currently shows informational FAIL on this host;
(2) per project run `/update-agenticapps-workflow` (2.0.0→2.1.0) then
`/injection-guard init`. Downstream factiv hosts (callbot/cparx/fx-signal-agent)
are a separate cross-family engagement.

## Open questions
- README migration index (`migrations/README.md`) is stale (stops at 0012, missing
  0013–0023). Left as pre-existing debt — not touched to avoid partial-backfill
  inconsistency. Worth a separate cleanup pass.
