---
phase: 23
reviewers: [gemini, codex]
reviewed_at: 2026-05-29T15:28:27Z
plans_reviewed:
  - .planning/phases/23-observability-followups/PLAN.md
runtime_skipped: claude (running inside Claude Code per workflow rule)
unavailable: coderabbit, opencode (not installed)
plan_commit_at_review: aa227f0
prompt_size_kb: 168
---

# Cross-AI Plan Review — Phase 23

> **Reviewers:** Gemini (200K context, code-completion focus) + Codex/GPT-5.4 (high-reasoning effort, codebase-exploration mode read-only).
> **Plan-checker baseline:** PASSED on all 15 internal criteria; reviewers' job is to find what it missed.
> **Verdict spread:** Gemini → LOW risk; Codex → HIGH risk. The divergence itself is the headline finding — Codex performed live codebase exploration and surfaced runtime correctness issues the prompt-only Gemini review couldn't see.

---

## Gemini Review

**Verdict:** Proceed with minor revisions. LOW overall risk.

### Summary

This is an exceptionally thorough and well-architected plan that demonstrates a deep understanding of the project's context, conventions, and potential risks. It correctly identifies and manages downstream impacts, includes proactive security analysis, and follows a rigorous test-driven development discipline. The plan should proceed, with minor revisions to address a potential stability issue in the health-check timeout implementation and to clarify minor bookkeeping details.

### Strengths

- **Proactive Threat Modeling**: The inclusion of a detailed STRIDE analysis (T-23-01–T-23-07) is exemplary. It identifies and proposes mitigations for security concerns like information disclosure, DoS, and tampering *before* a single line of code is written.
- **Rigorous TDD Discipline**: The consistent use of RED/GREEN TDD cycles for new features and tests (e.g., Tasks 1.3, 1.4-1.7, 2.1-2.3, 3.1) provides a strong foundation for correctness and significantly de-risks the implementation, especially in a project without a CI pipeline.
- **Explicit Contract Management**: The plan meticulously identifies contracts from the previous phase (D6, D12, R02, R04), clearly articulating which are preserved and which are intentionally regressed as part of the F5 refactor. It even verifies the impact of these regressions (T-23-02).
- **Clarity on Downstream Impact**: The plan shows excellent awareness of downstream consumers (`fxsa`, `callbot`) and specifies multiple communication touchpoints (ADR-0029, CHANGELOG.md, commit messages) for the behavioral changes in F5, ensuring consumers are not surprised.

### Concerns

- **MEDIUM**: **Potential for unhandled promise rejections in F2 `healthz` snippets.**
  - **Where**: Tasks 1.4, 1.5, and 1.6 (`healthz-snippet.ts` implementation).
  - **What**: The proposed implementation for probe timeouts uses `Promise.race` with a promise that rejects when an `AbortSignal` fires. If the actual probe finishes first, the `Promise.race` settles, but the timeout promise remains pending. When the signal eventually aborts, its `reject` function is called, leading to an unhandled promise rejection.
  - **Why**: Unhandled promise rejections can crash Node.js processes and cause difficult-to-debug instability in other serverless runtimes. This is a correctness and stability issue that undermines the purpose of a health check.

- **LOW**: **Fragility of F4 `SKILL.md` drift test parser.**
  - **Where**: Task 1.3, implementation of `test-skill-md-version-matches-latest-migration-to-version`.
  - **What**: The test uses `grep ^version: ... | awk '{print $2}'` to parse the version from YAML frontmatter. As noted in D-04, this is a pragmatic but brittle choice. It would fail on common, valid YAML variations like indented keys, quoted values (`version: "0.7.0"`), or trailing comments.
  - **Why**: This introduces technical debt. A future, seemingly unrelated change to `SKILL.md` formatting could cause this test to fail incorrectly, blocking valid changes, or pass incorrectly, re-introducing the version drift it is meant to prevent.

- **LOW**: **Inconsistent test count accounting in G6.**
  - **Where**: `PLAN.md` `<verification>` block, "Test count target (G6)".
  - **What**: The plan estimates the template test count will increase from `228` to `231+`. However, the detailed TDD tasks imply a much larger increase: F2 adds four new test files, and F5 adds significant new test cases to three files. The `231+` figure appears to be a miscalculation.
  - **Why**: This is a minor bookkeeping error and does not affect functionality. However, in a plan of this exceptional quality and detail, the inconsistency stands out and may cause confusion during the final verification task (T5.4).

