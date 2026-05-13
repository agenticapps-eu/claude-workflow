# Phase 07 — Post-process GSD section markers in CLAUDE.md

**Migration:** 0010-post-process-gsd-sections
**Version bump:** 1.8.0 → 1.9.0
**Date opened:** 2026-05-13
**Predecessor:** Migration 0009 (vendored workflow block, 1.7.0 → 1.8.0)
**Goal:** Drop the ~265-line inlined-content footprint in `<!-- GSD:{slug}-start -->`-wrapped sections of CLAUDE.md down to a 3-line reference-link form, bringing cparx CLAUDE.md from ~496L (post-0009) to ≤200L.

---

## Background

After migration 0009 ships, `cparx/CLAUDE.md` is still ~496 lines. The bulk
of the remaining bloat lives between lines 351–615 in seven HTML-comment
marker blocks:

| Slug | source: label | Lines | Real source file |
|---|---|---|---|
| project | `PROJECT.md` | ~17 | `.planning/PROJECT.md` |
| stack | `codebase/STACK.md` | ~45 | `.planning/codebase/STACK.md` |
| conventions | `CONVENTIONS.md` | ~75 | `.planning/codebase/CONVENTIONS.md` |
| architecture | `ARCHITECTURE.md` | ~95 | `.planning/codebase/ARCHITECTURE.md` |
| skills | `skills/` | ~8 | `.claude/skills/` (autodiscovered) |
| workflow | `GSD defaults` | ~12 | (none — hardcoded constant) |
| profile | (no source attr) | ~6 | (managed by `generate-claude-profile`) |

The `source:` attribute is a **display label**, not a real file path. The
generator maps each slug to a real path under `.planning/` (see Decision A).

---

## Decisions

### Decision A — Source identification (gating decision)

**Question:** What writes the `<!-- GSD:{slug}-start source:{path} -->`
markers? Without this answer, post-processor design is guessing.

**Finding:** The writer is the upstream `gsd-tools` CLI v1.34.2, installed at
`~/.claude/get-shit-done/`, NOT owned by `claude-workflow`. Specifically:

- **Module:** `~/.claude/get-shit-done/bin/lib/profile-output.cjs`
- **Function:** `buildSection(sectionName, sourceFile, content)` at lines
  236–242 — emits the exact `<!-- GSD:{sectionName}-start source:{sourceFile} -->`
  / `<!-- GSD:{sectionName}-end -->` pair.
- **Entry point:** `gsd-tools generate-claude-md` (CLI subcommand routed
  through `bin/gsd-tools.cjs` line 932).
- **Trigger:** ON-DEMAND only. Confirmed by greping all installed skills,
  plugins, and hooks — no auto-invocation. User runs it manually via Bash
  (`node $HOME/.claude/get-shit-done/bin/gsd-tools.cjs generate-claude-md
  --output CLAUDE.md`). The `workflows/new-project.md` step at line 1135
  uses it during initial project scaffold, then it's silent.
- **Critical capability — `detectManualEdit()`:** lines 257–262 + 980–991.
  When called with `--auto`, gsd-tools compares each section's current
  content (normalised: trimmed, ≥3 blank-lines collapsed to 2) against
  what it would generate fresh. If they differ, the section is added to
  `sectionsSkipped` and left alone.
- **Provenance:** `~/.claude/get-shit-done/` has no package.json or README;
  templates (`templates/claude-md.md`) reference patterns shared with
  `~/Sourcecode/agenticapps/open-design/.pi/gsd/templates/claude-md.md`,
  putting this in the `pi-agentic-apps-workflow` family lineage.
  Cross-repo to `claude-workflow`.

**Implication:** The post-processor must coexist with gsd-tools. Without
`--auto`, gsd-tools unconditionally overwrites managed sections (line 992
`updateSection` calls run regardless). With `--auto`, gsd-tools respects
manual edits — and the reference-link form IS effectively a manual edit
from gsd-tools' perspective.

---

### Decision B — Post-processor design

**Question:** What exact transformation does the post-processor apply?

**Chosen design:**

For each `<!-- GSD:{slug}-start[ source:{path}] -->...<!-- GSD:{slug}-end -->`
block found in `CLAUDE.md`, replace the entire block with the
self-closing reference form:

```text
<!-- GSD:{slug} source:{path} /-->
## {original H2 heading from the block}
See [`{linkPath}`](./{linkPath}) — auto-synced.
```

Where `{linkPath}` resolves the `source:` label to the real file path
gsd-tools uses internally:

| source: label | Resolves to |
|---|---|
| `PROJECT.md` | `.planning/PROJECT.md` |
| `codebase/STACK.md` | `.planning/codebase/STACK.md` |
| `research/STACK.md` | `.planning/research/STACK.md` |
| `CONVENTIONS.md` | `.planning/codebase/CONVENTIONS.md` |
| `ARCHITECTURE.md` | `.planning/codebase/ARCHITECTURE.md` |
| `STACK.md` | `.planning/codebase/STACK.md` (fallback variant) |
| `skills/` | `.claude/skills/` |
| `GSD defaults` | (no link — keep heading only, content lives in vendored `workflow.md` from migration 0009) |
| (no source) | (no link — `profile` section; show placeholder only) |

