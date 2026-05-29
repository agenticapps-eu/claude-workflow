# Phase 22 — Summary

**Ship target:** `claude-workflow 1.18.0` + `add-observability 0.6.0`
**Branch:** `feat/sentry-crons-healthz-v1.18.0` (30 commits ahead of main)
**Date opened:** 2026-05-29
**Date ready-for-PR:** 2026-05-29

## What this phase delivers

Three deliverables in one PR closing the "is the platform up and is the cron firing?" gap that the v0.5.x in-request observability wrapper couldn't see:

1. **`withCronMonitor` wrapper** — optional, additive export across 4 stacks (worker / pages / supabase-edge / go-fly-http; react-vite skipped). Emits Sentry checkin heartbeats (`in_progress` → `ok`/`error`) per scheduled-handler invocation. 3-source slug resolution (explicit > env > auto-derived). `monitorConfig` (schedule + maxRuntime) forwarded as Sentry's 2nd arg on first checkin only. Fail-safe when `SENTRY_DSN` is unset.

2. **`healthz-snippet.{ts,go}` copy-only templates** — per-stack HTTP healthz handlers aggregating dependency probes into 200 / 503. Fail-closed on zero probes configured (503 + "no probes configured" reason). Multi-line WARNING block at top of each file instructing operator to adapt-before-mounting. NOT routed through `withObservability` (D4 — avoids Sentry transaction-view noise from Uptime probes).

3. **Operator runbook** — `add-observability/uptime-setup-runbook.md` (460 lines) walking operators through Sentry UI configuration: Crons setup per `monitorSlug`, Uptime setup per `/healthz` endpoint, `policy.md` inventory template, Security & Public Exposure mitigations (`?detail=true` gating, `/healthz` vs `/readyz` deferral, probe authentication).

Distributed via **additive migration 0019** with 2-pass atomic apply mirroring 0017's hardened pattern (codex's HIGH-severity finding on the original single-pass plan was caught and addressed pre-execution).

## Artifacts

| Artifact | Path | Purpose |
|---|---|---|
| Design (locked) | `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` | G1–G8 + D1–D12 |
| Plan + binding revisions | `.planning/phases/22-sentry-crons-healthz/PLAN.md` | 17 tasks + R01–R12 |
| Pre-plan multi-AI review | `.planning/phases/22-sentry-crons-healthz/22-REVIEWS.md` | gemini LOW / codex HIGH; 5 verified inconsistencies |
| Stage 1 + 2 review | `.planning/phases/22-sentry-crons-healthz/REVIEW.md` | spec compliance + code quality |
| Security review | `.planning/phases/22-sentry-crons-healthz/SECURITY.md` | 10-dimension threat analysis |
| Verification | `.planning/phases/22-sentry-crons-healthz/VERIFICATION.md` | 1:1 goal evidence + test counts |
| Summary (this file) | `.planning/phases/22-sentry-crons-healthz/SUMMARY.md` | cross-links + PR prep |
| ADR | `docs/decisions/0028-sentry-crons-healthz-conventions.md` | host-discretion vs spec-mandate trade-off |
| Migration spec | `migrations/0019-sentry-crons-and-healthz.md` | operator-facing procedure |
| Apply engine | `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | 724-line bash, 2-pass atomic |
| Fixtures (7) | `migrations/test-fixtures/0019/0{1..7}-*/` | exercise the apply engine |
| Runbook | `add-observability/uptime-setup-runbook.md` | Sentry UI configuration |

## Verdicts

| Gate | Verdict | Notes |
|---|---|---|
| Pre-plan multi-AI review (gemini + codex) | gemini LOW / codex HIGH | All 5 codex HIGH findings folded as R01–R12 binding revisions |
| Stage 1 spec compliance | PASS WITH ISSUES | 1 LOW: INIT.md Phase 5 docs gap (information present in source comments + runbook) |
| Stage 2 code quality | PASS | 4 minor stylistic items deferrable |
| /cso security | PASS WITH HARDENING | 0 HIGH, 2 MEDIUM (probe timeout + signal trap, deferred to 22.1), 4 LOW |
| Test suites | GREEN | migrations 178 PASS / 0 FAIL; templates 228 PASS across 5 stacks |
| G2 byte-identical | PASS | filename allowlist verified; no existing wrapper files modified |

**Overall:** ready to merge. All blockers addressed; non-blocking items documented as 22.1 follow-ups.

## Branch composition

30 commits ahead of `main`:

| Group | Commits | Notes |
|---|---|---|
| Bootstrap | 1 | `122aafa` SKILL.md drift hotfix (D9 — folds 0018 follow-up) |
| Planning artifacts | 4 | CONTEXT, PLAN, 22-REVIEWS, fold-feedback |
| Worker cron-monitor | 2 | RED + GREEN |
| Pages cron-monitor | 2 | RED + GREEN |
| Supabase-edge cron-monitor | 2 | RED + GREEN |
| Go-fly-http cron-monitor | 2 | RED + GREEN |
| 4× healthz snippets | 8 | RED + GREEN per stack |
| Operator runbook | 1 | T14 |
| Migration 0019 (MD + engine) | 1 | T10 |
| Migration fixtures + wiring | 1 | T11 + T12 |
| ADR-0028 | 1 | T15 |
| CHANGELOG + version bumps | 1 | T16 |
| Post-completion cleanup | 1 | T18 (R12) |
| Stage 1 review | 1 | spec compliance |
| Stage 2 review | 1 | code quality |
| Security review | 1 | /cso |

## Adjacent / out-of-scope

- **No spec change** to `agenticapps-workflow-core@v0.4.0` — phase 22 implementation behavior under §10.6/§10.7. If future evidence shows projects routinely ship without cron heartbeating, revisit as §10.10 in a separate proposal. (ADR-0028.)
- **Downstream adoption** (fxsa / callbot / cparx pulling v1.18.0) is covered by separate prompts (D / E / F in the user's sequencing plan).
- **22.1 follow-ups** (collected from review gates):
  1. INIT.md Phase 5 composition notes (Stage 1 LOW).
  2. Healthz per-probe timeout (Stage 2 MEDIUM S4).
  3. Migration engine signal trap (Stage 2 MEDIUM S6).
  4. SKILL.md drift guardrail test (CONTEXT N4).

## Ready for PR

- All test suites green.
- All review verdicts in.
- Branch composition coherent (30 atomic commits).
- VERIFICATION.md cross-links 1:1 evidence per goal.
- PR title (proposed): `feat: Sentry Crons heartbeats + healthz endpoint convention (claude-workflow 1.18.0)` against `main`.
- PR body to compose via `superpowers:finishing-a-development-branch`.
