# Phase 09 — PLAN

**Migration:** 0006-llm-wiki-builder-integration
**Version bump:** 1.9.1 → 1.9.2
**Plan written via:** `superpowers:writing-plans`
**Inputs:** CONTEXT.md, RESEARCH.md, ADR 0019, drafted migration body (cleaned).

This plan converts RESEARCH.md decisions into executable tasks. The risk profile is lower than Phase 08 (install-time only, no PreToolUse hook), so the fixture matrix is narrower and the threat model is smaller. Same discipline: TDD red/green, multi-AI plan review dogfood, three-stage post-execution review.

## Plan change log

| Date | Change | Driver |
|---|---|---|
| 2026-05-13 | Initial draft | Phase scope |
| 2026-05-13 | **Amended after multi-AI review (09-REVIEWS.md)**: added T5b smoke test (B1), locked wrong-target symlink policy to ABORT (B2), locked missing-CLAUDE.md policy to skip-with-warning (B3), strengthened family heuristic to require child .git dirs (F2), added 6 new fixtures (count 9 → 15), removed CONTEXT/PLAN drift on path validation (F3), added harness sandbox-escape guard (F1). | codex review BLOCKs B1-B3 + FLAGs F1-F4 + gemini FLAGs |

---

## Task graph

```
T1 (fixtures-RED) ──┐
                    ├──> T3 (harness-stanza) ──> T4 (harness-GREEN)
T2 (migration-cleanup) ┘                                │
                                                        ▼
                                              T5 (live apply/rollback)
                                                        │
                                                        ▼
                                T6 (CHANGELOG + SKILL + README + config-hooks)
                                                        │
                                                        ▼
                                                  T7 (VERIFICATION.md)
```

Wave 1 (parallel): T1, T2.
Wave 2: T3 → T4.
Wave 3: T5.
Wave 4: T6.
Wave 5: T7.

Then Stage 1 + Stage 2 + CSO reviews; address findings; commit; open PR.

---

## Tasks

### T1 — Author test fixtures for 0006 migration (`tdd="true"`)

**Files written (15 scenarios, post-09-REVIEWS amendment):**
- `migrations/test-fixtures/0006/01-plugin-missing/{setup.sh,expected-exit,expected-stderr.txt}` — pre-flight fail
- `migrations/test-fixtures/0006/02-fresh-install/{setup.sh,expected-exit,verify.sh}` — clean tmp dir, full apply
- `migrations/test-fixtures/0006/03-idempotent-reapply/{setup.sh,expected-exit,verify.sh}` — reapply on top of 02 result
- `migrations/test-fixtures/0006/04-rollback/{setup.sh,expected-exit,verify.sh}` — apply then rollback; family data preserved
- `migrations/test-fixtures/0006/05-zero-families/{setup.sh,expected-exit,verify.sh}` — `~/Sourcecode/` has only skip-listed dirs; family-creation loop is no-op
- `migrations/test-fixtures/0006/06-existing-config-preserved/{setup.sh,expected-exit,verify.sh}` — pre-existing custom `.wiki-compiler.json` not clobbered
- `migrations/test-fixtures/0006/07-symlink-target-collision/{setup.sh,expected-exit,expected-stderr.txt}` — `~/.claude/plugins/llm-wiki-compiler` exists as a real file; migration refuses to overwrite
- `migrations/test-fixtures/0006/08-existing-correct-symlink/{setup.sh,expected-exit,verify.sh}` — symlink already points at right target; idempotent
- `migrations/test-fixtures/0006/09-claudemd-update-idempotency/{setup.sh,expected-exit,verify.sh}` — running twice doesn't duplicate `## Knowledge wiki` section
- **`migrations/test-fixtures/0006/10-wrong-target-symlink/{setup.sh,expected-exit,expected-stderr.txt}`** (codex B2) — symlink exists pointing at `/tmp/other-plugin`; migration ABORTS with locked-policy error message; user must rollback before reinstall.
- **`migrations/test-fixtures/0006/11-missing-family-claudemd/{setup.sh,expected-exit,verify.sh}`** (codex B3) — family dir exists but has no CLAUDE.md; migration applies everything else and logs `note: <family>/CLAUDE.md not present, skipping ## Knowledge wiki section addition`; no partial file created.
- **`migrations/test-fixtures/0006/12-non-family-dir-skipped/{setup.sh,expected-exit,verify.sh}`** (codex F2) — `~/Sourcecode/experiments/` exists with no immediate-child `.git` subdirs; migration skips it (heuristic: family iff `find <dir>/*/.git -maxdepth 1 -type d` is non-empty).
- **`migrations/test-fixtures/0006/13-missing-plugins-parent/{setup.sh,expected-exit,verify.sh}`** (codex F4) — `~/.claude/` exists but `~/.claude/plugins/` doesn't; migration `mkdir -p`'s the parent.
- **`migrations/test-fixtures/0006/14-knowledge-as-file/{setup.sh,expected-exit,expected-stderr.txt}`** (codex F4) — `<family>/.knowledge` exists as a regular file (not dir); migration aborts with clear error rather than silently failing on `mkdir`.
- **`migrations/test-fixtures/0006/15-malformed-existing-config/{setup.sh,expected-exit,verify.sh}`** (codex F4) — pre-existing `.wiki-compiler.json` is invalid JSON; migration preserves it (per RESEARCH §5) but emits a `warn: <family>/.wiki-compiler.json exists but is not valid JSON; skipping` stderr line. User responsibility to fix.
- `migrations/test-fixtures/0006/README.md` — fixture documentation

