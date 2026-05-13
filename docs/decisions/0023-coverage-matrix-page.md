---
id: 0023
slug: coverage-matrix-page
title: Coverage Matrix Page — per-repo presence + freshness dashboard
status: Accepted
date: 2026-05-13
supersedes: []
related: [0018, 0019, 0020]
---

# ADR 0023: Coverage Matrix Page

## Status

Accepted (Phase 10 of agenticapps-dashboard).

## Context

The AgenticApps Superpowers + GSD + gstack workflow defines a knowledge layer per repo
(CLAUDE.md), per family (wiki), globally (GitNexus index), and per workflow installation
(skill version). Until Phase 10, there was NO surface answering "which repos are doing
their knowledge-layer homework, and what needs attention?"

State before this ADR: ~45 repos across three client families (agenticapps=9, factiv=3,
neuroflash=33), each with independent CLAUDE.md presence, GitNexus index age, wiki
inclusion, and workflow skill version. There was no aggregated view. Gaps were discovered
by accident (wrong jq schema bug in migration 0007; neuroflash missing 25+ repos from
.wiki-compiler.json sources; dashboard itself has version-unknown skill because its bundle
layout precedes the migration install pattern).

## Decision

Ship a `/coverage` page in agenticapps-dashboard that scans every git repo under
`~/Sourcecode/{agenticapps,factiv,neuroflash}` (one level deep, excluding personal/shared/archive)
and surfaces a 4-column presence/freshness matrix.

### Columns (4)

1. **CLAUDE.md** (or AGENTS.md fallback) — exists / missing. Presence only; no freshness
   window because CLAUDE.md is a living document, not a time-bounded artifact.

