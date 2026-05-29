# Sentry Crons + Uptime — Operator Setup Runbook

This runbook walks an operator through the Sentry UI configuration that
pairs with the code-side primitives shipped by `add-observability`
v0.6.0:

- **`withCronMonitor` / `WithCronMonitor`** emits per-invocation Sentry
  `captureCheckIn` heartbeats from a scheduled handler. Per-`monitorSlug`,
  one **Cron Monitor** is provisioned in the Sentry UI.
- **`healthz-snippet.{ts,go}`** ships a copy-only `/healthz` HTTP handler
  that aggregates dependency probes into a 200 / 503 response. Per
  public `/healthz` endpoint, one **Uptime Monitor** is provisioned.

The wrapper templates do not auto-create either object in Sentry — the
operator does that here, once per slug and once per endpoint, and
records the inventory in `.observability/policy.md` so future operators
don't lose context.

> **Why two products?** `withCronMonitor` answers *"did the scheduled
> handler actually run?"*. Uptime answers *"is the public surface
> reachable at all?"*. The wrappers' in-process capture path can't fire
> from code that never ran — both gaps need out-of-process monitors.
> The host-discretion trade-off behind not mandating this in spec §10.x
> is documented in **ADR-0028 — Sentry Crons + healthz conventions**.

Prerequisites:

- An active Sentry organization with **Crons** and **Uptime
  Monitoring** enabled in your plan.
- The wrapper templates already materialized into your repo via
  `add-observability init` or migration 0019.
- A team to route alerts to (created under **Settings → Teams**).

---

## Part 1 — Sentry Crons (per `monitorSlug`)

### Why this matters

Sentry **upserts** a Cron Monitor the first time it sees a checkin for a
given slug, but it will not alert on a monitor that has *never* received
a checkin. If you cycle slugs per deploy (don't — see CONTEXT D3), or if
the very first scheduled run silently fails before reaching
`captureCheckIn`, Sentry has nothing to alert on. Pre-provisioning the
monitor in the UI before the first deploy guarantees the alert pipeline
is wired before the heartbeat ever arrives.

### Step 1 — Find the slugs your wrappers emit

Each call to `withCronMonitor(handler, { monitorSlug: "…" })` (TS) or
`WithCronMonitor(ctx, fn, WithMonitorSlug("…"))` (Go) defines one slug.
Grep the codebase to inventory them:

```bash
# TS stacks
grep -rn "withCronMonitor" --include="*.ts" .

# Go stack
grep -rn "WithCronMonitor\|WithMonitorSlug" --include="*.go" .
```

If a call site omits the explicit slug, the wrapper falls back per
CONTEXT D6:

1. Env var `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` (handler name
   uppercased, hyphens → underscores).
2. Auto-derived: Worker uses `${SERVICE_NAME}:${controller.cron}`;
   Pages / Supabase Edge use `${SERVICE_NAME}:${handlerName ?? "scheduled"}`;
   Go uses `${SERVICE_NAME}:${handlerName ?? "scheduled"}`.

> **Multi-cron workers (D11):** a Cloudflare Worker that dispatches a
> single `scheduled` export against multiple cron triggers (`crons =
> ["*/15 * * * *", "0 0 * * *"]` in `wrangler.toml`) **MUST** pass
> `monitorSlug` explicitly per branch. The env-var convention cannot
> disambiguate, and the auto-derived form will emit one monitor per
> cron expression — which the operator may not have provisioned. Read
> `controller.cron` and dispatch:
>
> ```typescript
> const SLUG_BY_CRON: Record<string, string> = {
>   "*/15 * * * *": "fxsa-ingest-15min",
>   "0 0 * * *":    "fxsa-ingest-daily",
> };
> export default withSentry(env)(withObservabilityScheduled(
>   async (controller, env, ctx) => withCronMonitor(
>     innerHandler,
>     { monitorSlug: SLUG_BY_CRON[controller.cron] ?? "fxsa-ingest-unknown" },
>   )(controller, env, ctx),
> ));
> ```

### Step 2 — Create the Cron Monitor in Sentry

For each slug surfaced above:

1. Navigate to **Crons → Add Monitor**.
2. **Name**: a human-readable label (the slug is the machine ID; the
   name is what the on-call sees in alerts).
3. **Slug**: paste the exact slug emitted by your code. Sentry will
   reject mismatches at checkin time.
4. **Schedule type**: `crontab` (the common case) or `interval`. Match
   what the runtime actually uses — Cloudflare cron triggers and
   `pg_cron` are crontab; Go `time.NewTicker(1 * time.Hour)` is interval.
5. **Schedule value**: the exact cron expression or interval. Sentry
   uses this to compute the *missed checkin* window.
6. **Checkin margin**: how late a checkin may be before "missed" fires.
   Default 1 minute is fine for 15-min+ schedules; for 1-min crons,
   raise to 5+ minutes to absorb cold-start jitter.
7. **Max runtime**: how long an in-progress checkin may stay open before
   Sentry flips it to "error: timeout". Per CONTEXT N5, the wrapper
   does **not** enforce this client-side — it is metadata-only
   forwarded from `config.maxRuntimeSeconds`. Set it in the UI to
   ~1.5× your handler's p99.
8. **Timezone**: match your cron's source (Cloudflare cron is UTC,
   `pg_cron` is database-server-local).
