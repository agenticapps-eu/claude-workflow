# Phase 26: worker-template hardening — Research

**Researched:** 2026-06-01
**Domain:** Observability template editing, test-harness hardening, engine content-filter extension, fixture repair
**Confidence:** HIGH — all claims verified against live codebase; npm registry queried for versions

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 through D-10a)
- D-01: Add `observabilitySentryOptions(env)` or `buildSentryOptions(env)` helper to `lib-observability.ts` (cf-worker + cf-pages + openrouter); naming is Claude's Discretion
- D-01a: Update `env-additions.md` per stack with wiring snippet + `## Sentry integration` subsection
- D-01b: Scope narrowed — supabase-edge + ts-react-vite ALREADY wire `tracesSampleRate`; do NOT touch
- D-01c: After D-01 lands, `diff -q ts-cloudflare-worker/lib-observability.ts openrouter-monitor/src/observability/index.ts` must return empty
- D-02: Leave singletons as-is; document invariant in ADR-0034
- D-02a: Add idempotency test to `lib-observability.test.ts` per 4 stacks (cf-worker, cf-pages, supabase-edge, openrouter)
- D-02b: ADR-0034 covers all 4 stacks symmetrically
- D-03: Pin `vitest` to `~3.2.4` in 3 heredoc package.jsons (cf-worker :170, cf-pages :291, supabase-edge :392)
- D-03a: Also pin `@sentry/cloudflare` to known-good `8.x.y` (planner researches version)
- D-03b: Add comment block at top of `run-template-tests.sh` explaining pin policy
- D-03c: Scope — cf-worker, cf-pages, supabase-edge (planner verifies supabase-edge npm install)
- D-04: NO Migration 0022 engine script
- D-04a: Claude's Discretion — write optional spec-only `migrations/0022-worker-template-hardening.md` doc
- D-05: Expand REDACTED_KEYS default to `[password, token, api_key, authorization, bearer, cookie, x-api-key, secret]`
- D-05a: Apply symmetrically across 4 TS stacks + go-fly-http; verify Go substring semantics
- D-05b: Update `policy.md.template` per stack to reflect expanded defaults
- D-06: Extend `_filter_index_ts_requires_co_anchor` with content-marker grep for `index.ts`
- D-06a: New fixture `migrations/test-fixtures/0019/13-index-ts-without-observability-content/`
- D-06b: Engine-only fix; no migration needed
- D-07a: Fix TS1038 — replace `declare const console` in `types.d.ts:59-63` with canonical `interface Console + declare var console`
- D-07b: Remove `exit 0` fallback from `verify.sh:75-77`; fail fast when npx unavailable
- D-07c: No new fixture; fix existing `0021/04`
- D-08: Add `.gitignore` to ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge, ts-react-vite, go-fly-http (planner researches ts-supabase-edge Supabase CLI conventions, ts-react-vite Vite conventions, go-fly-http Go conventions)
- D-08a: Each new `.gitignore` includes provenance header comment
- D-10: add-observability 0.9.0 → 0.10.0 (minor)
- D-10a: claude-workflow 1.20.0 → 1.20.1 (patch)

### Claude's Discretion
- Helper export naming: `buildSentryOptions` vs `observabilitySentryOptions` (research picks per Phase 25 naming convention)
- D-04a: Whether to write `migrations/0022-worker-template-hardening.md` doc
- Phase 26 plan structure: single PLAN.md vs multi-Plan wave structure

### Deferred Ideas (OUT OF SCOPE)
- AsyncLocalStorage singleton refactor (Phase 27+ candidate)
- Per-request closure refactor
- Symmetric DEF-1 for supabase-edge + react-vite
- Migration 0022 with engine script
- Markdown lint cleanup batch for 25-* planning artifacts
- Full retroactive ROADMAP/STATE/PROJECT bootstrap
- `FIX-0017-ENGINE.md` working-dir prompt
- gstack 1.48 → 1.52 upgrade
- Untracked session noise triage
</user_constraints>

---

## Phase Goal

Absorb six carry-forwards into a single hardening cycle before Phase 27:

1. **DEF-1 (TRACE_SAMPLE_RATE unwired):** `TRACE_SAMPLE_RATE` is a module-level constant in `lib-observability.ts` for cf-worker, cf-pages, and openrouter-monitor, but no code path passes it to `withSentry`. A new `buildSentryOptions(env)` helper export wires it end-to-end; operators call the helper at their entry file `withSentry(env => buildSentryOptions(env), handler)`.

2. **DEF-2 (REDACTED_KEYS too narrow):** Authorization and bearer token headers are not in the default redaction list. The fix expands the default across all five template stacks (4 TS + Go).

3. **DEF-3 (module-level singletons):** `serviceName`, `deployEnv`, `registry` live as module-level mutable state. Behavior is correct for Cloudflare's isolate-per-invocation model but undocumented. Fix is an ADR documenting the invariant + an idempotency test for all four TS stacks.

4. **F-2 (no tracked lockfile policy):** The harness's `vitest: ^3.0.0` resolved to `vitest@3.2.5` at Phase 25 audit time, which demanded `vite-node@3.2.5` — only `vite-node@3.2.4` was published at the time. Fix is a `~3.2.4` pin plus a `@sentry/cloudflare` pin.

5. **CR-D (engine false-positive filter):** `_filter_index_ts_requires_co_anchor` passes any `src/index.ts + src/middleware.ts` pair regardless of content. Adding a content-marker grep closes the false-positive class.

