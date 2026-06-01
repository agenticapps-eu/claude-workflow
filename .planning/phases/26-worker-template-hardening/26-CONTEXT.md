# Phase 26: worker-template hardening - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 26 absorbs deferred items surfaced by Phases 24 and 25 reviews into a single cleanup cycle. **Scope is fixed.** Three concrete fix-classes:

1. **Template wrapper gaps** carried forward from Phase 24's `/review` (DEF-1 unwired `TRACE_SAMPLE_RATE`, DEF-2 missing `authorization` / `bearer` in REDACTED_KEYS, DEF-3 module-level singletons + Cloudflare-isolate assumption).
2. **Test harness drift defense** (F-2 — no tracked lockfile policy; surfaced concretely by the Phase 25 audit-time `vitest@3.2.5 → vite-node@3.2.5` upstream registry drift).
3. **Post-Phase-25 CodeRabbit residuals** (CR-D `_filter_index_ts_requires_co_anchor` content-marker firewall; CR-E `0021/04 verify.sh` exit-0 mask + TS1038 ambient `declare const console`).

Plus extending Phase 24's `.gitignore` shape from `openrouter-monitor` to the three other TS template directories.

**Out of scope (deferred to later phases or rejected):**
- Migration 0022 — fixes are template-only, no engine port needed (rationale in D-04 below).
- AsyncLocalStorage refactor of singletons — over-engineering for a latent issue (D-02).
- Cross-stack uniform refactor of TRACE_SAMPLE_RATE wiring across supabase-edge / react-vite — those stacks already wire correctly (D-01b).
- 10 × markdown lint findings in `.planning/phases/25-*/*.md` historical artifacts — cosmetic, not worth Phase 26 bandwidth (D-09).
- Full retroactive ROADMAP/STATE/PROJECT bootstrap — separate phase before Phase 27 (carry-forward, not Phase 26 scope).

</domain>

<decisions>
## Implementation Decisions

### DEF-1 — TRACE_SAMPLE_RATE wiring (cf-worker / cf-pages / openrouter-monitor)

- **D-01:** Add `observabilitySentryOptions(env): SentryOptions` export to `lib-observability.ts`. Returns `{ dsn: env.SENTRY_DSN, environment: deployEnv, release: serviceName, tracesSampleRate: TRACE_SAMPLE_RATE, sendDefaultPii: false }`. Operator wires via:
  ```ts
  export default withSentry(env => observabilitySentryOptions(env), withObservability(handler));
  ```
  Wrapper owns the contract end-to-end; TRACE_SAMPLE_RATE stops being dead code. Naming convention mirrors Phase 25 D-19's `buildMonitorConfig` — Claude's Discretion: planner picks `buildSentryOptions` or `observabilitySentryOptions` per Phase 25 naming convention.

- **D-01a:** Update `env-additions.md` per stack with the wiring snippet so operators know to call the helper. Add `## Sentry integration` subsection between `## Production secrets` and `## package.json`. Include note that `@sentry/cloudflare ≥ 8.0.0` is required (already declared as dep).

- **D-01b — Scope (narrow per codex H-3/H-6 principle):** D-01 applies to `ts-cloudflare-worker` + `ts-cloudflare-pages` + `openrouter-monitor` (bundled subtree, per Phase 25 D-21 byte-symmetry). `ts-supabase-edge` already wires `tracesSampleRate` at `destinations/sentry.ts:86` (Deno runtime has direct `Sentry.init` call). `ts-react-vite` already wires at `destinations/sentry.ts:81`. **Do not touch what works.**

- **D-01c — D-21 byte-symmetry preserved:** After D-01 lands in `ts-cloudflare-worker/lib-observability.ts`, `openrouter-monitor/src/observability/index.ts` must remain byte-identical. Verification step in PLAN.md: `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` returns empty.

### DEF-2 — REDACTED_KEYS default expansion

