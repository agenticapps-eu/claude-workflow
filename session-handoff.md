# Session Handoff — 2026-05-16 (PRs #34 + #35 both merged; scaffolder at v1.12.0)

## Status snapshot

- **claude-workflow PR #34** **MERGED** as squash commit `6f35aad`
  on `main`. v0.3.2 of `add-observability` skill (REDACTED_KEYS
  expansion + ts-react-vite re-export fix) shipped. CodeRabbit's 3
  actionable nits (2× MD040, 1× v0.3.3 → v0.3.2 factual) addressed
  in commit `11edac9` before merge.
- **claude-workflow PR #35** **MERGED** as squash commit `2459f3c`
  on `main`. Migration 0013 + 5 fixtures + 0011 retro-note +
  scaffolder bump 1.11.0 → 1.12.0 + Phase 15 smoke updates + CHANGELOG
  `[1.12.0]` opened + `[1.11.0]`/`[1.10.0]` date-stamped. Merged
  without waiting for CodeRabbit (per explicit user direction); the
  full suite was PASS=136 FAIL=0 at merge time.
- **Dev-machine sync needed**: `~/.claude/skills/agenticapps-workflow/`
  is still at v1.11.0 (pre-PR-#35). Pull from main before invoking
  `/update-agenticapps-workflow` against any downstream project so
  the consuming agent sees v1.12.0's 0013 migration.

## Next session: start here

### 1. Sync local scaffolder install

```bash
cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only
grep '^version:' skill/SKILL.md  # expect: version: 1.12.0
```

### 2. Run 0013 against cparx adoption (carried forward from prior handoff)

cparx is still at workflow v1.9.3 with the dirty WIP state restored
from the stash (per the discarded-7-commit-branch decision in the
prior session). Now that 0013 is shipping, the cparx adoption path
becomes:

```bash
cd ~/Sourcecode/factiv/cparx
# Stash unrelated WIP first if dirty
claude /update-agenticapps-workflow
# Migration 0011 pre-flight aborts (no observability:) → run init →
# re-run /update — applies 0011 + 0012 + 0013 in one go.
#
# NOTE: cparx is at v1.9.3; 0013 only auto-inits FROM v1.11.0+.
# So cparx still goes through the two-/update flow this time.
# Future projects starting from v1.11.0+ (or fresh installs that
# land directly on v1.12.0) skip the two-/update step.
```

For cparx specifically, the cleaner path (proven on the discarded
branch but to be re-executed against fresh main) is:

1. Manually remove `.claude/skills/add-observability/` (0013 would
   automate this from v1.11.0+ but cparx is at v1.9.3 still)
2. `claude /add-observability init` (Phases 1-9; templates correct
   per F2 fix in PR #34)
3. `claude /update-agenticapps-workflow` (applies 0011 + 0012 + 0013)
4. `claude /add-observability scan --update-baseline`
5. `claude /add-observability scan-apply --confidence high` (this
   step was NOT in the discarded branch — it's the actual gap
   remediation, ~14 high-confidence fixes across cparx app code)

Each step commits atomically per the cparx report's pattern.

### 3. After cparx adoption succeeds → fx-signal-agent

Same flow. Check workflow version first:

```bash
grep '^version:' ~/Sourcecode/agenticapps/fx-signal-agent/.claude/skills/agentic-apps-workflow/SKILL.md
```

- v1.9.x → same two-update path as cparx today.
- v1.11.0+ → 0013 handles vendored cleanup AND auto-init in one
  `/update-…` invocation.

### 4. Plausible follow-ups (after #35 lands)

- **F3 from cparx report**: go-fly-http multi-binary entry detection.
  Post-candidate-selection HTTP-shape verification. `add-observability`
  v0.3.3 or v0.4.0. Low severity, no migration needed.
- **`test_init_fixtures()` harness**: Phase 15 F4. The 0013 fixtures
  exercise the migration's pre-flight + idempotency contracts but
  not the 7 init fixture pairs themselves. F2 (now fixed in v0.3.2)
  was direct evidence for why a harness that diffs
  `before/` → `expected-after/` matters. Worth a dedicated phase
  for v1.13.0.
- **`policy:` multi-stack support**: cparx-style dual-stack repos
  ship only the primary stack's path in CLAUDE.md (per spec §10.8
  scalar `policy:`). Future spec amendment + matching parser change
  could add `policies: [path1, path2]` array form. Out of scope for
  0013.

## Open questions (carried forward)

- **Authoritative baseline.json for cparx**: hand-authored counts on
  the discarded branch were conservative. Real adoption should run
  `claude /add-observability scan --update-baseline` for authoritative
  numbers.
- **`enforcement.ci:` field**: still omitted by default. v1.10.0
  Option-4 stance carried forward. The opt-in CI workflow remains
  copy-paste from `add-observability/enforcement/observability.yml.example`.
- **CI workflow wiring for `--strict-preflight`**: flag exists; no
  GHA workflow uses it yet. Could land alongside any future migration
  if you want to gate the suite on strict-preflight.
- **Carried from prior sessions**: Residual #32 formal §1-§8
  conformance audit doc; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`; fx-signal-agent v1.10.0 adoption verification.
