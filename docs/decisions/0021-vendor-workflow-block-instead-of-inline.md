# ADR-0021: Vendor the workflow block as a per-repo file instead of inlining it into CLAUDE.md

**Status**: Accepted
**Date**: 2026-05-13
**Linear**: n/a (internal infrastructure)
**Supersedes (in part)**: ADR-0013 (migration framework — extends its consumer-repo-update model)
**Migration**: 0009-vendor-claude-md-sections.md (1.7.0 → 1.8.0)

## Context

Migration `0000-baseline.md` Step 4 has been the canonical "ship the
AgenticApps workflow into a project" entrypoint since v1.2.0. It works by
literally `cat`-ing `templates/claude-md-sections.md` (~150 lines of
Superpowers/GSD/gstack hooks, commitment ritual, rationalization table,
13 red flags) into the consumer project's CLAUDE.md:

```bash
echo "" >> CLAUDE.md
cat ~/.claude/skills/agenticapps-workflow/templates/claude-md-sections.md >> CLAUDE.md
```

CLAUDE.md is **always loaded** into every Claude Code conversation in the
project. The recommended budget is ≤200 lines. By inlining 150 lines of
boilerplate, every project starts ~150 lines into its budget before any
project-specific content. Audit on 2026-05-13 found two factiv repos
materially blowing the budget for this reason:

| Repo | CLAUDE.md lines | Status |
|---|---:|---|
| `factiv/cparx/CLAUDE.md` | 646 | 3.23× over budget |
| `factiv/fx-signal-agent/CLAUDE.md` | 372 | 1.86× over budget |

`fx-signal-agent`'s CLAUDE.md retains the source template's literal H1
line (`# CLAUDE.md Sections — paste into your project's CLAUDE.md`),
proving the content was copied verbatim by the migration's `cat`. This is
the smoking gun.

The boilerplate is identical across every AgenticApps project. There is
no per-project customisation requirement for it — when the workflow
scaffolder bumps the hooks, every project should pick up the new version.
A vendored file with re-sync semantics fits this model exactly; an
inlined block does not (each consumer project would need a manual
multi-line edit to take an upgrade).

## Decision

**Vendor the workflow block as `<repo>/.claude/claude-md/workflow.md`.**
CLAUDE.md links to that path with a short reference block:

```markdown
## Workflow

This project follows the AgenticApps Superpowers + GSD + gstack workflow.
See [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md) for the
full hooks, rituals, and red-flag tables. That file is **vendored** by
`claude-workflow` migrations — re-run `/update-agenticapps-workflow` to
re-sync; do not edit it directly. Project-specific overrides go in this
CLAUDE.md.
```

Three properties this gives us:

1. **Self-contained repos.** The vendored file lives inside the project
   tree. Cloning the repo on a machine without the workflow scaffolder
   installed does not break anything that needs to read the workflow
   block — it's right there in `.claude/claude-md/workflow.md`. The
   `claude-workflow` meta-repo is a setup/update-time dependency, not a
   runtime dependency.
2. **Always-loaded budget protection.** CLAUDE.md drops from ~150 lines
   of boilerplate to ~7 lines of reference. Project-specific content gets
   the budget back.
3. **Migration-driven re-sync.** Future bumps to the workflow block ship
   as a new migration that copies the updated template into each
   project's `.claude/claude-md/workflow.md`, with byte-compare
   divergence detection that prompts the user before overwriting
   customised local copies.

**Detection + remediation for the existing inlined-block state.**
Migration 0009 detects the inlined block via a heading-level-agnostic
Superpowers regex (`^#{2,4} Superpowers Integration Hooks \(MANDATORY`)
and offers to extract + replace it with a reference, with a 3-way pick
(replace-with-canonical / preserve-customisation-as-vendored / skip).
The user always confirms before CLAUDE.md is mutated.

The regex is heading-level-agnostic by design: the deprecated
`templates/claude-md-sections.md` source emits the heading at H3
(`### Superpowers`), so cparx and fx-signal-agent have H3 on disk; the
new vendored canonical `templates/.claude/claude-md/workflow.md` emits
H2. The `^#{2,4}` range covers both shapes plus any future heading
re-numbering without code changes. A smoking-gun H1
(`^# CLAUDE.md Sections [—-] paste into your project's CLAUDE.md`,
em-dash class accepts both U+2014 and U+002D) is a separate signal that
also promotes detection to "inlined", catching projects where the
Superpowers heading was renamed during customisation but the H1 from
the verbatim paste survives.

**Patch migration 0000 in-place.** Step 4's apply block is rewritten to
write the vendored file + a short reference block, instead of `cat`-ing
the template into CLAUDE.md. Fresh installs go straight to the vendored
state from v1.8.0 forward. Migration 0000's pre-flight already refuses on
existing installs (`test -f
.claude/skills/agentic-apps-workflow/SKILL.md` → error), so this in-place
patch cannot affect any project past 1.2.0.

## Alternatives Rejected

### Symlink the consumer project's CLAUDE.md sections to the meta-repo

`<repo>/.claude/claude-md/workflow.md → ~/.claude/skills/agenticapps-workflow/templates/.claude/claude-md/workflow.md`

**Rejected**: defeats the self-contained-repo property. Cloning the repo
on a machine without the scaffolder leaves a dangling symlink. The
scaffolder also lives at a per-user path (`~/.claude/...`), so the
symlink isn't even portable across machines that *do* have it installed
in different locations.

