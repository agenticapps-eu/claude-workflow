# 0032 — withCronMonitor generic narrowed for strict Env (cf-worker only)

**Status**: Accepted  **Date**: 2026-05-31  **Phase**: 25-fix-0019-engine-and-cron-wrappers

## Context

Phase 22's `withCronMonitor<E extends Record<string, unknown>>` (cf-worker) requires every consumer `Env` interface to either add `[key: string]: unknown` (loses index-access safety and TypeScript strictness benefits) or cast at every call site with `as Record<string, unknown>`. callbot's strict `Env { SENTRY_DSN: string; SERVICE_NAME: string; SUPABASE_URL: string; ... }` (no index signature) couldn't satisfy the constraint — callbot worked around it by applying `as Record<string, unknown>` at every call site in `apps/backend/src/index.ts`.

This workaround is fragile: it silences TypeScript's type narrowing on the env object, defeats the purpose of a named-field `Env` interface, and creates a maintenance burden (every new consumer must replicate the cast). Issue #56 Finding 3 surfaced the cast as a hand-applied local patch in callbot's `cron-monitor.ts:141-149`.

The root cause is in the wrapper itself: the dynamic env-key lookup `env[envKey]` (where `envKey` is a computed string) requires `E` to be indexable. But the wrapper only needs access to two specific fields — `SENTRY_DSN` and `SERVICE_NAME`. The indexable-env requirement was broader than necessary.

## Decision

Narrow `withCronMonitor<E extends Record<string, unknown>>` → `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` **on cf-worker + openrouter-monitor bundled ONLY**.

Inside the wrapper, the dynamic env-var lookup at the access site becomes `(env as unknown as Record<string, unknown>)[envKey]` — the wrapper internals know they are performing a dynamic lookup by design; callers no longer need to lie about their interface. The cast lives at the one place where it is semantically correct (the wrapper knows `envKey` is a valid key at runtime even if TypeScript doesn't know it statically). Apply symmetrically to the bundled openrouter-monitor copy at `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` (D-21 bundled cf-worker snapshot sync).

## Why cf-pages and supabase-edge are EXCLUDED

The `<E>` generic narrowing is structurally inapplicable on the other two TS stacks (verified by codex H-3 per-stack signature review):

- **cf-pages:** `withCronMonitor<R>(handler: () => Promise<R>, ...): (env: Record<string, unknown>) => Promise<R>`. The generic parameter `<R>` is the return type of the handler — not an env type. There is no `<E>` to narrow. The returned function still takes `env: Record<string, unknown>` in the cf-pages signature, which means the strict-Env problem on cf-pages is a different structural issue requiring a different fix (redesigning the pages return-wrapper signature). That is deferred as a Phase 26 carve-out.

- **supabase-edge:** No generics at all. The supabase-edge `withCronMonitor` reads `Deno.env.get()` directly — there is no `Env` parameter in the function signature. D-05 generic narrowing is structurally inapplicable; a Deno-shaped strict-env idiom would require its own design. Deferred as a Phase 26 carve-out.

## Alternatives Rejected

| Alternative | Reason Rejected |
|-------------|-----------------|
| **Keep loose `Record<string, unknown>`** (status quo) | Forces every `Env` interface to add `[key: string]: unknown`, losing index-access safety. Downstream consumers with strict `Env` (callbot, cparx, fxsa — any cf-worker project with a named-field `Env`) must cast at every call site. The cast is a symptom of a constraint that is broader than the wrapper actually needs. |
| **Require named-Env-only interface** (prescriptive approach) | Too prescriptive — would mean the wrapper exports a required `WrapperEnv` interface that all consumers must extend. Imposes a structural coupling where none was needed; most consumers already have their own `Env` type in their project. |
| **Add index-sig escape hatch + doc warning** (e.g., optional `[key: string]: unknown` in the constraint) | Half-fix: still doesn't help strict-mode consumers who deliberately omit the index signature. The doc warning would be ignored. |
| **Blanket-apply across all 3 TS stacks** | Structurally inapplicable on cf-pages (`<R>` return-type generic, not env generic) and supabase-edge (no generics, reads `Deno.env.get()` directly) per codex H-3 signature verification. Applying it mechanically would produce a no-op on those stacks or a type-error during compilation. |

## Consequences

- Strict-typed `Env` interfaces (callbot, cparx, fxsa — when on cf-worker) satisfy the `withCronMonitor` constraint without any consumer-side casts. The `as Record<string, unknown>` LOCAL-PATCH in callbot's `cron-monitor.ts:141-149` becomes unnecessary once Migration 0021 delivers the updated template.
- Generic narrowing is functionally non-breaking on cf-worker — every previously-conforming `E` (had index signature, almost certainly had `SENTRY_DSN` somewhere) still conforms to the new stricter constraint `{ SENTRY_DSN?: string; SERVICE_NAME?: string }`. The new constraint is a subset of `Record<string, unknown>` so there are no regressions.
- cf-pages and supabase-edge are UNCHANGED. The scope narrowing is explicit and documented.
- `add-observability` bumps 0.8.0 → 0.9.0 (minor, surface expansion). Test surface gains D-16 type-level fixture with strict-typed `CallbotEnv` on cf-worker only. D-18 migrated-wrapper SC5 fixture (`0021/04`) verifies SC5 acceptance end-to-end through the Migration 0021 path.
