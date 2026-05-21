# Phase 20 — Absorb workflow-core spec 0.4.0 into claude-workflow

**Branch**: `feat/v1.14.0-workflow-additions`
**Spec target**: `agenticapps-workflow-core@v0.4.0`
**Version bump**: `1.12.0 → 1.14.0`, `implements_spec: 0.3.2 → 0.4.0`
**Date opened**: 2026-05-20
**Hand-off source**: user-provided prompt (this session)

## Background

`agenticapps-workflow-core@v0.4.0` shipped three new spec sections and one
placeholder ADR:

- **§11 Coding Discipline** — canonical-prose section (the Karpathy
  four-rule block). Host implementations MUST inject the block verbatim
  into their primary project-instruction file.
- **§12 Authoring Conventions** — declarative-contract SHOULD requiring
  branchy workflows (≥2 branches AND ≥1 cycle/fallback) to be rendered
  as Mermaid in newly-authored SKILL.md / contract files. Existing
  files MAY be converted opportunistically.
- **§13 TS Declare-First Skill** — declarative-contract SHOULD that
  hosts targeting TypeScript SHOULD ship a `ts-declare-first`-shaped
  skill.
- **ADR 0015 Secret-scanner choice** — Proposed, Decision TBD. This
  PR is the designated ratifying body: it benchmarks `betterleaks`
  against `gitleaks` on a fixture and writes the Decision block back
  via a cross-repo PR.

This phase absorbs all four into claude-workflow.

## Goals (must-haves)

| # | Goal | Evidence shape |
|---|------|----------------|
| G1 | §11 canonical block injected verbatim into project CLAUDE.md via migration 0014 | `diff` byte-identical between core spec block and injected block; host's own CLAUDE.md carries the block; templates/project-template (path TBD in P0) carries the block |
| G2 | `ts-declare-first` skill scaffolded into the host repo via migration 0015 | Skill files exist at the host's chosen path; `implements_spec: 0.4.0` in frontmatter; cites §13; install.sh / scaffolder offers install when TS detected in package.json |
| G3 | Mermaid audit pass on host-owned SKILL.md files | Every branchy paragraph in `skill/SKILL.md`, `add-observability/SKILL.md`, and `templates/**/SKILL.md` is either converted (Mermaid + retained judgment-prose) or annotated with one-line HTML-comment justification |
| G4 | ADR 0015 ratified in workflow-core via cross-repo PR | PR URL recorded in this PR's description; ADR file shows Status: Accepted; Decision block populated; local ADR in `docs/decisions/` mirrors the outcome with full evaluation artifacts referenced |
| G5 | Version bump + CHANGELOG + spec-version metadata | `skill/SKILL.md` shows `version: 1.14.0`, `implements_spec: 0.4.0`; CHANGELOG.md has 1.14.0 entry; dogfood re-run produces "0 changes" on second pass |
| G6 | Migration test harness passes for 0014 and 0015 | `bash migrations/run-tests.sh --strict-preflight` count increases by N test cases; PASS=FAIL=0 maintained |

## Divergences from the hand-off prompt's stated premise

The hand-off prompt assumed `claude-workflow at v1.13.x` with `gitleaks
wired into CI templates under templates/ci/ and into add-observability
CI fragments`. Phase 0 verification falsified both:

### D1 — Current scaffolder is at v1.12.0, not v1.13.x

`skill/SKILL.md` shows `version: 1.12.0` (verified 2026-05-20 against
`main @ c9414b9`). `implements_spec: 0.3.2` matches the prompt's "(or
any prior 0.3.x)" qualifier. Most natural interpretation: v1.13.x simply
never shipped; the release line went `1.12.0 → 1.14.0` directly. The
prompt's STOP condition reads "If they're not 1.13.x and 0.3.2 (or any
prior 0.3.x)" — the parenthetical naturally qualifies `implements_spec`
(the value with `.x` form). Treating this as acceptable.

### D2 — No `gitleaks` invocations anywhere in claude-workflow

`grep -RIn 'gitleaks' .` returns empty. The session-handoff snapshot
documents the deliberate stance:

> `enforcement.ci:` field still omitted by default. v1.10.0 Option-4
> local-first stance held through v1.12.0. Opt-in CI workflow remains
> copy-paste from `add-observability/enforcement/observability.yml.example`.

The single existing CI artifact (`observability.yml.example`, lines 1–149)
invokes `claude /add-observability scan`, not any secret scanner.

**Consequence for Phase 5**: The "conditional CI template swap" premise
is materially false — there is no `gitleaks` invocation to swap. The
hand-off's own skip path (§Phase 5: "If Phase 4's decision is 'stay':
skip Phase 5 entirely") covers half of this; the other half is:
**if Phase 4 outcome is "adopt betterleaks", Phase 5 becomes
"introduce" rather than "swap"** — add an opt-in CI fragment alongside
`observability.yml.example` rather than rewriting existing templates.

This reshape is documented in PLAN.md Phase 5. No migration 0016 is
needed in either branch of the conditional (nothing to migrate
*from* in downstream projects). Migration 0016 is dropped from scope.

## Non-goals (preserved from hand-off)

