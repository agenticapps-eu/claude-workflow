# Phase 06 — RESEARCH (brainstorming alternatives)

Per `superpowers:brainstorming`: list alternatives, surface trade-offs, pick
with rationale. "There's only one way" is a red flag — list anyway.

## Inlined-block detection strategy

The migration must detect whether a project's CLAUDE.md contains the
~150-line workflow boilerplate before deciding whether to extract it.
False positives (deleting non-boilerplate content) and false negatives
(missing the boilerplate, leaving it inlined) both have material cost.

### Alternative A — Regex signature scan (chosen)

```bash
INLINED=0
grep -q "^## Superpowers Integration Hooks (MANDATORY" CLAUDE.md && INLINED=1
```

Single-line `grep`. The H2 heading text is highly specific (full
parenthetical, exact emphasis), so false-positive risk is near zero. The
H2 is present in every inlined copy regardless of how the user customised
the surrounding sections.

**Pros**: minimal-dependency (just `grep -q`), fast, deterministic, easy
to explain in the migration prose, easy to inverted-check for idempotency
(`! grep -q ...`).

**Cons**: cannot tell whether the inlined block has been *modified*
relative to the template baseline — that's a separate divergence check
(Step 2 idempotency), not the detection step.

**Boundary determination**: extraction range = first match of any of the
three signature markers (`# CLAUDE.md Sections —`, `## Development Workflow`,
or `## Superpowers Integration Hooks`) through the end of the
`13 Red Flags` numbered list (matched by `^13\. .*Trigger Automatic STOP`
or the next H1/H2 boundary, whichever comes first).

### Alternative B — Checksum against template baseline

```bash
TPL_SHA=$(sha256sum templates/claude-md-sections.md | awk '{print $1}')
# Extract the suspected block from CLAUDE.md, sha256sum it, compare.
```

**Pros**: Detects exact-template inlining with zero false-positive risk.

**Cons**:
- Doesn't detect customised inlined blocks (any whitespace change breaks
  the checksum). Migration would fail to extract from cparx and
  fx-signal-agent if either has so much as a trailing newline drift.
- Requires deciding the extraction boundary *before* checksumming, which
  needs Alternative A as a sub-step anyway.
- Brittle across template-version drift: when the workflow scaffolder
  bumps the template, the checksum changes and the migration falsely
  reports "no inline block detected" on projects pasted from the older
  template.
- Adds a `sha256sum` dependency (BSD/macOS sometimes ships only
  `shasum -a 256`); unwanted shell-portability complexity.

**Verdict**: rejected as primary detection. Useful as a *post-detection*
divergence check (does the extracted block match the current template?),
but that's exactly what Step 2's `grep` idempotency check already does
more cheaply.

### Alternative C — Marker insertion (workflow plants its own anchors)

Have the template start with `<!-- AGENTICAPPS-WORKFLOW-BLOCK-START -->`
and end with `<!-- AGENTICAPPS-WORKFLOW-BLOCK-END -->`. Detect by finding
the markers; extract by everything between them.

**Pros**: Surgical extraction. Tolerant of customisation between the
markers. Future-proof against template content drift.

**Cons**:
- Existing inlined copies (cparx, fx-signal-agent — i.e. the only
  projects we actually need this migration for) **don't have these
  markers** because they predate this design. Migration 0009 would have
  to fall back to Alternative A for them anyway.
- Once added, every paste of the template would carry these HTML
  comments forward — visual noise in CLAUDE.md.
- Requires modifying the template itself, which expands the migration's
  blast radius.

**Verdict**: rejected for 0009. **Worth revisiting for 0010+** — once 0009
has migrated existing projects to vendored mode, the vendored file can
include start/end markers as `<!-- vendored-from: claude-workflow@1.8.0 -->`
header, which gives Alternative C's benefits prospectively. Not needed for
the migration that does the initial extraction.

### Pick

