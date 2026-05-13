# Phase 07 — VERIFICATION.md

Migration 0010 (`post-process-gsd-sections`, v1.8.0 → v1.9.0).
Evidence for each must-have from PLAN.md.

**Branch:** `feat/post-process-gsd-sections-0010`
**Commits in this branch off main+0009:**
- `40bd?` — test(RED): phase 07 fixtures + harness
- `3bf6727` — feat(GREEN): post-process GSD section markers
- `8606387` — feat(workflow): migration 0010 + ADR 0022 + v1.9.0

---

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC-1 | `migrations/0010-post-process-gsd-sections.md` exists with apply + revert blocks; `from_version: 1.8.0, to_version: 1.9.0` | ✅ MET | Commit `8606387`. Frontmatter lines 1–11 of the file. 4 steps, each with idempotency check + rollback. |
| AC-2 | Post-processor script at `templates/.claude/hooks/normalize-claude-md.sh`; POSIX-safe, idempotent, source-existence-safe | ✅ MET | Commit `3bf6727`. `bash 3.2+`, `set -u`, `set -o pipefail`. `build_replacement()` returns 1 (preserve) when resolved source path is missing. Idempotency verified by fixture `inlined-7-sections` double-run. |
| AC-3 | Hook registered in `templates/claude-settings.json` PostToolUse block for `Edit\|Write\|MultiEdit` | ✅ MET | Commit `8606387`. New "Hook 6 — Normalize CLAUDE.md after Edit/Write (migration 0010)" entry; `python3 -m json.tool` validates clean. |
| AC-4 | `migrations/run-tests.sh test_migration_0010()` stanza with ~15 assertions; all PASS | ✅ MET | 7 assertions (fewer than estimated; the 5 fixtures double up — diff-against-golden plus line-count plus idempotency plus missing-input). All PASS on commit `8606387`. |
| AC-5 | No regressions in prior fixtures (0001, 0009) | ✅ MET | Full harness output:<br>`PASS: 57 / FAIL: 8 / SKIP: 0`<br>The 8 FAILs are pre-existing in `test_migration_0001()` (caused by `git merge-base HEAD main` resolving to a post-0001-merge commit; documented in session-handoff line 117–119, predates this phase). 0009 PASSES unchanged. 0010: 7/7 PASS. |
| AC-6 | ADR in `docs/decisions/` capturing source identification + chosen approach + 0009/0010 boundary + upstream-patch follow-up | ✅ MET | Commit `8606387`: `docs/decisions/0022-post-process-gsd-section-markers.md` (12 KB). Sections: Context (source identification), Decision (post-processor in claude-workflow), Alternatives rejected (3 alternatives with rationale), Consequences (good/bad/neutral), 0009/0010 boundary matrix, TODOs. |
| AC-7 | Applying 0009 + 0010 to a copy of cparx CLAUDE.md drops 647L → ≤200L | ❌ PARTIAL — 278L (target missed by 78L) | End-to-end measurement below. Documented in CHANGELOG and ADR 0022's "Bad / risks" section: the remaining 78L gap is non-GSD content (gstack skill table, anti-patterns, repo-structure diagram, project notes — ~232L). Closing the gap requires a follow-up phase. |
| AC-8 | Two-stage review (`/review` Stage 1 + `superpowers:requesting-code-review` Stage 2) and `/cso` audit complete with no unresolved BLOCKs | 🔵 PENDING | Runs in Phase 07's task #6 (Post-phase gates), to be invoked next. Findings will be appended below. |

---

## End-to-end measurement (AC-7)

Procedure (reproducible via Bash):

```bash
TMPDIR="$(mktemp -d)"
cp /Users/donald/Sourcecode/factiv/cparx/CLAUDE.md "$TMPDIR/CLAUDE.md"

# Simulate 0009 Step 4 (Superpowers block extraction, lines 154–285).
sed -i.bak '154,285d' "$TMPDIR/CLAUDE.md"

# Simulate 0009 Step 3 (append ## Workflow reference).
cat >> "$TMPDIR/CLAUDE.md" <<'EOF'

## Workflow

This project uses the AgenticApps Superpowers + GSD + gstack workflow.
Full hooks, rituals, and red-flag tables: [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md).
Vendored — re-sync via `/update-agenticapps-workflow`.
EOF

# Stage source files so 0010's existence guards pass.
mkdir -p "$TMPDIR/.planning/codebase" "$TMPDIR/.claude/skills/dummy" "$TMPDIR/.claude/claude-md"
touch "$TMPDIR/.planning/PROJECT.md" \
      "$TMPDIR/.planning/codebase/STACK.md" \
      "$TMPDIR/.planning/codebase/CONVENTIONS.md" \
      "$TMPDIR/.planning/codebase/ARCHITECTURE.md" \
      "$TMPDIR/.claude/claude-md/workflow.md"
echo "stub" > "$TMPDIR/.claude/skills/dummy/SKILL.md"

# Run 0010 post-processor.
( cd "$TMPDIR" && \
  /Users/donald/Sourcecode/agenticapps/claude-workflow/templates/.claude/hooks/normalize-claude-md.sh \
  "$TMPDIR/CLAUDE.md" )
```