- **D-05:** Expand REDACTED_KEYS `default` in `meta.yaml` from `[password, token, api_key]` to `[password, token, api_key, authorization, bearer, cookie, x-api-key, secret]`. Industry-standard set. Substring-match semantics unchanged (the redactor uses `.some((r) => k.includes(r))` at `lib-observability.ts:343`).

- **D-05a — Scope:** Apply symmetrically across all 4 TS template stacks (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `ts-react-vite`) + Go template (`go-fly-http/meta.yaml`). Verify the Go template's redaction logic supports substring match in the same way (planner verifies during research).

- **D-05b — `policy.md.template` update:** The generator inlines REDACTED_KEYS from `policy.md` (per the comment at `lib-observability.ts:64-66`). Update `policy.md.template` per stack to reflect the expanded defaults so consent gate 1 (policy.md write) presents the broader set to operators.

### DEF-3 — Module-level singleton handling

- **D-02:** Leave `let serviceName`, `let deployEnv`, `let registry` as module-level mutable singletons. Document the Cloudflare-isolate-per-invocation assumption in a new ADR: `docs/decisions/0034-observability-init-singleton-invariant.md`.

- **D-02a — Idempotency test:** Add `init() is idempotent within a single isolate` assertion to `lib-observability.test.ts` per stack (cf-worker, cf-pages, supabase-edge, openrouter-monitor). Test shape: call `init(env_a, ctx)` → call `init(env_b, ctx)` with different `env_b.SERVICE_NAME` → assert the result is deterministic (either no-op or atomic replacement matching last-call semantics). Test name: `init() called twice within isolate yields deterministic singleton state`.

- **D-02b — Scope:** ADR-0034 applies to all 4 TS template stacks symmetrically (singletons appear in cf-worker:75-76+83, cf-pages:82-83+90, supabase-edge:85-86+96, openrouter:75-76+83 — verified). supabase-edge has an extra `let initialized` + `let _testEnv` from test bootstrap; the ADR's invariant covers those too (lazy-init + test-only state, not request-scoped state). Idempotency test applies symmetrically.

### F-2 — Test harness drift defense

- **D-03:** Pin `vitest` to `~3.2.4` in `run-template-tests.sh` heredoc package.jsons for cf-worker (`:170`), cf-pages (`:291`), supabase-edge (`:392`). The `~` lock prevents future `vitest@3.2.5+` from being resolved, dodging the upstream `vite-node@3.2.5` registry drift that bit Phase 25 audit-time.

- **D-03a:** Also pin `@sentry/cloudflare` to a known-good `8.x.y` (planner researches current stable version) in cf-worker + cf-pages heredocs. Same pattern: prevent unbounded `^8.0.0` resolution from picking up a future broken minor.

- **D-03b — Re-pin cadence:** Add a comment block at top of `run-template-tests.sh` (`# Harness pins — re-bump deliberately:`) explaining the policy: pins are intentional, not lockfile substitutes. Operators upgrading should re-pin to current known-good after vetting.

- **D-03c — Stack scope:** D-03 applies to the 3 TS stacks that the harness exercises with `npm install` (cf-worker, cf-pages, supabase-edge — though supabase-edge uses `deno test`, the harness still does an `npm install` shim for some assertions; planner verifies). ts-react-vite is NOT exercised by the harness today (it ships as a Vite SPA, not a backend test target) — out of scope this phase even though it has the same vitest pin risk. go-fly-http uses `go test` — no npm exposure.

### Migration shape

