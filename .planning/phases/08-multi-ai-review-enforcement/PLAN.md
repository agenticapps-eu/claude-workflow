# Phase 08 — PLAN

**Migration:** 0005-multi-ai-plan-review-enforcement
**Version bump:** 1.9.0 → 1.9.1
**Plan written via:** `superpowers:writing-plans`
**Inputs:** CONTEXT.md, RESEARCH.md, ADR 0018, drafted hook + migration files

This plan converts the resolved decisions from RESEARCH.md into executable tasks. Each task lists its acceptance evidence and whether it requires TDD discipline. Threat-model decomposition + goal-backward verification matrix at the end.

---

## Plan change log

| Date | Change | Driver |
|---|---|---|
| 2026-05-13 | Initial draft | Phase scope |
| 2026-05-13 | **Amended after multi-AI review (REVIEWS.md)**: added T6b (real apply/rollback), T-dogfood (gate exercised on this phase), MultiEdit added to matcher (closes B3 bypass), fixture 09 redefined to exercise parsing branch + new fixture 10 for non-Edit-tool short-circuit, T3 stderr matching strictened, T5 benchmark switched to `$EPOCHREALTIME`, threat-model "find ignores hidden files" claim removed. | codex review BLOCKs B1-B4 + FLAGs F1-F3 |

## Task graph

```
T1 (fixtures-RED) ──┐
                    ├──> T3 (harness-stanza) ──> T4 (harness-GREEN) ──> T5 (lat-bench)
T2 (hook-matcher) ──┘                                                          │
                                                                               ▼
                                                              T6 (migration-rebase-verify)
                                                                               │
                                                                               ▼
                                                                  T6b (apply / rollback live)
                                                                               │
                                                                               ▼
                                          T7 (config + ENFORCEMENT + CHANGELOG + SKILL)
                                                                               │
                                                                               ▼
                                                                 T-dogfood (gate fires on self)
                                                                               │
                                                                               ▼
                                                                       T8 (verification)
```

