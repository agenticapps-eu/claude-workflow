# Session Handoff — 2026-07-08 (Migration 0026 IMPLEMENTED — post-review gates + PR remain)

## Status: plan executed + reviewed + verified GREEN. Remaining: /cso, optional cross-AI review, PR.
Branch `feat/gitnexus-background-reindex` (off main @ 6957f19). All 4 plan tasks done, each task-reviewed clean, whole-branch opus review done (verdict: merge-with-fixtures), the one Important finding FIXED, verification-before-completion GREEN.

## Accomplished this session
- **writing-plans** → `docs/superpowers/plans/2026-07-08-gitnexus-background-reindex.md` (78379bf).
- **subagent-driven-development** — all 4 tasks (fresh implementer + task-reviewer each; all spec ✅ / quality Approved):
  - T1 (4dfe6df): engine `templates/.claude/hooks/gitnexus-reindex.cjs` (ported + `$CLAUDE_PROJECT_DIR`-preferred root) + fixture 05-engine-behaviour + `test_migration_0026()` in run-tests.sh.
  - T2 (6ac8d9e): `bin/build-snapshot.sh` copies `.cjs` (+chmod); PostToolUse Bash entry in `templates/claude-settings.json`; snapshot regenerated; parity §2 binding + new §8 (with RED-proof).
  - T3 (1a44f02): `migrations/0026-...md` + replay fixtures 01–04 + `skill/SKILL.md` 2.3.0→2.4.0 (lockstep) + snapshot rebuild (VERSION 2.4.0).
  - T4 (c50fe98): ADR-0039, CHANGELOG [2.4.0], MANIFEST.
