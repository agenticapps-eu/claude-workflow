# SECURITY.md — Phase 24 (OpenRouter Integration)

> **/cso Chief Security Officer audit — diff mode, daily-confidence gate (8/10).**
> Scope: `feat/openrouter-integration-v1.19.0` (PR #55) vs `origin/main` (`7904681..10f4cdc`, 18 commits, 35 files, ~5400 insertions).
> Date: 2026-05-30. Output: `.planning/phases/24-openrouter-integration/SECURITY.md` (this file) + machine-readable copy at `.gstack/security-reports/2026-05-30-073500.json`.

---

## Status

**DONE_WITH_CONCERNS** — 0 CRITICAL, 0 HIGH, **2 MEDIUM**, 0 LOW. Neither MEDIUM blocks merge; both are easy fixes. The substantive security posture is strong: the high-value attack surface (production OpenRouter API key + outbound HTTP boundary) is correctly defended with the right primitives.

## Verdict

**Safe to squash-merge PR #55 as-is.** The two MEDIUM findings (F-1 .gitignore documentation gap, F-2 lockfile supply-chain integrity) are below the merge-block bar. Both can ship in a fast follow-up or be folded into Phase 25.x — captured here so they don't get lost.

---

## Attack surface census (Phase 24 delta)

```
CODE SURFACE (new in Phase 24)
  Public endpoints:      0 (monitor is scheduled-only, no HTTP routes)
  Authenticated:         0
  Admin-only:            0
  API endpoints:         0 (no inbound — outbound consumer of OpenRouter only)
  File upload points:    0
  External integrations: 1 NEW — GET https://openrouter.ai/api/v1/key (Bearer-auth, every 15 min)
  Background jobs:       1 NEW — openrouter-credit-check scheduled handler
  WebSocket channels:    0

INFRASTRUCTURE SURFACE (new in Phase 24)
  CI/CD workflows:       0 (none modified)
  Webhook receivers:     0 (none added)
  Container configs:     0 (no Dockerfile)
  IaC configs:           1 NEW — add-observability/templates/openrouter-monitor/wrangler.toml
  Deploy targets:        1 NEW — Cloudflare Workers (cron-only)
  Secret management:     wrangler secret put (Cloudflare native KMS) + env binding

NEW SECRETS (in scope)
  OPENROUTER_API_KEY     required — keys:read scope MANDATORY (T1 mitigation in README §5)
  SENTRY_DSN             required — without it, destinations registry no-ops silently
  AXIOM_TOKEN            optional — Axiom ingest token
  AXIOM_DATASET          optional — Axiom dataset name
```

## Architecture mental model

The openrouter-monitor is a standalone Cloudflare Worker that polls OpenRouter's `/api/v1/key` endpoint every 15 minutes (`*/15 * * * *` cron) and emits structured budget telemetry. Composition chain:

```text
withSentry(env => ({ dsn, environment, release, tracesSampleRate, sendDefaultPii: false }))
  → withObservabilityScheduled                 // calls init(), populates destinations registry
    → withCronMonitor(handler, { monitorSlug })  // Sentry Crons heartbeat (ADR-0029 Guarded Shape A)
      → checkCredit                              // the handler
```

Trust boundary: `OPENROUTER_API_KEY` (RESTRICTED) lives in Cloudflare Workers secrets, flows through the `env` binding into the `Authorization: Bearer …` header on a single HTTPS GET. No echoes, no logging of the key value, no URL-embedded credential.

---

## Findings

### F-1 (MEDIUM, confidence 9/10, VERIFIED) — README's `.gitignore` claim is unfounded

* **Severity:** MEDIUM
* **Confidence:** 9/10
* **Status:** VERIFIED (file:line quoted, repo `.gitignore` inspected, `git check-ignore` confirms)
* **Phase:** 2 (Secrets Archaeology) + 5 (Infrastructure Shadow Surface)
* **Category:** Secrets / Documentation drift
* **File:** `add-observability/templates/openrouter-monitor/README.md:100`

**Quoted motivating line:**

```markdown
- `.gitignore` covers `.dev.vars`, `*.env`, `*.env.local`.
```

**What's wrong:** The monitor template ships **no `.gitignore`** (`add-observability/templates/openrouter-monitor/.gitignore` does not exist), and the repo's root `.gitignore` does not cover `.env`, `.env.local`, `.dev.vars`, or `node_modules/`. `git check-ignore` confirms: `.dev.vars`, `.env`, and `node_modules/foo` are all **NOT excluded** in this repo.

**Why it matters:** The README documents this exclusion as a security guarantee. A maintainer testing the monitor template in-place (running `npm install` and `wrangler dev` in `add-observability/templates/openrouter-monitor/` with a real OpenRouter `sk-or-v1-…` key in `.dev.vars`) could accidentally `git add .dev.vars` and commit a live production credential. The pattern is recoverable (key rotation + history scrub) but the cost of containment is exactly what the README §5 leak-response runbook describes — a real incident.

**Exploit scenario:**
1. Maintainer clones claude-workflow and wants to dogfood the monitor.
2. Creates `add-observability/templates/openrouter-monitor/.dev.vars` with `OPENROUTER_API_KEY=sk-or-v1-…` (real key, even keys:read scope).
3. Runs `git add .` to stage their other changes; `.dev.vars` is included (not gitignored, contrary to README claim).
4. Commits + pushes to a fork or PR branch.
5. Key now lives in git history. Even if revoked, the leaked-key window exposed spend-pattern metadata (keys:read scope) or, if generation-scope was mistakenly used, allowed an attacker to burn the org budget cap within minutes.

**Impact:** Trust gap. The README §5 "Accidental-commit prevention" subsection is operator-facing documentation that explicitly cites `.gitignore` coverage. If that coverage is missing, the operator's mental model is wrong at exactly the moment they're about to leak.

**Recommendation:**

Ship a template-local `.gitignore` at `add-observability/templates/openrouter-monitor/.gitignore`:

```gitignore
# Secrets (NEVER commit these)
.dev.vars
.env
.env.local
.env.*.local

# Generated
node_modules/

# Build artifacts
dist/
.wrangler/
```

The template-local `.gitignore` is the right shape because (a) the monitor template is designed to be forked — the consumer's `.gitignore` matters more than the claude-workflow repo's; (b) shipping the file means the README's claim becomes true the instant the consumer copies the template into their monorepo. Also add the same `.gitignore` shape to the other 3 template dirs (`ts-cloudflare-worker/`, `ts-cloudflare-pages/`, `ts-supabase-edge/`) for consistency, even though they're not Phase 24 work — they share the same forkable-template shape.

Alternative: amend the repo's root `.gitignore` to cover `.env*` / `.dev.vars` / `node_modules/`. This protects in-place dogfooding but not consumers. The template-local solution is better.

---

### F-2 (MEDIUM, confidence 8/10, VERIFIED) — No tracked `package-lock.json` in monitor template (supply-chain integrity)

* **Severity:** MEDIUM
* **Confidence:** 8/10
* **Status:** VERIFIED (`git ls-files` returns empty for `package-lock.json`)
* **Phase:** 3 (Dependency Supply Chain)
* **Category:** Supply Chain
* **File:** `add-observability/templates/openrouter-monitor/`

**What's wrong:** The template ships a `package.json` pinning `@sentry/cloudflare ^8.0.0` + 4 devDependencies, but no `package-lock.json` is tracked in git. `npm install` generates a lockfile locally but it's untracked (per current `git status`). The README §1 installs with bare `npm install` and gives no lockfile guidance.

**Why it matters:** For a template that ships **production-deployable infra** (a Cloudflare Worker holding a live OpenRouter key), lockfile absence means:
- Two consumers cloning the template at different times resolve different transitive trees.
- A malicious update to a deep transitive (sub-dep of `@sentry/cloudflare`, `wrangler`, `vitest`, or `@cloudflare/workers-types`) lands silently on next install.
- No `npm audit` reproducibility — security scans against one fork's resolved tree don't transfer to another fork.

This is the supply-chain attack vector that hit `event-stream`, `colors`, `coa`, and `ua-parser-js` — a single transitive compromise hits everyone without a lockfile.

**Exploit scenario (concrete):**
1. Attacker compromises a maintainer account of a transitive dep of `wrangler` or `vitest` (devDeps don't matter here — but `@sentry/cloudflare` transitive deps DO matter, since the monitor ships them to prod).
2. Publishes a malicious patch version that exfiltrates env vars (including `OPENROUTER_API_KEY` and `SENTRY_DSN`) during the build/deploy step.
3. Consumer who forked the template last week is safe (they pinned via their own local lockfile). Consumer who forks this week resolves the patch and gets compromised on `wrangler deploy`.
4. Stolen `OPENROUTER_API_KEY` → spend-pattern leak (keys:read) or budget burn (if generation scope was mistakenly used).

**Impact:** Adds a non-deterministic supply-chain window for every consumer who forks the template. The mitigation per CSO precedent #10 ("Lockfile not tracked by git IS a finding for app repos, NOT for library repos") applies here — the monitor template is closer to an app than a library because it's deployed verbatim.

**Recommendation:**

Two options:

**Option A (preferred):** Commit `package-lock.json` to `add-observability/templates/openrouter-monitor/`. Consumers get a known-good baseline tree and can `npm ci` for reproducibility. Update README §1 to recommend `npm ci` for production deploys.

**Option B:** If keeping the lockfile out of git is intentional (some template repos do this to let consumers pick lock format — `package-lock.json` vs `yarn.lock` vs `pnpm-lock.yaml` vs `bun.lockb`), then:
- Add to README §1: "Run `npm install`, commit the generated `package-lock.json` in YOUR fork before deploying. Without a tracked lockfile, transitive supply-chain updates land silently on each `npm install`."
- Ship a template-local `.gitignore` that does NOT exclude `package-lock.json` (so the consumer's `git add` picks it up).

Either way: make the lockfile policy explicit. Today it's neither shipped nor documented.

---

## Verified-safe items (auditor's notes, not findings)

These were checked and found clean. Documented so future reviewers don't re-litigate them.

| Concern | Where | Why it's safe |
|---|---|---|
| **`err.message` paths leak API key?** | `check-credit.ts:130, 158` | `err.message` from fetch failures contains the request URL (`https://openrouter.ai/api/v1/key`), NOT the Authorization header. URL is non-sensitive (public endpoint). API key never appears in error messages. |
| **Sentry breadcrumbs capture Authorization header?** | `index.ts:46-56` | `@sentry/cloudflare ^8.0.0` default Breadcrumbs integration captures fetch URL+method+status. Headers are NOT captured by default. `sendDefaultPii: false` on line 56 hardens further. |
| **OpenRouter response body echoes the key?** | `check-credit.ts:152-188` | Verified against ADR-0030 docs: `/api/v1/key` returns `{ data: { usage, limit } }` — usage metadata only, no key echo. On parse failure (line 158-168), only the SyntaxError `message` is logged (e.g., "Unexpected token X"), NOT the response body. On contract-guard failure (line 178-188), a hardcoded message is logged — no body content. |
| **SSRF via fetch URL?** | `check-credit.ts:125-128` | URL is hardcoded `"https://openrouter.ai/api/v1/key"`. No user input, no env-var interpolation into the URL. No SSRF. |
| **TLS verification disabled?** | Whole template | No `NODE_TLS_REJECT_UNAUTHORIZED`, no `rejectUnauthorized: false`, no `InsecureSkipVerify`. Default TLS hardening intact. |
| **Inline secrets in wrangler.toml?** | `wrangler.toml:35-36` | Only `DEPLOY_ENV` and `SERVICE_NAME` as real `[vars]`. All sensitive bindings (`OPENROUTER_API_KEY`, `SENTRY_DSN`, `AXIOM_TOKEN`, `AXIOM_DATASET`) are documented as comments only — actual values via `wrangler secret put`. |
| **Install scripts in production deps?** | `package.json` | None. No `preinstall`/`postinstall`/`install` scripts. Only `test` and `deploy` scripts (both consumer-invoked). |
| **PII in consumer helper `recordLLMResponseMeta`?** | `llm-response-meta.ts:74-91` | Captures metadata only: model, service, rate-limit headers, token counts, cache_ratio. NO prompt text, NO completion text. Comment on line 66 explicitly states "It does NOT log inputs or outputs". |
| **Runbook §2 PII gate enforcement?** | `openrouter-integration.md:88-130` | Explicit ⚠️ callout pinning `recordInputs: false` / `recordOutputs: false` as default. Names callbot (HIPAA), cparx (financial PII) as non-negotiable. Consent gate via `policy.md` for the allowed-exceptions carve-out (synthetic/eval-dataset only). Strong defaults + auditable consent path. |
| **`DEPLOY_ENV` defaults to "production"?** | `index.ts:53` | NO — defaults to `"dev"` per Stage 1 F-5 fix. `wrangler.toml [vars]` sets `"production"` explicitly for real deploys. Fail-safe: local `wrangler dev` never pollutes the prod Sentry environment. |
| **Cron timing creates DoS risk on OpenRouter?** | `wrangler.toml:14` | `*/15 * * * *` = 96 requests/day to OpenRouter from this monitor per consumer. Negligible by OpenRouter's own rate-limits (no rate-limit incident in the 13-fixture test suite). |
| **Bearer template literal injection?** | `check-credit.ts:126` | `Authorization: \`Bearer ${env.OPENROUTER_API_KEY}\`` — env vars are trusted input per CSO precedent #3. No user-controlled data flows into the header construction. |

---

## STRIDE — openrouter-monitor component

| Threat | Verdict | Notes |
|---|---|---|
| **Spoofing** | ✅ MITIGATED | Bearer auth to OpenRouter (standard). Cloudflare Workers cron is system-triggered, no spoofable client. |
| **Tampering** | ✅ MITIGATED | HTTPS in transit. Sentry/Axiom are append-only sinks. Code path is deterministic (cron + fixed URL). |
| **Repudiation** | ✅ MITIGATED | Every cron tick produces a `credit_pulse` log envelope to Sentry + Axiom with timestamp. Audit trail exists by construction. |
| **Information Disclosure** | ⚠️ MOSTLY MITIGATED | API key never leaks via error paths, breadcrumbs, or response bodies (verified above). **Gap:** F-1 `.gitignore` documentation drift creates an attractive-nuisance trap for maintainers dogfooding the template. Fix per F-1. |
| **Denial of Service** | ✅ MITIGATED | `AbortSignal.timeout(10_000)` on fetch (Stage 1 F-3). Cron frequency conservative (15 min). `withCronMonitor` self-alerts on stall (`openrouter-credit-check` slug, Sentry Crons heartbeat). |
| **Elevation of Privilege** | ✅ MITIGATED | `keys:read` scope mandate (README §5 leading ⚠️). Even on key compromise, blast radius = spend-metadata exposure, not budget burn. Per-env keys + 90-day rotation + operator-offboarding rotation all documented as runbook procedures. |

---

## Data classification

| Class | Data | Where it lives | Protections |
|---|---|---|---|
| **RESTRICTED** | `OPENROUTER_API_KEY` | Cloudflare Workers secrets (KMS-backed) → env binding → Authorization header | `keys:read` scope mandate, per-env keys, 90-day rotation cadence, leak-response runbook, operator-offboarding rotation, recommended `gitleaks`/`trufflehog` pre-commit hook for `sk-or-v1-` prefix |
| **RESTRICTED** | `SENTRY_DSN`, `AXIOM_TOKEN` | Cloudflare Workers secrets | Documented as `wrangler secret put`-only. No inline references in source or wrangler.toml `[vars]`. |
| **CONFIDENTIAL** | Spend metadata (`used`, `limit`, `used_ratio`) | Sentry (events + errors) + Axiom (time-series) | Business metric, not PII. Sentry/Axiom are paid SaaS with auth-gated access. Threshold tuning documented. |
| **INTERNAL** | Cron heartbeat (`openrouter-credit-check`) | Sentry Crons | Operational signal. No leak risk. |
| **PUBLIC** | Alert thresholds, service name, README/runbook content | Source repo | Intentionally public. |

---

## Phase coverage

| Phase | Status | Notes |
|---|---|---|
| 0 — Architecture mental model + stack detection | ✅ | Node/TS + Cloudflare Worker + Sentry SDK v8 + Vitest. Stack-aware scanning applied. |
| 1 — Attack surface census | ✅ | Census above; 1 new outbound integration, 1 new scheduled handler, 4 new secrets. |
| 2 — Secrets archaeology (diff mode) | ✅ | No leaked credentials in PR diff. F-1 surfaces documentation drift in adjacent layer. |
| 3 — Dependency supply chain | ✅ | No install scripts in prod deps. F-2 surfaces lockfile-tracking gap. `npm audit` deferred (no `node_modules` hydrated globally; per-fork concern). |
| 4 — CI/CD pipeline security | ✅ SKIPPED (--diff scope) | No `.github/workflows/` changes in Phase 24. |
| 5 — Infrastructure shadow surface | ✅ | `wrangler.toml` clean. No Dockerfile, no IaC (Terraform/K8s), no compose. |
| 6 — Webhook & integration audit | ✅ | OpenRouter integration is OUTBOUND only — not a webhook receiver. TLS defaults intact. No OAuth surface. |
| 7 — LLM & AI security | ✅ | The monitor itself makes NO LLM calls. Consumer helper (`recordLLMResponseMeta`) captures metadata only — no prompt/completion content. Runbook §2 PII gate is strong. |
| 8 — Skill supply chain | ✅ SKIPPED (--diff scope) | No new skills in Phase 24. |
| 9 — OWASP Top 10 | ✅ | A01 N/A (no auth surface), A02 ✅ (no weak crypto, HTTPS Bearer), A03 ✅ (env-var bearer, no SQL/cmd surface), A05 ✅ (DEPLOY_ENV fail-safe, sendDefaultPii false), A09 ✅ (cron + Sentry audit trail), A10 ✅ (hardcoded URL, no SSRF). A04/A07/A08 N/A for cron-only worker. |
| 10 — STRIDE threat model | ✅ | See table above. |
| 11 — Data classification | ✅ | See table above. |
| 12 — FP filtering + active verification | ✅ | Both findings self-verified; quoted motivating lines for the pre-emit verification gate. No verifier subagent dispatched (findings are documentation/operational, not code-pattern matches). |
| 13 — Findings report | ✅ | This file. |
| 14 — Save report | ✅ | JSON copy at `.gstack/security-reports/2026-05-30-073500.json`. `.gstack/` is already gitignored per repo root `.gitignore`. |

---

## Remediation roadmap

Both findings are below the merge-block bar. Recommended sequencing:

1. **F-1 (.gitignore)**: ship in a follow-up commit on this branch (1 file, 1 line of work). Could also fold into the squash-merge if you want a clean ship. Trivial.
2. **F-2 (lockfile)**: requires a decision (commit lockfile vs document the policy). Recommend folding into **Phase 25.x worker-template cleanup** alongside DEF-1/2/3 — same forkable-template shape concern.

Neither warrants holding PR #55.

---

## Trend tracking

No prior `.gstack/security-reports/` exist in this repo. This is the **first /cso run**. Establishes the baseline; future audits will compare against this report's `fingerprint` field per finding.

---

## Disclaimer

This tool is not a substitute for a professional security audit. /cso is an AI-assisted scan that catches common vulnerability patterns — it is not comprehensive, not guaranteed, and not a replacement for hiring a qualified security firm. LLMs can miss subtle vulnerabilities, misunderstand complex auth flows, and produce false negatives. For production systems handling sensitive data, payments, or PII, engage a professional penetration testing firm. Use /cso as a first pass to catch low-hanging fruit and improve your security posture between professional audits — not as your only line of defense.
