# ADR-0034 — observability init() repeated-init determinism contract

**Status:** Accepted
**Date:** 2026-06-01
**Phase:** 26 — worker-template hardening (DEF-3)
**Supersedes:** none
**Superseded by:** none

## Context

Four TypeScript observability templates ship today (`ts-cloudflare-worker`,
`ts-cloudflare-pages`, `ts-supabase-edge`, and the byte-symmetric
`openrouter-monitor/src/observability/index.ts`). All four declare the
generated wrapper's runtime configuration as **module-level mutable state**:

```typescript
// ts-cloudflare-worker / ts-cloudflare-pages / openrouter-monitor
let serviceName: string = SERVICE_DEFAULT;
let deployEnv:   string = "dev";
let registry:    Registry | null = null;
```

```typescript
// ts-supabase-edge — same three plus two extras:
let initialized: boolean = false;
let serviceName: string = SERVICE_DEFAULT;
let deployEnv:   string = "dev";
/** @internal — test-only seam. Never set in production code. */
let _testEnv:    InitEnv | null = null;
let registry:    Registry | null = null;
```

These singletons are read by `logEvent`, `captureError`, and `startSpan` to
tag every emitted envelope with the active service/deploy-env metadata.
They are *mutated* by `init(env, ctx)` (cf-worker/cf-pages/openrouter) or
`init()` (supabase-edge), which the `withObservability` middleware runs
near the top of every handler invocation.

Phase 24's `/review` (DEF-3) flagged the contract under which this is safe
as **undocumented**. This ADR records the contract so future refactors do
not break it accidentally.

### Cloudflare runtime model (corrected after cross-AI review)

