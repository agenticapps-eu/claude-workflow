---
phase: 26
slug: worker-template-hardening
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-01
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `26-RESEARCH.md` §Validation Architecture; Wave 0 gaps must be closed before D-XX implementation tasks run.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (cf-worker / cf-pages)** | vitest (harness-ephemeral `npm install` in heredoc package.json) |
| **Framework (supabase-edge)** | `deno test -A --no-check $OBS_DIR/*.test.ts` (no npm) |
| **Framework (openrouter-monitor)** | vitest via tracked `package-lock.json` in `add-observability/templates/openrouter-monitor/` |
| **Framework (engine fixtures)** | bash dispatcher `migrations/run-tests.sh` over `migrations/test-fixtures/00XX/NN-*/` directories |
| **Quick run command (per stack)** | `bash add-observability/templates/run-template-tests.sh <stack>` |
| **Quick run command (engine fixtures)** | `bash migrations/run-tests.sh` (filterable by fixture name) |
| **Full suite command** | `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh` |
| **Byte-symmetry check** | `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` |
| **Estimated runtime** | ~60–120s (template stacks dominate; engine fixtures ~5–10s) |

---

## Sampling Rate

- **After every task commit:** Run the closest verify — `bash run-template-tests.sh <stack>` for template edits, `bash migrations/run-tests.sh` for engine/fixture edits.
- **After every plan wave:** Full suite + byte-symmetry diff.
- **Before `/gsd-verify-work`:** Full suite green, `diff -q` empty, every D-XX grep assertion satisfied.
- **Max feedback latency:** ~60s for affected stack, ~120s for full suite.

---

## Per-Decision Verification Map

> Each plan task addressing a decision must include the listed automated command in its `<acceptance_criteria>` (grep-verifiable or test-runner output).

