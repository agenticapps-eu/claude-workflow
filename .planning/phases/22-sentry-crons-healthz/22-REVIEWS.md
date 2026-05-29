---
phase: 22
reviewers: [gemini, codex]
reviewed_at: 2026-05-29T13:00:00Z
plans_reviewed: [PLAN.md]
verdicts: { gemini: LOW, codex: HIGH }
runtime_self: claude (skipped per CLAUDE_CODE_ENTRYPOINT=cli; coderabbit + opencode not installed locally)
---

# Cross-AI Plan Review — Phase 22

Two reviewers (gemini, codex) independently assessed CONTEXT.md + PLAN.md. **They diverged sharply** — gemini called overall risk LOW; codex called it HIGH and surfaced 5 verified internal inconsistencies. That divergence is exactly what ADR-0018's "no single-reviewer drift" rule is meant to surface.

---

## Gemini Review

### Summary

Exceptionally well-structured and comprehensive plan that, executed as written, would successfully deliver Goals G1–G8. The plan addresses out-of-band cron monitoring + uptime probing through optional wrappers and copy-only templates. Mature: backward compatibility, TDD, robust migration strategy with multiple fixtures, clear operator documentation. **LOW risk overall.**

### Strengths

- **Low-Risk Implementation:** Purely additive. `withCronMonitor` + copy-only snippets keep existing v0.5.1 byte-identical (G2).
- **Thorough TDD:** RED + GREEN commits per behavioral test in T02–T09; high regression-safety.
- **Robust Migration Strategy:** T10–T12 covers 5 real-world scenarios (idempotency, refusal on hand-modified, multi-module).
- **Granularity:** 17 logically-sequenced tasks with explicit code snippets and commit messages.
- **Documentation Plan:** Runbook + ADR + INIT.md updates + CHANGELOG — not just code.

### Concerns

- **MEDIUM — Migration Brittleness.** The style-insensitive content-hash check (D8, T10) is sound, but benign formatter version bumps (e.g. Prettier) between v1.17.0 adoption and 0019 apply could flip hashes and force unnecessary refusal. The plan provides a diff + guidance, but adoption friction is real.
- **LOW — Healthz Misconfiguration.** Copy-only snippets ship example probes (KV / DB). Operator may copy without adapting → permanently `degraded` 503 on dependencies they don't actually run.
- **LOW — Silent Heartbeat Failures.** `withCronMonitor` swallows `captureCheckIn` errors for reliability, but an invalid DSN or Sentry-side issue is invisible to the operator.
- **LOW — Minor Info Disclosure in /healthz.** Default snippet exposes internal dependency names (`db`, `kv`, `serviceBinding`) in the response body — minor topology leak if endpoint is public.

### Suggestions

- Strengthen the top-of-file comment in healthz snippets: **WARNING — adapt or remove unused example probes; non-existent deps will report permanent degraded.**
- Add opt-in `SENTRY_DEBUG=1` to surface swallowed `captureCheckIn` errors to console for debugging.
- Add "Security Considerations" section to the runbook covering healthz public-exposure risk + optional check-breakdown removal.

### Risk Assessment

**LOW.** Additive design + comprehensive testing minimizes correctness risk. Main risk is migration UX (content-hash brittleness), not code defects. The plan's patch-fallback adequately mitigates.

---

## Codex Review

### Summary

Strong on release hygiene, additive migration thinking, and operator documentation, **but does NOT cleanly deliver G1–G8 as written.** Five internal contradictions: export-surface mismatch, bad fit between D5 and current supabase-edge architecture, missing monitor-config forwarding, migration sketch missing 0017's atomic all-clean property, and a fixture set that doesn't prove the atomic refusal. **HIGH risk** — executed literally, would ship green unit tests + production-incomplete release.

### Strengths

- Disciplined additive-only change posture — correct for a migration-locked scaffolder.
- D4 (keep /healthz out of `withObservability`) is correct.
- Unusually explicit about idempotency, hand-modified refusal, fixture-driven migration testing.
- T02–T05 pin core behavior contract (happy / throw / no-DSN).
- Operator runbook isn't fluff — UI-side configuration is part of the feature for Sentry Crons/Uptime.

### Concerns