- **Final whole-branch review (opus):** no Critical; 1 Important (#1) FIXED at **f4a9f41** — fixture 02 idempotency test was vacuous (else-branch `"x"` never matched `gitnexus-reindex`); now uses the real payload + asserts total PostToolUse length unchanged; load-bearing proof held.
- **Verification-before-completion GREEN:** `run-tests.sh` exit 0 `PASS:165`; `check-snapshot-parity.sh` PASS; `build-snapshot.sh --check` OK. (Uncounted preflight `FAIL=2` = pre-existing env probes: 0008 curl to a down local server, 0011 local scaffolder-clone file — unrelated.)

## Open review findings (Minor, in .superpowers/sdd/progress.md)
- **#2 (for /cso):** engine spawns `sh -c 'gitnexus analyze …; rm -f "<lock>"'` with the repo path interpolated into the shell string — low-prob injection if a repo path contains `` ` ``/`$(…)`/`"`. Paths come from git/`CLAUDE_PROJECT_DIR`. Engine is a verbatim port of `~/.gitnexus-hooks/reindex-on-change.cjs`; hardening = argv-form spawn + rm lock from Node. Left for /cso (didn't unilaterally deviate from the plan-mandated verbatim port).
- #3 10-min TTL reclaim could double-spawn on a >10min analyze (add a comment). #4 fires on every Bash call (inherent). #5 fixtures replay a copy of migration jq (pre-existing pattern, 0025 too).

## Next session: start here
Remaining workflow-commitment gates: (1) **/cso** — warranted (hook spawns a subprocess + touches storage); focus on finding #2. (2) Optional **cross-AI review** (two-stage / [[gsd-review-non-skippable]]) — note the code already had 4 task reviews + 1 opus whole-branch review; /gsd-review is really a plan gate. (3) **finishing-a-development-branch → PR** (outward-facing — confirm with user first). **AFTER MERGE:** fast-forward `~/.claude/skills/agenticapps-workflow`, then `/update-agenticapps-workflow` per repo.

## Environment (carry-over, still true)
GitNexus pinned to **1.6.4** globally; `GITNEXUS_INVOCATION=gitnexus` in `~/.claude/settings.json`. **Do NOT run `npx gitnexus analyze`** (the stale-index nudge that keeps firing is exactly what this migration eliminates). SDD scratch (briefs/reports/ledger/diffs) under `.superpowers/sdd/` (git-ignored). The `~/.gitnexus-hooks/` engine stays host-local; this migration is the Claude-host productization.

---

# Session Handoff — 2026-07-08 (GitNexus FTS root-cause fix + freshness hooks)

## Accomplished
- **Fixed the GitNexus FTS "DB v42 vs build v40" errors.** Root cause was NOT cross-build skew (the prior [[gitnexus-fts-version-skew]] memory was backwards). It's a **single-build bug**: gitnexus's LadybugDB engine writes storage **v42** but the bundled FTS extension reads **v40**, in every build 1.6.5→1.6.10-rc.7. Proven by running `analyze` then reading `.gitnexus/lbug` offset 4 immediately. **1.6.4 is the newest internally-consistent build** (engine+FTS both v40) — which is why codex/opencode (pinned 1.6.3) never errored.
- **Pinned global gitnexus 1.6.9-rc.44 → 1.6.4** on node v24.16.0 (backs Claude PATH + MCP). Re-analyzed **all 11 indexed repos to v40** — 3 were misaligned (agenticapps-workflow-core v42, agenticapps-dashboard v41, fx-signal-agent v41).
- **Durability guard:** added `GITNEXUS_INVOCATION=gitnexus` to `~/.claude/settings.json` `env` so `run.cjs` uses the local 1.6.4 build instead of npx/pnpm-dlx registry-latest (v42) on manual reindexes.
- **Freshness hooks (reindex, not nudge):** shared engine `~/.gitnexus-hooks/reindex-on-change.cjs` (detached background incremental reindex, lockfile-guarded, writer pinned to local build, fail-open, kill-switch `GITNEXUS_AUTOREINDEX_DISABLED=1`); opencode plugin `~/.config/opencode/plugin/gitnexus-freshness.ts` (live, Nyx-safe); codex patch staged in scratchpad (hooks.json is Nyx-managed → not auto-applied).
- Mapped GitNexus/wiki-builder hook wiring across Claude/codex/opencode: Claude alone had the freshness hook (staleness-nudge, not reindex); codex/opencode had gitnexus as MCP + skills only. wiki-builder = staleness-nudge on SessionStart, manual `/wiki-compile`.

## Decisions
- **Downgrade, not upgrade** — fix is to pin ≤1.6.4, the opposite of the old memory's "upgrade CLI to v41". Trade-off: ~5 patch versions behind; revert with `npm i -g gitnexus@1.6.9` if FTS-search-disabled is acceptable (graph queries/MCP still work).
- **codex/opencode left on 1.6.3** (already v40-consistent, no error).
- Corrected the `gitnexus-fts-version-skew` memory + MEMORY.md index to the single-build root cause.

## Files modified (ALL OUTSIDE version control — nothing else to commit)
- `~/.claude/settings.json` (GITNEXUS_INVOCATION env) — not a git repo
- `~/.gitnexus-hooks/reindex-on-change.cjs`, `~/.config/opencode/plugin/gitnexus-freshness.ts` — new, not git repos
- `.gitnexus/` DBs across 11 repos re-analyzed to v40 — gitignored
- Auto-memory `gitnexus-fts-version-skew.md` rewritten

## Next session: start here
GitNexus FTS is fixed and all 11 repos aligned at v40. Optional follow-ups: (1) apply the staged codex freshness patch (`scratchpad/codex-gitnexus-freshness.md`) — caveat: Nyx may regenerate `~/.codex/hooks.json`; (2) bump codex/opencode to 1.6.4 for uniformity; (3) **file the upstream gitnexus bug** (FTS native extension storage version lags the engine from 1.6.5+); (4) consider baking `GITNEXUS_INVOCATION=gitnexus` into the claude-workflow snapshot so `run.cjs` never pulls a newer-format writer.

## Open questions
- Adopt the background-reindex engine into the Claude hook itself (currently Claude only nudges)? That's a claude-workflow product change (a migration), not just local config.

---

# Session Handoff — 2026-07-06 (Rollout 1 + §15 backfill + 2 bug fixes)

## Bug fixes (this session, both MERGED)
- **claude-workflow #80** — setup/SKILL.md Step 5 post-check asserted a stale §14 injection grep (moved to injection-guard at 0023); replaced with a §15 ritual-tail marker present in the 2.3.0 snapshot. Scaffolder clone fast-forwarded.
- **agenticapps-dashboard #62** — flaky CI: **9** agent test files each ran `tsup` (clean:true) in `beforeAll`; vitest's parallel forks raced on the shared `dist/` → intermittent `ERR_MODULE_NOT_FOUND` when a spawned `node dist/cli.js` hit a mid-clean dist. Fix: removed all in-test builds; rely on the pre-test `pnpm build` CI already runs (+ `pretest: tsup` for local). **Lesson: a vitest project-level `globalSetup` fires per-fork in workspace mode — my first cut used it and reintroduced the race; don't build inside the test lifecycle at all.** Verified 111 files pass, 0 in-test builds; CI green, merged clean (no override).

---

# Session Handoff — 2026-07-06 (Rollout 1 landed + §15 backfill)

## Accomplished
- **Rollout 1 fully landed** — 6 repos now on claude-workflow **v2.3.0** via merged PRs:
  - **4 factiv** (fx-signal-agent #103, callbot #85, cparx #83, fbc-platform #59): replayed migrations 0023→0025, §14 declined (supported no-op), surgical commits (SKILL.md + config.json only). Admin-merged (authorized) — blocked by pre-existing failing security checks (gitleaks/pnpm-audit), unrelated to the 2-file diffs.
  - **agenticapps-roadmap #3**: moved from `phase-03-linear-proxy` → `main`, updated to 2.3.0, merged clean (no override). 48-commit phase-04 WIP branch untouched. Repo left on main.
  - **agenticapps-dashboard #61**: fresh **snapshot install** (ADR-0036, no replay) — removed a stray full clone of claude-workflow.git at `.claude/skills/agenticapps-workflow`; laid down skill v2.3.0 + settings/hooks/scripts + claude-md/workflow.md + CLAUDE.md ref + ADR template; merged snapshot hooks + §15 knowledge_capture into existing GSD config. Changed `.gitignore` `.claude/skills/` → `.claude/skills/*` + negation so the workflow version marker is tracked (other skills stay local). Admin-merged (authorized); CI failure was a pre-existing stale-dist subprocess test in packages/agent, unrelated.
- **Installed injection-guard prerequisite**: ran obs `install.sh` (v0.13.0) → `~/.claude/skills/injection-guard` symlink (0023 pre-flight needed it). Repointed obs/add-observability skill links to current Sourcecode repo.
- **§15 Obsidian backfill** — created 4 notes in `~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/`: callbot.md (8), cparx.md (8), fbc-platform.md (7), fx-signal-agent.md (8 learnings). Mined via 4 parallel agents from session-handoffs/ADRs/planning/git history, curated to the vault's transferable-only bar, secret-scanned.

## Decisions
- **Surgical commits** (only migration/install-touched files), not broad pre-step commits — the repos' dirt included ambiguous scratch. Pre-existing dirt left for repo owners.
- **Branch → PR → (admin-)merge per repo** — honors "never commit to main" + the repos' PR-to-main convention. Admin override used only where pre-existing unrelated checks blocked, with explicit per-scope authorization.
- **§14 declined for the mechanical pass** — full injection-guard init is a 9-phase source-modifying scaffold across ~6 roots per monorepo; deferred to its own pass.

## Files modified
- 6 repos: merged workflow-update/install commits (see PRs above). No app code touched.
- `~/.claude/skills/{injection-guard,observability,add-observability}` symlinks.
- 4 new vault notes (outside any repo).

## Next session: start here
Rollout 1 is done. Deferred workstreams, in priority order: (1) **full §14 `/injection-guard init`** as a per-repo pass (fx-signal-agent first — worker-agent is the clear LLM path), run *inside* each repo through its 3 consent gates; (2) decide whether to fresh-install 2.3.0 into the **never-installed agenticapps repos** (observability, agentlinter, wiki-builder, dotclaude) — rollout said flag-not-install; (3) the 2 dirty never-installed factiv repos (factiv-design-system, factiv-website) + open-design + pi-agentic-apps-workflow.

## Open questions / loose ends
- **Stale setup post-check**: setup/SKILL.md Step 5 asserts `grep -rq "prompt.injection|injection-defense" .claude`, which no longer holds for the 2.3.0 snapshot (§14 moved to injection-guard at 0023). Fix in claude-workflow (drop/replace that post-check).
- **fbc-platform CLAUDE.md** has no workflow-reference block — verify intended.
- **agenticapps-dashboard** has a real pre-existing CI bug: `packages/agent` subprocess test fails on a missing `dist/chunk-*.js` (stale build artifact) — worth fixing independently.
- **Local `main` in the 5 update repos is 1 commit behind** origin after merge (they carry pre-existing dirt) — `git pull` when each tree is clean.
- **claude-workflow's own `.planning/config.json` still lacks `knowledge_capture`** (carried from prior handoff).
- **GitNexus FTS v41/v40 skew persists** ([[gitnexus-fts-version-skew]]).