### Suggestions

1. **For Concern #1 (Unhandled Rejection)**: Change the timeout implementation in Tasks 1.4, 1.5, and 1.6 to a more robust pattern using `AbortController` + `setTimeout`/`clearTimeout`. This ensures the timeout is always cleaned up, preventing unhandled rejections.
   ```typescript
   const controller = new AbortController();
   const timeoutId = setTimeout(() => controller.abort(new DOMException("TimeoutError")), probeTimeoutMs);
   try {
     await env.SERVICE_BINDING.fetch(new Request("https://internal/healthz", { signal: controller.signal }));
     checks.serviceBinding = true;
   } catch (e) {
     checks.serviceBinding = (e instanceof DOMException && e.name === "TimeoutError") ? "timeout" : false;
   } finally {
     clearTimeout(timeoutId);
   }
   ```

2. **For Concern #2 (Brittle Parser)**: Add an explicit comment to the test implementation in Task 1.3 acknowledging the fragility and linking to the rationale in D-04.

3. **For Concern #3 (Test Count)**: In the `<verification>` block of `PLAN.md`, replace the specific test count with a qualitative goal — drop "228 → 231+" in favour of "template suite tests increased to cover F2 (healthz timeouts × 4) and F5 (cron-monitor parity × 3)".

### Risk Assessment

**LOW**. The plan is comprehensive and proactively mitigates most risks through its detailed TDD approach, threat model, and clear documentation strategy. The primary architectural change (F5) and its behavioral regression are well-understood and communicated. The identified concerns are minor and can be easily addressed with the suggested revisions. The largest external risk—the lack of CI—is known and effectively compensated for by the rigor of the plan itself.

---

## Codex Review (GPT-5.4, high reasoning, read-only codebase exploration)

**Verdict:** Proceed with revisions, not as-is. **HIGH** overall risk.

### Summary

Proceed with revisions, not as-is. The plan is strong on intent and documentation discipline, but it understates the real F5 runtime regression, over-assumes stack symmetry in F2/F5, and has a flawed F3 trap design. The biggest issue is that Shape A as written can stop the cron body from running at all when Sentry check-in setup throws, which is materially worse than the plan's current "SDK errors now bubble up" framing.

### Strengths

- The plan is unusually explicit about preserved versus regressed Phase 22 contracts, especially around D6/D12 and the R02/R04 regression. That is better than most internal execution plans.
- D-07 includes an audit step before changing 0019 semantics. That is the right instinct for migration-engine work where older engines are already carrying accidental contracts.
- The plan correctly recognizes that F5 needs downstream-facing release notes and an ADR, rather than hiding the behavior change inside a refactor.
- The migration work is fixture-driven rather than relying on shell-script inspection alone, which is the right testing posture for this repo's no-CI reality.

### Concerns

- **HIGH** — **Shape A skips cron execution when pre-callback check-in throws.**
  - **Where:** Task 2.1/2.2/2.3, D-08 Shape A. Source refs: `add-observability/templates/ts-cloudflare-worker/middleware.ts:78`, official `@sentry/core` `withMonitor` at `packages/core/src/exports.ts`.
  - **What:** The plan documents "SDK errors now propagate", but `withMonitor` sends the `in_progress` check-in *before* invoking the callback. If that pre-callback check-in throws, the handler **never runs**.
  - **Why:** This is not just a logging-path regression; it turns Sentry transport failures into **skipped cron executions**. On Pages, there is no outer observability wrapper at all, so the failure goes straight to the external caller. On Worker/Supabase, the outer wrapper will capture and rethrow, but the job body is still skipped.

- **MEDIUM** — **`withIsolationScope` legitimately removes handler-set Sentry scope state from outer capture.**
  - **Where:** D-08 "documented addition" and Task 5.3 CHANGELOG language. Source refs: `cron-monitor.ts:115` (Pages), `cron-monitor.ts:166` (Supabase).
  - **What:** The plan treats `withIsolationScope` as a non-breaking correctness improvement, but it can legitimately remove handler-set Sentry scope state from the outer error-capture path.
  - **Why:** If downstream cron code does `Sentry.setTag`, `setUser`, breadcrumbs, or other scope mutation inside the cron body and then throws, the outer capture path may no longer see that state after isolation unwinds. That is a real downstream behavior change, not just an internal cleanup.

