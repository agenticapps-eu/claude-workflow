# Session Handoff — 2026-05-13 (phases 08, 09, 10 + housekeeping)

## Accomplished

Shipped THREE migrations through the full GSD pipeline end-to-end in one
session, plus pushed/merged the predecessor 0008/0009/0010 batch and
closed the carry-over draft. Scaffolder advanced from **1.7.0 → 1.9.3**
across the day.

| PR | Title | Merge |
|---|---|---|
| #10 | feat: vendor CLAUDE.md workflow block (0009, v1.8.0) | `f77a205` |
| #13 | feat: migrations 0008 (Coverage Matrix) + 0010 (post-process GSD markers), v1.9.0 | `20bcfdf` |
| #9  | fix: bootstrap .claude/settings.json in baseline + self-heal in 0004 | `b94de20` |
| #14 | feat: migration 0005 — multi-AI plan review enforcement gate (v1.9.1) | `33ab559` |
| #15 | feat: migration 0006 — LLM wiki compiler integration (v1.9.2) | `af21388` |
| #16 | feat: migration 0007 — GitNexus code-graph MCP integration (v1.9.3) | `a55ec60` |
| #12 | draft: carry-over 0005-0007 | **closed** (split across 14/15/16) |

Each of phases 08, 09, 10 followed the same discipline: CONTEXT → RESEARCH
(≥2 alternatives) → PLAN (TDD tasks + threat model + goal-backward) →
multi-AI plan review (codex + gemini dogfood) → BLOCK fixes → TDD
red/green → Stage 1 + Stage 2 + CSO post-execution reviews → fix
findings → non-draft PR → squash-merge.

## Decisions (cross-phase patterns that emerged)

- **Multi-AI review dogfood works.** Codex flagged real bugs in every
  phase (Phase 08 B1-B4, Phase 09 B1-B3, Phase 10 B1-B3). The discipline
  caught silent-false-green patterns and structural inconsistencies
  before execution. Worth the cost.
- **Stage 2 + CSO consistently caught H1-class bugs.** The `sed && rm`
  / `jq && mv` `&&`-chain under `set -e` pattern recurred across phases.
  Each phase's CSO/Stage 2 caught it again; each subsequent phase carried
  the lesson forward. Worth codifying in a workflow lint.
- **Scope reduction for Phase 10**: original 0007 draft would have run
  30-90 min of `gitnexus analyze` per migration apply. Stripped to setup-
  only — install script registers MCP entry, helper script ships for
  user-initiated indexing. Cleaner contract, sandboxable, license-honest.
- **Fixture matrix grew with each phase** as multi-AI review caught new
  edge cases: Phase 08 had 11, Phase 09 had 15, Phase 10 had 18.
- **Preserve-data rollback** is the right default across all three.
  Phase 09 set the pattern (RESEARCH §3); Phase 10 carried it forward
  (gitnexus rollback removes MCP entry + version bump only).

## Files modified (key shippable artifacts)

Across phases 08+09+10 + housekeeping merges:

- `migrations/0005-multi-ai-plan-review-enforcement.md` (multi-AI review gate)
- `migrations/0006-llm-wiki-builder-integration.md` (LLM wiki)
- `migrations/0007-gitnexus-code-graph-integration.md` (GitNexus MCP)
- `templates/.claude/hooks/multi-ai-review-gate.sh` (hook 6 — PreToolUse)
- `templates/.claude/scripts/install-wiki-compiler.sh` + rollback
- `templates/.claude/scripts/install-gitnexus.sh` + rollback + index-family-repos.sh helper
- `migrations/test-fixtures/{0005,0006,0007}/` — 13 + 15 + 18 fixtures
- `migrations/run-tests.sh` — 3 new stanzas (test_migration_0005/0006/0007)
- `docs/decisions/0018-multi-ai-plan-review-enforcement.md`
- `docs/decisions/0019-llm-wiki-compiler-integration.md`
- `docs/decisions/0020-gitnexus-code-graph-integration.md`
- `migrations/README.md` — index rows for 0005/0006/0007 promoted
- `CHANGELOG.md` — `[1.9.1]`, `[1.9.2]`, `[1.9.3]` sections with explicit license blocks
- `skill/SKILL.md` — version 1.9.0 → 1.9.3
- `.planning/phases/{08,09,10}-*/` — full GSD artifact sets per phase

## Next session: start here

Three carry-over follow-ups remain, all surfaced by reviews + tracked but
deferred to a 1.9.1.1 / 1.9.4 patch series:

1. **Phase 08 carry-over** (CSO H1 retroactive): migration 0005's
   `sed && rm .bak` chain has the same bug Phase 09 + 10 fixed in their
   own scripts. Apply the explicit if/then/else pattern to 0005's
   install + rollback steps.
2. **CSO M2 follow-up** for 0006: pin the vendored `ussumant/llm-wiki-compiler`
   plugin to a tag + SHA-256 (supply-chain hardening). Same approach for
   gitnexus pinning in 0007 (CSO M2 there: `claude.json` MCP entry uses
   `gitnexus` global binary, but the user's `npm install -g gitnexus` is
   unpinned). Sketch in respective ADRs.
3. **Phase 10 deferred FLAGs**: fixture 13 cosmetic rename; helper script
   `GITNEXUS_BIN` env-override warning; symlinked `~/.claude.json` edge
   case. None of these break anything; tracked in REVIEW.md.

Recommended first action next session: pressure-test all three migrations
end-to-end on a real consumer repo (`~/Sourcecode/factiv/cparx`) via
`/update-agenticapps-workflow --dry-run --from 1.7.0`. Confirms the 0008
→ 0009 → 0010 → 0005 → 0006 → 0007 application chain runs cleanly.

## Open questions

- **Should the workflow add a shell-lint hook** that catches the
  `&& rm` / `&& mv` chain pattern under `set -e`? CSO H1 has fired in
  three consecutive phases now. Time to make it structural.
- **Multi-AI plan review CLI choice**: currently using `codex exec` +
  `gemini -p`. The migration 0005 pre-flight requires ≥2 of
  `gemini|codex|claude|coderabbit|opencode`. On this dev machine the
  coderabbit + opencode CLIs are absent. Should the workflow ship a
  setup-doc for installing them, or is "any 2" sufficient?
- **Helper script license consent**: `bash index-family-repos.sh`
  surfaces a `⚠ LICENSE` block in usage, but a user who reads the
  warning and runs `--all` is implicitly accepting PolyForm Noncommercial
  for every repo touched. Worth requiring a `--accept-license` first-time
  flag? Tracked but not implemented.
