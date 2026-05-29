# 0029 — cron-monitor SDK composition (Guarded Shape A)

**Status**: Accepted  **Date**: 2026-05-29  **Phase**: 23-observability-followups
**Supersedes**: none (extends 0028's cron-monitor conventions)
**Revision**: Amended post-multi-AI-review on 2026-05-29 from original Shape A to
Guarded Shape A per `23-REVIEWS.md` codex HIGH-1.

## Context

Phase 22 reinvented Sentry's in_progress→ok/error lifecycle (duration tracking,
thenable handling) around a 3-source slug-resolution wrapper. `Sentry.withMonitor<T>(slug, callback, monitorConfig?): T`
ships in `@sentry/core` and is re-exported by `@sentry/cloudflare` + `@sentry/deno`.
Post-PR-#53 the user requested a refactor to compose with the SDK helper rather than
reinvent the lifecycle. Six honest shapes considered (5 rejected).

The three TypeScript `withCronMonitor` implementations in `ts-cloudflare-worker`,
`ts-cloudflare-pages`, and `ts-supabase-edge` each contain ~50 LOC of hand-rolled
in_progress → ok/error lifecycle that duplicates what `Sentry.withMonitor` provides.
The question is: which composition shape correctly exposes the SDK primitive while
preserving Phase 22's behavioral contracts?

## Decision

**Guarded Shape A** — compose `Sentry.withMonitor` underneath our existing outer
wrapper, with a `handlerStarted` flag inside the callback. If `Sentry.withMonitor`
throws BEFORE the callback runs (e.g., transport failure on `in_progress` check-in),
fall back to running the handler unmonitored. If it throws AFTER the callback
completed (post-handler transport failure), let the error propagate.

Canonical code block (binding for executors — also in CONTEXT.md D-08):

```typescript
let handlerStarted = false;
try {
  await Sentry.withMonitor(
    monitorSlug,
    () => {
      handlerStarted = true;
      return handler(controller, env, ctx);
    },
    monitorConfig,
  );
} catch (err) {
  if (!handlerStarted) {
    // Sentry transport failed before handler ran — fall back to unmonitored.
    await handler(controller, env, ctx);
    return;
  }
  throw err; // handler-thrown OR post-callback errors propagate as before
}
```

## Alternatives Rejected

| Shape | Description | Why rejected |
|-------|-------------|--------------|
| **Original Shape A (unguarded)** | `await Sentry.withMonitor(slug, () => handler(...), monitorConfig);` with no handlerStarted flag | **Codex HIGH-1 empirical finding (`23-REVIEWS.md`):** `withMonitor` sends `in_progress` check-in BEFORE invoking the callback (verified at `@sentry/core/src/exports.ts`). Transport failure at that moment causes the **cron handler to be SKIPPED ENTIRELY**, not just the heartbeat logging. On Cloudflare Pages there is no outer observability wrapper at all, so this failure goes straight to the external caller. On Worker/Supabase the outer wrapper catches the throw but the job body is still skipped. This regression is materially worse than the original PLAN's "SDK errors now bubble up" framing. Guarded variant restores the "cron always runs" contract. |
| **Shape B (Drop-in replacement)** | `withCronMonitor(handler, config?) = (c, e, ctx) => Sentry.withMonitor(resolveSlug(...), () => handler(c, e, ctx), buildMonitorConfig(config))` | Drops R02 fail-safe (Sentry logs warning on no-DSN). Drops R04 swallow. Loses D6's silent-on-no-DSN behaviour. Also subject to original-Shape-A skipped-cron regression. |
| **Shape C (Deprecate + parallel `withCronMonitorV2`)** | Keep v0.6.0 wrapper with `@deprecated`; add `withCronMonitorV2` as Shape A | +50 LOC per file. Zero downstream risk but compounds future maintenance — two wrappers to keep in sync. |
| **Shape D (Compose with SDK-throw firewall via stack inspection)** | Shape A + try/catch wrapper that catches errors whose stack frame includes `captureCheckIn` | Restores R02/R04 at significant complexity cost. Brittle stack-frame inspection. High test surface. Subsumed by Guarded Shape A which achieves the cron-always-runs goal more reliably. |
| **Shape F (No refactor — port only `duration` tracking pattern)** | +8 LOC per file. All Phase 22 contracts preserved. | Loses strategic value of using upstream's primitive. User's "baked in" directive interpreted as a genuine refactor. |

