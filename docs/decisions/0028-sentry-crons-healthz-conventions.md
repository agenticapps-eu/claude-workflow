# ADR-0028: Sentry Crons heartbeats + `/healthz` as host-discretion (not spec mandate)

**Status**: Accepted  **Date**: 2026-05-29  **Workflow version**: 1.18.0

## Context

`add-observability` v0.5.1 ships per-stack wrappers (`withObservability`,
`withObservabilityScheduled`, plus the Sentry SDK's own `withSentry` wrap at the
entry file) whose visibility ends at request boundary. Two production failure
modes are invisible to the in-request capture path:

1. **Scheduled handler didn't fire.** A `ScheduledHandler` that never gets
   invoked (Cloudflare cron trigger misconfigured, `pg_cron` paused, fly
   machine down) emits zero events through `withObservabilityScheduled` —
   there is no error to capture if the handler never ran.
2. **Platform up but routing failed / process crashed before user code.** A
   Worker that is deployed but routing-failed, a Supabase Edge function that
   502s before reaching user code, a Go service that crashed and did not
   restart — `captureError` cannot fire from code that never executes.

Sentry's product surface already covers both gaps: **Crons** (`captureCheckIn`
heartbeats) for "did the scheduled handler actually run?" and **Uptime** (HTTP
probes against `/healthz`) for "is the platform up?". The open question is
whether `add-observability` should *mandate* these patterns across all
destinations under spec §10 — i.e. add a new sub-section like §10.10
"Out-of-process observability" — or ship them as host-discretion conventions
under the existing §10.6 (destination independence) and §10.7 (generator
obligation).

## Decision

**Host-discretion under §10.6/§10.7. No spec amendment.**

Ship `withCronMonitor` (TS) / `WithCronMonitor` (Go) + `healthz-snippet.{ts,go}`
+ `add-observability/uptime-setup-runbook.md` as **optional opt-in** sibling
files in the per-stack templates. The generator obligation under §10.7 is
satisfied because the affordances exist and are trivial to adopt; the spec
itself does not require them.

Concretely:

- `withCronMonitor` ships as a NEW sibling export in `cron-monitor.{ts,go}`
  per stack — existing wrapper files (`middleware.ts`, `_middleware.ts`,
  `middleware.go`, `observability.go`, `index.ts`, `destinations/*`) are NOT
  modified, preserving the v0.5.1 byte-identical contract.
- `healthz-snippet.{ts,go}` ships as a copy-only template per stack, NOT
  auto-mounted by `init`. Operator decides where to mount.
- `uptime-setup-runbook.md` is the binding contract between the code-side
  emission (slug, monitor config) and the Sentry UI-side configuration
  (monitor schedule, alerts, Uptime probes).
- Project `policy.md` records the operator's inventory of cron monitors +
  uptime probes — the missing link between code, UI config, and project
  documentation.

## Alternatives rejected

Cross-references to phase planning live in
[`.planning/phases/22-sentry-crons-healthz/22-REVIEWS.md`](../../.planning/phases/22-sentry-crons-healthz/22-REVIEWS.md)
and [`CONTEXT.md`](../../.planning/phases/22-sentry-crons-healthz/CONTEXT.md).

- **Spec mandate as §10.10 "Out-of-process observability".** Rejected: would
  multiply adapter surface across every destination (Sentry, Axiom, future
  Datadog/Honeycomb/etc.) since each destination would need a checkin/probe
  contract. Sentry Crons UI is the value here, not destination-mirroring;
  mandating it across destinations adds adapter complexity without
  proportional operator value. Revisit if downstream evidence shows projects
  routinely ship without heartbeating despite the affordance.
- **Mirror checkins to the Axiom destination** (CONTEXT D2 + Open Q1).
  Rejected: doubles signal surface without obvious operator value; Sentry
  Crons UI is what surfaces missed-checkin alerts. Axiom path stays log-only.