2. **GitNexus indexed** — fresh (last-indexed ≤ 14 days) / stale (> 14 days) / missing
   (not in `~/.gitnexus/registry.json`) / not-applicable (no `~/.gitnexus/` at all).
   The registry is a top-level JSON array — use `jq 'length'` not `jq '.repos | length'`
   (migration 0007's verify script contained a bug corrected here).

3. **Wiki linked** — fresh (both `.wiki-compiler.json` source reference exists AND
   `<family>/.knowledge/wiki/.compile-state.json` last-compiled ≤ 7 days) / stale /
   missing. Multi-signal: inclusion in the wiki source list AND recency of last compile.

4. **Workflow version** — matches head migration's `to_version` (fresh) / behind
   (stale) / ahead (fresh) / missing-skill (no SKILL.md found at any candidate path) /
   version-unknown (SKILL.md present but no version field — dashboard's own pre-migration
   convention). Head version read from highest-numbered migration file in
   `~/Sourcecode/agenticapps/claude-workflow/migrations/` (lex-descending sort,
   first with `to_version` wins — D-10-06).

### Layout

Grouped sections per family with sticky family-header aggregate counts
(`family · N repos · ✕ N missing · ⚠ N stale · ✓ N fresh`), collapse toggle per family,
and a cross-family status filter + search toolbar. This preserves the `~/Sourcecode/CLAUDE.md`
family-boundary contract while keeping cross-family visibility on one page. Default:
all families expanded. Collapse state persists in localStorage.

### Override surface

Inline `⚠ N override` chip per row when `<repo>/.planning/phases/*/multi-ai-review-skipped`
sentinel files exist (ADR 0018 / migration 0005). Click expands to an inline list showing
`<phase-slug> — sentinel since YYYY-MM-DD` (timestamp from `git log -1 --format=%aI`).

The `GSD_SKIP_REVIEWS=1` env-var override is undetectable (no on-disk trace) — documented
gap. The override chip surface is intentionally forward-compatible: future migration types
may add new sentinel patterns; the chip slot will accumulate them.

### Refresh semantics (D-10-02 + D-10-09)

- **GitNexus stale** → daemon spawns `gitnexus analyze` (PATH-resolved binary, argv-array,
  NEVER `npx` — CSO requirement from D-5-21). Returns `updatedRow` on success.
- **Wiki stale** → CLIPBOARD-ONLY. No headless `/wiki-compile` runner exists (the slash
  command is Claude Code interactive only). Dashboard surfaces a "Copy command" affordance
  + subscript noting the limitation. Defer headless wiki refresh to a future migration.
- **CLAUDE.md missing** → help-link (no daemon action; requires human authoring).
- **Workflow version mismatch** → clipboard copy of `claude /update-agenticapps-workflow`.

The daemon's `POST /api/coverage/refresh` accepts only `{ action: 'gitnexus-analyze' }`;
all clipboard actions are SPA-side only. Non-'gitnexus-analyze' action values are rejected
at Zod parse (400) — enforced boundary.

### Cache (D-10-01)

30s daemon-side memo cache (`Map<'all', { value, expiresAt }>`); cleared on
`POST /api/coverage/refresh`. Pull-only; no chokidar background watcher against
`~/Sourcecode` (would be expensive across 45 repos).

## Consequences

**Positive:**

- Single surface for cross-family knowledge-layer health across all ~45 repos.
- GAPS are surfaced immediately: neuroflash has 33 repos but `.wiki-compiler.json`
  references only 8; the coverage page makes this visible.
- Workflow version detection is self-updating: the highest migration's `to_version`
  field is single source of truth — no dedicated VERSION file needed.
- Override chip makes multi-AI review bypass auditable at a glance.
- Phase 10 proves all empty states work (GitNexus not installed on dev machine;
  no sentinels in production repos; version-unknown for dashboard's own SKILL.md).

**Negative:**

- Wiki refresh requires user terminal interaction (clipboard) — not fully automated in v1.
- `GSD_SKIP_REVIEWS=1` env-var override is invisible to the coverage page.
- 30s cache means freshness data can be up to 30s stale (acceptable — coverage data
  churns slowly; session-to-session freshness is more important than second-to-second).
- Workflow head scanner reads the highest-numbered migration (lex sort) — if a repo
  ships with a higher number but lower semantic version, the comparison could be wrong.
  Mitigated by the migration numbering convention (sequential integers).

**Mitigations:**

- Future migration may add a headless wiki-compile runner; v1 documents the limitation
  in UI subscript and this ADR.
- Audit on env-var overrides relies on user discipline + git log conventions.
- Dashboard-side fixture test (CODEX MED-17) locks the migration 0008 frontmatter shape
  in CI so drift between dashboard expectations and the upstream migration file is caught
  automatically.

## Alternatives Considered

**Cross-family aggregate health-score % hero number** — "Coverage health: 67% green"
header stat. Deferred to v1.2 — the matrix itself is more actionable; a % number
abstracts away which repos have gaps.

**Per-repo drill-down detail page** (`/coverage/$repo`) — Row is self-contained in v1;
adding a detail page would require new routing + daemon endpoints for per-repo history.
Deferred.

**AgentLinter as 5th column** — Phase 5 already ships AgentLinter score in the per-project
view. Cross-repo column in Coverage would duplicate that; defer until the matrix pattern
is validated.

**chokidar background watcher** — Rejected per D-10-01 (pull-only). Real-time FS watching
across 45 repos is expensive and couples the daemon to a background process lifecycle.

**Daemon spawns `/wiki-compile`** — Rejected. `/wiki-compile` is a Claude Code slash
command with no headless runner. Coupling the daemon to `claude code -p` experimental
headless mode would break on Claude Code CLI surface changes (D-10-09 correction).

## Related Decisions

- ADR 0018 — multi-ai-plan-review-enforcement (sentinel override data source)
- ADR 0019 — llm-wiki-compiler-integration (Wiki column data source)
- ADR 0020 — gitnexus-code-graph-integration (GitNexus column; note: 0020's verify
  script has a `.repos | length` bug corrected in migration 0008 and documented here)

## Decisions Captured (D-10-XX)

All 11 Phase 10 decisions are captured in this ADR:

| Decision | Summary |
|----------|---------|
| D-10-01 | Pull with 30s daemon-side memo cache; no background watcher |
| D-10-02 | Per-row refresh; daemon-spawns gitnexus only; clipboard for wiki/CLAUDE.md/workflow |
| D-10-03 | Grouped sections per family; sticky family headers + aggregate counts + collapse |
| D-10-04 | Inline override chip when multi-ai-review-skipped sentinels exist |
| D-10-05 | Repo discovery: every git repo under ~/Sourcecode/{agenticapps,factiv,neuroflash} |
| D-10-06 | Workflow version head from highest migration's to_version (lex-descending sort) |
| D-10-07 | Sort + filter: family-then-name default; chips for status; search box |
| D-10-08 | New "Observability" sidebar section (vs peer top-level item) — user preference |
| D-10-09 | Wiki refresh is clipboard-only in v1 (no headless /wiki-compile runner) |
| D-10-10 | GitNexus never-indexed → missing; ~/.gitnexus/ absent → not-applicable (column-wide) |
| D-10-11 | Phase 10 ships with not-applicable GitNexus baseline; no gitnexus install bundled |
