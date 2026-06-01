# Session Handoff — 2026-06-01 (Phase 25 MERGED — v1.20.0 live)

## Accomplished

- **Phase 25 merged to main** as `8a838e8 v1.20.0 fix(#56): 0019 engine + withCronMonitor/withQueueMonitor + Migration 0021 (#57)`. Squash-merge per repo convention (see `git log main --no-merges` — every recent landing has the `(#NN)` fingerprint).
- **v1.20.0 ships:** claude-workflow 1.19.0 → 1.20.0; add-observability 0.8.0 → 0.9.0. Two migration deltas (0019 re-rev + new 0021).
- **All four issue #56 findings closed** with ADRs 0031/0032/0033 + codex-revised narrowed scopes (D-05 cf-worker+openrouter, D-07 cf-worker+cf-pages, D-19 cf-worker+cf-pages+openrouter; supabase-edge carve-outs honored throughout).
- **Audit chain on PR:** code review (0 critical · 4 warn · 5 info) · security (13/13 threats closed) · verification (7/7 SC) · validation (`nyquist_compliant: true`).
- **CodeRabbit cycle (2 rounds):** initial 18 actionable; 5 closed by fix-up commits (`5226a22` test header + CHANGELOG D-05 scope/type + plan awk + `efec4e2` D-19 scope drift in both CHANGELOGs). Final state: 13 remaining = 10 markdown-lint nitpicks + 1 JSDoc + 2 design-call items parked for Phase 26.
- **Local cleanup:** main fast-forwarded to `8a838e8`; local feature branch deleted. STATE.md + session-handoff.md (this file) updated to MERGED state.

## Decisions

- **Squash-merge over merge-commit:** matched repo's established `vN.X.Y ... (#NN)` convention (every landing in `git log main --no-merges` for the last 10 PRs).
- **CodeRabbit findings D + E parked for Phase 26 — design-call items, not last-mile fixes:**
  - D — `_filter_index_ts_requires_co_anchor` content-marker firewall (`templates/.claude/scripts/migrate-0019-...sh:233`): currently only checks sibling-middleware existence, not `index.ts` content. Any `src/index.ts + src/middleware.ts` Hono/Worker app gets flagged. Downstream REFUSE path catches it (no destructive write), but emits unsolicited `.observability-0019.patch`. Add `grep -q "observability\|withObservability\|sentry"` filter in Phase 26.
  - E — `0021/04-callbot-shape-strict-env-typecheck/verify.sh:75-77` silently `exit 0` when `npx` unavailable, masking TS1038 in ambient `declare const console` block. Phase 26: pin tsc via `node_modules/.bin/tsc` fallback or fail the fixture when npx is missing.
- **CodeRabbit finding C kept as historical fix:** awk predicate `awk "{exit !(>=4)}"` in `25-05-PLAN.md:1093` was a real bug but only affected the verify command if anyone re-runs it. Fixed cleanly to `awk '{exit !($1>=4)}'`; smoke-tested rc=0 for input 4, rc=1 for input 3.
- **Markdown-lint findings skipped:** 10 × MD040/MD046/MD028/MD058/MD001/MD056 across historical `25-*-PLAN.md` / `25-CONTEXT.md` / `25-RESEARCH.md` / `25-REVIEWS.md` / `25-VALIDATION.md` / `25-02-SUMMARY.md`. Cosmetic, in already-shipped planning artifacts. Not worth piecemeal touch-ups.
- **ROADMAP.md "stray 63" finding rejected:** CodeRabbit hallucination — verified, file ends at line 62.

## Files modified (this session)

- `.planning/STATE.md` — flipped `status: executing` → `merged`, milestone bumped, Session Continuity rewritten for Phase 26 routing
- `session-handoff.md` (this file) — rewritten for MERGED state

Phase 25 itself shipped 46 commits via PR #57; see `git log --oneline 875c90c..8a838e8` (single squash commit on main, rich per-task history preserved on the deleted branch ref / PR commits view).

## Next session: start here

1. **`/gsd-discuss-phase 26`** — worker-template hardening. Scope:
   - **DEF-1** (TRACE_SAMPLE_RATE unwired) from PR #55 carry-forward
   - **DEF-2** (REDACTED_KEYS missing `authorization` / `bearer`)
   - **DEF-3** (module-level mutable singletons)
   - **F-2** (no tracked package-lock.json policy)
   - **NEW: vitest pin defense** — upstream npm-registry drift bit us at audit time. Options: (a) pin to `~3.2.4` in harness, (b) commit tracked `package-lock.json` for the harness, (c) both. Documented in `25-VALIDATION.md` "Environmental caveat (audit-time, 2026-06-01)".
   - **NEW: CodeRabbit finding D** — `_filter_index_ts_requires_co_anchor` content-marker firewall to prevent false positives on `src/index.ts + src/middleware.ts` non-wrapper apps.
   - **NEW: CodeRabbit finding E** — `0021/04 verify.sh` exit-0 mask + TS1038 ambient `declare const console`.
   - Extend Phase 24's `.gitignore` shape from `openrouter-monitor` to `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`.

2. **Optional: trigger callbot follow-up PR** per issue #56 acceptance signals:
   - drop LOCAL-PATCH at `callbot:cron-monitor.ts:141-149`
   - re-run Migration 0021 cleanly
   - replace local `withMonitor` helper with `withCronMonitor` + `withQueueMonitor` from upstream
   - verify `tsc --noEmit` green against `CallbotEnv`

## Open questions / follow-ups

- **Remote branch `feat/fix-0019-engine-and-cron-wrappers-v1.20.0` still exists on origin** (squash-merge `--delete-branch` failed due to local checkout conflict). Decide whether to `git push origin --delete feat/fix-0019-engine-and-cron-wrappers-v1.20.0` (standard cleanup) or keep for archival reference. Recommendation: delete — squash captured everything onto main.
- **Untracked session noise (unchanged):** `.claude/`, `AGENTS.md`, `CLAUDE.md` (gstack-prompted), `.planning/config.json`, `add-observability/templates/openrouter-monitor/package-lock.json`, `add-observability/templates/{ts-cloudflare-{pages,worker}}/node_modules/`, `FIX-0017-ENGINE.md`. Phase 26 cleanup pass should triage each — commit, .gitignore, or delete.
- **Full retroactive ROADMAP/STATE/PROJECT bootstrap still deferred** — current stubs are minimum enablers. Should land before Phase 27 ideally.
- **gstack 1.48 → 1.52 upgrade available** — snoozed from prior session. Run `/gstack-upgrade` when convenient.

## State snapshot for resumption

- Branch: `main` at `8a838e8` (fast-forwarded post-merge; clean working tree apart from session noise listed above)
- Remote: origin/main matches; origin's `feat/fix-0019-engine-and-cron-wrappers-v1.20.0` ref still present (cleanup pending decision)
- STATE.md status: `merged` / current focus: Phase 26 next to discuss
- ROADMAP.md: Phase 25 marked Complete; Phase 26 stub still TBD
- Versions live on main: claude-workflow `1.20.0`, add-observability `0.9.0`
- PR #57: MERGED on 2026-06-01 by DonaldVl, squash-merge `8a838e8`