- **Embed commit SHA in the monitor slug** (CONTEXT D3 + Open Q2). Rejected:
  Sentry treats slugs as long-lived monitor identifiers; cycling the slug per
  deploy creates one monitor per commit and silently breaks missed-checkin
  alert continuity (Sentry will not fire alerts on a monitor that never
  received a single checkin). Commit SHA goes to Sentry's
  `environment`/`release` context instead.
- **Route `/healthz` through `withObservability`** (CONTEXT D4 + Open Q3).
  Rejected: Uptime probes hit `/healthz` every 1–15 min × N regions, which
  crowds Sentry's transaction view and obscures real traffic patterns.
  `/healthz` is observable via Sentry Uptime alone; the snippet uses raw
  `Response` / `http.HandlerFunc`.
- **Config option on `withObservabilityScheduled` instead of a separate
  wrapper** (CONTEXT D1). Rejected: keeps the scheduled wrapper API surface
  frozen per the v0.5.x compatibility constraint and lets future cron-only
  knobs (`maxRuntimeSeconds`, `schedule` overrides) land without churning
  the general scheduled wrapper.
- **Per-cron-expression env keys** (e.g. `SENTRY_CRON_MONITOR_SLUG_SCHEDULED_15MIN`,
  CONTEXT D11 + N6). Rejected for v1.18.0: multi-cron handlers must pass
  `monitorSlug` explicitly; per-cron-expression env-key disambiguation is
  deferred to a future minor. Runbook documents the workaround.

## Consequences

- Additive migration shape. Migration 0019 (1.17.0 → 1.18.0) adopts the new
  exports on existing projects; refuses on hand-modified wrappers via the
  same content-hash check 0017 settled on. Projects that don't need cron
  monitoring or uptime probes can skip the migration with no behavioural
  impact.
- Per-project adoption is opt-in. The operator decides which scheduled
  handlers wrap with `withCronMonitor` and where to mount the healthz
  snippet. The runbook + `policy.md` "Out-of-process monitors" section
  template are the discoverable surface that makes adoption viable.
- The runbook is the **binding contract** between code-side emission (slug,
  monitor config forwarded on `in_progress` checkin) and UI-side
  configuration (Sentry monitor settings, alert routing, Uptime probe
  schedule). Without the runbook, the slug-resolution precedence and the
  `monitorConfig` upsert behavior are invisible to operators.
- `policy.md` records the inventory of cron monitors + uptime probes per
  project — the audit trail for "which scheduled handlers are
  heartbeating" + "which endpoints are probed".
- If future evidence (from downstream adoption in fxsa / cparx / callbot)
  shows projects routinely ship scheduled handlers without heartbeating,
  this decision should be revisited as a §10.10 spec amendment.

## References

- CONTEXT D1–D12 + N1–N7: [`22-sentry-crons-healthz/CONTEXT.md`](../../.planning/phases/22-sentry-crons-healthz/CONTEXT.md)
- Cross-AI plan review (gemini LOW vs codex HIGH; 5 verified inconsistencies folded as R01–R12):
  [`22-sentry-crons-healthz/22-REVIEWS.md`](../../.planning/phases/22-sentry-crons-healthz/22-REVIEWS.md)
- ADR-0014 (observability architecture): `~/Sourcecode/agenticapps/agenticapps-workflow-core/adrs/0014-observability-architecture.md`
- ADR-0026 (`add-observability` 0.5.1 wrapper fixes): [`0026-add-observability-0-5-1-wrapper-fixes.md`](./0026-add-observability-0-5-1-wrapper-fixes.md)
- ADR-0027 (GSD post-phase observability hook): [`0027-postphase-observability-hook.md`](./0027-postphase-observability-hook.md)
- Sentry Crons: <https://docs.sentry.io/product/crons/>
- Sentry Uptime: <https://docs.sentry.io/product/uptime-monitoring/>
