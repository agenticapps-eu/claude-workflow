---
phase: 23-observability-followups
audited: 2026-05-29T17:51:00Z
auditor: /cso (gstack daily mode, 8/10 confidence gate)
status: passed
threats_open: 0
threats_total: 5
scope: phase-23-diff (101a146..d2e7b50, 31 commits)
report: .gstack/security-reports/2026-05-29T175100Z.json
---

# Phase 23: observability-followups — Security Posture Report

## Verdict: PASSED

No findings clear the daily-mode 8/10 confidence gate. Phase 23 introduces no new exploitable surface. Two below-bar observations preserved in the appendix for future hardening.

## Scope

The phase 23 diff (31 commits across 6 internal waves, on `feat/observability-followups-v0.7.0`):
- 16 Sentry-touching template files (cron-monitor + healthz × 4 stacks + ADR-0029)
- 2 migration scripts (`migrations/run-tests.sh` + `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`)
- 1 SKILL.md version bump + CHANGELOG entry

**Repo identity note:** `claude-workflow` is a scaffolder/migration framework — templates run downstream, not here. The threat model is supply-chain-to-downstream, not deployed-service.

## Threats Evaluated

The session-handoff identified 5 specific concerns. All evaluated below:

### T-23-S-01: F5 changes Sentry credential flow through `withIsolationScope` boundaries → REFRAMED

F5 changes **context/scope flow** (tags, breadcrumbs, user-context), NOT **credential flow**. Sentry credentials live on the `Client` instance (DSN), not on `Scope`. The DSN flow path is unchanged: read from `env.SENTRY_DSN` at `isConfigured()`, never logged, never embedded. The credential boundary was not the actual semantic change.

**Verification:** Read `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:115–153` (Guarded Shape A implementation), traced the DSN read path through `isConfigured()`, confirmed it returns boolean only and never propagates the secret value.

### T-23-S-02: `withIsolationScope` semantic change risks downstream consumer breakage → DOCUMENTATION-CLASS

Handler-set tags/breadcrumbs may not propagate to outer error-capture after isolation unwinds. The `add-observability/CHANGELOG.md:24` "HONEST SEMANTIC" entry documents this for downstream consumers. **No credential or auth implication.**

### T-23-S-03: Guarded Shape A fallback executes handler unmonitored on pre-callback transport failure → BY-DESIGN

Cron always runs (R02 contract). The fallback path means a pre-callback Sentry failure produces "no check-in" rather than "no cron". Operator observability gap exists in the fallback path (`cron-monitor.ts:144–148`) — when fallback fires, Sentry sees zero signal that the run happened. This is the deliberate trade-off vs. silently skipping the cron, with ADR-0029 capturing 5 rejected alternative shapes.

### T-23-S-04: F3 `--pause-between-passes` signal-file path validation → SAFE

Explicit allow-list prefix matching: `${TMPDIR:-/tmp}/sigterm-test-*` OR `*/migrations/test-fixtures/0019/*/sigterm-*`. Anything else exits 2 with a clear error. **One minor sub-threshold gap:** path validation matches the literal string, not the canonical-resolved path. A symlink in `${TMPDIR}/sigterm-test-foo` pointing to `/etc/passwd` would pass validation; subsequent `touch` would attempt to update mtime on the target. On root-owned files this fails closed; on user-owned files the realistic exploit value is bounded to "update mtime of a file the user already owns" — sub-threshold.

### T-23-S-05: D-07 `emit_refuse_artifacts` default flip introduces new write paths → STRICTLY-LESS-WRITE

v0.6.0 wrote `.observability-0019.patch` to ALL roots (DIRTY + CLEAN) on refuse. v0.7.0 writes only to DIRTY roots by default; `--allow-partial` (or `ALLOW_PARTIAL=true` env) restores v0.6.0 behavior. **Removes a write surface, does not add one.**

## STRIDE Summary

| Component | Top concerns | Status |
|---|---|---|
| `withCronMonitor` (TS, 3 stacks) | T: `_setWithMonitorForTest` exported in Supabase bundle (A-01) | Below-bar appendix |
| Healthz handlers (TS + Go) | I: topology-leaking default response (A-02) | Below-bar appendix |
| `migrate-0019` engine | T: `.observability-0019.patch` write, R: traceable via `migrate-0019:` log prefix | OK |
| `migrations/run-tests.sh` | D: signal-file path validation (T-23-S-04) | OK |

## Below-Bar Observations (recommended for v0.8.0)

### A-01: `_setWithMonitorForTest` exported in production bundle (Supabase Edge)

* **Pseudo-severity:** LOW · **Confidence on real exploit:** 4/10
* **File:** `add-observability/templates/ts-supabase-edge/cron-monitor.ts:91`
* **Pattern:** Module-level mutable state wrapped by exported `_setWithMonitorForTest(impl)`. No runtime guard. `@internal` JSDoc is non-enforced.
* **Exploit prerequisite:** Downstream developer (or their transitive dep) imports `_`-prefixed `ForTest` from prod code.
* **Recommendation:** Adopt one of WR-03's fixes (add `| null` null-restore branch), or gate the export behind a build-time conditional (`if (import.meta.test)` for Deno).

### A-02: Healthz template ships topology-leaking default response

* **Pseudo-severity:** LOW · **Confidence on real exploit:** 6/10
* **File:** all 3 TS healthz-snippet.ts files
* **Pattern:** Default response enumerates `{ db, upstream, kv }` probes; template header comment documents the SECURITY trade-off but ships the leaky default.
* **Impact:** Reconnaissance signal aiding targeted follow-up.
* **Recommendation (v0.8.0):** Flip default to `{ status: 'ok' | 'degraded' }` only; opt into per-check breakdown via `?detail=true` (gated).

## Protection Posture

* `.gitleaks.toml` / `.secretlintrc`: **absent** — recommended for future commits (phase 23 introduced no secrets, but `cron-monitor.ts` handles DSN flow; future contributors could leak).
* `.gstack/security-reports/` is gitignored as of this session (added to `.gitignore`).
* No prior `/cso` runs — this is the baseline. Future audits will trend against `2026-05-29T175100Z.json`.

## Disclaimer

This is an AI-assisted scan, not a substitute for professional penetration testing. For production systems handling sensitive data, payments, or PII, engage a professional firm. Use `/cso` between professional audits, not as the only line of defense.