### Runtime fetch from the meta-repo

`curl https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/claude-md/workflow.md`
on every Claude Code session.

**Rejected**: introduces a network dependency at agent startup. Any
network blip breaks Claude's ability to read the workflow block,
including in air-gapped or offline development. Also a meaningful
security boundary (fetching executable-influencing content over HTTP at
runtime).

### Use Claude Code's `@import` syntax to reference the meta-repo

CLAUDE.md contains `@import ~/.claude/skills/agenticapps-workflow/templates/.claude/claude-md/workflow.md`.

**Rejected**: Claude Code does not support `@import` in CLAUDE.md as of
2026-05. The reference style we use (`See [\`.claude/claude-md/workflow.md\`](...)`)
is a plain markdown link, which Claude reads when explicitly opened. That's
the supported pattern. Even if `@import` were added later, we'd still
prefer vendoring for the self-containment property.

### Reduce the workflow block to ≤30 lines and keep it inlined

**Rejected**: the block's content is the workflow contract — every hook,
rationalization, and red flag has been added based on past failure modes
(see ADRs 0014 through 0020). Reducing it would either drop enforcement
content (regressing past lessons) or compress it to terse hints that
Claude reads less reliably. The right tier for this content is the
always-loaded zone, but the right *location* is a referenced file, not
inline.

### Bundle migration 0010 (GSD compiler reference-mode for auto-managed sections) into the same release

**Rejected for this phase**. Cparx's CLAUDE.md is at 646 lines because
*both* the workflow block (this ADR's concern) and the GSD-managed
PROJECT/STACK/CONVENTIONS/ARCHITECTURE blocks are inlined. The audit was
explicit that getting cparx ≤200L requires changing the GSD compiler
behaviour too — but that's a different blast radius (touches GSD code,
not workflow-template content). Bundling them inflates the PR review
burden and entangles two unrelated risks. Migration 0010 is queued as a
follow-up phase. After 0009 alone, fx-signal-agent reaches ~201 lines
and cparx improves materially (646 → ~496) without the riskier GSD
compiler change.

## Consequences

### Positive

- New AgenticApps projects start with CLAUDE.md ≤200 lines by default.
- Existing projects on v1.7.0 can opt into the lighter shape via
  `/update-agenticapps-workflow`, with the migration runtime walking
  them through any divergence prompts.
- Workflow-block updates ship as small, reviewable migrations going
  forward (the canonical content lives in *one* place — the meta-repo's
  `templates/.claude/claude-md/workflow.md` — and propagates via
  byte-compare-driven re-sync).
- The "meta-repo is never referenced at runtime" property is now a
  documented invariant: enforced by file vendoring, surfaced in CLAUDE.md
  reference text ("That file is vendored by `claude-workflow` migrations"),
  and codified here.

### Negative

- One extra file in each repo (`.claude/claude-md/workflow.md`,
  ~150 lines). Negligible storage; no runtime cost since Claude only
  reads it when explicitly opened or referenced.
- The migration's Step 4 (inlined-block extraction) is the most novel
  logic in any migration so far — boundary detection over markdown
  content. It's gated by user confirmation and a diff preview, but it's
  more invasive than any prior migration step. Mitigated by hand-built
  test fixtures for the four user-facing scenarios (fresh / pristine /
  customised / already-vendored).
- Patching migration 0000 Step 4 in-place breaks the historical
  immutability convention (migrations are typically frozen once shipped).
  Justified because 0000's pre-flight already prevents re-execution
  against installed projects, so the change cannot affect anyone past
  1.2.0. A note in the patched Step 4 documents the rationale for future
  readers.
- `setup-agenticapps-workflow --target-version 1.2.0` (the documented
  "advanced — for installing a specific historical version, e.g. for
  reproducing an old project" path) no longer produces the literal
  v1.2.0 disk shape after the in-place 0000 patch. Instead it produces
  the v1.8.0 vendored shape (the migration chain stops at 0000's
  to_version of 1.2.0, but 0000 itself now writes the vendored layout).
  This is acceptable — no real user invokes `--target-version 1.2.0`
  for genuine historical reproduction; the flag exists for chain
  debugging — but the trade-off is undocumented in `setup/SKILL.md`'s
  flag table and would surprise anyone reading the flag's description.
  Flagged in Stage 2 review (FLAG-2); accepted as a documented
  limitation of the in-place patch.

### Neutral

- Cparx still over the 200-line CLAUDE.md budget after this migration
  (~496 lines, down from 646). Migration 0010 (GSD compiler
  reference-mode) is the path to ≤200L. Tracked as a follow-up.

## Implementation references

- Migration: `migrations/0009-vendor-claude-md-sections.md`
- Vendored source: `templates/.claude/claude-md/workflow.md`
- Patched bootstrap: `migrations/0000-baseline.md` Step 4
- Setup skill update: `setup/SKILL.md` (post-setup summary, migration history)
- Update skill update: `update/SKILL.md` (Step 5 divergence variant; failure modes table)
- Test fixtures: `migrations/test-fixtures/0009/`
- Test stanza: `migrations/run-tests.sh` `test_migration_0009()`
- Audit (problem statement): `~/Documents/Claude/Projects/agentic-workflow/factiv-claude-md-audit-2026-05-13.md`
- Phase artifacts: `.planning/phases/06-vendor-claude-md-sections/`