- **HIGH — G1/G2 contradiction.** G1 says `middleware.{ts,go}` exports `withCronMonitor`, but PLAN's file structure puts it in new `cron-monitor.{ts,go}` files. **VERIFIED against CONTEXT.md L29 and PLAN.md file-structure table.** Both can't be true: either re-export from existing wrapper (breaks G2 byte-identical) or fix G1.
- **HIGH — D5/T13 wrong for Supabase Edge.** Stack only has `withObservability(handler)` for request handlers ([middleware.ts](add-observability/templates/ts-supabase-edge/middleware.ts) line 36); no `withObservabilityScheduled`, no `withSentry` composition. **VERIFIED: grep returned no matches.** D5's "(worker & supabase-edge)" composition claim is wrong for supabase-edge.
- **HIGH — Monitor config (schedule + maxRuntimeSeconds) not forwarded to Sentry.** JS API is `captureCheckIn(checkIn, monitorConfig?)`; Go API is `CaptureCheckIn(checkIn, monitorConfig)`. PLAN T02 + T05 sample code only passes the first arg, so `schedule` and `maxRuntimeSeconds` are dead fields contradicting CONTEXT N5's "forwarded as metadata" claim. (Codex web-search sources: <https://docs.sentry.io/platforms/javascript/guides/koa/configuration/draining/>, <https://pkg.go.dev/github.com/getsentry/sentry-go>.)
- **HIGH — T10 single-pass apply regresses 0017's atomic safety.** 0017 explicitly classifies all roots, gates on all-clean, then applies in a second pass ([migrate-0017-axiom-destination.sh:305+](templates/.claude/scripts/migrate-0017-axiom-destination.sh)). **VERIFIED: classification loop confirmed.** T10's `for wrapper_dir in ...; do ... done` sketch is single-pass; a dirty wrapper discovered after a clean one is already applied yields partial state — exactly what 0017 hardened against.
- **HIGH — Fixtures don't prove atomic refusal.** T11 has no "2 clean + 1 dirty multi-root" case. That's the failure mode 0017 was built around. Missing fixture means atomic property goes untested.
- **MEDIUM — D6 inconsistency.** Locked text says pages/supabase auto-derives to `${serviceName}:scheduled`; T03/T04 sketch derives `${serviceName}:${handlerName}` (defaults to "scheduled" when unset, but takes operator-passed handlerName otherwise). Different semantic.
- **MEDIUM — Env-var naming too coarse.** `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` doesn't model a single worker `scheduled` export dispatching multiple cron expressions. For multi-cron, `SENTRY_CRON_MONITOR_SLUG_SCHEDULED` is ambiguous.
- **MEDIUM — T01 overstates harness work.** `ts-supabase-edge` already globs `*.test.ts` (line 434); Go already globs `*.go` (line 513). **VERIFIED.** Only worker + pages need explicit copy-line additions.
- **MEDIUM — Existence-gated copies are a foot-gun if they survive past the transition.** Silently skip misspelled/missing files.
- **MEDIUM — Healthz can false-green on empty checks.** Worker/Go sketches: `Object.values({}).every(Boolean)` returns `true` → 200 OK on zero checks configured. Bad default.
- **MEDIUM — Healthz mixes liveness + dependency-readiness + info-disclosure.** Suggest split: shallow `/healthz` (always 200 while alive) vs deep `/readyz` (dependency probes), k8s-convention.
- **MEDIUM — Go sample wrong SDK return type.** `sentry.CaptureCheckIn` returns `*EventID`, not `EventID` per [pkg.go.dev sentry-go](https://pkg.go.dev/github.com/getsentry/sentry-go). Package-level seam fragile under `t.Parallel()` — document non-parallel constraint.
- **LOW — T17 byte-identical check brittle.** `git diff main` is sensitive to unrelated main drift. Reframe as "no modifications to file list in the diff" rather than byte-equal to main.

### Suggestions

- Resolve export contract first: keep `withCronMonitor` in new sibling files, rewrite G1 as "importable from `cron-monitor.{ts,go}`" — NOT "exported from existing middleware".
- Rewrite D5/T13 for supabase-edge: either `withObservability(withCronMonitor(handler))` or document as plain request-handler wrapping with no scheduled-wrapper language.
- Add 1 explicit test per stack asserting `monitorConfig` (with `schedule` + `maxRuntimeSeconds`) is forwarded to `captureCheckIn`'s second arg.
- Make 0019 a two-phase engine like 0017: classify → all-clean gate → apply. Add fixture with 2 clean + 1 dirty roots.
- Add dedicated `react-vite`-only fixture (the "no eligible stacks" path T10 claims but doesn't test).
- Make `/healthz` fail closed on zero configured probes, OR split shallow `/healthz` from deep `/readyz`.
- Tighten slug override for worker multi-cron handlers: require explicit `monitorSlug` OR support per-cron-expression env keys.
- Fix Go SDK return type to `*EventID`; document tests as non-parallel.

### Risk Assessment

**HIGH.** Not implementation difficulty — semantic drift between locked design, current scaffolder architecture, and sample code the executor is supposed to follow. Most-likely failure mode: PR looks disciplined + green-harnesses + ships with incorrect Supabase composition / no monitor-config forwarding / migration atomicity weaker than 0017 / health-checks reporting healthy when nothing is checked. **Production-facing mistakes, not plan-polish.**

Sources for SDK validation: <https://docs.sentry.io/platforms/javascript/guides/koa/configuration/draining/>, <https://pkg.go.dev/github.com/getsentry/sentry-go>.

---

## Consensus Summary

### Agreed strengths (both reviewers)

- Additive design + no v0.5.1 export touched (G2 byte-identical intent is right; codex disputes execution, gemini accepts it).
- Healthz NOT wrapped by `withObservability` (D4) — correct for probe-noise reasons.
- Operator runbook + fixture-driven migration testing are well-scoped.

### Agreed concerns (both reviewers — highest priority)

- **Healthz default snippet is operationally fragile.** Both flag: (a) unadapted-probes-stay-shipped (gemini's permanent-degraded) and (b) zero-checks-false-green (codex's 200-on-nothing). Same root: snippet doesn't enforce "checks must be configured" invariant. **Action: T06/T07/T08/T09 implementations must fail-closed when no probes are configured AND ship with a stronger top-of-file warning AND the runbook must call out the public-exposure risk.**
- **Heartbeat silent-failure / observability of cron-monitor itself.** Both flag the swallowed-error path is invisible to operators. **Action: add opt-in `SENTRY_DEBUG=1` console-log path in the wrapper code; document in runbook.**

### Divergent views (worth investigating)

- **Overall risk: LOW (gemini) vs HIGH (codex).** Codex grounds its HIGH on 5 verified internal inconsistencies (G1/G2 contradiction, D5-supabase mismatch, missing monitor-config forwarding, T10 atomicity regression, missing atomic-refusal fixture). Gemini didn't catch any of these. **Verifying codex's claims locally confirms all 4 verifiable ones are correct** (the 5th — Sentry SDK API shape — relies on web-search Sentry docs).
- **Migration brittleness severity.** Gemini calls it MEDIUM (content-hash + formatter drift); codex calls atomicity regression HIGH but doesn't separately flag the hash brittleness. Both point at the same family of failures but at different specific risks.

### Codex's verified claims (cross-checked against repo)

| Claim | Verification command | Result |
|---|---|---|
| supabase-edge globs `*.test.ts` (T01 overstates) | `sed -n '434,437p' add-observability/templates/run-template-tests.sh` | ✅ verified — `for f in "$SRC"/*.test.ts; do ... done` present |
| Go stack globs `*.go` (T01 overstates) | `sed -n '513,516p' add-observability/templates/run-template-tests.sh` | ✅ verified — `for f in "$SRC"/*.go; do ... done` present |
| supabase-edge has no `withObservabilityScheduled` or `withSentry` | `grep -nE "withObservabilityScheduled\|withSentry" add-observability/templates/ts-supabase-edge/{middleware,index}.ts` | ✅ verified — no matches |
| 0017 apply engine is 2-pass (classify → gate → apply) | `sed -n '305,335p' templates/.claude/scripts/migrate-0017-axiom-destination.sh` | ✅ verified — `declare -a CLEAN_DIRS DIRTY_DIRS` + classification loop confirmed |

Sentry SDK claims (`captureCheckIn(checkIn, monitorConfig?)` second arg, Go `*EventID` return) require final verification at T02/T05 execution; codex's web-search sources point at Sentry's official docs.

---

## Required plan revisions before execution

Based on the verified HIGH+MEDIUM findings, **CONTEXT.md and PLAN.md need targeted revisions** before T01 can be executed. Proposed delta:

### CONTEXT.md edits

1. **G1 — fix "exported from middleware.{ts,go}" → "importable from cron-monitor.{ts,go}".** Aligns G1 with PLAN's file structure (the export contract was the inconsistency).
2. **D5 — narrow composition order to worker only.** Document supabase-edge as `withObservability(withCronMonitor(handler))` (no scheduled wrapper exists there). Remove "(worker & supabase-edge)" wording.
3. **D6 — clarify auto-derived slug as `${serviceName}:${handlerName}` where `handlerName` defaults to "scheduled".** Remove the contradictory "${serviceName}:scheduled" wording.
4. **N5 — split into N5a (schedule + maxRuntimeSeconds ARE forwarded to Sentry via captureCheckIn's monitorConfig second arg) and N5b (client-side timeout enforcement out-of-scope).** The implementation must actually forward; CONTEXT must reflect.
5. **New D11 — multi-cron worker handlers must use explicit `monitorSlug`** (per-cron env-key support deferred to future). Document the env-var limitation.

### PLAN.md edits

6. **T01 — drop existence-gated copy lines for supabase-edge and go-fly-http.** Those stacks already glob. Only worker + pages need 4-line additions. Plan length: ~40 lines saved.
7. **T02 + T05 — sample implementations must pass `monitorConfig` (schedule + maxRuntimeSeconds) as 2nd arg to `captureCheckIn`** on the first checkin (in_progress) per Sentry SDK contract. Add 1 test per stack asserting the second-arg shape.
8. **T05 — fix Go return type `sentry.EventID` → `*sentry.EventID`** in cron_monitor.go + stub.
9. **T06 + T07 + T08 + T09 — healthz fails closed on zero configured probes.** Default snippet returns 503 + `{"status":"degraded","reason":"no probes configured"}` when checks map is empty. Strengthens the top-of-file WARNING.
10. **T10 — rewrite apply engine sketch as 2-pass (classify all roots → all-clean gate → apply only if all-clean).** Mirror 0017's structure verbatim, not the single-pass sketch.
11. **T11 — add fixture 06: `06-multi-root-mixed-clean-dirty-refuses-all`** (2 clean + 1 dirty wrappers; expected-exit non-zero; verify.sh asserts NONE of the wrappers got cron-monitor.ts — proves atomic refusal).
12. **T17 — reframe byte-identical check from "git diff against main" to "git diff filename-set excludes existing wrapper files in the diff".** Less brittle.
13. **NEW T18 (post-completion cleanup) — remove the T01 existence-gates** and assert all expected files exist. Closes the foot-gun.
14. **T02–T05 — add opt-in `SENTRY_DEBUG=1` console-log path** in the swallowed-error catch blocks. Surfaces silent heartbeat failures for operators.
15. **T06–T09 — top-of-file comment promoted to a multi-line WARNING block** addressing both gemini's permanent-degraded and codex's false-green concerns.
16. **T14 (runbook) — add "Security & Public Exposure" section** covering healthz info-disclosure mitigation (optional `?detail=true` query param to opt into per-check breakdown) and recommendation to consider `/healthz` vs `/readyz` split.

### Out-of-scope deferrals (documented in PLAN, not blocking)

- Per-cron-expression env-key support (codex's multi-cron concern). Deferred to a future minor — D11 documents the workaround (explicit `monitorSlug` arg).
- Shallow `/healthz` vs deep `/readyz` split (codex's k8s-convention suggestion). Defer to a future minor; this PR ships the single-endpoint version with the WARNING + fail-closed defaults.

---

## Next-step routing

The 5 HIGH issues are not "polish" — they are structural. The plan needs revision before T01 can be executed. Two paths:

1. **Fold revisions inline now** (`/gsd-plan-phase 22 --reviews` would do this autonomously, but the revision list is concrete enough that I can apply edits directly): edits 1–16 above land in CONTEXT.md + PLAN.md as commit 4 of the feature branch, then T01 proceeds.
2. **User reviews this REVIEWS.md first** and approves the revision list (or revises it) before I touch CONTEXT/PLAN.

Recommended: path 1, with the revision list shown above as the diff intent.