- Not changing pi-agentic-apps-workflow or codex-workflow source.
  Tracking issues only.
- Not rewriting existing SKILL.md prose for style. Mermaid audit
  converts only paragraphs meeting the §12 trigger.
- Not adopting Karpathy's full plugin (slash-commands,
  commitment-ritual mods). Only the canonical four-rule block.
- Not benchmarking scanners on customer/private code. Internal
  fixtures only.
- Not auto-ratifying ADR 0015 without thresholds hitting documented
  criteria.
- Not adding a mandatory GSD gate for `ts-declare-first`. Opt-in per
  §13's SHOULD.

## Open questions surfaced from Phase 0 verification

The hand-off prompt has answers for these; Phase 0 surfaced them as
concrete decisions still needed before P1/P2 execute. None block the
planning gate, but each must be answered before its phase executes.

1. **Where does the host repo's project-template CLAUDE.md live?**
   The hand-off says "`templates/project-claude-md.md` (or wherever
   the init scaffolder pulls its project-template CLAUDE.md from —
   grep for the existing scaffolded text)". Phase 1 must grep for
   the actual file before authoring migration 0014.
2. **What's the host's chosen path for the `ts-declare-first` skill?**
   The hand-off says `skills/ts-declare-first/`, but claude-workflow's
   precedent is `add-observability/` at repo root (not under `skills/`).
   Phase 2 must pick a convention consistent with `add-observability/`:
   place at `ts-declare-first/` at repo root, install-symlinked into
   `~/.claude/skills/` via the same pattern as migration 0012.
3. **Scanner benchmark fixture choice** — the hand-off offers cparx
   pilot OR `vercel-labs/deepsec`. Phase 4 must verify cparx seeded
   secrets are still present in git history before committing.
   Fallback to deepsec if not.
4. **Cross-repo PR ordering**: hand-off says workflow-core ADR-0015 PR
   merges *before* this 1.14.0 PR opens for review. Phase 4 confirms
   this ordering; Phase 6 verifies the cross-link resolves.

## Phase 0 discovery addendum (resolves OQ1, partly OQ2)

Verified on disk before opening P1:

- **No host root `CLAUDE.md`** at `claude-workflow/CLAUDE.md`. The
  hand-off prompt's "update claude-workflow's own root CLAUDE.md" path
  is N/A — the scaffolder repo ships content for *consumer* projects
  and doesn't itself carry one. P1's "host dogfood" via the host's own
  CLAUDE.md is dropped; dogfood happens via P6's fixture-project
  update flow instead.

- **Project CLAUDE.md is assembled, not templated.** It is created
  by `migrations/0000-baseline.md` Step 4 (originally) and reshaped
  by `migrations/0009-vendor-claude-md-sections.md` (since v1.8.0).
  Current shape: a small CLAUDE.md that references a vendored
  `.claude/claude-md/workflow.md` (long-form workflow content the
  agent reads on demand). The vendor pattern exists specifically
  to keep CLAUDE.md small enough to be re-read at session start
  (fixing cparx's 646-line / fx-signal's 372-line bloat per
  ADR 0021).

- **§11's design intent is opposite to the workflow-vendor pattern.**
  §11 says "These four rules are reread every session because the
  failure modes they prevent recur every session." So the §11 block
  MUST be inlined in CLAUDE.md, not vendored to a sibling file. This
  is consistent with §12's placement advisory ("§11 canonical block
  lives near the top of CLAUDE.md ... not appended below long
  appendices"). Migration 0014 inlines, not vendors-and-references.

- **`templates/claude-md-sections.md` is DEPRECATED** (header
  declares so). Used only for 0009's legacy-detection grep. Migration
  0014 must NOT touch it.

- **OQ1 resolution**: there is no single "project-template
  CLAUDE.md" file. The shaping happens inside migration 0000-baseline
  (which builds the initial CLAUDE.md) and is then reshaped by
  later migrations. Migration 0014 follows the same idiom: it
  amends `CLAUDE.md` in-place via grep-detect + section-insert,
  not by editing a template file.

- **OQ2 partial resolution**: `add-observability/` is at repo root,
  not `skills/`. Migration 0015 follows that idiom — skill lands at
  `ts-declare-first/` at repo root, with `.claude/skills/` symlink
  the install pattern (mirrors migration 0012).

## Artifacts this phase produces

- `migrations/0014-inject-spec-11-coding-discipline.md` + test fixtures
- `migrations/0015-add-ts-declare-first-skill.md` + test fixtures
- `ts-declare-first/` skill directory (path per OQ2)
- Edits to `skill/SKILL.md`, `add-observability/SKILL.md`,
  `templates/**/SKILL.md` (Mermaid audit; surface enumerated in P3)
- `docs/decisions/NNNN-secret-scanner-choice.md` (local ADR)
- Cross-repo PR against `agenticapps-workflow-core` updating
  `adrs/0015-secret-scanner.md`
- Edits to `skill/SKILL.md` frontmatter (version + implements_spec)
- Edits to `CHANGELOG.md` (1.14.0 entry)
- This PR's description with: pre/post grep counts, idempotency
  re-run output, byte-identical-§11 diff (empty output), evaluation
  artifact paths, cross-repo PR URL
