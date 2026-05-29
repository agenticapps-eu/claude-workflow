# Phase 22 — Sentry Crons + healthz: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `claude-workflow` v1.18.0 with three deliverables — (1) optional `withCronMonitor` / `WithCronMonitor` wrapper across 4 stacks, (2) per-stack `healthz-snippet.{ts,go}` copy-only templates, (3) operator runbook for Sentry Crons + Uptime configuration — installable on existing v1.17.0 projects via additive migration 0019.

**Architecture:** Each stack gains a NEW file for `withCronMonitor` (`cron-monitor.{ts,go}`) and a NEW file for the healthz snippet (`healthz-snippet.{ts,go}`). No existing v0.5.1 export is touched. Cron checkins fire as `captureCheckIn` events; slug resolution is 3-source (explicit > env > auto-derived). Healthz returns 200/503 with per-check breakdown and is NOT routed through `withObservability` (Decision D in CONTEXT.md). Migration 0019 splices the new files into materialized projects via content-hash-checked apply engine mirroring 0017's pattern.

**Tech Stack:** TypeScript 5.x (Vitest 3.x runner) for worker/pages/supabase-edge; Go 1.21+ for go-fly-http; bash for the migration apply engine; existing `migrations/run-tests.sh` + `add-observability/templates/run-template-tests.sh` harnesses.

**CONTEXT.md**: `.planning/phases/22-sentry-crons-healthz/CONTEXT.md` (locked design — Goals G1–G8, Decisions D1–D12).

---

## REVISIONS — post REVIEWS.md (binding; supersedes body where conflict exists)

> The multi-AI plan review (`.planning/phases/22-sentry-crons-healthz/22-REVIEWS.md`) surfaced 5 HIGH + 7 MEDIUM verified inconsistencies on 2026-05-29. Codex's claims were checked against the actual repo state. The following 11 revisions are **binding for execution**. Where a revision conflicts with task text below, the revision wins. Original task text is retained for context.

### R01 — T01 simplification: drop supabase-edge and go-fly-http copy lines
**OLD (T01 Step 3):** Add 4 `substitute_tokens` lines inside `test_go_fly_http()` for `cron_monitor.{go,_test.go}` + `healthz_snippet.{go,_test.go}`. Plus 4 lines inside `test_ts_supabase_edge()`.
**NEW (binding):** Skip both. `add-observability/templates/run-template-tests.sh` line 434 already globs `for f in "$SRC"/*.test.ts; do substitute_tokens "$f" ...` for supabase-edge (covers all `*.ts` source files via the adjacent loop), and line 513 globs `*.go` for the Go stack. **T01 modifies only `test_ts_cloudflare_worker()` and `test_ts_cloudflare_pages()`** — 4 explicit copy lines each, no existence-gating because these are the only paths that don't already glob. Plan length saved: ~30 lines.

### R02 — Remove existence-gated copy lines entirely
**OLD (T01 Step 5):** Wrap each new `substitute_tokens` call with `[[ -f "$SRC/file" ]] && substitute_tokens ...`.
**NEW (binding):** Do NOT add existence gates. T01 lands AFTER the first cron-monitor file exists in worker (commit ordering: T02 step 1 RED commit lands BEFORE T01). Either:
- **Option A (recommended):** Reorder — T02 RED for worker lands first as commit 4, then T01 runner extension as commit 5. The runner extension references files that already exist.
- **Option B:** Bundle T01 + T02-RED into a single combined commit ("test+infra: enable cron-monitor test discovery").

Existence-gated copies were codex's foot-gun concern (silent skips on misspelled files). Eliminating the gate eliminates the foot-gun.

### R03 — T02 / T03 / T04 / T05 implementations forward `monitorConfig` (schedule + maxRuntimeSeconds) on in_progress checkin
**OLD (T02 Step 4 impl):** `captureCheckIn({ monitorSlug, status: "in_progress" })`.
**NEW (binding):** When `config?.schedule` OR `config?.maxRuntimeSeconds` is set, pass them as Sentry's `monitorConfig` 2nd arg ONLY on the in_progress checkin:
```ts
const monitorConfig = (config?.schedule || config?.maxRuntimeSeconds)
  ? { schedule: config?.schedule, maxRuntime: config?.maxRuntimeSeconds }
  : undefined;
checkInId = captureCheckIn(
  { monitorSlug, status: "in_progress" },
  monitorConfig,  // 2nd arg per Sentry SDK contract — UPSERTS monitor config in UI
) as string;
```
Subsequent `ok`/`error` checkins pass only the first arg. Add 1 new test per stack ("forwards monitorConfig on in_progress, omits on completion") asserting the 2nd-arg shape via `vi.mocked(captureCheckIn).mock.calls[0][1]` (and Go equivalent). Resolves CONTEXT N5/D12 from "claimed but dead field" to actually-forwarded. Source: <https://docs.sentry.io/platforms/javascript/guides/koa/configuration/draining/>.

### R04 — T02 / T03 / T04 / T05 add opt-in `SENTRY_DEBUG=1` console-log in catch blocks
**OLD (T02 Step 4 impl):** `try { captureCheckIn(...) } catch { /* swallow */ }`.
**NEW (binding):** Surface swallowed errors when `SENTRY_DEBUG=1`:
```ts
try { captureCheckIn(...); } catch (e) {
  if (env.SENTRY_DEBUG === "1" || (globalThis as any).process?.env?.SENTRY_DEBUG === "1") {
    console.error("[withCronMonitor] captureCheckIn threw:", e);
  }
}
```
Go equivalent uses `os.Getenv("SENTRY_DEBUG") == "1"`. Add 1 test per stack ("logs swallowed errors when SENTRY_DEBUG=1, silent otherwise"). Addresses gemini's LOW concern about silent heartbeat failures.