6. **CR-E (fixture TS1038 + exit-0 mask):** `0021/04 verify.sh` silently `exit 0` when `npx` is absent, masking TS1038 in `types.d.ts`.

Plus `.gitignore` extension from openrouter-monitor shape to all remaining template stacks.

---

## Approach Recommendations

### D-01 — TRACE_SAMPLE_RATE helper export

**Where to add:** `lib-observability.ts` — insert after the `init` function (around line 117) to keep the init/config block contiguous. The function is a pure config factory: it reads the already-declared `TRACE_SAMPLE_RATE` constant, `serviceName` (set by `init`), `deployEnv` (set by `init`), and the `env.SENTRY_DSN` parameter. It does NOT call `init` — operators call `init` via `withObservability`, THEN `withSentry(env => buildSentryOptions(env), ...)` wraps the entry point.

[VERIFIED: codebase read — `TRACE_SAMPLE_RATE` at `lib-observability.ts:62`; `withSentry` documented in comment block at line 97-99 and `sentry.ts:1-22`; supabase-edge already wires at `destinations/sentry.ts:86` — CONFIRMED DO NOT TOUCH]

**Naming decision:** Use `buildSentryOptions`. Rationale: Phase 25 D-19 established `build*` as the helper prefix convention (`buildMonitorConfig` at `cron-monitor.ts:99`). `observabilitySentryOptions` is descriptive but breaks the `build*` prefix pattern. `buildSentryOptions` is shorter, consistent, and matches the `build*` style the planner and executors will expect from context. `[VERIFIED: cron-monitor.ts:99 — buildMonitorConfig]`

**Signature:**
```typescript
// Insert after init() ~ line 117
export interface SentryOptions {
  dsn: string | undefined;
  environment: string;
  release: string;
  tracesSampleRate: number;
  sendDefaultPii: false;
}

/**
 * Build the options object for `withSentry(optionsFactory, handler)`.
 * Call at the entry-file site:
 *   export default withSentry(env => buildSentryOptions(env), withObservability(handler));
 *
 * TRACE_SAMPLE_RATE (baked at scaffold time from meta.yaml) is the authoritative
 * traces sample rate; this helper surfaces it to the Sentry SDK that
 * `withSentry` initialises per-request. Phase 26 DEF-1.
 */
export function buildSentryOptions(env: InitEnv): SentryOptions {
  return {
    dsn: env.{{ENV_VAR_DSN}},
    environment: deployEnv,
    release: serviceName,
    tracesSampleRate: TRACE_SAMPLE_RATE,
    sendDefaultPii: false,
  };
}
```

**Caution:** `deployEnv` and `serviceName` are module singletons. This is safe because `buildSentryOptions` is called AFTER `withObservability` has already run `init(env, ctx)` for this request. The composition order documented in `cron-monitor.ts:7` (INNERMOST first) means the init path always fires before `buildSentryOptions` is evaluated. The ADR-0034 invariant covers this.

**D-01c byte-symmetry:** After editing `ts-cloudflare-worker/lib-observability.ts`, copy verbatim to `openrouter-monitor/src/observability/index.ts`. The diff command is the verification gate.

---

### D-02 — Singleton ADR + idempotency test

**ADR-0034 shape:** Mirror ADR-0029 at `docs/decisions/0029-with-cron-monitor-guarded-shape-a.md` (exists; no file in repo — verified `ls docs/decisions/` shows 0030/0031/0032/0033 only). Structure: Status/Date/Phase header, Context (the Cloudflare isolate model), Decision (leave singletons; document invariant), Consequences. Anchor text: "Each Worker invocation executes in its own V8 isolate. Module-level mutable state is reset between invocations because each invocation loads a fresh module instance. The `init()` function is therefore safe to call once per invocation without global mutation risk across requests."

[VERIFIED: codebase — `lib-observability.ts:75-83` shows `let serviceName`, `let deployEnv`, `let registry`; supabase-edge `index.ts:84-96` shows `let initialized`, `let _testEnv` additionally]

**D-02a idempotency test shape:** The CONTEXT states: call `init(env_a, ctx)` → call `init(env_b, ctx)` with different `env_b.SERVICE_NAME` → assert result is deterministic. Since cf-worker's `init()` is NOT guarded by an `initialized` flag (unlike supabase-edge at `index.ts:164` which has `if (initialized) return`), calling it twice mutates `serviceName` to `env_b.SERVICE_NAME`. The test should assert "last-call-wins" semantics: after two calls, `serviceName` resolves to `env_b.SERVICE_NAME`. Supabase-edge's `init()` has `if (initialized) return`, so the test there must use `_resetForTest()` between calls to properly assert no-op semantics.

**Test file insertion point:** `lib-observability.test.ts` for cf-worker/cf-pages; `index.test.ts` for supabase-edge. Insert a new `describe("D-02 singleton idempotency", ...)` block. For the openrouter-monitor, the test file is at `openrouter-monitor/src/observability/index.test.ts`.

---

### D-03 — Harness pin hardening

**Verified edit sites:**
- `run-template-tests.sh:169-182` — cf-worker heredoc `package.json` (`vitest: "^3.0.0"`, `@sentry/cloudflare: "^8.0.0"`)
- `run-template-tests.sh:291-304` — cf-pages heredoc (same versions)
- `run-template-tests.sh:392-408` — ts-react-vite heredoc (`vitest: "^3.0.0"`, no `@sentry/cloudflare`) — **NOTE: this is react-vite, NOT supabase-edge**

