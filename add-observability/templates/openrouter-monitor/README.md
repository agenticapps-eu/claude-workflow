# openrouter-monitor

A standalone Cloudflare Worker that polls `OpenRouter /api/v1/key` every 15 minutes for proactive budget alerting. Forkable as-is; copy into a monorepo and update `wrangler.toml`'s `name`.

> ⚠️ **Use a `keys:read`-scoped OpenRouter API key** — never the generation key. A leaked generation key would burn the org's budget cap within minutes.

Architecture: [ADR-0030](../../../docs/decisions/0030-openrouter-integration-sdk-first.md). Cron heartbeat via `withCronMonitor` ([ADR-0029](../../../docs/decisions/0029-cron-monitor-sdk-composition.md)) so the monitor itself self-alerts on stall.

---

## 1. Install

```bash
npm install
```

The monitor pins `@sentry/cloudflare ^8.0.0` — it makes no LLM calls, so it doesn't need the Sentry AI Monitoring SDK minimum of `≥ 10.2.0` (that constraint applies to your main app, not this monitor). If you fork the monitor into a repo that already uses `@sentry/cloudflare ^10.x`, you can bump this pin — the bundled `src/observability/` subtree is forward-compatible.

## 2. Configure

### Secrets (set via `wrangler secret put`)

| Secret | Required | Notes |
|---|---|---|
| `OPENROUTER_API_KEY` | yes | **`keys:read` scope ONLY**. Format `sk-or-v1-…`. |
| `SENTRY_DSN` | yes | Without it, `init()` doesn't configure the destinations registry → `logEvent`/`captureError` silently no-op. |
| `AXIOM_TOKEN` | optional | For time-series `credit_pulse` ingestion. |
| `AXIOM_DATASET` | optional | Axiom dataset name. |

```bash
wrangler secret put OPENROUTER_API_KEY
wrangler secret put SENTRY_DSN
wrangler secret put AXIOM_TOKEN   # optional
wrangler secret put AXIOM_DATASET # optional
```

### Vars (set in `wrangler.toml`)

| Var | Default | Purpose |
|---|---|---|
| `DEPLOY_ENV` | `production` | Sentry environment tag. |
| `SERVICE_NAME` | `openrouter-monitor` | Sentry release identifier. |
| `OPENROUTER_WARNING_RATIO` | `0.85` | Emits `credit_low` warn at this used-ratio. |
| `OPENROUTER_CRITICAL_RATIO` | `0.95` | `captureError(OpenRouterBudgetCriticalError)` at this used-ratio. |

## 3. Deploy

```bash
wrangler deploy
```

Verify the first scheduled run via `wrangler tail` — you should see an `openrouter.credit_pulse` event within 15 minutes.

## 4. Tune

- **Cron frequency**: edit `wrangler.toml` `[triggers] crons`. Default is `*/15 * * * *` (every 15 min). Tighter is fine; looser risks budget overruns going undetected.
- **Ratio thresholds**: set `OPENROUTER_WARNING_RATIO` / `OPENROUTER_CRITICAL_RATIO` in `[vars]` or via secret-put. Inverted thresholds (warning ≥ critical) are detected, logged as `openrouter.misconfigured_thresholds`, and fall back to defaults.
- **Sentry alert wiring**: in your Sentry project, create an alert rule on `OpenRouterBudgetCriticalError` issue type → notification channel of choice. The cron monitor (slug `openrouter-credit-check`) has its own heartbeat — alert on missing check-ins.
- **Axiom dashboard**: the `openrouter.credit_pulse` event ships every 15 min with `{used, limit, used_ratio}` attrs. Plot a 7-day chart against your project's daily budget.

## 5. Security & Secret Lifecycle

The single most important detail: **scope**.

### Scope

Use a key with `keys:read` scope **only**. Never the generation key.

- `keys:read` leak → exposes spend metadata. Recoverable: rotate the key.
- Generation-key leak → an attacker can burn your org's budget cap within minutes. Recoverable: revoke immediately, monitor for unexpected spend.