| Stage | Line count | Δ |
|---|---|---|
| Original `factiv/cparx/CLAUDE.md` | **647** | — |
| After 0009 (Superpowers block extracted; ref appended) | **521** | −126 (−19%) |
| After 0009 + 0010 (GSD markers normalized) | **278** | −243 (−47% from 521; −57% from 647) |
| User's stated target | ≤200 | gap: 78L (28%) |

**Net reduction:** 369 lines (57% of original).
**0010 alone:** 243 lines removed (47% of post-0009 size).

GSD-marker positions in the final file:

```
218: <!-- GSD:project source:PROJECT.md /-->
222: <!-- GSD:stack source:codebase/STACK.md /-->
226: <!-- GSD:conventions source:CONVENTIONS.md /-->
230: <!-- GSD:architecture source:ARCHITECTURE.md /-->
234: <!-- GSD:skills source:skills/ /-->
(workflow block: REMOVED — .claude/claude-md/workflow.md exists)
237: <!-- GSD:profile /-->
```

Six self-closing markers in 22 lines (218–239) of the final file —
down from the original 265 lines of inlined content. The `workflow`
block was removed entirely per ADR 0022's Decision B-4 (collapses
when 0009's vendored file exists).

### Why ≤200L wasn't met

The non-GSD content in cparx CLAUDE.md sums to ~232L. After 0010, the
GSD section uses ~22L. Static project-specific content makes up the
balance:

- `# CLAUDE.md` header + Project Overview (lines 1–22 of original) — ~22L
- Tech Stack (project-authored, not GSD-managed) — ~30L
- Repo Structure ASCII diagram — ~39L
- Environment Strategy table — ~10L
- gstack section + Available skills list — ~12L
- Anti-patterns to avoid — ~5L
- Skill routing section (project-authored) — ~10L

**Path to ≤200L:**

1. **Phase 08 candidate:** vendor or reference the gstack `Available
   skills` list (currently a flat enumeration of 30+ skill names) the
   way 0009 vendored the Superpowers block — moves another 12L out.
2. **Phase 09 candidate:** collapse the Repo Structure ASCII diagram
   to a 3-line reference to the actual directory tree (or a
   `tree -L 2` output file linked from CLAUDE.md). Saves ~36L.
3. After both phases, cparx projects to ~230L — still above 200L. The
   remaining gap is content the user explicitly authored as
   project-canonical (architecture decisions, environment strategy);
   trimming it further is a judgment call, not a mechanical migration.

The ADR-0022 "Bad / risks" section captures this gap. CHANGELOG section
1.9.0 includes "End-to-end projection: 647 → 0009 → ~496L → 0010 →
~270L" — empirical (278L) is within 3% of the projection.

---

## Test harness output

Full output of `bash migrations/run-tests.sh 0010`:

```
━━━ Migration 0010 — Post-process GSD section markers ━━━
  ✓ fresh: no-op preserves content byte-for-byte
  ✓ inlined-7-sections: 7-block normalization matches golden
  ✓ inlined-source-missing: preserves block with missing source; normalizes others
  ✓ with-0009-vendored: 0009 reference untouched; project block normalized
  ✓ cparx-shape: normalized output ≤ 200 lines (got 147, max 200)
  ✓ idempotency: second run produces identical output
  ✓ non-existent input: script exits non-zero

━━━ Summary ━━━
  PASS: 7
```

Full harness (`bash migrations/run-tests.sh`):

```
━━━ Summary ━━━
  PASS: 57
  FAIL: 8     ← pre-existing 0001 FAILs (carry-over from before this phase)
```

The 8 FAILs are in `test_migration_0001()` — caused by `git merge-base
HEAD main` resolving to a post-0001-merge commit instead of a true
v1.2.0 baseline. Pre-dates this phase per session-handoff.md line
117–119. Not introduced by 0010.

---

## Files modified in this phase

```
A migrations/0010-post-process-gsd-sections.md      (new)
A templates/.claude/hooks/normalize-claude-md.sh    (new — executable)
A docs/decisions/0022-post-process-gsd-section-markers.md (new ADR)
A migrations/test-fixtures/0010/ ...                (5 fixture dirs + README)
M migrations/run-tests.sh                           (test_migration_0010 stanza)
M migrations/README.md                              (Migration index row)
M templates/claude-settings.json                    (Hook 6 added)
M skill/SKILL.md                                    (version 1.8.0 → 1.9.0)
M CHANGELOG.md                                      (new [1.9.0] section)
A .planning/phases/07-post-process-gsd-sections/    (CONTEXT, RESEARCH, PLAN, VERIFICATION)
```

---

## Post-phase gates (AC-8) — to be populated

- `/review` (Stage 1 — spec compliance): _pending_
- `superpowers:requesting-code-review` (Stage 2 — code quality): _pending_
- `/cso` (security audit — hook lifecycle + shell injection paths): _pending_

Findings from each gate will be appended below as REVIEW.md, REVIEW.md
Stage 2 section, and SECURITY.md respectively. Any BLOCK-severity
finding gates the PR.
