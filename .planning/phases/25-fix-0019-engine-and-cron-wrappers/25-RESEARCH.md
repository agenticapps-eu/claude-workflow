# Phase 25: Fix 0019 engine + withCronMonitor — Research

**Researched:** 2026-05-31
**Domain:** Bash migration engines (POSIX), TypeScript discriminated unions, Cloudflare Queue consumer wrappers, Sentry Crons SDK composition
**Confidence:** HIGH (Sentry types verified in installed SDK; Cloudflare types verified in installed `@cloudflare/workers-types`; engine line numbers verified; existing fixtures + ADRs read end-to-end)

## Summary

Issue #56 surfaced four discrete gaps from migrating callbot v1.16.0 → v1.19.0. CONTEXT.md locked the design: silent-alias `index.ts` for cf-worker/cf-pages anchors, discriminated-union `CronMonitorSchedule`, narrowed `withCronMonitor<E>` generic, and a new `withQueueMonitor` mirroring Guarded Shape A (ADR-0029). What remains for the planner is implementation-level work — line-anchored engine diffs, symmetric template edits across three TS stacks, expanded test fixtures, and three ADRs (0031, 0032, 0033).

Two findings reshape the planner's job materially beyond what CONTEXT.md captured:

1. **The canonical materialised wrapper filename for cf-worker AND cf-pages is `index.ts`, not `lib-observability.ts`** (verified in `meta.yaml`). The template source is named `lib-observability.ts`, but `meta.yaml:target.wrapper_path` writes it to `index.ts`. The 0019 engine's `stack_fingerprint_files` (`migrate-0019-…sh:340-348`) looks for `lib-observability.ts` — which never exists in a real project. The existing 7 fixtures hand-seed `lib-observability.ts` (test-only divergence from production reality), which is why the bug shipped green. D-01's framing — "accept `index.ts` as an alias" — is half right: `index.ts` is actually the **canonical** name; `lib-observability.ts` is fixture-only. Engine must treat `index.ts` as a first-class anchor, and the existing fixtures should keep working (treat `lib-observability.ts` as a legacy alias for fixture compatibility, or migrate fixtures).
2. **D-02's "no follow-up migration needed" premise is broken by the migration runner's `from_version` matching contract** (`migrations/README.md:60-99`). A project at `1.18.0` or `1.19.0` (already ran 0019) will NOT re-trigger 0019 even if we re-rev it — the runner matches `from_version: 1.17.0` only. So callbot at `1.19.0` cannot re-run 0019 to pick up the engine fix OR the new `queue-monitor.{ts,go}`. Either ship a new migration `0021` (`from_version: 1.19.0` → `to_version: 1.20.0`) that copies the four new/fixed files into already-migrated projects, OR document the manual recovery (delete `cron-monitor.{ts,go}`, downgrade `skill/SKILL.md` version, re-run engine). There is no `--force` flag today (OQ-5 verified — engine relies purely on `cron-monitor.{ts,go}` presence as idempotency marker). This is the single biggest decision the planner needs to escalate.

**Primary recommendation:** Plan in 5 waves — (W0) ADR-0031/32/33 + engine-fix test fixtures (RED); (W1) engine fix + classify branches; (W2) three TS template edits for D-03/D-05 symmetric; (W3) three new `queue-monitor.ts` + tests; (W4) migration 0019 docs amendment + decision on 0021-vs-recovery for already-migrated projects; (W5) version bumps + CHANGELOG. Plan must explicitly resolve OQ-1 + the runner-contract finding above before any code lands.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Engine — anchor file detection (D-01, D-02):**
- **D-01:** Engine accepts `index.ts` as alias anchor for ts-cloudflare-worker AND ts-cloudflare-pages silently. Implementation: extend `find` candidates at `:224-226` to include `-name index.ts`, extend classify branches at `:317-331` so cf-worker matches `(lib-observability.ts OR index.ts) + middleware.ts` and cf-pages matches `(lib-observability.ts OR index.ts) + _middleware.ts`. The `middleware.ts` / `_middleware.ts` co-anchor requirement guards against unintended matches.
- **D-02:** No follow-up migration 0021; update 0019.md docs only. Re-run with `--force` is the recovery path. (*See `## Open Questions` for runner-contract finding that destabilises this premise.*)

**Schedule type — discriminated union (D-03, D-04):**
- **D-03:** Replace `interface CronMonitorSchedule { type: "crontab" | "interval"; value: string }` with `type CronMonitorSchedule = { type: "crontab"; value: string } | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" }`. Apply symmetrically to all three TS templates. Go template needs no change.
- **D-04:** Type-shape change is functionally non-breaking. Minor bump justified by surface expansion (D-08).

**Generic narrowing (D-05, D-06):**
- **D-05:** Narrow `withCronMonitor<E extends Record<string, unknown>>` → `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`. Inside wrapper: `(env as unknown as Record<string, unknown>)[envKey]`. Apply symmetrically to all 3 TS templates + new `queue-monitor.ts`.
- **D-06:** Generic narrowing functionally non-breaking. Minor bump.

**withQueueMonitor (D-07 — D-12):**
- **D-07:** New `queue-monitor.ts` in `ts-cloudflare-worker`, `ts-cloudflare-pages`, and (for symmetry) `ts-supabase-edge`. Signature: `withQueueMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }, Msg = unknown>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, config?: CronMonitorConfig): typeof handler`.
- **D-08:** Guarded Shape A semantics (ADR-0029): `handlerStarted` flag; pre-callback transport failure → unmonitored fallback; post-callback errors propagate.
- **D-09:** Slug resolution mirrors D6 3-source: `config.monitorSlug` > env `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` > auto-derive `${SERVICE_NAME ?? "service"}:queue:${batch.queue}`.
- **D-10:** Multi-queue policy mirrors D11: handlers dispatching by `batch.queue` MUST pass explicit `monitorSlug`.
- **D-11:** Migration 0019 expanded to copy `queue-monitor.{ts,go}` alongside existing files. Idempotency marker stays `cron-monitor.ts` presence.
- **D-12:** Go template (`go-fly-http/queue_monitor.go`) — out of scope this phase.

**Versioning (D-13, D-14):**
- **D-13:** `add-observability` 0.8.0 → 0.9.0 (minor).
- **D-14:** `claude-workflow` 1.19.0 → 1.20.0 (minor).

**Test surface (D-15, D-16, D-17):**
- **D-15:** Extend `migrations/test-fixtures/0019/` with new fixture(s) for `index.ts`-anchored wrapper (cf-worker AND cf-pages).
- **D-16:** Extend `cron-monitor.test.ts` × 3 stacks: (a) type-level test for `CronMonitorSchedule` interval-variant requires `value: number + unit`; (b) generic-narrowing fixture with strict-typed `Env`; (c) regression for `crontab` variant.
- **D-17:** New `queue-monitor.test.ts` × 3 TS stacks, structurally identical to `cron-monitor.test.ts`.

### Claude's Discretion

- Specific file naming for the migration docs amendment ("Recovery" section heading, line position) — planner decides per docs convention.
- Exact `as unknown as Record<string, unknown>` placement inside `resolveSlug` (function boundary vs `env[envKey]` access site) — planner picks smaller diff.
- Whether `queue-monitor.test.ts` mocks `MessageBatch` via `@cloudflare/workers-types` import or hand-rolls a minimal interface — planner picks per existing test conventions.
- Whether to bump migration filename to `0019.1-…` or keep at `0019-…` with re-rev annotation — planner decides per migration history conventions (see Open Questions).

### Deferred Ideas (OUT OF SCOPE)

**Phase 26 carry-forward (was Phase 25.x in handoff):**
- DEF-1: TRACE_SAMPLE_RATE unwired in worker template
- DEF-2: REDACTED_KEYS missing `authorization` / `bearer` in worker template
- DEF-3: module-level mutable singletons in worker template
- F-2: no tracked `package-lock.json` policy across templates
- Extending Phase 24's `add-observability/templates/openrouter-monitor/.gitignore` shape to ts-cloudflare-worker, ts-cloudflare-pages, ts-supabase-edge

**Future phases:**
- Full retroactive bootstrap of ROADMAP.md / STATE.md / PROJECT.md
- Migration 0017 engine bug fixes (`FIX-0017-ENGINE.md`)
- `withQueueMonitor` for Go templates (Fly HTTP)
- GH Actions CI to run the 466-fixture test surface
- PROMPT C fxsa adoption + PROMPT D callbot adoption rollouts

## Phase Requirements

Phase 25 has no `REQUIREMENTS.md` — requirements are inherited from CONTEXT.md decisions D-01..D-17. The ROADMAP success criteria map directly to those decisions:

| Roadmap SC | Maps to CONTEXT.md | Research support |
|------------|--------------------|------------------|
| SC1 — Engine accepts `index.ts`-anchored wrappers | D-01 | `## Architecture Patterns`, `## Engine Fix Sites`, fixture pattern |
| SC2 — `CronMonitorSchedule` matches Sentry's `MonitorSchedule` | D-03, D-04 | `## Sentry Type Verification`, code example |
| SC3 — `withCronMonitor` works with strict-typed `Env` | D-05, D-06 | `## Generic Narrowing Pattern`, code example |
| SC4 — `withQueueMonitor` with Guarded Shape A | D-07—D-10 | `## Cloudflare MessageBatch`, full Guarded Shape A template |
| SC5 — Acceptance fixture (callbot or synthetic strict-Env) | D-15, D-16, D-17 | Test pattern + harness verification |
| SC6 — Test surface extended | D-15, D-16, D-17 | `## Validation Architecture` |
| SC7 — Issue #56 closed | — | Linkback responsibilities split per finding |

## Project Constraints (from CLAUDE.md)

The repo-level `CLAUDE.md` directives the planner MUST honor:

- **MUST run `gitnexus_impact()` before editing any symbol.** Required for `withCronMonitor`, `resolveSlug`, `buildMonitorConfig` symbols. Report blast radius (direct callers, affected processes, risk level) BEFORE proposing edits.
- **MUST run `gitnexus_detect_changes()` before committing** to verify changes only affect expected symbols and execution flows.
- **MUST warn user if impact analysis returns HIGH or CRITICAL risk.**
- **NEVER rename symbols with find-and-replace** — use `gitnexus_rename`.
- **Always use feature branches + PRs to main; never commit directly to main.** (Phase 25 already on `feat/fix-0019-engine-and-cron-wrappers-v1.20.0` per STATE.md.)