**Alternative A** (regex signature scan) for detection.
**Step 2 idempotency check** for divergence (already trivially detects it
via grepping for content that's only in the current template).

This matches the audit's exact recommendation ("the H1 is verbatim from
the template — strong evidence the block was pasted").

---

## Setup-skill remediation strategy (root-cause fix)

Migration 0000 Step 4 cats the template into CLAUDE.md. We need new
projects to vendor on first install. Three ways to achieve that:

### Option 1 — Patch 0000 in-place (chosen)

Edit `migrations/0000-baseline.md` Step 4 to:
1. `mkdir -p .claude/claude-md`
2. Copy the template to `.claude/claude-md/workflow.md`
3. Append a 5-line reference block to CLAUDE.md (not the full content).

**Pros**: Fresh installs go straight to vendored state. No churn from
"0000 inlines, 0009 immediately undoes it" sequence.

**Cons**: Migrations are conventionally immutable. But 0000's pre-flight
already refuses on existing installs (`test -f
.claude/skills/agentic-apps-workflow/SKILL.md` → error), so re-running
0000 against an existing install is impossible. The "immutability" only
matters for projects re-running setup — which is forbidden anyway.

### Option 2 — Leave 0000 alone, let 0009 fix it on the way through

Fresh install runs `0000 → 0001 → ... → 0009`. After 0009, the project
is in the vendored state. The intermediate state (post-0000, pre-0009)
has inlined CLAUDE.md.

**Pros**: Strict immutability of migration history.

**Cons**:
- Setup briefly creates the bug, then fixes it. Wasteful, confusing in
  per-step diffs.
- 0009's "extract inlined block" path runs on every fresh install —
  unnecessary work, and the user gets prompted about extraction even
  though they just installed it.
- Setup commit history shows "added inlined block (commit A)" then
  "extracted inlined block (commit B)" with no real reason.

### Option 3 — Branch by detected scenario in 0009

0009 itself decides "fresh install: vendor; existing install with inline:
extract; existing install already vendored: no-op". Single migration
handles all cases.

**Pros**: Single source of truth.

**Cons**:
- Conflates baseline-creation with upgrade. 0009's prose becomes much
  more complex.
- Doesn't solve the "0000 inlined, then 0009 ran" intermediate-state
  problem on fresh installs — 0000 is still wrong.

### Pick

**Option 1**: patch 0000 Step 4 in-place. Migrations are immutable
*after release*, but 0000 is the bootstrap step — it represents the
"shape v1.2.0 ships in" not "what was committed on day X". The
constitutional argument for immutability is "don't break re-runs"; 0000
is already non-re-runnable by design (pre-flight refuses).

A note in the patched 0000 Step 4 documents the change so future readers
understand why the bootstrap step writes vendored state instead of
inlining.

---

## Migration 0009 vs migration 0010 — bundle or split?

Already covered in CONTEXT.md Decision 4. Pick: **split**. Rationale
recorded there.

---

## Test fixture strategy — git-ref vs hand-built

Migration 0001's test harness uses `git show <ref>:<path>` to materialize
fixtures from history. That works because 0001 patches existing
template files that have a clear pre-/post-commit baseline.

Migration 0009's test scenarios include:
- Fresh install (no `.claude/claude-md/` yet)
- Idempotent re-run (already vendored)
- Pre-existing inlined block (the cparx/fx-signal-agent shape)
- Customised local copy

These shapes don't all exist as commits in this repo's history. The
"pre-existing inlined block" state is what cparx and fx-signal-agent look
like *as of today* — there's no commit in claude-workflow's history that
captures it.

**Pick**: hand-built fixtures in `migrations/test-fixtures/0009/`. Each
scenario is a small directory with the synthetic CLAUDE.md +
`.claude/claude-md/workflow.md` (or absence) + `.claude/skills/...SKILL.md`
shape. The harness copies them into temp dirs and runs the idempotency
checks.

The 0005/0006/0007 fixture dirs already follow this pattern (empty
`before/` and `after/` subdirs as placeholders); 0009 will be the first
to actually populate them.