- **D-04:** Template-only — NO Migration 0022. Rationale:
  - D-01 (`observabilitySentryOptions`) requires OPERATOR action at their entry file (`withSentry(env => observabilitySentryOptions(env), ...)`); a migration can't force that wiring, only document it. Fresh applies + `env-additions.md` operator-facing snippet suffices.
  - D-05 (REDACTED_KEYS) updates template defaults via `meta.yaml`; existing projects' `policy.md` is operator-owned and won't be touched.
  - D-02 (singleton ADR + idempotency test) is doc + test; no behavior delta to migrate.
  - D-06 (CR-D content-marker firewall) + D-03 (harness pins) are engine / harness fixes — they apply automatically to anything running the engine past commit-land, no per-project migration needed.
  - D-07 (CR-E TS1038 + verify.sh exit-0) is a test-fixture fix; same as above.
  - D-08 (.gitignore extension) is for fresh applies; existing projects can manually copy the file.

- **D-04a — Migration spec doc?** Optionally write `migrations/0022-worker-template-hardening.md` as a spec-only documentation artifact (no engine script) describing the delta for audit / discoverability purposes. **Claude's Discretion** — planner decides based on docs convention; lean towards "no spec doc" since template-only changes can be captured in CHANGELOG entries.

### CR-D — `_filter_index_ts_requires_co_anchor` content-marker firewall

- **D-06:** Extend `_filter_index_ts_requires_co_anchor` at `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:208-233` to also content-check the `index.ts` file. Acceptance requires BOTH:
  1. (existing) Sibling `middleware.ts` (cf-worker shape) or `_middleware.ts` (cf-pages shape) present.
  2. (existing) Path does NOT contain `/dist/`, `/build/`, `/out/` (codex M-2 dist-filter).
  3. **(new)** `index.ts` content matches case-insensitive marker regex: `grep -qiE "observability|lib-observability|withObservability|sentry|agenticapps:observability"`.

- **D-06a — New fixture:** `migrations/test-fixtures/0019/13-index-ts-without-observability-content/` — seeds `src/index.ts` + `src/middleware.ts` where `index.ts` is a vanilla Hono `app.get(...)` with no observability markers. Expected: `SKIP_UNSUPPORTED` (no anchor classified). Verifies the false-positive class CodeRabbit identified is closed.

- **D-06b — Engine-only fix; no migration:** D-06 changes the engine binary that ships in `templates/.claude/scripts/` — any project re-running migration 0019 picks up the new filter automatically.

### CR-E — `0021/04` verify.sh exit-0 mask + TS1038

- **D-07:** Two sub-fixes in `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/`:

  **D-07a — TS1038 ambient `declare const console`:** Replace the current ambient block in `types.d.ts:59-63`:
  ```ts
  // BEFORE (TS1038 — illegal `declare` inside `declare global`)
  declare const console: { log(...): void; warn(...): void; error(...): void; };
  ```
  with canonical pattern:
  ```ts
  // AFTER
  interface Console {
    log(...args: unknown[]): void;
    warn(...args: unknown[]): void;
    error(...args: unknown[]): void;
  }
  declare var console: Console;
  ```

  **D-07b — verify.sh exit-0 mask:** Remove the `exit 0` fallback at `verify.sh:75-77`. New behavior: if `npx` is unavailable, FAIL the fixture with explicit error message (`fixture 0021/04 FAIL — npx required for tsc typecheck`). CI environments must have npx; dev boxes that don't can install Node 18+ which bundles npx. Honest fail-fast.

- **D-07c — No new fixture needed:** D-07a/b fix existing fixture, not new ones.

### .gitignore extension

- **D-08:** Extend `.gitignore` shape from `add-observability/templates/openrouter-monitor/.gitignore` to:
  - `ts-cloudflare-worker/.gitignore` — copy verbatim (same runtime, same secret-leak risk).
  - `ts-cloudflare-pages/.gitignore` — copy verbatim (same runtime).
  - `ts-supabase-edge/.gitignore` — adapt for Deno runtime: keep `.dev.vars`, `.env*`, `node_modules/` (some tooling still creates it); drop `.wrangler/`; add `supabase/.temp/` if Supabase CLI convention requires it (planner researches Supabase CLI gitignore patterns).
  - `ts-react-vite/.gitignore` — Vite ships with its own `.gitignore` convention; planner checks if extending is needed or if existing covers the surface.
  - `go-fly-http/.gitignore` — Go has different conventions (vendor/, *.test); planner researches.

