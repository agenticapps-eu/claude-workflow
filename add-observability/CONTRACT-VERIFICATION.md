# Contract verification — TS & Go templates vs. spec §10 v0.2.1

Side-by-side check that both wrappers expose the same semantic contract.

> **Updated 2026-05-10 (v0.2.1) — five stacks shipped**
>
> All stack templates declare `path_root` (spec §10.7.1) and ship with contract test fixtures (spec §10.7 revised).
>
> | Stack | Wrapper | Tests | Runner | Result |
> |---|---|---|---|---|
> | ts-cloudflare-worker | own | 15 | vitest + jsdom | 15/15 pass |
> | ts-cloudflare-pages  | inherits worker | (inherited) | n/a | static review |
> | ts-react-vite        | own (browser-flavored) | 22 | vitest + jsdom | 22/22 pass + tsc clean |
> | ts-supabase-edge     | own (Deno-flavored) | 12 | deno test | 12/12 pass |
> | go-fly-http          | own | 12 | go test | 12/12 pass |
>
> **Total: 61 contract tests passing across 4 runtimes** (Cloudflare Worker isolate, browser/jsdom, Deno, Go).
>
> Latent bug caught by test fixtures: Go template imported `crypto/rand` and `math/rand/v2` both as `rand` (compile-time conflict). Fixed by aliasing as `mrand "math/rand/v2"`. The cparx pilot masked this because I aliased manually when materializing; the test fixture caught it on the v0.2.1 verification run — exactly the failure mode the test fixtures exist to prevent.

| §10 requirement | TS (ts-cloudflare-worker) | Go (go-fly-http) |
|---|---|---|
| **§10.1 logEvent**                      | `logEvent(envelope: Envelope): void` | `LogEvent(ctx context.Context, env Envelope)` |
| **§10.1 captureError**                  | `captureError(err: unknown, envelope: Envelope): void` | `CaptureError(ctx context.Context, err error, env Envelope)` |
| **§10.1 startSpan**                     | `startSpan(name, attrs) → Span` | `StartSpan(ctx, name, attrs) → (ctx, *Span)` |
| **§10.1 wrapper-only (no vendor SDK in app code)** | enforced by import discipline + scan checklist | enforced by import discipline + scan checklist |
| **§10.2 trace_id field**                | filled in `emit()` from active context | filled in `emit()` from active context |
| **§10.2 span_id field**                 | ditto | ditto |
| **§10.2 service field**                 | from `serviceName` (init-resolved) | from `serviceName` (init-resolved) |
| **§10.2 env field**                     | from `deployEnv` (init-resolved) | from `deployEnv` (init-resolved) |
| **§10.2 event field**                   | from envelope arg | from envelope arg |
| **§10.2 severity field**                | `Severity` union, default `info` | `Severity` const, default `SeverityInfo` |
| **§10.2 attrs field**                   | `Record<string, unknown>` | `map[string]any` |
| **§10.3 traceparent generate at edge**  | `newRootContext()` in middleware when no inbound header | `NewRootContext()` in middleware when no inbound header |
| **§10.3 traceparent propagate inbound** | `parseTraceparent()` in middleware; `runWithContext` binds it | `ParseTraceparent()` in middleware; `WithContext` binds it |
| **§10.3 traceparent propagate outbound**| `instrumentedFetch` / `tracedFetch` | `TracingTransport` |
| **§10.3 no vendor-proprietary primary header** | only `traceparent` set; Sentry's own headers MAY be added by SDK | only `traceparent` set; Sentry's own headers MAY be added by SDK |
| **§10.4 #1 handler entry span**         | `withObservability` opens root span via `runWithContext` | `Middleware` opens root span via `StartSpan` |
| **§10.4 #2 outbound child span**        | scan-flagged; `tracedFetch` propagates trace, app code wraps in `startSpan` | scan-flagged; `TracingTransport` propagates trace, app code wraps in `StartSpan` |
| **§10.4 #3 caught-error captureError**  | scan-flagged at try/catch sites; middleware catches unhandled | scan-flagged at `if err != nil` sites; middleware recovers panics |
| **§10.4 #4 business-event logEvent**    | scan-flagged at heuristic sites (`*Created`, `pay*`, `signup*`) | scan-flagged at heuristic sites |
| **§10.5 non-blocking emission**         | `safeFireAndForget` via `ctx.waitUntil` | `safeFireAndForget` via goroutine |
| **§10.5 fail-safe behavior**            | inner try/catch in `safeFireAndForget`; never throws | `recover()` in goroutine; logs warning, never panics caller |
| **§10.5 PII discipline**                | `redactObject` + `REDACTED_KEYS` from policy.md | `redactObject` + `redactedKeys` from policy.md |
| **§10.5 sampling: error/fatal not sampled** | `if (severity === "debug" && Math.random() > rate) return` — only debug sampled | `if sev == SeverityDebug && rand.Float64() > rate` — only debug sampled |
| **§10.6 destination independence**      | only `@sentry/cloudflare` import is in `index.ts`; swap to OTel/Axiom by replacing internal `init()` + `safeFireAndForget` blocks | only `getsentry/sentry-go` import is in `observability.go`; swap by replacing `Init()` + `safeFireAndForget` blocks |
| **§10.7 generator obligation**          | (covered by skill, not by templates) | (covered by skill, not by templates) |
| **§10.8 project metadata**              | written into `<instruction-file>` by skill init | written into `<instruction-file>` by skill init |