9. **Alert rule**: route to the team that owns the cron. At minimum,
   alert on *missed* and *error*.

> **D12 — monitor config upsert.** The wrapper forwards `schedule` and
> `maxRuntimeSeconds` as Sentry's optional 2nd `captureCheckIn`
> argument on the *in_progress* checkin only. Sentry treats subsequent
> same-slug checkins as already-configured, so the UI-side schedule
> you set above is the source of truth from that point on. If you
> change the schedule in `wrangler.toml`, also change it in the UI.

### Worked example A — `fxsa-worker` (TypeScript, 15-min Cloudflare Worker)

| Field             | Value                              |
|-------------------|------------------------------------|
| Name              | `fxsa-worker — ingest (15 min)`    |
| Slug              | `fxsa-ingest-15min`                |
| Schedule type     | `crontab`                          |
| Schedule value    | `*/15 * * * *`                     |
| Checkin margin    | `2 minutes`                        |
| Max runtime       | `120 seconds` (handler p99 ~80s)   |
| Timezone          | `UTC`                              |
| Alert routes to   | `#fxsa-oncall` Slack via PagerDuty |

Wrapper call site:

```typescript
export default withSentry(env)(withObservabilityScheduled(
  withCronMonitor(ingestHandler, {
    monitorSlug: "fxsa-ingest-15min",
    schedule: { type: "crontab", value: "*/15 * * * *" },
    maxRuntimeSeconds: 120,
  }),
));
```

### Worked example B — `callbot-kompendium` (Go, hourly `time.NewTicker`)

| Field             | Value                                |
|-------------------|--------------------------------------|
| Name              | `callbot-kompendium — sweep (1 h)`   |
| Slug              | `callbot-kompendium-sweep-hourly`    |
| Schedule type     | `interval`                           |
| Schedule value    | `1 hour`                             |
| Checkin margin    | `5 minutes`                          |
| Max runtime       | `600 seconds` (sweep p99 ~7 min)     |
| Timezone          | `UTC`                                |
| Alert routes to   | `#callbot-oncall` Slack              |

Wrapper call site:

```go
ticker := time.NewTicker(1 * time.Hour)
defer ticker.Stop()
for range ticker.C {
    err := observability.WithCronMonitor(ctx, sweepOnce,
        observability.WithMonitorSlug("callbot-kompendium-sweep-hourly"),
        observability.WithMaxRuntimeSeconds(600),
    )
    if err != nil {
        log.Printf("sweep failed: %v", err)
    }
}
```

---

## Part 2 — Sentry Uptime (per HTTPS endpoint)

### Why this matters

`withCronMonitor` cannot tell you that the worker is deployed but
routing-failed, that the Pages Function returns 502 before reaching user
code, or that your Go service crashed and didn't restart. Sentry Uptime
probes the public HTTP surface from Sentry's regional probers and
alerts on reachability and response-shape regressions — orthogonal to
the in-process capture path. One Uptime Monitor per public `/healthz`
endpoint.

### Step 1 — Inventory `/healthz` endpoints

Each project that mounted the `healthz-snippet.{ts,go}` template exposes
one. Grep for the snippet's handler export:

```bash
grep -rn "healthzHandler\|HealthzHandler" --include="*.ts" --include="*.go" .
```

Then verify each is publicly reachable from your edge:

```bash
curl -fsS https://fxsa-worker.example.com/healthz
# expected: {"status":"ok","checks":{"kv":true,"serviceBinding":true}}
```

### Step 2 — Create the Uptime Monitor in Sentry

For each endpoint:

1. Navigate to **Uptime → Create Monitor**.
2. **Name**: project + endpoint (`fxsa-worker — /healthz`).
3. **URL**: the full HTTPS URL. Use the public production URL, not a
   staging or internal one (those should have their own monitors).
4. **HTTP method**: `GET`.
5. **Interval**: `1 minute` for tier-1 critical, `5 minutes` for normal,
   `15 minutes` for batch-only systems. Probes are not free — pick
   the slowest interval that meets your detection-time SLO.
6. **Expected response**:
   - **Status code**: `200`.
   - **Response body contains**: `"status":"ok"`. This guards against
     a 200 from a CDN cache when the origin is degraded; the body
     match enforces that the probe reached *your* handler. Optionally
     also add a body-does-not-contain rule for `"status":"degraded"`
     as a belt-and-braces guard.
