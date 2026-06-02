# Phase 27: 1.21.0 stable baseline (SPLIT-00 gate) - Research

**Researched:** 2026-06-02
**Status:** ⚠️ RESEARCH BLOCKED — two locked decisions contradict repo reality + the `versioning-tracks-migrations` rule. User decision required before planning (see §Blockers).
**Method:** Inline (gsd-phase-researcher subagent unavailable — API 529 overload ×2). Findings verified directly against the codebase.

---

## Summary of confirmations (WR items — all GREEN to plan)

### WR-01 — go-test counter double-count ✅ confirmed
- Bug is at `add-observability/templates/run-template-tests.sh:633-634`:
  `PASSED=$(echo "$OUTPUT" | grep -c '^--- PASS' || echo "0")` (+ FAILED twin).
  `grep -c` prints `0` AND exits 1 on no match → `|| echo "0"` appends a second
  `0` → captured value is `"0\n0"`. Fix: drop `|| echo "0"` (or `|| true`).
- **FIREWALL (do NOT touch):** lines 128, 130, 558, 559 use
  `grep -oE … | grep -oE '^[0-9]+' || echo "0"` — `grep -oE` prints nothing on
  no match, so `|| echo "0"` is the CORRECT fallback. A fix that changes these is wrong.
- **How to validate:** the harness has no self-test for its own counters; validate
  by (a) grep asserting lines 633-634 no longer contain `|| echo "0"`, and
  (b) running a go stack through the harness and confirming the count renders as a
  single integer (no `0\n0`).

### WR-02 — supabase-edge D-02a test state leak ✅ confirmed
- `ts-supabase-edge/index.test.ts:209-243` restores `console.log` in `finally`
  (231-233) but never calls `_resetForTest()` → leaves `initialized=true` +
  env-a singletons, leaking into later tests in the file. Docstring (line 206)
  documents the intended `_resetForTest() // cleanup` that the code omits.
- Helper: `export function _resetForTest(env?: InitEnv): void` at `index.ts:145`
  — zero-arg call resets `_testEnv=null; initialized=false; registry=null`.
- Fix: add `_resetForTest();` inside the `finally` (after restoring console.log).
  Runner: Deno (`Deno.test`).

### WR-03 — buildSentryOptions unit tests × 3 ✅ confirmed (with a correction — see Blocker C)
- Helper signature (all 3 stacks): `buildSentryOptions(env: InitEnv): SentryOptions`.
- **Actual returned shape** (openrouter, resolved):
  ```ts
  { dsn: env.SENTRY_DSN,
    environment: env.DEPLOY_ENV ?? "dev",
    release: env.SERVICE_NAME ?? SERVICE_DEFAULT,   // SERVICE_DEFAULT = "openrouter-monitor"
    tracesSampleRate: TRACE_SAMPLE_RATE,            // const = 0.1  (NOT env-derived!)
    sendDefaultPii: false }
  ```
- cf-worker / cf-pages are **token templates**: `dsn: env.{{ENV_VAR_DSN}}`,
  `environment: env.{{ENV_VAR_ENV}} ?? "dev"`, `release: env.{{ENV_VAR_SERVICE}} ?? SERVICE_DEFAULT`
  (`SERVICE_DEFAULT = "{{SERVICE_NAME}}"`), `tracesSampleRate: {{TRACE_SAMPLE_RATE}}`.
  These are only testable AFTER the harness materializes them (token substitution
  into a temp dir). So **only openrouter is directly testable as-is**; cf-worker/
  cf-pages tests run through the materialization harness.
- **openrouter MED-4 decoupling holds:** existing `index.test.ts` D-02a block must
  stay free of `buildSentryOptions`; the new WR-03 tests are a separate block.

### WR-04 — openrouter entry uses the helper ✅ confirmed
- Current `openrouter-monitor/src/index.ts:47-57` inlines the options object
  (`tracesSampleRate: 0.1` hardcoded). Target:
  `export default withSentry(env => buildSentryOptions(env), { scheduled: withObservabilityScheduled(withCronMonitor(checkCredit, {…})) })`.
- Wrapper signatures:
  - `withObservabilityScheduled<Env extends Record<string, unknown>>(…)` (`src/observability/middleware.ts:78`)
  - `withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(…)` (`src/observability/cron-monitor.ts:128`)
  - import `buildSentryOptions` from `./observability` (already exported, `index.ts:154`).