| Decision | Plan (anticipated) | Wave | Behavior to verify | Test Type | Automated Command | Wave 0 File Exists | Status |
|----------|--------------------|------|--------------------|-----------|-------------------|--------------------|--------|
| D-01 export | 02 | 2 | `buildSentryOptions(env)` exported in cf-worker | grep | `grep -q "export function buildSentryOptions" add-observability/templates/ts-cloudflare-worker/lib-observability.ts` | n/a | ⬜ pending |
| D-01 cf-pages | 02 | 2 | helper present in cf-pages | grep | `grep -q "export function buildSentryOptions" add-observability/templates/ts-cloudflare-pages/lib-observability.ts` | n/a | ⬜ pending |
| D-01 openrouter | 02 | 2 | helper present in openrouter-monitor | grep | `grep -q "export function buildSentryOptions" add-observability/templates/openrouter-monitor/src/observability/index.ts` | n/a | ⬜ pending |
| D-01a env-additions | 02 | 2 | `## Sentry integration` subsection present in env-additions.md (cf-worker, cf-pages, openrouter) | grep | `grep -l "## Sentry integration" add-observability/templates/ts-cloudflare-worker/env-additions.md add-observability/templates/ts-cloudflare-pages/env-additions.md` → 2 hits | n/a | ⬜ pending |
| D-01c byte-symmetry | 02 (wave-final) | 2 | cf-worker ↔ openrouter byte-identical | diff | `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts` → exit 0, empty | n/a | ⬜ pending |
| D-02 ADR | 01 | 0 | ADR-0034 present | file | `test -f docs/decisions/0034-observability-init-singleton-invariant.md` | ❌ W0 task | ⬜ pending |
| D-02a idempotency (cf-worker) | 01 RED → 02 GREEN | 0 → 2 | new `describe("init() idempotency")` block PASS | vitest | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` exits 0 with "init() called twice within isolate yields deterministic singleton state" PASS | ❌ W0 stub | ⬜ pending |
| D-02a idempotency (cf-pages) | 01 RED → 02 GREEN | 0 → 2 | same | vitest | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-pages` | ❌ W0 stub | ⬜ pending |
| D-02a idempotency (supabase-edge) | 01 RED → 02 GREEN | 0 → 2 | same | deno test | `bash add-observability/templates/run-template-tests.sh ts-supabase-edge` | ❌ W0 stub | ⬜ pending |
| D-02a idempotency (openrouter) | 01 RED → 02 GREEN | 0 → 2 | same | vitest | `cd add-observability/templates/openrouter-monitor && npx vitest run` | ❌ W0 stub | ⬜ pending |
| D-03 vitest pin (3 sites) | 03 | 3 | `~3.2.4` present in cf-worker + cf-pages + ts-react-vite heredocs | grep | `grep -c '"vitest": "~3.2.4"' add-observability/templates/run-template-tests.sh` → 3 | n/a | ⬜ pending |
| D-03a sentry pin (2 sites) | 03 | 3 | `~8.55.0` in cf-worker + cf-pages heredocs | grep | `grep -c '"@sentry/cloudflare": "~8.55.0"' add-observability/templates/run-template-tests.sh` → 2 | n/a | ⬜ pending |
| D-03b policy comment | 03 | 3 | "Harness pins — re-bump deliberately" comment at top of harness | grep | `grep -q "Harness pins" add-observability/templates/run-template-tests.sh` | n/a | ⬜ pending |
| D-05 REDACTED_KEYS (5 stacks) | 02 | 2 | `authorization` present in 5 meta.yaml files | grep | `grep -l "authorization" add-observability/templates/*/meta.yaml \| wc -l` → 5 | n/a | ⬜ pending |
| D-05 additive | 02 | 2 | existing `card_number`/`ssn`/`cvv` STILL present (no regression) | grep | `grep -c "card_number" add-observability/templates/ts-cloudflare-worker/meta.yaml` ≥ 1 | n/a | ⬜ pending |
| D-05a Go substring | 02 | 2 | Go `redact` uses `strings.Contains` (verified pre-edit; ensure unchanged) | grep | `grep -q "strings.Contains" add-observability/templates/go-fly-http/observability.go` | n/a | ⬜ pending |
| D-05b policy.md.template (5 stacks) | 02 | 2 | `authorization` present in 5 `policy.md.template` files | grep | `grep -l "authorization" add-observability/templates/*/policy.md.template \| wc -l` → 5 | n/a | ⬜ pending |
| D-06 engine filter | 03 | 3 | content-marker regex injected into `_filter_index_ts_requires_co_anchor` | grep | `awk '/_filter_index_ts_requires_co_anchor/,/^_/' templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh \| grep -qE "observability\|withObservability\|sentry"` | n/a | ⬜ pending |
| D-06a fixture 13 setup | 01 | 0 | fixture dir + setup.sh + verify.sh present | file | `test -d migrations/test-fixtures/0019/13-index-ts-without-observability-content && test -f migrations/test-fixtures/0019/13-index-ts-without-observability-content/verify.sh` | ❌ W0 task | ⬜ pending |
| D-06a dispatcher entry | 01 | 0 | fixture 13 reachable from dispatcher | bash | `bash migrations/run-tests.sh 2>&1 \| grep -q "13-index-ts-without-observability-content"` | ❌ W0 task | ⬜ pending |
| D-06a fixture 13 RED→GREEN | 01 RED → 03 GREEN | 0 → 3 | fixture 13 GREEN post-D-06 (was RED on Wave 0) | bash | `bash migrations/run-tests.sh` exits 0 with "✓ 13-index-ts-without-observability-content" | ❌ W0 RED, 03 GREEN | ⬜ pending |
| D-06a no-patch assertion | 01 (verify.sh) | 0 | fixture verify asserts no `.observability-0019.patch` emitted | bash | within fixture verify.sh: `test ! -e "$WORKDIR/.observability-0019.patch"` | ❌ W0 task | ⬜ pending |
| D-07a TS1038 removed | 03 | 3 | no `declare const console` inside `declare global` | grep | `grep -q "declare const console" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts` → exit 1 | n/a | ⬜ pending |
| D-07a canonical pattern | 03 | 3 | `interface Console` + `declare var console: Console` present | grep | `grep -q "interface Console" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts && grep -q "declare var console: Console" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts` | n/a | ⬜ pending |
| D-07b exit-0 removed | 03 | 3 | no `exit 0` fallback in `0021/04/verify.sh` | grep | `grep -c "exit 0" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh` → 0 | n/a | ⬜ pending |
| D-07b honest fail | 03 | 3 | npx-missing emits explicit error string | grep | `grep -q "fixture 0021/04 FAIL — npx required" migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/verify.sh` | n/a | ⬜ pending |
| D-07 fixture green | 03 | 3 | full regression — fixture 04 still GREEN post-fix | bash | `bash migrations/run-tests.sh` exits 0 with "✓ 04-callbot-shape-strict-env-typecheck" | n/a | ⬜ pending |
| D-08 .gitignore presence | 02 | 2 | new `.gitignore` files in 4 stacks (excluding openrouter-monitor which already has one) | find | `find add-observability/templates -maxdepth 2 -name .gitignore -not -path "*/openrouter-monitor/*" \| wc -l` ≥ 4 | n/a | ⬜ pending |
| D-08a provenance header | 02 | 2 | each new `.gitignore` cites Phase 24 or Phase 26 | grep | `grep -l "Phase 2[46]" add-observability/templates/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge,ts-react-vite,go-fly-http}/.gitignore \| wc -l` ≥ 4 | n/a | ⬜ pending |
| D-10 version (add-observability) | 03 | 3 | CHANGELOG has 0.10.0 entry | grep | `grep -c "^## \[0\.10\.0\]" add-observability/CHANGELOG.md` ≥ 1 | n/a | ⬜ pending |
| D-10a version (root) | 03 | 3 | root CHANGELOG has 1.20.1 entry | grep | `grep -c "^## \[1\.20\.1\]" CHANGELOG.md` ≥ 1 | n/a | ⬜ pending |