7. **Regions**: enable at least two geographically distant probers
   (e.g. `us-east` and `eu-west`) so a single-region outage in
   Sentry's probe network doesn't false-page you.
8. **Timeout**: `10 seconds` is fine for most healthz handlers. If your
   handler does a deep dep check that legitimately takes longer, raise
   it — but also consider splitting `/healthz` (shallow, public) and
   `/readyz` (deep, internal — see Part 4).
9. **Alert rule**: route to the same team as the corresponding Cron
   Monitor when possible — the on-call should see both signals
   together.

> **Probe rate vs. cost.** A 1-minute probe across 4 regions = 5,760
> requests / day per endpoint. If your handler is wrapped in
> `withObservability`, that's 5,760 Sentry transactions / day of pure
> probe noise — which is why CONTEXT D9 declares `/healthz` NOT
> wrapped. Keep it that way.

### Step 3 — Verify the probe lands

After saving, wait one interval. The monitor's history should show one
green entry. If it's red, common causes:

- **DNS / TLS error**: prober can't reach the URL. Check the public
  URL is correct and reachable from outside your network.
- **Body match fail**: handler returned 200 but body didn't include
  `"status":"ok"`. Either the snippet wasn't adapted (so it's
  fail-closed-503 per R06), or your probes are genuinely failing.
- **5xx**: dependency probe failed. Hit the URL with `curl` to see
  which `checks.*` key is `false`.

---

## Part 3 — Cross-link via `.observability/policy.md`

### Why this matters