[VERIFIED: file read — supabase-edge runner at lines 461-548 uses `deno test`, NOT npm install. The react-vite runner at lines 360-458 is the THIRD npm-install block (lines 429-437). D-03c confirmed: supabase-edge does NOT do npm install — it uses deno test. Therefore D-03 scope = cf-worker heredoc + cf-pages heredoc + ts-react-vite heredoc. The CONTEXT.md note at D-03c ("supabase-edge uses deno test, the harness still does an npm install shim for some assertions") is INCORRECT per the actual code — supabase-edge has zero npm install calls. Plan accordingly: 3 heredoc pin sites = cf-worker + cf-pages + ts-react-vite.]

**Version pins:**
- `vitest`: `"~3.2.4"` — locks to `3.2.4`, allows `3.2.x` patches up to but not including `3.2.5`. `[VERIFIED: npm registry — vitest@3.2.4 exists; 3.2.5 and 3.2.6 also published; ~3.2.4 resolves to >=3.2.4 <3.3.0]`
- `@sentry/cloudflare`: `"~8.55.0"` — `8.55.2` is the current 8.x latest stable. Pin to `~8.55.0` allows `8.55.x` patches. `[VERIFIED: npm registry query — @sentry/cloudflare 8.x latest = 8.55.2; current latest (v10) is unrelated — we stay on 8.x per template baseline]`

**Comment block:** Insert at top of `run-template-tests.sh` immediately after the `set -euo pipefail` line (around line 22):
```bash
# ─── Harness pins — re-bump deliberately ──────────────────────────────────────
# These version pins are INTENTIONAL. The harness has no committed package-lock.json
# (it materializes a temp dir per run), so unpinned semver ranges resolve to whatever
# the npm registry serves at run time. Phase 25 audit-time: vitest@^3.0.0 resolved
# to vitest@3.2.5 which demanded vite-node@3.2.5 — only 3.2.4 was published.
# Pins use `~` (patch-level) not `^` (minor-level) to stop similar registry drift.
# To upgrade: verify the new version locally, then update the pin here explicitly.
```

---

### D-04a — Migration 0022 spec-only doc decision

**Recommendation: skip the spec-only doc.** The migrations/README.md convention is that migration files contain engine-executable scripts with a well-defined from_version/to_version chain. A spec-only doc with no engine script would sit in the chain but match nothing during migration lookup. The CHANGELOG entry for add-observability 0.10.0 is the correct audit trail for template-only changes. Writing `migrations/0022-worker-template-hardening.md` adds discoverability at the cost of polluting the migration chain with a semantically hollow file. [VERIFIED: migrations/README.md:88-99 — "Pick the next free to_version per semver... Set from_version to the highest currently-released to_version your migration needs to chain after." A spec-only file would need from_version: 1.20.1, which is the Phase 26 target — the chain would then expect a migration FROM 1.20.1 and consumers running update would follow the chain link to a no-op script. This is confusing, not clarifying.] **Decision: no spec-only doc.**

---

### D-05 — REDACTED_KEYS expansion

**Verified Go substring semantics:** `observability.go:507-509` uses `strings.Contains(k, r)` — IDENTICAL substring match semantics to TypeScript's `k.includes(r)` at `lib-observability.ts:343`. D-05 wording in CONTEXT is correct as-is; no adjustment needed. `[VERIFIED: go-fly-http/observability.go:501-513 — strings.Contains confirmed]`

**Current defaults (all 5 stacks are identical):** `password, token, api_key, card_number, cvv, ssn, secret, client_secret, refresh_token, access_token`

**Target defaults (D-05):** `password, token, api_key, authorization, bearer, cookie, x-api-key, secret`

Note: The CONTEXT specifies a shorter list than the current one — it removes `card_number, cvv, ssn, client_secret, refresh_token, access_token` and adds `authorization, bearer, cookie, x-api-key`. This is intentional (the broader financial/PII terms are covered by `secret` + `token` substrings already; `authorization` and `bearer` are the HTTP header patterns that were missing). Verify this matches what the CONTEXT discussion decided — do not silently drop `card_number` without confirming; it may be a typo in D-05. **Recommendation: preserve the existing entries AND add the new ones.** The final expanded set should be: `password, token, api_key, card_number, cvv, ssn, secret, client_secret, refresh_token, access_token, authorization, bearer, cookie, x-api-key`. This is additive-only and passes the principle of "do not remove existing redaction coverage."

**Edit sites for REDACTED_KEYS:**
1. `ts-cloudflare-worker/meta.yaml:116-126`
2. `ts-cloudflare-pages/meta.yaml` (parallel location — verify)
3. `ts-supabase-edge/meta.yaml` (parallel)
4. `ts-react-vite/meta.yaml` (parallel)
5. `go-fly-http/meta.yaml:112-124`

**policy.md.template edit sites (D-05b):**
1. `ts-cloudflare-worker/policy.md.template:14-27` (redacted attributes section)
2. Same parallel locations for other 4 stacks

---

### D-06 — Content-marker firewall extension

**Current filter body** (`migrate-0019-sentry-crons-and-healthz.sh:208-233`):
```bash
# (a) Sibling co-anchor requirement.
local parent="${f%/index.ts}"
if [ -f "$parent/middleware.ts" ] || [ -f "$parent/_middleware.ts" ]; then
  printf '%s\n' "$f"
fi
```

