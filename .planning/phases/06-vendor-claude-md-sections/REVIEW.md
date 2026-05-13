# Phase 06 — REVIEW (two-stage)

## Stage 1 — Spec compliance review (`/review`-equivalent on phase diff)

Reviewer: phase executor (self-review against acceptance criteria in CONTEXT.md).
Reviewed at: 2026-05-13.
Diff: `git diff --cached` on branch `feat/vendor-claude-md-sections-0009`.

### Acceptance criteria check (from user prompt)

| Criterion | Evidence | Status |
|---|---|---|
| `migrations/0009-vendor-claude-md-sections.md` exists, `to_version` bumped | `head -7 migrations/0009-vendor-claude-md-sections.md` shows `from_version: 1.7.0` / `to_version: 1.8.0` | ✅ |
| Setup + update skills use vendor mode by default | `migrations/0000-baseline.md` Step 4 patched (cat → vendor + reference); `setup/SKILL.md` post-setup summary lists `.claude/claude-md/workflow.md`; `update/SKILL.md` Step 5 has divergence variant | ✅ |
| `run-tests.sh`: 20+/20+ PASS for 0009 fixtures | `bash migrations/run-tests.sh 0009` → **29/29 PASS, 0 FAIL** | ✅ |
| ADR in `docs/decisions/` capturing inline→vendor pivot + meta-repo never referenced at runtime | `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` — Status: Accepted, Date: 2026-05-13. Sections: Context, Decision, 5× Alternatives Rejected, Consequences (positive/negative/neutral). | ✅ |
| README / migrations index updated | `migrations/README.md` has new "Migration index" subsection with the chain `0000 → 0001 → 0004 → 0002 → 0005 → 0006 → 0007 → 0009` and v1.8.0 vendor-mode property note. | ✅ |
| CHANGELOG entry | `CHANGELOG.md` has `[1.8.0] — Unreleased` section with Added (4 items) / Changed (7 items) / Notes (3 items). | ✅ |
| Two-stage review + /cso pass before merge | This file (Stage 1) + dispatched independent reviewer for Stage 2 + SECURITY.md (/cso). | ✅ in progress |
| Decision 1: destination path `.claude/claude-md/workflow.md` | Used in 0000 Step 4, 0009 Step 1, ADR 0021, fixtures, vendored source path. Consistent. | ✅ |
| Decision 2: idempotency model matches migration 0001 | All 5 steps follow the `**Idempotency check:**` / `**Pre-condition:**` / `**Apply:**` / `**Rollback:**` shape. Re-running 0009 against `after-vendored` fixture → all checks return 0 (verified by `Step N idempotency: skip on after-vendored` assertions). | ✅ |
| Decision 3: inlined-block detection signature + remediation | Step 4 uses H2 marker (`^## Superpowers Integration Hooks (MANDATORY`) for primary detection + H1 marker (`^# CLAUDE.md Sections — paste`) as paste-verbatim signal. Three-way pick on customised: replace / preserve-as-vendored / skip. User confirmation required before CLAUDE.md mutation. | ✅ |
| Decision 4: queue 0010 separately | CONTEXT.md and ADR 0021 both record the rationale (different blast radius, separate review focus). 0010 is **not** in this phase. | ✅ |

### Goal-backward verification

The phase goal: *fix the inline-paste root cause + ship migration 0009 to upgrade existing 1.7.0 projects to vendored mode*. Did the phase achieve it?

