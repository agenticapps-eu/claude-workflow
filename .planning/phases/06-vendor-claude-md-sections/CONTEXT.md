# Phase 06 — Vendor CLAUDE.md sections (migration 0009)

**Phase status**: discuss → plan → execute
**Date**: 2026-05-13
**Workflow version**: 1.7.0 → 1.8.0

## Problem

Two factiv repos have CLAUDE.md files >200 lines because the AgenticApps
workflow boilerplate (~150 lines) is inlined verbatim into each project's
CLAUDE.md:

| Repo | Lines | Status |
|---|---:|---|
| `factiv/cparx/CLAUDE.md` | 646 | 3.23× over budget |
| `factiv/fx-signal-agent/CLAUDE.md` | 372 | 1.86× over budget |

Audit: `~/Documents/Claude/Projects/agentic-workflow/factiv-claude-md-audit-2026-05-13.md`.

`fx-signal-agent` retains the source template's H1 line verbatim
(`# CLAUDE.md Sections — paste into your project's CLAUDE.md`), proving the
content was pasted unchanged. Root cause: migration `0000-baseline.md` Step 4
literally `cat`s `templates/claude-md-sections.md` into `CLAUDE.md`:

```bash
echo "" >> CLAUDE.md
cat ~/.claude/skills/agenticapps-workflow/templates/claude-md-sections.md >> CLAUDE.md
```

(See `migrations/0000-baseline.md` line 99.)

Every project that ran `/setup-agenticapps-workflow` from v1.2.0 onward
inherited this paste-block. The fix is structural: vendor the block as
`<repo>/.claude/claude-md/workflow.md` and have CLAUDE.md link to that local
path.

## Goal

Ship migration 0009 that:

1. Vendors the workflow block into each registered repo as
   `.claude/claude-md/workflow.md`.
2. Detects pre-existing inlined-block state and offers to extract + replace
   it with a reference (with user confirmation before mutating CLAUDE.md).
3. Leaves projects with customised local copies untouched (re-syncs only
   when local matches a known-template baseline; otherwise prompts with
   diff).
4. Patches migration `0000-baseline.md` Step 4 so fresh installs vendor
   from the start, eliminating the bug at its source.

## Non-goals

- Migration 0010 (GSD compiler reference-mode for auto-managed
  PROJECT/STACK/CONVENTIONS/ARCHITECTURE sections). Cparx needs that to get
  under 200L, but it's a different blast radius (touches GSD compiler code,
  not workflow-template content) and ships separately. Queued for the next
  phase.
- Reorganising other inlined sections (repo-structure, supabase-notes,
  skill-routing). Project-specific reorg is per-repo work, not a
  workflow-meta migration.
- Auto-import / `@import`-style includes. v1 reads referenced files only
  when explicitly opened by Claude; the link in CLAUDE.md is enough.

## Decisions surfaced (would normally come out of /gsd-discuss-phase)

The user's prompt explicitly asked these be surfaced rather than assumed.
A second system-reminder ("work without stopping for clarifying questions")
landed before I could open AskUserQuestion modals, so I made the reasonable
call on each — recorded here with rationale; user can redirect.

### Decision 1 — Destination path inside the registered repo

