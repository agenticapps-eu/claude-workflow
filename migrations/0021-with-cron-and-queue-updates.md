---
migration_id: "0021"
from_version: 1.19.0
to_version: 1.20.0
type: "re-rev-with-dirty-detection"
idempotency_marker: "queue-monitor.ts presence (cf-worker + cf-pages) AND cron-monitor.ts content-hash matches v1.20.0 baseline (twofold per codex M-8)"
related: ["0019", "0028", "0029", "0031", "0032", "0033"]
---

# Migration 0021 — Re-rev cron-monitor.ts + ship queue-monitor.ts for v1.19.0 projects

> **Status:** Released 2026-05-31 (Phase 25)
> **Architecture:** [ADR-0033](../docs/decisions/0033-with-queue-monitor.md) (the re-rev rationale lives there per CONTEXT D-02b revised)
> **Related:** [Migration 0019](0019-sentry-crons-and-healthz.md) (the original wrapper migration; this migration delivers the Phase 25 cron-monitor.ts D-03/D-05 fixes AND the new queue-monitor.ts to v1.19.0 projects that Migration 0019 cannot reach by virtue of the runner's exact `from_version` matching).

## Goal

Deliver to projects already at v1.19.0 the Phase 25 template changes that Migration 0019 cannot retrigger on per the runner's `from_version` contract:

1. **Updated `cron-monitor.ts`** with the discriminated-union `CronMonitorSchedule` (D-03 — all 3 TS stacks) and narrowed `withCronMonitor<E>` generic (D-05 — cf-worker only; cf-pages signature is `<R>` return-type generic — codex H-3 verified). Also exports `buildMonitorConfig` and `isConfigured` (D-19 — cf-worker + cf-pages only — queue-monitor consumer requirement).
2. **New `queue-monitor.ts`** with Guarded Shape A semantics (D-07/D-08/D-09/D-10 — see [ADR-0033](../docs/decisions/0033-with-queue-monitor.md)). cf-worker + cf-pages ONLY (codex H-6 — Supabase Edge is Deno-runtime; no Cloudflare-Queue equivalent).

This is a **re-rev with dirty detection** (NOT additive-only) — projects with hand-modified `cron-monitor.ts` (e.g., callbot's LOCAL-PATCH at `cron-monitor.ts:141-149`) are REFUSED with `.observability-0021.patch` listing the diff. Per CONTEXT D-02b revised. See [ADR-0033 §"Why a re-rev"](../docs/decisions/0033-with-queue-monitor.md) for the rationale (codex H-7).

## Inputs

- **Sources:**
  - `add-observability/templates/<stack>/cron-monitor.ts` (one of `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`) — updated v1.20.0 baseline.
  - `add-observability/templates/<stack>/queue-monitor.ts` (cf-worker + cf-pages ONLY).
- **Target wrapper directory:** discovered by reusing Migration 0019's classify_stack + `resolve_anchor_files()` + sibling-anchor + dist-path filter logic (post-Phase-25 widening per ADR-0031 + codex M-2).
- **Project state:** SKILL.md at `version: 1.19.0`.

## Apply

Two-phase apply mirroring Migration 0019's all-clean-gate (per CONTEXT D-02b revised):

**Phase 1 — Discovery + canonicalisation:**
1. Discover wrapper roots (same find + filter pipeline as Migration 0019 post-Plan-02).
2. For each root, classify stack via classify_stack().
3. For each root, canonicalise the existing `cron-monitor.ts` using `canonicalize_awk` (verbatim mirror of 0019's canonicaliser — per `migrations/0019-sentry-crons-and-healthz.md:260` anti-pattern: "Mirror, not fork").
4. Compare canonical hash against the v1.20.0 template baseline (pre-computed when the engine is built).

**Phase 2 — Decision gate:**
- If ALL roots have canonical-hash-match to v1.20.0 baseline AND already have `queue-monitor.ts` (cf-worker + cf-pages) — twofold idempotency check (codex M-8 / gemini MEDIUM) — exit 0 (SKIP_ALREADY).
- If ALL roots have canonical-hash-match to v1.19.0 baseline (post-0019 baseline, NOT v1.20.0) — proceed to Phase 3 (apply).
- If ANY root has hand-modified `cron-monitor.ts` (canonical hash matches NEITHER baseline) — REFUSE: emit `.observability-0021.patch` showing the diff between project's `cron-monitor.ts` and the v1.20.0 template; exit non-zero.

**Phase 3 — Apply (only if all-clean gate passed):**
For each discovered wrapper root:
1. Classify stack (cf-worker / cf-pages / supabase-edge / go-fly-http / unknown).
2. If stack is `go-fly-http`, SKIP (out of scope per Phase 25 D-12).
3. If stack is `unknown`, SKIP_UNSUPPORTED.
4. For cf-worker + cf-pages: `cp <template>/cron-monitor.ts <wrapper>/cron-monitor.ts && cp <template>/queue-monitor.ts <wrapper>/queue-monitor.ts`.
5. For ts-supabase-edge: `cp <template>/cron-monitor.ts <wrapper>/cron-monitor.ts` ONLY (codex H-6 — no queue-monitor.ts here).

After all wrappers processed (or no wrappers found — pre-init projects):
6. Bump SKILL.md `version: 1.19.0` → `version: 1.20.0`.

## Verify

- `test -f <wrapper>/queue-monitor.ts` per cf-worker + cf-pages wrapper.
- `! test -e <wrapper>/queue-monitor.ts` for ts-supabase-edge wrappers (negative — codex H-6).
- Canonical hash of `<wrapper>/cron-monitor.ts` matches v1.20.0 template baseline (verified by re-running engine — should exit 0 / SKIP_ALREADY).
- `grep -q '^version: 1.20.0$' .claude/skills/agentic-apps-workflow/SKILL.md`.

## Idempotency

**Twofold idempotency marker (codex M-8 + gemini MEDIUM):** Re-running the engine on an already-migrated wrapper SKIPs that wrapper if BOTH:
1. `queue-monitor.ts` is present in the wrapper root (cf-worker + cf-pages); AND
2. `cron-monitor.ts` canonical hash matches the v1.20.0 baseline.

Either check failing on its own (queue-monitor present but cron-monitor outdated; OR cron-monitor v1.20.0 but queue-monitor missing) does NOT count as idempotent — the engine re-applies that root. This prevents partial-state from a previous failed run.

Implication: an operator who hand-applied `queue-monitor.ts` (e.g., copied from this repo before 1.20.0 shipped) BUT did not update `cron-monitor.ts` will trigger a re-apply on the cron-monitor side (queue-monitor stays unchanged since the canonical hash check is on cron-monitor only).

## Recovery

**Got a `.observability-0021.patch` from a refuse?**

Migration 0021 refused because at least one wrapper's `cron-monitor.ts` was hand-modified (canonical hash matches neither the v1.19.0 nor v1.20.0 template baseline). Two paths:

**Drop the LOCAL-PATCH (recommended for callbot):** The Phase 25 D-03 + D-05 fixes IN THE TEMPLATE eliminate the need for callbot's LOCAL-PATCH cast at `cron-monitor.ts:141-149`. Delete the LOCAL-PATCH lines; run Migration 0021 again; the engine accepts (canonical hash now matches v1.19.0 baseline); the new template ships and includes the D-03 fix natively. (This is the supported callbot upgrade story per CONTEXT specifics.)

**Keep the LOCAL-PATCH and merge:** Apply the `.observability-0021.patch` manually to your hand-modified `cron-monitor.ts`. Re-running Migration 0021 will then succeed.

## Why a re-rev (not additive-only)?

See [ADR-0033](../docs/decisions/0033-with-queue-monitor.md) §"Re-rev rationale (codex H-7)". Short answer: the v1.19.0 callbot project has TWO bugs the Phase 25 cron-monitor.ts template fixes (D-03 schedule type, D-05 generic narrowing). An additive-only Migration 0021 that only ships `queue-monitor.ts` would leave callbot's cron-monitor.ts at the pre-Phase-25 broken state — Findings 2 and 3 of issue #56 would not close for v1.19.0 consumers. The re-rev shape ships BOTH the updated cron-monitor.ts AND the new queue-monitor.ts, which is what closes the findings end-to-end.
