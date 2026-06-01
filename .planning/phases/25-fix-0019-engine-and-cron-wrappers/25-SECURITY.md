---
phase: 25
slug: fix-0019-engine-and-cron-wrappers
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-01
---

# Phase 25 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail for the Fix-0019 engine + cron/queue wrapper revision (v1.20.0).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Engine (0019/0021) → project filesystem | Engine writes wrapper files (`cron-monitor.ts`, `queue-monitor.ts`, `lib-observability.ts`/`index.ts`, healthz handler) into wrapper roots discovered via `find`. D-01 widens discovery to `-name index.ts`. | Template TS source files (no secrets) |
| Engine apply_root (0021) → wrapper directory | New engine surface; reuses 0019's pre-classify filter + canonicalize_awk + all-clean gate. | Template TS source files (no secrets) |
| `find` traversal → ROOTS array | Engine recursively scans `.`; widened candidates expand attack surface for write-to-attacker-controlled-dir. | Filesystem paths |
| `classify_stack` → `apply_root` | Misclassification could direct file writes to unintended dirs. | Path + stack label |
| `emit_refuse_artifacts_for` → `.observability-0019.patch` | Refuse-path emits diff into project tree; must match actual project filenames. | TS source bytes (operator-side; nothing transmitted off-host) |
| `CronMonitorConfig.monitorSlug` → Sentry monitor namespace | Slug becomes Sentry server-side monitor identifier. | Slug string |
| Cloudflare runtime → handler (`batch.queue`) | Platform-provided string flows into auto-derived queue-monitor slug. | Slug string |
| Operator-set env vars → `resolveQueueSlug` / `buildMonitorConfig` | `SENTRY_DSN`, `SENTRY_CRON_MONITOR_SLUG_QUEUE`, etc., read at runtime. | Deployment-time secrets |
| `Env` interface → `withCronMonitor` generic constraint | Narrowing the generic affects which consumer Env shapes satisfy the constraint (cf-worker + openrouter post-revision). | Type-level only |
| 0021 baseline-fixture files → 0021 engine canonical-hash comparison | Frozen v1.19.0 baseline files are the source-of-truth that the 0021 engine compares project state against. | Byte-stable fixture snapshots |
| `./cron-monitor` named exports → `queue-monitor.ts` consumer | `CronMonitorConfig`, `buildMonitorConfig`, `isConfigured` re-exported via single import line. | Type + value bindings (no secrets) |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-25-01 | T (Tampering) | Engine wrapper-root discovery (D-01 widens `find` to `-name index.ts`); attacker-shaped project layout could trigger write to chosen dir | mitigate | Pre-classify filter `_filter_index_ts_requires_co_anchor` requires sibling `middleware.ts` or `_middleware.ts` and rejects `*/dist/*`, `*/build/*`, `*/out/*`. Existing `./node_modules`/`./.git` prunes retained. Fixtures `11-stray-index-ts-no-co-anchor` + `12-dist-shaped-anchor-pair` lock the negative cases. Evidence: `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:196-232` (filter fn), `:252-270` (find pass + prunes pipes to filter). | closed |
| T-25-02 | I/T (Slug injection) | `resolveQueueSlug` auto-derive on cf-worker + cf-pages from `batch.queue` | accept | Trust Cloudflare platform-provided `batch.queue` string. Sentry server-side validates slug format; no FS write occurs based on slug. Verified by `queue-monitor.test.ts` auto-derive assertion. Severity LOW. | closed |
| T-25-03 | D (Denial-of-monitoring) | Guarded Shape A unmonitored fallback (pre-callback Sentry transport throw → handler runs unmonitored) | accept | Explicit ADR-0029 trade-off: "queue/cron always runs" beats "monitoring always recorded". Codex M-6 sync-throw test ensures post-callback synchronous throws propagate (not fall-through to fallback). Severity LOW. | closed |
| T-25-04 | T (Tampering) | Engine accepts `index.ts` from `dist/` build output → could overwrite compiled JS | mitigate | Sibling co-anchor filter + codex M-2 dist-path filter (rejects `*/dist/*`, `*/build/*`, `*/out/*` before sibling check). Fixture 12 (`12-dist-shaped-anchor-pair`) is regression test. 0021 engine inherits filters via shared `_filter_index_ts_requires_co_anchor`. Evidence: `migrate-0019-sentry-crons-and-healthz.sh:208-232` (`_filter_index_ts_requires_co_anchor` with dist-path drop at :214-216). | closed |
| T-25-05 | T (Tampering) | `resolve_anchor_files` picks wrong anchor when both `index.ts` AND `lib-observability.ts` present in same dir | accept | Operator-shaped condition — having both files is itself a code-quality smell. Engine prefers `index.ts` (canonical per `meta.yaml`); existing fixtures with only `lib-observability.ts` continue to work. No write-path expansion. Evidence: `migrate-0019-sentry-crons-and-healthz.sh:409-436` (`resolve_anchor_files` prefers `index.ts`). Severity LOW. | closed |
| T-25-06 | T (Tampering) | Generic narrowing locks consumer `Env` shape (cf-worker + openrouter only post-revision) | accept | Per CONTEXT D-06 — implausible operator overrides SENTRY_DSN field type. No code path bypassable. Severity LOW. | closed |
| T-25-07 | I (Info Disclosure) | `(env as unknown as Record<string, unknown>)[envKey]` cast bypasses TS strictness | accept | Cast is internal to wrapper; no env-key reaches attacker-controlled sink. Sentry slug sanitised server-side. Severity LOW. | closed |
| T-25-08 | I (Info Disclosure) | Operator-controlled `SENTRY_CRON_MONITOR_SLUG_QUEUE` could route metrics to wrong Sentry monitor | accept | Env vars are deployment-time secrets; operator with env-set access controls deployment regardless. Each Sentry DSN scopes to one project — no cross-tenant attack. Severity LOW. | closed |
| T-25-09 | I (Info Disclosure) | D-19 named exports (`buildMonitorConfig`, `isConfigured`) + Issue #56 linkback comments could leak internal architectural detail | accept | Helpers operate over `{ SENTRY_DSN?: string }` / `CronMonitorConfig` only — no secret material flows. Re-export internal to add-observability templates (no public package boundary). Linkback content is ADR citations + public CHANGELOG. Severity LOW. | closed |
| T-25-10 (a) | T (Tampering) | Fixture drift if v1.19.0 baseline changes silently | mitigate | 0021 fixtures pin baseline content explicitly under `migrations/test-fixtures/0021/baselines/v1.19.0/<stack>/cron-monitor.ts` as byte-stable snapshots; never edited in-place. Evidence: files exist at `migrations/test-fixtures/0021/baselines/v1.19.0/{ts-cloudflare-worker,ts-cloudflare-pages,ts-supabase-edge}/cron-monitor.ts` and are referenced from `migrations/test-fixtures/0021/common-setup.sh:9,29,38,47`. | closed |
| T-25-10 (b) | T (Tampering) | `emit_refuse_artifacts_for` would emit diff against legacy `lib-observability.ts` while project anchor is `index.ts` (operator-visible mismatch) | mitigate | `emit_refuse_artifacts_for` invokes `resolve_anchor_files()` to resolve the actual project-side anchor before emitting the patch. Evidence: `migrate-0019-sentry-crons-and-healthz.sh:660-678` (`emit_refuse_artifacts_for` calls `resolve_anchor_files` at :672) and `:760-764` (refuse path uses resolved anchor). | closed |
| T-25-10 (c) | T (Tampering) | Migration 0021 canonicaliser must mirror 0019's exactly (per `migrations/0019-sentry-crons-and-healthz.md:260`) | accept | 0021 engine ships a VERBATIM MIRROR of 0019's `canonicalize_awk` with explicit "do not fork" header comment. Evidence: `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh:10-15` (file header constraint) and `:307-313` (`# ⚠️ VERBATIM MIRROR of migrate-0019 ⚠️` block header). Severity LOW (internal-consistency safeguard, not exploitable). | closed |
| T-25-11 | I (Info Disclosure) | Migration 0021's `.observability-0021.patch` emitted in refuse path could leak project-side code via diff | accept | Same risk profile as 0019's `.observability-0019.patch`. Written to project root by operator's own engine invocation; nothing transmitted off-host. Operator's choice whether to commit/share. Severity LOW. | closed |