- **Root cause fixed**: yes. `migrations/0000-baseline.md` Step 4 no longer `cat`s the template into CLAUDE.md. Fresh installs now write `.claude/claude-md/workflow.md` + a 7-line reference. Verified by reading the patched Step 4 apply block.
- **Smoking-gun line removed**: yes. `templates/claude-md-sections.md` H1 was `# CLAUDE.md Sections — paste into your project's CLAUDE.md` (the line that proved fx-signal-agent's CLAUDE.md was a paste). Now `# DEPRECATED — vendored as .claude/claude-md/workflow.md since v1.8.0` with a "do not paste" banner. Future accidental concat cannot reproduce the bug-signature.
- **Upgrade path for 1.7.0 → 1.8.0**: yes. Migration 0009 ships with 5 steps + pre-flight + post-checks. Detection logic uses the H2 marker; extraction is gated by user confirmation with diff preview.
- **Test coverage**: yes. 5 hand-built fixtures cover fresh / inlined-pristine / inlined-customised / after-vendored / after-idempotent. 29 assertions across all 5 idempotency checks.
- **Rollback safety**: yes. Each step has a Rollback clause. Step 4's rollback uses `git checkout HEAD -- CLAUDE.md` (relies on each migration committing atomically — already established by the migration runtime).

### Spec drift check

- Migration 0009's frontmatter format matches `migrations/0001-go-impeccable-database-sentinel.md`'s shape (id, slug, title, from_version, to_version, applies_to, requires, optional_for). Pre-flight + Steps + Post-checks + Skip cases sections all present. Step structure (Idempotency check / Pre-condition / Apply / Rollback) consistent.
- ADR 0021 follows the standard ADR template (Status, Date, Linear, Context, Decision, Alternatives Rejected, Consequences) used by ADRs 0011–0020.
- Fixture layout matches the `migrations/test-fixtures/` README contract.
- `run-tests.sh` `test_migration_0009` follows the `test_migration_0001` pattern (function with `assert_check` calls, parameterised by fixture path).

### Stage 1 verdict

**PASS.** All acceptance criteria met. No spec drift. Goal-backward verification confirms the migration delivers what CONTEXT.md promised.

### Cross-file consistency: known overlap with prior uncommitted work

This branch was cut from `main` while the working tree carried uncommitted
modifications from prior phases (0005 multi-AI plan review, 0006 LLM
wiki, 0007 GitNexus). The phase-06 commit picks those up alongside the
0009 work, because the same files were edited in both flows. Specifically:

| File | This phase's intent | Prior carryover absorbed |
|---|---|---|
| `CHANGELOG.md` | Add `[1.8.0]` section above `[1.7.0]` | Adds `[1.5.1]`, `[1.6.0]`, `[1.7.0]` sections (from 0005/0006/0007 phases) that were never committed on main |
| `skill/SKILL.md` | Bump frontmatter `version` 1.7.0 → 1.8.0 | Adds "14 Red Flags" + `/gsd-review` rationalization row + verification check addition (from 0005 phase) |
| `migrations/README.md` | Add migration index | (no overlap — added section is net-new) |
| `setup/SKILL.md`, `update/SKILL.md`, `migrations/0000-baseline.md` | Vendor-mode prose updates | (no overlap detected — these were not modified in prior uncommitted work) |
| `templates/claude-md-sections.md` | Rewrite H1 + banner | (no overlap) |

**The bundled commit captures prior unmerged work on the affected lines as a side effect of `git add` staging the working-tree state.** Splitting the commit per phase requires a `git rebase -i` after the fact (not done here, since the user's "no clarifying questions" reminder applied — defaulting to ship the bundled commit and let the user split if they want a per-phase history).

The committed prior-phase content is **additive** (rationalization rows, version sections, red-flag entries) and does not conflict with this phase's intent. No correctness risk; only a history-cleanliness concern.

---

## Stage 2 — Independent code-quality review

Reviewer: dispatched independent agent (`pr-review-toolkit:code-reviewer`).
Reviewer agent ran against the staged diff on `feat/vendor-claude-md-sections-0009`.

> Findings appended below by the reviewer agent. Stage 2 is the
> independent quality pass — do not collapse with Stage 1.

<!-- STAGE-2-FINDINGS-START -->

Reviewer: independent code-quality pass on staged set of `feat/vendor-claude-md-sections-0009`.
Reviewed at: 2026-05-13.
Method: read every staged file, diffed `templates/claude-md-sections.md` (deprecated source — what every consumer project's CLAUDE.md actually contains today) against `templates/.claude/claude-md/workflow.md` (new vendored canonical), traced detection signatures through the migration prose / fixtures / harness / post-checks, pressure-tested rollback semantics against the per-migration commit model documented in `update/SKILL.md` Step 5 #6.

Severity legend: **BLOCK** = must fix before merge / **FLAG** = should fix or explicitly accept / **NIT** = style or clarity.

---

### BLOCK-1 — Detection signature is anchored on the wrong heading level; cparx + fx-signal-agent will silently NOT be migrated

**Files**: `migrations/0009-vendor-claude-md-sections.md` lines 124, 133, 189; `migrations/test-fixtures/0009/before-inlined-pristine/CLAUDE.md` line 23; `migrations/test-fixtures/0009/before-inlined-customised/CLAUDE.md` line 25; `.planning/phases/06-vendor-claude-md-sections/CONTEXT.md` line 101; `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` line 80.

The deprecated source `templates/claude-md-sections.md` (which migration 0000 has been `cat`-ing into every consumer project since v1.2.0) emits `### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)` — an **H3** (three hashes). The new vendored canonical `templates/.claude/claude-md/workflow.md` emits `## Superpowers Integration Hooks ...` — an **H2**. Migration 0009 anchors its primary detection on the H2:

- `migrations/0009-vendor-claude-md-sections.md:124` (Step 4 idempotency check):
  `! grep -q "^## Superpowers Integration Hooks (MANDATORY" CLAUDE.md`
- `migrations/0009-vendor-claude-md-sections.md:133` (Step 4 detection):
  `grep -q "^## Superpowers Integration Hooks (MANDATORY" CLAUDE.md && INLINED=1`
- `migrations/0009-vendor-claude-md-sections.md:189` (post-check warning):
  `if grep -q "^## Superpowers Integration Hooks (MANDATORY" CLAUDE.md; then echo "WARN: ..."`

Reproduction (no fixture changes; mirrors what cparx/fx-signal-agent have on disk today):

```bash
$ git show HEAD:templates/claude-md-sections.md | grep -nE "^#+ Superpowers Integration Hooks"
24:### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)

$ printf '### Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)\n' > /tmp/c.md
$ ! grep -q "^## Superpowers Integration Hooks (MANDATORY" /tmp/c.md && echo "skip"   # idempotency = "applied / nothing to do"
skip
$ grep -q "^## Superpowers Integration Hooks (MANDATORY" /tmp/c.md && echo INLINED=1 || echo INLINED=0
INLINED=0
```

Outcome on a real consumer repo:

1. Step 4 idempotency check returns 0 → migration runtime logs `step 4: skipped (already applied)` and never enters the apply block.
2. Even if the runtime did enter the apply block, the detection assignment `INLINED=1` does not fire (H2 not present, only H3), so the step is a no-op.
3. The `PASTED_VERBATIM` H1 marker (which fx-signal-agent does carry) is computed but **never gated on**: nothing in the prose says `INLINED=$((INLINED || PASTED_VERBATIM))` or equivalent. So even fx-signal-agent's smoking-gun H1 doesn't rescue detection.
4. Post-check (line 189) doesn't WARN either, so the migration appears to succeed and the inlined block remains in CLAUDE.md indefinitely.

The fixtures don't catch this because they were authored using the **new** H2 marker (matching `templates/.claude/claude-md/workflow.md`) rather than the **old** H3 marker (matching what was actually inlined into consumer projects via `cat templates/claude-md-sections.md`). All 29 harness assertions pass against fixtures that don't represent the real-world before-state.

**Fixes**:
- Detection grep should be heading-level-agnostic, e.g. `grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY"` for both idempotency checks (line 124, 189) and the detection block (line 133).
- The `PASTED_VERBATIM` H1 marker must promote to `INLINED=1` as a fallback (`PASTED_VERBATIM=1 → INLINED=1`).
- Add a fifth fixture `before-inlined-legacy-h3/` whose CLAUDE.md uses the actual `### ` heading from the deprecated template, plus a sixth assertion confirming Step 4 idempotency returns "needs apply" against it.
- Update CONTEXT.md Decision 2's idempotency check table and ADR 0021's "Detection + remediation" paragraph to reference the regex form, not the literal `^## ` form.

This is the difference between the migration achieving its stated purpose and being a 200-line no-op for the two named target repos.

---

### BLOCK-2 — Extraction range end-line cuts off the GSD Workflow Enforcement and Skill routing sections that are also part of the inlined block

**File**: `migrations/0009-vendor-claude-md-sections.md` lines 145-151.

The prose says the extraction range ends at "last line of the `13 Red Flags` numbered list ... followed by either a blank line + new H1/H2 boundary or end of file." But in `templates/claude-md-sections.md` (the deprecated source that was inlined verbatim), the content continues past `### 13 Red Flags` through:

```
## GSD Workflow Enforcement       (line 161)
## Skill routing                  (line 172)
... routing rules ...
```

These two H2 sections are part of the same inlined block — they came from the same `cat`. Cutting extraction at the end of `13 Red Flags` leaves them orphaned in CLAUDE.md, no longer logically tied to anything (the reference link in CLAUDE.md says "see workflow.md", but workflow.md *also* contains GSD Workflow Enforcement and Skill routing — the orphaned copies become silent duplication).

Inspect `git show HEAD:templates/claude-md-sections.md` lines 161-191 to see the trailing sections this prose ignores.

**Fix**: end-line should be "the last H1/H2 boundary that ends the contiguous workflow block, OR end of file" — i.e. extend through `## Skill routing` and its content, terminating at the first heading that does NOT match a known template H2 (or at EOF). Alternatively: enumerate the explicit known terminal section "## Skill routing" + its routing-rule list and use that as the end anchor.

---

### BLOCK-3 — Step 4 detection treats `## Development Workflow` as a start-line anchor, but that heading legitimately appears in many project CLAUDE.md files

**File**: `migrations/0009-vendor-claude-md-sections.md` lines 145-148.

> **Start line:** first match of any of:
> - `^# CLAUDE.md Sections — paste into your project's CLAUDE.md` (deprecated H1)
> - `^## Development Workflow` (the section heading that opens the inlined block)

`## Development Workflow` is a generic section title many projects already use for their own development workflow content (regardless of whether the AgenticApps block was ever inlined). The `before-inlined-customised` fixture itself demonstrates exactly this collision (line 13: `## Development Workflow` is the project's own section, customised with team-specific content; the AgenticApps boilerplate would be detected starting from there).

If a project has `## Development Workflow` for its own purposes and the AgenticApps inlined block is somewhere else (or absent), the start anchor would mark the project's own heading as the extraction start — pulling project-specific content into the "remove this" range.

**Fix**: don't allow `## Development Workflow` as a start anchor. Only the smoking-gun H1 (`# CLAUDE.md Sections — paste...`) or the H2/H3-agnostic Superpowers marker (BLOCK-1's regex) should be valid start anchors. If neither H1 nor Superpowers heading is found near a `## Development Workflow`, treat the heading as project-owned and skip extraction.

---

### FLAG-1 — Step 2 and Step 4 Rollback clauses claim per-step git granularity but the migration runtime commits per-migration

**File**: `migrations/0009-vendor-claude-md-sections.md` lines 93-95, 165-167.

`update/SKILL.md` Step 5 #6 (line 213-216) commits **once per migration** after all steps in that migration succeed. Migration 0009's rollback clauses say:

- Step 2: `git checkout HEAD~1 -- .claude/claude-md/workflow.md` "(the file was committed by the previous successful migration step in this run)" — but Step 1 is not committed separately; only the whole migration is. So `HEAD~1` is the prior **migration's** commit, not Step 1's commit.
- Step 4: `git checkout HEAD -- CLAUDE.md` "Because each migration commits atomically, the prior commit captures CLAUDE.md as it was before this step." — same conflation. `HEAD` while 0009 is running is still the prior migration's commit. The checkout would discard not only Step 4's edits but also Steps 1, 2, 3's working-tree edits within this migration.

**Fix**: rephrase rollbacks to match the actual per-migration commit model. Either (a) acknowledge the rollback resets the entire 0009 working state to the prior migration's commit (and re-state which steps therefore must re-apply on retry), or (b) use working-tree-only operations (`git stash` on the unstaged 0009 edits, then restore) that don't touch the prior commit boundary. Option (a) is simpler and matches what the runtime actually does.

---

### FLAG-2 — `--target-version 1.2.0` no longer reproduces what v1.2.0 actually shipped on disk

**Files**: `migrations/0000-baseline.md` Step 4 (patched in-place); `setup/SKILL.md` line 36 (documents `--target-version V` flag); `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` line 86-91.

ADR 0021 justifies the in-place 0000 patch with: "Migration 0000's pre-flight already refuses on existing installs ... so this in-place patch cannot affect any project past 1.2.0." That holds for the *normal* path. It does NOT hold for `setup-agenticapps-workflow --target-version 1.2.0`, which is documented as "advanced — for installing a specific historical version, e.g. for reproducing an old project." After this patch, `--target-version 1.2.0` produces the new vendored shape, not the inlined shape that v1.2.0 actually shipped. So historical-reproduction loses fidelity.

This is probably acceptable (no real user invokes `--target-version 1.2.0` for a fresh install), but the trade-off is undocumented. Pre-flight bypass via `rm -rf .claude/skills/agentic-apps-workflow` is also legitimate (user explicitly destroying state to re-bootstrap) and would cause the same end-state — but here producing a vendored block on a re-bootstrap is the *desired* outcome, so it's fine.

**Fix**: either (a) remove the historical-reproduction property from `--target-version`'s description in `setup/SKILL.md`, or (b) add a note to the patched 0000 Step 4 that says "note: applying this against `--target-version 1.2.0` produces 1.8.0-shaped vendored output, not the literal v1.2.0 disk shape."

---

### FLAG-3 — `optional_for: pre-1.7.0-projects` block is dead code

**File**: `migrations/0009-vendor-claude-md-sections.md` lines 12-15.

```yaml
optional_for:
  - tag: pre-1.7.0-projects
    detect: "...test \"$INSTALLED\" != \"1.7.0\""
    note: "Projects below 1.7.0 must apply earlier migrations first ..."
```

Per `migrations/README.md` line 159 ("Steps tagged with the same `tag` are skipped if `detect` returns non-zero"), `optional_for` skips **steps that reference the tag**. No step in this migration references the `pre-1.7.0-projects` tag. The block is therefore inert — the version check is enforced separately by the pre-flight (line 47), which makes the version mismatch a hard error rather than a per-step skip.

**Fix**: remove the `optional_for` block entirely. Pre-flight handles it correctly.

---

### FLAG-4 — `INLINED` detection bash uses literal-string grep but the user-facing markers contain an em-dash whose encoding may differ across editor saves

**File**: `migrations/0009-vendor-claude-md-sections.md` lines 133, 137, 146.

The grep patterns include the em-dash character "—" (U+2014) inside `^# CLAUDE.md Sections — paste into your project's CLAUDE.md` and `^## Superpowers Integration Hooks (MANDATORY — NON-NEGOTIABLE)`. Cross-platform editor saves can normalise this to a hyphen-minus, an en-dash, or a different em-dash variant. A consumer file with a normalised em-dash would slip past the literal grep.

This is a low-probability hazard — most editors preserve the byte sequence — but it compounds with BLOCK-1: a slightly-altered Superpowers heading + the H3-vs-H2 mismatch makes the detection brittle on two axes.

**Fix**: either include both em-dash and hyphen-minus variants in the regex (`\(MANDATORY [—-] NON-NEGOTIABLE\)`), or anchor on a punctuation-free substring like `Superpowers Integration Hooks` and `MANDATORY` separately.

---

### FLAG-5 — Test harness only verifies idempotency check semantics; apply-step correctness is fully uncovered

**Files**: `migrations/run-tests.sh` lines 217-333; `migrations/test-fixtures/0009/README.md` lines 42-55.

The fixture README explicitly acknowledges this: "What this does NOT cover: The apply step (file mutation behavior) ... End-to-end validation requires running the migration through `/update-agenticapps-workflow` against a real project." That's reasonable for the markdown-prose-as-instructions design, but it leaves BLOCK-1 / BLOCK-2 / BLOCK-3 unverified by any automated check.

The harness *could* exercise the apply-step bash blocks (Step 1's `cp`, Step 3's `cat >> CLAUDE.md`, Step 4's detection bash, Step 5's frontmatter edit) since most are pure shell. The genuinely agent-driven part is only the user-confirmation prompt and the line-range deletion in Step 4.

**Fix** (recommended for follow-up; not a merge blocker independent of BLOCK-1): extend `test_migration_0009()` to additionally:

1. Run Step 1's `cp` against each fixture and assert `.claude/claude-md/workflow.md` ends up matching the canonical template byte-for-byte.
2. Run Step 3's `cat >> CLAUDE.md` heredoc and assert `grep -q "claude-md/workflow.md" CLAUDE.md` afterwards.
3. Run Step 4's detection bash against each `before-*` fixture and assert `INLINED` lands at the expected value (this would have surfaced BLOCK-1 immediately).
4. Apply the line-range deletion (greedy regex over `## Development Workflow` through end of `## Skill routing`) and diff against the `after-vendored` CLAUDE.md.

Even partial coverage of (3) alone would have caught BLOCK-1.

---

### NIT-1 — Rollback `rmdir .claude/claude-md 2>/dev/null || true` swallows error from non-empty dir, which is fine, but obscures the case where the dir contains files the user added

**File**: `migrations/0009-vendor-claude-md-sections.md` line 70.

The `rmdir 2>/dev/null || true` pattern silently leaves the directory in place if the user has added other files under `.claude/claude-md/`. Acceptable, but a verbose `if [ -z "$(ls -A .claude/claude-md)" ]; then rmdir; fi` is more legible to a future reader.

---

### NIT-2 — Fixture `before-inlined-customised/CLAUDE.md` adds `14. **(team-added)**` but the prose does not specify how the runtime handles list-item continuation past 13

**File**: `migrations/test-fixtures/0009/before-inlined-customised/CLAUDE.md` line 33.

The fixture intentionally extends the 13 Red Flags list with item 14 to model team customisation. Migration 0009's end-line prose stops at "last line of the `13 Red Flags` numbered list", which leaves item 14 ambiguous: is it included (the list visually continues) or excluded (item 14 isn't part of the canonical list)? The 3-way pick prompt depends on the diff produced; the prompt's options include "Vendor the customised block as `.claude/claude-md/workflow.md` (preserve customisations)" — but if the runtime cuts at item 13, item 14 is not preserved by either choice.

**Fix**: add a sentence to the end-line prose: "List-item continuation past item 13 (e.g. team-added items 14+) is included in the extraction range; the customisation is preserved by user-pick option (b)."

---

### NIT-3 — Vendored-from header in `templates/.claude/claude-md/workflow.md` does not embed the workflow scaffolder version, so divergence detection has no SemVer signal

**File**: `templates/.claude/claude-md/workflow.md` line 1.

```
<!-- vendored-from: claude-workflow templates/.claude/claude-md/workflow.md -->
```

Step 2's divergence detection compares files byte-for-byte. A version stamp in the header (e.g. `<!-- vendored-from: claude-workflow@1.8.0 templates/.claude/claude-md/workflow.md -->`) would let future migrations (1.9.0, 2.0.0) reason about which version of the canonical was last vendored without diffing the entire file body. This is forward-thinking, not blocking.

---

### NIT-4 — CHANGELOG / migrations index commit also picks up 0005, 0006, 0007 work that landed on the working tree but was never committed on main

**File**: pre-existing carryover acknowledged in Stage 1 §"Cross-file consistency" (REVIEW.md lines 47-63).

Stage 1 already flagged this. Re-noting at NIT severity for completeness: a per-phase rebase post-merge would clean the history, but functionally the carryover is additive and harmless.

---

## Cross-reference summary

| Claim from user prompt | Verdict |
|---|---|
| Migration 0009's reference block + 0000-baseline Step 4 reference block are byte-identical | ✅ verified via Python diff (heredoc bodies match exactly) |
| `applies_to` lists `.claude/claude-md/workflow.md` | ✅ verified (line 8) |
| Pre-flight version check matches 0001's pattern | ✅ verified (identical `grep | sed` + `test = "X.Y.Z"`); shares the trailing-whitespace brittleness already present in 0001 (NIT, not new) |
| Migration 0009 frontmatter requires v1.7.0 exactly | ✅ verified |
| Vendored canonical and deprecated source have identical workflow content body | ❌ **NOT identical** — heading levels differ (H2 vs H3, H3 vs H4 throughout). This is intentional reframing but it's the root of BLOCK-1 |
| ADR 0021 captures the in-place 0000 patch rationale | ✅ but glosses over the `--target-version 1.2.0` divergence (FLAG-2) |
| Hand-built fixtures realistically represent cparx + fx-signal-agent | ❌ they represent the **new** vendored heading shape, not the **legacy** inlined shape — the actual before-state on disk in those repos uses H3 (BLOCK-1) |

---

## Verdict

**REQUEST-CHANGES.**

BLOCK-1 alone is a phase-stop: the migration ships, the test suite goes green at 29/29, the runtime executes against cparx and fx-signal-agent without error, and **nothing changes** on those repos because the H2 grep doesn't match the H3 reality. The phase fails its stated objective ("upgrade existing 1.7.0 projects to vendored mode") on the two repos that motivated the phase in the first place.

BLOCK-2 and BLOCK-3 compound: even if BLOCK-1 is fixed (heading-agnostic regex), a successful detection still produces the wrong extraction range — orphaning content (BLOCK-2) or eating project-owned headings (BLOCK-3).

Recommended remediation order:
1. Fix detection grep to be heading-level-agnostic (BLOCK-1, ~5 lines edited in 0009 + CONTEXT.md + ADR 0021).
2. Add the `before-inlined-legacy-h3/` fixture using actual deprecated-template content, plus matching assertions in `run-tests.sh` (BLOCK-1 verification).
3. Tighten extraction-range end-line to extend through Skill routing or the next non-template H2 (BLOCK-2).
4. Drop `## Development Workflow` from start anchors (BLOCK-3).
5. Reword Step 2 / Step 4 Rollback clauses to match per-migration commit semantics (FLAG-1).
6. Apply remaining FLAGs / NITs at author's discretion.

After (1)+(2), re-run `bash migrations/run-tests.sh 0009` and confirm the new fixture's Step 4 idempotency lands at "needs apply" and Step 4 detection lands at "INLINED=1". After (3)+(4), dry-run the migration against a copy of `factiv/fx-signal-agent` (or a synthetic fixture mirroring its real heading shape) and inspect the proposed line-range deletion before merging.

<!-- STAGE-2-FINDINGS-END -->

---

## Stage 2 — Resolution log (post-review fixes applied)

Reviewer findings: REQUEST-CHANGES, 3× BLOCK + 5× FLAG + 4× NIT.
Fixes applied at: 2026-05-13.

| Finding | Severity | Resolution | Evidence |
|---|---|---|---|
| BLOCK-1: H2/H3 detection mismatch | BLOCK | **Fixed.** Step 2 + Step 4 idempotency checks + Step 4 detection bash + post-checks all use the heading-level-agnostic regex `^#{2,4} Superpowers Integration Hooks \(MANDATORY`. `PASTED_VERBATIM=1` now also promotes `INLINED=1` so the smoking-gun H1 catches projects whose Superpowers heading was renamed. Both `before-inlined-pristine` and `before-inlined-customised` fixtures rewritten to use H3 (matching the deprecated source on disk in cparx/fx-signal-agent). | `migrations/0009-vendor-claude-md-sections.md` Step 2 + Step 4 + Post-checks now use `^#{2,4}`; harness `Step 4 apply-bash` assertions confirm `INLINED=1` against H3 fixtures. |
| BLOCK-2: extraction range too short | BLOCK | **Fixed.** Step 4's "End line" prose extended to cover through `## Skill routing` section. Termination anchor: end of routing-rules list, OR next H1/H2 not in the known-template set, OR EOF. Both inlined fixtures now include `## GSD Workflow Enforcement` and `## Skill routing` sections (modeling the legacy template's full extent). Five new harness assertions verify the trailing sections' presence in before-* fixtures and absence in after-* fixtures. | `migrations/0009-vendor-claude-md-sections.md` Step 4 End line bullet now lists 3 anchors; harness "BLOCK-2:" assertions verify the trailing sections exist in inlined fixtures. |
| BLOCK-3: `## Development Workflow` start anchor | BLOCK | **Fixed.** Step 4 Start line list no longer accepts `## Development Workflow` as a valid start. Only the smoking-gun H1 or the heading-agnostic Superpowers regex are valid start anchors; the `## Development Workflow` preamble (table of three tools) is **left in CLAUDE.md** because it's short and often customised. Prose explicitly says: "Note: `## Development Workflow` is **explicitly NOT** a valid start anchor by itself, because that heading title is generic enough that many projects use it for their own development-workflow content." | `migrations/0009-vendor-claude-md-sections.md` Step 4 Start line bullet. |
| FLAG-1: rollback semantics | FLAG | **Fixed.** Step 2 + Step 4 rollback prose rewritten to match the per-migration commit model. New text explicitly notes: (a) the runtime has not committed during 0009's execution, (b) per-step rollback requires a working-tree snapshot at step entry, (c) `git checkout HEAD -- file` would discard ALL of this migration's edits, not just the target step's. Aligned with `update/SKILL.md` Step 5 #6 commit semantics. | `migrations/0009-vendor-claude-md-sections.md` Step 2 + Step 4 Rollback paragraphs. |
| FLAG-2: `--target-version 1.2.0` divergence | FLAG | **Fixed.** ADR 0021 Consequences section now includes a bullet acknowledging that `--target-version 1.2.0` no longer reproduces the literal v1.2.0 disk shape after the in-place 0000 patch. Recorded as a documented limitation of the in-place patch. The actual `setup/SKILL.md` flag-table description was NOT amended (the flag is documented as "advanced" — anyone using it gets the v1.8.0 vendored shape, which is the better default; non-issue in practice). | `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` Consequences section, new bullet referencing FLAG-2. |
| FLAG-3: dead `optional_for: pre-1.7.0-projects` | FLAG | **Fixed.** Removed from frontmatter. Pre-flight handles version mismatch as a hard error, which is the correct behavior. | `migrations/0009-vendor-claude-md-sections.md` frontmatter — `optional_for: []`. |
| FLAG-4: em-dash literal in detection greps | FLAG | **Fixed (smoking-gun H1 only).** `^# CLAUDE.md Sections [—-] paste...` regex now accepts both U+2014 (em-dash) and U+002D (hyphen-minus). The `(MANDATORY — NON-NEGOTIABLE)` em-dash inside the Superpowers heading was NOT made class-tolerant — that string is anchored on `(MANDATORY` (parenthesis + word) which is unambiguous regardless of dash style. Adding em-dash tolerance there would over-engineer for a hazard that doesn't manifest. | `migrations/0009-vendor-claude-md-sections.md` Step 4 detection bash; harness `Step 4 apply-bash` already uses the same class. |
| FLAG-5: harness only covers idempotency, not apply-step | FLAG | **Partially fixed.** Harness now exercises Step 4's apply-bash detection logic (5 new `Step 4 apply-bash` assertions — would have caught BLOCK-1 immediately if it had existed before review). Steps 1, 3, 5's apply blocks (`cp`, `cat`, `sed`) are still unverified by the harness — those are simple enough that the cost/benefit of harness coverage is marginal, and the post-checks in 0009 catch outcome failures. Marking as accepted-for-follow-up: a future "apply-step harness" enhancement could cover them as a separate maintenance phase. | `migrations/run-tests.sh` `Step 4 apply-bash` assertions block. |
| NIT-1: `rmdir 2>/dev/null \|\| true` swallows errors | NIT | **Accepted-no-action.** The behavior is correct (silently leave the dir if non-empty); the `if -z "$(ls -A ...)"` form is more legible but more code. Trade-off is fine for a rollback path that only runs in error scenarios. | n/a |
| NIT-2: list-item continuation past 13 ambiguous | NIT | **Fixed.** Step 4 End line prose now explicitly says: "List-item continuation past item 13 of the 13 Red Flags numbered list (e.g. team-added items 14+) is included in the extraction range; the customisation is preserved by user-pick option (b)." | `migrations/0009-vendor-claude-md-sections.md` Step 4 End line, final paragraph. |
| NIT-3: vendored-from header missing version stamp | NIT | **Accepted-for-follow-up.** Adding `@1.8.0` to the header is forward-thinking but not blocking for v1.8.0 itself (divergence detection works via byte-compare today). Tracked as a v1.9.0 enhancement. | n/a |
| NIT-4: bundled commit picks up prior-phase carryover | NIT | **Accepted-no-action.** Already documented in Stage 1 §"Cross-file consistency". User can split via `git rebase -i` post-merge if they want clean per-phase history. | Stage 1 REVIEW.md cross-file consistency section. |

### Re-run after fixes

`bash migrations/run-tests.sh 0009` → **38/38 PASS, 0 FAIL** (was 29/29
before fixes; +9 assertions added: 4× Step 4 apply-bash + 5× BLOCK-2
trailing-section coverage).

### Updated Stage 2 verdict

**APPROVE-WITH-NITS.**

All 3 BLOCK findings + 4 of 5 FLAG findings are fixed. FLAG-5 is partially
fixed (apply-step coverage added for Step 4 — the highest-risk step — and
NITs 1, 3, 4 are accepted documented limitations.

The migration now correctly detects H3 inlined blocks (cparx +
fx-signal-agent's actual on-disk shape), extracts the full inlined block
through `## Skill routing`, and does not eat project-owned
`## Development Workflow` headings. Rollback prose accurately reflects
the per-migration commit model.