**Each fixture:**
- `setup.sh` — materialize the pre-apply state in a tmp dir + write the apply script to a known path
- `verify.sh` (optional) — post-apply assertions (file presence, content checks, symlink-target verification)
- `expected-exit` — single integer
- `expected-stderr.txt` (optional) — strict line-presence stderr matching

**Sandboxing strategy:** Each fixture's `setup.sh` builds a fake `$HOME`-equivalent (e.g. `$TMP/home/`) with stub `~/.claude/plugins/`, stub `~/Sourcecode/{agenticapps,...}/`, stub `~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json`. The migration apply script runs with `HOME=$TMP/home` so all `~`-paths resolve to the sandbox. The host `~/.claude/` and `~/Sourcecode/` are never touched by the harness.

**Acceptance:**
- 9 scenarios written.
- Each setup.sh runs cleanly in a fresh tmp dir.
- Commit: `test(RED): phase 09 — 9 fixtures for migration 0006 LLM wiki builder integration`.

### T2 — Clean up migration 0006 body + ADR 0019

**Migration body changes** (`migrations/0006-llm-wiki-builder-integration.md`):
- Strike Step 3's "(Already created by migration 0005 if you applied that first — this step is a no-op in that case.)" — the current 0005 is multi-AI review, not knowledge scaffolding. Step 3 stays in 0006.
- Strike Notes section's references to `.knowledge/sources.yaml.legacy (created by migration 0005)` — that file doesn't exist anywhere.
- Strike Notes section's "Each family's CLAUDE.md (updated by migration 0005/0006)" — only 0006 touches family CLAUDE.md.
- **Add `**Idempotency check:**` markers** to Steps 1-5 + rollback (Phase 08 BLOCK-1 lesson).
- **Replace Step 1's bare `ln -sfn`** with the validated-target form from RESEARCH §6.
- **Add a new Step 4.5** (or rewrite Step 4) to append `## Knowledge wiki` section to each family CLAUDE.md (per RESEARCH §4).
- **Strengthen pre-flight** with `tr -d '[:space:]'` on the INSTALLED extraction (Phase 08 FLAG-E lesson).
- **Clean up `sed -i.bak`** to chain `&& rm -f .bak` (Phase 08 FLAG-C lesson).