> **Cloudflare Workers reuse V8 isolates across requests for performance.**
> Module-level state (`let serviceName`, `let deployEnv`, `let registry`,
> plus supabase-edge's `let initialized` and `let _testEnv`) persists
> across requests within an isolate's lifetime. The `init(env, ctx)`
> function is called per request by the `withObservability` middleware, so
> the same module instance may see `init()` called many times — once per
> request that the isolate serves. The risk is NOT "forgetting that state
> persists across requests" (the framing rejected after cross-AI review).
> The risk IS "depending on stale state from a previous request when env
> values change between requests." The contract this ADR locks is:
> re-running `init()` with new env values yields a deterministic post-init
> state — the specific semantics differ per stack.

See Cloudflare's published runtime model:
- [Workers Best Practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/)
- [How Workers works](https://developers.cloudflare.com/workers/reference/how-workers-works/)

The relevant fact: Cloudflare REUSES Worker isolates across requests for
performance. Module-level state persists across requests within an
isolate's lifetime. `init()` may be called multiple times against the same
module instance, in sequence (Cloudflare's documented model serialises
request handling within an isolate).

### Two contract shapes across the four stacks

- **cf-worker / cf-pages / openrouter-monitor — last-call-wins.**
  `init()` is NOT guarded by an `initialized` flag. Each call mutates
  `serviceName`/`deployEnv`/`registry` to the new env's values. After
  `init(env_b, ctx)` following `init(env_a, ctx)`, the singletons reflect
  `env_b`. This is **deterministic** (output is a function of inputs) but
  **not idempotent** (state changes per call) — hence "repeated-init
  determinism", not "idempotency". An earlier draft used "idempotency"
  loosely; cross-AI review correctly pointed out that mutation-on-every-call
  is the OPPOSITE of idempotent. The contract is determinism, not idempotency.

- **supabase-edge — first-call-wins.**
  `init()` checks `if (initialized) return` as the first statement.
  Subsequent calls within the same isolate are no-ops, so the singletons
  stay at the first call's values until `_resetForTest()` clears
  `initialized`. Also deterministic; also framed as "repeated-init
  determinism" — but with the additional first-call-wins guard.

### Rejected prior framing (cross-AI review note)

> An earlier draft of this ADR (pre-cross-AI-review) framed Cloudflare's
> model as "module-level mutable state is reset between invocations / fresh
> module instance per invocation." Codex's adversarial review correctly
> identified that framing as inconsistent with Cloudflare's documented
> isolate-reuse behaviour (see Cloudflare Workers Best Practices and How
> Workers works, linked above). This ADR adopts the isolate-reuse-aware
> framing instead. The practical contract for DEF-3 closure is unchanged:
> deterministic post-init state; mutations on each call (cf-worker family)
> or no-op-after-first (supabase-edge). The CHANGE is in the JUSTIFICATION,
> not the contract — what we now SAY is correct about WHY the contract is
> safe.

The previously-rejected phrasing ("reset between invocations", "fresh
module instance per invocation") is explicitly named here so future
readers can see this ADR has been corrected against Cloudflare's
documented runtime model.

## Decision

1. **cf-worker / cf-pages / openrouter-monitor `init()` is intentionally
   NOT guarded by an `initialized` flag.** Last-call-wins semantics is the
   contract within the isolate lifetime. Each call to `init(env, ctx)`
   re-derives `serviceName`, `deployEnv`, and `registry` from the new env
   and overwrites the singletons.

2. **supabase-edge `init()` IS guarded by `let initialized` +
   `if (initialized) return`.** First-call-wins semantics on the Deno-edge
   runtime. Subsequent calls within the same isolate are no-ops. The
   `_resetForTest(env?)` helper clears `initialized` so tests can rerun
   `init()` with an injected env.

3. **D-02b — supabase-edge extra out-of-band state.** The invariant
   explicitly covers supabase-edge's additional module-level state:

   - `let initialized: boolean = false` — an idempotency-enforcing flag
     (NOT a request-scoped value). Persists across requests served by the
     same isolate; that is the design — it is the mechanism by which
     first-call-wins is enforced for the lifetime of the isolate.

   - `let _testEnv: InitEnv | null = null` — a test-only seam set via the
     existing `_resetForTest(env)` export. Production code never observes
     a non-null `_testEnv` because the production code path never calls
     `_resetForTest`. The JSDoc `@internal` marker documents this. The
     production `init()` reads `_testEnv ?? envFromDeno()`, so a null
     `_testEnv` (the production case) falls through to the Deno-env read.

   Both pieces of extra state are covered by the same isolate-reuse-aware
   contract that covers `serviceName`, `deployEnv`, and `registry`. This
   ADR names them explicitly so future readers understand the full scope
   of "module-level mutable state" the contract protects.

4. **D-02a test contract — repeated-init determinism, observed via
   `logEvent` envelope chain.** A test per stack asserts the contract:
   call `init()` twice within the same isolate, observe the singletons
   via the `logEvent` → `console.log` envelope chain, assert the
   post-second-call state matches the stack's contract:

   - cf-worker / cf-pages / openrouter-monitor → second envelope reflects
     `env_b` (last-call-wins).
   - supabase-edge → second envelope still reflects `env_a` (first-call-wins;
     second `init()` was a no-op).

   Tests observe via the EXISTING `logEvent` surface — they do NOT depend
   on Phase 26's new `buildSentryOptions(env)` helper. DEF-3's proof
   should not require DEF-1's helper; the singleton-state contract is
   testable independently through the existing logEvent envelope chain
   (which already reads `serviceName` and `deployEnv` and emits them to
   `console.log` in every emitted JSON event).

## Consequences

- **What this ADR locks.** The contract that future refactors
  (AsyncLocalStorage, per-request closure — both deferred per
  `.planning/phases/26-worker-template-hardening/26-CONTEXT.md` §Deferred
  Ideas) must honour or replace explicitly. Any change to the four `init`
  functions that breaks repeated-init determinism (last-call-wins for
  cf-worker family; first-call-wins for supabase-edge) requires either a
  superseding ADR or a deliberate decision to break the test.

- **When the contract is safe.** Cloudflare's documented runtime model
  serialises request handling within an isolate. Handlers are short
  (typically tens of milliseconds). The window between `init()` setting
  state and `logEvent` reading it is small and entirely within a single
  request's execution. Repeated `init()` calls across requests within a
  warm isolate produce deterministic state-after-call values; the
  state-after-call values are reflected immediately in subsequent reads.

- **When the contract becomes wrong.** If a future Cloudflare runtime
  change exposes concurrent isolate-level execution (current model:
  requests are SERIALISED within an isolate), OR if the wrappers are ported
  to a long-lived Node/Deno process with explicit concurrent requests, the
  deterministic-mutation semantics could race. Today this risk is LOW
  because handlers are short and Cloudflare's documented model serialises
  request handling within an isolate. If the runtime model changes, the
  contract requires the AsyncLocalStorage / per-request-closure refactor
  (deferred per CONTEXT §Deferred Ideas, ADR-0034 supersession candidate).

- **supabase-edge `_testEnv` JSDoc enforcement.** The `_testEnv` seam
  additionally requires that production code never call `_resetForTest`
  — the JSDoc `@internal` marker is the documentation that enforces this.
  Linters that understand `@internal` (TSDoc, api-extractor) will warn on
  production-code references; the symbol stays exported only because tests
  in the same package need it.

- **Residual risk today: LOW.**

## Rejected alternatives

| Alternative | Reason rejected |
|-------------|-----------------|
| **AsyncLocalStorage refactor** — use the existing `AsyncLocalStorage<InternalSpanContext>` shape (already imported at `lib-observability.ts:21,73`) and extend it to carry `serviceName`/`deployEnv`/`registry` per-request. | Over-engineering for a latent issue. The current invariant is safe; the ALS refactor is a Phase 27+ candidate per CONTEXT §Deferred Ideas. Documented in 26-CONTEXT. |
| **Per-request closure with explicit `InitContext` parameter** — pass `{serviceName, deployEnv, registry}` through the call chain instead of reading singletons. | Largest API surface change of the alternatives (every `logEvent`/`captureError`/`startSpan` caller updates its signature). Deferred per CONTEXT §Deferred Ideas. |
| **Defer entirely (no ADR, no test).** | Rejected — the contract is undocumented today, which itself is the bug DEF-3 names. Phase 24 `/review` explicitly called out the missing documentation; landing tests without the ADR leaves the contract unstated. |
| **Prior framing — "module state reset between invocations / fresh module instance per invocation".** | Rejected post-cross-AI-review (codex HIGH-1, 2026-06-01) as inconsistent with Cloudflare's documented isolate-reuse behaviour. The corrected framing is "isolate-reuse-aware deterministic mutation", not "fresh per invocation". See the Context section's "Rejected prior framing" note. |
| **Mislabel the contract as "idempotency" across all four stacks.** | Rejected post-cross-AI-review (codex MED-3, 2026-06-01). cf-worker/cf-pages/openrouter mutate state on every `init()` call — the OPPOSITE of idempotent. "Repeated-init determinism" is the accurate phrase across all four stacks; the supabase-edge first-call-wins variant happens to be idempotent within the isolate lifetime, but the cross-stack term is determinism. |

## Precedents

- **ADR-0029 — withCronMonitor SDK composition / Guarded Shape A**
  (Phase 23). Established the precedent of "leave the singleton pattern,
  document the contract" rather than refactoring. ADR-0034 follows the
  same shape: name the contract, write the test, leave the pattern.

- **ADR-0033 — withQueueMonitor + Migration 0021** (Phase 25). Phase 25's
  ADR voice and structure (Status/Date/Phase header → Context → Decision →
  Consequences → Rejected alternatives → Precedents). ADR-0034 mirrors
  this shape for consistency across the docs/decisions corpus.

## References

- Cloudflare Workers Best Practices —
  https://developers.cloudflare.com/workers/best-practices/workers-best-practices/
- How Workers works —
  https://developers.cloudflare.com/workers/reference/how-workers-works/
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts:60-117`
  (the singletons and `init()` function this ADR documents)
- `add-observability/templates/ts-supabase-edge/index.ts:84-172`
  (the supabase-edge variant with `initialized` + `_testEnv`)
- `add-observability/templates/openrouter-monitor/src/observability/index.ts`
  (byte-symmetric copy of `ts-cloudflare-worker/lib-observability.ts` per
  ADR-0033 D-21)
- `.planning/phases/26-worker-template-hardening/26-CONTEXT.md` §DEF-3,
  §Deferred Ideas
- `.planning/phases/26-worker-template-hardening/26-REVIEWS.md` §HIGH-1
  (the codex review correction this ADR incorporates)
