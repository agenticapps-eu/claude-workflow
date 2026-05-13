# Phase 06 — VERIFICATION

Goal-backward verification: for each must-have from CONTEXT.md and the
user's prompt, what artifact proves the goal was achieved?

## Acceptance criteria (from user prompt)

### 1. `migrations/0009-vendor-claude-md-sections.md` exists, version frontmatter bumps the workflow version

- **Evidence**: `head -7 migrations/0009-vendor-claude-md-sections.md`
- **Result**: file exists; frontmatter has `id: 0009`, `slug: vendor-claude-md-sections`, `from_version: 1.7.0`, `to_version: 1.8.0`. Matches the migration framework's convention.

### 2. setup + update skills use vendor mode by default

- **Evidence (setup)**: `migrations/0000-baseline.md` Step 4 patched in-place — apply block now writes `.claude/claude-md/workflow.md` and appends a 7-line `## Workflow` reference to CLAUDE.md (no longer `cat`s the template). `setup/SKILL.md` post-setup summary lists the vendored file as a created artifact. Migration history table updated.
- **Evidence (update)**: `update/SKILL.md` Step 5 #5 has the new "divergence variant" prompt with 3-way pick (Replace / Keep / Vendor-local). Failure modes table extended with vendored-file divergence + inlined-block extraction-ambiguous outcomes.
- **Result**: ✅ verified by reading the patched files.

### 3. `migrations/run-tests.sh`: 20+/20+ PASS for migration 0009 fixtures

- **Evidence**: `bash migrations/run-tests.sh 0009`
- **Result**: **38 PASS / 0 FAIL** (29 idempotency + 4 paste-verbatim detection + 4 Step 4 apply-bash + 5 BLOCK-2 trailing-section coverage). Exceeds the 20+ target by nearly 2×.

### 4. ADR in `docs/decisions/` capturing the inline→vendor pivot and why the meta repo is never referenced at runtime

- **Evidence**: `docs/decisions/0021-vendor-workflow-block-instead-of-inline.md` exists. Status: Accepted, Date: 2026-05-13. Sections: Context, Decision (3 properties + detection-remediation paragraph + 0000-patch decision), 5× Alternatives Rejected (symlink, runtime fetch, `@import`, reduce-block-size, bundle-0010), Consequences (3 positive, 4 negative including FLAG-2 acknowledgment, 1 neutral). Implementation references list ties the ADR to all 8 modified files.
- **Result**: ✅ verified.

### 5. README / migrations index updated

- **Evidence (migrations index)**: `migrations/README.md` has new "Migration index (current chain)" subsection with the 8-row chain table (0000 → 0001 → 0004 → 0002 → 0005 → 0006 → 0007 → 0009) and v1.8.0 vendor-mode property note for 0000.
- **Evidence (README)**: top-level `README.md` not modified — no claims about CLAUDE.md inlining present that would need correcting.
- **Result**: ✅ verified.

### 6. Two-stage review + `/cso` pass before merge

- **Evidence (Stage 1)**: REVIEW.md §"Stage 1 — Spec compliance review" — verdict PASS, all 11 acceptance criteria checked, goal-backward verification + spec-drift check both clean. Cross-file consistency overlap with prior phases documented.
- **Evidence (Stage 2)**: REVIEW.md §"Stage 2 — Independent code-quality review" appended by `pr-review-toolkit:code-reviewer` agent. Initial verdict REQUEST-CHANGES (3× BLOCK + 5× FLAG + 4× NIT). Resolution log appended documenting fixes for all 3 BLOCKs + 4 of 5 FLAGs + 1 NIT; remaining items accepted with rationale. Updated verdict APPROVE-WITH-NITS.
- **Evidence (/cso)**: SECURITY.md — 4 findings (1 INFORMATIONAL, 2 LOW, 1 INFORMATIONAL). Verdict PASS. No new threat vectors; existing trust boundary actually narrowed (meta-repo no longer referenced at runtime).
- **Result**: ✅ verified.

## Decisions surfaced in CONTEXT.md (would normally come out of /gsd-discuss-phase)

### Decision 1 — Destination path

- **Choice**: `.claude/claude-md/workflow.md`
- **Evidence of consistent application**: used in 0000 Step 4 (apply + post-checks + applies_to), 0009 Step 1 + Step 3 + applies_to, ADR 0021 (5+ references), all 5 fixtures, vendored source path, harness assertions, CHANGELOG entry, REVIEW.md.
- **Result**: ✅ no path drift across artifacts.

