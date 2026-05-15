# Phase 14 — CONTEXT — Implement spec §10.9 enforcement layer

**Date**: 2026-05-15
**Branch**: `feat/observability-enforcement-v1.10.0`
**Scaffolder bump**: `1.9.3 → 1.10.0`
**Spec target**: `agenticapps-workflow-core` §10.9 at `spec_version: 0.3.0`
**Migration slot**: `0011-observability-enforcement.md` (next free sequential ID)

## Origin

This phase was opened from a hand-off prompt (`claude-workflow-update-prompt.md`, written 2026-05-13) that pre-supposed claude-workflow was at v1.5.0. In the two days between draft and execution, the chain advanced through phases 11/12/13 (chain-gap cleanup, 0005 verify-path fix, preflight-correctness audit) and `skill/SKILL.md` is now at `1.9.3`. The hand-off's specific numbers (target version `1.6.0`, migration `0003-enforcement-v0.3.0.md`) are stale; this CONTEXT re-bases against current state. The hand-off's **technical content** — three primitives + a migration — is exactly what spec §10.9 mandates and is implemented unchanged.

## What §10.9 demands of generators

Spec §10.9 (`spec/10-observability.md`, lines 168-238) introduces three new MUSTs and one MAY:

1. **§10.9.1 Delta scan (MUST)** — `scan` accepts `--since-commit <ref>`, walks only files diffed between `<ref>` and HEAD. Same confidence buckets as full scan. A machine-readable summary MUST accompany the human report.

2. **§10.9.2 Baseline file (MUST)** — `.observability/baseline.json` (canonical path) records spec_version, scanned_at, scanned_commit, module_roots, counts (conformant / high / medium / low + per-checklist high gaps), and `policy_hash`. Generators MUST regenerate the baseline on successful `scan-apply` and MUST expose `--update-baseline` for manual refresh.

3. **§10.9.3 CI-integration guidance (SHOULD-ship-reference, MUST-not-allow-silent-opt-out)** — Each host SHIPS a reference workflow that runs delta scan on PRs, diffs the count against the baseline from the merge-target branch, fails on regression, comments with new findings. Projects MUST be able to opt out by deleting/emptying the baseline file but MUST NOT be able to do so silently — the workflow logs a clear message when enforcement is disabled.

4. **§10.9.4 Pre-commit hook (MAY)** — Optional, deferred to a later version per the hand-off's "Non-goals".

Spec §10.8 gains an optional `enforcement:` sub-block (baseline path, ci workflow path, pre_commit toggle) that projects MAY add to declare their enforcement posture. Projects that **declare** the sub-block MUST satisfy the per-field §10.9 requirements.

## Current state of `add-observability/`

| File | Current version | Purpose | Modification needed |
|---|---|---|---|
| `SKILL.md` | `version: 0.2.1`, `implements_spec: 0.2.1` | Skill manifest + subcommand dispatch | Bump both to `0.3.0`. Document new flags in subcommand description. |
| `scan/SCAN.md` | 6 phases (Detect → Metadata → Walk → Trivial → Compose → Print) | Brownfield audit procedure | Insert Phase 0.5 (resolve scope from `--since-commit`); insert Phase 7 (emit baseline). |
| `scan/checklist.md` | C1-C4 detection rules | Read by SCAN.md | No change (rules unchanged). |
| `scan/detectors.md` | Language patterns per checklist | Read by SCAN.md | No change. |
| `scan/report-template.md` | Markdown template with `{{...}}` tokens | Filled by SCAN.md Phase 5 | Add `scope` + `since_commit` frontmatter fields; add delta banner section. |
| `scan/baseline-template.json` | **does not exist** | new | Create. |
| `scan-apply/APPLY.md` | 8 phases, Phase 6 rewrites `.scan-report.md` | Apply consented fixes | Extend Phase 6 to regenerate `baseline.json` too. |
| `scan-apply/example-session.md` | Worked example | Documentation | Touch only if APPLY.md additions require a new example step. |
| `templates/<stack>/*` | 5 stacks, 61 contract tests | Stack code emitters | **No change** — regression guard: all 61 tests must remain green. |
| `CONTRACT-VERIFICATION.md` | v0.2.1 verification record | Spec coverage doc | Add a "v0.3.0 §10.9" addendum section pointing at the new artefacts. |
| `ci/observability.yml` | **does not exist** | new | Create. |
| `ci/README.md` | **does not exist** | new | Create — documents the GHA limitation (Claude Code in CI not yet supported) and the three project-side workarounds. |

## Current migration chain

```
0000 (unknown→1.2.0)  baseline
0001 (1.2.0→1.3.0)    go-impeccable-database-sentinel
0004 (1.3.0→1.4.0)    programmatic-hooks-architecture-audit
0002 (1.4.0→1.5.0)    observability-spec-0.2.1
0008 (1.5.0→1.6.0)    coverage-matrix-page
0009 (1.6.0→1.8.0)    vendor-claude-md-sections (skips 1.7)
0010 (1.8.0→1.9.0)    post-process-gsd-sections
0005 (1.9.0→1.9.1)    multi-ai-plan-review-enforcement
0006 (1.9.1→1.9.2)    llm-wiki-builder-integration
0007 (1.9.2→1.9.3)    gitnexus-code-graph-integration
```