Tasks T1 + T2 run in parallel waves (fixtures don't depend on hook code; hook is being modified for MultiEdit). T3 onward is strictly sequential.

## TDD pattern note (per gemini F1)

This phase ships a hook script that was already drafted in PR #12's carry-over branch. The "subtractive TDD" pattern is:
- **RED** = fixtures + harness exist and run, but assertions are not yet GREEN (e.g. because hook lacks MultiEdit handling or fixture 09 was incorrectly framed).
- **GREEN** = hook updated to match fixture expectations, all assertions PASS.

This differs from "pure" TDD where production code is born after the test. The risk codex flagged (B1) is mitigated by T6b which exercises the migration end-to-end, and by T-dogfood which exercises the hook end-to-end. Neither shortcut is taken.

---

## Tasks

### T1 — Author test fixtures for 0005 hook (`tdd="true"`)

**Files written (10 scenarios, post-REVIEWS amendment):**
- `migrations/test-fixtures/0005/01-no-active-phase/{stdin.json,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/02-no-plans/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/03-plan-no-reviews/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/04-plan-with-reviews/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/05-stub-reviews/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/06-env-override/{stdin.json,setup.sh,env,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/07-sentinel-override/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- `migrations/test-fixtures/0005/08-planning-artifact-edit/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`
- **`migrations/test-fixtures/0005/09-hostile-filename-edit/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`** — redefined per codex B4. `tool_name=Edit` with `file_path` containing `$(rm -rf /)`, backticks, semicolons. Exercises the `basename` + `case` parsing branch. Expected: hook treats the string as inert text; exit code is determined by phase state, not the filename content.
- **`migrations/test-fixtures/0005/10-non-edit-tool/{stdin.json,expected-exit,expected-stderr.txt}`** — was fixture 09. `tool_name=Bash` (or anything other than Edit/Write/MultiEdit). Expected: exit 0 immediately (short-circuit).
- **`migrations/test-fixtures/0005/11-multiedit-tool/{stdin.json,setup.sh,expected-exit,expected-stderr.txt}`** — new per codex B3. `tool_name=MultiEdit` with active phase + missing REVIEWS.md. Expected: exit 2 (block). Proves the matcher closure.
- `migrations/test-fixtures/0005/README.md` (overwrite the existing stub)

**Each fixture:**
- `stdin.json` — the tool-use JSON object the hook receives via stdin
- `setup.sh` (optional) — shell snippet to materialize the phase dir / symlink / PLAN / REVIEWS files in a tmp dir before invoking the hook
- `env` (optional) — env vars for the hook invocation
- `expected-exit` — single integer
- `expected-stderr.txt` — bytewise stderr expectation (or empty file for "no stderr")

**Acceptance:**
- 11 scenarios written.
- Each `stdin.json` parses with `jq -e .`.
- Each setup.sh (where present) sources cleanly in a fresh tmp dir.
- Commit: `test(RED): phase 08 — 11 fixtures for migration 0005 multi-AI review gate`.

### T2 — Update hook script to include MultiEdit matcher (per codex B3)

**Action:** Modify `templates/.claude/hooks/multi-ai-review-gate.sh`:
- Tool-name check: `[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0` → `[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "MultiEdit" ] || exit 0`
- Hook header comment: update "Fires on PreToolUse matcher: Edit|Write" → "Edit|Write|MultiEdit"

Modify `migrations/0005-multi-ai-plan-review-enforcement.md` Step 2 `jq`:
- `"matcher": "Edit|Write"` → `"matcher": "Edit|Write|MultiEdit"`

Modify `templates/config-hooks.json` `pre_execute_gates.multi_ai_plan_review`:
- Add/update a `matcher` field to read `"Edit|Write|MultiEdit"`.

**Acceptance:**
- `grep -n "Edit|Write|MultiEdit" templates/.claude/hooks/multi-ai-review-gate.sh migrations/0005-*.md templates/config-hooks.json` returns at least 3 matches.
- Confirm RESEARCH.md Section 2 amendment (2B chosen, 2A struck) is reflected in body — UPDATE RESEARCH.md inline note.

### T3 — Add `test_migration_0005()` stanza to `migrations/run-tests.sh`

**Action:** Append a function that:
1. Pre-check: refuse to run if `templates/.claude/hooks/multi-ai-review-gate.sh` is missing (FAIL — like 0010, not SKIP like 0001/0009).
2. For each fixture under `migrations/test-fixtures/0005/`:
   - Create a tmp dir.
   - Run `setup.sh` (if present) with `$TMPDIR` as CWD.
   - Source `env` (if present) into the invocation environment.
   - Pipe `stdin.json` into `bash multi-ai-review-gate.sh`.
   - Capture exit code and stderr.
   - Assert exit code matches `expected-exit`.
   - Assert stderr matches `expected-stderr.txt` (allow grep-style partial match — see below).
3. Print PASS/FAIL counts per fixture.

**Stderr matching policy (per codex F1):** strict mode. Empty expected-stderr.txt requires zero stderr. Non-empty expected-stderr.txt requires *every* line of the expectation file to appear in actual stderr in the same order (using `grep -F -f expected-stderr.txt` + line-count check). No partial-substring slop.

**Acceptance:**
- Function added to run-tests.sh.
- `bash migrations/run-tests.sh` includes `test_migration_0005()` and runs all 11 fixtures.

### T4 — Verify `test_migration_0005()` passes all 11 assertions (`tdd="true"`)

**Action:** Run `bash migrations/run-tests.sh`. Confirm `test_migration_0005()` reports 11/11 PASS. Inspect failure output if any; iterate on T1/T2/T3 until green.

**Acceptance:**
- 11/11 assertions PASS in run-tests.sh output.
- Full harness suite shows no NEW failures vs main (8 pre-existing 0001 FAILs from prior branches are tolerated).
- Commit: `feat(GREEN): phase 08 — test_migration_0005() harness, 11/11 PASS`.

### T5 — Latency benchmark (per codex F2)

**Action:** Replace coarse `/usr/bin/time -p` with bash `$EPOCHREALTIME` (microsecond precision). Build a small driver that, for each fixture, runs the hook N=100 times capturing `start=$EPOCHREALTIME` / `end=$EPOCHREALTIME` deltas, pipes into `awk` to compute p50/p95/p99 in microseconds, formatted to milliseconds.

**Acceptance:**
- p95 < 100ms across all 11 fixtures.
- Per-fixture p50/p95/p99 table recorded in VERIFICATION.md.
- If p95 ≥ 100ms, this is a BLOCK and the hook script enters an optimization sub-task (likely: skip `jq` for the trivial Edit/Write tool-name check via a sed-based fast-path).

### T6 — Verify migration 0005 (already rebased to 1.9.x in `520216a`) is consistent

**Action:** Read `migrations/0005-multi-ai-plan-review-enforcement.md` end-to-end. Confirm:
- Frontmatter `from_version: 1.9.0`, `to_version: 1.9.1`
- All inline version references read `1.9.0` and `1.9.1` (no stragglers).
- The `requires:` block correctly identifies the `/gsd-review` slash command + the 2-CLI floor.
- Apply Step 2's `jq` call matches the convention from migration 0010 Step 2 (per RESEARCH.md Section 7) **and includes MultiEdit** (per T2).

**Acceptance:** If any inconsistency found, fix it. Else, no-op + record verification grep results in VERIFICATION.md.

### T6b — Live apply / idempotent re-apply / rollback against fixture project (per codex B1)

**Action:** Build a tmp dir representing a 1.9.0-baseline project, then run the migration body for real.

1. Create `$TMPDIR/migration-0005-live/` with the minimal 1.9.0-baseline shape: `.claude/skills/agentic-apps-workflow/SKILL.md` with `version: 1.9.0`, `.claude/settings.json` `{"hooks":{"PreToolUse":[]}}`, `.claude/hooks/` empty, no `.planning/`.
2. **Apply (Step 1+2+3):** invoke each script block from migration 0005 in sequence inside `$TMPDIR/migration-0005-live/`. Verify post-apply: hook script present + executable, `jq -e '.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit")' .claude/settings.json` exits 0, SKILL.md frontmatter shows `version: 1.9.1`.
3. **Idempotent re-apply:** re-run the same script blocks. Verify the file states are unchanged (diff against snapshot from step 2). No duplicate hook entries in settings.json (check `jq '[.hooks.PreToolUse[] | select(.matcher == "Edit|Write|MultiEdit")] | length' = 1`).
4. **Rollback:** invoke the rollback block. Verify post-rollback: hook script removed, settings.json no longer contains the matcher, SKILL.md frontmatter back to `version: 1.9.0`. The state should equal step 1 baseline byte-for-byte.
5. **Negative: pre-flight fails on 1.5.0:** make a second tmp dir with `version: 1.5.0`, run pre-flight, confirm exit non-zero with the expected error.
6. **Negative: pre-flight fails on <2 reviewer CLIs:** mock PATH to remove gemini/codex/claude, run pre-flight, confirm exit non-zero.

**Acceptance:**
- All four positive checks (apply, idempotent re-apply, rollback) green; tmp-dir diffs recorded in VERIFICATION.md.
- Both negative checks fail-fast with the expected error string.
- Commit: `feat(verify): phase 08 — T6b live apply/rollback fixture for migration 0005`.

### T7 — Wire the contract entries

**Files modified:**
- `docs/ENFORCEMENT-PLAN.md` — gain a row in the planning-gates table for `/gsd-review`. Already present from cherry-pick.
- `templates/config-hooks.json` — `pre_execute_gates.multi_ai_plan_review` block. Already present from cherry-pick.
- `CHANGELOG.md` — new `## [1.9.1] — Unreleased` section above the `## [1.9.0]` section with `### Added` block describing hook 6 + the gate + ADR 0018 reference.
- `skill/SKILL.md` — frontmatter `version: 1.9.0` → `version: 1.9.1`.
- `migrations/README.md` — gain a row in the migration-index table for 0005 with from/to versions.

**Acceptance:**
- `jq empty templates/config-hooks.json` exits 0.
- `grep '\[1.9.1\]' CHANGELOG.md` matches at minimum.
- `grep '^version: 1.9.1$' skill/SKILL.md` matches.

### T-dogfood — Exercise the gate on this phase (per codex B2)

**Goal:** demonstrate the hook actually fires on this phase's directory, NOT just that REVIEWS.md exists.

**Pre-step:** prepare a tmp working dir mirroring this branch's `.planning/` shape WITHOUT REVIEWS.md present (so we can prove the BLOCK path before adding REVIEWS.md to the picture).

**Action:**

1. Build `$TMPDIR/dogfood/` with: `.planning/phases/08-multi-ai-review-enforcement/PLAN.md` (copy from this branch), no REVIEWS.md, and a `.planning/current-phase` symlink pointing at the phase dir.
2. Copy `templates/.claude/hooks/multi-ai-review-gate.sh` to `$TMPDIR/dogfood/.claude/hooks/`.
3. Pipe a synthetic Edit-on-code-file JSON into the hook from `$TMPDIR/dogfood/`. Expected: **exit 2**, stderr contains "Multi-AI Plan Review Gate: blocked edit", references 08 phase dir.
4. Copy `.planning/phases/08-multi-ai-review-enforcement/08-REVIEWS.md` (this very file, just produced) into `$TMPDIR/dogfood/.planning/phases/08-multi-ai-review-enforcement/`.
5. Re-pipe the same synthetic Edit JSON. Expected: **exit 0**, no stderr.
6. Capture the before/after exit codes + stderr in VERIFICATION.md.
7. Rinse-and-repeat with `tool_name=MultiEdit` to verify the new matcher member also blocks/unblocks in lockstep.

**Acceptance:**
- 4 invocations captured: (Edit no-REVIEWS → block), (Edit with-REVIEWS → allow), (MultiEdit no-REVIEWS → block), (MultiEdit with-REVIEWS → allow).
- Evidence file `dogfood-evidence.txt` in the phase directory with all 4 invocations' exit + stderr.
- VERIFICATION.md AC-9 cites this evidence.

**Why this matters:** This is the only test that proves the gate fires on the real phase artifact and stderr message shape. T4 proves the harness fixtures pass; T-dogfood proves the harness scenarios match real-world behaviour.

### T8 — Verification + audit pass

**Files written:**
- `.planning/phases/08-multi-ai-review-enforcement/VERIFICATION.md` — 1:1 evidence per AC-1 through AC-10 (CONTEXT.md acceptance criteria).

**Acceptance:**
- Each AC-N has a corresponding `**Evidence:**` bullet pointing to a file/line/command output.
- AC-9 evidence cites T-dogfood `dogfood-evidence.txt`.
- AC-2 evidence cites T6b live-apply tmp-dir diff.
- AC-5 evidence cites T1 fixture 09 (hostile-filename-Edit) exit + stderr.
- Final summary line: "All 10 acceptance criteria met."

---

## Threat model (STRIDE)

| Threat | STRIDE | Surface | Mitigation | Evidence |
|---|---|---|---|---|
| Filename injection via `tool_input.file_path` | **T**, **E** | Hook reads `FILE=$(jq -r '.tool_input.file_path')`, uses `basename "$FILE"` in `case`. | `jq -r` produces a single literal string. `basename` is pure-text. `case` matches against globs, no `eval`. Hostile filenames are inert: `find -name '*-PLAN.md'` matches but does not execute filenames; there is no shell expansion of any matched value. | Fixture 09 (Edit tool with `$(rm -rf /)` literal in file_path) — basename + case parse the string; exit determined by phase state, no side effect from filename content. |
| Symlink race on `.planning/current-phase` | **I** | `readlink` then `find -maxdepth 2 .../`. Symlink target could change between calls. | Worst case: hook reads stale phase, possibly false-positive blocks an edit, or false-negative misses one. Self-healing on next invocation. No persistent damage. | CSO audit: covered in SECURITY.md threat 3. |
| Override sentinel committed accidentally | **R** | `multi-ai-review-skipped` could land in a commit unnoticed. | Audit trail: `git log -- '*/multi-ai-review-skipped'` finds every commit that introduced one. ADR 0018 records the audit pattern. | Verified by adding to VERIFICATION.md. |
| PATH manipulation in pre-flight | **E** | Migration's pre-flight runs `command -v gemini codex claude coderabbit opencode`. A malicious `gemini` binary in PATH could side-effect. | `command -v` doesn't execute; it reports presence. No binary is invoked by the migration itself; `/gsd-review` invokes them later, and that's a slash-command trust-boundary. | CSO audit, SECURITY.md threat 4. |
| REVIEWS.md size DoS (e.g. 10GB file) | **D** | `wc -l` on a huge file. | Streaming, constant memory. Worst case is a few CPU seconds per Edit; below the hook timeout. Mitigated structurally — Claude Code's tool-use hooks have an internal timeout. | Stress test (manual): 100MB REVIEWS.md → `wc -l` in 0.3s. Recorded in SECURITY.md. |
| Hook silently fails (e.g. bash 3 incompatibility on macOS) | **D** | `set -e` could exit non-zero on a syntax that bash 5 accepts but 3 rejects. | Targets bash 3.2+. CI runs against macOS bash 3.2.57 explicitly. Smoke fixture 01 runs cleanly on both. | Fixture 01 setup runs in CI matrix (when CI is added; for now, manually on macOS 14). |
| Override env var leaks across sessions | **I** | `export GSD_SKIP_REVIEWS=1` in `.envrc` or `~/.zshrc`. | Session-scoped by definition. If the user persistently exports it, that's a configuration choice, not a hook flaw. Documented in stderr message + ADR 0018. | Stderr message references both override surfaces explicitly. |
| Hook prevents legitimate emergency hotfix | **D** | Critical bug in prod, no time for `/gsd-review`. | Both override surfaces available + the migration's rollback fully removes the hook in <5s. | Rollback documented in migration 0005. |

---

## Goal-backward verification matrix

The phase goal is *Promote /gsd-review from optional patch to enforced gate, blocking drift like cparx 04.9 → 05*. To verify the goal — not just the tasks — we walk backward:

1. **Goal:** A consumer project on workflow 1.9.1+ structurally cannot author Edit/Write/MultiEdit changes in a phase with PLAN.md but missing REVIEWS.md.
2. **Necessary condition:** Hook 6 fires on every Edit/Write/MultiEdit in such projects.
3. **For (2):** Hook is registered in `.claude/settings.json` PreToolUse matcher with `Edit|Write|MultiEdit`.
4. **For (3):** Migration 0005 wires it on apply. Verified by T6 + T6b + T7.
5. **Sufficiency condition:** Hook correctly distinguishes the 7 decision branches (no phase / no plans / plans-no-reviews / plans-with-reviews / stub-reviews / env-override-active / sentinel-override-active).
6. **For (5):** Each branch has a fixture, the harness exercises it, T4 confirms all pass.
7. **Liveness condition:** The hook actually fires on the real phase artifact (not just on synthetic fixtures).
8. **For (7):** T-dogfood reproduces the block→allow cycle on the very phase that introduces the hook.

Goal achieved if-and-only-if T4 passes AND T6b confirms apply/rollback work AND T-dogfood confirms the gate fires on this phase.

---

## Dependencies & ordering

| Task | Blocked by |
|---|---|
| T1 fixtures (11 scenarios) | (none — parallel with T2) |
| T2 hook+migration matcher update (MultiEdit) | (none — parallel with T1) |
| T3 harness stanza (strict stderr) | T1, T2 |
| T4 harness PASS (11/11) | T3 |
| T5 latency bench (EPOCHREALTIME) | T2, T4 |
| T6 migration consistency | T2 |
| T6b live apply/rollback fixture | T2, T6 |
| T7 contract wiring | T6, T6b |
| T-dogfood gate fires on self | T7 (hook + REVIEWS.md must coexist) |
| T8 VERIFICATION.md | T1, T4, T5, T6, T6b, T7, T-dogfood |

Wave 1 (parallel): T1, T2.
Wave 2: T3.
Wave 3 (parallel): T4, T6.
Wave 4: T6b (depends on T6 confirmation).
Wave 5 (parallel): T5, T7.
Wave 6: T-dogfood.
Wave 7: T8.

---

## Out-of-band commitments (per CONTEXT.md)

- **Multi-AI plan review (this phase's gate dogfooding itself):** PLAN.md must be read by ≥2 reviewer CLIs and the output captured in `08-REVIEWS.md` before T1 executes. If reviewer CLIs are unavailable in this environment, `08-REVIEWS.md` records that fact explicitly + recommends a manual deferred review post-merge. Either way, the artifact exists.
- **Stage 1 / Stage 2 / CSO reviews:** post-execution. Required before PR submission. Each gets a section in REVIEW.md (Stage 1, Stage 2) and a dedicated SECURITY.md (CSO).

---

## Risks accepted

- **MultiEdit not in matcher.** ~2% of edits bypass. Tracked as residual risk; future minor patch can add MultiEdit if usage rises.
- **Bash 3.2 compatibility.** Not CI-tested on every commit (no CI yet). Manual macOS bash 3.2.57 run is the proxy.
- **`/gsd-review` slash command is in `templates/gsd-patches/`, not `templates/.claude/`.** The hook checks `~/.claude/get-shit-done/commands/gsd-review.md` (the installed location), but the user must have run `bash ~/.config/gsd-patches/bin/sync` once. Migration pre-flight surfaces this gap.

---

## Definition of done

This phase is done when:
1. All 8 tasks marked complete in TaskList.
2. `migrations/run-tests.sh` PASS for `test_migration_0005()` with 9/9.
3. CHANGELOG `[1.9.1]` section landed.
4. SKILL.md version is `1.9.1`.
5. REVIEW.md has Stage 1 + Stage 2 sections, both APPROVE (or APPROVE-WITH-FLAGS with FLAGs prose-addressed).
6. SECURITY.md from `/cso` recorded — no Critical findings.
7. VERIFICATION.md has 1:1 evidence for AC-1 through AC-10.
8. PR opened, non-draft, targeting main.
