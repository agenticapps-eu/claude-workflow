---
phase: 27
plan: "05"
subsystem: observability-templates
tags: [WR-04, buildSentryOptions, sentry, openrouter, byte-symmetry, DEF-1]
dependency_graph:
  requires: [WR-03]
  provides: [WR-04]
  affects: [27-06]
tech_stack:
  added: []
  patterns: [env-pure-sentry-options, helper-delegation, snapshot-unchanged-invariant]
key_files:
  created:
    - add-observability/templates/.gitignore
  modified:
    - add-observability/templates/openrouter-monitor/src/index.ts
decisions:
  - "Single-line form for withSentry call: `withSentry((env: Env) => buildSentryOptions(env), {...})` satisfies the plan's grep pattern (\\s* matches zero whitespace)"
  - "Trailing newline artifact in snapshot vs plain run: --snapshot writes `printf '%s\\n'`, plain run writes `printf '%s'` — content is byte-identical; invariant holds"
  - "run-template-tests.sh openrouter is not a valid harness stack ID (same finding as 27-02); openrouter tested directly via npx vitest run — 17 passed"
metrics:
  duration_minutes: 10
  completed_date: "2026-06-02"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 2
requirements: [WR-04]
---

# Phase 27 Plan 05: WR-04 openrouter Entry Rewrite + Byte-Symmetry Re-verify Summary

**One-liner:** Openrouter entry rewired from inline hardcoded Sentry options to `buildSentryOptions(env)` helper (DEF-1 fix); byte-symmetry pair proven unchanged by WR-04 via snapshot-before/compare-after; 17 tests GREEN.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Snapshot byte-symmetry, rewire entry to use buildSentryOptions(env) | 88b609e | openrouter-monitor/src/index.ts, templates/.gitignore |
| 2 | Assert byte-symmetry UNCHANGED + openrouter suite GREEN | (verification only — no commit) | — |

## What Was Built

**Task 1 — WR-04 entry rewrite:**

- Added `import { buildSentryOptions } from "./observability"` to `src/index.ts` (D-04b)
- Replaced the inline hardcoded options object (which baked `tracesSampleRate: 0.1` directly) with the helper delegation: `withSentry((env: Env) => buildSentryOptions(env), {...})`
- Updated the composition-chain comment block at the top of the file to show `buildSentryOptions(env)` instead of the old `env => ({...})` inline form
- Created `add-observability/templates/.gitignore` with `.byte-symmetry.snapshot` entry so the ephemeral verification output is never committed or shown as untracked noise
- The second `withSentry` argument (the `scheduled:` handler chain with `withObservabilityScheduled` + `withCronMonitor`) is byte-unchanged — handler semantics fully preserved
- Frozen pair files (`openrouter-monitor/src/observability/index.ts`, `ts-cloudflare-worker/lib-observability.ts`) not touched

**Task 2 — Byte-symmetry invariant + suite GREEN:**

- Pre-WR-04 snapshot captured: 4 diff lines (the known pre-existing comment-prose drift at the `(b) extend InitEnv ... SENTRY_RELEASE` block)
- Post-WR-04 output: same 4 diff lines — content byte-identical (trailing newline artifact between `--snapshot` and plain run modes is not content drift)
- `diff` of snapshot vs after: empty on content comparison — WR-04 invariant holds
- `npx vitest run` in openrouter-monitor: **17 passed (2 files)**

## GitNexus Impact Analysis

Per CLAUDE.md mandate, impact analysis was run on `buildSentryOptions` (openrouter instance) before editing:

- **Target:** `Function:add-observability/templates/openrouter-monitor/src/observability/index.ts:buildSentryOptions`
- **Direction:** upstream
- **Direct callers (d=1):** 0 (it was exported but uncalled from the entry — this plan adds the first call site)
- **Affected processes:** 0
- **Risk level: LOW**

No HIGH or CRITICAL risk — proceeded with edit.