- **MEDIUM** — **Supabase `@sentry/deno` deferred verification can strand Wave 2 halfway.**
  - **Where:** Task 2.3 and Task 5.4. Source refs: `add-observability/templates/ts-supabase-edge/cron-monitor.ts:53`, `cron-monitor.test.ts:17`, `run-template-tests.sh:499` (pins `@sentry/*` to `^8.0.0`).
  - **What:** The plan defers `@sentry/deno` export verification to execute-time, but the repo's Supabase stack uses a Deno-specific test seam today and the harness pins older major versions.
  - **Why:** Worker/Pages can switch to `vi.mock`; Supabase cannot mirror that literally because its current suite exists specifically to avoid module-boundary mocking under `deno test`. Wave 2 could land Worker + Pages green and Supabase red, with no clean rollback path mid-wave.

- **HIGH** — **F3 trap design is incorrect and broken in multiple ways.**
  - **Where:** Task 3.1 action block.
  - **What:** The proposed `trap 'cleanup' INT TERM EXIT` with a warning-emitting `cleanup` runs on successful exits too, and the plan never actually re-raises the signal. The path validation is also bypassable when `TMPDIR` is empty because `"$TMPDIR"/*` degenerates to `/*`.
  - **Why:** This changes normal engine behavior (cleanup runs on every successful exit, polluting output), makes the "re-raise" acceptance criterion false, and weakens the T-23-07 mitigation enough that `/etc/passwd`-style paths can slip through on hosts without `TMPDIR` set.

- **MEDIUM** — **F2 over-assumes stack symmetry; Pages and Go interfaces don't support D-03's contract.**
  - **Where:** Tasks 1.4-1.7. Source refs: `ts-cloudflare-pages/healthz-snippet.ts:24` (Pages onRequest), `go-fly-http/healthz_snippet.go:62` (Go upstream probe interface).
  - **What:** F2 is planned as if all four stacks share the same "handler + optional timeout override" surface. They do not. Pages exports a runtime-fixed `onRequest(ctx)`, so the proposed third-arg override is not a real operator-facing configuration path. Go's upstream probe interface is `Get(url)`, so the proposed timeout can only race the call, not actually cancel it.
  - **Why:** D-03 says timeout is caller-configurable across stacks, but the current plan only truly achieves that for some of them.

- **MEDIUM** — **D-07 "zero-side-effect" framing is inaccurate; dirty-root patches still emitted.**
  - **Where:** D-07, Task 4.1, Task 4.2. Source ref: `templates/.claude/scripts/migrate-0017-axiom-destination.sh:368`.
  - **What:** The plan says 0019 will "match 0017" and repeatedly calls the new default "zero-side-effect" or "truly atomic", but the actual reference engine 0017 already writes dirty-root patches on default refuse, and the proposed 0019 behavior still writes a dirty-root patch too.
  - **Why:** Operator-facing language is currently inaccurate. If the abort still writes `.patch` and `.gitignore` entries in dirty roots, that is not zero-side-effect. The audit step may catch this, but the plan text and changelog text are already wrong.

- **MEDIUM** — **Test verification machinery is not executable as written.**
  - **Where:** Task 1.3, Task 3.1, Task 5.4, and `<verification>`/`G6`.
  - **What:** `migrations/run-tests.sh` only dispatches numeric migration filters plus two hard-coded names today, so `test-skill-md-version-matches-latest-migration-to-version` and `test-sigterm-mid-apply-preserves-state` will **not run** unless the dispatcher is explicitly extended. Separately, the template harness has no global test-total summary, so the "228 → 231+" gate cannot be checked mechanically from its current output.
  - **Why:** This makes the RED/GREEN commands and final G6 gate partly aspirational rather than runnable. Tasks need to extend the harness machinery before the new tests can be exercised.

### Suggestions

1. **Guarded Shape A.** Change F5 from "plain `await Sentry.withMonitor(...)`" to a guarded shape: set a `handlerStarted` flag inside the callback; if `withMonitor` throws before the callback starts, fall back to running the handler unmonitored. Preserves most of Shape A while avoiding skipped cron bodies on pre-check-in failure.