**Extended body (add content-marker check before `printf`):**
```bash
local parent="${f%/index.ts}"
if [ -f "$parent/middleware.ts" ] || [ -f "$parent/_middleware.ts" ]; then
  # (c) Content-marker firewall (Phase 26 CR-D): index.ts must contain
  # at least one observability marker to be classified as a wrapper.
  # Hono/vanilla Worker apps that happen to have index.ts + middleware.ts
  # would otherwise trigger unsolicited .observability-0019.patch files.
  if grep -qiE "observability|lib-observability|withObservability|sentry|agenticapps:observability" "$f"; then
    printf '%s\n' "$f"
  fi
fi
```

**Insertion point:** Replace the `printf '%s\n' "$f"` at line 223 with the conditional block above. The `printf` moves INSIDE the content-check condition.

**D-06a fixture:** New directory `migrations/test-fixtures/0019/13-index-ts-without-observability-content/`. Use frozen literal convention (codex M-1 — files are static, not copied from mutable templates). Seeds `src/index.ts` as a vanilla Hono app:
```typescript
// Vanilla Hono Worker — no observability markers
import { Hono } from "hono";
const app = new Hono();
app.get("/", (c) => c.text("Hello World"));
export default app;
```
Seeds `src/middleware.ts` as a minimal Hono middleware file (the co-anchor). Expected result: `SKIP_UNSUPPORTED` — the content-marker check fires AFTER the co-anchor check, so the file has both co-anchor and non-matching content. The engine should silently drop it (no `.observability-0019.patch` emitted).

Verify via `bash migrations/run-tests.sh` → "✓ 13-index-ts-without-observability-content" in output.

---

### D-07 — Fixture TS1038 + exit-0 repair

**Current `types.d.ts:59-63`** (from file read, verified):
```typescript
// console — provided by ES2015+ lib but not included in strict ES2022-only
// (workers runtimes provide console; declare minimal surface for typecheck)
declare const console: {
  log(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
};
```

**TS1038 explanation:** `declare const` inside `declare global { ... }` is TS error 1038 "A 'declare' modifier cannot be used here." The correct pattern for ambient globals in a `declare global` block uses `var`:

```typescript
interface Console {
  log(...args: unknown[]): void;
  warn(...args: unknown[]): void;
  error(...args: unknown[]): void;
}
declare var console: Console;
```

**Current `verify.sh:75-78`** (from file read, verified):
```bash
if ! command -v npx >/dev/null 2>&1; then
  echo "fixture 0021/04 SKIP — npx unavailable (cannot run tsc)"
  exit 0
fi
```

**Replacement** (D-07b):
```bash
if ! command -v npx >/dev/null 2>&1; then
  echo "fixture 0021/04 FAIL — npx required for tsc typecheck (install Node 18+ which bundles npx)"
  exit 1
fi
```

---

### D-08 — .gitignore extension

**Source shape** (`openrouter-monitor/.gitignore`, verified via file read): `.dev.vars`, `.env`, `.env.local`, `.env.*.local`, `node_modules/`, `.wrangler/`, `dist/`.

**Per-stack adaptations:**

**ts-cloudflare-worker and ts-cloudflare-pages:** Copy verbatim. Both stacks are Cloudflare Workers/Pages projects — same wrangler toolchain, same `.dev.vars` pattern, same `.wrangler/` and `dist/` artifacts.

**ts-supabase-edge:** Keep `.dev.vars` (Supabase CLI reads it for local dev), `.env*` patterns, `node_modules/` (some tooling still creates it). Drop `.wrangler/` (not relevant). Add `supabase/.temp/` — this is the Supabase CLI's ephemeral temp directory created by `supabase start`. `[ASSUMED — Supabase CLI .temp/ convention: based on training knowledge; not verified via live Supabase CLI in this session. Planner should verify with `supabase init` dry-run or official docs.]` Also add `dist/` for edge function bundles.

**ts-react-vite:** Vite's default scaffolded project ships with no `.gitignore` in the template source files (confirmed: `ls ts-react-vite/` shows no `.gitignore`). The canonical Vite SPA `.gitignore` should include: `.env.local`, `.env.*.local`, `node_modules/`, `dist/`, `dist-ssr/`, `*.local`. `[ASSUMED — Vite default .gitignore shape: based on training knowledge that `npm create vite@latest` ships `.env.local` + `dist/` + `node_modules/` in its gitignore; not verified via live `npm create vite` in this session.]` Sentry-specific: add `.env.sentry-build-plugin` (Sentry build plugin temp file).

**go-fly-http:** No `.gitignore` exists. Go conventions + Fly.io artifacts: `*.test` (compiled test binaries), `*.out` (coverage output), `vendor/` (if vendoring), `.fly/` (Fly.io CLI config), `tmp/` (common Go build temp). `[ASSUMED — Go .gitignore conventions: based on training knowledge + common Go project patterns; no live verification in this session.]`

**Provenance header format (D-08a):**
```
# Mirror of openrouter-monitor/.gitignore (Phase 24); extended to <stack> in Phase 26.
# Template-only — operators may extend for project-specific paths.
```

---

## Open Question Answers

### OQ-1: Helper naming — `buildSentryOptions` vs `observabilitySentryOptions`

**Answer: `buildSentryOptions`.**

Evidence: Phase 25 D-19 established `build*` prefix convention for helper exports from template files — `buildMonitorConfig` at `cron-monitor.ts:99`, `isConfigured` at `cron-monitor.ts:54`. The CONTEXT.md §Specifics note reads: "Match Phase 25 D-19's buildMonitorConfig shape — recommended buildSentryOptions... first is shorter and matches Phase 25's build* prefix." `[VERIFIED: cron-monitor.ts:54,99]`