The cost of containment is orders of magnitude lower with read-only scope.

### Per-environment keys

Use separate keys per environment:

```text
OPENROUTER_API_KEY_DEV   →  for the dev/staging Worker
OPENROUTER_API_KEY_PROD  →  for the prod Worker
```

A dev-env leak must not expose prod spend metadata. Bind each Worker (different `name` in `wrangler.toml`) to its own secret.

### Rotation cadence

**90-day rotation recommended.**

Procedure:

1. Create a new `keys:read` key in the OpenRouter dashboard.
2. `wrangler secret put OPENROUTER_API_KEY` and paste the new value.
3. Wait for the next scheduled run (≤15 min). Verify in `wrangler tail` that you see `openrouter.credit_pulse` — confirms the new key works.
4. Revoke the old key in the OpenRouter dashboard.

Downtime window: ≤5 minutes. Schedule rotations during low-budget-risk windows.

### Accidental-commit prevention

- `.gitignore` covers `.dev.vars`, `*.env`, `*.env.local`.
- `wrangler.toml` declares secrets only as **comments** — the actual value goes via `wrangler secret put`, never plaintext in source.
- Recommended pre-commit hook: `gitleaks detect` or `trufflehog filesystem .`, scanning for OpenRouter key prefix `sk-or-v1-`.

### Leak-response runbook

If a key is leaked (committed to a repo, logged in plaintext, posted in a Slack channel):

1. **Revoke FIRST** — go to the OpenRouter dashboard and revoke the key. Every minute of delay is budget burn risk if the key has generation scope.
2. Rotate per the rotation procedure above (create new, deploy, verify, revoke).
3. Audit `wrangler tail` history for unexpected `credit_pulse` origins.
4. File a security incident report.
5. Post-mortem: how did the key end up where it shouldn't be? Update guardrails.

### Operator offboarding

When an operator with deploy access leaves the team, rotate the key. Their shell history, clipboard, 1Password vault, or local `.dev.vars` may retain the value.

## 6. Fork into a monorepo

Copy the entire `openrouter-monitor/` directory into your repo at a path of your choosing. The bundled `src/observability/` subtree is self-contained (no cross-package imports), so the fork works standalone.

If your main app already has its own observability wrapper, replace the bundled `src/observability/` with a symlink (or workspace import) to your existing wrapper. The monitor's `check-credit.ts` only requires `logEvent` and `captureError` exports — drop-in compatible with any wrapper that follows ADR-0014 / §10.6.

## 7. Troubleshooting

- **No events firing** — check `wrangler tail`. If you see nothing on the cron trigger:
  - Verify `SENTRY_DSN` is set. Without it, the destinations registry doesn't initialise and `logEvent` silently drops events.
  - Verify the cron trigger fired: `wrangler tail --format pretty` shows scheduled invocations.
- **`OpenRouterHealthcheckFailedError(0)`** — network failure (DNS, TLS, OpenRouter outage). Check the OpenRouter status page.
- **`OpenRouterHealthcheckFailedError(-1)`** — malformed response body. OpenRouter API contract changed; review the response shape and adjust `check-credit.ts`.
- **`OpenRouterHealthcheckFailedError(429)`** — rate-limited. This is unusual on `/api/v1/key`; tighten the cron frequency or contact OpenRouter.
- **`OpenRouterBudgetCriticalError` firing unexpectedly** — check `wrangler tail` for the latest `credit_pulse`. `used_ratio` is the source of truth. If the alert fires but you think `used_ratio` is wrong, verify your OpenRouter dashboard.
- **Cron monitor stale** — the monitor itself uses `withCronMonitor` (ADR-0029) so Sentry tracks its own check-ins via the `openrouter-credit-check` slug. If you see no Sentry check-ins for ≥30 min, the monitor itself has stalled — investigate the Worker logs.