2. **Pre-callback regression test per stack.** Add one explicit regression test per TS stack for the scenario "Sentry check-in setup throws before callback start". Decide deliberately whether the handler should still run. The current plan never tests the most dangerous behavioral change.

3. **Supabase Deno-friendly seam.** For Supabase, do not mirror the Worker/Pages mocking plan. Introduce a `_setWithMonitorForTest` seam or equivalent Deno-friendly indirection before touching implementation. Verify the actual pinned `@sentry/deno` major before starting any Wave 2 commits.

4. **Rewrite F3 trap.** Split into separate paths: `EXIT` should be silent/idempotent cleanup only; `INT`/`TERM` handlers should cleanup and then exit with signal-compatible status (`exit 130` / `exit 143`). Validate pause paths with `${TMPDIR:-/tmp}` plus an explicit relative fixture prefix, not raw `$TMPDIR`.

5. **F2 per-stack rework.** Pages should use either a local constant or an env/config field available through `context.env`; Go should either widen the upstream interface to a context-aware request surface or explicitly document that the timeout only caps handler latency, not the underlying outbound call.

6. **Reframe D-07.** Stop calling D-07 "zero-side-effect" unless dirty-root patch emission is removed too. If dirty-root patch emission stays, update the migration 0019 markdown and script usage/help text to say exactly that default refuse still writes dirty-root recovery artifacts but no longer touches clean roots.

7. **Move ADR-0029 earlier.** Context says the ADR is valuable before code lands; putting it in Wave 5 loses that benefit.

8. **GitNexus discipline.** Run `gitnexus_detect_changes()` before each commit or at least once per wave, not only in Task 5.4. The current plan violates the repo rule it cites.

9. **G6 gate replacement.** Replace the G6 numeric test-total gate with checks the harnesses can actually prove: presence of the new named tests in output plus overall exit status, or add explicit summary counters to the harness first.

### Risk Assessment

**HIGH** — the current plan can ship a materially stronger F5 failure mode than it documents, and the F3 trap design is incorrect enough to change normal engine behavior while still failing its own signal-handling goals.

---

## Consensus Summary

**Reviewer divergence is itself the headline:** Gemini (prompt-only, no codebase exploration) verdict LOW; Codex (read-only codebase exploration enabled, high reasoning) verdict HIGH. Codex's HIGH findings came from actually reading `cron-monitor.ts`, `middleware.ts`, `migrate-0017-axiom-destination.sh`, `run-template-tests.sh`, and the Sentry SDK source — none of which were inline in the prompt. The lesson: cross-AI review is not redundant; reviewers with different tool access surface different blind spots.

### Agreed Strengths

- Proactive threat modeling (T-23-01–T-23-07) is exemplary.
- TDD red/green discipline is rigorous and well-suited to the no-CI environment.
- Explicit contract preservation/regression management between Phase 22 and Phase 23 is unusually clear.
- Downstream consumer communication strategy (ADR + CHANGELOG + commit body) is robust.

### Agreed Concerns