**Rules:**

1. **Idempotent.** If the script encounters a self-closing form
   (`<!-- GSD:{slug} source:{path} /-->`) with no matching `-end` marker
   following, no-op for that section.
2. **Source-existence safety.** Before replacing a block, resolve the
   `source:` label to its real file path and verify the file exists. If
   missing, **preserve the inlined content unchanged** and emit a warning
   to stderr. Never lose information.
3. **Scope guard.** Regex matches `<!-- GSD:{slug}-start[ optional space and source attr][ space]-->`
   exactly. The vendored 0009 reference block uses no markers, so this
   regex cannot match it.
4. **Special-case `workflow`:** the canonical content is now in
   `.claude/claude-md/workflow.md` (from 0009). The post-processor SKIPS
   the `workflow` block entirely if the 0009 vendored file exists — the
   block is redundant once 0009 has applied. If the 0009 vendored file
   doesn't exist, fall back to the standard reference-link form pointing
   at `(none — internal)`.
5. **Special-case `profile`:** no `source:` attribute. Replace with:
   ```
   <!-- GSD:profile /-->
   ## Developer Profile
   > Run `/gsd-profile-user` to generate. Managed by `generate-claude-profile`.
   ```

**Why this form (vs alternatives in RESEARCH.md):**

- Self-closing `<!-- GSD:{slug} /-->` is a signal to gsd-tools that the
  section has been intentionally simplified. gsd-tools' `extractSectionContent`
  searches for `-start` (line 226) — the self-closing form contains no
  `-start`, so gsd-tools' `hasMarkers` check (line 978) returns false,
  and `updateSection` either appends a new section (creating a duplicate)
  or, more usefully, the user runs gsd-tools with `--auto` and the block
  goes through `detectManualEdit`. **Risk:** without `--auto`,
  `updateSection`'s "appended" branch (line 254) appends a fresh inlined
  block at file-end, leaving the reference link in place AND adding
  inline content. Document this risk in the ADR and in CHANGELOG; the
  mitigation is `--auto` plus a `bin/normalize-claude-md.sh` re-run.

---

### Decision C — Install point

**Question:** Where does the post-processor live and how is it triggered?

**Chosen install point:**

1. **Script location:** `templates/.claude/hooks/normalize-claude-md.sh`
   — vendored shell script (pure POSIX + bash regex; no node dependency
   since not all consumer projects have node available). Mirrors the
   existing pattern of other hook scripts in `templates/.claude/hooks/`
   (database-sentinel.sh, design-shotgun-gate.sh, etc.).
2. **Hook registration:** PostToolUse hook on `Edit|Write|MultiEdit`,
   registered in `templates/claude-settings.json`. The hook script reads
   `$CLAUDE_TOOL_INPUT_file_path` (or parses stdin JSON) and only
   normalizes when the changed path ends with `/CLAUDE.md`.
3. **Standalone runnable:** Same script callable directly as
   `.claude/hooks/normalize-claude-md.sh CLAUDE.md` for one-shot use.
   The migration's `apply` block runs it once during install.

**Alternatives rejected:**

- **SessionStart hook:** runs once per session, would catch CLAUDE.md
  bloat caused by gsd-tools runs in PREVIOUS sessions but adds latency
  to every session bootstrap. We already have 2 SessionStart hooks
  (session-bootstrap, architecture-audit-check). Rejected as too eager.
- **Stop hook:** runs after every assistant turn. Excessive — CLAUDE.md
  doesn't change that often. Rejected.
- **`bin/normalize-claude-md.sh` + cron/launchd:** out-of-band, adds
  install complexity (per-OS scheduler config), poor visibility.
  Rejected.
- **PostToolUse on Bash matching `gsd-tools generate-claude-md`:** more
  targeted but breaks if user invokes gsd-tools via wrapper or alias.
  Less robust than file-path-based filter on Edit/Write of CLAUDE.md.
  Rejected as a primary trigger but kept as a bonus check (the hook
  also runs after any Bash command matching `gsd-tools.*generate-claude-md`).

**Rationale:** Co-location with the project that needs it; consistent
with claude-workflow's existing hook pattern; idempotent so PostToolUse
re-fires are cheap.

---

### Decision D — One-shot vs ongoing

**Question:** Does the migration run the post-processor against existing
CLAUDE.md content (one-shot seed), or only install the hook (ongoing)?

**Chosen:** **Both.**

