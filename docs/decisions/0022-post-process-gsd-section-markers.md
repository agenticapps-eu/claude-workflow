# ADR 0022 — Post-process GSD section markers via downstream hook (not upstream patch)

**Status**: Accepted
**Date**: 2026-05-13
**Phase**: 07 / Migration 0010 (v1.8.0 → v1.9.0)
**Supersedes**: none
**Related**: ADR 0021 (vendor workflow block — handles a different inlined block)

## Context

After migration 0009 (ADR 0021) vendors the Superpowers/GSD/gstack
workflow block to `.claude/claude-md/workflow.md`, consumer CLAUDE.md
files still carry inlined content wrapped by GSD section markers:

```text
<!-- GSD:project-start source:PROJECT.md -->
## Project
...18 lines of project summary...
<!-- GSD:project-end -->
```

The seven managed sections (`project`, `stack`, `conventions`,
`architecture`, `skills`, `workflow`, `profile`) account for ~265 lines
in `factiv/cparx/CLAUDE.md`. After 0009 ships, cparx CLAUDE.md is still
~496 lines — above the 200-line context-budget target.

### Source identification

Step 1a of the phase's discuss-phase investigation traced the marker
emission to:

- **Module:** `~/.claude/get-shit-done/bin/lib/profile-output.cjs`
- **Function:** `buildSection(sectionName, sourceFile, content)` line 236
- **CLI entry:** `gsd-tools generate-claude-md`
- **Owner:** Upstream `pi-agentic-apps-workflow` family (provenance via
  shared templates with `~/Sourcecode/agenticapps/open-design/.pi/gsd/`),
  cross-repo to `claude-workflow`.
- **Trigger:** On-demand only. User invokes via Bash. Not currently a
  hook. Not auto-invoked. Confirmed by grep across `~/.claude/`,
  installed plugins, and consumer-project hooks.
- **Critical capability:** `--auto` flag at `cmdGenerateClaudeMd()` line
  981 calls `detectManualEdit()`. When a section's current content
  diverges from what gsd-tools would re-generate, the section is added
  to `sectionsSkipped` and left alone. Without `--auto`, the section is
  overwritten unconditionally via `updateSection()` at line 252.

### Source label vs file path

The `source:` HTML comment attribute is a **display label**, not a real
path. gsd-tools generates `source:PROJECT.md` but reads from
`.planning/PROJECT.md`. The mapping is hard-coded in `generateXxxSection`
functions:

| `source:` label | Actual file read by gsd-tools |
|---|---|
| `PROJECT.md` | `.planning/PROJECT.md` |
| `codebase/STACK.md` | `.planning/codebase/STACK.md` |
| `research/STACK.md` | `.planning/research/STACK.md` (fallback) |
| `STACK.md` | `.planning/codebase/STACK.md` (fallback variant) |
| `CONVENTIONS.md` | `.planning/codebase/CONVENTIONS.md` |
| `ARCHITECTURE.md` | `.planning/codebase/ARCHITECTURE.md` |
| `skills/` | `.claude/skills/` (autodiscovered, no file) |
| `GSD defaults` | (hardcoded constant — no file) |

A downstream post-processor must replicate this mapping to generate
correct reference links.

## Decision

**Ship a downstream post-processor hook in `claude-workflow`. Do NOT
patch `gsd-tools` upstream as the primary fix.**

The post-processor is a POSIX bash 3.2+ script
`templates/.claude/hooks/normalize-claude-md.sh` vendored into consumer
projects by migration 0010 and registered as a Claude Code PostToolUse
hook on `Edit|Write|MultiEdit`. The script:

1. Walks CLAUDE.md line-by-line, finding `<!-- GSD:{slug}-start[ source:{label}] --> ... <!-- GSD:{slug}-end -->` blocks.
2. Rewrites each block to a self-closing reference form:
   ```text
   <!-- GSD:{slug} source:{label} /-->
   ## {Heading}
   See [`{linkPath}`](./{linkPath}) — auto-synced.
   ```
3. Resolves `source:` labels to real file paths (per the table above).
4. Preserves blocks where the resolved file path is missing
   (source-existence safety; never loses information).
5. Special-cases `workflow` (removes the block entirely when 0009's
   `.claude/claude-md/workflow.md` exists) and `profile` (emits a
   `/gsd-profile-user` placeholder, since the section has no `source:`
   attribute and no on-disk source file to link to).
6. Collapses runs of 2+ consecutive blank lines down to 1 (mirroring
   `gsd-tools`' own normalization in `detectManualEdit` at line 260,
   `s.trim().replace(/\n{3,}/g, '\n\n')`).
7. Atomically rewrites the file only when content has changed (avoids
   re-triggering PostToolUse on its own write).