The wrapper templates materialize a `policy.md` in `.observability/`
that records the project's observability posture (destinations,
sampling, redaction, etc.). The Cron / Uptime inventory lives in the
*Sentry UI*, but the operator-side decisions ("which slugs exist?
which endpoints are probed? where do alerts go?") only exist in one
operator's head until they're written down. Adding an
**Out-of-process monitors** section to `policy.md` records that
inventory next to the rest of the observability config, so future
operators (and PR reviewers) can verify that every `withCronMonitor`
call site has a corresponding Sentry-side monitor.

### Template — append to `.observability/policy.md`

```markdown
## Out-of-process monitors

### Sentry Crons

| Monitor slug                       | Owner          | Schedule        | Max runtime | Alert route          | Notes |
|-----------------------------------|----------------|-----------------|-------------|----------------------|-------|
| `fxsa-ingest-15min`               | fxsa-platform  | `*/15 * * * *`  | 120 s       | `#fxsa-oncall` / PD  | Critical ingest path; missed → page |
| `callbot-kompendium-sweep-hourly` | callbot-runtime | `1 h interval` | 600 s       | `#callbot-oncall`    | Batch; missed → ticket only |

### Sentry Uptime

| Endpoint                                  | Owner          | Interval | Regions          | Alert route         | Notes |
|-------------------------------------------|----------------|----------|------------------|---------------------|-------|
| `https://fxsa-worker.example.com/healthz` | fxsa-platform  | 1 min    | us-east, eu-west | `#fxsa-oncall` / PD | Public; shallow probe; `?detail=true` for ops only |
| `https://callbot-kompendium.fly.dev/healthz` | callbot-runtime | 5 min | us-east, eu-west | `#callbot-oncall` | Public; auth gated — see Bearer token in 1Password |

### Verification

When adding a new `withCronMonitor` call site or a new public
`/healthz` mount, the PR description must reference the row added to
the table above. Reviewers grep `policy.md` against the diff:

    git diff main -- '**/*.ts' '**/*.go' | grep -E 'withCronMonitor|healthzHandler' \
      | xargs -I{} grep -F "{}" .observability/policy.md || echo "MISSING: add row to policy.md"
```

Adapt the columns to your project's actual taxonomy — the goal is one
table row per slug and one per endpoint, with a clear owner and alert
route.

---

## Part 4 — Security & Public Exposure

> **Binding:** this section satisfies PLAN R10. The
> `healthz-snippet.{ts,go}` files ship a permissive default for local
> development; production exposure requires the hardening described
> here.

### Why this matters

The default healthz handler returns the per-check breakdown
unconditionally:

```json
{
  "status": "degraded",
  "checks": {
    "kv": true,
    "serviceBinding": false,
    "postgres": true,
    "internalSearchService": false
  }
}
```

Each key in `checks` names an *internal dependency* of your service.
An attacker probing `/healthz` learns your topology: which datastores
you depend on, which downstream services you call, and — through
status fluctuation over time — which of those are flaky enough to
target for amplification attacks. The information disclosure is low-
severity in isolation but compounds with any other reconnaissance.

This is by design for local development — when you're debugging "why
is healthz red?" the per-check breakdown is exactly what you want.
The mitigation is to **gate the breakdown behind a query parameter**
for production.

### Mitigation 1 — gate `checks` behind `?detail=true`

Adapt your copy of `healthz-snippet.ts` (you already copied it per the
WARNING block at the top of the snippet) to suppress the `checks` map
unless `?detail=true` is present. Worker example:

```typescript
const url = new URL(req.url);
const detail = url.searchParams.get("detail") === "true";

// ... probe execution unchanged, populating `checks: Record<string, boolean>` ...

const probeNames = Object.keys(checks);
if (probeNames.length === 0) {
  // R06 fail-closed branch — keep the `reason` field always-visible.
  return new Response(
    JSON.stringify({
      status: "degraded",
      reason: "no probes configured — adapt healthz-snippet.ts to your dependencies",
    }),
    { status: 503, headers: { "content-type": "application/json" } },
  );
}

const allOk = probeNames.every((k) => checks[k]);
const body: Record<string, unknown> = { status: allOk ? "ok" : "degraded" };
if (detail) body.checks = checks;

return new Response(JSON.stringify(body), {
  status: allOk ? 200 : 503,
  headers: { "content-type": "application/json" },
});
```

Behaviour after this change:

- Public probe (`GET /healthz`) → `{"status":"ok"}` or
  `{"status":"degraded"}`. No internal topology leak.
- Ops probe (`GET /healthz?detail=true`) → full breakdown as before.
  Useful from inside a bastion or via curl-from-ops-machine.

Update your Sentry Uptime monitor's body-match to the shallow form
(`"status":"ok"`) — the previous `checks.*:true` body match would
break under this change. The Part 2 Step 2 example uses the shallow
match.

> **The unmodified copy-only `healthz-snippet.ts` shipped by
> `add-observability` returns the per-check breakdown unconditionally
> — that's intentional for local development.** The runbook (this
> section) is where the operator learns about hardening it for
> production. The snippet's top-of-file WARNING block points back
> here; see the worker snippet header for the exact reference.

### Mitigation 2 — `/healthz` (shallow, public) vs `/readyz` (deep, internal)

A Kubernetes-style split keeps the public surface minimal while
preserving deep dependency visibility for ops:

- **`/healthz`** — *liveness*. Always returns 200 while the process is
  alive enough to handle requests. No dependency probing. Body:
  `{"status":"ok"}`. Public; safe to probe from Sentry Uptime at any
  interval.
- **`/readyz`** — *readiness*. Returns 200 only when all dependencies
  probe healthy; returns 503 with the full `checks` breakdown when
  any probe fails. Internal-only — bind to a private interface,
  put behind a bastion, or require auth (Mitigation 3).

> CONTEXT **N7** defers shipping `/readyz` as a template in this
> phase. The pattern above is documented here so operators who want
> the split can implement it themselves on top of the existing
> `healthz-snippet.{ts,go}` — copy the snippet twice, strip the
> probes from one (it becomes `/healthz`), and keep the probes in
> the other (it becomes `/readyz`). The pattern may ship as a
> template in a future minor; until then, it's a copy-and-modify on
> the operator side.

### Mitigation 3 — Sentry Uptime probe authentication

If `/healthz` is auth-gated (recommended for `/readyz`, optional for
`/healthz` when topology leakage is a concern), Sentry Uptime's
**Headers** config attaches a long-lived Bearer token to every probe:

1. Generate a long-lived service token scoped to "read healthz only".
   Use a separate token per environment so revoking one doesn't blast
   the others.
2. Store the token in your secrets manager (1Password, Vault, AWS SM).
3. In the Sentry Uptime monitor's **Headers** field, add:

   ```
   Authorization: Bearer <token>
   ```

4. Verify the monitor still goes green after the change.
5. Set a calendar reminder for token rotation — Sentry will not warn
   you when the token expires; the monitor will flip red.

> **Don't reuse a user-session token.** Use a service token scoped
> to the single healthz route. A leaked user-session token is far
> more dangerous than a leaked healthz-only token.

---

## References

- **ADR-0028** — Sentry Crons + healthz conventions (host-discretion
  trade-off; not a spec mandate).
- **CONTEXT.md** decisions D1 (separate wrapper), D3 (slugs are stable),
  D6 (3-source slug resolution), D9 (`/healthz` not wrapped), D11
  (multi-cron explicit slug), D12 (monitorConfig forwarding), N7
  (`/readyz` deferred).
- **PLAN.md** revisions R06 (fail-closed empty probes), R07 (WARNING
  block), R10 (this runbook's Part 4 mandate).
- Sentry Crons docs: <https://docs.sentry.io/product/crons/>.
- Sentry Uptime docs: <https://docs.sentry.io/product/uptime-monitoring/>.