Workflow-level (`~/.claude/CLAUDE.md` — AgenticApps workflow):
- Tasks with `tdd="true"` → strict red-green-refactor (failing test first).
- Frontend component changes → `/browse` screenshot before commit (N/A this phase — backend/templates only).
- Always run `/review` on the phase diff post-execute.
- Run `/cso` if phase touches auth, storage, API, or LLM code. Phase 25 touches Sentry SDK boundary + observability wrapper code — borderline. Recommend `/cso` because the wrapper is the security/observability transport boundary.

## Standard Stack

### Core (verified)

| Library | Version (verified) | Purpose | Why Standard |
|---------|--------------------|---------|--------------|
| `@sentry/cloudflare` | `^8.0.0` (template pin; **CITED:** `add-observability/templates/run-template-tests.sh:174`) | Sentry SDK with `withMonitor` re-export for Worker/Pages wrappers | The 3 TS templates already use this; Phase 23 verified `withMonitor` ships in `@sentry/core` and is re-exported by `@sentry/cloudflare`. **VERIFIED** in installed `node_modules/@sentry/core/build/types/exports.d.ts:95`. |
| `npm:@sentry/deno@^8.0.0` | `^8.0.0` | Sentry SDK for Supabase Edge stack | Already pinned in `ts-supabase-edge/cron-monitor.ts:28` via Deno `npm:` specifier. |
| `@cloudflare/workers-types` | `^4.20240909.0` (openrouter-monitor pin) / `^4.20260531.1` (latest **VERIFIED:** `npm view`) | Ambient types for `ScheduledController`, `ExecutionContext`, `MessageBatch<Body>` | Required for `withQueueMonitor` signature. |
| `vitest` | `^3.0.0` (template harness) / `^4.1.7` (latest **VERIFIED:** `npm view`) | Test framework for `*.test.ts` files | Template harness already uses vitest 3; mocking pattern (`vi.fn()`, `vi.mock()`) established in `cron-monitor.test.ts`. |
| sentry-go | `v0.31.0` (CITED: `cron_monitor.go:84-85`) | Native `sentry.MonitorSchedule` interface — explains why D-03 is JS-only | Go template uses native `sentry.MonitorSchedule` as `interface` value (not struct), so D-03 schedule fix doesn't apply Go-side. |

**Version verification (npm registry, 2026-05-31):**
- `@sentry/cloudflare`: latest `10.55.0` — but template suite uses `^8.0.0` per Phase 24 carve-out. **No SDK version change this phase.** The narrowed generic in D-05 and the discriminated union in D-03 both work against `@sentry/cloudflare ^8.0.0` (`SerializedCheckIn['monitor_config']['schedule']` shape unchanged between SDK 8.x and 10.x — verified in installed 8.55.2 types).
- `@sentry/core`: tracks `@sentry/cloudflare`. Installed: `8.55.2`. **VERIFIED** the `MonitorSchedule` discriminated union shape (see `## Sentry Type Verification` below).

**Note on `^8.0.0` template pin:** Phase 24's openrouter-monitor scaffold ships with `@sentry/cloudflare ^8.0.0` deliberately as a carve-out (the 10.2.0 floor in `openrouter-integration.md` D-17 applies only to consumer apps using AI Monitoring; the monitor itself makes no LLM calls). Phase 25 inherits this — no version pin change.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Bash (POSIX-compliant) | `set -uo pipefail` style | Engine script | Already established at `migrate-0019-…sh:47`; new lines must follow same conventions (bash 3.2 compat, no associative arrays — see `:264-273` for dedupe pattern). |
| `awk` (POSIX) | system | `canonicalize_awk` style-insensitive content-hash | `migrate-0019-…sh:362-446` — verbatim from 0017; do NOT diverge per `migrations/0019-…md:260` ("Mirror, not fork, 0017's canonicaliser"). |

### Alternatives Considered (and rejected)

| Instead of | Could Use | Tradeoff / Reason rejected |
|------------|-----------|----------------------------|
| Discriminated-union `type CronMonitorSchedule` | Re-export Sentry's `MonitorSchedule` directly | **Rejected in CONTEXT D-3 / DISCUSSION-LOG:** tightest coupling; SDK version drift risk. Discriminated union is our type that happens to be structurally compatible. |
| Discriminated-union `type CronMonitorSchedule` | Keep interface, add `unit?` as optional | **Rejected in CONTEXT D-3 / DISCUSSION-LOG:** half-fix; still doesn't satisfy Sentry's `MonitorSchedule`. |
| Generic narrowing (D-05) | Keep `Record<string, unknown>` | **Rejected:** forces every downstream `Env` interface to either add `[key: string]: unknown` (loses index-access safety) or cast at every call site. |
| New `withQueueMonitor` export | Re-shape `withCronMonitor` to accept `MessageBatch` OR `ScheduledController` | **Rejected per D-07 (mirrors Phase 22 D1):** separate wrapper keeps API surface frozen; lets queue-specific knobs land without churning the cron wrapper. |
| Re-rev 0019 | Ship new migration 0021 with `from_version: 1.19.0` | **Active open question** — see `## Open Questions` OQ-1 (planner-level). CONTEXT D-02 picks re-rev, but the migration runner's `from_version` contract means re-revving alone doesn't re-trigger on already-migrated projects. |

**Installation / setup:** No new packages this phase. Engine is a vendored bash script. Test harness already wires `vitest` + `@sentry/cloudflare`.

## Sentry Type Verification

