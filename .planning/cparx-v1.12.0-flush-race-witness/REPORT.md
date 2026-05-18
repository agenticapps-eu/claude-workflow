# cparx Sentry-wiring witness — go-fly-http Flush-race discovery

**Date**: 2026-05-18
**Driver**: post-adoption Sentry-DSN smoke verification on factiv/cparx
**Repo**: `agenticapps-eu/cparx` PR #48 (chore/observability-adoption-v1.12.0)
**Verifier**: Claude Opus 4.7 (1M context), driven by user request "verify Sentry delivery"
**Witness commit (cparx)**: `7e71ef8b`
**Upstream fix commit (this repo)**: see PR opened from `fix/go-template-flush-race`

---

## Outcome

**FIX UPSTREAMED** as `add-observability` v0.3.2 → v0.3.3 (template +
contract tests + CONTRACT-VERIFICATION.md row). cparx pilot ships the
same fix downstream as the witness of this bug.

## Symptom

cparx adopter ran `/add-observability init` (v0.3.2), bumped the
workflow to v1.12.0 via the standard migration chain (0011+0012+0013),
wired SENTRY_DSN via `fly secrets set` and SERVICE_NAME/DEPLOY_ENV in
`fly.toml [env]`, then verified with the new `backend/cmd/sentry-smoke`
binary. Smoke test stdout was clean — every event logged as JSON via
slog, `sentry.Flush` returned "Buffer flushed successfully", no init
errors. **But the `cparx-backend` Sentry project showed 0 events in
its 14-day Issues feed.**

## Diagnosis

Two-step isolation:

1. **Direct-SDK control**: added `backend/cmd/sentry-direct/main.go`
   which calls `sentry.CaptureException` synchronously on the main
   goroutine — bypasses the wrapper entirely. Event `75f36db8…`
   arrived in Sentry within 30 seconds, surfaced as
   `CPARX-BACKEND-1` ("direct SDK smoke test — bypasses cparx wrapper").
   This proves: DSN is correct, network is open, Sentry project is
   reachable, sentry-go works.

2. **Wrapper-routed events**: re-running `cmd/sentry-smoke` (which
   calls `observability.CaptureError` → `safeFireAndForget` → goroutine
   → `sentry.CaptureException`) — the direct-SDK test event arrived,
   the wrapper-routed events still did not.

**Conclusion**: the bug is in the wrapper's emission layer, not the SDK
or DSN. The `safeFireAndForget` goroutine pattern races against
`sentry.Flush`:

- `sentry.Flush(d)` waits for sentry-go's *transport buffer* to drain.
  It does NOT know about goroutines that haven't yet *enqueued* into
  that buffer.
- The smoke test's call sequence: `CaptureError(...)` returns
  immediately (launches goroutine); `sentry.Flush(5s)` runs on the main
  goroutine. If the Go scheduler hasn't yet run the emission goroutine
  to its `hub.CaptureException(...)` call, the transport buffer is
  empty and Flush returns true with no events enqueued.
- The main goroutine then exits, the SDK is torn down, and the
  unscheduled emission goroutine never gets to send.

**Why long-running services don't see this**: per-request emission
goroutines have plenty of scheduler time between requests. The transport
worker keeps the buffer drained in steady-state. The race only bites
short-lived processes (CLI tools, tests, migrations, the cparx pilot's
smoke verifier).

## Fix

`emissionWG sync.WaitGroup` in the wrapper tracks every
`safeFireAndForget` goroutine (Add on launch, Done on completion). New
public `observability.Flush(timeout time.Duration) bool` waits on the
WaitGroup *before* calling `sentry.Flush`. When `sentryReady=false`
(test runs without a DSN), the SDK-Flush call is skipped and Flush
reports success once the WG drains.

Smoke test updated to call `observability.Flush` instead of
`sentry.Flush`; re-running on cparx delivered the event +
breadcrumb to Sentry where the prior wrapper-routed run silently
dropped them.

## Why TS templates don't need this fix

| Template | Drain mechanism | Why no Flush primitive needed |
|---|---|---|
| `ts-cloudflare-worker` | Worker runtime's `ctx.waitUntil` extends the request's lifetime to await all pending promises | Microtasks scheduled by `Promise.resolve().then(...)` run before the Worker isolate exits. |
| `ts-cloudflare-pages` | Inherits Worker behaviour (Pages Functions run on Workers runtime) | Same as above. |
| `ts-supabase-edge` | Deno Deploy isolate behaviour mirrors Worker — pending promises are awaited | Same. |
| `ts-react-vite` | Browser page is long-lived; SDK transport batches periodically | No "exit" event to drain at. |
| `go-fly-http` | **No equivalent runtime-await for short-lived processes** | Explicit `Flush(timeout)` is the only safe pattern. |

The TS templates retain their inline `Promise.resolve().then(fn)`
microtask-scheduling shape with no changes. The asymmetry is captured
in `add-observability/CONTRACT-VERIFICATION.md` ("Drain-before-flush
primitive" row).

## Test additions

Three new tests in
`add-observability/templates/go-fly-http/observability_test.go`:

- `TestFlushDrainsInFlightEmissions` — launches 50 emission goroutines
  with 10ms work each, asserts all 50 have run by the time Flush
  returns. Regression-guards the core WG-drain contract.
- `TestFlushReturnsTrueWithNoEmissions` — idle-wrapper baseline; Flush
  must return promptly with success on zero in-flight.
- `TestFlushTimesOutOnStuckEmission` — bounded-wait check; a stuck
  emission goroutine MUST cause Flush to return false within budget
  rather than blocking forever.

Verified via materialise-and-test against cparx's wrapper directory:
**15/15 tests pass** (12 prior + 3 new).

## Upstream propagation summary

| Repo | Change | Status |
|---|---|---|
| factiv/cparx PR #48 | Wrapper fix + sentry-smoke + sentry-direct + fly.toml env-stubs + downstream Flush-vs-sentryReady refinement | shipped (commits c6c80d39, 74b3072a, a1e6e5b1, 7e71ef8b) |
| agenticapps-eu/claude-workflow (this PR) | Template fix + 3 contract tests + CONTRACT-VERIFICATION.md parity row + CHANGELOG + skill v0.3.3 bump | THIS PR |
| agenticapps-eu/agenticapps-workflow-core | §10.5 Flush-primitive obligation addendum | sibling PR |

## References

- cparx witness: `factiv/cparx` PR #48 commits c6c80d39, 7e71ef8b
- Spec §10.5 (Operational requirements): `agenticapps-workflow-core/spec/10-observability.md`
- sentry-go transport: `github.com/getsentry/sentry-go` (worker / HTTPTransport)
- Prior cparx verification: `.planning/cparx-v1.10.0-adoption-verification/REPORT.md`