**ADR changes** (`docs/decisions/0019-llm-wiki-compiler-integration.md`):
- Strike "Related: Migration 0005 (knowledge substrate scaffold), Migration 0006 (wiki-builder integration)" — rewrite to just "Related: Migration 0006".
- Strike "Why .wiki-compiler.json instead of sources.yaml" section's "Migration 0005 originally created `<family>/.knowledge/sources.yaml`..." paragraph — that draft never shipped.
- Strike "Relationship to migration 0005" section entirely — replace with a 2-line note that 0006 is self-contained.
- Update "Migration" pointer at top: reflect the fold-in of directory scaffolding into 0006.

**Acceptance:**
- Migration body has zero references to a non-existent prior scaffold step.
- ADR 0019 has zero references to a non-existent 0005-knowledge migration.
- All 5 apply steps have explicit Idempotency check markers.
- Commit: `refactor(0006): self-contain migration body + idempotency markers + symlink validation`.

### T3 — Add `test_migration_0006()` stanza to `migrations/run-tests.sh`

**Action:** Append a function modeled on `test_migration_0005()` but adapted for install-time semantics:
1. Pre-check: FAIL if migration body file is missing.
2. For each fixture under `migrations/test-fixtures/0006/`:
   - `mktemp -d` for fake `$HOME`; chdir to that tmp dir.
   - Run `setup.sh` to materialize pre-apply state.
   - Run the migration's apply script with `HOME=$TMP/home`; capture exit + stderr.
   - Run `verify.sh` (if present) for post-apply assertions.
   - Assert exit code matches `expected-exit`.
   - Assert stderr matches `expected-stderr.txt` (strict line-presence per Phase 08 F1).
3. Per-fixture cleanup: `rm -rf $TMP`.

**Acceptance:**
- Function added to run-tests.sh.
- Dispatcher updated to invoke `test_migration_0006` when filter matches.

### T4 — Verify `test_migration_0006()` passes all 9 assertions (`tdd="true"`)

**Action:** Run `bash migrations/run-tests.sh 0006`. Confirm 9/9 PASS. Iterate on T1/T2/T3 until green.

**Acceptance:**
- 9/9 assertions PASS.
- Full harness shows no NEW failures vs main.
- Commit: `feat(GREEN): phase 09 — test_migration_0006() harness, 9/9 PASS`.

### T5 — Live apply / idempotent re-apply / rollback against a real tmp sandbox

**Action:** Build a sandboxed `$HOME` directory with realistic layout (vendored plugin stub, two stub family dirs, baseline SKILL.md at 1.9.1). Run the migration body end-to-end:
1. Apply — verify symlink, dirs, configs, CLAUDE.md sections, version bump.
2. Idempotent re-apply — verify no duplicate entries, no config clobbering, no CLAUDE.md duplication.
3. Rollback — verify symlink removed, version reverted; verify family data preserved.

Capture before/after snapshots; record in VERIFICATION.md.

**Acceptance:**
- All three cycles green.
- Snapshot diffs match RESEARCH §3 (preserve-data rollback) expectations.

### T5b — Post-apply usability smoke test (codex B1)

Closes the goal-vs-verification gap: T5 proves filesystem state, T5b proves the install is *parseable and discoverable*. Cheaper than running an actual `/wiki-compile` (no LLM round-trip) but catches malformed manifests, broken globs, and non-discoverable command surfaces.

**Action:** Against the same sandbox T5 leaves behind (post-apply, before rollback):
1. **Plugin manifest parses:** `jq empty ~/.claude/plugins/llm-wiki-compiler/.claude-plugin/plugin.json` exits 0.
2. **Plugin declares canonical commands:** the manifest's `commands` array (or equivalent — depends on the plugin's manifest schema, inspected during T5b authoring) includes at least `wiki-compile` and `wiki-lint`. If absent, the install is non-discoverable from Claude Code.
3. **Per-family config parses:** for each `<family>/.wiki-compiler.json` written, `jq empty` exits 0.
4. **At least one source glob resolves:** for each family config, at least one entry in `sources[*].path` resolves to ≥1 real file via `compgen -G <glob>` (within the sandbox). Catches typos like `**/docs/decisons` (note the typo) that would compile to an empty wiki.

