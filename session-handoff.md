# Session Handoff — 2026-05-14 (phases 08-10 shipped + chain-gap discovered)

## Accomplished

Shipped THREE migrations through the full GSD pipeline end-to-end across
this session, plus pushed/merged the predecessor 0008/0009/0010 batch and
closed the carry-over draft. Scaffolder advanced from **1.7.0 → 1.9.3**.

| PR | Title | Merge |
|---|---|---|
| #10 | feat: vendor CLAUDE.md workflow block (0009, v1.8.0) | `f77a205` |
| #13 | feat: migrations 0008 (Coverage Matrix) + 0010 (post-process GSD markers), v1.9.0 | `20bcfdf` |
| #9  | fix: bootstrap .claude/settings.json in baseline + self-heal in 0004 | `b94de20` |
| #14 | feat: migration 0005 — multi-AI plan review enforcement gate (v1.9.1) | `33ab559` |
| #15 | feat: migration 0006 — LLM wiki compiler integration (v1.9.2) | `af21388` |
| #16 | feat: migration 0007 — GitNexus code-graph MCP integration (v1.9.3) | `a55ec60` |
| #12 | draft: carry-over 0005-0007 | **closed** (split across 14/15/16) |

Each of phases 08, 09, 10 followed full GSD discipline: CONTEXT → RESEARCH
(≥2 alternatives) → PLAN (TDD + threat model + goal-backward) → multi-AI
plan review (codex + gemini dogfood) → BLOCK fixes → TDD red/green →
Stage 1 + Stage 2 + CSO post-execution reviews → fix findings → PR →
squash-merge.

Plus end-of-day **cparx dry-run** revealed a real chain-integrity bug
(see Next session).

## Decisions (cross-phase patterns)

- **Multi-AI review dogfood works.** Codex flagged real bugs in every
  phase (08 B1-B4, 09 B1-B3, 10 B1-B3). Worth the cost.
- **Stage 2 + CSO consistently caught H1-class bugs.** The
  `sed && rm` / `jq && mv` `&&`-chain under `set -e` pattern recurred
  across phases — each `cmdA && cmdB` short-circuits silently and `set -e`
  doesn't fire on the outer expression. Worth codifying as a workflow lint.
- **Scope reduction for Phase 10** stripped 0007 from "install +
  setup + 30-90 min mass-indexing" down to setup-only (install script +
  helper script). Cleaner contract, sandboxable, license-honest.
- **Fixture matrix grew with each phase**: 13 (0005) → 15 (0006) → 18 (0007).
- **Preserve-data rollback** is the right default across all three.

## ⚠ Next session — chain-gap cleanup (Phase 11)

The cparx dry-run surfaced a real bug: **the migration chain on main has
a gap AND a collision** that block cparx-at-v1.5.0 (and any project on
that version line) from progressing to 1.9.3.

```
CURRENT (broken)              PROPOSED (Phase 11 fix)
0001  1.2 → 1.3               0001  1.2 → 1.3
0004  1.3 → 1.4               0004  1.3 → 1.4
0002  1.4 → 1.5               0002  1.4 → 1.5
[GAP 1.5 → 1.7]               0008  1.5 → 1.6   ← re-anchor (was 1.7→1.8)
0008  1.7 → 1.8  ─┐ collision 0009  1.6 → 1.8   ← re-anchor (was 1.7→1.8;
0009  1.7 → 1.8  ─┘                              skip 1.7 — to_version need
0010  1.8 → 1.9                                  not be from+0.1)
0005  1.9 → 1.9.1             0010  1.8 → 1.9   (unchanged)
0006  1.9.1 → 1.9.2           0005-0007 unchanged
0007  1.9.2 → 1.9.3
```

Why re-anchoring 0008/0009 is the cleanest fix:
- **0008 (Coverage Matrix Page)** is workflow-repo only — the dashboard
  surface doesn't change consumer-project state. Re-anchoring its
  version is functionally harmless.
- **0009 (Vendor CLAUDE.md sections)** does the same work regardless
  of version. The to_version jump 1.6 → 1.8 (skipping 1.7) is unusual
  but supported — the migration runner matches on `from_version`.
- Resolves the 0008/0009 collision (both currently at 1.7→1.8).
- Closes the 1.5→1.7 gap without touching shipped migrations 0010/0005/
  0006/0007.

**Phase 11 scope:** version-chain hygiene only. No code-logic changes.
- Rewrite frontmatter `from_version`/`to_version` on `0008` and `0009`.
- Strike stale CHANGELOG `[1.6.0]` and `[1.7.0]` sections — they describe
  the pre-rebase 0006/0007 (`1.5.1 → 1.6.0` and `1.6.0 → 1.7.0`) which
  ended up shipping at `1.9.1 → 1.9.2` and `1.9.2 → 1.9.3` instead.
  Replace with one-line "see [1.9.2]/[1.9.3]" pointer entries.
- Update `migrations/README.md` index to reflect new from→to.
- Test harness: run `bash migrations/run-tests.sh` end-to-end after the
  frontmatter change to confirm no regressions.
- Open Phase 11 PR through the full GSD discipline OR via `/gsd-quick`
  if treated as a typed-fix (no functional changes, just metadata).

After Phase 11 lands, **rerun the cparx dry-run** to confirm:
`/update-agenticapps-workflow --dry-run --from 1.5.0` inside cparx walks
0008 → 0009 → 0010 → 0005 → 0006 → 0007 cleanly.

**Alternative considered** if strict +0.1 increments preferred: keep 0009
at `1.6 → 1.7`, add new `0011-bridge-1.7-1.8.md` (no-op version bump).
More files, more granular, same end-state. Reject in favor of the leaner
two-frontmatter-edit fix above.

## Other follow-ups (lower priority)

Carry-over from phases 08-10 reviews:

1. **Phase 08 CSO H1 retroactive**: migration 0005's `sed && rm .bak`
   chain has the same bug Phase 09 + 10 fixed in their own scripts.
   Apply the explicit if/then/else pattern.
2. **Supply-chain pinning**: pin vendored `ussumant/llm-wiki-compiler`
   plugin to a tag + SHA-256 (0006 follow-up). Pin the `gitnexus` MCP
   command's npm install reference similarly (0007 follow-up).
3. **Phase 10 deferred FLAGs**: fixture 13 cosmetic rename; helper
   script `GITNEXUS_BIN` env-override warning; symlinked `~/.claude.json`
   edge case.

## Open questions

- **Shell-lint hook** for the `&&`-chain pattern under `set -e`? CSO H1
  has fired in three consecutive phases. Time to make it structural.
- **Multi-AI plan review CLI floor**: currently using `codex exec` +
  `gemini -p`. The 0005 pre-flight requires ≥2 of
  `gemini|codex|claude|coderabbit|opencode`. coderabbit + opencode
  CLIs are absent here — workflow ship a setup-doc, or "any 2" is fine?
- **Helper script license consent**: `index-family-repos.sh` surfaces
  a `⚠ LICENSE` block in usage, but `--all` is implicit acceptance.
  Worth a `--accept-license` first-time flag?

## Files relevant for Phase 11

- `migrations/0008-coverage-matrix-page.md` (lines 5-6 — frontmatter)
- `migrations/0009-vendor-claude-md-sections.md` (lines 5-6)
- `migrations/README.md` (index table)
- `CHANGELOG.md` (sections `[1.6.0]` line ~120, `[1.7.0]` line ~103)
- `migrations/run-tests.sh` (full-suite verification post-rewrite)
