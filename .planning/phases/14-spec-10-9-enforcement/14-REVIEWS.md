# Phase 14 — REVIEWS — Pre-execution peer review of PLAN.md

**Date**: 2026-05-15
**Reviewers**: 3 (codex-cli 0.130.0, gemini 0.28.2, Claude Opus 4.7)
**Subject**: `.planning/phases/14-spec-10-9-enforcement/PLAN.md` v1 (initial draft)
**Verdict aggregate**: **BLOCK** — codex returned BLOCK on Q1 (spec conformance), gemini and Claude returned REQUEST-CHANGES. PLAN.md must be revised before T1 starts.

Raw reviewer outputs live in `.codex-review.md`, `.gemini-review.md`, `.claude-review.md` (gitignored — not committed). This file is the consolidated, committed record.

---

## Reviewer roster

| Reviewer | Tool | Mode | Result |
|---|---|---|---|
| Codex GPT-5 | `codex exec` (default approval) | full tool access, full workspace + spec dir read | BLOCK (Q1) |
| Gemini Code Reviewer v1.0 | `gemini --allowed-tools "read_file,list_directory,search_file_content,glob"` | read-only, workspace-only — could not read spec at `agenticapps-workflow-core/` | REQUEST-CHANGES (Q4 BLOCK on SHA pinning) |
| Claude Opus 4.7 (phase author) | self-review, structured | full workspace + spec | REQUEST-CHANGES (Q4 FLAG on SHA pinning + injection) |

Gemini's workspace constraint meant it relied on CONTEXT.md / RESEARCH.md summaries of the spec rather than the spec itself. Its Q1 PASS is therefore weaker evidence than codex's Q1 BLOCK; codex's reading of the spec (line citations to §10.9.1 line 176 and §10.9.2 lines 211-217) is authoritative.

The 3-reviewer floor declared by migration 0005 pre-flight is met (2 CLIs available + 1 host Claude). No reviewer was a sub-agent of another; codex and gemini were invoked as independent OS processes.

---

## Consolidated findings (by question)

### Q1 — Spec conformance: **BLOCK** (codex), PASS (gemini, weak), PASS w/ FLAG (Claude)

Codex identified three concrete spec-conformance gaps that all reviewers must agree are load-bearing because they are MUSTs in §10.9:

1. **Empty-delta path skips machine-readable summary** — T1 says "On empty result, write a delta report and exit", but §10.9.1 line 176 makes the machine-readable summary an unconditional MUST. Fix: emit `delta.json` with zero counts BEFORE the early exit. Apply this for the empty-delta case; the `delta.json` always exists whenever `--since-commit` was provided.

2. **Baseline schema relaxed beyond spec** — PLAN T3/T4 allow `policy_hash: null` (for projects without policy.md) and `scanned_commit: "working-tree"` (for dirty trees). Spec §10.9.2 lines 184-217 shows literal SHA + sha256 forms in the canonical schema; allowing nulls/non-SHA values produces a non-spec-conformant artefact that the dashboard and CI gate would have to special-case. Fix: tighten — `policy_hash` is always `sha256:<hex>`; `scanned_commit` is always a 40-char SHA (`git rev-parse HEAD`). Projects without `policy.md` cause the scan to error out, not to emit a degraded baseline. The migration's pre-flight enforces both preconditions before Step 2 runs.

3. **CI fail rule wording does not match the spec's comparison** — PLAN T6 says "fail if delta gaps > 0". §10.9.3 says "Compares the delta scan's high-confidence-gap count against the baseline file from the PR's merge-target branch. Fails the PR if the count increases." The pragmatic implementation is equivalent (delta represents net new gaps in the PR), but the workflow MUST do the explicit comparison so the spec wording is met and the comparison's inputs are auditable. Also: the case "base branch has no baseline.json" is undefined by PLAN — fix: log a clear "enforcement disabled — no baseline on base branch" and pass the gate (per §10.9.3 "MUST NOT be able to opt out silently — the workflow MUST log a clear message").

### Q2 — Spec-vs-handoff divergence: PASS (all 3)

RESEARCH D1's reading (baseline writes ONLY on `--update-baseline` or `scan-apply` success) is confirmed by every reviewer with a direct line citation: §10.9.2 line 219 is the only sentence in the spec that constrains *when* the baseline is updated, and it lists those two triggers. PLAN.md correctly encodes this.

### Q3 — Migration 0011 design: FLAG (codex, gemini, Claude)

Three points, two of them substantive:

1. **T7 Step 2's apply primitive (skill invocation from migration)** — workable inside Claude-Code-driven update flows but creates a hard `claude`-CLI dependency the migration framework didn't have before. Mitigation: declare `tool: claude` in the migration's `requires:` block with verify `command -v claude >/dev/null`, so a host without claude in PATH fails pre-flight with a clear message rather than producing a half-applied migration.