- **F2 healthz timeout implementation has correctness bugs.** Gemini: unhandled promise rejection from `Promise.race` + `AbortSignal`. Codex: stack symmetry doesn't hold (Pages, Go can't actually implement D-03's caller-configurable contract as planned). Both flag F2 as MEDIUM in different dimensions. **The plan needs F2 per-stack rework, not a mirror-from-worker approach.**
- **G6 test count gate is wrong.** Gemini: arithmetic miscalculation. Codex: not executable as written (harness dispatcher doesn't support the new test names; template harness has no test-total counter). Both flag at LOW/MEDIUM severity. **The G6 gate needs replacement, and the harness machinery needs extension before the new tests can run.**

### Codex-only HIGH Concerns (blocking)

- **F5 Shape A skips cron execution on pre-callback check-in failure.** Sentry's `withMonitor` sends `in_progress` before the callback runs; if that throws, the handler doesn't execute. The plan documented "SDK errors propagate" but missed "cron skipped entirely". On Pages there's no outer wrapper to catch it. **Highest-severity finding of the review.** Mitigation: guarded Shape A (handler runs unmonitored if pre-check-in fails) + one explicit regression test per stack.
- **F3 trap design is broken.** `trap cleanup INT TERM EXIT` runs cleanup on success (polluting output); no signal re-raise (acceptance criterion is false); `TMPDIR` unset bypasses path validation (`/etc/passwd`-style paths slip through). Mitigation: split `EXIT` (silent idempotent) from `INT`/`TERM` (cleanup + signal-compatible exit codes 130/143); `${TMPDIR:-/tmp}` + explicit fixture-prefix path validation.

### Codex-only MEDIUM Concerns (warrant fix before execute)

- `withIsolationScope` removes handler-set scope state from outer capture (real downstream behavior change, not just internal cleanup) — document the actual semantic in CHANGELOG 0.7.0 + ADR-0029.
- Supabase `@sentry/deno` verification deferred to execute-time is a Wave 2 strand risk — verify the pinned major and introduce a `_setWithMonitorForTest` Deno-friendly seam before any Wave 2 commit lands.
- D-07 "zero-side-effect" / "truly atomic" framing is operator-facing inaccurate (dirty-root patches still emitted under the new default). Either remove dirty-root patches too, or reframe the language in CONTEXT + PLAN + CHANGELOG.

### Codex-only LOW-MEDIUM Concerns (worth incorporating)

- ADR-0029 in Wave 5 misses its pre-implementation value — move earlier (Wave 1 or pre-Wave-1).
- GitNexus discipline: run `gitnexus_detect_changes()` per-commit or per-wave, not just final-verification Task 5.4. Plan currently violates the rule it cites.

### Gemini-only Concerns (worth incorporating but lower priority)

- F4 SKILL.md drift test parser is fragile against valid YAML variations. Mitigation: explicit "this is intentionally minimal" comment in the test referencing D-04 — at minimum so future maintainers know it's a deliberate trade-off.

### Divergent Views

- **Risk verdict gap (LOW vs HIGH).** Resolved in favour of Codex's HIGH: Gemini's analysis was prompt-only and didn't have visibility into the actual Sentry SDK source or the Pages/Supabase implementation differences. Codex's higher-tooling-access verdict is more accurate.

---

## Recommended Next Step

`/gsd-plan-phase 23 --reviews` — replan to fold the consensus concerns + Codex-only HIGH findings into PLAN.md. Key revision targets the planner should address:

1. **Replace D-08 Shape A with Guarded Shape A** in Tasks 2.1/2.2/2.3 + add pre-callback regression test per stack. Update CONTEXT.md D-08 to reflect the guard. Update ADR-0029 plan accordingly.
2. **Rework Task 3.1 trap** — split EXIT (silent idempotent) from INT/TERM (cleanup + `exit $((128 + signal))`); fix path validation with `${TMPDIR:-/tmp}` + explicit fixture-prefix.
3. **F2 per-stack rework** — drop "mirror worker" assumption; per-stack implementation matching each runtime's actual probe interface. Either narrow D-03's "caller-configurable across stacks" contract or expand the Pages/Go interfaces.
4. **G6 gate replacement** — extend `migrations/run-tests.sh` dispatcher to support the new test names; replace numeric template test count with "named tests present + overall exit 0" check.
5. **D-07 framing fix** — either also remove dirty-root patch emission to honor "zero-side-effect", or rewrite CONTEXT/PLAN/CHANGELOG language to be operator-honest about what changes ("default no longer touches clean roots; dirty roots still get recovery artifacts").
6. **Supabase Deno seam** — Task 2.3 must verify `@sentry/deno` `withMonitor` export AND introduce the Deno-friendly test seam BEFORE any Wave 2 commit on supabase-edge. Escalate as CHECKPOINT if blocked.
7. **ADR-0029 reordering** — move from Wave 5 to Wave 1 (or pre-Wave-1) so the architectural rationale lands before code.
8. **GitNexus per-wave discipline** — add `gitnexus_detect_changes()` requirement to each wave-closing task, not just Task 5.4.
9. **Gemini F2 unhandled-rejection fix** — incorporate the `AbortController` + `setTimeout`/`clearTimeout` pattern in Tasks 1.4-1.7 (subsumed by per-stack rework but worth explicit call-out).

This is a substantive revision pass — expect ≥6 atomic plan edits + a CONTEXT.md amendment (D-08 → Guarded Shape A, D-07 framing). After revision: re-run `gsd-plan-checker` → if PASSED, optionally re-run `/gsd-review --phase 23 --all` to confirm HIGH concerns landed, then proceed to `/gsd-execute-phase 23`.
