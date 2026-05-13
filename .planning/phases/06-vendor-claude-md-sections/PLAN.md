# Phase 06 — PLAN

**Goal**: Vendor the workflow boilerplate as `.claude/claude-md/workflow.md`
in each registered repo. Fix the inline-paste root cause in migration 0000.
Ship migration 0009 to upgrade existing 1.7.0 projects.

**Workflow version**: 1.7.0 → 1.8.0.

## Files this phase will create

```
templates/.claude/claude-md/workflow.md                       (new — vendor source)
migrations/0009-vendor-claude-md-sections.md                  (new — migration)
migrations/test-fixtures/0009/before-fresh/                   (new — fixtures)
migrations/test-fixtures/0009/before-inlined-pristine/
migrations/test-fixtures/0009/before-inlined-customised/
migrations/test-fixtures/0009/after-vendored/
migrations/test-fixtures/0009/after-idempotent/
docs/decisions/0021-vendor-workflow-block-instead-of-inline.md (new — ADR)
.planning/phases/06-vendor-claude-md-sections/SUMMARY.md       (new — exec log)
.planning/phases/06-vendor-claude-md-sections/REVIEW.md
.planning/phases/06-vendor-claude-md-sections/SECURITY.md
.planning/phases/06-vendor-claude-md-sections/VERIFICATION.md
```

## Files this phase will modify

```
migrations/0000-baseline.md       (Step 4 patched: cat → vendor)
migrations/run-tests.sh           (add test_migration_0009 stanza)
migrations/README.md              (add 0009 to index)
setup/SKILL.md                    (Step 5 prose: vendor mode)
update/SKILL.md                   (Step 5 prose: re-sync + divergence prompt)
skill/SKILL.md                    (frontmatter: version 1.7.0 → 1.8.0)
CHANGELOG.md                      (add 1.8.0 section)
templates/claude-md-sections.md   (re-purpose H1 to point at vendored mode)
```

## Tasks

### T1 — Create vendored source `templates/.claude/claude-md/workflow.md`