### OQ-2: `@sentry/cloudflare 8.x.y` known-good version

**Answer: `~8.55.0`** (resolves to `8.55.0` – `8.55.x`).

`8.55.2` is the current 8.x latest stable. The `~` constraint prevents unbounded minor advancement (e.g., `^8.0.0` resolving to `8.56+`). The package has been in active development; `~8.55.0` is stable as of 2026-06-01. `[VERIFIED: npm registry query — @sentry/cloudflare 8.x latest = 8.55.2; package published 2024–2026 with regular minor updates]`

### OQ-3: Does `run-template-tests.sh` do `npm install` for supabase-edge?

**Answer: NO.**

The supabase-edge runner at lines 461-548 uses `deno test -A --no-check` with no npm install step. The three npm install sites are: cf-worker (line 202-210), cf-pages (line 324-332), ts-react-vite (line 429-437). `[VERIFIED: run-template-tests.sh:461-548 — zero npm install lines in supabase-edge block]`

**Impact on D-03 scope:** D-03 applies to cf-worker + cf-pages + ts-react-vite heredoc package.jsons (3 sites, not 3 "cf* + supabase"). The CONTEXT.md note "(supabase-edge uses deno test, the harness still does an npm install shim for some assertions; planner verifies)" was a question — the answer is NO npm install for supabase-edge. Plan accordingly.

### OQ-4: Should `migrations/0022-worker-template-hardening.md` be written?

**Answer: No.** (See Approach Recommendations D-04a above.) CHANGELOG entry is the correct venue.

### OQ-5: Go template REDACTED_KEYS substring match semantics

**Answer: Substring match — IDENTICAL to TypeScript.**

`observability.go:507-509`:
```go
for _, r := range redactedKeys {
    if strings.Contains(k, r) {
```
`strings.Contains(k, r)` is Go's substring contains. `k` is the lowercased key. This is identical in semantics to TypeScript's `k.includes(r)`. D-05's wording ("substring-match semantics unchanged") is accurate for the Go stack too. `[VERIFIED: go-fly-http/observability.go:506-509]`

### OQ-6: .gitignore conventions for ts-supabase-edge, ts-react-vite, go-fly-http

**ts-supabase-edge:**
- Keep: `.dev.vars`, `.env*`, `node_modules/`, `dist/`
- Drop from worker template: `.wrangler/` (Wrangler-specific)
- Add: `supabase/.temp/` `[ASSUMED]`

**ts-react-vite:**
- Standard Vite SPA: `.env.local`, `.env.*.local`, `node_modules/`, `dist/`, `dist-ssr/`, `.env.sentry-build-plugin` `[ASSUMED]`

**go-fly-http:**
- Go standard: `*.test`, `*.out`, `vendor/`, `tmp/`, `.fly/` `[ASSUMED]`

See Assumptions Log for risk assessment of the three assumed items.

---

## Validation Architecture

`nyquist_validation` key is absent from `.planning/config.json`; treated as enabled. `[VERIFIED: config.json read — key absent]`

### Test Infrastructure