*Status legend: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements (must exist before Wave 2/3 implementation)

- [ ] `docs/decisions/0034-observability-init-singleton-invariant.md` — ADR-0034 (verify ID is free at task execution; if taken, slot up to next free)
- [ ] `migrations/test-fixtures/0019/13-index-ts-without-observability-content/setup.sh` — seeds vanilla Hono `src/index.ts` + `src/middleware.ts` (no observability content)
- [ ] `migrations/test-fixtures/0019/13-index-ts-without-observability-content/verify.sh` — asserts SKIP_UNSUPPORTED + no `.observability-0019.patch` emitted
- [ ] `migrations/test-fixtures/0019/13-index-ts-without-observability-content/expected-exit` — exit-code expectation file (per fixture convention)
- [ ] Dispatcher entry in `migrations/run-tests.sh` for fixture 13 (verify auto-discovery first; add explicit entry only if needed)
- [ ] `add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts` — new `describe("D-02 singleton idempotency")` RED block
- [ ] `add-observability/templates/ts-cloudflare-pages/lib-observability.test.ts` — same RED block
- [ ] `add-observability/templates/ts-supabase-edge/lib-observability.test.ts` (or `index.test.ts` — planner verifies) — RED block (Deno test shape)
- [ ] `add-observability/templates/openrouter-monitor/src/observability/index.test.ts` — RED block (must stay byte-symmetric to cf-worker test once D-01c contract extends to test files — planner verifies whether the symmetry contract covers tests)

**Wave 0 RED-verification:** Before Wave 2 starts, the following commands MUST report failures (RED state):
- `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` → idempotency test fails (no `buildSentryOptions` yet)
- `bash migrations/run-tests.sh` → fixture 13 fails (engine filter not yet updated)

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| ADR-0034 narrative correctness | D-02 | Prose review — requires human judgment that singleton invariant is articulated correctly and Cloudflare-isolate model is accurately summarized | Read `docs/decisions/0034-*.md` end-to-end; confirm follows ADR-0029/0030/0033 shape and explicitly cites "isolate-per-invocation"; sign off in PR review |
| env-additions.md operator wiring snippet quality | D-01a | Prose + code-snippet review — operator-facing doc must be unambiguous about the `withSentry(env => buildSentryOptions(env), handler)` pattern | Read each updated `env-additions.md`; confirm snippet present, runnable, and matches actual helper signature |
| CHANGELOG upgrade-note clarity (T1 mitigation) | D-10 | Prose review — must clearly state operators with existing `policy.md` should review REDACTED_KEYS | Read `add-observability/CHANGELOG.md` 0.10.0 entry; confirm UPGRADE NOTE present |
| D-08 provenance header phrasing | D-08a | Prose review — confirm citation is accurate (Phase 24 precedent, Phase 26 extension) | Read each new `.gitignore` header; confirm Phase 24 / Phase 26 cited |

---

## Validation Sign-Off

- [ ] All D-XX decisions have an automated grep / diff / test-runner verification in the table above
- [ ] Wave 0 RED state confirmed before Wave 2 starts (idempotency tests + fixture 13 FAIL)
- [ ] Wave 2 GREEN state for D-01 / D-02a / D-05 / D-05b / D-08
- [ ] Wave 3 GREEN state for D-03 / D-06 / D-07 / D-10 / D-10a
- [ ] Byte-symmetry diff returns empty after Wave 2 closes
- [ ] Full suite green: `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh`
- [ ] Manual review items signed off in PR
- [ ] `nyquist_compliant: true` set in this file's frontmatter

**Approval:** pending