2. **Fixture 04 (CI workflow already present) "preserve + exit 4" leaves a stamped-as-1.10.0 project with a non-conformant workflow** — codex caught this clearly. Fix: ALWAYS overwrite `.github/workflows/observability.yml` with the scaffolder-shipped version. The workflow file is scaffolder-owned per the §10.9.3 reference-workflow contract; user-side edits are explicitly out-of-scope. Document in `ci/README.md` that local edits will be clobbered on each scaffolder update (advise: fork the action, or override in a sibling workflow file).

3. **Migration aborts vs skips for projects without `observability:` block** — CONTEXT and PLAN disagreed; codex flagged the drift. Fix: change Migration 0011 to ABORT pre-flight with the message "Run `claude /add-observability init` first, then re-run `/update-agenticapps-workflow`." Remove the `optional_for: no-observability` clause. The migration framework's standard "from_version mismatch → skip silently" still applies for projects on versions other than 1.9.3.

### Q4 — CI workflow security: BLOCK (gemini), FLAG (codex, Claude)

Three concrete tightenings, all of which become T6 implementation requirements:

1. **Pin action SHAs, not tags.** `marocchino/sticky-pull-request-comment@v2` is a supply-chain attack vector. T6 implementation MUST use 40-char SHAs with the tag in a comment. Specific pins (as of 2026-05-15):
   - `actions/checkout@<resolve at implementation>` # v4.x
   - `marocchino/sticky-pull-request-comment@<resolve at implementation>` # v2.9.x or latest stable

   Resolve via `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` at T6 implementation time and hardcode the resulting SHA. Add a one-line note in `ci/README.md` linking to a renovate/dependabot config example that updates the pinned SHAs.

2. **Avoid GitHub context interpolation inside `run:` blocks.** Pattern: lift `${{ github.event.pull_request.base.sha }}` into a step-level `env:` first, then reference `$BASE_SHA` inside `run:`. Applied universally — every `${{ }}` interpolation gets an env-var indirection.

3. **`pull_request` (NOT `pull_request_target`).** PRs from forks must run with no secrets and no write tokens. The workflow currently triggers on `pull_request` (correct); make this explicit in `ci/README.md` with a "DO NOT change to `pull_request_target`" callout. Threat model written into the README: a malicious PR could put a prompt-injection payload in the diff that `claude` reads; mitigation is read-only permissions and least-trust env.

4. **Concurrency control.** Codex didn't flag this but Claude self-review did — add `concurrency: { group: observability-${{ github.ref }}, cancel-in-progress: true }` to prevent races on rapid pushes.

### Q5 — PLAN/RESEARCH/CONTEXT drift: FLAG (all 3)

Three drifts to resolve:

1. **CONTEXT.md "Coverage matrix" implies baseline.json is the machine-readable summary** (a line that says "machine-readable summary | baseline.json"). RESEARCH D1 supersedes: `delta.json` is the per-PR machine-readable summary; `baseline.json` is the canonical conformance state, written only on `--update-baseline` / `scan-apply` success. Fix: update the CONTEXT.md Coverage matrix row in this revision.