- **D-08a — Provenance:** Each new `.gitignore` includes a header comment block citing this phase + the openrouter-monitor precedent (`# Mirror of openrouter-monitor/.gitignore (Phase 24); extended to <stack> in Phase 26`).

### Versioning

- **D-10:** `add-observability` bumps 0.9.0 → **0.10.0** (minor). Template surface changes: D-01 helper export (new public function), D-05 REDACTED_KEYS default broadening, D-02 ADR + idempotency tests, D-08 new `.gitignore` files. No breaking changes — every prior consumer continues to work; new consumers get the new defaults.

- **D-10a:** `claude-workflow` bumps 1.20.0 → **1.20.1** (patch). Engine + harness changes only: D-06 content-marker filter (false-positive reduction, behavior narrowing not additive), D-03 harness pins, D-07 fixture fix. Repo convention: "patch for clarifications, minor for additive, major for breaking" — D-06 is a behavior refinement (not new capability), D-03 is internal, D-07 is fixture-only. **Patch is honest.**

### Claude's Discretion

- **Helper export naming:** `buildSentryOptions` vs `observabilitySentryOptions` — planner picks per Phase 25 D-19 naming convention (which used `buildMonitorConfig` + `isConfigured`).
- **D-04a (Migration 0022 spec-only doc):** Planner decides whether to write `migrations/0022-worker-template-hardening.md` as a docs-only artifact for discoverability, or skip entirely.
- **Phase 26 plan structure:** Single Plan vs multi-Plan wave structure — planner picks based on Plan-checker max-task threshold guidance. Phase 25 used 5 plans; Phase 26 has narrower scope but the same per-stack symmetry shape, so 2-3 plans is likely.
- **`go-fly-http` REDACTED_KEYS verification:** Planner verifies Go redaction substring semantics during research; if Go uses exact-match instead of substring, D-05 wording adjusts.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 24 carry-forward source
- `.planning/phases/24-openrouter-integration-kit/SUMMARY.md` §"Deferred items" — DEF-1/2/3 + F-2 origin
- `.planning/phases/24-openrouter-integration-kit/CONTEXT.md` — original Phase 24 decisions (REDACTED_KEYS context, policy.md flow)
- `add-observability/templates/openrouter-monitor/.gitignore` — D-08 shape source