*Status: all 13 entries closed.*
*Disposition: mitigate (4) · accept (9) · transfer (0)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-25-02 | T-25-02 | Trust Cloudflare platform-provided `batch.queue` string. Sentry server-side validates slug format; no file-system write occurs based on slug. Verified by queue-monitor.test.ts auto-derive assertion. | gsd-security-auditor (per ADR-0033, Plan 01/04 threat_model) | 2026-06-01 |
| AR-25-03 | T-25-03 | Explicit ADR-0029 trade-off — "queue/cron always runs" beats "monitoring always recorded". Codex M-6 sync-throw test ensures post-callback synchronous throws propagate, not fall through to the unmonitored fallback. | gsd-security-auditor (per ADR-0029, Plans 01/03/04 threat_model) | 2026-06-01 |
| AR-25-05 | T-25-05 | Operator-shaped condition — having both `index.ts` and `lib-observability.ts` in the same dir is a code-quality smell. Engine canonically prefers `index.ts` per `meta.yaml`. Existing fixtures with only `lib-observability.ts` continue to work. No write-path expansion. | gsd-security-auditor (per Plan 02 threat_model) | 2026-06-01 |
| AR-25-06 | T-25-06 | Per CONTEXT D-06 — implausible that an operator overrides the `SENTRY_DSN` field type. No code path is bypassable as a result of generic narrowing on cf-worker + openrouter. | gsd-security-auditor (per Plan 03 threat_model) | 2026-06-01 |
| AR-25-07 | T-25-07 | The `(env as unknown as Record<string, unknown>)[envKey]` cast is internal to the wrapper; no env key reaches an attacker-controlled sink. Sentry sanitises the slug server-side. | gsd-security-auditor (per Plan 03 threat_model) | 2026-06-01 |
| AR-25-08 | T-25-08 | Env vars are deployment-time secrets; an operator with env-set access controls the deployment regardless. Each Sentry DSN scopes to one project, so no cross-tenant attack is possible via slug routing. | gsd-security-auditor (per Plan 04 threat_model) | 2026-06-01 |
| AR-25-09 | T-25-09 | The D-19 helpers (`buildMonitorConfig`, `isConfigured`) operate only over `{ SENTRY_DSN?: string }` / `CronMonitorConfig` — no secret material flows through them. Re-export is internal to add-observability templates (no public package boundary). Issue #56 linkback comments cite ADRs + public CHANGELOG only. | gsd-security-auditor (per Plans 03/05 threat_model) | 2026-06-01 |
| AR-25-10c | T-25-10 (c) | 0021 engine SHARES the canonicalize_awk source from 0019 via verbatim copy with an explicit "do not fork" header. Refinement to 0017 → ported to 0019 → ported here is the only sanctioned change path. This is an internal-consistency safeguard, not an exploitable surface. | gsd-security-auditor (per Plan 05 threat_model + migrations/0019-sentry-crons-and-healthz.md:260-263) | 2026-06-01 |
| AR-25-11 | T-25-11 | Same risk profile as 0019's `.observability-0019.patch`. The patch is written to the project root by the operator's own engine invocation; nothing is transmitted off-host. Whether to commit or share the patch is the operator's choice. | gsd-security-auditor (per Plan 05 threat_model) | 2026-06-01 |

*Accepted risks do not resurface in future audit runs.*

---

## Unregistered Threat Flags

None. SUMMARY 25-05 (`## Threat Flags`) explicitly states "None — this plan introduces no new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries." SUMMARY 25-04 (`## Threat Surface Scan`) confirms only the registered T-25-02 / T-25-03 / T-25-08 entries arose, all already accepted in the register. SUMMARIES 25-01 / 25-02 / 25-03 contain no threat-flag section (plans of those waves added only RED fixtures / engine filter / generic narrowing, all explicitly mapped to existing IDs).

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-01 | 13 | 13 | 0 | gsd-security-auditor (State B — no prior SECURITY.md; built from PLAN threat_models + SUMMARY threat-flag scans + implementation grep verification) |

**Verification methods**
- mitigate (T-25-01, T-25-04, T-25-10a, T-25-10b): grep + line-anchored evidence in implementation files (read-only).
- accept (all others): rationale carried verbatim from PLAN `<threat_model>` into Accepted Risks Log above.
- No HIGH-severity threats — ASVS L1 block-on-HIGH gate does not trigger.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-01