Copy the existing `templates/claude-md-sections.md` content (less the "paste
into your project's CLAUDE.md" framing H1) into the vendored source path.
Add a `<!-- vendored-from: claude-workflow templates/.claude/claude-md/workflow.md -->`
header so future template-version drift is detectable.

**Verification**: `test -f templates/.claude/claude-md/workflow.md && grep -q "vendored-from" templates/.claude/claude-md/workflow.md`

### T2 — Patch `migrations/0000-baseline.md` Step 4 (root-cause fix)

Replace Step 4's apply block from `cat ... >> CLAUDE.md` to:
1. `mkdir -p .claude/claude-md`
2. `cp ~/.claude/skills/agenticapps-workflow/templates/.claude/claude-md/workflow.md .claude/claude-md/workflow.md`
3. Append a 5-line reference block to CLAUDE.md.

Update Step 4's idempotency check accordingly. Update the rollback. Add a
note explaining the change.

**Verification**: `grep -A30 "^### Step 4" migrations/0000-baseline.md | grep -q "claude-md/workflow.md"`

### T3 — Update `templates/claude-md-sections.md` H1

The file's H1 (`# CLAUDE.md Sections — paste into your project's CLAUDE.md`)
is the literal smoking-gun in fx-signal-agent's CLAUDE.md. Rewrite the H1
to a non-paste framing so any future accidental concat doesn't reproduce
the bug-signature. Add a top banner: "DO NOT PASTE — this template is
vendored as .claude/claude-md/workflow.md by migration 0000-baseline /
0009. Setup automation handles this."

**Verification**: `! grep -q "paste into your project's CLAUDE.md" templates/claude-md-sections.md`

### T4 — Write `migrations/0009-vendor-claude-md-sections.md`

5 steps:
- Step 1: Create `.claude/claude-md/workflow.md` from canonical template.
- Step 2: Add reference block to CLAUDE.md (above any existing inlined block).
- Step 3: Detect inlined block via H2 marker grep; flag for Step 4.
- Step 4: If detected, prompt user with diff, extract, replace inline range
  with reference (already added in Step 2 — Step 4 just removes the
  inline range). Three user choices: (a) replace with canonical,
  (b) preserve customisation as the vendored copy, (c) skip.
- Step 5: Bump version 1.7.0 → 1.8.0.

Frontmatter `from_version: 1.7.0`, `to_version: 1.8.0`, `applies_to`,
`requires: []` (no external skill dependencies).

Pre-flight: enforce `version: 1.7.0`, file existence (CLAUDE.md, skill).
Post-checks: verify vendored file present, CLAUDE.md contains reference,
inlined block absent (or partial — Step 4 may have been skipped).

**Verification**: file exists, frontmatter valid, all 5 steps follow the
established `### Step N: ...` / `**Idempotency check:**` / `**Apply:**` /
`**Rollback:**` shape (matches 0001).

### T5 — Update `setup/SKILL.md`

Step 5 prose mentions "Step 4 (CLAUDE.md sections)" — keep the reference
but note that Step 4 now writes a vendored file plus a CLAUDE.md reference
block, not the inlined content. Update Step 6 "Files created / modified"
list to include `.claude/claude-md/workflow.md`. No structural code changes —
the migration runtime already handles the new Step 4 shape.

**Verification**: prose mentions vendored path, no claim of "appends 150
lines to CLAUDE.md".

### T6 — Update `update/SKILL.md`

Step 5 prose: when re-running migration 0009 and `.claude/claude-md/workflow.md`
exists but byte-differs from the canonical template, emit a divergence
prompt with diff + 3-way pick (canonical/keep/skip). Update Failure modes
table with the new "divergence" outcome. No structural code changes — the
per-step Apply prompt already supports diff-then-confirm.

**Verification**: prose mentions divergence detection, 3-way pick.

### T7 — Build hand-built fixtures `migrations/test-fixtures/0009/`

Five scenarios:
1. `before-fresh/` — no `.claude/claude-md/`, no inlined block (clean
   project, just SKILL.md at version 1.7.0). Migration should apply
   Steps 1, 2, 5 only (Step 4 idempotency returns 0 — nothing to extract).
2. `before-inlined-pristine/` — CLAUDE.md contains the canonical inlined
   block (matches `templates/claude-md-sections.md` byte-for-byte). All 5
   steps apply.
3. `before-inlined-customised/` — CLAUDE.md inlined block has a custom
   first paragraph. Steps 1–3 apply normally; Step 4 detects divergence.
4. `after-vendored/` — fully migrated; all idempotency checks return 0.
5. `after-idempotent/` — same as `after-vendored/` plus the project ran
   `/update-agenticapps-workflow` once already; idempotency must still
   return 0.

Each scenario contains the minimum file set:
- `.claude/skills/agentic-apps-workflow/SKILL.md` (synthetic, with version field)
- `CLAUDE.md`
- `.claude/claude-md/workflow.md` (only in `after-*` scenarios)

**Verification**: `ls migrations/test-fixtures/0009/{before-fresh,before-inlined-pristine,before-inlined-customised,after-vendored,after-idempotent}` — all exist.

### T8 — Extend `migrations/run-tests.sh`

Add `test_migration_0009()` function. For each step's idempotency check,
assert `not-applied` on every `before-*` fixture and `applied` on every
`after-*` fixture. Add 4 detection-specific assertions (Step 4 detection
returns "needs extraction" on inlined fixtures, "no inline" on fresh and
after fixtures).

Target: ≥20 assertions. Steps 1, 2, 3, 5 each get 5 fixture checks
(5 × 4 = 20) + Step 4 detection adds 4 = 24.

**Verification**: `bash migrations/run-tests.sh 0009` exits 0 with PASS ≥ 20.

### T9 — Bump `skill/SKILL.md` version 1.7.0 → 1.8.0

Single-line frontmatter edit.

**Verification**: `grep -q '^version: 1.8.0' skill/SKILL.md`

### T10 — Write ADR `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md`

Standard ADR shape. Status Accepted, Date 2026-05-13.

Sections:
- Context: 646L cparx, 372L fx-signal-agent, root cause is migration 0000
  Step 4's `cat`.
- Decision: vendor as `.claude/claude-md/workflow.md`; CLAUDE.md links;
  meta-repo never referenced at runtime.
- Alternatives Rejected: symlink (breaks self-containment), runtime fetch
  (network dependency at agent startup), markdown `@import` (not
  supported in CLAUDE.md by Claude Code).
- Consequences: per-repo update flow via migration system; new projects
  vendor on install; existing projects upgrade via 0009.

**Verification**: `test -f docs/decisions/0021-vendor-workflow-block-instead-of-inline.md`

### T11 — Update CHANGELOG + migrations index + README

- `CHANGELOG.md`: add `[1.8.0] — Unreleased` section above `[1.7.0]`.
- `migrations/README.md`: add row for 0009 in the migration index table.
- Top-level `README.md`: spot-check for any "CLAUDE.md inlines workflow"
  claim that needs correcting; otherwise no change.

**Verification**: `grep -q "1.8.0" CHANGELOG.md && grep -q "0009" migrations/README.md`

### T12 — Run-tests pass

Execute `bash migrations/run-tests.sh 0009`. Iterate fixtures + harness
until 20+ PASS, 0 FAIL.

### T13 — Two-stage review + /cso

- Stage 1 `/review` on phase diff → REVIEW.md.
- Stage 2 `superpowers:requesting-code-review` (independent agent) →
  REVIEW.md Stage 2 section.
- `/cso` (this migration auto-rewrites CLAUDE.md in arbitrary registered
  repos — security-relevant boundary) → SECURITY.md.
- Compose VERIFICATION.md with 1:1 evidence per acceptance criterion.

## Dependency graph

```
T1 (vendor source) → T2 (patch 0000) → T4 (write 0009) → T7 (fixtures) → T8 (run-tests) → T12 (run pass)
                  → T3 (template H1)
T5 (setup skill) ← parallel after T2
T6 (update skill) ← parallel after T4
T9 (version bump) ← after T4
T10 (ADR) ← parallel any time
T11 (CHANGELOG/README) ← after T9
T13 (review/cso) ← after T12
```

T1, T3, T5, T6, T10 can run in parallel waves where helpful. T2 must
precede T7 (fixtures depend on knowing the new 0000 shape). T8 depends on
T7. T12 depends on T8.

## Goal-backward verification

For each acceptance criterion in CONTEXT.md, what evidence proves it?

| Criterion | Evidence file |
|---|---|
| migration 0009 exists, frontmatter bumps `to_version` 1.7→1.8 | `head -10 migrations/0009-vendor-claude-md-sections.md` |
| setup + update use vendor mode | diff in `migrations/0000-baseline.md`, `setup/SKILL.md`, `update/SKILL.md` |
| 20+/20+ test PASS | `bash migrations/run-tests.sh 0009` exit 0 |
| ADR 0021 exists | `test -f docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` |
| README + index + CHANGELOG updated | `git diff main -- CHANGELOG.md migrations/README.md` |
| Two-stage review + /cso | `REVIEW.md` (both stages), `SECURITY.md` |