1. **One-shot:** The migration's `apply` block detects whether the target
   project's `CLAUDE.md` has any `<!-- GSD:{slug}-start -->` markers, and
   if so, runs the normalize script against the file (after user
   confirmation with diff preview, consistent with 0009's pattern).
2. **Ongoing:** The hook is installed and registered. Future writes to
   CLAUDE.md (including by gsd-tools when run without `--auto`) trigger
   the post-processor automatically.

**Steady state:** A project on v1.9.0 should never carry inlined
GSD-marker content for more than one Edit/Write tool call.

---

### Decision E — Interaction with migration 0009

**Question:** Does the 0010 post-processor risk touching 0009's vendored
workflow block?

**Answer: No, by construction.**

- 0009's vendored workflow block lives at `.claude/claude-md/workflow.md`
  (a separate file, not in CLAUDE.md).
- 0009's CLAUDE.md reference is a 5-line plain markdown reference,
  containing no `<!-- GSD: -->` markers.
- The post-processor regex (`<!-- GSD:{slug}-start[ optional source]
  -->...<!-- GSD:{slug}-end -->`) cannot match anything in 0009's output.

**Edge case:** A project that has applied 0010 but NOT 0009 would still
have an inlined `<!-- GSD:workflow-start source:GSD defaults -->` block.
The post-processor handles this (Decision B, special-case 4): if the
0009 vendored file (`.claude/claude-md/workflow.md`) doesn't exist,
the post-processor falls back to a heading-only reference form. This
keeps 0010 forward-compatible with projects that skipped 0009.

---

### Decision F — Coverage matrix expectation

**Target:** After both 0009 and 0010 apply to a copy of cparx CLAUDE.md,
total lines ≤ 200L (user's stated target ~165L).

**Estimated arithmetic:**

| Step | Lines | Delta |
|---|---|---|
| Pre-0009 | 647 | (current) |
| Post-0009 (workflow block vendored) | ~497 | −150 |
| Post-0010 (7 marker blocks → 7 × 3-line refs + blank lines) | ~250 | −247 |

Estimate may be high or low — verified empirically in the run-tests.sh
fixture (Decision G). If the estimate exceeds the ≤200L target, evaluate
whether the user's "~165L" projection requires also rewriting some
non-marker inlined content (out of scope for 0010).

---

### Decision G — Verification fixtures

**Question:** How do we prove the post-processor works without touching
the real cparx CLAUDE.md?

**Chosen fixtures (added to `migrations/test-fixtures/0010/`):**

1. **`fresh.md`** — no markers, no-op expected.
2. **`inlined-7-sections.md`** — synthetic CLAUDE.md with all 7 marker
   blocks (project, stack, conventions, architecture, skills, workflow,
   profile) inlined. Post-processor expected to drop ≥ 200L.
3. **`inlined-source-missing.md`** — same as above but with
   `<!-- GSD:project-start source:NONEXISTENT.md -->`. Post-processor
   expected to PRESERVE that block (safety rule from Decision B-2).
4. **`after-normalized.md`** — output of (2) → post-processor. Re-running
   the post-processor against this MUST be a no-op (idempotency).
5. **`cparx-shape.md`** — copy of cparx/CLAUDE.md (lines 1–647) but with
   PII / project-specific identifiers redacted. Post-processor + assertion
   that line count drops ≤ 200L.

**run-tests.sh assertions:** for each fixture, expected output exists at
`expected/<name>.md`. The harness runs the post-processor and `diff`s
against the expected output. Plus a special "idempotent" pass that runs
the post-processor twice and asserts the second run is a no-op (diff
shows zero changes).

---

## Acceptance criteria

- [ ] `migrations/0010-post-process-gsd-sections.md` exists with `apply`
      and `revert` blocks. Frontmatter: `from_version: 1.8.0,
      to_version: 1.9.0`.
- [ ] Post-processor script at
      `templates/.claude/hooks/normalize-claude-md.sh`. POSIX-safe,
      idempotent, source-existence-safe.
- [ ] Hook registered in `templates/claude-settings.json` PostToolUse
      block for `Edit|Write|MultiEdit`.
- [ ] `migrations/run-tests.sh` `test_migration_0010()` stanza covers 5
      fixtures with ~15 assertions; all PASS. All prior fixtures
      (0001 + 0009) still PASS — no regressions.
- [ ] ADR in `docs/decisions/NNNN-post-process-gsd-section-markers.md`
      capturing source identification, post-processor vs upstream-patch
      trade-off, the 0009/0010 boundary, and the `--auto`-flag risk.
- [ ] Verification: applying 0009 + 0010 to a *copy* of cparx CLAUDE.md
      drops line count from 647L to ≤200L. Document before/after in
      VERIFICATION.md.
- [ ] Two-stage review (`/review` stage 1 + `superpowers:requesting-code-review`
      stage 2) and `/cso` audit complete with no unresolved BLOCKs.

---

## Out of scope

- **Patching gsd-tools upstream.** Adding a native `--reference-mode`
  flag to `~/.claude/get-shit-done/bin/lib/profile-output.cjs` is the
  root-cause fix. ADR documents why we defer it: cross-repo coordination
  with pi-agentic-apps-workflow, longer feedback loop, and the
  post-processor remains useful even after upstream patches as a
  defense-in-depth for older gsd-tools versions.
- **`profile` section overhaul.** Decision B handles the no-source-attr
  case minimally. A richer profile reference form is a follow-up.
- **Other non-marker inlined bloat in CLAUDE.md** (e.g., gstack skill
  table, ## Skill routing block, project-specific notes). Out of scope
  for 0010; revisit if cparx still exceeds the target line count after
  0009 + 0010 land.