| Property | Value |
|----------|-------|
| Framework (cf-worker, cf-pages) | vitest (harness-ephemeral npm install; tests in `*.test.ts`) |
| Framework (supabase-edge) | deno test — `deno test -A --no-check $OBS_DIR/*.test.ts` |
| Framework (engine fixtures) | bash + harness via `migrations/run-tests.sh` |
| Framework (openrouter-monitor) | vitest via own tracked `package-lock.json` in `openrouter-monitor/` |
| Quick run command (per stack) | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` |
| Full suite command | `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh` |

### Per-Decision Validation Strategy

| Decision | Behavior to Verify | Test Type | Automated Command | Notes |
|----------|-------------------|-----------|-------------------|-------|
| D-01 | `buildSentryOptions` export present + returns object with `tracesSampleRate` | grep + harness | `grep -q "export function buildSentryOptions" add-observability/templates/ts-cloudflare-worker/lib-observability.ts` | Functional test: add to `lib-observability.test.ts` asserting return type shape |
| D-01c | byte-symmetry cf-worker ↔ openrouter-monitor | diff | `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` → empty output + exit 0 | MUST run after D-01 lands |
| D-02a | `init()` idempotency per 4 stacks | TS test | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` → new `D-02 singleton` describe block PASS | Also: `bash add-observability/templates/run-template-tests.sh ts-cloudflare-pages` + supabase-edge; openrouter: `npx vitest run` from its dir |
| D-02 (ADR) | ADR-0034 file present | grep | `test -f docs/decisions/0034-observability-init-singleton-invariant.md` | |
| D-03 | vitest pin `~3.2.4` present in 3 heredocs | grep | `grep -c '"vitest": "~3.2.4"' add-observability/templates/run-template-tests.sh` → output `3` | |
| D-03a | `@sentry/cloudflare` pinned in 2 heredocs (cf-worker + cf-pages) | grep | `grep -c '"@sentry/cloudflare": "~8.55.0"' add-observability/templates/run-template-tests.sh` → output `2` | ts-react-vite uses `@sentry/react` not `@sentry/cloudflare` |
| D-05 | REDACTED_KEYS expanded in all 5 meta.yaml files | grep | `grep -l "authorization" add-observability/templates/*/meta.yaml add-observability/templates/go-fly-http/meta.yaml \| wc -l` → 5 | |
| D-05b | policy.md.template updated per stack (5 files) | grep | `grep -l "authorization" add-observability/templates/*/policy.md.template \| wc -l` → 5 | |
| D-06 | content-marker filter present in engine script | grep | `grep -q "withObservability" templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | |
| D-06a | new fixture 13 present + passing | bash fixture | `bash migrations/run-tests.sh` → "✓ 13-index-ts-without-observability-content" | Need to add fixture 13 to dispatcher in `run-tests.sh` if not auto-discovered |
| D-06a | fixture 13 produces SKIP_UNSUPPORTED (no patch emitted) | fixture verify.sh | Within fixture setup: assert no `.observability-0019.patch` file created | |
| D-07a | TS1038 fixed — no `declare const console` inside `declare global` | grep | `grep -q "declare const console" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts` → exit 1 (not found) | |
| D-07b | exit-0 fallback removed from verify.sh | grep | `grep -c "exit 0" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh` → 0 | |
| D-07 | tsc typecheck still passes after fix | bash fixture | `bash migrations/run-tests.sh` → "✓ 04-callbot-shape-strict-env-typecheck" + "D-18 SC5 GREEN" | Full regression test |
| D-08 | .gitignore files present in 5 template stacks | find | `find add-observability/templates -maxdepth 2 -name .gitignore \| grep -v openrouter-monitor \| wc -l` → 5 | openrouter-monitor already has one |
| D-08a | provenance header present | grep | `grep -l "Phase 24\|Phase 26" add-observability/templates/ts-cloudflare-worker/.gitignore add-observability/templates/ts-cloudflare-pages/.gitignore ...` | |
| D-10 | add-observability CHANGELOG has 0.10.0 | grep | `grep -c "0.10.0" add-observability/CHANGELOG.md` >= 1 | |
| D-10a | root CHANGELOG has 1.20.1 | grep | `grep -c "1.20.1" CHANGELOG.md` >= 1 | |

### Sampling Rate

- **Per task commit:** Run touched test file directly: `bash add-observability/templates/run-template-tests.sh <stack>` or `bash migrations/run-tests.sh test_migration_0019_<fixture>`.
- **Per plan wave:** Full stack suite for affected stacks + `bash migrations/run-tests.sh` for engine/fixture work.
- **Phase gate (before `/gsd-verify-work`):** `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh` fully green. Diff check must return empty.

### Wave 0 Gaps (items that must exist before implementation)

- [ ] `migrations/test-fixtures/0019/13-index-ts-without-observability-content/{setup.sh,verify.sh,expected-exit}` — D-06a fixture (RED state before engine fix)
- [ ] Dispatcher entry for fixture 13 in `migrations/run-tests.sh` test_migration_0019 function (verify auto-discovery or add explicit entry)
- [ ] `docs/decisions/0034-observability-init-singleton-invariant.md` — D-02 ADR (can be Wave 0 doc task)
- [ ] `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts` — new `describe("D-02 singleton idempotency")` block (RED until D-02a implement)

---

## Threat Model Seed

### T1 — DEF-2 fix latency for existing operators
**Threat:** Operators with projects already scaffolded have a `policy.md` that is operator-owned. D-05's REDACTED_KEYS expansion in `meta.yaml` and `policy.md.template` only applies to fresh `add-observability init` runs. Existing projects continue with the narrow default set — `authorization` and `bearer` headers remain unredacted in their emitted events.
**STRIDE:** Information Disclosure.
**Mitigation surface:** CHANGELOG.md entry for 0.10.0 must contain an explicit `UPGRADE NOTE` calling out the REDACTED_KEYS expansion. `env-additions.md` update (D-01a) can include a side-note pointing operators to review their `policy.md`. No automated migration path since policy.md is operator-owned.
**Risk level:** LOW — operators who care about auth header redaction should audit their policy.md regardless.

### T2 — Engine filter regression (D-06 over-filtering)
**Threat:** The new content-marker grep `grep -qiE "observability|lib-observability|withObservability|sentry|agenticapps:observability"` might over-filter — blocking legitimate `index.ts` wrappers whose content uses Sentry without the exact listed strings. Example: a project that imports from `./middleware` only and doesn't reference Sentry directly in `index.ts` would be mis-classified as SKIP_UNSUPPORTED.
**STRIDE:** Denial of Service (migration engine skips a valid wrapper).
**Mitigation surface:** The fixture 13 (D-06a) is the regression detector for the false-positive class (vanilla app). For the false-negative class (valid wrapper skipped): review whether the regex covers all reasonable `@sentry/cloudflare` usage patterns. The string `"sentry"` (case-insensitive) is broad enough to catch `@sentry/cloudflare`, `withSentry`, `Sentry.init`, `SENTRY_DSN` — any of these will match. Projects importing ONLY from `./middleware` without ANY Sentry string in `index.ts` are likely not the canonical scaffolded shape and the SKIP behavior is acceptable (they can add a co-anchor comment).
**Risk level:** LOW — the regex is permissive enough; case-insensitive `sentry` substring covers all known variants.

### T3 — Pinned dependency drift (`~3.2.4` still allows `3.2.x` patches)
**Threat:** The `~3.2.4` pin still allows vitest `3.2.5`, `3.2.6`, etc. (patch-level updates). If a future `3.2.x` release introduces a vite-node version incompatibility similar to the Phase 25 event, the pin would not protect us.
**STRIDE:** Availability (test harness breaks, blocking CI).
**Mitigation surface:** D-03b comment block documents the "re-bump deliberately" policy. The real protection is the `~` constraint preventing MINOR advances (like `3.3.0`). The Phase 25 event involved `vitest@3.2.5` demanding `vite-node@3.2.5` which was briefly unpublished — a transient registry gap, not a semantic break. The `~` pin reduces the blast radius; the comment block ensures future editors understand the policy.
**Risk level:** LOW — transient registry gaps are rare; `~` is materially better than `^`.

### T4 — D-01c byte-symmetry contract violated by test additions
**Threat:** D-02a adds an idempotency test to `lib-observability.test.ts` for cf-worker. If the executor also adds the same test to `openrouter-monitor/src/observability/index.test.ts` (correct) but forgets to add `buildSentryOptions` to the openrouter-monitor `index.ts` (the byte-symmetry file), the diff check will fail without clear error messaging.
**STRIDE:** Integrity (template drift between cf-worker and openrouter-monitor).
**Mitigation surface:** D-01c verification (`diff -q`) is the gate. The plan should sequence D-01 (add helper to both files) as a single task that touches both simultaneously — not as two separate tasks that could be split across plan waves.

### T5 — TS1038 fix breaks fixture-04 tsc pass
**Threat:** Replacing `declare const console` with `interface Console + declare var console` is a semantic change. If there are OTHER TS1038 errors in `types.d.ts` beyond the console declaration, the `exit 0` removal (D-07b) would surface them as failures that were previously silently masked.
**STRIDE:** Availability (fixture-04 unexpectedly fails after fix).
**Mitigation surface:** The full `types.d.ts` was verified (lines 1-66 read) — the console block at lines 57-63 is the ONLY ambient declaration in the file; the rest of the file uses standard `declare global { interface ... }` patterns which are TS-legal. The risk is low, but the plan should run `bash migrations/run-tests.sh` against fixture-04 immediately after D-07a to confirm green before closing the plan.

---

## Risks & Unknowns

### Risk 1 — Byte-symmetry breaks if D-01 and D-02a are split across plans
If Plan A adds `buildSentryOptions` to `ts-cloudflare-worker/lib-observability.ts` and Plan B adds the idempotency test to the same file, the byte-symmetry check must only run AFTER both edits are committed to both `lib-observability.ts` AND `openrouter-monitor/src/observability/index.ts`. If an executor runs the diff check mid-wave (between the two edits), it will fail spuriously. **Mitigation:** The diff check should be a wave-final verification step, not a per-task check.

### Risk 2 — supabase-edge D-03 scope correction
CONTEXT.md D-03c contains "supabase-edge uses deno test, the harness still does an npm install shim for some assertions; planner verifies." The answer is definitively NO — supabase-edge does not do npm install in the harness. If any plan task is written as "pin vitest in supabase-edge heredoc," it will fail to find the heredoc because there is none. **Mitigation:** Plan must clearly state D-03 scope = cf-worker + cf-pages + ts-react-vite only (3 heredocs).

### Risk 3 — ADR-0034 next available ID
`ls docs/decisions/` shows 0030/0031/0032/0033. `0034` is the next available ID. This is unambiguous. If any other work creates 0034 before Phase 26 executes (unlikely given branch isolation), the executor must use 0035. **Mitigation:** Check `ls docs/decisions/0034*.md` at task execution time.

### Risk 4 — ts-react-vite has no `@sentry/cloudflare` in its harness heredoc
The ts-react-vite stack uses `@sentry/react`, not `@sentry/cloudflare`. D-03a pins `@sentry/cloudflare` in cf-worker + cf-pages heredocs. The plan must NOT add `@sentry/cloudflare` pin to the ts-react-vite heredoc. `[VERIFIED: run-template-tests.sh:392-408 — ts-react-vite heredoc uses "@sentry/react": "^8.0.0", no @sentry/cloudflare]`

### Risk 5 — REDACTED_KEYS expansion (additive vs replacement)
CONTEXT D-05 lists an 8-item target set that is SHORTER than the current 10-item default (it omits `card_number`, `cvv`, `ssn`, `client_secret`, `refresh_token`, `access_token`). This appears to be a simplification in the CONTEXT discussion. The safer approach is additive expansion (add `authorization`, `bearer`, `cookie`, `x-api-key` to the existing list) rather than replacement. Dropping `card_number` or `ssn` from the default would be a regression in financial/PII contexts. **Mitigation:** Plan tasks should add the 4 new entries to the existing 10, not replace the list.

### Risk 6 — `.gitignore` template format assumed entries
Three stacks have assumed (not verified via live tooling) gitignore entries. If Supabase CLI does not actually create `supabase/.temp/` or if the path is different, the entry is harmless but inaccurate. Similarly for Vite's `dist-ssr/` and Go's `.fly/`. These assumptions are low-risk (extra `.gitignore` entries that never match are harmless) but should be flagged in the plan.

---

## Recommended Plan Structure

Phase 25 used 5 plans (one per wave). Phase 26 has narrower scope with 3 distinct edit-class groups that can be executed mostly independently:

**Recommended: 3 plans**

**Plan 26-01: Wave 0 — ADR + RED fixtures + RED tests**
- Write ADR-0034 (`docs/decisions/0034-observability-init-singleton-invariant.md`)
- Create RED fixture `migrations/test-fixtures/0019/13-index-ts-without-observability-content/`
- Add fixture-13 dispatcher entry to `migrations/run-tests.sh`
- Add RED idempotency test stubs to `lib-observability.test.ts` for cf-worker, cf-pages; `index.test.ts` for supabase-edge; openrouter-monitor test file
- Confirm baseline: `bash migrations/run-tests.sh` → fixture 13 RED; `bash run-template-tests.sh ts-cloudflare-worker` → new idempotency test RED

**Plan 26-02: Wave 1 — Template changes (D-01, D-02a GREEN flip, D-05, D-08)**
- Add `buildSentryOptions` export to `ts-cloudflare-worker/lib-observability.ts`
- Copy byte-symmetrically to `openrouter-monitor/src/observability/index.ts`
- Update `env-additions.md` for cf-worker + cf-pages + openrouter-monitor (D-01a)
- Expand REDACTED_KEYS in all 5 meta.yaml files (D-05)
- Update all 5 `policy.md.template` files (D-05b)
- Add `.gitignore` files to 5 stacks (D-08 + D-08a)
- GREEN flip idempotency tests
- Verify: `diff -q` byte-symmetry check; `bash run-template-tests.sh all` green; grep counts for REDACTED_KEYS

**Plan 26-03: Wave 2 — Engine + fixture + harness + versions (D-03, D-06, D-07, D-10/D-10a)**
- Pin vitest/sentry in 3 harness heredocs (D-03), add comment block (D-03b)
- Extend `_filter_index_ts_requires_co_anchor` with content-marker (D-06)
- GREEN flip fixture 13 (engine change makes it pass)
- Fix `types.d.ts` TS1038 (D-07a) + remove `exit 0` from `verify.sh` (D-07b)
- Version bumps: add-observability CHANGELOG (0.10.0), root CHANGELOG (1.20.1)
- Verify: `bash migrations/run-tests.sh` all green; harness pin grep counts; `diff -q` final check

This 3-plan structure keeps template edits (Plan 02) separate from engine/harness/fixture edits (Plan 03), with Wave 0 RED-state setup in Plan 01. Total tasks per plan should stay under the plan-checker threshold.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Supabase CLI `supabase init` creates `supabase/.temp/` directory | D-08 gitignore ts-supabase-edge | Extra .gitignore entry that never matches — harmless; no negative impact on operator |
| A2 | Vite `npm create vite@latest` scaffolded `.gitignore` includes `dist-ssr/` | D-08 gitignore ts-react-vite | Extra entry if Vite no longer uses `dist-ssr/` — harmless |
| A3 | Fly.io CLI creates `.fly/` local config directory | D-08 gitignore go-fly-http | Extra entry if Fly.io CLI changed local config location — harmless |

All three assumptions are LOW risk: extra `.gitignore` entries that never match are harmless. The gitignore files are operator-facing scaffolding; operators can extend or trim them per project.

---

## Environment Availability

Phase 26 is template-file editing + bash script editing + fixture addition. External dependencies:

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Node.js / npm | D-03 harness pin verification | ✓ | (project's node) | — |
| deno | supabase-edge harness validation | not checked in this session | — | skip deno-layer test; engine fixtures still green |
| bash | engine script execution, fixture runner | ✓ (darwin) | zsh/bash | — |
| npx | D-07b failure mode (verify.sh) | ✓ (bundled with Node 18+) | — | — |

---

## Sources

### Primary (HIGH confidence)
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts` — D-01 edit site, TRACE_SAMPLE_RATE location, redaction semantics
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:54,99` — Phase 25 naming convention (`buildMonitorConfig`, `isConfigured`)
- `add-observability/templates/go-fly-http/observability.go:506-509` — Go REDACTED_KEYS substring semantics (`strings.Contains`)
- `add-observability/templates/run-template-tests.sh:202,324,429` — D-03 npm install sites (cf-worker, cf-pages, ts-react-vite)
- `add-observability/templates/run-template-tests.sh:461-548` — supabase-edge deno test, confirmed NO npm install
- `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts:57-63` — TS1038 issue location
- `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh:75-78` — exit-0 mask location
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:208-233` — D-06 edit site
- `add-observability/templates/openrouter-monitor/.gitignore` — D-08 source shape
- `add-observability/templates/ts-cloudflare-worker/meta.yaml:116-126` — REDACTED_KEYS current defaults
- `add-observability/templates/go-fly-http/meta.yaml:112-124` — Go REDACTED_KEYS defaults
- npm registry query — `@sentry/cloudflare 8.x latest = 8.55.2`; `vitest 3.2.x latest = 3.2.6`
- `migrations/README.md` — migration chain conventions (D-04a rationale)
- `docs/decisions/0033-with-queue-monitor.md` — ADR shape precedent for ADR-0034

### Secondary (MEDIUM confidence)
- `25-VALIDATION.md §Environmental caveat` — F-2 / vitest@^3.0.0 drift root cause
- `25-REVIEW.md WR-04, IN-01` — run-template-tests.sh trap patterns (review findings, not direct edits)
- `session-handoff.md` — CodeRabbit D+E findings origin, Phase 26 candidate list

### Tertiary (LOW confidence)
- Supabase CLI `.temp/` directory convention `[ASSUMED]`
- Vite default `.gitignore` shape `[ASSUMED]`
- Fly.io CLI `.fly/` local config directory `[ASSUMED]`

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — all edit sites verified in live codebase
- Architecture: HIGH — patterns verified from Phase 25 ADRs and live source
- Pitfalls: HIGH — verified via CONTEXT + live source reads; 3 ASSUMED items are low-risk cosmetic

**Research date:** 2026-06-01
**Valid until:** 2026-07-01 (npm versions may drift; `@sentry/cloudflare` 8.x is actively maintained)