Migration 0010 also runs the script as a one-shot during apply
(user-confirmed with diff preview), seeding existing CLAUDE.md files.

## Alternatives rejected

### Alt-1: Patch `gsd-tools` upstream with a `--reference-mode` flag

Add a flag to `gsd-tools generate-claude-md` so `buildSection` emits
the self-closing form natively. Optionally surface as
`.planning/config.json` key `claude_md.compile_mode: "reference"`.

**Why rejected (as primary fix):**
- Cross-repo work in `pi-agentic-apps-workflow`. Coordination,
  review, release cadence — out of `claude-workflow`'s control.
- Doesn't help projects on older gsd-tools versions (1.34.2 is the
  current installed version; older versions are still in the wild).
- Slower feedback loop: cparx needs to drop ≤200L now, not after an
  upstream release cycle.
- Doesn't catch hand-edited inlined blocks (rare but happens — cparx's
  inlined state on disk pre-dates this phase's investigation).

**Recommended as follow-up:** A PR to `pi-agentic-apps-workflow`
introducing `--reference-mode` would be the root-cause fix. After
upstream lands, the downstream post-processor becomes a defense-in-depth
no-op (the regex still works, but there's nothing to normalize once
gsd-tools emits the reference form natively).

### Alt-2: Standalone CLI + cron/launchd

Ship `bin/normalize-claude-md.sh` as a project-level executable, run
manually or via cron/launchd. No Claude Code hook integration.

**Why rejected:**
- Manual; defeats the "ongoing protection" requirement (project drifts
  back to inlined state between cron runs).
- Per-OS scheduler config (launchd on macOS, systemd-timer on Linux,
  Task Scheduler on Windows). Install complexity.
- No event-driven trigger; cron-based "ongoing" has a long
  inconsistency window.

### Alt-3: Node script with HTML comment parser

Ship `.claude/hooks/normalize-claude-md.mjs` using a proper HTML comment
parser (parse5 or hand-rolled FSM) for edge cases the bash regex can't
handle.

**Why rejected:**
- Adds runtime dependency on node. Some consumer projects (Go-only
  services, Python services) don't have node installed.
- Either adds an npm install step or vendors `node_modules` — both
  bloat the template.
- The edge cases (nested markers, embedded `-->` in attribute values)
  don't occur in practice — the marker format is generated by `gsd-tools`'
  `buildSection` and is always line-leading and single-line.

## Consequences

### Good

- **Time-to-cparx-relief:** hours, not weeks. Migration 0010 lands in
  this release; applied to cparx, line count drops 647L → projected
  ~270L (depends on non-GSD content; ≤200L is a stretch goal — see
  Risks below).
- **Blast radius minimised:** changes scoped to `claude-workflow`. No
  upstream PRs.
- **Ongoing protection:** PostToolUse hook catches any future
  inflation (e.g., a user running `gsd-tools generate-claude-md`
  without `--auto`).
- **Idempotent steady state:** repeated `gsd-tools` runs produce
  inlined blocks; PostToolUse re-normalizes; everything converges to
  the same self-closing form within one Edit/Write cycle.
- **Source-existence safety:** the migration never deletes content if
  the linked file is missing — preserves information by default.

### Bad / risks

- **Fights upstream.** Without `--auto`, `gsd-tools` re-inflates
  sections (replaces self-closing form with full inline content via
  `updateSection` line 252). PostToolUse on the subsequent Edit
  catches this, but there's a brief inconsistent window. Mitigation:
  document the `--auto` flag in the migration's apply prose; encourage
  users to install a shell alias.
- **Bash regex parsing.** Robust enough for the canonical marker shape
  but vulnerable to weird whitespace inside `<!-- ... -->`. The greedy
  `.+` capture with trailing whitespace trim handles `source:GSD
  defaults` (label with spaces); fuzzing-style edge cases (e.g.,
  `<!-- GSD:project-start -->` embedded in a fenced code block) would
  match incorrectly. Mitigation: line-leading anchor (`^<!--`) keeps
  embedded markers within code blocks safe most of the time. Verified
  in fixture `with-0009-vendored.md`.
- **Line-count target gap.** cparx is projected to land at ~270L after
  0009+0010, not the user's stated ~165L target. The gap is non-GSD
  content (gstack skill table, anti-patterns list, repo structure ASCII
  diagram, project-specific notes — ~232L). Closing the gap requires a
  follow-up phase trimming non-GSD content; out of scope for 0010.
  Documented in VERIFICATION.md with empirical line-count math.
