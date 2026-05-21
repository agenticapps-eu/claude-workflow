# Phase 20 — Execution Plan

This plan executes the six phases described in CONTEXT.md, with the
Phase 5 reshape from divergence D2. Every phase has a verification
gate before the next can start.

> **Discipline reminder.** §11 canonical block is verbatim. §12
> Mermaid trigger is ≥2 branches AND ≥1 cycle/fallback. §13's
> Phase-1 declaration → Phase-2 failing test → Phase-3 implementation
> ordering MUST NOT collapse into one commit for any ts-declare-first
> exemplar shipped in the skill scaffold.

## Conventions

- One PR per phase is *not* the discipline here — the whole thing is
  a single 1.14.0 PR. Phases are commit-grouping units.
- Atomic commits per discrete change. Migrations land as
  `feat(migrations): NNNN — <slug>` per existing precedent (see
  PR #35).
- Migration test cases land in the same commit as the migration they
  test (existing precedent in PRs #28–#30).
- Verification gate evidence is captured *in the commit message* for
  each terminal commit of a phase, mirroring the recent
  CHANGELOG hygiene precedent.

---

## P1 — Migration 0014: inject §11 canonical block

### P1.1 — Vendor §11 block

**Task**: copy the canonical block from `agenticapps-workflow-core/
spec/11-coding-discipline.md` (lines 26–102, the contents of the
quad-backtick fence) into a vendored mirror inside the scaffolder
bundle.

- **Vendor path** (chosen): `migrations/spec-mirrors/11-coding-discipline-0.4.0.md`.
  Versioned filename so future spec revisions can land alongside
  rather than overwrite, with the migration choosing which version
  to inject.
- **Verification gate**: `diff` between source and vendored copy
  produces empty output. Capture diff command in commit message.
- **TDD**: not applicable — this is a one-shot copy with structural
  verification, not behavior. Verification-before-completion gate
  is the diff.

### P1.2 — Author migration 0014

**File**: `migrations/0014-inject-spec-11-coding-discipline.md`

Follow the format of 0013 (frontmatter + Pre-flight + Steps +
Rollback). Key sections:

- **Frontmatter**: `id: 0014`, `slug: inject-spec-11-coding-discipline`,
  `title: "Inject spec §11 Coding Discipline canonical block (closes spec 0.4.0 §11 conformance)"`,
  `from_version: 1.12.0`, `to_version: 1.14.0`,
  `applies_to: [CLAUDE.md, ...templates...]`.
- **Pre-flight**: workflow scaffolder version is 1.12.0 (or 1.14.0 for
  re-apply); vendored §11 block exists at the chosen path; CLAUDE.md
  exists in target project (if not, no-op for the project but record
  in scan-report — this matches the permissive idiom 0013 uses for
  the observability-block path).
- **Step 1**: Inject §11 block into project's CLAUDE.md at anchor
  `## Coding Discipline (spec §11)` per RESEARCH.md B2/B3.
- **Step 2**: Bump host scaffolder version (1.12.0 → 1.14.0) and
  spec-version stamp in `skill/SKILL.md`. Note this is the only
  migration that bumps to 1.14.0 — subsequent migrations in this PR
  (just 0015) ride along; the bump is tied to spec-absorption, not
  per-migration.
- **Rollback**: remove the section bracketed by the heading anchor
  and the next heading.

### P1.3 — Update claude-workflow's own root CLAUDE.md (or surface its absence)

**Task**: Phase-0 surfaced uncertainty about whether the host repo
has a root CLAUDE.md. P1 begins with a grep.

```bash
ls /Users/donald/Sourcecode/agenticapps/claude-workflow/CLAUDE.md 2>&1
```

- If present: apply the same injection inline (so host dogfoods its
  own migration). Commit separately.
- If absent: do not create one solely for §11. Surface via a
  follow-up note in CHANGELOG.md.

### P1.4 — Update project-template CLAUDE.md

**Task**: Locate the file the init scaffolder uses for fresh-project
CLAUDE.md (grep for `# CLAUDE.md` or for a known boilerplate string
in `templates/`). Inject the §11 anchor with provenance comment.

If no project-template exists, the scaffolder generates CLAUDE.md
dynamically — locate the generator (likely under `setup/` or
`install.sh` or `migrations/0013-...` Step 2's auto-init logic) and
amend the generated content there.

### P1.5 — Migration 0014 test fixtures

Following 0013's pattern (setup.sh / verify.sh / expected-exit per
case under `migrations/test-fixtures/0014/`):

| Case | Setup | Verify | Expected exit |
|------|-------|--------|---------------|
| `01-anchor-missing` | Project with CLAUDE.md, no §11 anchor | Anchor present, block matches vendored bytes | 0 |
| `02-anchor-present-matching` | Project with §11 anchor at current spec version | File unchanged byte-for-byte (no-op) | 0 |
| `03-anchor-present-stale` | Project with §11 anchor at simulated older spec version (e.g., `0.3.x`) | Anchor present, block replaced, provenance comment updated | 0 |
| `04-anchor-present-unmanaged` | Project with `## Coding Discipline (spec §11)` heading but no provenance comment | Migration refuses, exit 3, conflict message in stderr | 3 |
| `05-no-claudemd` | Project with no CLAUDE.md | Migration no-ops with informational message | 0 |
| `06-idempotent-reapply` | Apply migration once, then again | Second apply produces zero changes (file mtime unchanged is acceptable evidence) | 0 |

**TDD discipline**: 0014's setup.sh + verify.sh + expected-exit
written FIRST (run-tests.sh harness reports FAIL because migration
file doesn't exist yet — that's the RED). Then 0014's migration
file authored — re-run harness, PASS=GREEN.

Commit shape:
- `test(migration-0014): fixtures for 6 cases (RED)`
- `feat(migration-0014): inject spec §11 canonical block (GREEN)`

### P1 verification gate

- `bash migrations/run-tests.sh --strict-preflight` exits 0 with PASS
  count = prior + 6.
- `diff <(extract canonical block from spec/11) <(extract block from
  claude-workflow's CLAUDE.md after migration applied)` produces
  empty output. (If claude-workflow has no root CLAUDE.md, replace
  with a fixture project run.)
- `grep -RIn 'spec-source: agenticapps-workflow-core@0.4.0 §11'`
  shows the provenance comment in expected locations.

---

## P2 — Migration 0015: scaffold ts-declare-first skill

### P2.1 — Author the skill files

**Path** (chosen): `ts-declare-first/` at the host repo root,
following `add-observability/`'s precedent. NOT under `skills/`
(no such directory exists in claude-workflow).

Files:

| Path | Purpose |
|------|---------|
| `ts-declare-first/SKILL.md` | Frontmatter: `implements_spec: 0.4.0`, `name`, `version: 0.1.0`, `description` that mentions §13. Body: phase 1/2/3 prompts referenced from §13 verbatim where possible. |
| `ts-declare-first/README.md` | One-page operator guide. |
| `ts-declare-first/prompt.md` | Operator handoff prompt template for invoking the skill on a TS module. |
| `ts-declare-first/templates/example.declare.ts` | Non-normative bounded-queue declaration (from §13's illustrative example, marked non-normative). |
| `ts-declare-first/templates/example.test.ts` | Matching failing-test stub (§13 phase 2). |
| `ts-declare-first/templates/example.impl.ts` | Matching implementation (§13 phase 3) — separate file so the three-commit shape is structurally enforced when an operator copies the templates. |

**TDD**: not applicable in the unit-test sense. Structural
verification: file presence + frontmatter content.

### P2.2 — Author migration 0015

**File**: `migrations/0015-add-ts-declare-first-skill.md`

- **Frontmatter**: `id: 0015`, `slug: add-ts-declare-first-skill`,
  `title: "Scaffold ts-declare-first skill for TS projects (closes spec 0.4.0 §13 conformance)"`,
  `from_version: 1.14.0`, `to_version: 1.14.0` (rides on 0014's bump),
  `applies_to: [".claude/skills/ts-declare-first → symlink"]`.
- **Pre-flight**: workflow scaffolder version is 1.14.0; global
  scaffolder bundle exists.
- **Step 1**: Detect TS-primary project per §13 heuristic
  (`package.json` exists AND any of: `"types"` field, `"main"`
  resolves to `.ts`, `typescript` in deps/devDeps). If not
  TS-primary, no-op with informational message — opt-in per
  §13's MAY.
- **Step 2**: Install `ts-declare-first` symlink into
  `.claude/skills/ts-declare-first → $HOME/.claude/skills/agenticapps-workflow/ts-declare-first`
  (same idiom as migration 0012's slash-discovery for
  `add-observability`).
- **Rollback**: remove the symlink.

### P2.3 — Wire into install.sh / init flow

**Task**: Locate the scaffolder entrypoint that runs migrations on
new project init (likely `install.sh` or the `setup/` directory).
Ensure 0015 runs as part of the standard chain. Most likely no
changes needed — 0015 just lands in the migrations directory and
the existing chain picks it up. Confirm by re-running install on a
fixture TS project (covered by P2.4 case 01).

### P2.4 — Migration 0015 test fixtures

| Case | Setup | Verify | Expected exit |
|------|-------|--------|---------------|
| `01-ts-primary-installs-skill` | package.json with `"main": "index.ts"` + `typescript` devDep | `.claude/skills/ts-declare-first/` symlink resolves to global | 0 |
| `02-py-only-no-skill` | Python project, no package.json | `.claude/skills/ts-declare-first/` does NOT exist | 0 |
| `03-polyglot-mixed` | package.json present but `typescript` not in deps and `"main"` is `.js` | Skill NOT installed; informational message about declining | 0 |
| `04-idempotent-reapply` | Apply once, then again | Second apply zero changes | 0 |

### P2 verification gate

- `bash migrations/run-tests.sh --strict-preflight` exits 0 with PASS
  count = prior + 4.
- `cat ts-declare-first/SKILL.md` shows `implements_spec: 0.4.0`
  in frontmatter and cites §13 in opening paragraph.
- The three template files are present and the implementation file
  is structurally distinct from the declaration file (no overlap
  in function bodies).

---

## P3 — Mermaid-convention audit pass

### P3.1 — Enumerate branchy paragraphs

For each of `skill/SKILL.md`, `add-observability/SKILL.md`, and
every `templates/**/SKILL.md` (first task: `find templates -name
'SKILL.md'` to enumerate), produce a per-file checklist of branchy
paragraphs. A paragraph is *branchy* if it contains language like:
"if X then Y, else Z", "in this case ... otherwise", "loop until",
numbered conditional steps, or a verification gate with multiple
exit paths.

Output: `P3-AUDIT-LOG.md` in this phase directory listing each
candidate with its file:line range and a CONVERT/KEEP decision.

### P3.2 — Apply §12 trigger to each

For each candidate:

- **CONVERT** if ≥2 branches AND ≥1 cycle/fallback: replace the
  prose passage with a Mermaid `flowchart TD` block plus 1–3
  sentences of judgment-prose immediately below.
- **KEEP** otherwise: leave prose unchanged but add a one-line
  HTML comment inline:
  `<!-- §12 audit 2026-05-XX: judgment-only, no flow -->`.

### P3.3 — Per-diagram rules

- Use `flowchart TD` (top-down).
- Every observable terminal state has a labeled node, including
  `REPORT` (escalate to user) where the agent cannot determine the
  next step.
- Failure paths render as `-->|failure| <node>`.
- The diagram MUST NOT elide a branch the prose mentions (§12).
- Retained prose carries the criteria the diagram can't encode.

### P3.4 — Bound

The audit is bounded to the three file groups above. Deeper
branchy paragraphs in helper docs are noted in
`P3-AUDIT-LOG.md`'s "Follow-up" section but not converted here.

### P3 verification gate

- `P3-AUDIT-LOG.md` exists in this phase directory.
- Every CONVERT decision shows a corresponding `flowchart TD`
  block in the target file.
- Every KEEP decision shows the HTML-comment annotation.
- `grep -c '<!-- §12 audit'` count matches the KEEP count from
  the audit log.
- `grep -c '```mermaid' { skill/SKILL.md add-observability/SKILL.md
  templates/**/SKILL.md }` count matches the CONVERT count.

---

## P4 — Scanner evaluation + ratify ADR 0015

### P4.1 — Install scanners

Install both via documented release binary. Capture exact versions
to `/Users/donald/Documents/Claude/Projects/agentic-workflow/
scanner-eval-2026-05-20/` per RESEARCH.md A5.

### P4.2 — Select fixture

Per RESEARCH.md A2:
1. Run gitleaks against cparx HEAD in dry-run.
2. Compare detected count against documented seeded-secret count.
3. If ≥3 known TPs still present, use cparx; else clone deepsec
   read-only into scratch.

### P4.3 — Run all 7 criteria

Execute per RESEARCH.md A3. Wall-clock criterion: median of 3
runs. Capture all artifacts to the documented path. No
post-hoc threshold adjustment.

### P4.4 — Apply decision rule

Per RESEARCH.md A4:
- SWAP / STAY / REVISIT outcome from the locked rule.
- DECISION.md in the artifact directory records which rule fired.

### P4.5 — Write local ADR

`docs/decisions/00NN-secret-scanner-choice.md` (next free local
ADR number — Phase 0 grep shows highest is 0014). Mirror the
outcome with full evaluation artifacts referenced. Status:
Accepted. Decision: <outcome>.

### P4.6 — Cross-repo PR against workflow-core

Open PR against `agenticapps-workflow-core` updating
`adrs/0015-secret-scanner.md`:

- Status: Proposed → Accepted
- Decision block populated per the locked rule's outcome
- Consequences block populated
- References block links the local ADR
- Linear: — (no Linear issue for this work)

This PR MUST merge before the 1.14.0 PR opens for code review.
P6 confirms the cross-link resolves.

### P4 verification gate

- All 7 criterion files exist in the artifact path with raw output.
- `DECISION.md` records the outcome with which-rule-fired.
- `docs/decisions/00NN-secret-scanner-choice.md` exists in this
  repo.
- Cross-repo PR URL captured in this phase's commit message.

---

## P5 — CI template handling (RESHAPED — premise divergence D2)

### Branch on P4 outcome

**P4 = STAY**: skip P5 entirely. ADR records "remain on gitleaks
recommendation; claude-workflow does not ship CI templates that
invoke it; downstream projects choose locally." Phase 0's grep
count (zero) is unchanged in P6's verification.

**P4 = REVISIT**: skip P5 entirely (same as STAY). Carry a
90-day calendar reminder in this phase's notes.

**P4 = SWAP** (adopt betterleaks):

P5.SWAP.1 — Add an opt-in CI fragment file at
`add-observability/enforcement/secret-scan.yml.example`
demonstrating betterleaks invocation. Mirror the shape of the
existing `observability.yml.example` (pinned action SHAs,
read-only top-level permissions, `pull_request` trigger,
sticky-comment failure path).

P5.SWAP.2 — Update `add-observability/enforcement/README.md`
(if present — grep first) to document the new opt-in CI fragment
alongside the observability one. If no README, add a short header
note inside the YAML.

P5.SWAP.3 — Do NOT add a migration 0016. There is nothing in
downstream projects to swap. Downstream projects pick up the
opt-in fragment by copying from the example, same as
observability.yml.example.

### P5 verification gate (both branches)

- If STAY/REVISIT: `grep -RIn 'gitleaks\|betterleaks' .` count
  matches Phase 0's count (zero) post-P5.
- If SWAP: the new `secret-scan.yml.example` exists; the README
  references it; no migration 0016 file exists; the project
  CHANGELOG.md entry calls out "opt-in, not auto-applied".

---

## P6 — Version bump + CHANGELOG + dogfood

### P6.1 — Version bump

Migration 0014 already bumps `skill/SKILL.md` version 1.12.0 →
1.14.0 and `implements_spec` 0.3.2 → 0.4.0 in Step 2. P6.1
verifies the bump is reflected on disk:

```bash
grep '^version:' skill/SKILL.md           # expect: version: 1.14.0
grep '^implements_spec:' skill/SKILL.md   # expect: implements_spec: 0.4.0
```

### P6.2 — CHANGELOG entry

Append to `CHANGELOG.md`. Body content per the hand-off prompt's
draft. Cite migrations 0014 + 0015, the §12 audit, and ADR 0015's
ratification. Conditional bullet for the swap or stay outcome.

### P6.3 — Dogfood — first run

```bash
cd /tmp/dogfood-fixture     # fresh clone of claude-workflow at HEAD
bash <(globally-installed update flow)
```

Expected: migrations 0014 and 0015 apply. Confirm structural
evidence per each phase's gate.

### P6.4 — Dogfood — idempotency re-run

Re-run the same update. Expected output: "0 changes". Capture
stdout and append to this phase's commit message.

### P6.5 — Tracking issues

Open issues in pi-agentic-apps-workflow and codex-workflow GitHub
trackers titled "Absorb agenticapps-workflow-core 0.4.0" with a
checklist linking to the four spec sections and ADR 0015.

### P6 verification gate

- Idempotency: second update run reports zero changes.
- `grep '^version:'` and `^implements_spec:` show expected values.
- CHANGELOG.md has 1.14.0 entry.
- Cross-repo ADR 0015 PR is merged (confirm via `gh pr view`).
- Tracking issue URLs recorded in this phase's commit message.

---

## Cross-phase verification (run before opening PR for review)

```bash
# Migration test suite green
bash migrations/run-tests.sh --strict-preflight
# Expect: PASS=N+10 (6 cases for 0014, 4 cases for 0015), FAIL=0

# §11 byte-identity
diff <(awk '/^```/,/^```/' agenticapps-workflow-core/spec/11-coding-discipline.md \
        | grep -v '^```') \
     <(awk '/^## Coding Discipline \(spec §11\)/,/^## /' claude-workflow/CLAUDE.md \
        | grep -v '^## ' | grep -v '^<!--')
# Expect: empty output (or no host CLAUDE.md if that's the chosen state)

# gitleaks count (D2 divergence verification)
PRE_COUNT=0   # captured in Phase 0
POST_COUNT=$(grep -RIn 'gitleaks' . 2>/dev/null | wc -l)
# Expect: $POST_COUNT == 0 (STAY/REVISIT) OR documented count (SWAP)

# Spec version bump
grep '^version:' skill/SKILL.md           # 1.14.0
grep '^implements_spec:' skill/SKILL.md   # 0.4.0

# Cross-repo ADR PR merged
gh -R agenticapps-eu/agenticapps-workflow-core pr view <ADR-PR-NUM> \
   --json state -q .state
# Expect: MERGED
```

Capture all of the above in the final PR's description's
"Verification" section.