### R05 — T05 Go `captureCheckinFn` return type is `*sentry.EventID`, not `sentry.EventID`
**OLD (T05 Step 4 impl):** `var captureCheckinFn = func(checkIn *sentry.CheckIn) sentry.EventID { return sentry.CaptureCheckIn(checkIn, nil) }`.
**NEW (binding):** Per [pkg.go.dev sentry-go](https://pkg.go.dev/github.com/getsentry/sentry-go), `sentry.CaptureCheckIn` returns `*sentry.EventID`. Update:
```go
var captureCheckinFn = func(checkIn *sentry.CheckIn, monitorConfig *sentry.MonitorConfig) *sentry.EventID {
  return sentry.CaptureCheckIn(checkIn, monitorConfig)
}
```
Helper file's `capturedCheckin.ID` field type becomes `*sentry.EventID`. Stub returns a non-nil pointer (`id := sentry.EventID("stub-id"); return &id`). Add code comment: `// Tests using this seam MUST NOT use t.Parallel() — captureCheckinFn is package-level.`

### R06 — T06 / T07 / T08 / T09 healthz fail-closed on zero configured probes
**OLD (T06 Step 3 impl):** `const allOk = Object.values(checks).every(Boolean); return new Response(JSON.stringify({ status: allOk ? "ok" : "degraded", checks }), { status: allOk ? 200 : 503, ... });`.
**NEW (binding):** Empty `checks` map MUST fail-closed:
```ts
const probeNames = Object.keys(checks);
if (probeNames.length === 0) {
  return new Response(
    JSON.stringify({ status: "degraded", reason: "no probes configured — adapt healthz-snippet.ts to your dependencies", checks: {} }),
    { status: 503, headers: { "content-type": "application/json" } },
  );
}
const allOk = probeNames.every((k) => checks[k]);
// ... rest unchanged
```
Go equivalent: `if len(checks) == 0 { ... allOK=false; ... }`. Add 1 test per stack ("returns 503 with `reason: no probes configured` when no deps wired"). Addresses BOTH gemini's "permanent degraded" AND codex's "200-on-empty false-green" concerns.

### R07 — T06 / T07 / T08 / T09 top-of-file comment promoted to multi-line WARNING block
**OLD:** Single comment line `// Copy this file into your routes layer...`.
**NEW (binding):** Multi-line block:
```ts
//
// ╔════════════════════════════════════════════════════════════════════╗
// ║ WARNING — healthz snippet is a TEMPLATE, not a library.            ║
// ║                                                                    ║
// ║ Before mounting:                                                   ║
// ║  1. Copy this file into your routes layer (e.g. routes/healthz.ts) ║
// ║  2. ADAPT the dependency probes to YOUR project's actual bindings. ║
// ║     Unadapted probes for non-existent deps will report degraded.   ║
// ║     Zero probes configured → endpoint returns 503 (fail-closed).   ║
// ║  3. Review SECURITY: per-check breakdown leaks internal topology.  ║
// ║     For public endpoints, consider `?detail=true` opt-in (T14      ║
// ║     runbook describes the gating pattern).                         ║
// ║                                                                    ║
// ║ Do NOT import this file directly from elsewhere in your app.       ║
// ╚════════════════════════════════════════════════════════════════════╝
```
Apply across all 4 healthz snippets (worker/pages/supabase-edge/go-fly-http; Go uses `//` comment lines without the box-drawing characters or with them — at executor discretion).

### R08 — T10 apply engine is 2-pass: classify → all-clean gate → apply (mirror 0017)
**OLD (T10 Step 2 sketch):** Single `for wrapper_dir in "${WRAPPER_DIRS[@]}"; do ... copy_new_files ...; done` loop.
**NEW (binding):** Mirror `templates/.claude/scripts/migrate-0017-axiom-destination.sh` lines 305+. Pass 1 classifies every root as `CLEAN | DIRTY | ALREADY | UNSUPPORTED`; pass 2 only runs if `DIRTY_DIRS` is empty (all-clean gate). If any dirty, refuse atomically — emit `.observability-0019.patch` for each clean dir that would have been applied, exit non-zero, NO files written:
```bash
# Pass 1 — classify
declare -a CLEAN_DIRS=() CLEAN_STACKS=()
declare -a DIRTY_DIRS=() ALREADY_DIRS=() UNSUPPORTED_DIRS=()
for wrapper_dir in "${WRAPPER_DIRS[@]}"; do
  stack=$(detect_stack "$wrapper_dir")
  case "$stack" in
    ts-react-vite) ALREADY_DIRS+=("$wrapper_dir") ; continue ;;
    unknown) UNSUPPORTED_DIRS+=("$wrapper_dir") ; continue ;;
  esac
  if [ -f "$wrapper_dir/cron-monitor.ts" ] || [ -f "$wrapper_dir/cron_monitor.go" ]; then
    ALREADY_DIRS+=("$wrapper_dir") ; continue
  fi
  if is_known_clean_wrapper "$wrapper_dir" "$stack"; then
    CLEAN_DIRS+=("$wrapper_dir"); CLEAN_STACKS+=("$stack")
  else
    DIRTY_DIRS+=("$wrapper_dir")
  fi
done

# All-clean gate
if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  for d in "${DIRTY_DIRS[@]}"; do emit_patch_for "$d" ; done
  log_refuse "$DIRTY_DIRS"
  exit 1
fi

# Pass 2 — apply
for i in "${!CLEAN_DIRS[@]}"; do
  copy_new_files "${CLEAN_DIRS[$i]}" "${CLEAN_STACKS[$i]}"
done
```
Restores the atomic property 0017 was hardened around.

### R09 — T11 add fixture 06: mixed clean+dirty multi-root proves atomic refusal
**OLD (T11):** 5 fixtures (`01-fresh-apply` ... `05-multi-module-root`).
**NEW (binding):** Add `migrations/test-fixtures/0019/06-mixed-clean-dirty-refuses-all/`:
- `setup.sh`: materializes 2 clean v1.17.0 wrappers + 1 hand-modified wrapper in the same project root.
- `expected-exit`: non-zero.
- `verify.sh`: asserts NONE of the 3 wrappers got `cron-monitor.ts` created — proves atomic refusal. Also asserts `.observability-0019.patch` files exist for the 2 clean dirs (their would-be diffs were emitted), confirming operator can re-attempt after manually addressing the dirty wrapper.

Plus add fixture `07-react-vite-only/`: project with only ts-react-vite stack present; expected-exit `0`; verify.sh asserts no files written and stdout includes "no eligible stacks". (Codex's dedicated react-vite-only path concern.)

### R10 — T14 runbook adds "Security & Public Exposure" section
**OLD (T14 outline):** 3 sections (Crons setup / Uptime setup / policy.md cross-link).
**NEW (binding):** Add 4th section "Part 4 — Security & Public Exposure" covering:
- `/healthz` endpoint info-disclosure risk when public-exposed (per-check breakdown reveals internal topology).
- Recommended mitigation: gate per-check breakdown behind `?detail=true` query param, default response is `{"status":"ok"}` or `{"status":"degraded"}` only.
- Optional split into `/healthz` (always 200 while alive — shallow) vs `/readyz` (deep deps — internal-only).
- Sentry Uptime probe authentication: if `/healthz` is auth-gated, configure the probe with a long-lived Bearer token in Sentry's "Headers" config.

### R11 — T17 byte-identical reframed from "git diff main" to "diff filename allowlist"
**OLD (T17 Step 2):** `git diff main -- [list of existing wrapper files] ; Expected: NO output.`
**NEW (binding):** Use a filename allowlist that asserts the diff includes ONLY new files + the version bumps + CHANGELOG + ADR + INIT.md + runbook:
```bash
ALLOWED=(
  add-observability/templates/'*/cron-monitor.ts'
  add-observability/templates/'*/cron_monitor.go'
  add-observability/templates/'*/cron_monitor_test.go'
  add-observability/templates/'*/cron-monitor.test.ts'
  add-observability/templates/'*/healthz-snippet.ts'
  add-observability/templates/'*/healthz_snippet.go'
  add-observability/templates/'*/healthz-snippet.test.ts'
  add-observability/templates/'*/healthz_snippet_test.go'
  add-observability/templates/run-template-tests.sh
  add-observability/init/INIT.md
  add-observability/uptime-setup-runbook.md
  add-observability/SKILL.md
  skill/SKILL.md
  migrations/0019-sentry-crons-and-healthz.md
  migrations/run-tests.sh
  migrations/test-fixtures/0019/
  templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh
  docs/decisions/0028-sentry-crons-healthz-conventions.md
  CHANGELOG.md
  .planning/phases/22-sentry-crons-healthz/
)
git diff --name-only main..HEAD | while read f; do
  ok=0; for p in "${ALLOWED[@]}"; do [[ "$f" == $p ]] && { ok=1; break; }; done
  [ "$ok" = 1 ] || { echo "DISALLOWED: $f"; exit 1; }
done
# AND: assert existing v0.5.1 wrapper files are NOT in the changed-files set:
git diff --name-only main..HEAD | grep -E "(lib-observability\.ts|^.*/middleware\.ts$|^.*/_middleware\.ts$|^.*/middleware\.go$|^.*/observability\.go$|^.*/index\.ts$|^.*/destinations.*\.(ts|go)$)" && exit 1
```
Less brittle than byte-equal; honors the actual constraint (no edits to existing wrapper files).

### R12 — NEW T18: post-completion cleanup (existence gates removed; export presence asserted)
After T17 passes:
- Remove any existence-gated copy lines left in `run-template-tests.sh` (per R02 they should never have landed, but verify).
- Add an assertion to T16's Step 4 that `grep -rl "withCronMonitor" add-observability/templates/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge}/cron-monitor.ts && grep -rl "WithCronMonitor" add-observability/templates/go-fly-http/cron_monitor.go` returns all 4 expected files.

Commit message: `chore(phase-22): T18 post-completion guardrails (export presence + no existence gates)`.

---

## File structure

### New files

| Path | Purpose |
|---|---|
| `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` | `withCronMonitor` + `CronMonitorConfig` + slug resolver |
| `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` | 3 cron tests + 1 slug-precedence test |
| `add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts` | Copy-only KV + Service-Binding healthz handler |
| `add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts` | 200/503 contract test |
| `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts` | `withCronMonitor` (generic async fn shape) |
| `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts` | 3 cron tests + 1 slug-precedence test |
| `add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts` | Copy-only Pages-Function healthz at `functions/healthz.ts` |
| `add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts` | 200/503 contract test |
| `add-observability/templates/ts-supabase-edge/cron-monitor.ts` | `withCronMonitor` (Deno Request→Response shape) |
| `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts` | 3 cron tests + 1 slug-precedence test |
| `add-observability/templates/ts-supabase-edge/healthz-snippet.ts` | Copy-only `SELECT 1` healthz handler |
| `add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts` | 200/503 contract test |
| `add-observability/templates/go-fly-http/cron_monitor.go` | `WithCronMonitor(ctx, slug, fn) error` helper |
| `add-observability/templates/go-fly-http/cron_monitor_test.go` | 3 cron tests + 1 slug-precedence test |
| `add-observability/templates/go-fly-http/healthz_snippet.go` | Copy-only DB-ping + downstream-HTTP-probe handler |
| `add-observability/templates/go-fly-http/healthz_snippet_test.go` | 200/503 contract test |
| `add-observability/uptime-setup-runbook.md` | Operator runbook (~150 lines) |
| `migrations/0019-sentry-crons-and-healthz.md` | Migration metadata + procedure |
| `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | Apply engine (mirrors 0017's structure) |
| `migrations/test-fixtures/0019/01-fresh-apply/` | `setup.sh` + `expected-exit` + `verify.sh` |
| `migrations/test-fixtures/0019/02-already-applied/` | Same triplet |
| `migrations/test-fixtures/0019/03-hand-modified-refuse/` | Same triplet |
| `migrations/test-fixtures/0019/04-no-scheduled-handlers-project/` | Same triplet |
| `migrations/test-fixtures/0019/05-multi-module-root/` | Same triplet |
| `docs/decisions/0028-sentry-crons-healthz-conventions.md` | ADR |

### Modified files

| Path | Change |
|---|---|
| `add-observability/templates/run-template-tests.sh` | Copy `cron-monitor.test.ts` + `healthz-snippet.test.ts` (TS stacks); copy `cron_monitor_test.go` + `healthz_snippet_test.go` (Go stack); package.json scripts unchanged |
| `add-observability/init/INIT.md` | Phase 5 detail per-stack: document `withSentry(withObservabilityScheduled(withCronMonitor(handler)))` composition where applicable; healthz copy-instruction added to Phase 8 |
| `migrations/run-tests.sh` | Add `test_migration_0019()` function + invoke it in the run loop |
| `skill/SKILL.md` | `version: 1.17.0` → `1.18.0` (applied as part of T17, **NOT** inside migration 0019 apply — bumped in source so a fresh install ships at 1.18.0) |
| `add-observability/SKILL.md` | `version: 0.5.1` → `0.6.0` (same rationale) |
| `CHANGELOG.md` | New `## [1.18.0] — 2026-05-29` section |

---

## Task list

Tasks T02–T05 (cron monitor) and T06–T09 (healthz) execute per-stack and are independent within their group. T10–T13 (migration) depend on T02–T09. T14–T17 (docs + version) depend on T10–T13. T18 is the integration smoke gate.

### T01: Extend template test runner to pick up new test files

**Files:**
- Modify: `add-observability/templates/run-template-tests.sh`

Without this task, vitest/`go test` won't discover the new `cron-monitor.test.ts` / `healthz-snippet.test.ts` / `cron_monitor_test.go` / `healthz_snippet_test.go` files because the runner explicitly maps named files (e.g. `substitute_tokens "$SRC/lib-observability.test.ts" "$OBS_DIR/index.test.ts"`).

- [ ] **Step 1: Read the existing copy block for `ts-cloudflare-worker`** to identify the per-stack handler function.

Run: `grep -nE "test_ts_cloudflare_worker|copy.*test.ts|substitute_tokens" add-observability/templates/run-template-tests.sh | head -20`

Expected: locates the per-stack copy site (around lines 125–135 per earlier exploration) and the function boundary.

- [ ] **Step 2: For each TS stack handler (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`), add two lines after the existing `lib-observability.test.ts` copy line.** Pattern, with `$OBS_DIR` already-defined per stack:

```bash
# add-observability/templates/run-template-tests.sh — inside test_ts_cloudflare_worker()
substitute_tokens "$SRC/cron-monitor.ts"        "$OBS_DIR/cron-monitor.ts"
substitute_tokens "$SRC/cron-monitor.test.ts"   "$OBS_DIR/cron-monitor.test.ts"
substitute_tokens "$SRC/healthz-snippet.ts"     "$OBS_DIR/healthz-snippet.ts"
substitute_tokens "$SRC/healthz-snippet.test.ts" "$OBS_DIR/healthz-snippet.test.ts"
```

Apply the same four-line block inside `test_ts_cloudflare_pages()` and `test_ts_supabase_edge()`, targeting each stack's materialized obs dir.

- [ ] **Step 3: For `test_go_fly_http()`, add two lines for the Go pair.**

```bash
substitute_tokens "$SRC/cron_monitor.go"      "$WORKDIR/internal/observability/cron_monitor.go"
substitute_tokens "$SRC/cron_monitor_test.go" "$WORKDIR/internal/observability/cron_monitor_test.go"
substitute_tokens "$SRC/healthz_snippet.go"      "$WORKDIR/internal/observability/healthz_snippet.go"
substitute_tokens "$SRC/healthz_snippet_test.go" "$WORKDIR/internal/observability/healthz_snippet_test.go"
```

(Verify the exact `$WORKDIR/internal/observability/...` path against the existing Go copy lines — adopt whatever the existing block uses.)

- [ ] **Step 4: For `ts-react-vite`, do NOT add copy lines** — react-vite is browser-only and gets neither cron nor healthz per Decision D10.

- [ ] **Step 5: Re-run the suite to confirm the changes don't break existing tests (new files don't exist yet, so the copy should fail or no-op gracefully).** Wrap each new `substitute_tokens` call with an existence check:

```bash
[[ -f "$SRC/cron-monitor.test.ts" ]] && substitute_tokens "$SRC/cron-monitor.test.ts" "$OBS_DIR/cron-monitor.test.ts"
```

This lets the runner stay green between T01 and T02 (the files don't exist yet during the interim commit).

> ⚠️ **Superseded by R12 (T18 guardrails).** The existence-gated `substitute_tokens` lines shown above were the original RED-state safety net. Binding revision R12 — and the T18 post-completion guardrails commit (`47659ec`) — removed them in favour of unconditional copies after the source files landed in T02. The annotation here preserves the historical "what was originally planned" record; do not re-introduce existence gates when re-executing this plan. See `22-REVIEWS.md` R12 for the binding rationale.

- [ ] **Step 6: Run the suite to confirm green baseline preserved.**

Run: `bash add-observability/templates/run-template-tests.sh all 2>&1 | tail -5`

Expected: `PASS All stacks passed` with the same 170 test count as the pre-T01 baseline.

- [ ] **Step 7: Commit.**

```bash
git add add-observability/templates/run-template-tests.sh
git commit -m "feat(add-observability): test runner copies cron + healthz files

T01 of phase 22. Extends per-stack test_*() functions to copy the new
cron-monitor.{ts,go} / healthz-snippet.{ts,go} files (and their
*.test.{ts,go} pairs) into the materialized work dir so vitest / go
test discover them. Existence-gated so the runner stays green between
this commit and T02 (files don't exist yet).

ts-react-vite intentionally skipped — browser bundle, no cron/healthz
per Decision D10 in CONTEXT.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### T02: `withCronMonitor` for `ts-cloudflare-worker` (TDD: RED then GREEN)

**Files:**
- Create: `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts`
- Create: `add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts`

The worker is the reference stack — its tests + implementation are written in full here; T03–T04 reference back to this as the template pattern.

- [ ] **Step 1: Write the failing test file (RED commit).**

```typescript
// add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { withCronMonitor } from "./cron-monitor";

// Sentry SDK is mocked at the module boundary — the cron-monitor module
// imports `Sentry.captureCheckIn` from `@sentry/cloudflare`, so we stub it.
const captureCheckIn = vi.fn();
vi.mock("@sentry/cloudflare", () => ({
  captureCheckIn: (...args: unknown[]) => captureCheckIn(...args),
}));

const fakeController = { scheduledTime: 0, cron: "*/15 * * * *" } as ScheduledController;
const fakeCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;

beforeEach(() => {
  captureCheckIn.mockReset();
  captureCheckIn.mockReturnValueOnce("checkin-abc"); // 1st call returns checkInId
});

describe("withCronMonitor", () => {
  it("emits in_progress + ok on happy path", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withCronMonitor(handler, { monitorSlug: "fxsa-ingest-15min" });
    await wrapped(fakeController, { SENTRY_DSN: "https://stub@sentry.io/1" }, fakeCtx);

    expect(handler).toHaveBeenCalledOnce();
    expect(captureCheckIn).toHaveBeenCalledTimes(2);
    expect(captureCheckIn).toHaveBeenNthCalledWith(1, { monitorSlug: "fxsa-ingest-15min", status: "in_progress" });
    expect(captureCheckIn).toHaveBeenNthCalledWith(2, { checkInId: "checkin-abc", monitorSlug: "fxsa-ingest-15min", status: "ok" });
  });

  it("emits in_progress + error and re-throws on handler exception", async () => {
    const boom = new Error("handler exploded");
    const handler = vi.fn(async () => { throw boom; });
    const wrapped = withCronMonitor(handler, { monitorSlug: "fxsa-ingest-15min" });

    await expect(wrapped(fakeController, { SENTRY_DSN: "https://stub@sentry.io/1" }, fakeCtx)).rejects.toBe(boom);

    expect(captureCheckIn).toHaveBeenCalledTimes(2);
    expect(captureCheckIn).toHaveBeenNthCalledWith(1, { monitorSlug: "fxsa-ingest-15min", status: "in_progress" });
    expect(captureCheckIn).toHaveBeenNthCalledWith(2, { checkInId: "checkin-abc", monitorSlug: "fxsa-ingest-15min", status: "error" });
  });

  it("no-ops cleanly when SENTRY_DSN is unset", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withCronMonitor(handler, { monitorSlug: "fxsa-ingest-15min" });

    await wrapped(fakeController, {} as Record<string, unknown>, fakeCtx);

    expect(handler).toHaveBeenCalledOnce();
    expect(captureCheckIn).not.toHaveBeenCalled();
  });

  describe("slug resolution", () => {
    it("uses explicit config.monitorSlug above all sources", async () => {
      const handler = vi.fn(async () => {});
      const wrapped = withCronMonitor(handler, { monitorSlug: "explicit-wins" });

      await wrapped(fakeController, {
        SENTRY_DSN: "https://stub@sentry.io/1",
        SENTRY_CRON_MONITOR_SLUG_SCHEDULED: "env-loses",
        SERVICE_NAME: "auto-loses",
      } as Record<string, unknown>, fakeCtx);

      expect(captureCheckIn).toHaveBeenNthCalledWith(1, expect.objectContaining({ monitorSlug: "explicit-wins" }));
    });

    it("falls back to SENTRY_CRON_MONITOR_SLUG_<handler> env when explicit absent", async () => {
      const handler = vi.fn(async () => {});
      const wrapped = withCronMonitor(handler); // no explicit slug

      await wrapped(fakeController, {
        SENTRY_DSN: "https://stub@sentry.io/1",
        SENTRY_CRON_MONITOR_SLUG_SCHEDULED: "env-wins",
        SERVICE_NAME: "auto-loses",
      } as Record<string, unknown>, fakeCtx);

      expect(captureCheckIn).toHaveBeenNthCalledWith(1, expect.objectContaining({ monitorSlug: "env-wins" }));
    });

    it("falls back to auto-derived ${SERVICE_NAME}:${controller.cron} when neither set", async () => {
      const handler = vi.fn(async () => {});
      const wrapped = withCronMonitor(handler);

      await wrapped(fakeController, {
        SENTRY_DSN: "https://stub@sentry.io/1",
        SERVICE_NAME: "fxsa-worker",
      } as Record<string, unknown>, fakeCtx);

      expect(captureCheckIn).toHaveBeenNthCalledWith(1, expect.objectContaining({ monitorSlug: "fxsa-worker:*/15 * * * *" }));
    });
  });
});
```

- [ ] **Step 2: Run vitest to confirm RED.** The implementation file doesn't exist yet — vitest should fail at the import resolution step.

Run: `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker 2>&1 | tail -20`

Expected: FAIL — `Failed to resolve import "./cron-monitor"` or `Cannot find module`. Confirms the test wires up correctly.

- [ ] **Step 3: Commit the RED.**

```bash
git add add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts
git commit -m "test(worker): RED — withCronMonitor cron + slug-resolution tests

T02/1 of phase 22. 3 cron behavioral tests (happy, error+rethrow, no-DSN
no-op) + 3 slug-precedence tests (explicit > env > auto). Confirms
captureCheckIn invocation contract and the 3-source slug resolution from
CONTEXT D6. Implementation lands in next commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 4: Write the implementation file (GREEN commit).**

```typescript
// add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
//
// withCronMonitor — Sentry Crons heartbeat wrapper for Cloudflare Worker
// scheduled handlers. Composes INNERMOST in the chain:
//   withSentry(env)(withObservabilityScheduled(withCronMonitor(handler, {...})))
//
// Fail-safe: when SENTRY_DSN is unset (isConfigured() false), zero checkins
// fire and the handler runs unchanged. Matches the v0.5.x wrapper contract.

import { captureCheckIn } from "@sentry/cloudflare";

export interface CronMonitorConfig {
  monitorSlug?: string;
  schedule?: { type: "crontab" | "interval"; value: string };
  maxRuntimeSeconds?: number;
}

type ScheduledFn<E> = (
  controller: ScheduledController,
  env: E,
  ctx: ExecutionContext,
) => void | Promise<void>;

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && env.SENTRY_DSN.length > 0;
}

function resolveSlug<E extends Record<string, unknown>>(
  config: CronMonitorConfig | undefined,
  env: E,
  controller: ScheduledController,
  handlerName: string = "scheduled",
): string {
  if (config?.monitorSlug) return config.monitorSlug;

  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = env[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;

  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  const cronExpr = controller.cron || "scheduled";
  return `${serviceName}:${cronExpr}`;
}

export function withCronMonitor<E extends Record<string, unknown>>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E> {
  return async (controller, env, ctx) => {
    if (!isConfigured(env)) {
      await handler(controller, env, ctx);
      return;
    }

    const monitorSlug = resolveSlug(config, env, controller);
    let checkInId: string | undefined;
    try {
      checkInId = captureCheckIn({ monitorSlug, status: "in_progress" }) as string;
    } catch {
      // Sentry SDK threw during checkin emission — swallow + run handler.
      // Cron heartbeat is not in the critical path.
    }

    try {
      await handler(controller, env, ctx);
      if (checkInId !== undefined) {
        try { captureCheckIn({ checkInId, monitorSlug, status: "ok" }); } catch { /* swallow */ }
      }
    } catch (err) {
      if (checkInId !== undefined) {
        try { captureCheckIn({ checkInId, monitorSlug, status: "error" }); } catch { /* swallow */ }
      }
      throw err;
    }
  };
}
```

- [ ] **Step 5: Run vitest to confirm GREEN.**

Run: `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker 2>&1 | tail -10`

Expected: `PASS [ts-cloudflare-worker] 51 tests passed` (45 prior + 6 new — 3 cron + 3 slug-precedence).

- [ ] **Step 6: Commit the GREEN.**

```bash
git add add-observability/templates/ts-cloudflare-worker/cron-monitor.ts
git commit -m "feat(worker): GREEN — withCronMonitor implementation

T02/2 of phase 22. Implements the cron-heartbeat wrapper per CONTEXT
Decisions D1 (separate wrapper), D5 (innermost composition), D6 (3-source
slug resolution), and fail-safe-on-no-DSN. Sentry checkin emission is
wrapped in try/swallow so an SDK throw during captureCheckIn doesn't
break the cron — heartbeat is not in the critical path.

All 6 new tests pass; existing 45 worker tests unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### T03: `withCronMonitor` for `ts-cloudflare-pages` (TDD: RED then GREEN)

**Files:**
- Create: `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts`
- Create: `add-observability/templates/ts-cloudflare-pages/cron-monitor.test.ts`

**Deltas from T02:**
- Pages has no `ScheduledController` — the wrapper takes a generic async fn `() => Promise<R>` so an operator wrapping cron-like work (e.g. a Pages Function that's externally triggered by a Workflow or Worker on cron) can use it.
- Slug resolution drops the controller-cron fallback; auto-derived slug becomes `${SERVICE_NAME}:scheduled`.
- Env shape: Pages env is `Record<string, unknown>` per Pages Functions context.env.

- [ ] **Step 1: Write `cron-monitor.test.ts`** mirroring T02's tests with these substitutions:
  - Remove the `fakeController` / `fakeCtx` setup; the wrapper signature is `<R>(handler: () => Promise<R>, config?, env?: Record<string, unknown>) => () => Promise<R>` — env is passed as the third arg because Pages env isn't ambient.
  - In the auto-derive test, assert the slug becomes `"fxsa-pages:scheduled"` (no cron expr available).
  - Drop the SENTRY_CRON_MONITOR_SLUG_SCHEDULED env var convention test since Pages uses a single handler name; instead use `handlerName: "ingest-15min"` arg → env key `SENTRY_CRON_MONITOR_SLUG_INGEST_15MIN`.

```typescript
// Skeleton of the env-fallback test (full file mirrors T02 with env arg):
it("falls back to SENTRY_CRON_MONITOR_SLUG_<handler> env", async () => {
  const handler = vi.fn(async () => {});
  const wrapped = withCronMonitor(handler, { handlerName: "ingest-15min" });
  const env = { SENTRY_DSN: "https://stub@sentry.io/1", SENTRY_CRON_MONITOR_SLUG_INGEST_15MIN: "env-wins" };
  await wrapped(env);
  expect(captureCheckIn).toHaveBeenNthCalledWith(1, expect.objectContaining({ monitorSlug: "env-wins" }));
});
```

- [ ] **Step 2: Run vitest → RED, commit RED.**

Run: `bash add-observability/templates/run-template-tests.sh ts-cloudflare-pages 2>&1 | tail -10`. Expected: FAIL on `./cron-monitor` import resolution.

Commit message: `test(pages): RED — withCronMonitor (generic async-fn shape) tests`.

- [ ] **Step 3: Write `cron-monitor.ts`** with the generic-fn signature:

```typescript
import { captureCheckIn } from "@sentry/cloudflare";

export interface CronMonitorConfig {
  monitorSlug?: string;
  handlerName?: string;
  schedule?: { type: "crontab" | "interval"; value: string };
  maxRuntimeSeconds?: number;
}

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && env.SENTRY_DSN.length > 0;
}

function resolveSlug(config: CronMonitorConfig | undefined, env: Record<string, unknown>): string {
  if (config?.monitorSlug) return config.monitorSlug;
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = env[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;
  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  return `${serviceName}:${handlerName}`;
}

export function withCronMonitor<R>(
  handler: () => Promise<R>,
  config?: CronMonitorConfig,
): (env: Record<string, unknown>) => Promise<R> {
  return async (env) => {
    if (!isConfigured(env)) return handler();
    const monitorSlug = resolveSlug(config, env);
    let checkInId: string | undefined;
    try { checkInId = captureCheckIn({ monitorSlug, status: "in_progress" }) as string; } catch {}
    try {
      const result = await handler();
      if (checkInId !== undefined) { try { captureCheckIn({ checkInId, monitorSlug, status: "ok" }); } catch {} }
      return result;
    } catch (err) {
      if (checkInId !== undefined) { try { captureCheckIn({ checkInId, monitorSlug, status: "error" }); } catch {} }
      throw err;
    }
  };
}
```

- [ ] **Step 4: Run vitest → GREEN, commit GREEN.**

Run: `bash add-observability/templates/run-template-tests.sh ts-cloudflare-pages 2>&1 | tail -10`. Expected: `PASS [ts-cloudflare-pages] 37 tests passed` (31 prior + 6 new).

Commit message: `feat(pages): GREEN — withCronMonitor (generic async-fn) implementation`.

---

### T04: `withCronMonitor` for `ts-supabase-edge` (TDD: RED then GREEN)

**Files:**
- Create: `add-observability/templates/ts-supabase-edge/cron-monitor.ts`
- Create: `add-observability/templates/ts-supabase-edge/cron-monitor.test.ts`

**Deltas from T02:**
- Wrapper signature is `(handler: (req: Request) => Promise<Response>, config?) => (req: Request) => Promise<Response>` — Supabase Edge functions are Deno-style Request→Response handlers, called by `pg_cron` via HTTP.
- The wrapper reads env via `Deno.env.get()` per the existing pattern (look at `index.ts`'s init function for the reference). Test stubs `globalThis.Deno = { env: { get: (k) => stubMap[k] } }`.
- Sentry import: this stack uses `@sentry/deno` per the existing destinations adapter — verify the actual import path against `destinations/sentry.ts` and mirror.
- Auto-derived slug: `${SERVICE_NAME}:scheduled` (no controller).

- [ ] **Step 1: Read `add-observability/templates/ts-supabase-edge/destinations/sentry.ts`** to identify the actual Sentry import path the stack uses.

Run: `head -30 add-observability/templates/ts-supabase-edge/destinations/sentry.ts`

Expected: shows the `import { ... } from "..."` for Sentry. Use the same import in `cron-monitor.ts`.

- [ ] **Step 2: Write `cron-monitor.test.ts`** with Deno env stub and Request→Response handler signature. Mirror T02's 6 tests; the `fakeController` is replaced with `new Request("https://stub/cron")` and the wrapped fn is invoked with the request.

```typescript
beforeEach(() => {
  captureCheckIn.mockReset();
  captureCheckIn.mockReturnValueOnce("checkin-abc");
  (globalThis as any).Deno = { env: { get: (k: string) => stubEnv[k] } };
});

it("emits in_progress + ok on happy path", async () => {
  stubEnv = { SENTRY_DSN: "https://stub@sentry.io/1" };
  const handler = vi.fn(async () => new Response("ok"));
  const wrapped = withCronMonitor(handler, { monitorSlug: "callbot-sweep" });
  const res = await wrapped(new Request("https://stub/cron"));
  expect(res.status).toBe(200);
  expect(captureCheckIn).toHaveBeenCalledTimes(2);
});
```

- [ ] **Step 3: Run vitest → RED, commit RED.**

Commit message: `test(supabase-edge): RED — withCronMonitor (Deno Request handler) tests`.

- [ ] **Step 4: Write `cron-monitor.ts`** using `Deno.env.get` for env access:

```typescript
import * as Sentry from "@sentry/deno"; // VERIFY against destinations/sentry.ts; mirror exactly.

export interface CronMonitorConfig {
  monitorSlug?: string;
  handlerName?: string;
  schedule?: { type: "crontab" | "interval"; value: string };
  maxRuntimeSeconds?: number;
}

const SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";

function denoEnv(key: string): string | undefined {
  try { return (globalThis as any).Deno?.env?.get(key); } catch { return undefined; }
}

function isConfigured(): boolean {
  const dsn = denoEnv("SENTRY_DSN");
  return typeof dsn === "string" && dsn.length > 0;
}

function resolveSlug(config?: CronMonitorConfig): string {
  if (config?.monitorSlug) return config.monitorSlug;
  const handlerName = config?.handlerName ?? "scheduled";
  const envKey = SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = denoEnv(envKey);
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;
  const serviceName = denoEnv("SERVICE_NAME") ?? "service";
  return `${serviceName}:${handlerName}`;
}

export function withCronMonitor(
  handler: (req: Request) => Promise<Response>,
  config?: CronMonitorConfig,
): (req: Request) => Promise<Response> {
  return async (req) => {
    if (!isConfigured()) return handler(req);
    const monitorSlug = resolveSlug(config);
    let checkInId: string | undefined;
    try { checkInId = Sentry.captureCheckIn({ monitorSlug, status: "in_progress" }) as string; } catch {}
    try {
      const res = await handler(req);
      if (checkInId !== undefined) { try { Sentry.captureCheckIn({ checkInId, monitorSlug, status: "ok" }); } catch {} }
      return res;
    } catch (err) {
      if (checkInId !== undefined) { try { Sentry.captureCheckIn({ checkInId, monitorSlug, status: "error" }); } catch {} }
      throw err;
    }
  };
}
```

- [ ] **Step 5: Run vitest → GREEN, commit GREEN.**

Run: `bash add-observability/templates/run-template-tests.sh ts-supabase-edge 2>&1 | tail -10`. Expected: `PASS [ts-supabase-edge] 32 tests passed` (26 prior + 6 new).

Commit message: `feat(supabase-edge): GREEN — withCronMonitor (Deno Request) implementation`.

---

### T05: `WithCronMonitor` for `go-fly-http` (TDD: RED then GREEN)

**Files:**
- Create: `add-observability/templates/go-fly-http/cron_monitor.go`
- Create: `add-observability/templates/go-fly-http/cron_monitor_test.go`

**Signature:** `func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error`.

- [ ] **Step 1: Read `add-observability/templates/go-fly-http/destinations.go`** for the Sentry import path and checkin API the Go stack uses.

Run: `grep -nE "captureCheckIn|CaptureCheckIn|sentry" add-observability/templates/go-fly-http/destinations.go | head -10`

Expected: shows `github.com/getsentry/sentry-go` or similar; mirror the exact import.

- [ ] **Step 2: Write `cron_monitor_test.go`** with 3 cron tests + 3 slug-precedence tests. Use `t.Setenv` for env injection; stub Sentry via a package-level var override pattern (the existing `observability_test.go` likely does this — read it for the convention).

```go
// add-observability/templates/go-fly-http/cron_monitor_test.go
package observability

import (
	"context"
	"errors"
	"testing"
)

func TestWithCronMonitorEmitsCheckinsOnHappyPath(t *testing.T) {
	t.Setenv("SENTRY_DSN", "https://stub@sentry.io/1")
	calls := captureCheckinStub(t) // helper installs a stub on the sentry shim

	err := WithCronMonitor(context.Background(), func() error { return nil },
		WithMonitorSlug("fxsa-go-cron"))

	if err != nil { t.Fatalf("unexpected error: %v", err) }
	if len(calls) != 2 { t.Fatalf("expected 2 checkins, got %d", len(calls)) }
	if calls[0].Status != "in_progress" { t.Errorf("first checkin status = %q, want in_progress", calls[0].Status) }
	if calls[1].Status != "ok" { t.Errorf("second checkin status = %q, want ok", calls[1].Status) }
}

func TestWithCronMonitorEmitsErrorAndReturnsOriginal(t *testing.T) {
	t.Setenv("SENTRY_DSN", "https://stub@sentry.io/1")
	calls := captureCheckinStub(t)
	boom := errors.New("handler exploded")

	err := WithCronMonitor(context.Background(), func() error { return boom },
		WithMonitorSlug("fxsa-go-cron"))

	if !errors.Is(err, boom) { t.Fatalf("expected original error, got %v", err) }
	if len(calls) != 2 || calls[1].Status != "error" {
		t.Fatalf("expected in_progress+error, got %+v", calls)
	}
}

func TestWithCronMonitorNoopsWhenDSNUnset(t *testing.T) {
	t.Setenv("SENTRY_DSN", "")
	calls := captureCheckinStub(t)
	ran := false
	err := WithCronMonitor(context.Background(), func() error { ran = true; return nil })
	if err != nil { t.Fatalf("unexpected error: %v", err) }
	if !ran { t.Fatal("handler did not run") }
	if len(calls) != 0 { t.Fatalf("expected 0 checkins, got %d", len(calls)) }
}

func TestSlugExplicitOverridesEnv(t *testing.T) {
	t.Setenv("SENTRY_DSN", "https://stub@sentry.io/1")
	t.Setenv("SENTRY_CRON_MONITOR_SLUG_SCHEDULED", "env-loses")
	t.Setenv("SERVICE_NAME", "auto-loses")
	calls := captureCheckinStub(t)
	_ = WithCronMonitor(context.Background(), func() error { return nil }, WithMonitorSlug("explicit-wins"))
	if calls[0].MonitorSlug != "explicit-wins" { t.Errorf("got slug %q", calls[0].MonitorSlug) }
}

func TestSlugEnvOverridesAuto(t *testing.T) {
	t.Setenv("SENTRY_DSN", "https://stub@sentry.io/1")
	t.Setenv("SENTRY_CRON_MONITOR_SLUG_SCHEDULED", "env-wins")
	t.Setenv("SERVICE_NAME", "auto-loses")
	calls := captureCheckinStub(t)
	_ = WithCronMonitor(context.Background(), func() error { return nil })
	if calls[0].MonitorSlug != "env-wins" { t.Errorf("got slug %q", calls[0].MonitorSlug) }
}

func TestSlugAutoDerivesFromServiceName(t *testing.T) {
	t.Setenv("SENTRY_DSN", "https://stub@sentry.io/1")
	t.Setenv("SERVICE_NAME", "fxsa-go")
	calls := captureCheckinStub(t)
	_ = WithCronMonitor(context.Background(), func() error { return nil })
	if calls[0].MonitorSlug != "fxsa-go:scheduled" { t.Errorf("got slug %q", calls[0].MonitorSlug) }
}
```

- [ ] **Step 3: Run go test → RED, commit RED.**

Run: `bash add-observability/templates/run-template-tests.sh go-fly-http 2>&1 | tail -10`.
Expected: FAIL — `undefined: WithCronMonitor` and `undefined: captureCheckinStub`.

Commit message: `test(go): RED — WithCronMonitor cron + slug tests`.

- [ ] **Step 4: Write `cron_monitor.go`** with the Functional Options pattern + Sentry stub hook:

```go
// add-observability/templates/go-fly-http/cron_monitor.go
package observability

import (
	"context"
	"os"
	"strings"

	sentry "github.com/getsentry/sentry-go" // VERIFY mirror against destinations.go
)

// CronMonitorOption configures WithCronMonitor.
type CronMonitorOption func(*cronMonitorConfig)

type cronMonitorConfig struct {
	monitorSlug       string
	handlerName       string
	maxRuntimeSeconds int
}

func WithMonitorSlug(slug string) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.monitorSlug = slug }
}

func WithHandlerName(name string) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.handlerName = name }
}

func WithMaxRuntimeSeconds(s int) CronMonitorOption {
	return func(c *cronMonitorConfig) { c.maxRuntimeSeconds = s }
}

// captureCheckinFn is a package-level seam so tests can swap a stub.
// Default implementation calls Sentry; tests override via captureCheckinStub.
var captureCheckinFn = func(checkIn *sentry.CheckIn) sentry.EventID {
	return sentry.CaptureCheckIn(checkIn, nil)
}

func resolveCronSlug(c *cronMonitorConfig) string {
	if c.monitorSlug != "" { return c.monitorSlug }
	handlerName := c.handlerName
	if handlerName == "" { handlerName = "scheduled" }
	envKey := "SENTRY_CRON_MONITOR_SLUG_" + strings.ReplaceAll(strings.ToUpper(handlerName), "-", "_")
	if v := os.Getenv(envKey); v != "" { return v }
	svc := os.Getenv("SERVICE_NAME")
	if svc == "" { svc = "service" }
	return svc + ":" + handlerName
}

func cronIsConfigured() bool { return os.Getenv("SENTRY_DSN") != "" }

func WithCronMonitor(ctx context.Context, fn func() error, opts ...CronMonitorOption) error {
	cfg := &cronMonitorConfig{}
	for _, opt := range opts { opt(cfg) }

	if !cronIsConfigured() { return fn() }

	slug := resolveCronSlug(cfg)
	inProgress := &sentry.CheckIn{ MonitorSlug: slug, Status: sentry.CheckInStatusInProgress }
	checkInID := safeCaptureCheckin(inProgress)

	err := fn()
	if err != nil {
		if checkInID != "" {
			safeCaptureCheckin(&sentry.CheckIn{ ID: checkInID, MonitorSlug: slug, Status: sentry.CheckInStatusError })
		}
		return err
	}
	if checkInID != "" {
		safeCaptureCheckin(&sentry.CheckIn{ ID: checkInID, MonitorSlug: slug, Status: sentry.CheckInStatusOK })
	}
	return nil
}

func safeCaptureCheckin(c *sentry.CheckIn) sentry.EventID {
	defer func() { _ = recover() }() // swallow SDK panics
	return captureCheckinFn(c)
}
```

- [ ] **Step 5: Add `captureCheckinStub` helper to a test-helpers file** so tests can capture the checkin payloads:

```go
// add-observability/templates/go-fly-http/cron_monitor_test_helpers_test.go
package observability

import (
	"testing"
	sentry "github.com/getsentry/sentry-go"
)

type capturedCheckin struct {
	ID          sentry.EventID
	MonitorSlug string
	Status      sentry.CheckInStatus
}

func captureCheckinStub(t *testing.T) *[]capturedCheckin {
	t.Helper()
	calls := &[]capturedCheckin{}
	prev := captureCheckinFn
	captureCheckinFn = func(c *sentry.CheckIn) sentry.EventID {
		id := sentry.EventID("stub-id")
		*calls = append(*calls, capturedCheckin{ID: id, MonitorSlug: c.MonitorSlug, Status: c.Status})
		return id
	}
	t.Cleanup(func() { captureCheckinFn = prev })
	return calls
}
```

Update tests to deref the returned `*[]capturedCheckin` (`calls := *captureCheckinStub(t)` → `(*calls)[0].MonitorSlug`).

- [ ] **Step 6: Run go test → GREEN, commit GREEN.**

Run: `bash add-observability/templates/run-template-tests.sh go-fly-http 2>&1 | tail -10`. Expected: `PASS [go-fly-http] 31 tests passed` (25 prior + 6 new).

Commit message: `feat(go): GREEN — WithCronMonitor implementation`.

---

### T06: healthz snippet for `ts-cloudflare-worker`

**Files:**
- Create: `add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts`
- Create: `add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts`

- [ ] **Step 1: Write the failing test.**

```typescript
// add-observability/templates/ts-cloudflare-worker/healthz-snippet.test.ts
import { describe, it, expect, vi } from "vitest";
import { healthzHandler } from "./healthz-snippet";

describe("healthzHandler", () => {
  it("returns 200 status:ok when all checks pass", async () => {
    const env = {
      OBSERVABILITY_KV: { get: vi.fn().mockResolvedValue(null) },
      SERVICE_BINDING: { fetch: vi.fn().mockResolvedValue(new Response("ok", { status: 200 })) },
    };
    const res = await healthzHandler(new Request("https://stub/healthz"), env);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ status: "ok", checks: { kv: true, serviceBinding: true } });
  });

  it("returns 503 status:degraded with per-check breakdown when a dep fails", async () => {
    const env = {
      OBSERVABILITY_KV: { get: vi.fn().mockRejectedValue(new Error("kv down")) },
      SERVICE_BINDING: { fetch: vi.fn().mockResolvedValue(new Response("ok", { status: 200 })) },
    };
    const res = await healthzHandler(new Request("https://stub/healthz"), env);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body).toEqual({ status: "degraded", checks: { kv: false, serviceBinding: true } });
  });
});
```

- [ ] **Step 2: Run vitest → RED, commit.**

Commit message: `test(worker): RED — healthz snippet 200/503 contract`.

- [ ] **Step 3: Write the implementation.**

```typescript
// add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts
//
// Copy this file into your routes layer at e.g. `src/routes/healthz.ts`,
// adapt the dependency probes to your actual bindings, and wire it into
// your fetch router so Sentry Uptime can probe `/healthz`. Do NOT import
// this snippet directly — it is a template, not a library.
//
// Contract:
//   200 {"status":"ok",       "checks": {...}}  all probes succeeded
//   503 {"status":"degraded", "checks": {...}}  at least one probe failed
//
// This handler is intentionally NOT wrapped by `withObservability` —
// /healthz hits from Uptime probes (1-15min × N regions) would crowd
// Sentry's transaction view with noise. See CONTEXT D4.

export interface HealthzEnv {
  OBSERVABILITY_KV?: { get: (key: string) => Promise<string | null> };
  SERVICE_BINDING?: { fetch: (req: Request) => Promise<Response> };
}

export async function healthzHandler(_req: Request, env: HealthzEnv): Promise<Response> {
  const checks: Record<string, boolean> = {};

  if (env.OBSERVABILITY_KV) {
    try { await env.OBSERVABILITY_KV.get("healthz-probe"); checks.kv = true; }
    catch { checks.kv = false; }
  }

  if (env.SERVICE_BINDING) {
    try {
      const res = await env.SERVICE_BINDING.fetch(new Request("https://internal/healthz"));
      checks.serviceBinding = res.status < 500;
    } catch { checks.serviceBinding = false; }
  }

  const allOk = Object.values(checks).every(Boolean);
  return new Response(
    JSON.stringify({ status: allOk ? "ok" : "degraded", checks }),
    { status: allOk ? 200 : 503, headers: { "content-type": "application/json" } },
  );
}
```

- [ ] **Step 4: Run vitest → GREEN, commit.**

Commit message: `feat(worker): GREEN — healthz snippet (KV + service-binding probes)`.

---

### T07: healthz snippet for `ts-cloudflare-pages`

**Files:**
- Create: `add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts`
- Create: `add-observability/templates/ts-cloudflare-pages/healthz-snippet.test.ts`

**Deltas from T06:**
- Pages Functions signature: `export const onRequest: PagesFunction<Env> = async (context) => {...}` — the snippet exports `onRequest` directly, not a `healthzHandler` factory. Top comment instructs copying to `functions/healthz.ts`.
- Probes: KV ping (same as worker) + `DB?.prepare("SELECT 1").first()` if D1 bound.

Test pattern mirrors T06 with `onRequest({ env, request: new Request("https://stub/healthz") })` invocation. RED → commit → implementation → GREEN → commit (same shape).

Commit messages: `test(pages): RED — healthz snippet contract` / `feat(pages): GREEN — healthz snippet (KV + D1 probes)`.

---

### T08: healthz snippet for `ts-supabase-edge`

**Files:**
- Create: `add-observability/templates/ts-supabase-edge/healthz-snippet.ts`
- Create: `add-observability/templates/ts-supabase-edge/healthz-snippet.test.ts`

**Deltas from T06:**
- Deno-style handler: `export default async (_req: Request): Promise<Response>`
- Probe: `SELECT 1` via the Supabase client. The snippet takes a `supabase: { rpc: ..., from: ... }` factory arg so the test can inject a stub.

Test mirrors T06 with `supabase.from("_healthz").select("1").limit(0)` stub. Commit messages: `test(supabase-edge): RED — healthz snippet contract` / `feat(supabase-edge): GREEN — healthz snippet (SELECT 1 probe)`.

---

### T09: healthz snippet for `go-fly-http`

**Files:**
- Create: `add-observability/templates/go-fly-http/healthz_snippet.go`
- Create: `add-observability/templates/go-fly-http/healthz_snippet_test.go`

**Shape:**

```go
// add-observability/templates/go-fly-http/healthz_snippet.go
//
// Copy this file into your routes layer (e.g. internal/routes/healthz.go),
// adapt the dependency probes, and mount on your mux. Do NOT import this
// snippet directly — it is a template, not a library.
package observability

import (
	"context"
	"encoding/json"
	"net/http"
	"time"
)

type HealthzDeps struct {
	DB       interface{ PingContext(context.Context) error }
	Upstream interface{ Get(string) (*http.Response, error) }
}

func HealthzHandler(deps HealthzDeps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		checks := map[string]bool{}
		if deps.DB != nil {
			checks["db"] = deps.DB.PingContext(ctx) == nil
		}
		if deps.Upstream != nil {
			res, err := deps.Upstream.Get("https://internal/healthz")
			checks["upstream"] = err == nil && res != nil && res.StatusCode < 500
		}

		allOK := true
		for _, ok := range checks { if !ok { allOK = false; break } }

		status := "ok"; code := http.StatusOK
		if !allOK { status = "degraded"; code = http.StatusServiceUnavailable }

		w.Header().Set("content-type", "application/json")
		w.WriteHeader(code)
		_ = json.NewEncoder(w).Encode(map[string]any{"status": status, "checks": checks})
	}
}
```

Tests: stub `DB` and `Upstream` interfaces, assert response code + body shape. RED → commit → GREEN → commit. Commit messages: `test(go): RED — healthz snippet contract` / `feat(go): GREEN — healthz snippet (DB+upstream probes)`.

---

### T10: Migration 0019 markdown + apply engine

**Files:**
- Create: `migrations/0019-sentry-crons-and-healthz.md`
- Create: `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`

The MD file is documentation; the .sh file is the executable apply engine that materialized projects run.

- [ ] **Step 1: Write `migrations/0019-sentry-crons-and-healthz.md`.** Mirror the frontmatter shape of `migrations/0018-postphase-observability-hook.md`. Body sections: Pre-flight, Idempotency, Hand-modified refuse, Apply, Post-checks, Skip cases.

Frontmatter:

```yaml
---
id: 0019
slug: sentry-crons-and-healthz
title: Sentry Crons heartbeats (withCronMonitor) + /healthz convention
from_version: 1.17.0
to_version: 1.18.0
applies_to:
  - <wrapper-dir>/cron-monitor.{ts,go}          # newly added
  - <wrapper-dir>/healthz-snippet.{ts,go}       # newly added; copy-only
  - <wrapper-dir>/middleware.{ts,go}            # NO change — wrapper interface frozen
  - CLAUDE.md observability block               # NO change
optional_for:
  - projects without scheduled handlers (cparx-shape — wrapper still applies; exports just unused)
  - ts-react-vite-only projects (full skip; nothing to do)
---
```

Body sections (~120 lines) document the 6 steps. Cross-link to ADR-0028.

- [ ] **Step 2: Write `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`.** Mirror the structural skeleton of `templates/.claude/scripts/migrate-0017-axiom-destination.sh` — same flag parsing, same logging conventions, same hand-modified-detection (content-hash with style-insensitive canonicalization). DIFFERENCES from 0017:
  - No CLAUDE.md `observability:` block rewrite (D9 in CONTEXT — 0019 doesn't touch metadata).
  - Detect "already applied" by `grep -q "export function withCronMonitor" <wrapper>/cron-monitor.ts`.
  - For each detected wrapper dir, copy the four new files (`cron-monitor.{ts,go}`, `healthz-snippet.{ts,go}`) from the scaffolder source.
  - For react-vite-only projects, log "no eligible stacks; skipping" and exit 0.

Skeleton (read 0017's script for the full conventions before writing):

```bash
#!/usr/bin/env bash
# migrate-0019-sentry-crons-and-healthz.sh
# Adopt withCronMonitor + healthz-snippet on existing v0.5.x wrappers.
set -euo pipefail

# Mirror 0017's flag parsing + logging conventions exactly.
# ...

# For each materialised wrapper found in the project:
for wrapper_dir in "${WRAPPER_DIRS[@]}"; do
  stack=$(detect_stack "$wrapper_dir")
  case "$stack" in
    ts-react-vite) log "skip $wrapper_dir (react-vite — no cron/healthz)" ; continue ;;
    *) ;;
  esac

  if grep -q "export function withCronMonitor\|func WithCronMonitor" "$wrapper_dir"/* 2>/dev/null; then
    log "skip $wrapper_dir (already has withCronMonitor)"
    continue
  fi

  # Hand-modified detection: canonicalize existing middleware files,
  # compare hash against known v1.17.0 hashes. If hash mismatches, refuse.
  if ! is_known_clean_wrapper "$wrapper_dir" "$stack"; then
    refuse_with_patch "$wrapper_dir" "$stack"
    continue
  fi

  copy_new_files "$wrapper_dir" "$stack"  # cron-monitor + healthz-snippet
done
```

Commit message (for the pair): `feat(migrations): 0019 — withCronMonitor + healthz adoption (1.17.0 → 1.18.0)`.

---

### T11: Migration 0019 test fixtures (5 cases)

**Files:**
- Create: `migrations/test-fixtures/0019/01-fresh-apply/{setup.sh,expected-exit,verify.sh}`
- Create: `migrations/test-fixtures/0019/02-already-applied/{setup.sh,expected-exit,verify.sh}`
- Create: `migrations/test-fixtures/0019/03-hand-modified-refuse/{setup.sh,expected-exit,verify.sh}`
- Create: `migrations/test-fixtures/0019/04-no-scheduled-handlers-project/{setup.sh,expected-exit,verify.sh}`
- Create: `migrations/test-fixtures/0019/05-multi-module-root/{setup.sh,expected-exit,verify.sh}`

Read `migrations/test-fixtures/0018/01-needs-apply/{setup.sh,verify.sh}` and `migrations/test-fixtures/0017/*/setup.sh` for the harness conventions before writing.

- [ ] **Step 1: 01-fresh-apply** — `setup.sh` materializes a clean v1.17.0 worker wrapper; `expected-exit` is `0`; `verify.sh` asserts `cron-monitor.ts` + `healthz-snippet.ts` exist in the wrapper dir and contain the expected exports.

```bash
# migrations/test-fixtures/0019/01-fresh-apply/setup.sh
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$1"
mkdir -p "$PROJECT_DIR/.claude/observability"
# Copy a known-clean v1.17.0 worker wrapper into the project (use the same
# fixture-seeding pattern 0017's setup.sh uses).
cp -r "$REPO_ROOT/migrations/test-fixtures/_seeds/v1.17.0-worker/." "$PROJECT_DIR/.claude/observability/"
```

```bash
# migrations/test-fixtures/0019/01-fresh-apply/verify.sh
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$1"
WRAPPER="$PROJECT_DIR/.claude/observability"
test -f "$WRAPPER/cron-monitor.ts" || { echo "FAIL: cron-monitor.ts missing"; exit 1; }
test -f "$WRAPPER/healthz-snippet.ts" || { echo "FAIL: healthz-snippet.ts missing"; exit 1; }
grep -q "export function withCronMonitor" "$WRAPPER/cron-monitor.ts" || { echo "FAIL: withCronMonitor not exported"; exit 1; }
echo "PASS"
```

(Note: `_seeds/` may not exist — if not, inline the wrapper file content directly in `setup.sh`. Follow whatever 0017 does.)

- [ ] **Step 2: 02-already-applied** — `setup.sh` materializes a wrapper that already has `cron-monitor.ts`; `expected-exit` is `0` (idempotency); `verify.sh` asserts the file wasn't overwritten (record + check the original mtime/content hash).

- [ ] **Step 3: 03-hand-modified-refuse** — `setup.sh` materializes a wrapper but mutates `middleware.ts` (e.g. injects a comment); `expected-exit` is non-zero (refuse); `verify.sh` asserts `cron-monitor.ts` was NOT created (no partial apply) AND a `.observability-0019.patch` file was generated with the would-be diff.

- [ ] **Step 4: 04-no-scheduled-handlers-project** — `setup.sh` materializes a cparx-shape project (worker, no scheduled trigger configured); `expected-exit` is `0` (still applies; the exports are opt-in); `verify.sh` asserts files exist.

- [ ] **Step 5: 05-multi-module-root** — `setup.sh` materializes an fxsa-shape root with 3 worker wrapper dirs + 1 react-vite wrapper dir; `expected-exit` is `0`; `verify.sh` asserts all 3 worker dirs got the new files AND the react-vite dir did NOT.

Commit: `test(migrations): 0019 fixtures — fresh / idempotent / refuse / cparx / fxsa`.

---

### T12: Wire migration 0019 into `migrations/run-tests.sh`

**Files:**
- Modify: `migrations/run-tests.sh`

- [ ] **Step 1: Read the existing `test_migration_0018()` function** to mirror its structure.

Run: `grep -nE "test_migration_0018|test_migration_0017" migrations/run-tests.sh | head -5`

- [ ] **Step 2: Write `test_migration_0019()` immediately after `test_migration_0018()`.** It iterates the 5 fixtures, runs `setup.sh` to a temp project, invokes the apply engine, checks exit code against `expected-exit`, runs `verify.sh`. Mirror 0018's pattern verbatim.

- [ ] **Step 3: Invoke `test_migration_0019()` in the main run loop** (find where 0018 is invoked and add 0019 right after).

- [ ] **Step 4: Run the full suite.**

Run: `bash migrations/run-tests.sh 2>&1 | tail -8`

Expected: `PASS: 171+N` where N = 5 (one per fixture, each contributing 1 PASS line in the canonical reporting). If 0017/0018 fixtures produce >1 line each, adjust accordingly. The critical assertion: `FAIL: 0`.

- [ ] **Step 5: Commit.**

Commit message: `test(migrations): wire 0019 into run-tests.sh — 5 fixtures green`.

---

### T13: `init/INIT.md` Phase 5 + Phase 8 updates

**Files:**
- Modify: `add-observability/init/INIT.md`

- [ ] **Step 1: Locate Phase 5 detail subsections per stack.**

Run: `grep -nE "^#### Phase 5 detail" add-observability/init/INIT.md`

Expected: 5 subsection headers (one per stack).

- [ ] **Step 2: For `ts-cloudflare-worker`, `ts-supabase-edge` subsections, add a paragraph** documenting the composition order:

```markdown
**Composition with `withCronMonitor` (optional, v1.18.0+):** When you also import the optional `withCronMonitor` export, wrap your scheduled handler as:

    withSentry(env)(
      withObservabilityScheduled(
        withCronMonitor(scheduledHandler, { monitorSlug: "<slug>" })
      )
    )

`withCronMonitor` MUST be the innermost wrapper so its try/catch fires before `withObservabilityScheduled`'s span/scope cleanup. See `add-observability/uptime-setup-runbook.md` for slug configuration.
```

- [ ] **Step 3: For `ts-cloudflare-pages` subsection, add a paragraph** noting Pages Functions don't have scheduled handlers but `withCronMonitor` can wrap any async function the operator triggers externally (e.g. via a parallel Worker on cron).

- [ ] **Step 4: For `go-fly-http` subsection, document `WithCronMonitor` invocation** inside the operator's existing `time.Ticker` loop pattern.

- [ ] **Step 5: Locate Phase 8 (Smoke verify) and add a paragraph** about the healthz snippet:

```markdown
**If your stack accepts HTTP traffic and you want Sentry Uptime monitoring,** copy `<wrapper-dir>/healthz-snippet.{ts,go}` to your routes layer (e.g. `src/routes/healthz.ts` or `functions/healthz.ts`) and mount it. Then configure Sentry Uptime per `add-observability/uptime-setup-runbook.md`.
```

- [ ] **Step 6: Commit.**

Commit message: `docs(INIT): Phase 5 composition order + Phase 8 healthz copy-instruction (1.18.0)`.

---

### T14: Operator runbook `add-observability/uptime-setup-runbook.md`

**Files:**
- Create: `add-observability/uptime-setup-runbook.md`

- [ ] **Step 1: Write the runbook in 3 sections (~150 lines total).**

```markdown
# Sentry Crons + Uptime — Operator Setup Runbook

> When to use this: after running `add-observability scan` (or after materializing a fresh wrapper at v1.18.0+) on a project that exposes scheduled handlers or HTTP endpoints, follow this runbook to wire the Sentry UI side of cron-checkin alerting and uptime probing. The wrapper code emits checkins; the Sentry monitors that receive and alert on them are configured here.

## Part 1 — Sentry Crons (per `monitorSlug`)

For each `monitorSlug` your project emits (find them by running
`grep -rn 'withCronMonitor\|WithCronMonitor' .`), create a Cron Monitor in Sentry:

1. In Sentry → **Crons** → **Add Monitor**.
2. **Name**: human-readable (e.g. "FXSA Ingest 15-min").
3. **Slug**: must match the `monitorSlug` value emitted by the wrapper exactly.
4. **Schedule**: match your platform's cron trigger (e.g. `*/15 * * * *`).
5. **Alert thresholds**: missed checkin → email + Slack to on-call rotation.
6. **Max runtime**: set to the wrapper's `maxRuntimeSeconds` value if configured; otherwise pick a value 3× the expected handler latency.

[... continues with worked examples for fxsa / callbot ...]

## Part 2 — Sentry Uptime (per HTTPS endpoint)

For each public `/healthz` endpoint:

1. Sentry → **Uptime Monitoring** → **Add Monitor**.
2. **Target URL**: the public URL of your healthz endpoint (e.g. `https://api.fxsa.io/healthz`).
3. **Check interval**: 1 min for critical paths, 15 min for batch / non-realtime.
4. **Expected response**: status `200` AND body contains `"status":"ok"`.
5. **Regions**: probe from at least 2 (us-east-1, eu-west-1 for global services).
6. **Alert routing**: 503 or timeout → page on-call.

[... continues ...]

## Part 3 — Cross-link via `policy.md`

The wrapper materialized a `policy.md` in your `.observability/` dir. Add a section recording your monitor inventory so future operators don't lose context:

\`\`\`markdown
## Out-of-process monitors (Sentry Crons + Uptime — configured in Sentry UI, not in code)

### Cron monitors
- `fxsa-ingest-15min` — schedule `*/15 * * * *`, max runtime 240s, alert: on-call (email+slack)
- ...

### Uptime monitors
- `https://api.fxsa.io/healthz` — 1min interval, us-east-1 + eu-west-1, alert: on-call
- ...
\`\`\`
```

- [ ] **Step 2: Commit.**

Commit message: `docs(add-observability): uptime-setup-runbook.md — Sentry Crons + Uptime + policy.md cross-link`.

---

### T15: ADR-0028

**Files:**
- Create: `docs/decisions/0028-sentry-crons-healthz-conventions.md`

- [ ] **Step 1: Write the ADR following the template at `docs/decisions/0027-postphase-observability-hook.md`.**

```markdown
# ADR-0028: Sentry Crons heartbeats + `/healthz` convention as host-discretion (not spec mandate)

**Status**: Accepted
**Date**: 2026-05-29
**Workflow version**: 1.18.0
**Linear**: (none — internal sequencing)

## Context

`add-observability` v0.5.1 ships per-stack wrappers that capture errors and logs during a request. Two production failure modes are invisible to that path: (a) a scheduled handler that never fires, (b) a platform that's deployed but routing-failed. Sentry's product surface already covers both gaps — Crons (heartbeat checkins) and Uptime (HTTP probes against `/healthz`).

The question: should `add-observability` make these trivial to adopt (host-discretion) or should the workflow spec MANDATE them across all destinations (§10.x addition)?

## Decision

**Host-discretion under spec §10.6/§10.7.** The v1.18.0 release of `add-observability` ships `withCronMonitor` as an optional, additive wrapper export and a copy-only `healthz-snippet.{ts,go}` template. The generator obligation under §10.7 is satisfied by making both trivial to opt into; the spec is not amended.

## Alternatives rejected

- **Spec mandate (§10.10 "Out-of-process observability").** Would require every destination (Axiom, Sentry, future) to support a checkin equivalent, multiplying adapter surface. Sentry Crons UI is the actual product value here; emulating it across destinations adds surface without operator benefit.
- **Mirror checkins to Axiom destination.** Doubles the signal surface; Axiom dashboards aren't the place an operator goes for "did my cron fire". Resolves to D2 in CONTEXT.md.
- **Include git short-SHA in monitor slug.** Cycles monitor identity per deploy; silently breaks Sentry's missed-checkin alert continuity. Commit SHA goes in `environment`/`release` Sentry context. Resolves to D3.
- **Route /healthz through `withObservability`.** Uptime probes (N regions × 1–15min) crowd Sentry's transaction view and obscure real traffic patterns. /healthz is observable via Sentry Uptime alone. Resolves to D4.

## Consequences

- Existing v0.5.x projects keep working without adopting v1.18.0 (additive migration).
- Per-project adoption is opt-in: the wrapper exports `withCronMonitor`, but the operator decides which handlers to wrap and which Sentry monitor slugs to provision in the Sentry UI.
- The operator runbook (`add-observability/uptime-setup-runbook.md`) is the binding contract between code-side emission and UI-side configuration. `policy.md` records the resulting monitor inventory per-project.
- If future evidence shows projects routinely ship without cron heartbeating, this decision should be revisited as a §10.10 spec amendment.

## References

- CONTEXT.md decisions D1–D10 (this phase).
- Sentry Crons docs: <https://docs.sentry.io/product/crons/>
- Sentry Uptime docs: <https://docs.sentry.io/product/uptime-monitoring/>
- ADR-0014 (observability architecture baseline).
- ADR-0026 (add-observability 0.5.1 wrapper fixes).
- ADR-0027 (post-phase observability hook).
```

- [ ] **Step 2: Commit.**

Commit message: `docs(adr): 0028 — Sentry Crons + healthz as host-discretion (not spec mandate)`.

---

### T16: CHANGELOG + skill version bumps

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `skill/SKILL.md`
- Modify: `add-observability/SKILL.md`

- [ ] **Step 1: Add the `## [1.18.0] — 2026-05-29` section to CHANGELOG.md** above the existing `## [1.17.0]` entry. Mirror the `## [1.17.0]` shape.

```markdown
## [1.18.0] — 2026-05-29

### Added — Sentry Crons heartbeats (`withCronMonitor`) + `/healthz` convention (issue Phase 22)

- New optional `withCronMonitor` / `WithCronMonitor` wrapper exported by 4 stack templates (worker / pages / supabase-edge / go-fly-http). Composes innermost in the scheduled chain (worker / supabase-edge); generic async-fn shape on pages; functional-options style in Go. Fail-safe when `SENTRY_DSN` is unset (zero checkins, no exception). 3-source slug resolution: explicit > env-var (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>`) > auto-derived (`${SERVICE_NAME}:${cronExpr}`). See `add-observability/uptime-setup-runbook.md` for Sentry UI configuration.
- New `healthz-snippet.{ts,go}` template per stack — copy-only (operator decides where to mount). 200 ok / 503 degraded contract with per-check breakdown. Intentionally NOT routed through `withObservability` to keep Sentry's transaction view free of probe noise.
- New `add-observability/uptime-setup-runbook.md` — operator-facing walkthrough of Sentry UI configuration for Crons + Uptime + `policy.md` cross-link template.
- Migration 0019 (`from_version: 1.17.0`, `to_version: 1.18.0`) — additive adoption; refuses on hand-modified wrappers via content-hash check mirroring 0017's style-insensitive canonicalization. 5 fixtures (fresh / already-applied / hand-modified-refuse / cparx-shape / fxsa-multi-module).
- ADR-0028 records host-discretion-vs-spec-mandate decision.

### Fixed

- `skill/SKILL.md` version drift: PR #52 declared `to_version: 1.17.0` (migration 0018) but left the SKILL.md frontmatter at `1.16.0`. Folded as commit 1 of this branch (`122aafa`) — keeps the 1:1 version-tracks-migrations invariant intact.

### Compatibility

- All v0.5.1 template exports byte-identical (worker / pages / supabase-edge / go-fly-http / react-vite). 170 existing template-suite tests pass unchanged.
- v1.17.0 projects can skip migration 0019; no breaking change.
- react-vite stack: no changes (browser bundle has no scheduled handlers; no server-side healthz).
```

- [ ] **Step 2: Bump `skill/SKILL.md` version frontmatter.**

```yaml
# was: version: 1.17.0
version: 1.18.0
```

- [ ] **Step 3: Bump `add-observability/SKILL.md` version frontmatter.**

```yaml
# was: version: 0.5.1
version: 0.6.0
```

- [ ] **Step 4: Run BOTH test suites green to confirm version bumps don't break assertions.**

Run: `bash migrations/run-tests.sh 2>&1 | tail -5 && bash add-observability/templates/run-template-tests.sh all 2>&1 | tail -5`

Expected: both PASS with the expected totals (171+5 and 170+~30).

- [ ] **Step 5: Commit.**

Commit message: `chore: bump claude-workflow → 1.18.0 / add-observability → 0.6.0 + CHANGELOG`.

---

### T17: Final integration smoke + push

**Files:** none

- [ ] **Step 1: Re-run both suites green.**

Run: `bash migrations/run-tests.sh && bash add-observability/templates/run-template-tests.sh all`

Expected: zero failures across both.

- [ ] **Step 2: Verify the export-byte-identical claim.**

Run: `git diff main -- add-observability/templates/ts-cloudflare-worker/middleware.ts add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/ts-cloudflare-pages/_middleware.ts add-observability/templates/ts-cloudflare-pages/lib-observability.ts add-observability/templates/ts-supabase-edge/middleware.ts add-observability/templates/ts-supabase-edge/index.ts add-observability/templates/go-fly-http/middleware.go add-observability/templates/go-fly-http/observability.go`

Expected: NO output. If any byte changed in these files, the byte-identical claim (G2) is violated — investigate and roll back.

- [ ] **Step 3: Push the branch.**

Run: `git push -u origin feat/sentry-crons-healthz-v1.18.0`

Expected: branch tracking set up.

PR creation is task #14 in the task tracker, handled by `superpowers:finishing-a-development-branch`.

---

## Self-review

**1. Spec coverage** (against CONTEXT.md G1–G8):

| Goal | Covered by tasks | Notes |
|---|---|---|
| G1 (`withCronMonitor` exported, 4 stacks) | T02 / T03 / T04 / T05 | One task per stack, RED+GREEN per |
| G2 (v0.5.1 byte-identical) | T17 step 2 | git diff assertion as the gate |
| G3 (3 cases + fail-safe per stack) | T02–T05 step 1 (test file) | All 6 tests per TS stack, mirrored in Go |
| G4 (slug 3-source precedence) | T02 step 1 (`describe("slug resolution")`); mirrored T03–T05 | Tests assert each precedence rule |
| G5 (healthz snippet copy-only contract) | T06–T09 | Top-of-file comment + 200/503 tests |
| G6 (migration 0019 + 5 fixtures + content-hash refuse) | T10 + T11 + T12 | Apply engine + fixtures + run-tests.sh wiring |
| G7 (operator runbook) | T14 | ~150 lines, 3 sections |
| G8 (version bumps + ADR-0028 + CHANGELOG + suites green) | T15 + T16 + T17 | All three bumps + final smoke |

No gaps.

**2. Placeholder scan**: no "TBD"/"TODO"/"implement later"/"add appropriate error handling"/"similar to Task N". Test code shown in full for T02, T06; T03–T05 / T07–T09 reference T02/T06 as the canonical pattern with explicit deltas (signature changes, env access) — this is by-design pattern-reference, not placeholder.

**3. Type consistency**:
- `CronMonitorConfig` interface name used consistently across T02 / T03 / T04 (`CronMonitorOption` in T05 Go, intentional per Go convention).
- `monitorSlug` field name used consistently (no `slug` / `monitor_slug` drift).
- `captureCheckIn` (TS) / `CaptureCheckIn` (Go) match their respective SDK conventions.
- Slug env prefix `SENTRY_CRON_MONITOR_SLUG_` consistent across T02–T05.
- `healthzHandler` (TS T06) / `HealthzHandler` (Go T09) match language conventions.

**4. Self-review issues found and fixed inline:**
- Initially proposed `init` flag wiring in T14 — removed, scope-creep beyond CONTEXT G6 (which scopes 0019 to additive file installation only; CLAUDE.md observability block is "NO change").
- T11 step 1 originally said "use `_seeds/` dir"; added the fallback "if not, inline content directly" note because the seed dir may not exist in this repo.

---

## Execution handoff

Plan committed to `.planning/phases/22-sentry-crons-healthz/PLAN.md`. Two execution options:

**1. Subagent-driven (recommended)** — `superpowers:subagent-driven-development`: fresh subagent per task (T01 → T02 → ... → T17), Stage 1 + Stage 2 review between tasks via this session, fast iteration. Best for this plan's size (17 tasks across ~30+ commits).

**2. Inline execution** — `superpowers:executing-plans`: execute tasks in this session with checkpoints. Higher context cost given plan length.

Default routing if the user does not specify: subagent-driven, as recommended.