- **The `workflow` block removal is a behavior change.** Pre-0010, the
  GSD `workflow` block held a short "GSD Workflow Enforcement"
  paragraph distinct from the Superpowers integration block 0009
  vendored. 0010 removes the GSD `workflow` block entirely on the
  assumption that the `.claude/claude-md/workflow.md` file (from 0009)
  is the single source of workflow truth. Users who relied on the
  shorter GSD `workflow` paragraph as the canonical version lose it.
  Mitigation: 0009's vendored file is more comprehensive (includes
  commitment ritual, Red Flags table) and supersedes the shorter GSD
  paragraph anyway. The migration's apply prose notes this.

### Neutral

- **Marker format compatibility with `gsd-tools`.** The self-closing
  form `<!-- GSD:{slug} source:{label} /-->` is invisible to gsd-tools'
  `extractSectionContent` (searches for the literal `-start` substring
  at line 226). Effects:
  - `gsd-tools generate-claude-md --auto`: never sees the section,
    falls through to `updateSection`'s "append" branch (line 254)
    which adds a fresh inlined block at file-end.
  - PostToolUse re-normalizes the appended block back to self-closing
    on the next Edit/Write of CLAUDE.md.
  - Steady state: one self-closing marker per slug; transient
    appended blocks are normalized within one tool call.
  - **Garbage risk:** if `gsd-tools` runs multiple times between
    PostToolUse fires, multiple appended blocks accumulate. The
    post-processor processes them all in one pass (each `-start...-end`
    becomes a self-closing form, then `collapse_blank_runs` tidies
    up spacing). No dedup is needed for the *self-closing* markers
    because gsd-tools never emits them (only `-start`/`-end` pairs).

## 0009 / 0010 boundary

Migration 0009 handles the inlined **Superpowers Integration Hooks**
block — a different inlined-content shape, anchored by `^#{2,4}
Superpowers Integration Hooks \(MANDATORY` and (in the smoking-gun
case) `# CLAUDE.md Sections — paste into your project's CLAUDE.md`. No
HTML comment markers; emitted by claude-workflow's own
`migrations/0000-baseline.md` Step 4.

Migration 0010 handles the **GSD-managed section blocks** —
HTML-comment-wrapped, emitted by `gsd-tools` (upstream). No regex
overlap; the two migrations operate on disjoint shapes within CLAUDE.md.

| Shape | 0009 | 0010 |
|---|---|---|
| `^#{2,4} Superpowers Integration Hooks \(MANDATORY` | extracts | leaves alone |
| `^<!-- GSD:[a-z]+-start` | leaves alone | normalizes |
| `# CLAUDE.md Sections — paste into your project's CLAUDE.md` | extracts | leaves alone |
| Vendored reference `## Workflow / See [.claude/claude-md/workflow.md]` (5-line block from 0009) | emits | leaves alone (no `<!-- GSD: -->` marker; regex skips) |

The post-processor's regex `^<!--[[:space:]]*GSD:([a-z]+)-start` cannot
match anything 0009 produces or any prose 0009 leaves behind.

## Verification

`migrations/run-tests.sh test_migration_0010()` runs 7 assertions:

1. `fresh.md` (no markers): script is a no-op.
2. `inlined-7-sections.md`: all 7 marker blocks normalize byte-for-byte
   against expected golden.
3. `inlined-source-missing.md`: block with missing source is preserved;
   other blocks normalize.
4. `with-0009-vendored.md`: 0009's reference is untouched; inlined
   block is normalized.
5. `cparx-shape.md`: 339L → ≤200L (empirical: 147L on the current
   fixture).
6. Idempotency: second invocation produces identical output (no churn).
7. Missing input: script exits non-zero (operational safety).

All seven PASS on commit `feat(GREEN): post-process GSD section markers
in CLAUDE.md` (`3bf6727`).

End-to-end cparx verification (applying both 0009 and 0010 to a real
copy of `factiv/cparx/CLAUDE.md`) is captured in
`.planning/phases/07-post-process-gsd-sections/VERIFICATION.md`.

## TODOs / follow-ups

- **PR to `pi-agentic-apps-workflow`** adding `--reference-mode` to
  `gsd-tools generate-claude-md`. After upstream lands, 0010's
  post-processor becomes defense-in-depth and the migration's apply
  prose can soften the `--auto` recommendation.
- **`bin/normalize-claude-md.sh` wrapper** in the scaffolder repo that
  re-runs the post-processor against all consumer repos in a family
  (for the case where a user mass-runs `gsd-tools generate-claude-md`
  across all repos and needs to re-normalize en masse).
- **Phase 08 candidate:** trim non-GSD content in cparx CLAUDE.md
  (gstack skill table, anti-patterns list, repo structure diagram)
  if cparx still exceeds the 200L target after 0010 applies.
