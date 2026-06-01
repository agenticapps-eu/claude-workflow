# Phase 25: Fix 0019 engine + withCronMonitor — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-31
**Phase:** 25-fix-0019-engine-and-cron-wrappers
**Areas discussed:** Anchor policy, Schedule type, Generic shift, Queue wrapper scope, Migration scope, Queue deploy, Multi-queue policy
**Source issue:** [#56](https://github.com/agenticapps-eu/claude-workflow/issues/56)

---

## Bootstrap decisions (pre-discussion)

Before the formal discussion, the user made two scoping choices via AskUserQuestion:

### Roadmap gap (workflow precondition)

| Option | Description | Selected |
|--------|-------------|----------|
| Skip — straight to /gsd-discuss-phase 25 | Create the phase directory directly; defer ROADMAP.md bootstrap as a later phase | ✓ |
| Stub minimal ROADMAP.md first, then /gsd-add-phase 25 | Honours the GSD invariant but adds ~5 min retro work |  |
| Full retroactive bootstrap as Phase 25 instead | Reverse priorities — do handoff item #2 as Phase 25 |  |

**User's choice:** Skip — straight to discuss
**Notes:** The discuss-phase workflow hard-exited on missing ROADMAP. Compromise: a one-row Phase 25 stub ROADMAP.md was written to unblock the tool, with explicit framing that this is not the full retroactive bootstrap. The skip-choice was honoured in spirit.

### Phase scope

| Option | Description | Selected |
|--------|-------------|----------|
| One phase, all four findings | Bundle as #56 was filed | ✓ |
| Split: Phase 25 = engine + types; Phase 26 = wrappers | Two-phase split |  |
| Split: Phase 25 = Finding 1 only; Phase 26 = rest | Hotfix-shaped split |  |

**User's choice:** One phase, all four findings (Recommended)
**Notes:** Confirms #56's bundling. Single CONTEXT.md / PLAN.md / SUMMARY.md cycle.

---

## Anchor policy (D-1)

| Option | Description | Selected |
|--------|-------------|----------|
| Alias — silently accept index.ts | Extend find at :224 + classify at :317-331; both anchor shapes first-class | ✓ |
| REFUSE with actionable rename hint | Discover index.ts candidates, refuse with exit 2 + rename hint |  |
| Hybrid — alias by default + warn on legacy | Accept + stderr warning |  |

**User's choice:** Alias — silently accept index.ts (Recommended)
**Notes:** The middleware.ts co-anchor requirement guards against unintended index.ts matches in unrelated dirs. Most permissive for legacy 0017-shaped projects; lowest friction for callbot and similar migrations.

---

## Schedule type (D-2)

| Option | Description | Selected |
|--------|-------------|----------|
| Discriminated union, type alias | `type CronMonitorSchedule = { type: 'crontab'; value: string } \| { type: 'interval'; value: number; unit: ... }` | ✓ |
| Keep interface, add `unit` as optional | Less invasive but half-fix; still doesn't satisfy Sentry's MonitorSchedule |  |
| Re-export Sentry's MonitorSchedule directly | Tightest coupling; SDK version drift risk |  |

**User's choice:** Discriminated union, type alias (Recommended)
**Notes:** Matches Sentry's MonitorSchedule discriminated union. Drops the consumer-side LOCAL-PATCH cast in callbot's cron-monitor.ts:141-149. Functionally non-breaking — population of consumers using interval against current (broken) shape is empty.

---

## Generic shift (D-3)

| Option | Description | Selected |
|--------|-------------|----------|
| Ship in Phase 25, minor bump | Narrow `<E extends Record<string, unknown>>` → `<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>`; one cast inside wrapper for env[envKey] | ✓ |
| Ship in Phase 25, MAJOR bump (add-observability 1.0.0) | Conservative semver but 1.0 signal not yet earned |  |
| Defer to Phase 26 | Phase 25 = engine + types only; generic narrowing rides Phase 26 |  |

**User's choice:** Ship in Phase 25, minor bump (Recommended)
**Notes:** Strictly looser-to-consumers in practice — every E that satisfied the old constraint satisfies the new. Bundling with the rest of the phase keeps callbot's cleanup as a single upgrade cycle.

---

## Queue wrapper scope (D-4)

| Option | Description | Selected |
|--------|-------------|----------|
| Ship in Phase 25 | New `queue-monitor.ts` across three TS stacks; mirror Guarded Shape A + D6 slug + D12 monitorConfig | ✓ |
| Split into Phase 25.5 | Phase 25 = engine + types + generic; Phase 25.5 = withQueueMonitor |  |

**User's choice:** Ship in Phase 25 (Recommended)
**Notes:** Same Guarded Shape A pattern; symmetric to withCronMonitor; one upgrade cycle for callbot to drop all 3 workarounds.

---

## Migration scope (D-5)

| Option | Description | Selected |
|--------|-------------|----------|
| Engine fix alone, update 0019.md docs | 0019 is additive + idempotent; affected projects re-run cleanly post-fix | ✓ |
| Ship migration 0021 — explicit re-run pointer | One-line operator hint as a no-op migration |  |

**User's choice:** Engine fix alone, update 0019.md docs (Recommended)
**Notes:** Confirms 0019's idempotency contract. Recovery path: re-run with `--force` (or whatever the existing engine supports — OQ-5).

---

## Queue deploy (D-6)

| Option | Description | Selected |
|--------|-------------|----------|
| Update 0019 to also copy queue-monitor.{ts,go} | Re-rev 0019; idempotency marker stays cron-monitor.ts | ✓ |
| Template-only — queue-monitor ships in templates dir but NOT copied by 0019 | Existing projects don't get queue-monitor via migration |  |
| Ship as migration 0021 — dedicated queue-monitor migration | Per-migration scope cleanliness vs additional migration count |  |

**User's choice:** Update 0019 to also copy queue-monitor.{ts,go} (Recommended)
**Notes:** Symmetric with how cron-monitor + healthz-snippet were added in 0019 originally. Migration filename re-rev vs 0019.1 naming punted to planner (OQ-1).

---

## Multi-queue policy (D-7)

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror D11: multi-queue requires explicit monitorSlug | Same reason as Phase 22 D11 — auto-derived per-queue slugs may not be provisioned in Sentry | ✓ |
| Always auto-derive per-queue (no D11 analog) | Simpler but may surprise operators |  |

**User's choice:** Mirror D11 (Recommended)
**Notes:** Symmetric with cron-monitor's D11 contract. Enforcement shape (compile-time vs runtime vs silent) punted to planner (OQ-3).

---

## Claude's Discretion

The following areas were marked for planner-level decision and noted in CONTEXT.md `<open_questions>`:

- Migration filename — keep at 0019 with re-rev annotation vs bump to 0019.1 (OQ-1)
- queue-monitor.ts inclusion in ts-supabase-edge for cross-stack consistency (OQ-2)
- Multi-queue explicit-slug enforcement shape — compile-time/runtime/silent (OQ-3)
- ADR numbering — confirm next available number (OQ-4)
- 0019 engine `--force` flag — verify existing engine supports idempotent re-run (OQ-5)

## Deferred Ideas

Captured in CONTEXT.md `<deferred>`:
- Phase 26 carry-forward: DEF-1, DEF-2, DEF-3, F-2 lockfile policy, `.gitignore` extension to 3 templates
- Future: full retroactive ROADMAP/STATE/PROJECT bootstrap; FIX-0017-ENGINE.md migration 0017 fixes; withQueueMonitor for Go; GH Actions CI; consumer adoption PRs (fxsa, callbot)