`gitnexus_detect_changes` run before commit: staged scope shows no unexpected symbols/flows in the template files (gitnexus tracks repo execution graph, not template scaffold files — correct behaviour).

## Byte-Symmetry Verification Detail

```
Pre-change snapshot (4 diff lines — known pre-existing drift):
163,164c163,164
<   //   (b) extend `InitEnv` + meta.yaml with a dedicated `SENTRY_RELEASE`
<   //       token and prefer it here: ...
---
>   //   (b) extend `InitEnv` with a dedicated `SENTRY_RELEASE` field and
>   //       prefer it here: ...

Post-WR-04 output: identical content
diff snapshot after: EMPTY (content-level) — WR-04 did not change symmetry state
```

## Acceptance Criteria

- [x] `grep -E 'withSentry\(\s*\(env: Env\) => buildSentryOptions\(env\)'` matches src/index.ts
- [x] `grep 'tracesSampleRate: 0.1' src/index.ts` returns nothing
- [x] `grep -F 'import { buildSentryOptions } from "./observability"' src/index.ts` matches
- [x] `.byte-symmetry.snapshot` exists and is gitignored — `git status --porcelain` returns nothing for it
- [x] Second `withSentry` argument (scheduled handler chain) byte-unchanged
- [x] `git diff --name-only` does not list frozen pair files
- [x] Byte-symmetry snapshot vs after: content-identical (WR-04 did not change symmetry state)
- [x] `npx vitest run` (openrouter) exits 0 — 17 passed

## Deviations from Plan

### Known Plan Issue (same as 27-02)

**`run-template-tests.sh openrouter` is not a valid stack name.** The harness only accepts `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-react-vite`, `ts-supabase-edge`, `go-fly-http`. The plan's verify block references this invalid ID. Openrouter tested directly via `npx vitest run` in the template directory — all 17 tests passed. This is a pre-existing plan documentation issue, not an implementation deviation.

### Trailing newline in snapshot comparison

The `--snapshot` mode writes `printf '%s\n' "$out"` (trailing newline) while plain run writes `printf '%s'` (no trailing newline). A raw `diff` of the two shows `\ No newline at end of file` on the after side. Content is byte-identical; the invariant holds. Documented here to prevent confusion in future reviews.

## Known Stubs

None. The entry is fully wired: `buildSentryOptions(env)` is called at runtime with the real `env` binding; no placeholder values flow to the SDK.

## Future Cleanup (Flagged — Do NOT Edit in Phase 27)

**Pre-existing comment-prose drift in byte-symmetry pair** (frozen during 1.21.0 cooling-off):

- File: `ts-cloudflare-worker/lib-observability.ts` line ~163-164
- Drift: cf-worker says `"+ meta.yaml with a dedicated ... token"`, openrouter says `"with a dedicated ... field"`
- Not token-substitutable
- Predates Phase 27
- Pair files are frozen during 1.21.0 baseline; fix in a future cleanup phase

## Threat Flags

None. WR-04 routes the entry THROUGH the already-tested helper (`buildSentryOptions`) — it does not introduce new network surfaces, auth paths, or schema changes. The `sendDefaultPii: false` and REDACTED_KEYS invariants live in the observability module (pair), which is preserved unchanged and verified by the snapshot check.

T-27-05-01 (Information Disclosure) mitigated: inline divergent options object removed; routing through test-locked helper eliminates silent PII-forwarding risk.
T-27-05-02 (Tampering — byte-symmetry pair) mitigated: snapshot-before/compare-after + `git diff --name-only` guard confirmed pair untouched.

## Self-Check: PASSED

Files exist:
- FOUND: add-observability/templates/openrouter-monitor/src/index.ts
- FOUND: add-observability/templates/.gitignore
- FOUND: .planning/phases/27-1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum-/27-05-SUMMARY.md

Commits exist:
- FOUND: 88b609e (feat(27-05): WR-04 — rewire openrouter entry to use buildSentryOptions(env))