## Symmetric features (parity check)

| Feature | TS | Go | Match? |
|---|---|---|---|
| Inbound `traceparent` parser | ✓ | ✓ | ✓ |
| Outbound `traceparent` formatter | ✓ | ✓ | ✓ |
| Root context generator | ✓ | ✓ | ✓ |
| Active context lookup | `getActiveContext()` | `FromContext(ctx)` | ✓ (idiomatic per language) |
| Span object with setAttribute / setStatus / end | ✓ | ✓ | ✓ |
| Idempotent span end | `if (ended) return` | `if s.ended { return }` | ✓ |
| Console / stdout JSON mirror | `console.log/warn/error(JSON.stringify(event))` | `slog.Info/Warn/Error(json.Marshal(event))` | ✓ |
| Sentry breadcrumb on every event | ✓ | ✓ | ✓ |
| Init idempotency | `if (initialized) return` | `sync.Once` | ✓ |
| Service name resolution from env | `env.{{ENV_VAR_SERVICE}}` | `os.Getenv("{{ENV_VAR_SERVICE}}")` | ✓ |

## Deliberate divergences

| Divergence | TS | Go | Reason |
|---|---|---|---|
| Span context propagation | `AsyncLocalStorage.run()` (callback-scoped) | `context.Context` (explicit param) | Each language's idiomatic mechanism. Both satisfy §10.3. |
| `startSpan` returns | `Span` only | `(ctx, *Span)` | Go callers need the child context to propagate; TS callers get it implicitly via ALS. |
| Outbound interceptor | `instrumentedFetch(originalFetch)` returning a wrapped fetch | `TracingTransport` http.RoundTripper | Each language's HTTP-client extension point. |
| Error type | `unknown` (TS) | `error` (Go) | Each language's error idiom. |

## Known gaps (deferred to v0.3.0)

- **TS nested spans don't mutate active context.** AsyncLocalStorage.run requires a callback; the spec's `startSpan() → span` API can't update the active span without either `enterWith` (leak risk) or restructuring as `withSpan(name, attrs, fn)`. v0.2.0 documents this in the wrapper comment; outbound calls inside a child span use the parent's span_id. Acceptable because the trace_id is correct — only the immediate parent_span_id is approximated.
- **No queue handler middleware in TS** — commented-out skeleton present, uncomment when fx-signals adds queues. (Go side has no queue analog yet.)
- **No metrics primitive.** Counters / histograms / gauges are not in §10.1. If a project needs them, application code can call `logEvent({ event: "metric.foo", attrs: { value, kind: "counter" } })` and aggregate downstream. v0.3.0 may add a `recordMetric` if usage justifies it.
- **No log levels finer than 5 severities.** `trace` severity below `debug` is not in the spec. Add via spec amendment if a real need surfaces.

## Sanity-check commands (run after generator output is in a real project)

For a TS project:

```bash
# 1. Templates compile after parameter substitution
tsc --noEmit src/lib/observability/index.ts src/lib/observability/middleware.ts

# 2. Required exports present
grep -q 'export function logEvent\b'   src/lib/observability/index.ts
grep -q 'export function captureError\b' src/lib/observability/index.ts
grep -q 'export function startSpan\b'  src/lib/observability/index.ts

# 3. No direct Sentry imports in app code (only in lib/observability/)
! grep -rE "from ['\"]@sentry/" --exclude-dir=node_modules --exclude-dir=lib src/
```

For a Go project:

```bash
# 1. Builds clean after parameter substitution
go build ./internal/observability/...

# 2. Required exports present
grep -q 'func LogEvent\b'      internal/observability/observability.go
grep -q 'func CaptureError\b'  internal/observability/observability.go
grep -q 'func StartSpan\b'     internal/observability/observability.go

# 3. No direct Sentry imports in app code (only in internal/observability/)
! grep -rE '"github.com/getsentry/sentry-go"' --include='*.go' \
    --exclude-dir=internal/observability \
    --exclude-dir=vendor .
```

These commands become part of the scan validator in task #4 — they ARE
the high-confidence conformance checks.

## Result