**Chosen**: `.claude/claude-md/workflow.md` (matches the user's recommendation
and the audit's proposed layout).

**Why**: colocates with other Claude-related config (`.claude/skills/`,
`.claude/hooks/`, `.claude/settings.json`), discoverable, repo-local,
self-contained.

**Alternatives rejected**:
- `docs/workflow.md` — clutters docs/, ambiguous (project workflow vs meta
  workflow).
- `.workflow.md` (root) — collides with project conventions; harder to
  spot grouping.
- Symlink to `~/.claude/skills/agenticapps-workflow/...` — defeats the
  self-contained-repo property; clones break on machines without the
  scaffolder.

### Decision 2 — Idempotency model (matches migration 0001 pattern)

**Chosen**: per-step idempotency check returns 0 when the desired end-state
is present.

For migration 0009 specifically:

| Step | Idempotency check |
|---|---|
| Step 1 (vendor file exists) | `test -f .claude/claude-md/workflow.md` |
| Step 2 (vendor content current) | `grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" .claude/claude-md/workflow.md` |
| Step 3 (CLAUDE.md reference exists) | `grep -q "claude-md/workflow.md" CLAUDE.md` |
| Step 4 (inlined-block removed) | `! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md` |
| Step 5 (version bump) | `grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md` |

The Superpowers heading regex is **heading-level-agnostic** (`^#{2,4}`)
because the deprecated `templates/claude-md-sections.md` source emits H3
(`### Superpowers`) — that's what cparx and fx-signal-agent have on disk
today — while the new vendored canonical `templates/.claude/claude-md/workflow.md`
emits H2 (`## Superpowers`). A literal H2 anchor would cause the
migration to silently no-op against the very projects it targets. This
was caught by Stage 2 review (BLOCK-1) and the regex form is the fix.

**Re-running the migration**:
- All steps already applied → all idempotency checks return 0 → all steps
  skip → "Up to date" message → exit 0.
- `.claude/claude-md/workflow.md` exists but content differs from baseline:
  Step 2 returns non-zero, the divergence-detection logic in `update/SKILL.md`
  Step 5 takes over (see Decision 3 remediation flow).

### Decision 3 — Inlined-block detection signature + remediation

**Detection signature** (any one match in CLAUDE.md → inlined block present):

| Marker | Source | Confidence |
|---|---|---|
| `# CLAUDE.md Sections — paste into your project's CLAUDE.md` | template H1 line — only present if pasted verbatim | **highest** (fx-signal-agent) |
| `## Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)` | template H2 — present in any inlined copy | **high** (cparx + fx-signal-agent) |
| `13 Red Flags — Trigger Automatic STOP` | template subsection title | **high** (every inlined copy has it) |

The migration uses the **H2 marker as primary** (catches both cases) and
the H1 marker as a separate "this is definitely a paste, not deliberate
inlining" signal that allows the migration to recommend extraction without
asking.

**Remediation flow**:

1. Detect: grep CLAUDE.md for the H2 marker.
2. If detected, extract the inlined block (from the line containing the
   first marker — `# CLAUDE.md Sections` if present, else
   `## Development Workflow` (the section that opens the inlined block) —
   through the end of the `13 Red Flags` numbered list).
3. Compare extracted block against the canonical
   `templates/.claude/claude-md/workflow.md` template.
   - Match (modulo trailing whitespace) → safe to replace; vendor the
     canonical file and replace the inline range with the reference block.
     **Still ask the user** to confirm before mutating CLAUDE.md (per the
     user's explicit request).
   - No match → user has customised the inlined block. Show a diff. Offer:
     - (a) Replace with canonical (lose customisations)
     - (b) Vendor the *customised* block to `.claude/claude-md/workflow.md`,
       replace inline range with reference (preserve customisations as the
       vendored copy)  [recommended]
     - (c) Skip mutation — only create `.claude/claude-md/workflow.md` from
       canonical; CLAUDE.md keeps its inline copy. (Project lives with the
       duplication until the user reconciles.)
4. If inlined block is **not** detected: skip Step 4 entirely. The project
   either never inlined (post-migration-0009 setup) or already cleaned
   itself up.

**Safety**: never delete content from CLAUDE.md without user confirmation
and a diff preview. The migration runtime's per-step Apply prompt
(update/SKILL.md Step 5 #5) already gates this.

### Decision 4 — Bundle migration 0010 (GSD compiler reference-mode)?

**Chosen**: ship 0009 alone; queue 0010 separately.

**Why**:
- 0009's blast radius is workflow-template content + `.claude/claude-md/`
  in consumer repos (read-only file vendoring + a CLAUDE.md edit).
- 0010's blast radius is GSD compiler logic (`~/.claude/get-shit-done/...`)
  + every project's `<!-- GSD:* -->` blocks. Different code, different
  testing surface, different review focus.
- Coupling them inflates the PR (~600 lines combined vs ~250 for 0009
  alone), expands the review burden, and entangles two unrelated risks.
- Cparx not getting under 200L from 0009 alone is a known trade-off — the
  audit was explicit that "the only path to ≤200 is changing the GSD
  compiler behaviour."  0009 still ships value: fx-signal-agent goes
  372 → ~201, cparx goes 646 → ~496 (still over but materially better),
  and the inline→vendor pivot is established for 0010 to build on.
- 0010 should land as a separate migration `0010-gsd-compiler-reference-mode.md`
  in a follow-up PR. **Not in this phase.**

If the user wants 0010 in the same release cycle, queue it after 0009 lands
(separate phase, separate review).

## Acceptance criteria (from user prompt)

- [x] `migrations/0009-vendor-claude-md-sections.md` exists, version
      frontmatter bumps `to_version` to 1.8.0
- [x] setup + update skills use vendor mode by default (via patched 0000
      Step 4 + new 0009 + revised setup/SKILL.md prose)
- [x] `migrations/run-tests.sh`: 20+/20+ PASS for migration 0009 fixtures
- [x] ADR `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md`
      capturing the inline→vendor pivot and "meta-repo never referenced at
      runtime" property
- [x] README + migrations index + CHANGELOG updated
- [x] Two-stage review + `/cso` pass before merge

## Risks

| Risk | Mitigation |
|---|---|
| Migration 0009 destroys customisations in CLAUDE.md | Per-step Apply prompt always shows diff + asks confirmation. Customised local copies are detected via byte-compare against template baseline; mismatch → user pick. |
| Patching 0000 Step 4 breaks the 0001 test harness | The 0001 fixture extracts `templates/claude-md-sections.md` into the fixture's CLAUDE.md location. After patching 0000 to vendor, the *template file* is unchanged (still at `templates/claude-md-sections.md`); only 0000's apply behavior changes. The 0001 harness works against the template's content shape, not against 0000's apply step. → No regression. |
| Existing projects already on 1.7.0 won't get the fix | Migration 0009 is the upgrade path: pre-flight requires `version: 1.7.0`; running `/update-agenticapps-workflow` applies 0009 in the chain. |
| User runs 0009 on a project where the inlined block has been intermixed with project-specific CLAUDE.md edits | Detection uses H2 marker boundary. Extraction range is bounded (start marker → end of "13 Red Flags" subsection). If the user edited *inside* the block, divergence detection (Decision 3) catches it and prompts. |

## Out-of-scope clarifications (asked by audit, deferred here)

- "Should the meta-repo be referenced at runtime?" — **No.** Repos are
  self-contained. Audit was explicit. ADR 0021 codifies this.
- "Should we use symlinks instead of vendored copies?" — **No.** Same reason.
- "Should the new file live at `<repo>/.claude/claude-md/` or somewhere
  else?" — Decision 1 above.