Next slot: **`0011`**, `from_version: 1.9.3 → to_version: 1.10.0`. (0003 is a historical gap; not reused.)

## Project metadata changes in CLAUDE.md

Migration 0011 must update each project's `CLAUDE.md` observability block. The shape after migration:

```yaml
observability:
  spec_version: 0.3.0     # bumped from 0.2.1
  destinations: [...]
  policy: lib/observability/policy.md
  enforcement:            # NEW sub-block (§10.8 OPTIONAL — but enforced here)
    baseline: .observability/baseline.json
    ci: .github/workflows/observability.yml
    pre_commit: optional
```

The migration also adds one line under the project's existing Skills section: `Observability enforcement: claude /add-observability scan --since-commit main` (the per-PR command the developer can run locally, mirroring CI).

## Multi-AI plan review gate (migration 0005)

Migration 0005 installed a PreToolUse hook (`templates/.claude/hooks/multi-ai-review-gate.sh`) that blocks `Edit|Write` when a `*-PLAN.md` exists in the active phase but `*-REVIEWS.md` does not. **The claude-workflow scaffolder repo itself does not currently dogfood that migration in its own `.claude/settings.json`** (the repo *ships* the hook; it doesn't run it on itself). That means writing this phase's PLAN.md will not block subsequent edits.

The protocol still requires a multi-AI review of PLAN.md before execution. We satisfy this by producing `14-REVIEWS.md` after PLAN.md is drafted, with a structured critique pass (codex + gemini if available, otherwise a thorough Claude self-review with explicit rationale for what would normally be cross-checked). The session-handoff "match review depth to diff kind, not just size" norm applies — this is a substantial diff touching skill behaviour and migration infrastructure; full review is warranted.

## Coverage matrix (where each §10.9 obligation gets satisfied)

| Obligation | Where it lands | How verified |
|---|---|---|
| §10.9.1 `--since-commit` flag | `scan/SCAN.md` Phase 0.5 | Procedure includes `git diff --name-only <ref>...HEAD` and file-scope filter |
| §10.9.1 machine-readable summary | `.observability/delta.json` (separate from baseline; see RESEARCH D1) | Distinct file from baseline.json; emitted unconditionally whenever `--since-commit` is set, including on empty deltas |
| §10.9.1 confidence rules unchanged | `scan/SCAN.md` Phase 3 untouched | Same checklist.md / detectors.md drive both modes |
| §10.9.2 canonical path `.observability/baseline.json` | `scan/SCAN.md` Phase 7 + `scan/baseline-template.json` | Test fixture writes to that exact path |
| §10.9.2 schema (spec_version, scanned_at, scanned_commit, module_roots, counts, per-checklist gaps, policy_hash) | `baseline-template.json` | jq-validatable on each run |
| §10.9.2 baseline regen on `scan-apply` | `scan-apply/APPLY.md` Phase 6 extension | Fixture: apply session, assert baseline counts decrease |
| §10.9.2 `--update-baseline` manual override | `scan/SCAN.md` Phase 7 | Procedure includes the flag |
| §10.9.3 reference CI workflow shipped | `ci/observability.yml` | File present at the path |
| §10.9.3 no silent opt-out | CI step that logs explicit message if baseline missing/empty | Inline in `observability.yml` |
| §10.9.3 policy_hash diff (MAY) | CI step that warns on policy.md changes | Inline; warn-only at v1.10.0 |
| §10.8 `enforcement:` sub-block in CLAUDE.md | Migration 0011 Step 3 | Idempotency check via `yq`/`grep` |
| Adoption flow into existing projects | Migration 0011 | Test fixtures for fresh-apply, idempotent re-apply, rollback |

## Verification budget

- All 61 v0.2.1 contract tests still pass (no regression in `templates/*`).
- New `test_migration_0011()` in `run-tests.sh` with ≥ 6 sandboxed fixtures: fresh-apply, idempotent-re-apply, baseline-already-present (preserve), CI-workflow-already-present (preserve), CLAUDE.md-missing-observability-block (abort with clear message), rollback.
- A real delta-scan dry-run against this very repo's `feat/observability-enforcement-v1.10.0` HEAD vs `main` — the diff is large but contains zero conformance-relevant Go/TS source files, so the delta scan should produce a no-findings report. This is the smoke test that the scope-filter works.

## Open decisions surfaced to RESEARCH.md

Three from the hand-off prompt plus two surfaced during context re-baseline:

1. **Standalone Node scanner port** — defer? (Hand-off Q1)
2. **CI gate threshold: high only, or include medium?** (Hand-off Q2)
3. **`policy_hash` in baseline** — already in spec §10.9.2 as MUST. Not a decision, mark **closed**.
4. **Migration slot number** — 0011 vs reuse 0003 gap? Re-baseline calls for 0011.
5. **Pre-commit hook scope at v1.10.0** — defer per hand-off "Non-goals"? Reaffirmed: defer.