### Phase 25 residual source
- `.planning/phases/25-fix-0019-engine-and-cron-wrappers/25-VALIDATION.md` §"Environmental caveat (audit-time, 2026-06-01)" — F-2 / vitest pin context
- `.planning/phases/25-fix-0019-engine-and-cron-wrappers/25-REVIEW.md` — CodeRabbit findings D + E historical context
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:208-233` — D-06 edit site
- `migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/` — D-07 edit site (types.d.ts + verify.sh)
- `session-handoff.md` (root) — current Phase 26 candidate list

### Template files to edit
- `add-observability/templates/ts-cloudflare-worker/lib-observability.ts` — D-01 helper export (line ~62 area + new export), D-02 ADR target, D-05a singletons addressed by ADR
- `add-observability/templates/ts-cloudflare-pages/lib-observability.ts` — symmetric to cf-worker
- `add-observability/templates/openrouter-monitor/src/observability/index.ts` — D-01 byte-symmetric copy (D-21 contract from Phase 25)
- `add-observability/templates/ts-cloudflare-worker/env-additions.md` (and pages/supabase-edge variants) — D-01a operator wiring snippet
- `add-observability/templates/ts-cloudflare-worker/meta.yaml:116-120` — D-05 REDACTED_KEYS default expansion
- `add-observability/templates/ts-cloudflare-worker/policy.md.template` — D-05b policy.md template update
- `add-observability/templates/run-template-tests.sh:170,291,392` — D-03 harness pin sites (the heredoc package.jsons)

### Reference impls (don't touch — already correct)
- `add-observability/templates/ts-supabase-edge/destinations/sentry.ts:86` — TRACE_SAMPLE_RATE correctly wired (DEF-1 doesn't apply)
- `add-observability/templates/ts-react-vite/destinations/sentry.ts:81` — same (DEF-1 doesn't apply)

### Architectural context
- `add-observability/templates/ts-cloudflare-worker/destinations/sentry.ts:1-25` — explains why cf-worker can't call `Sentry.init` (v8 removed it; canonical setup is `withSentry(optionsFactory, handler)` at entry file) — foundational for D-01 design
- `docs/decisions/0029-with-cron-monitor-guarded-shape-a.md` — Phase 23 Guarded Shape A ADR (precedent for D-02 ADR shape)
- `docs/decisions/0030-openrouter-integration.md` — Phase 24 ADR (precedent for openrouter-monitor scope)
- `docs/decisions/0033-with-queue-monitor.md` — Phase 25 ADR (precedent for narrowed-scope ADRs)
- `CHANGELOG.md:1-50` — repo versioning convention (D-10 rationale source)

### Reference spec
- `migrations/README.md` §"Version semantics" — confirms patch-vs-minor-vs-major convention used in D-10/D-10a

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`AsyncLocalStorage<InternalSpanContext>`** at `lib-observability.ts:21,73` — already imported and used for span context. Reference pattern for D-02 (the alternative refactor we REJECTED — confirms it's feasible if Phase 27+ needs it).
- **Phase 25's `migrations/test-fixtures/0021/baselines/v1.19.0/` frozen-literal pattern (codex M-1)** — precedent for any new fixture files. D-06a fixture uses the same convention.
- **Phase 25 D-19 helper-export convention** (`export function buildMonitorConfig`, `export function isConfigured` from `cron-monitor.ts`) — naming + structural precedent for D-01's `observabilitySentryOptions` / `buildSentryOptions` helper.
- **Phase 24 `policy.md.template` consent-gate-1 pattern** — operator-facing policy.md content that the generator inlines into `lib-observability.ts`. D-05b updates this so default REDACTED_KEYS expansion ships to fresh applies via the standard consent gate.

### Established Patterns

- **Per-stack symmetry with carve-outs:** Phase 22/23/25 established that template edits apply symmetrically across `cf-worker`, `cf-pages`, `supabase-edge`, `openrouter-monitor` unless a runtime/SDK difference dictates a carve-out (codex H-3/H-6/H-7 patterns). Phase 26 follows: D-01 narrow to cf-worker+cf-pages+openrouter; D-05 broad to all 4; D-02 broad to all 4.
- **D-21 byte-symmetry contract:** openrouter-monitor's `src/observability/*.ts` stays byte-identical to cf-worker's wrapper files. D-01 edits both; verification step asserts `diff -q` returns empty post-execute.
- **Fixture frozen literals (codex M-1):** New fixtures (D-06a) use frozen literal `.ts` files under the fixture dir, NOT `cp` from mutable template sources. Avoids the fixture-breaks-on-template-edit class of bugs.
- **`/gsd-review` non-skippable (Workflow Commitment + ADR-0018):** Phase 25 proved codex catches structural issues that same-LLM plan-checker misses. Phase 26 MUST run `/gsd-review` after plan-checker PASS, before execute.

### Integration Points

- **Engine binary at `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`** — D-06's content-marker filter edits the engine that ships via the workflow scaffolder. Engine landing point: append to `_filter_index_ts_requires_co_anchor` body before the `printf '%s\n' "$f"` line.
- **`run-template-tests.sh` heredoc package.jsons** — D-03 edit sites. Three distinct heredocs (cf-worker, cf-pages, supabase-edge); each is self-contained. Tests run via `bash add-observability/templates/run-template-tests.sh <stack>` and verify exit 0.
- **`meta.yaml` REDACTED_KEYS default** — D-05 edit site. The `add-observability` generator reads from meta.yaml at INIT-time and inlines into the generated `policy.md` (consent gate 1). Operators who accept default policy.md inherit the broadened set; operators who customise their policy.md aren't disturbed.
- **`env-additions.md`** — D-01a edit site. Operator-facing wiring guide; expanding it with the `withSentry(env => observabilitySentryOptions(env), ...)` snippet is the only way DEF-1's fix actually reaches operator code paths.

</code_context>

<specifics>
## Specific Ideas

- **Helper export naming convention:** Match Phase 25 D-19's `buildMonitorConfig` shape — recommended `buildSentryOptions` or `observabilitySentryOptions` (planner picks). Both work; first is shorter and matches Phase 25's `build*` prefix.
- **Honest fail-fast:** D-07b removes the `exit 0` fallback from `0021/04 verify.sh`. The previous shape masked TS1038. Phase 26's discipline: if a fixture can't run its verification, FAIL — don't SKIP silently.
- **No spec-only docs unless they pull weight:** D-04a (optional `migrations/0022-worker-template-hardening.md`) is Claude's Discretion. The CHANGELOG entry is the canonical doc for template-only changes; a spec-only migration file would be discoverable-but-redundant.
- **D-21 byte-symmetry preserved:** `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` MUST return empty after D-01. This is the same contract Phase 25 established.

</specifics>

<deferred>
## Deferred Ideas

- **AsyncLocalStorage refactor of singletons** (Phase 27+ candidate): If a future Cloudflare runtime change (e.g., concurrent isolate invocations, or porting to Node/Deno hosting) breaks the current invariant ADR-0034 documents, this becomes the fix path. The Option B pattern from discuss is on file.
- **Per-request closure (explicit parameter) refactor** (Phase 27+ candidate): Most explicit, most testable, biggest API surface change. Reconsider if the codebase grows multi-runtime support.
- **Symmetric DEF-1 refactor for supabase-edge + react-vite**: If a future phase needs uniform DX across all stacks (one helper signature everywhere), revisit. Today these stacks wire correctly and don't need touching.
- **Migration 0022 with engine script**: If a future regression demands forcing fixes onto already-migrated projects (e.g., a security-critical REDACTED_KEYS update), 0021's re-rev-with-dirty-detection shape is the precedent. Phase 26's fixes don't meet that threshold.
- **Markdown lint cleanup batch** (Phase 27+ candidate or cleanup pass): The 10 CodeRabbit residuals in `.planning/phases/25-*/*.md` historical artifacts can be fixed in a single `markdownlint --fix` pass + audit if the project ever standardises on markdown linting as a CI gate. Today they're cosmetic in already-shipped docs.
- **Full retroactive ROADMAP/STATE/PROJECT bootstrap** (carry-forward from Phase 25 + earlier): Should land as its own phase before Phase 27 — current stubs are minimum enablers, not the full retro.
- **`FIX-0017-ENGINE.md` working-dir prompt**: Separate scope from Phase 26 (migration 0017 vs 0019/0021 + Phase 25 residuals); needs its own phase eventually.
- **gstack 1.48 → 1.52 upgrade** (operational, not a code-phase): Run `/gstack-upgrade` when convenient.
- **Untracked session noise triage** (cleanup pass): `.claude/`, `AGENTS.md`, `CLAUDE.md` (gstack-prompted), `.planning/config.json`, `add-observability/templates/openrouter-monitor/package-lock.json`, `add-observability/templates/{ts-cloudflare-{pages,worker}}/node_modules/`, `FIX-0017-ENGINE.md`. Phase 26 doesn't address these; future cleanup decides commit / gitignore / delete per item.

</deferred>

---

*Phase: 26-worker-template-hardening*
*Context gathered: 2026-06-01*