Both templates satisfy §10.1–10.6 with idiomatic per-language realizations of the same contract. Section 10.7 (generator obligation, including 10.7.1 module-root resolution added v0.2.1) is satisfied by the skill scaffolding (task #2 spec) plus the templates' `path_root` declaration. Section 10.8 (project metadata) is written by the skill's init subcommand (task #3 follow-up — wiring not yet implemented in the skill itself).

**Verdict (v0.2.1)**: templates verified end-to-end via materialize-and-test. 27 tests pass across both stacks. Task #3 closes for TS Cloudflare Worker + Go Fly HTTP. Three follow-ups remain for the other stack templates (#8, #9, #10), and the cparx pilot (#6) found six gaps that are now addressed:

| Gap | Status | How addressed |
|---|---|---|
| G1 — module-root path resolution | **fixed** | Spec §10.7.1; `path_root` field in both meta.yaml files; skill spec documents resolution algorithm. |
| G2 — transport-composition detector | **fixed** (in spec) | Skill spec C2 entry codifies the composition pattern. Detector implementation remains task #4 work. |
| G3 — detached goroutines outside request span | deferred to v0.3.0 | Documented in spec follow-ups. |
| G4 — fail-safe order with framework recoverer | **fixed** (clarification) | Spec §10.5 note added. |
| G5 — RequestID coexistence | already documented | No spec change needed; stack README templates explain. |
| G6 — wrapper unit tests in templates | **fixed** | Both stacks ship `*_test.{ts,go}` contract tests. Skill spec directory layout updated. |

---

## v0.3.0 §10.9 enforcement (phase 14, scaffolder 1.10.0)

Side-by-side check that the skill at v0.3.0 satisfies every MUST in
spec §10.9.1-3 (conformance enforcement, added v0.3.0).

| §10.9 obligation | Where it lands | Verified by |
|---|---|---|
| §10.9.1 `--since-commit` flag accepted | `scan/SCAN.md` Inputs + Phase 1.5 | phase 14 T1 grep checks; fixture 01 idempotency assertion |
| §10.9.1 delta scope = `git diff --name-only <ref>...HEAD` (triple-dot) | `scan/SCAN.md` Phase 1.5 step 2.d + Important Rules | `grep -q 'triple-dot' scan/SCAN.md` |
| §10.9.1 confidence/output rules unchanged | `scan/SCAN.md` Phase 3 (walk) preserves v0.2.x logic; only the input scope changes | structural review |
| §10.9.1 machine-readable summary emitted unconditionally | `scan/SCAN.md` Phase 8 — runs even on empty `files_walked` | `grep -q "Empty deltas still emit"` |
| §10.9.2 canonical path `.observability/baseline.json` | `scan/SCAN.md` Phase 7 atomic-write; `scan-apply/APPLY.md` Phase 6b | path hardcoded in both |
| §10.9.2 schema byte-exact to spec example | `scan/baseline-template.json` + sibling `.note.md` | `migrations/run-tests.sh 0011` fixture 02 jq schema check (`scanned_commit ~ ^[a-f0-9]{40}$`, `policy_hash ~ ^sha256:[a-f0-9]{64}$`) |
| §10.9.2 `module_roots` sorted (stack, path) | `scan/SCAN.md` Phase 7 step 2.MODULE_ROOTS | sort directive in procedure |
| §10.9.2 baseline regen on scan-apply success | `scan-apply/APPLY.md` Phase 6b | structural review (Phase 6b runs iff applied_count > 0) |
| §10.9.2 `--update-baseline` manual override | `scan/SCAN.md` Inputs + Phase 7 | `grep -q 'update-baseline'` |
| §10.9.3 reference CI workflow shipped | `ci/observability.yml` (SHA-pinned actions) + `ci/README.md` | `python3 -c yaml.safe_load`; `grep -E '@[a-f0-9]{40}'` |
| §10.9.3 (1) delta scan on every PR | `ci/observability.yml` step `if: pull_request` | inline in workflow |
| §10.9.3 (2) compare delta against base baseline | `ci/observability.yml` `Compare delta vs baseline` step | `git show ${BASE_SHA}:.observability/baseline.json` |
| §10.9.3 (3) fail PR if count increases | `ci/observability.yml` `if [ "$D" -gt 0 ]; then exit 1` | inline |
| §10.9.3 (4) surface findings as PR comment | `ci/observability.yml` `marocchino/sticky-pull-request-comment@0ea0beb...` | SHA-pinned action |
| §10.9.3 no silent opt-out | `ci/observability.yml` "Read base baseline" emits `::warning::enforcement disabled` if baseline missing/empty | `grep -q 'enforcement disabled'` |
| §10.8 enforcement sub-block | migration 0011 Step 3 patches CLAUDE.md | fixture 02 verify.sh |

**Phase 14 multi-AI review verdict**: BLOCK (codex Q1) → REQUEST-CHANGES
(gemini, Claude self) → APPROVE after 21-item PLAN.md v2 revision pass.
See `.planning/phases/14-spec-10-9-enforcement/14-REVIEWS.md`.

**Verdict (v0.3.0)**: skill fully implements §10.9.1-3. §10.9.4
(pre-commit hook, MAY) deferred to v1.11.0 per non-goals. CI workflow
ships SHA-pinned and threat-modelled but depends on `claude` in CI —
documented limitation; v1.11.0 ships a standalone Node scanner port as
the workaround.