## Consequences

**Preserved contracts (Phase 22):** D6 (3-source slug resolution), R02 fail-safe
no-DSN (preserved at the if-isConfigured guard), D11 (multi-cron explicit-slug),
D12 (monitorConfig 2nd-arg forwarding shape), **AND the "cron always runs"
guarantee** that original Shape A regressed.

**Documented regression (NARROWED vs original Shape A):** R02/R04 SDK-error swallow
drops only for POST-callback errors — i.e., errors from the `ok`/`error` check-ins
after the handler completed. PRE-callback errors no longer skip the cron (Guarded
fallback runs handler unmonitored). POST-callback errors propagate to the outer
`withObservabilityScheduled` capture path. Operators see SDK transport failures in
their normal error-capture path instead of silent swallow ONLY when the handler
already completed successfully. `SENTRY_DEBUG=1` is no longer the surfacing mechanism
for SDK errors.

**Documented addition (HONEST SEMANTIC per codex MEDIUM):** `withIsolationScope`
wrapping. Each cron run gets its own Sentry scope. This is NOT "purely non-breaking
correctness improvement" as original PLAN claimed — handler-set scope state (e.g.,
`Sentry.setTag`, `Sentry.setUser`, breadcrumbs set inside the cron body) may NOT be
visible to outer error-capture handlers after isolation unwinds. Downstream consumers
relying on cron-body scope mutations becoming visible to outer error handlers will see
different behaviour. Tags/breadcrumbs/user-context still no longer leak BETWEEN
consecutive cron invocations (the original benefit).

**Downstream impact:** fxsa and callbot pull `add-observability 0.7.0` → see the
narrowed regression + honest isolation-scope addition. CHANGELOG.md 0.7.0 calls both
out explicitly. No code change required downstream unless they relied on the documented
behaviours.

**Go stack unchanged.** `sentry-go` ships no `WithMonitor` equivalent
(Context7-verified). The Go `WithCronMonitor` impl IS the cross-stack parity. See D-09
/ `cron_monitor.go` package-doc note.

## Empirical Evidence Supporting Guarded Variant

From `23-REVIEWS.md` §Codex HIGH-1: read-only codebase exploration verified
`@sentry/core` `withMonitor` at `packages/core/src/exports.ts` sends `in_progress`
check-in via `captureCheckIn` BEFORE invoking the callback. The Cloudflare Pages
template (`add-observability/templates/ts-cloudflare-pages/cron-monitor.ts:115`) has
NO outer observability wrapper — a `captureCheckIn` failure would propagate directly
to the external caller, with the cron body never executing. This empirical finding
(not visible to prompt-only Gemini review) drove the Guarded amendment.

## Links

- CONTEXT (amended): `.planning/phases/23-observability-followups/CONTEXT.md` §D-08 (Guarded canonical block)
- Reviews: `.planning/phases/23-observability-followups/23-REVIEWS.md` §Codex HIGH-1
- Discussion log: `.planning/phases/23-observability-followups/DISCUSSION-LOG.md` §"Post-review revision — D-08 Guarded Shape A"
- Implementation: this phase's Task 2.1 / 2.2 / 2.3 GREEN commits
- Phase 22 contracts: `.planning/phases/22-sentry-crons-healthz/PLAN.md` §R02 §R04, `…/CONTEXT.md` §D6 §D11 §D12
- SDK reference: `@sentry/cloudflare` re-export of `@sentry/core` `withMonitor<T>` in `packages/core/src/exports.ts`