- **Byte-symmetry:** the contract pair is `ts-cloudflare-worker/lib-observability.ts ↔ openrouter-monitor/src/observability/index.ts` (the observability MODULE). WR-04 edits `src/index.ts` (ENTRY), NOT the module → symmetry unaffected. Re-run `diff -q` anyway to prove it.

### Versioning facts ✅ confirmed (feeds Blocker B)
- Version source of truth = `skill/SKILL.md` `version: 1.20.0` (line 3). **No `VERSION` file exists** in repo root or `add-observability/`.
- Highest migration = `migrations/0021-with-cron-and-queue-updates.md`, `to_version: 1.20.0`.
- Drift test `test_skill_md_version_matches_latest_migration_to_version` (`migrations/run-tests.sh:2210`): asserts `SKILL.md version == highest-numbered migration's to_version`. Currently 1.20.0 == 1.20.0 ✅.
- Root `CHANGELOG.md:7`: `## [Unreleased] — Phase 26 engine + harness + fixture hardening` — Phase 26's parked entry (D-10a precedent), explicitly NOT bumped to 1.20.1.

---

## ⚠️ Blockers (require user decision before planning)

### Blocker A — "1.21.0" cannot be the SKILL.md version without a migration
The drift test hard-couples `skill/SKILL.md version` to the **highest migration's
`to_version`** (currently 1.20.0). D-07a says **no new migration**. Therefore
bumping `SKILL.md` to 1.21.0 would FAIL the drift test — identical to why Phase 26
parked at 1.20.0 (`[Unreleased]`) instead of 1.20.1.