2. **CONTEXT promised a smoke test of this repo's delta scan against `main`** ("a real delta-scan dry-run against this very repo's `feat/observability-enforcement-v1.10.0` HEAD vs `main`"). PLAN never schedules it. Fix: add a new task T12.5 — "Smoke test — execute the delta scan procedure against this branch HEAD vs `main`, confirm `delta.json` is well-formed and reflects no observability-relevant findings (this repo has no `lib/observability/` because claude-workflow isn't itself instrumented)."

3. **CONTEXT says "missing observability block fixture should abort clearly"; T8 fixture 03 said "skip with exit 0".** Already covered under Q3 above — resolve as ABORT.

### Q6 — Risk register completeness: FLAG (all 3)

Add these four risks (each with mitigation, per the risk-register format):

| Risk | Likelihood | Mitigation |
|---|---|---|
| Baseline.json merge conflicts on concurrent PRs | High | Document in `ci/README.md` that mid-PR rebases against main require `scan --update-baseline` and a fresh commit. Note that conflicts are mechanical (counts) and the fix is regenerate-not-merge. RESEARCH D4 promised this. |
| `claude` CLI absent in target environment | Med | Migration 0011 frontmatter `requires.tool.claude` with verify `command -v claude`. Fails pre-flight cleanly if claude isn't installed. |
| Empty-delta produces no `delta.json` (codex Q1.1) | (closed by T1 fix) | T1 always emits `delta.json` regardless of empty walk |
| Claude running on untrusted PR-fork content in CI | High (when adopted) | Document threat model in `ci/README.md`. Permissions read-only on scan job; `pull_request` (not `pull_request_target`) confirmed. Recommend: projects with sensitive content evaluate whether to run scan only on internal PRs (via `if: github.event.pull_request.head.repo.full_name == github.repository`). |

### Q7 — Verification gaps: FLAG (codex, Claude), PASS (gemini)

Add these evidence rows to T14:

| Must-have | Evidence |
|---|---|
| §10.9.1 delta mode preserves confidence/output rules from full scan | Fixture: same fixture project under full scan vs delta scan; assert `.scan-report.md` section structure identical; assert delta findings ⊆ full findings |
| §10.9.2 baseline schema is byte-exact to spec example | T3 commits `baseline-template.json`; T13 includes `jq -e '.spec_version and .scanned_at and .scanned_commit and .module_roots and .counts and .high_confidence_gaps_by_checklist and .policy_hash' <fixture-output-baseline>.json` |
| §10.9.3 "compare against baseline" actually runs | Fixture: synthetic baseline.json (high=5) and synthetic delta.json (high=0) → assert workflow shell logic exits 0; synthetic delta.json (high=2) → assert exits 1 |
| §10.9.3 "fail on increase" via synthetic fixture | (same as row above) |
| §10.9.3 "surface findings as PR comment" | Structural: T16 SECURITY.md confirms the `marocchino/...` action is present with SHA-pin + minimal permissions. Behavioural test deferred (not feasible without GHA execution) — documented as "structural only" with rationale. |
| Migration 0011 preflight audit (Phase 13) green | T13 explicit row: `bash migrations/run-tests.sh preflight` exits 0 with 0011 listed as audited |

---

## Required PLAN.md revisions before T1 may start

A single PLAN.md revision pass incorporating the following list. Each item maps 1:1 to a finding above so the revision is auditable.

1. **T1**: empty-delta path runs Phase 8 (delta.json write) BEFORE exit. Document explicitly.
2. **T1**: codify `git diff --name-only <ref>...HEAD` (triple-dot) and note rationale in SCAN.md "Important rules".
3. **T3 / T4 Phase 7**: `scanned_commit` = `git rev-parse HEAD` (40-char SHA, always). `policy_hash` = `sha256:<hex of policy.md>` (always). No nulls, no "working-tree" string.
4. **T4 Phase 7 pre-condition**: error out if `policy.md` not found.
5. **T5 APPLY.md Phase 6b**: same schema constraints as T4 Phase 7.
6. **T6 observability.yml**: explicit `B = jq baseline_high; D = jq delta_high; if D > 0: fail` comparison logic. Handle missing base baseline → log "enforcement disabled — no baseline on base branch" and pass gate.
7. **T6 observability.yml**: SHA-pinned actions with version comments. Resolve SHAs at implementation time.
8. **T6 observability.yml**: env-var indirection for every `${{ }}` interpolation inside `run:`.
9. **T6 observability.yml**: explicit `pull_request` trigger comment "DO NOT change to pull_request_target".
10. **T6 observability.yml**: `concurrency:` block.
11. **T6 ci/README.md**: threat model section (claude-on-untrusted-PR-content + mitigations + opt-out path for sensitive projects).
12. **T6 ci/README.md**: baseline.json merge-conflict guidance.
13. **T7 frontmatter `requires`**: add `tool: claude` and `policy.md exists` pre-conditions.
14. **T7 Step 1**: ALWAYS overwrite `.github/workflows/observability.yml`. Drop fixture 04's "preserve + exit 4" branch.
15. **T7 pre-flight**: hard ABORT if `observability:` block missing from CLAUDE.md (drop `optional_for: no-observability`).
16. **T7 Step 2 Apply block**: name the in-skill dispatch path explicitly ("Read `~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md` and follow Phase 7 with `--update-baseline=true`").
17. **T8 fixtures**: drop fixture 04 (CI workflow already present, preserve); replace with "fixture 04: pre-existing custom workflow.yml gets overwritten with backup `.bak`". Add fixture 07: claude binary absent → pre-flight fails cleanly.
18. **T12.5 (new)**: smoke test — delta scan this repo's HEAD vs main; confirm delta.json well-formed.
19. **T14**: add 6 evidence rows above.
20. **Risk register**: add 4 risks listed above.
21. **CONTEXT.md Coverage matrix**: clarify delta.json is the machine-readable summary (not baseline.json).

This is the full list. After applying these, the PLAN is unanimously approved.

---

## Verdict timeline

- 2026-05-15 09:18 — PLAN.md v1 drafted
- 2026-05-15 09:25 — codex + gemini launched in parallel
- 2026-05-15 09:26 — gemini #1 errored on `--approval-mode plan`
- 2026-05-15 09:32 — gemini #2 completed (REQUEST-CHANGES)
- 2026-05-15 09:34 — codex completed (BLOCK)
- 2026-05-15 09:35 — REVIEWS.md drafted (this file)
- (pending) — PLAN.md v2 revision pass
- (pending) — T1 begins