**[VERIFIED]** against installed `node_modules/@sentry/core/build/types/types-hoist/checkin.d.ts` (`@sentry/core@8.55.2`, packaged with template harness's `@sentry/cloudflare ^8.0.0`):

```typescript
// From @sentry/core checkin.d.ts:2-12 — the canonical shape
interface CrontabSchedule {
    type: 'crontab';
    /** The crontab schedule string, e.g. 0 * * * *. */
    value: string;
}
interface IntervalSchedule {
    type: 'interval';
    value: number;
    unit: 'year' | 'month' | 'week' | 'day' | 'hour' | 'minute';
}
type MonitorSchedule = CrontabSchedule | IntervalSchedule;
```

**`MonitorConfig` shape (`checkin.d.ts:74-98`):**

```typescript
export interface MonitorConfig {
    schedule: MonitorSchedule;       // NOTE: required, NOT optional
    checkinMargin?: number;
    maxRuntime?: number;             // in minutes (per Sentry doc); template forwards seconds — see below
    timezone?: string;
    failureIssueThreshold?: number;
    recoveryThreshold?: number;
}
```

**`withMonitor` signature (`@sentry/core/build/types/exports.d.ts:95` — VERIFIED):**

```typescript
export declare function withMonitor<T>(
    monitorSlug: CheckIn['monitorSlug'],
    callback: () => T,
    upsertMonitorConfig?: MonitorConfig
): T;
```

**Implications for D-03:**

1. The unit enum order in CONTEXT D-3 ("`minute | hour | day | week | month | year`") is fine — Sentry's source order is reversed but TS discriminated-union literal-type equivalence is order-independent.
2. **`MonitorConfig.schedule` is REQUIRED in Sentry's type, not optional.** The current template's `buildMonitorConfig` returns `{ schedule?: CronMonitorSchedule; maxRuntime?: number } | undefined` — i.e., `schedule` is optional in our return type. This is technically incompatible with Sentry's `MonitorConfig` when the 3rd arg is provided. In practice `Sentry.withMonitor`'s 3rd arg is `upsertMonitorConfig?: MonitorConfig` (optional itself), and at runtime Sentry tolerates either path. **Planner decision:** when fixing D-03, also tighten `buildMonitorConfig`'s return type so `schedule` is required when the function returns a non-undefined value, OR keep loose if the runtime tolerance is preferred. Recommendation: keep current return-type loose; the template wrapper already gates on `hasSchedule || hasMaxRuntime`, so the only path that returns the object is when one or both are set. A configured schedule will always be present when the operator passes one. `[ASSUMED]` Sentry will accept this at runtime — verify with a regression test asserting `withMonitor` is called without throwing when only `maxRuntime` is set (no schedule).
3. **`maxRuntime` unit mismatch — wrapper uses seconds, Sentry doc says minutes.** This is a pre-existing template quirk (`cron-monitor.ts:84` comment: "Wrapper-API unit is SECONDS"). Out of scope for Phase 25; Go template's `WithMaxRuntimeSeconds` documents this honestly (`cron_monitor.go:96-99`). **Recommendation:** do NOT fix in Phase 25 — log as Phase 26 candidate. (`[CITED: @sentry/core/types-hoist/checkin.d.ts:34]` confirms field is `max_runtime` in minutes for serialised form.)

## Cloudflare MessageBatch — Type Verification

**[VERIFIED]** against installed `node_modules/@cloudflare/workers-types/index.d.ts` (`@cloudflare/workers-types`, pinned `^4.20240909.0` in `openrouter-monitor/package.json`; latest at `4.20260531.1`):

```typescript
// index.d.ts:2379-2386 — MessageBatch<Body>
interface MessageBatch<Body = unknown> {
  readonly messages: readonly Message<Body>[];
  readonly queue: string;
  readonly metadata: MessageBatchMetadata;
  retryAll(options?: QueueRetryOptions): void;
  ackAll(): void;
}

// Message<Body> (:2370-2376)
interface Message<Body = unknown> {
  readonly id: string;
  readonly timestamp: Date;
  readonly body: Body;
  readonly attempts: number;
  retry(options?: QueueRetryOptions): void;
  ack(): void;
}
```

**Canonical Queue handler signature (`workers-types/index.d.ts:510-516, :14282` — VERIFIED):**

```typescript
queue?(batch: MessageBatch): void | Promise<void>;
// And the parametric form Cloudflare exposes:
type QueueHandler<Env = unknown, Message = unknown, Props = unknown> = (
  batch: MessageBatch<Message>,
  env: Env,
  ctx: ExecutionContext<Props>,
) => void | Promise<void>;
```

**Implications for D-07/D-09:**

- **D-07 signature matches Cloudflare's canonical shape.** The CONTEXT signature `withQueueMonitor<E, Msg>(handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>, ...)` is identical to Cloudflare's `QueueHandler<E, Msg>`.
- **D-09 auto-derive uses `batch.queue` field (VERIFIED present on `MessageBatch`).** The exact slug `${SERVICE_NAME ?? "service"}:queue:${batch.queue}` will resolve to e.g. `callbot:queue:kompendium-events`.
- The handler runs once per batch; auto-deriving by queue name is correct (one batch belongs to exactly one queue per `MessageBatch.queue: string`).

## Engine Fix Sites — Exact Line Diffs

### D-01 fix site 1 — `find` candidate collection (`migrate-0019-…sh:219-229`)

Current:
```bash
done < <(find . \
            -path ./node_modules -prune -o \
            -path ./.git -prune -o \
            -path './**/node_modules' -prune -o \
            -type f \( \
              -name lib-observability.ts -o \
              -name observability.go -o \
              -name middleware.go \
            \) \
            -print 2>/dev/null \
          | sort -u)
```

**CRITICAL CAVEAT — `index.ts` is too generic to add unscoped.** Naively adding `-name index.ts` would match EVERY `index.ts` in the project (build outputs, dist/, generated code, etc.). The existing supabase-edge pickup (`:256-261`) handles this correctly by scoping the find to `-type d -name observability` AND filtering with `_filter_supabase_edge_roots` to require the `*/_shared/observability/` path shape.

**Recommended planner approach:** Either (a) gate `index.ts` matches by directory pattern (require parent dir to match `*/observability` or `*/_lib/observability` or `*/lib/observability`), or (b) accept `index.ts` only if a sibling `middleware.ts` / `_middleware.ts` exists (the same co-anchor requirement CONTEXT D-01 mentions). Option (b) is simpler and aligns with the classify branches.

Suggested diff shape (option (b)):
```bash
# Add to find candidate set:
              -name lib-observability.ts -o \
              -name observability.go -o \
              -name middleware.go -o \
              -name index.ts -o \
              -name _middleware.ts -o \      # cf-pages anchor (currently inferred from classify)
              -name middleware.ts \          # cf-worker co-anchor
```

Then a NEW post-find filter pass: discard any `index.ts` candidate whose parent dir does NOT also contain `middleware.ts` (cf-worker shape) OR `_middleware.ts` (cf-pages shape) OR is under `*/_shared/observability/` (supabase shape). This prevents `node_modules`-escaped `index.ts` files from polluting the ROOTS array.

**Alternative — pre-classify dedupe:** Allow `index.ts` candidates through unconditionally; `classify_stack()` returns `unknown` for index.ts in unrelated dirs, which then routes to `SKIP_UNSUPPORTED` (existing fail-closed path at `:496-498`). This is safer (engine already fails closed) but emits noise for every unrelated `index.ts` in the project — could surprise operators. Planner picks; recommendation: filter aggressively, fail closed only as backstop.

### D-01 fix site 2 — classify_stack branches (`migrate-0019-…sh:317-331`)

Current:
```bash
  # Cf-pages anchor file (_middleware.ts is Pages-specific)
  if [ -f "$dir/_middleware.ts" ] && [ -f "$dir/lib-observability.ts" ]; then
    echo "ts-cloudflare-pages"; return
  fi
  # ...
  # Cf-worker (default TS server shape)
  if [ -f "$dir/lib-observability.ts" ] && [ -f "$dir/middleware.ts" ]; then
    echo "ts-cloudflare-worker"; return
  fi
```

D-01 implementation:
```bash
  # Cf-pages: anchor is index.ts (canonical, per meta.yaml) OR lib-observability.ts (legacy)
  if [ -f "$dir/_middleware.ts" ] && ( [ -f "$dir/lib-observability.ts" ] || [ -f "$dir/index.ts" ] ); then
    echo "ts-cloudflare-pages"; return
  fi
  # ...
  # Cf-worker: anchor is index.ts (canonical) OR lib-observability.ts (legacy)
  if ( [ -f "$dir/lib-observability.ts" ] || [ -f "$dir/index.ts" ] ) && [ -f "$dir/middleware.ts" ]; then
    echo "ts-cloudflare-worker"; return
  fi
```

### D-01 fix site 3 — fingerprint file map (`migrate-0019-…sh:340-348`)

Current:
```bash
stack_fingerprint_files() {
  case "$1" in
    ts-cloudflare-worker) echo "lib-observability.ts middleware.ts" ;;
    ts-cloudflare-pages)  echo "lib-observability.ts _middleware.ts" ;;
    ts-supabase-edge)     echo "index.ts middleware.ts" ;;
    go-fly-http)          echo "observability.go middleware.go" ;;
    *) echo "" ;;
  esac
}
```

This needs to **pick the file that actually exists** in the wrapper root: prefer `index.ts` over `lib-observability.ts` when both are present (canonical wins), fall back to whichever exists. The `is_known_clean_wrapper()` consumer (`:470-483`) iterates `for f in $files; do ... if [ ! -f "$dir/$f" ]; then return 1; fi`, so we either need to (a) make the function return the resolved filename per-root, or (b) restructure `is_known_clean_wrapper` to accept "any-of" sets.

**Recommended planner approach:** Add a resolver helper `resolve_anchor_files()` that takes the dir + stack and returns the actually-present anchor file list, and have `stack_fingerprint_files()` declare the set of candidate names. Sketch:

```bash
stack_anchor_candidates() {
  case "$1" in
    ts-cloudflare-worker) echo "index.ts lib-observability.ts middleware.ts" ;;  # first match wins for anchor; middleware.ts always required
    ts-cloudflare-pages)  echo "index.ts lib-observability.ts _middleware.ts" ;;
    ts-supabase-edge)     echo "index.ts middleware.ts" ;;
    go-fly-http)          echo "observability.go middleware.go" ;;
    *) echo "" ;;
  esac
}

# At fingerprint time, resolve the anchor file actually present.
resolve_anchor_files() {
  local dir="$1" stack="$2"
  case "$stack" in
    ts-cloudflare-worker)
      local anchor=""
      if [ -f "$dir/index.ts" ]; then anchor="index.ts"
      elif [ -f "$dir/lib-observability.ts" ]; then anchor="lib-observability.ts"
      else return 1; fi
      echo "$anchor middleware.ts"
      ;;
    ts-cloudflare-pages)
      local anchor=""
      if [ -f "$dir/index.ts" ]; then anchor="index.ts"
      elif [ -f "$dir/lib-observability.ts" ]; then anchor="lib-observability.ts"
      else return 1; fi
      echo "$anchor _middleware.ts"
      ;;
    ts-supabase-edge) echo "index.ts middleware.ts" ;;
    go-fly-http)      echo "observability.go middleware.go" ;;
  esac
}
```

Then `is_known_clean_wrapper()` calls `resolve_anchor_files()` instead of `stack_fingerprint_files()` — and the source-template baseline still uses `lib-observability.ts` from `add-observability/templates/<stack>/` because that's the source-of-truth filename. The canonicalise+hash step compares the project's `index.ts` (canonicalised) against the template's `lib-observability.ts` (canonicalised) — both should hash identically because the canonicaliser masks token VALUES, not filenames.

### D-11 fix site — apply Files Copied (`migrate-0019-…sh:686-728`)

Current `apply_root()`:
```bash
    ts-cloudflare-worker|ts-cloudflare-pages|ts-supabase-edge)
      local cm="$src/cron-monitor.ts" hz="$src/healthz-snippet.ts"
      ...
        cp "$cm" "$dir/cron-monitor.ts"    || return 1
        cp "$hz" "$dir/healthz-snippet.ts" || return 1
```

D-11 expansion: copy `queue-monitor.ts` for TS stacks (omit for go-fly-http per D-12). Sketch:

```bash
    ts-cloudflare-worker|ts-cloudflare-pages|ts-supabase-edge)
      local cm="$src/cron-monitor.ts" hz="$src/healthz-snippet.ts" qm="$src/queue-monitor.ts"
      if [ ! -f "$cm" ] || [ ! -f "$hz" ] || [ ! -f "$qm" ]; then
        warn "  ERROR: template files missing for stack '$stack'"
        return 1
      fi
      ...
        cp "$cm" "$dir/cron-monitor.ts"    || return 1
        cp "$hz" "$dir/healthz-snippet.ts" || return 1
        cp "$qm" "$dir/queue-monitor.ts"   || return 1
```

**Caveat — D-11 vs already-applied:** if a project ran 0019 BEFORE Phase 25 ships, `cron-monitor.ts` is present → `SKIP_ALREADY` short-circuits (`:506-510`) → `queue-monitor.ts` is NEVER copied. This is the root of the runner-contract finding above. Either (a) extend idempotency to check `queue-monitor.ts` presence too (so re-run picks it up), or (b) ship a new migration with different idempotency marker. See `## Open Questions`.

### Refuse-artifact expansion (`emit_refuse_artifacts_for`, `:566-591`)

Current emits would-be `cron-monitor.ts` + `healthz-snippet.ts`. D-11 expansion: also emit would-be `queue-monitor.ts` for TS stacks.

## Architecture Patterns

### Recommended Project Structure

No structural changes — all edits are in-place to existing files. Three NEW files materialise:

```
add-observability/templates/
├── ts-cloudflare-worker/
│   ├── cron-monitor.ts          # EDIT (D-03 schedule type, D-05 generic)
│   ├── cron-monitor.test.ts     # EDIT (D-16 type-level + generic + crontab regression tests)
│   ├── queue-monitor.ts         # NEW (D-07, D-08, D-09, D-10)
│   └── queue-monitor.test.ts    # NEW (D-17)
├── ts-cloudflare-pages/
│   ├── cron-monitor.ts          # EDIT
│   ├── cron-monitor.test.ts     # EDIT
│   ├── queue-monitor.ts         # NEW
│   └── queue-monitor.test.ts    # NEW
├── ts-supabase-edge/
│   ├── cron-monitor.ts          # EDIT
│   ├── cron-monitor.test.ts     # EDIT
│   ├── queue-monitor.ts         # NEW (per CONTEXT default — ship for parity; OQ-2)
│   └── queue-monitor.test.ts    # NEW (only if previous file ships)
├── go-fly-http/
│   ├── cron_monitor.go          # NO CHANGE (Go uses native sentry.MonitorSchedule)
│   └── (no queue_monitor.go)    # D-12 — out of scope
└── openrouter-monitor/
    └── src/observability/
        ├── cron-monitor.ts      # ⚠️ bundled subtree — DO NOT TOUCH (separate Phase 24 surface, pinned @sentry/cloudflare ^8.0.0)
        └── (consider whether D-03/D-05 leakage applies)

migrations/
├── 0019-sentry-crons-and-healthz.md     # DOCS amendment (D-02, D-11)
└── test-fixtures/0019/
    ├── 01-fresh-apply/                  # existing
    ├── 02-already-applied/              # existing
    ├── 03-hand-modified-refuse/         # existing
    ├── 04-no-scheduled-handlers-project/ # existing
    ├── 05-multi-module-root/            # existing
    ├── 06-multi-root-mixed-clean-dirty-refuses-all/ # existing
    ├── 07-allow-partial-emits-patches/  # existing (Phase 23)
    ├── 07-react-vite-only/              # existing
    ├── 08-index-ts-anchored-worker/     # NEW (D-15 — cf-worker variant)
    └── 09-index-ts-anchored-pages/      # NEW (D-15 — cf-pages variant)

templates/.claude/scripts/
└── migrate-0019-sentry-crons-and-healthz.sh   # EDIT (D-01, D-11)

docs/decisions/
├── 0031-0019-engine-index-ts-anchor-alias.md  # NEW (D-01 policy)
├── 0032-cron-monitor-generic-narrowing.md     # NEW (D-05 API stability)
└── 0033-with-queue-monitor.md                 # NEW (D-07 new export)
```

**openrouter-monitor leakage check:** The Phase 24 scaffold bundles a copy of the cron-monitor.ts (CONTEXT D-09 reads: "openrouter-monitor — NOT touched this phase (separate Phase 24 surface)"). The bundled copy at `add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` will NOT receive D-03/D-05 updates this phase. **Planner risk:** future Phase 24 scaffold consumers using `withCronMonitor` with `schedule.interval` will still hit the bug. Recommend Phase 25 plan flag this as a Phase 26 candidate ("bundled subtree sync with template fixes"), OR include in Phase 25 scope (low-risk, byte-symmetric edit). My recommendation: include in scope; the bundled subtree is supposed to mirror the upstream template, and Phase 25's whole point is bringing them into structural parity.

### Pattern 1: Guarded Shape A — withQueueMonitor (template canonical block)

**Source canon: ADR-0029, CONTEXT D-08**

```typescript
// Source: add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:119-152 (mirror for queue)
// Source: docs/decisions/0029-cron-monitor-sdk-composition.md (Guarded Shape A)
import * as Sentry from "@sentry/cloudflare";

export interface CronMonitorConfig { /* reused from cron-monitor.ts */ }

const QUEUE_SLUG_ENV_PREFIX = "SENTRY_CRON_MONITOR_SLUG_";   // mirrors cron prefix per D-09

function isConfigured(env: { SENTRY_DSN?: string }): boolean {
  return typeof env.SENTRY_DSN === "string" && env.SENTRY_DSN.length > 0;
}

function resolveQueueSlug<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  config: CronMonitorConfig | undefined,
  env: E,
  batch: MessageBatch<unknown>,
): string {
  if (config?.monitorSlug) return config.monitorSlug;
  const handlerName = config?.handlerName ?? "queue";
  const envKey = QUEUE_SLUG_ENV_PREFIX + handlerName.toUpperCase().replace(/-/g, "_");
  const fromEnv = (env as unknown as Record<string, unknown>)[envKey];
  if (typeof fromEnv === "string" && fromEnv.length > 0) return fromEnv;
  const serviceName = typeof env.SERVICE_NAME === "string" ? env.SERVICE_NAME : "service";
  return `${serviceName}:queue:${batch.queue}`;
}

export function withQueueMonitor<
  E extends { SENTRY_DSN?: string; SERVICE_NAME?: string },
  Msg = unknown,
>(
  handler: (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => void | Promise<void>,
  config?: CronMonitorConfig,
): (batch: MessageBatch<Msg>, env: E, ctx: ExecutionContext) => Promise<void> {
  return async (batch, env, ctx) => {
    if (!isConfigured(env)) {
      await handler(batch, env, ctx);
      return;
    }
    const monitorSlug = resolveQueueSlug(config, env, batch);
    const monitorConfig = buildMonitorConfig(config); // reused from cron-monitor.ts (D-07)
    let handlerStarted = false;
    try {
      await Sentry.withMonitor(
        monitorSlug,
        () => {
          handlerStarted = true;
          return handler(batch, env, ctx);
        },
        monitorConfig,
      );
    } catch (err) {
      if (!handlerStarted) {
        await handler(batch, env, ctx);
        return;
      }
      throw err;
    }
  };
}
```

**Notes:**
1. Default `handlerName` is `"queue"` (vs cron's `"scheduled"`). Slug env-key naming: `SENTRY_CRON_MONITOR_SLUG_QUEUE`. **Open question for planner:** is `SENTRY_CRON_MONITOR_SLUG_*` the right prefix for queue monitors, or do we introduce `SENTRY_QUEUE_MONITOR_SLUG_*`? CONTEXT D-09 says "mirror D6 3-source" — the existing prefix is operator-facing convention, and Sentry treats them as the same `monitor_slug` field server-side. Recommendation: reuse `SENTRY_CRON_MONITOR_SLUG_*` for consistency (one env-naming rule), document in queue-monitor doc comment.
2. **Reuse vs duplication of `CronMonitorConfig` + helpers:** CONTEXT D-07 says "no duplication needed". The planner has two options:
   - (a) **Import from `./cron-monitor`:** `import { CronMonitorConfig, buildMonitorConfig } from "./cron-monitor"`. Smallest diff. Couples queue-monitor.ts to cron-monitor.ts at import time, which is fine since 0019 always copies both.
   - (b) **Duplicate inline:** copy `CronMonitorConfig` interface + `buildMonitorConfig` helper. Larger diff but no inter-file dependency. Matches the rest-of-template "import in isolation" posture (CONTEXT G1 in Phase 22).
   - **Recommendation:** option (a) for ts-cloudflare-worker/pages (where both files always co-exist post-migration). For ts-supabase-edge, the cron-monitor uses Deno-specific `_setWithMonitorForTest` seam — queue-monitor probably needs similar treatment if it ships there. Planner picks.

### Pattern 2: Discriminated-union CronMonitorSchedule (D-03 canonical edit)

```typescript
// BEFORE (cron-monitor.ts:20-23 in all 3 TS stacks):
export interface CronMonitorSchedule {
  type: "crontab" | "interval";
  value: string;
}

// AFTER (D-03):
export type CronMonitorSchedule =
  | { type: "crontab"; value: string }
  | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" };
```

**Validation test pattern (D-16) — type-level assertion via vitest's `expectTypeOf`:**

```typescript
import { expectTypeOf } from "vitest";
import type { CronMonitorSchedule } from "./cron-monitor";

it("CronMonitorSchedule.interval requires value:number + unit", () => {
  // CRONTAB: regression — accepts value: string
  expectTypeOf<CronMonitorSchedule>().toMatchTypeOf<{ type: "crontab"; value: string }>();

  // INTERVAL: requires value: number + unit
  type IntervalVariant = Extract<CronMonitorSchedule, { type: "interval" }>;
  expectTypeOf<IntervalVariant>().toHaveProperty("value").toBeNumber();
  expectTypeOf<IntervalVariant>().toHaveProperty("unit").toEqualTypeOf<
    "minute" | "hour" | "day" | "week" | "month" | "year"
  >();

  // Negative: ensure value: string on interval no longer compiles
  // @ts-expect-error — interval requires value: number, not string
  const bad: CronMonitorSchedule = { type: "interval", value: "5", unit: "minute" };
  void bad;
});
```

### Pattern 3: Generic narrowing (D-05 canonical edit)

```typescript
// BEFORE (cron-monitor.ts:115 — worker; analogous in pages/supabase-edge):
export function withCronMonitor<E extends Record<string, unknown>>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E> { /* ... */ }

// AFTER (D-05):
export function withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E> { /* ... */ }
```

**Inside `resolveSlug` (cron-monitor.ts:58-76), the env-key access becomes:**

```typescript
// BEFORE:
const fromEnv = env[envKey];

// AFTER (D-05 — one cast at the access site):
const fromEnv = (env as unknown as Record<string, unknown>)[envKey];
```

**Validation test pattern (D-16):** the test passes a strict-typed `Env` interface that the OLD signature rejected:

```typescript
interface CallbotEnv {
  SENTRY_DSN: string;
  SERVICE_NAME: string;
  SUPABASE_URL: string;
  // NO index signature — this is what failed pre-D-05
}

it("accepts strict-typed Env interface (no index signature required)", async () => {
  const handler = vi.fn(async () => {});
  // This should compile against the new generic constraint.
  const wrapped = withCronMonitor<CallbotEnv>(handler, { monitorSlug: "callbot:ingest" });
  await wrapped(
    fakeController,
    { SENTRY_DSN: "https://stub@sentry.io/1", SERVICE_NAME: "callbot", SUPABASE_URL: "https://s.co" },
    fakeCtx,
  );
  expect(handler).toHaveBeenCalledOnce();
});
```

### Anti-Patterns to Avoid

- **Don't change the canonicaliser (`canonicalize_awk`, `:362-446`).** Per `migrations/0019-sentry-crons-and-healthz.md:260-263`: "Any future refinement should land in 0017 FIRST and be back-ported here, not diverged." The D-01 fix touches discovery (find) and classification (classify_stack + stack_fingerprint_files), NOT canonicalisation. If `index.ts` and `lib-observability.ts` produce the same canonical hash (both files have the same content before token-substitution), this is automatic.
- **Don't unify cron and queue env-var prefixes asymmetrically.** Use `SENTRY_CRON_MONITOR_SLUG_*` for both — Sentry server-side doesn't distinguish cron vs queue at the monitor-slug field, and operators get one naming convention to learn.
- **Don't hand-roll a queue-monitor mock fixture in tests.** Reuse `vi.mock("@sentry/cloudflare", () => ({ withMonitor: ... }))` from `cron-monitor.test.ts`. Hand-rolled `MessageBatch` stub: cast a minimal `{ queue: "test-queue", messages: [] }` as `MessageBatch<unknown>` — the template harness's `tsconfig.json` uses `skipLibCheck: true` so the ambient `MessageBatch` type lookup is implicit, no need to install `@cloudflare/workers-types` in the harness.
- **Don't introduce a `--force` flag prematurely.** Per `## Open Questions` OQ-5, no `--force` flag exists today. CONTEXT D-02 hand-waves "re-run via `npx claude-workflow migrate 0019 --force`", but the engine has no such flag. Adding one would require new code paths + new fixtures. The truer recovery is: delete `cron-monitor.{ts,go}` and `queue-monitor.{ts,go}`, downgrade `skill/SKILL.md` `version: 1.17.0`, re-run engine. Plan should either ship the `--force` flag explicitly OR document this manual recovery, not both.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| In-progress/ok/error check-in lifecycle | Hand-rolled `Sentry.captureCheckIn(in_progress)` + duration timing + `captureCheckIn(ok|error)` | `Sentry.withMonitor(slug, callback, monitorConfig?)` | ADR-0029 — already established. Lifecycle, duration tracking, async thenable handling are SDK responsibilities. Phase 23 proved Guarded Shape A composes correctly. |
| Slug resolution for queue handler | New slug-resolution helper from scratch | Mirror `resolveSlug()` from `cron-monitor.ts:58-76` | 3-source resolution (D6/D-09) is established convention. Differ only in the auto-derive branch (`batch.queue` vs `controller.cron`). |
| MonitorSchedule type | Re-export `MonitorSchedule` from `@sentry/cloudflare` | Discriminated-union literal per D-03 | DISCUSSION-LOG explicitly rejected re-export: SDK-version-drift risk. Keep our type structurally compatible. |
| MessageBatch stub for tests | Class-based mock with internal state | Cast minimal `{ queue, messages: [] }` literal as `MessageBatch<unknown>` | Tests assert wrapper behaviour, not Cloudflare runtime semantics. Minimal stub suffices and matches `cron-monitor.test.ts:32` pattern (`{...} as ScheduledController`). |
| Migration filename-renaming convention | Custom 0019.1 naming | Either a new migration ID (e.g., 0021 — see Open Questions) or in-place re-rev per existing migration history | `migrations/README.md` says nothing about `.1`-style filenames; the chain is `from_version`/`to_version` based. Filename is documentation, not contract. |
| Engine `--force` flag | Bespoke `--force` that ignores `cron-monitor.ts` presence | Either rely on existing idempotency contract (skip → bump → done) OR document manual recovery (delete files + downgrade SKILL) | No `--force` exists today. Adding one expands engine surface for one niche path. |

**Key insight:** Every novel concept this phase shares structure with an existing concept. `withQueueMonitor` is `withCronMonitor` with a different handler signature. Engine `index.ts` alias is the same shape as the existing supabase-edge `index.ts` handling. Discriminated-union schedule is what Sentry already ships internally. **Plan should keep diffs symmetric and small.**

## Runtime State Inventory

> Phase 25 is a refactor + new-feature phase. Most categories don't apply (no stored data renamed, no live service config). Documented explicitly so planner has confidence we checked.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None.** Phase 25 does not rename any database keys, collection names, user IDs, or stored records. The `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` env-key convention is preserved (cron + queue use the same prefix per recommendation in `## Architecture Patterns Pattern 1 note 1`). | None. |
| Live service config | **One known consideration.** Sentry monitors (server-side) are auto-provisioned by `withMonitor`'s `upsertMonitorConfig` 2nd arg when set. Operators with multi-cron projects who provisioned monitors manually under specific slugs will not be affected — the slug-resolution policy (D6 / D-09) is unchanged in priority. | None — no operator action required. |
| OS-registered state | **None.** No OS-level registrations embed any string Phase 25 changes. | None. |
| Secrets/env vars | **One pre-existing convention preserved.** `SENTRY_CRON_MONITOR_SLUG_<HANDLER>` env-key naming kept for queue-monitor too (per planner recommendation). No new env vars introduced. `SENTRY_DSN` and `SERVICE_NAME` still required — but they were already in the (untyped) constraint, so this is no change. | None for operator. |
| Build artifacts / installed packages | **One real item.** Projects that already shipped 0019 carry `cron-monitor.ts` + `healthz-snippet.ts`. They do NOT carry `queue-monitor.ts`. Re-running 0019 (with the engine fix) hits `SKIP_ALREADY` and does not deploy `queue-monitor.ts`. **This is the runner-contract finding** — see `## Open Questions` OQ-1 and `## Engine Fix Sites § D-11 caveat`. | Planner-level decision required: ship migration 0021, OR document manual `cron-monitor.ts` deletion + downgrade SKILL.md + re-run as recovery, OR change idempotency marker. |

**Verified by:** `migrations/README.md:60-99` (runner contract); `migrate-0019-…sh:506-510` (idempotency check); existing fixture `02-already-applied/setup.sh` (idempotency behaviour). `grep -rn "force" migrate-0019-…sh` returned no results.

## Common Pitfalls

### Pitfall 1: `index.ts` over-matching pollutes ROOTS

**What goes wrong:** Naively adding `-name index.ts` to the find candidate set picks up every `index.ts` in `dist/`, `build/`, generated code, sibling source files. The classify_stack returns `unknown` for these, routing to `SKIP_UNSUPPORTED`, which is FAIL-CLOSED safe — but the engine output now lists 50+ "unsupported" lines per project, swamping the operator-facing summary.

**Why it happens:** `index.ts` is the most generic filename in TS projects. Existing find candidates (`lib-observability.ts`, `observability.go`, `middleware.go`) are unique enough that an unscoped find works. `index.ts` is not.

**How to avoid:** Either (a) filter candidates pre-classify (require sibling `middleware.ts` or `_middleware.ts` exists), or (b) scope the find with `-path` filters. Recommend (a) — aligns with the existing supabase-edge filter (`_filter_supabase_edge_roots`).

**Warning signs:** During Wave 1 implementation, run the engine in `--dry-run` mode against a real project (e.g., `~/Sourcecode/factiv/callbot` or the openrouter-monitor scaffold itself, which has `src/observability/index.ts`). Count the ROOTS array length. If > 10 for a single-wrapper project, the filter is too loose.

### Pitfall 2: Migration runner contract — re-revving 0019 does not replay on already-migrated projects

**What goes wrong:** Re-revving 0019 in place (per CONTEXT D-02) leaves callbot v1.19.0 stuck. The migration runner's `from_version`/`to_version` matching (`migrations/README.md:60-99`) skips any migration whose `from_version` is below the project's installed version. callbot at 1.19.0 will never re-trigger 0019 (`from_version: 1.17.0`) — so the engine fix (D-01) and the new queue-monitor copy (D-11) never apply.

**Why it happens:** CONTEXT D-02 conflates two scenarios — (a) project at 1.17.0 that previously failed 0019 due to anchor mismatch (engine fix resolves), and (b) project at 1.18.0/1.19.0 that ran 0019 hand-applied or via Phase 22's engine (engine fix doesn't help; queue-monitor is missing). Case (b) is what callbot is in.

**How to avoid:** Planner must explicitly resolve this. Options:
- **(a)** Ship migration 0021 (`from_version: 1.19.0` → `to_version: 1.20.0`) that ONLY copies `queue-monitor.{ts,go}` if absent (additive, matches the 0019 idempotency shape). Engine fix in 0019 still ships but applies only to pre-1.18.0 projects.
- **(b)** Modify 0019's idempotency check to require BOTH `cron-monitor.ts` AND `queue-monitor.ts` to be present before `SKIP_ALREADY`. Then re-revving 0019 with a higher `to_version: 1.20.0` AND a wider `from_version` matcher (e.g., supporting `1.17.*|1.18.*|1.19.*`) triggers re-application on partially-installed projects. **Caveat:** the runner uses exact-match on `from_version` per README, not glob-match. Glob support would be a runner-level change — out of scope for Phase 25.
- **(c)** Document manual recovery in `0019-sentry-crons-and-healthz.md`'s new "Recovery" section: "Already on 1.18.0+? `rm <wrapper>/cron-monitor.ts <wrapper>/healthz-snippet.ts`; downgrade `skill/SKILL.md version: 1.17.0`; re-run engine via the new claude-workflow 1.20.0 install." This is the most honest path; matches what callbot did manually.
- **(d)** Combination: docs amendment for case (a) (which works trivially post-fix) + ship migration 0021 for case (b) (the additive queue-monitor).

**Recommendation:** option (d). Migration 0021 is small (one file copy, idempotency = `queue-monitor.ts` presence), and 0019's docs amendment covers the engine-fix case. Avoids retrofitting the runner contract.

**Warning signs:** if the planner picks "no new migration", the VERIFICATION step MUST include a synthetic v1.19.0 → 1.20.0 fixture demonstrating the recovery path works end-to-end, otherwise the "callbot can adopt v1.20.0 cleanly" success criterion (SC5) is unverified.

### Pitfall 3: openrouter-monitor bundled subtree drifts from upstream template

**What goes wrong:** Phase 24 bundled a snapshot of `ts-cloudflare-worker/cron-monitor.ts` into `add-observability/templates/openrouter-monitor/src/observability/`. Phase 25 fixes the template at `ts-cloudflare-worker/cron-monitor.ts`, but if the planner doesn't ALSO update the bundled copy, a new openrouter-monitor scaffolded project ships with the OLD (broken) `CronMonitorSchedule` shape — defeating one of Phase 25's stated goals.

**Why it happens:** Phase 24 deliberately bundled the subtree (CONTEXT D-09 of Phase 24: "Monitor scaffold bundles the observability subtree"). The bundling is point-in-time; there's no symlink or build step to keep them in sync.

**How to avoid:** Include the bundled `openrouter-monitor/src/observability/cron-monitor.ts` in D-03/D-05 fix sites. Treat the bundled copy as a fourth (test-isolated) mirror. The diff is symmetric to ts-cloudflare-worker (same source file, byte-for-byte).

**Warning signs:** post-execute, run `diff add-observability/templates/ts-cloudflare-worker/cron-monitor.ts add-observability/templates/openrouter-monitor/src/observability/cron-monitor.ts` — should be empty.

### Pitfall 4: Test harness skipLibCheck masks discriminated-union compatibility regression

**What goes wrong:** The template test harness (`run-template-tests.sh:179-188`) writes a `tsconfig.json` with `skipLibCheck: true`. This means `Sentry.MonitorSchedule` type compatibility (the WHOLE POINT of D-03) is never asserted at typecheck time — only the literal shape of the local `CronMonitorSchedule` type is checked. Tests can pass even if the type still doesn't structurally match Sentry's.

**Why it happens:** `skipLibCheck` is required because `@sentry/cloudflare`'s type definitions reference ambient Cloudflare types the harness doesn't install. Removing `skipLibCheck` would require adding `@cloudflare/workers-types` to the harness — out of scope.

**How to avoid:** Add a type-level assertion in `cron-monitor.test.ts` that explicitly checks `CronMonitorSchedule` is assignable to `Sentry.MonitorConfig['schedule']`. Use `vitest`'s `expectTypeOf` or a hand-rolled `const _check: Sentry.MonitorConfig['schedule'] = ourSchedule;` pattern. This makes the contract enforcement explicit in the test file rather than implicit in the harness.

**Warning signs:** if a test asserts only that `withMonitor` was called with a specific 3rd argument structure (existing pattern at `cron-monitor.test.ts:55`), the type compatibility is NOT being asserted — only runtime equality is. The type-level test is the firewall.

### Pitfall 5: Reusing CronMonitorConfig from cron-monitor.ts inside queue-monitor.ts creates a re-export tax

**What goes wrong:** If `queue-monitor.ts` does `import { CronMonitorConfig } from "./cron-monitor"`, then projects that copy queue-monitor.ts WITHOUT cron-monitor.ts (e.g., a pure-queue-consumer Worker) have a broken import. Phase 25's migration always copies both, so this is fine in practice — but it constrains the templates to always-co-copy.

**Why it happens:** The CronMonitorConfig interface is small (3 fields) and re-using is tempting.

**How to avoid:** Two viable choices:
- (a) Always co-copy via 0019 (D-11 already does this). Accept the import dependency.
- (b) Duplicate the interface inline in queue-monitor.ts. Larger diff, cleaner contract.

**Recommendation:** (a) for now, with a doc comment `// CronMonitorConfig is shared between cron-monitor.ts and queue-monitor.ts; both files are always copied together by migration 0019`. If a downstream wants queue-only adoption later, refactor then.

## Code Examples

### Example 1: D-03 + D-05 combined edit (ts-cloudflare-worker/cron-monitor.ts diff)

```typescript
// Source: based on add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:20-23, :115

// BEFORE (lines 20-23):
export interface CronMonitorSchedule {
  type: "crontab" | "interval";
  value: string;
}

// AFTER (D-03):
export type CronMonitorSchedule =
  | { type: "crontab"; value: string }
  | { type: "interval"; value: number; unit: "minute" | "hour" | "day" | "week" | "month" | "year" };

// BEFORE (line 115, line 58):
export function withCronMonitor<E extends Record<string, unknown>>(/* ... */)
function resolveSlug<E extends Record<string, unknown>>(/* ... */) {
  const fromEnv = env[envKey];     // line 69
}

// AFTER (D-05):
export function withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(/* ... */)
function resolveSlug<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(/* ... */) {
  const fromEnv = (env as unknown as Record<string, unknown>)[envKey];
}
```

The `isConfigured` helper currently takes `env: Record<string, unknown>` (line 47). Narrow its argument to `env: { SENTRY_DSN?: string }` for consistency, or `env: { SENTRY_DSN?: unknown }` to keep the runtime type-check identical:

```typescript
// BEFORE (line 47):
function isConfigured(env: Record<string, unknown>): boolean {
  return typeof env.SENTRY_DSN === "string" && (env.SENTRY_DSN as string).length > 0;
}

// AFTER (D-05 — argument narrowed):
function isConfigured(env: { SENTRY_DSN?: string }): boolean {
  return typeof env.SENTRY_DSN === "string" && env.SENTRY_DSN.length > 0;
}
```

### Example 2: Test fixture — `index.ts`-anchored cf-worker (D-15)

```bash
# Source: based on migrations/test-fixtures/0019/01-fresh-apply/setup.sh
# File: migrations/test-fixtures/0019/08-index-ts-anchored-worker/setup.sh
#!/usr/bin/env bash
# Fixture 08 — fresh apply on a single clean v1.17.0 cf-worker wrapper anchored at
# index.ts (canonical materialised filename per meta.yaml; the issue #56 / Finding 1
# regression case). Expect: engine recognises the wrapper, applies cron-monitor.ts +
# healthz-snippet.ts + queue-monitor.ts (D-11), bumps version to 1.18.0, exits 0.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Seed the same v1.17.0 wrapper bytes but write to index.ts instead of lib-observability.ts.
ROOT="src/lib/observability"
mkdir -p "$ROOT"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$ROOT/index.ts"
cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/middleware.ts"        "$ROOT/middleware.ts"
```

```bash
# File: migrations/test-fixtures/0019/08-index-ts-anchored-worker/verify.sh
#!/usr/bin/env bash
# Verify fixture 08: clean cf-worker root anchored at index.ts migrated.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
ROOT="src/lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

test -f "$ROOT/cron-monitor.ts"    || { echo "cron-monitor.ts not installed"; exit 1; }
test -f "$ROOT/healthz-snippet.ts" || { echo "healthz-snippet.ts not installed"; exit 1; }
test -f "$ROOT/queue-monitor.ts"   || { echo "queue-monitor.ts not installed (D-11)"; exit 1; }
grep -q '^version: 1.18.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "version not bumped to 1.18.0"; exit 1; }

# index.ts is preserved (engine did not overwrite the anchor).
test -f "$ROOT/index.ts" || { echo "index.ts disappeared"; exit 1; }

echo "fixture 08 OK — index.ts-anchored cf-worker migrated cleanly"
```

Echo the fixture for cf-pages anchored at `index.ts` with `_middleware.ts` co-anchor (fixture 09).

```bash
# File: migrations/test-fixtures/0019/08-index-ts-anchored-worker/expected-exit
0
```

### Example 3: ADR-0031 skeleton (D-01 policy)

```markdown
<!-- File: docs/decisions/0031-0019-engine-index-ts-anchor-alias.md -->
# 0031 — 0019 engine accepts `index.ts` as canonical anchor

**Status**: Accepted  **Date**: 2026-05-31  **Phase**: 25-fix-0019-engine-and-cron-wrappers

## Context

Migration 0019's apply engine (`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`) discovered wrapper roots by looking for `lib-observability.ts` (cf-worker, cf-pages) or `observability.go` (go-fly-http) or `index.ts` scoped to `*/_shared/observability/` (supabase-edge). But `add-observability/templates/ts-cloudflare-worker/meta.yaml:target.wrapper_path` is `src/lib/observability/index.ts`, NOT `lib-observability.ts`. The template SOURCE file is named `lib-observability.ts`; the materialised TARGET file is `index.ts`. Same for cf-pages: `functions/_lib/observability/index.ts`. The engine never matched real materialised projects — only the test fixtures, which hand-seeded the SOURCE filename.

Issue #56 surfaced this when callbot (v1.16.0 → v1.19.0) attempted to apply 0019 and the engine reported "no wrappers found" with exit 0.

## Decision

Engine accepts `index.ts` AND `lib-observability.ts` as anchor filenames for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks. The `middleware.ts` (cf-worker) / `_middleware.ts` (cf-pages) co-anchor requirement remains — guards against unintended matches in unrelated dirs. The engine's content-hash canonicaliser is unchanged: both filenames hash to the same canonical fingerprint because they carry the same content.

## Alternatives Rejected

| Approach | Why rejected |
|----------|--------------|
| Rename template source files to `index.ts` | Breaks 1:1 SOURCE/TARGET symmetry; SOURCE filename serves as the canonical token-substitution origin and shouldn't be auto-renamed. |
| REFUSE on `index.ts` with rename hint | Friction for downstream projects (callbot, cparx). Engine is supposed to "just work" on existing-shape projects. |
| Hybrid alias-with-warning | Engine output noise vs operator value; silent alias is consistent with how `lib-observability.ts` was previously silently accepted in fixtures. |

## Consequences

- The 0019 engine now recognises any project scaffolded since 1.16.0 (canonical materialised path). Pre-engine-fix workarounds (hand-applied 0019) are no longer needed.
- Test fixtures gain coverage for `index.ts`-anchored wrappers (08-index-ts-anchored-worker, 09-index-ts-anchored-pages). The existing `lib-observability.ts`-seeded fixtures continue to pass — both filenames classify as the same stack.
- No spec change. No new ADR-supersedes (extends 0028).
```

Analogous skeletons for ADR-0032 (D-05 generic API stability) and ADR-0033 (D-07 withQueueMonitor new export).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `interface CronMonitorSchedule { type: "crontab" \| "interval"; value: string }` | Discriminated-union type alias matching Sentry's `MonitorSchedule` | Phase 25 (this) | Eliminates consumer-side casts; closes Finding 2 of issue #56. |
| `withCronMonitor<E extends Record<string, unknown>>` | `<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>` | Phase 25 | Strict-typed `Env` interfaces now satisfy the constraint without index-signature pollution; closes Finding 3. |
| No queue handler wrapper | `withQueueMonitor` with Guarded Shape A | Phase 25 | Closes Finding 4; symmetric with `withCronMonitor`. |
| Engine looks for `lib-observability.ts` only (cf-worker/pages) | Engine accepts `index.ts` OR `lib-observability.ts` (alias) | Phase 25 | Closes Finding 1; brings engine in line with `meta.yaml`'s canonical target path. |
| Hand-rolled `captureCheckIn` lifecycle | `Sentry.withMonitor` SDK helper (Guarded Shape A) | Phase 23 (ADR-0029) | Established. Both cron and queue wrappers follow. |
| Manual D11 multi-cron escape hatch (silent + docs) | Same for multi-queue (D-10 mirrors D11) | Phase 25 | Symmetric convention; planner picks enforcement shape (OQ-3 — recommend silent + docs for symmetry). |

**Deprecated/outdated:**

- Pre-Guarded Shape A patterns (raw `Sentry.withMonitor` wrap without `handlerStarted` flag): rejected in ADR-0029 due to "cron skipped on pre-callback transport error" regression. Phase 25 inherits this — queue-monitor MUST use Guarded Shape A.
- `--force` flag on 0019 engine: **never existed**, despite CONTEXT D-02 mentioning it. Planner must either add it explicitly or document manual recovery.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| bash | engine script + test fixtures | ✓ | system (3.2+ required per engine compat comment :264) | — |
| awk (POSIX) | canonicalize_awk | ✓ | system | — |
| sha256sum / shasum | content-hash | ✓ | system (engine has portable fallback at :143-149) | — |
| node + npm | template test harness | ✓ | 24.15.0 ([VERIFIED]) | — |
| vitest | `*.test.ts` files | ✓ (installed via harness) | template harness pins `^3.0.0`; latest `4.1.7` | — |
| `@sentry/cloudflare` | template imports + test harness `npm install` | ✓ (harness installs `^8.0.0`) | template harness pins `^8.0.0` ([VERIFIED:](`add-observability/templates/run-template-tests.sh:174`)); latest registry `10.55.0` (does not apply) | — |
| `@cloudflare/workers-types` | ambient `MessageBatch`, `ScheduledController`, `ExecutionContext` | template harness does NOT install (uses `skipLibCheck`); openrouter-monitor scaffold DOES install (`^4.20240909.0`) | latest `4.20260531.1` ([VERIFIED:](`npm view`)) | minimal hand-rolled stub `as MessageBatch<unknown>` in tests (existing pattern at `cron-monitor.test.ts:32` uses this for `ScheduledController`). |
| `npm:@sentry/deno@^8.0.0` | ts-supabase-edge stack | resolved at test-time via Deno specifier | template uses `^8.0.0` ([CITED:](`ts-supabase-edge/cron-monitor.ts:28`)) | — |
| `getsentry/sentry-go v0.31.0` | go-fly-http stack | resolved at test-time via Go module | template pins `v0.31.0` ([CITED:](`run-template-tests.sh`)) | — |
| GitNexus index | impact analysis per CLAUDE.md | ✓ assumed (CLAUDE.md instructs `npx gitnexus analyze` if stale) | — | proceed with manual symbol mapping if MCP unavailable. |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** `@cloudflare/workers-types` for the template harness — fallback is the existing `as <type>` cast pattern.

## Validation Architecture

Phase 25 inherits the `workflow.nyquist_validation` posture (no explicit `false` in `.planning/config.json`, so treated as enabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework (TS templates) | `vitest ^3.0.0` (harness-pinned) / `^4.1.7` (registry latest); test files: `*.test.ts` per stack template dir |
| Framework (engine fixtures) | bash + harness (`migrations/run-tests.sh`); fixture dirs under `migrations/test-fixtures/0019/` |
| Framework (Go) | `go test` — not exercised this phase (D-12 — no `queue_monitor.go` ships) |
| Config files | `add-observability/templates/run-template-tests.sh` (writes ephemeral `tsconfig.json` + `vitest.config.ts` per stack); `migrations/run-tests.sh` (dispatcher) |
| Quick run command (cron+queue tests, per stack) | `bash add-observability/templates/run-template-tests.sh ts-cloudflare-worker` |
| Full suite command | `bash add-observability/templates/run-template-tests.sh all && bash migrations/run-tests.sh` |
| Phase gate | Full suite green AND `tsc --noEmit` against synthetic strict-Env fixture passes — see callbot acceptance check below |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-01 | Engine accepts `index.ts` anchor for cf-worker | bash fixture | `bash migrations/run-tests.sh test_migration_0019_08_index_ts_anchored_worker` | ❌ Wave 0 (new fixture) |
| D-01 | Engine accepts `index.ts` anchor for cf-pages | bash fixture | `bash migrations/run-tests.sh test_migration_0019_09_index_ts_anchored_pages` | ❌ Wave 0 (new fixture) |
| D-01 | Existing `lib-observability.ts` fixtures still pass | bash regression | `bash migrations/run-tests.sh` (all 0019 fixtures) | ✅ |
| D-03 | `CronMonitorSchedule` interval-variant rejects `value: string` | TS type-level (`@ts-expect-error`) | `npx vitest run cron-monitor.test.ts` (per stack) | ✅ (test file exists; assertion is NEW) |
| D-03 | `CronMonitorSchedule.crontab` still accepts `value: string` | TS regression | same test file | ✅ |
| D-04 | type-shape change non-breaking on existing fixtures | TS regression | full template suite | ✅ |
| D-05 | strict-typed `Env` (no index signature) satisfies generic | TS type-level + runtime | `npx vitest run cron-monitor.test.ts` | ✅ (file exists; test is NEW) |
| D-05 | env-var slug lookup still works through cast | TS runtime | same test file | ✅ |
| D-07 | `withQueueMonitor` exported with correct signature | TS type-level + runtime | `npx vitest run queue-monitor.test.ts` (NEW) | ❌ Wave 0 |
| D-08 | Pre-callback Sentry transport failure → handler runs unmonitored | TS runtime mock | NEW queue-monitor.test.ts | ❌ Wave 0 |
| D-08 | Post-callback error propagates | TS runtime mock | NEW queue-monitor.test.ts | ❌ Wave 0 |
| D-09 | 3-source slug resolution (explicit > env > auto) | TS runtime mock | NEW queue-monitor.test.ts | ❌ Wave 0 |
| D-09 | Auto-derive uses `${SERVICE_NAME}:queue:${batch.queue}` | TS runtime mock | NEW queue-monitor.test.ts | ❌ Wave 0 |
| D-10 | Multi-queue explicit-slug enforcement (planner picks shape) | (see OQ-3) | depends on shape | depends |
| D-11 | Migration 0019 copies `queue-monitor.ts` to fresh wrapper | bash fixture | `bash migrations/run-tests.sh test_migration_0019_01_fresh_apply` (existing fixture, extended verify.sh) OR NEW fixture | ✅ (fixture exists; verify.sh needs extension) |
| D-15 | New `index.ts`-anchored fixtures pass | bash fixture | `bash migrations/run-tests.sh` (08, 09) | ❌ Wave 0 |
| D-16 | Type-level + generic + crontab tests pass per stack | TS | per-stack vitest | partial (file exists; tests NEW) |
| D-17 | Behavioural-parity tests pass per stack | TS | per-stack vitest | ❌ Wave 0 |
| SC5 — callbot/synthetic acceptance | strict-Env compiles against `withCronMonitor` + `withQueueMonitor` | TS `tsc --noEmit` | NEW synthetic fixture in `migrations/test-fixtures/0019/10-strict-env-typecheck/` OR consumer-side callbot verification | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `npx vitest run <touched-test-file>` (sub-30-second feedback)
- **Per wave merge:** per-stack `bash add-observability/templates/run-template-tests.sh <stack>` (~1-2 min) + targeted `bash migrations/run-tests.sh test_migration_0019_*` (~30s)
- **Phase gate:** full suite (`run-template-tests.sh all && run-tests.sh`) green; expect ~465 existing PASS + ~21 new tests (D-16 × 3 stacks × 3 tests + D-17 × 3 stacks × 5 tests + 2 new fixtures) = ~486 PASS.

### Wave 0 Gaps

- [ ] `migrations/test-fixtures/0019/08-index-ts-anchored-worker/{setup.sh, verify.sh, expected-exit}` — D-01 cf-worker fixture
- [ ] `migrations/test-fixtures/0019/09-index-ts-anchored-pages/{setup.sh, verify.sh, expected-exit}` — D-01 cf-pages fixture
- [ ] `migrations/test-fixtures/0019/10-strict-env-typecheck/` — synthetic callbot-shape fixture proving D-05 + D-03 compile against strict `Env` (likely a vitest+tsc fixture, not a migration fixture; placement TBD)
- [ ] `add-observability/templates/ts-cloudflare-worker/queue-monitor.test.ts` — Wave 0 RED
- [ ] `add-observability/templates/ts-cloudflare-pages/queue-monitor.test.ts` — Wave 0 RED
- [ ] `add-observability/templates/ts-supabase-edge/queue-monitor.test.ts` — Wave 0 RED (if OQ-2 ships supabase queue-monitor)
- [ ] `docs/decisions/0031-0019-engine-index-ts-anchor-alias.md` — Wave 0 (per Phase 23 precedent: ADRs land before code)
- [ ] `docs/decisions/0032-cron-monitor-generic-narrowing.md` — Wave 0
- [ ] `docs/decisions/0033-with-queue-monitor.md` — Wave 0
- [ ] `migrations/run-tests.sh` dispatcher — extend if new test names need explicit dispatcher entries (check Phase 23's `test-sigterm-mid-apply-preserves-state` pattern for naming conventions)

**Framework install:** None — `vitest` already in harness's `npm install`, bash + awk are system-provided.

## Security Domain

Phase 25 touches the Sentry SDK boundary + observability wrapper code. `security_enforcement` is not explicitly `false` in `.planning/config.json` (verified absent). Required.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 25 does not touch auth. |
| V3 Session Management | no | N/A. |
| V4 Access Control | no | No access-control surface changed. |
| V5 Input Validation | yes (low) | `withQueueMonitor` reads `batch.queue` (Cloudflare-provided, runtime-trusted) for slug auto-derive. Slug becomes a Sentry monitor identifier. **Risk: an attacker who can influence `batch.queue` (Cloudflare administrative compromise) could inject characters into the Sentry monitor slug.** Sentry server-side validates slug format. Standard control: trust the platform; no additional validation in wrapper. |
| V6 Cryptography | no | No new cryptographic surface. |
| V7 Error Handling | yes | Guarded Shape A semantics (handler always runs on pre-callback transport failure) is itself the error-handling control. Existing pattern (ADR-0029). |
| V12 Files and Resources | yes (engine) | Engine writes files into wrapper root. Existing path-canonicalization (`pwd -P`) guards against symlink attacks. D-01 widens the discovery candidate set but does NOT add new write paths. |

### Known Threat Patterns for the stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Engine writes `cron-monitor.ts` / `queue-monitor.ts` to attacker-controlled `index.ts`-anchored directory | T (Tampering) | Engine excludes paths under `SCAFFOLDER_TEMPLATES_REAL` (:213-217), excludes `node_modules` and `.git` (:220-222). D-01 add filter requires sibling `middleware.ts`/`_middleware.ts` co-anchor — this is the mitigation. |
| Slug injection via `batch.queue` or `controller.cron` | I/T | Trust Cloudflare platform-provided values. Slug ends up in a server-side Sentry call; Sentry validates. |
| `withMonitor` failure in unmonitored fallback path silently masks Sentry-side outage | D (Denial of monitoring) | Guarded Shape A is the explicit trade-off — "cron always runs" wins over "monitoring is always recorded". Operator alerts on missed Sentry checkins via Sentry-UI side rule. ADR-0029 documents the trade-off. |
| Engine accepts `index.ts` from `dist/` build output, overwrites compiled output with wrapper template | T | Pre-classify filter (sibling middleware.ts requirement) prevents matching `dist/` artefacts. Test fixture should include a "node_modules has index.ts but no middleware.ts → SKIP_UNSUPPORTED" assertion. |

**Recommendation:** add a Wave 0 negative fixture (`migrations/test-fixtures/0019/11-stray-index-ts-no-co-anchor/`) demonstrating engine SKIP_UNSUPPORTED behaviour when an `index.ts` exists without `middleware.ts` co-anchor. Prevents Pitfall 1 from regressing.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Sentry's runtime tolerates `MonitorConfig.schedule` being absent when `maxRuntime` is set | Sentry Type Verification (D-03 impact note 2) | Wrapper sends a `withMonitor` call without `schedule`. If Sentry SDK throws or rejects, the runtime test must catch it. Mitigation: regression test "only maxRuntime, no schedule, withMonitor still called". |
| A2 | `@sentry/cloudflare ^8.0.0` and `^10.x` share the same `MonitorSchedule` discriminated-union shape | Sentry Type Verification | If Sentry 10.x changed the unit enum (e.g., added `second`), our union is too narrow and consumer-side `tsc` may flag incompatibility against the wider type. Mitigation: verify against Sentry 10.x types if a downstream consumer pins to 10.x explicitly. Phase 24 already pins `^10.2.0` for AI Monitoring consumers — they should be verified. |
| A3 | Cloudflare's `MessageBatch.queue` field is the queue NAME, not a queue ID | Cloudflare MessageBatch verification | Auto-derive slug becomes ID-shaped (UUID) instead of human-readable. Cosmetic, not functional. Mitigation: operator can always pass explicit `monitorSlug`. |
| A4 | The bundled openrouter-monitor `cron-monitor.ts` should receive D-03/D-05 fixes | Pitfall 3 | If left out of scope, Phase 24 scaffold consumers still hit the bug. Mitigation: include in plan; symmetric edit. |
| A5 | Migration runner contract (README.md:60-99) is enforced strictly — no glob `from_version` matching | Pitfall 2 / Open Questions | If runner DOES support glob `from_version`, option (b) of Pitfall 2 mitigation is viable and simpler than option (a). Mitigation: planner reads `update` skill source code (or any tool that processes the migration runner) to confirm exact-match semantics. |
| A6 | Plan can decide OQ-3 (multi-queue enforcement shape) silently per Phase 22 D11 precedent — no user re-consultation needed | Open Questions OQ-3 | If user has changed their mind on enforcement style, Phase 25 ships a different policy than the user expected. Mitigation: CONTEXT.md explicitly punts OQ-3 to planner; recommendation: silent + docs (same as Phase 22 D11). |
| A7 | Engine `--force` flag was conceptual, not real | Open Questions OQ-5 / Common Pitfalls 2 | If a `--force` flag does exist somewhere I missed (e.g., in a wrapper script), the planner skips adding it. Mitigation: `grep -rn '\\-\\-force' templates/.claude/scripts/` was empty — confirmed. |

**Empty mitigations are NOT acceptable** — every assumption above either has a verifying test or a documented trade-off.

## Open Questions

1. **OQ-1 (CONTEXT-elevated): how do already-migrated projects (callbot at v1.19.0) pick up the engine fix + new `queue-monitor.{ts,go}`?**
   - What we know: Migration runner matches `from_version` exactly per `migrations/README.md:60-99`. Re-revving 0019 with `from_version: 1.17.0` won't trigger on v1.18.0+ projects. No `--force` flag exists today.
   - What's unclear: whether the planner ships a new migration 0021 (`from_version: 1.19.0`), or extends 0019's idempotency check, or documents manual recovery.
   - Recommendation: ship migration 0021 (additive, copies only `queue-monitor.{ts,go}`, idempotency = `queue-monitor.ts` presence). Pair with docs amendment for the case-(a) (pre-v1.18.0 projects). See Pitfall 2 option (d). **This is the single most important planner-level decision in Phase 25.**

2. **OQ-2 (from CONTEXT): supabase-edge `queue-monitor.ts` parity — ship or skip?**
   - What we know: Supabase Edge has no Cloudflare Queue equivalent. CONTEXT default: ship for parity ("symmetry beats deletion").
   - What's unclear: whether shipping introduces a non-functional file that will be deleted in a future hygiene phase.
   - Recommendation: ship. Symmetry is cheap, and a non-Worker stack adopting Cloudflare Queues via the Workers ServiceBindings + Queue.send proxy pattern is plausible. The supabase-edge variant follows the `_setWithMonitorForTest` Deno seam pattern (matches existing `cron-monitor.ts`).

3. **OQ-3 (from CONTEXT): multi-queue explicit-slug enforcement shape — compile-time / runtime warn / silent?**
   - What we know: Phase 22 D11 (multi-cron) chose silent + docs. CONTEXT default: silent for symmetry.
   - What's unclear: whether the planner has a strong reason to deviate (e.g., runtime warn aids debugging in production).
   - Recommendation: silent + docs (mirror Phase 22 D11). Add a doc-comment in `queue-monitor.ts` noting that handlers dispatching on `batch.queue` MUST set `monitorSlug` explicitly.

4. **OQ-4 (from CONTEXT): ADR numbering — next available number.**
   - What we know: latest existing ADR is `0030-openrouter-integration-sdk-first.md` ([VERIFIED:] `ls docs/decisions/`).
   - Recommendation: ADR-0031 (D-01), ADR-0032 (D-05), ADR-0033 (D-07). Match the format established by ADR-0029 + ADR-0030: H1 title, **Status** / **Date** / **Phase** header line, ## Context / ## Decision / ## Alternatives Rejected / ## Consequences sections.

5. **OQ-5 (from CONTEXT): does 0019 engine support `--force`?**
   - What we know: ([VERIFIED:] grep) NO `--force` flag exists in `migrate-0019-…sh`. The only flags are `--templates-dir`, `--allow-partial`, `--dry-run`, `--project-dir`, `--pause-between-passes` (test-only).
   - What's unclear: whether the planner should add `--force` (likely meaning "ignore `cron-monitor.ts` presence and re-copy") OR document manual recovery.
   - Recommendation: do NOT add `--force` in Phase 25. The semantics are confusing (force overwrite vs force re-classify?) and the existing idempotency contract (delete files + downgrade SKILL.md + re-run) is honest. Document the recovery path in the new "Recovery" section of `0019-…md` (per CONTEXT D-02). Adding `--force` belongs in a future engine-hardening phase if a real need surfaces.

6. **(NEW): does the openrouter-monitor bundled subtree get the D-03/D-05 fix this phase?**
   - What we know: CONTEXT D-09 says "openrouter-monitor NOT touched this phase".
   - What's unclear: whether NOT touching is intentional (Phase 24 surface is frozen) or oversight (the bundled subtree is a snapshot of `ts-cloudflare-worker`, which DOES get fixed).
   - Recommendation: include in scope. Same diff applied symmetrically. The "Phase 24 surface frozen" stance protects against API change, not internal fixes. Without this, openrouter-monitor scaffolded projects still ship the bug.

7. **(NEW): how does Phase 25 verify SC5 (callbot acceptance) without running against the real callbot repo?**
   - What we know: SC5 says "callbot (or the equivalent fixture) can re-run 0019 cleanly via the engine and replace local workarounds with upstream wrappers".
   - What's unclear: whether VERIFICATION runs `tsc --noEmit` against a synthetic strict-Env fixture in this repo, OR against the real callbot working tree.
   - Recommendation: synthetic fixture in `migrations/test-fixtures/0019/10-strict-env-typecheck/` proving compile-time satisfaction of the four acceptance items in issue #56's "Acceptance check" section. The real callbot adoption is a separate downstream PR (Phase 26+ scope).

## Sources

### Primary (HIGH confidence)

- **`@sentry/core@8.55.2` installed types** — `add-observability/templates/openrouter-monitor/node_modules/@sentry/core/build/types/types-hoist/checkin.d.ts` — `MonitorSchedule`, `MonitorConfig`, `withMonitor` signatures all VERIFIED directly from installed SDK.
- **`@cloudflare/workers-types` installed types** — same `node_modules` path — `MessageBatch<Body>`, `Message<Body>`, queue handler signature VERIFIED.
- **0019 migration spec** — `migrations/0019-sentry-crons-and-healthz.md` (read end-to-end).
- **0019 engine** — `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` (read end-to-end; line numbers cited are accurate).
- **`add-observability/templates/{worker,pages,supabase-edge}/cron-monitor.ts`** — current template state (read end-to-end).
- **`add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts`** — test pattern to mirror (read end-to-end).
- **Issue #56** — primary requirements source (fetched via `gh issue view 56`).
- **Phase 22 + 23 CONTEXT.md + PLAN.md** — established D6/D11/D12 + Guarded Shape A semantics.
- **ADR-0028, ADR-0029, ADR-0030** — read for format + precedent.
- **`migrations/README.md`** — runner contract source (read §"Frontmatter fields" + §"Picking versions").
- **`add-observability/templates/{worker,pages,supabase-edge}/meta.yaml`** — canonical `target.wrapper_path` field; resolves the issue #56 Finding 1 mystery (canonical is `index.ts`, not `lib-observability.ts`).

### Secondary (MEDIUM confidence)

- npm registry version queries (`npm view @sentry/cloudflare`, `@sentry/core`, `@cloudflare/workers-types`, `vitest`) — registry-current values 2026-05-31.
- Existing fixture pattern (`migrations/test-fixtures/0019/01-fresh-apply/{setup,verify}.sh` + `common-setup.sh`) — read fully; new fixtures will mirror.

### Tertiary (LOW confidence — flagged for validation)

- **OQ-5 verification (`--force` flag).** Grep returned no results; conclusion is "doesn't exist". A future engine refactor adding the flag would surprise a planner relying on this.
- **A2 — Sentry SDK 10.x `MonitorSchedule` shape unchanged from 8.x.** Verified only against 8.55.2. Phase 24 consumer pin (`^10.2.0`) means at least one downstream is on 10.x — but Phase 25 templates pin `^8.0.0`. If the type drifted, consumer-side `tsc` may flag it.

## Metadata

**Confidence breakdown:**
- Sentry SDK type shapes (D-03): HIGH — VERIFIED in installed SDK at known path.
- Cloudflare types (D-07): HIGH — VERIFIED in installed `@cloudflare/workers-types`.
- Engine fix sites (D-01): HIGH — line numbers + diff shape derived from end-to-end engine read.
- Migration runner contract (Pitfall 2 / OQ-1): HIGH — README.md §60-99 explicit.
- ADR numbering (OQ-4): HIGH — directory listing direct.
- Multi-queue enforcement (OQ-3): MEDIUM — recommendation by analogy to Phase 22 D11; no new ground-truth.
- Migration filename convention (OQ-1 filename half): MEDIUM — no documented `0019.1` precedent in `migrations/*.md` or README; recommendation by absence.
- openrouter-monitor leakage scope (OQ-6): MEDIUM — CONTEXT says "NOT touched"; my recommendation reverses based on byte-symmetry argument. Planner should escalate if uncertain.

**Research date:** 2026-05-31
**Valid until:** 2026-06-30 (Sentry SDK 8.x maintenance ongoing; 10.x carve-out per Phase 24 still applies; Cloudflare Workers Queue API stable in `@cloudflare/workers-types ^4.x` for 12+ months)