**Acceptance:**
- All four checks green for the sandbox T5 built.
- Numbers and `jq` outputs land in VERIFICATION.md.
- If any check fails, this is a BLOCK and the migration body enters a fix sub-task.

### T6 — Wire contract entries + version bump

**Files modified:**
- `CHANGELOG.md` — new `## [1.9.2] — Unreleased` section above `## [1.9.1]` with `### Added` block.
- `skill/SKILL.md` — frontmatter `version: 1.9.1` → `version: 1.9.2`.
- `migrations/README.md` — index row for 0006: change `*(draft — PR #12)*` annotation to `1.9.1 → 1.9.2`.
- `templates/config-hooks.json` — informational entry under a new `wiki_integration` block (no `pre_execute_gates` since this migration installs no hooks). Document the slash commands the user gains.

**Acceptance:**
- `jq empty templates/config-hooks.json` exits 0.
- `grep '\[1.9.2\]' CHANGELOG.md` matches.
- `grep '^version: 1.9.2$' skill/SKILL.md` matches.

### T7 — VERIFICATION.md

**File written:**
- `.planning/phases/09-llm-wiki-builder-integration/VERIFICATION.md` — 1:1 evidence per AC-1 through AC-10.

**Acceptance:**
- Each AC has a `**Evidence:**` bullet pointing to a file/line/command output.
- AC-2 evidence cites T5 sandbox diff.
- AC-4 evidence cites harness output.
- AC-10 evidence cites the gate-fires-on-this-phase property: the multi-AI review gate (installed in Phase 08) blocked T1 execution until `09-REVIEWS.md` existed.

---

## Threat model (STRIDE — smaller than Phase 08)

| Threat | STRIDE | Surface | Mitigation | Evidence |
|---|---|---|---|---|
| Symlink overwrites a real file at `~/.claude/plugins/llm-wiki-compiler` | **I**, **T** | Step 1's `ln -sfn` with `-f` flag would delete an existing regular file. | RESEARCH §6 validates target type before symlink. Fixture 07 asserts refusal-to-overwrite. | Fixture 07. |
| Cross-family `.wiki-compiler.json` leak | **I** | A misconfigured `sources[*].path` could point at another family's directory. | The default config uses `<family>/*/...` glob patterns rooted at the family directory. Pre-flight (T2 cleanup) does NOT validate path-resolution at write time — the plugin handles it at compile time. Risk is low because the migration only writes the *default* config; user customization is the user's responsibility. | Documented in Notes section of migration. |
| Family CLAUDE.md collision | **I** | Migration appends `## Knowledge wiki` section. If user has a section by that name, appending creates a duplicate. | Idempotency check: `grep -q '^## Knowledge wiki' <family>/CLAUDE.md` before appending. Fixture 09 asserts no duplication on re-apply. | Fixture 09. |
| Plugin supply chain (vendored copy compromised) | **T** | `~/Sourcecode/agenticapps/wiki-builder/` is cloned from upstream. If upstream is compromised or maintainer changes, a `git pull` brings malicious code into the symlinked plugin. | Out of scope for this migration. Document the trust assumption in ADR 0019. Future hardening: pin to a tag + SHA-256 (same approach as Phase 08 CSO M2 deferred item). | Note in ADR + migration Notes. |
| Vendored plugin contains hooks that fire at session start | **E** | The plugin ships its own hooks (under `wiki-builder/plugin/hooks/`). When symlinked into `~/.claude/plugins/`, those hooks execute in every Claude session on the host. | The plugin is OSS, auditable, and version-pinned via vendoring. Risk is the same as installing any community plugin. Mitigation: read the plugin's hooks before symlinking; document discoverability. | Documented as a known trade-off in ADR 0019. |
| Rollback leaves orphan files | **R** | Rollback preserves family data by design (RESEARCH §3). A user expecting clean uninstall is surprised. | Documented in migration Notes section. The cleanup-after-rollback command is given explicitly. | Notes section. |
| Version-bump partial state | **D** | If Step 5 (version bump) fails after Steps 1-4 succeed, the project is in an inconsistent state: symlink + configs + CLAUDE.md sections present, but `SKILL.md` still says 1.9.1. Re-applying would skip the dir/config/symlink steps (idempotency) but retry Step 5. | Each step has its own idempotency check; re-applying is safe even after partial failure. The migration framework treats "no version bump" as "migration didn't apply" and retries the whole body next `/update` run. | Fixture 03 (idempotent re-apply). |