This collides with **SPLIT-00**, which requires "claude-workflow 1.21.0 shipped +
tagged" AND downstreams pinning `.claude/skills/agentic-apps-workflow/SKILL.md
version: 1.21.0`. With no migration, the skill version stays 1.20.0 — downstreams
literally cannot pin to a 1.21.0 SKILL.md.

**Options:**
- **A1 — Ship migration 0022 (`to_version: 1.21.0`).** Legitimizes SKILL.md 1.21.0
  + downstream pinning. Cost: a migration with no real consumer-applied payload
  (template fixes don't migrate consumers; WR-03/04 are template-internal). Goes
  against the spirit of `versioning-tracks-migrations`. Could be justified IF the
  boundary ADR / a CLAUDE.md note is framed as a real consumer-facing change.
- **A2 — No SKILL.md bump; "1.21.0" = git tag + CHANGELOG only (Phase-26 precedent).**
  SKILL.md stays 1.20.0, Phase 27 changes append to `[Unreleased]`, ship a git tag
  `v1.21.0`. Strictly honors the rule. Cost: SPLIT-00's "SKILL.md version 1.21.0"
  gate condition must be rewritten to "git tag v1.21.0 / commit pin," and
  downstreams pin by tag, not skill version.
- **A3 — Revise the rule:** decouple skill version from migration to_version for
  release-only bumps (modify the drift test to allow SKILL.md ahead of latest
  migration). Biggest blast radius; changes the drift test + the rule itself.

**Recommendation: A2** (honors your `versioning-tracks-migrations` rule + Phase-26
precedent; cheapest; no fake migration). It requires editing SPLIT-00's downstream
pinning gate to "tag-based," which is a doc fix, not a code risk. A1 is defensible
only if you want downstreams to pin by skill version and accept a marker migration.

### Blocker B — `bin/gsd-tools.cjs` is NOT in this repo (D-06 target doesn't exist)
D-06 says "audit `bin/gsd-tools.cjs`." That file does **not exist in
claude-workflow**. The repo's `bin/` holds only shell scripts
(`agenticapps-architecture-cron.sh`, `check-hooks.sh`, install scripts). The
`gsd-tools.cjs` I (and SPLIT-01) referenced is the **GSD framework** tool at
`~/.claude/get-shit-done/bin/gsd-tools.cjs` — a separate system, installed
independently, NOT claude-workflow's code. Its commands (`phase-plan-index`,
`state begin-phase`, `init phase-op`, …) are GSD-framework, not this repo.

**Consequence:** SPLIT-01's premise ("split `bin/gsd-tools.cjs` into shared vs
workflow") is factually wrong. The repo's actual shared-able migration infra is
**`migrations/run-tests.sh`** (~2500 lines: dispatcher + drift test +
fixture-runner harness + all fixtures inline) plus the migration content files.

**Options:**
- **B1 — Retarget D-06 to `migrations/run-tests.sh`:** annotate SHARED (drift test,
  fixture-runner harness, dispatcher, pass/fail helpers) vs WORKFLOW
  (migration-specific apply/verify logic), and write the boundary ADR against the
  *real* artifact. Also add a note to SPLIT-01 correcting the gsd-tools.cjs error.
- **B2 — Drop split-prep from Phase 27 entirely:** defer the boundary audit to
  SPLIT-01 itself (where the real files are in front of you). Keeps 1.21.0 minimal.
- **B3 — Keep D-06 but audit the GSD-framework gsd-tools.cjs anyway** (out-of-repo).
  Not recommended — it's not claude-workflow's code to split.

**Recommendation: B1** (the intent of D-06 — pre-decide the SPLIT-01 boundary so
extraction is mechanical — is still valuable; just point it at the file that
actually exists and is actually shared). B2 is the lean alternative if you'd rather
keep 1.21.0 tiny and do all split-prep in SPLIT-01.

### Blocker C — WR-03 assertion set correction (factual, low-stakes)
CONTEXT D-03a assertion #2 ("`TRACE_SAMPLE_RATE` override is parsed and applied")
is **wrong**: `TRACE_SAMPLE_RATE` is a scaffold-time module **constant**
(`const TRACE_SAMPLE_RATE = 0.1` / `{{TRACE_SAMPLE_RATE}}`), not a runtime env var.
The helper has no env-override behavior. Corrected assertion set:
1. `tracesSampleRate === TRACE_SAMPLE_RATE` (baked constant; 0.1 for openrouter)
2. `environment === env.DEPLOY_ENV ?? "dev"` (test set + unset)
3. `release === env.SERVICE_NAME ?? SERVICE_DEFAULT` (test set + unset)
4. `sendDefaultPii === false`
5. `dsn === env.SENTRY_DSN`
This is a correction I can apply to CONTEXT directly (no decision change) — noting
it here for the audit trail.

---

## Test / build command reference (for plan acceptance criteria)
- Template harness (all stacks): `bash add-observability/templates/run-template-tests.sh all`
- Migration suite + drift test: `bash migrations/run-tests.sh`
- Drift test only: `bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version`
- Per-stack vitest / supabase-edge Deno tests are invoked through the harness
  (it materializes token templates into temp dirs before running).
- Byte-symmetry: `diff -q add-observability/templates/ts-cloudflare-worker/lib-observability.ts add-observability/templates/openrouter-monitor/src/observability/index.ts`

## ADR numbering
- Highest ADR = `docs/decisions/0034-observability-init-singleton-invariant.md`.
  Next free = **0035** for the boundary ADR (D-06a), pending Blocker B resolution.

---

## Validation Architecture

(Nyquist) Each deliverable → an observable signal:

| Item | Validation signal | Command/Check |
|---|---|---|
| WR-01 | lines 633-634 free of `\|\| echo "0"`; firewall lines unchanged | `grep -n '\|\| echo "0"' run-template-tests.sh` → only 128/130/558/559 |
| WR-02 | D-02a test calls `_resetForTest()` in finally; supabase-edge suite GREEN | grep + harness run |
| WR-03 | RED commit then GREEN; buildSentryOptions tests present × 3; assertions per Blocker-C set | test exit 0; grep for `buildSentryOptions` in 3 test files |
| WR-04 | `src/index.ts` contains `buildSentryOptions(env)`; no hardcoded `tracesSampleRate: 0.1`; diff -q empty | grep + diff -q |
| PROJECT.md | file exists with required sections | `test -f .planning/PROJECT.md` |
| Boundary ADR | ADR 0035 exists; SHARED/WORKFLOW annotations present in target (per Blocker B) | `test -f`; grep `// SHARED`/`// WORKFLOW` |
| Version | per Blocker A resolution (A2: tag + CHANGELOG, SKILL.md unchanged; drift test GREEN) | `bash migrations/run-tests.sh` drift test PASS |
| STATE/ROADMAP | Phase 26 marked merged; stale "Next action" line fixed | grep |

---

## RESEARCH BLOCKED
Planning cannot proceed faithfully until Blocker A (versioning approach) and
Blocker B (split-prep target) are resolved by the user. Blocker C is a factual
correction I will apply to CONTEXT.md regardless.