### Decision 2 — Idempotency model matches migration 0001

- **Evidence**: 0009 has 5 steps, each with `**Idempotency check:**` + `**Pre-condition:**` + `**Apply:**` + `**Rollback:**`. Re-running 0009 against `after-vendored` fixture: all 5 idempotency checks return 0 (`Step N idempotency: skip on after-vendored` × 5). Same against `after-idempotent` fixture (5 more assertions). Total: 10 assertions confirming re-run is no-op.
- **Result**: ✅ matches 0001's pattern.

### Decision 3 — Inlined-block detection signature + remediation

- **Evidence**: Step 4 detection uses heading-agnostic regex `^#{2,4} Superpowers Integration Hooks \(MANDATORY` (catches H2, H3, H4 — covers both deprecated source's H3 and new canonical's H2). Smoking-gun H1 `^# CLAUDE.md Sections [—-] paste...` (em-dash class) is a separate signal that promotes detection to "inlined". Three-way pick on customised: replace / preserve-as-vendored / skip. User confirmation required before CLAUDE.md mutation (per `update/SKILL.md` Step 5 #5 divergence variant). Apply-bash assertions in harness verify INLINED lands at expected value across all 4 before-* / after-* fixtures.
- **Result**: ✅ verified — 4 apply-bash assertions PASS in harness; resolves Stage 2 BLOCK-1.

### Decision 4 — Bundle migration 0010 separately

- **Evidence**: Migration 0010 not in this phase. CONTEXT.md §"Decision 4" + ADR 0021 §"Alternatives Rejected" both record rationale (different blast radius, separate review focus). Cparx improvement (646 → ~496) acknowledged as not yet meeting ≤200L; 0010 queued.
- **Result**: ✅ scope held.

## Cross-references (for future reviewers)

| Artifact | Purpose |
|---|---|
| `CONTEXT.md` | Phase intent, decisions surfaced, risks |
| `RESEARCH.md` | Brainstorming alternatives for detection / setup-skill remediation / migration-0010-bundling / fixture strategy |
| `PLAN.md` | Task breakdown, dependency graph, goal-backward verification table |
| `REVIEW.md` | Stage 1 (spec compliance) + Stage 2 (independent code-quality) + Resolution log for Stage 2 findings |
| `SECURITY.md` | /cso-style audit; 4 findings (none blocking); verdict PASS |
| `VERIFICATION.md` | This file — 1:1 evidence for each acceptance criterion + decision |

## Outcome

**Phase 06 complete.** Migration 0009 ships with:

- Heading-agnostic detection (H2 + H3 + H4) — works against cparx and fx-signal-agent's actual on-disk heading shape (H3) which initial implementation missed (caught by Stage 2 BLOCK-1, fixed pre-merge).
- Extraction range covers full inlined block through `## Skill routing` — caught by Stage 2 BLOCK-2, fixed pre-merge.
- Project-owned `## Development Workflow` headings preserved (start anchor uses Superpowers heading or smoking-gun H1, never `## Development Workflow` alone) — caught by Stage 2 BLOCK-3, fixed pre-merge.
- Per-migration commit model accurately documented in rollback prose — caught by Stage 2 FLAG-1, fixed pre-merge.
- Migration 0000 Step 4 patched in-place to vendor on first install — root-cause fix; ADR 0021 documents the immutability trade-off.
- Test harness extended from 29 to 38 assertions; new apply-step coverage prevents BLOCK-1 regression.
- Fixtures rewritten to mirror legacy on-disk shape (H3, with full trailing sections through Skill routing).
- 4 NITs accepted with documented rationale; 1 partial fix (FLAG-5: harness coverage extended for highest-risk step only); 1 follow-up enhancement queued (NIT-3: vendored-from version stamp for v1.9.0+).

Two follow-up phases queued for separate planning:
- Migration 0010 (GSD compiler reference-mode for auto-managed
  PROJECT/STACK/CONVENTIONS/ARCHITECTURE sections) — required to bring
  cparx ≤200L.
- Apply-step harness coverage for Steps 1, 3, 5's bash blocks (low priority — post-checks catch outcome failures).