No PreToolUse exposure — no latency budget.

---

## Goal-backward verification matrix

Goal: *Any consumer running `/setup-agenticapps-workflow` on a fresh machine OR `/update-agenticapps-workflow` on a 1.9.1 project gets the same wiki integration that's currently set up manually on this dev host.*

1. **Goal:** Plugin installed globally, family configs present, `.knowledge/` dirs scaffolded.
2. **Necessary condition:** Migration 0006 applies cleanly from 1.9.1 baseline.
3. **For (2):** T5 live-apply fixture passes. T6's contract entries reflect the new state.
4. **Sufficiency condition:** Idempotent re-apply is a no-op AND rollback returns to 1.9.1 baseline without destroying user data.
5. **For (4):** Fixtures 03 (re-apply) and 04 (rollback) pass. T5's live sandbox confirms both.
6. **Goal achieved if-and-only-if** T4 passes (harness GREEN) AND T5 confirms apply/idempotent/rollback live.

---

## Dependencies & ordering

| Task | Blocked by |
|---|---|
| T1 fixtures | (none — parallel with T2) |
| T2 migration + ADR cleanup | (none — parallel with T1) |
| T3 harness stanza | T1, T2 |
| T4 harness PASS | T3 |
| T5 live sandbox | T2, T4 |
| T6 contract wiring | T5 |
| T7 VERIFICATION.md | T1-T6 all complete |

---

## Out-of-band commitments (per CONTEXT.md)

- **Multi-AI plan review must run before T1 executes.** This phase is the first to *receive* the gate that Phase 08 installed. The gate isn't active on this branch (because we don't install it locally on this dev machine — the gate ships to consumer projects), so technically T1 could proceed without REVIEWS.md. But the discipline applies: we run codex + gemini against PLAN.md and capture in `09-REVIEWS.md` before T1.
- **Stage 1 / Stage 2 / CSO reviews** post-execution, before PR.

---

## Risks accepted

- **Dynamic family detection means behavior depends on `~/Sourcecode/` layout.** Two machines with different family directories produce different results. Acceptable: that's the point.
- **Plugin hooks run in every Claude session after symlink installs.** Documented as a known trade-off in ADR 0019. Users who don't want this can either skip migration 0006 (it's optional per the frontmatter) or unsymlink after install.
- **Pre-existing `.wiki-compiler.json` files are preserved even if stale.** Users with old-schema configs need to manually upgrade. The plugin's lint command detects schema drift.

---

## Definition of done

- All 7 tasks complete in TaskList.
- `migrations/run-tests.sh 0006` → 9/9 PASS.
- `CHANGELOG.md [1.9.2]` section landed.
- `SKILL.md` version is `1.9.2`.
- REVIEW.md has Stage 1 + Stage 2 sections, both APPROVE (or APPROVE-WITH-FLAGS with FLAGs prose-addressed).
- SECURITY.md from `/cso` recorded — no Critical findings.
- VERIFICATION.md has 1:1 evidence for AC-1 through AC-10.
- PR opened, non-draft, targeting main.
