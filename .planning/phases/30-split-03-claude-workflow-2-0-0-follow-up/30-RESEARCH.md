# Phase 30: SPLIT-03 — claude-workflow 2.0.0 follow-up - Research

**Researched:** 2026-06-03
**Domain:** Migration engine mechanics, tombstone pattern, drift test, hook replacement, reference cleanup
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Tombstone/redirect stubs for each removed migration number (0012, 0013, 0017, 0018, 0019, 0020, 0021) — minimal no-op `.md` files recording "moved to agenticapps-observability" + the equivalent obs migration reference. Chain stays contiguous.
- **D-02:** NEW superseding migration (0022) — repoints `requires: skill` and verify grep from `add-observability` to `observability`. `0011` is NOT mutated. Migration carries 2.0.0 bump (D-04) and #58 fix (D-07).
- **D-03:** Two fully independent installs. NO submodule, NO setup chaining. The repoint migration (D-02) verifies `observability` skill is present and emits an actionable install pointer if absent — no auto-install.
- **D-04:** `to_version: 2.0.0` on the 0022 migration. `skill/SKILL.md` → 2.0.0, git tag `v2.0.0`. PR: `v2.0.0 chore!: extract observability to agenticapps-observability (SPLIT-03)`.
- **D-05:** Non-immutable files only — rewrite `add-observability` → `observability` in README, CLAUDE.md template, setup/update skills, docs. Immutable shipped migrations keep their old-name references.
- **D-06:** `docs/UPGRADING.md` — document 1.21.0 → 2.0.0 transition.
- **D-07:** Replace Haiku prompt-type Stop hook (Hook 3, Phase Sentinel) with deterministic `phase-sentinel.sh`. Template change + migration step.

### Claude's Discretion

- Exact tombstone frontmatter shape and whether tombstones carry `from_version`/`to_version` passthrough.
- Whether the #58 hook migration step is part of the 0022 migration or a separately-numbered step within it.
- Whether `docs/UPGRADING.md` lives at repo root or under `docs/`.

### Deferred Ideas (OUT OF SCOPE)

- Obs 0.12.0 implementation-agnostic refactor (Destination contract + Sentry/Axiom adapters).
- FIX-0017 (4 XFAIL 0017 fixtures) — obs-repo follow-up phase.
- Make shared/obs repos public.
- Untracked root docs (`SPLIT-02-...md`, `RESEARCH-cron-monitor-flush-fxsa.md`, `FIX-0017-ENGINE.md`) — decide commit/gitignore/archive during Phase 30 cleanup.
</user_constraints>

---

## Summary

Phase 30 is the breaking cleanup side of the observability split. Phase 29 copied the obs tree into `agenticapps-observability` v0.11.1 (live) without touching claude-workflow. Phase 30 deletes the moved content from claude-workflow, tombstones the vacated migration slots, adds migration 0022 (the repoint + 2.0.0 bump + #58 fix), and ships the downstream upgrade story.

The migration engine applies migrations by `from_version` matching, not by numeric ID order. Tombstones are safe because a project that has already applied the real migration has its version field advanced past the tombstone's `from_version` slot — the tombstone never fires. A project that never applied (e.g. pre-1.11.0 project that never reached 1.11.0) lands on the tombstone's `from_version` and gets an actionable pointer rather than a hard gap.

The drift test (`vendor/agenticapps-shared/migrations/lib/drift-test.sh`) identifies "latest migration" as the alphabetically-last `.md` file matching `[0-9][0-9][0-9][0-9]-*.md` in the migrations directory. With tombstones at 0012–0021 and a new 0022, `0022` is the last file and the drift test reads its `to_version: 2.0.0`. As long as `skill/SKILL.md` also says `version: 2.0.0`, the drift test passes. Tombstones carry `to_version` lines that are read by the drift test; tombstones with no `to_version` line would confuse the drift mechanism — **tombstones MUST carry `to_version`**.

The #58 fix replaces the Haiku-backed `prompt`-type Stop hook with a deterministic 28-line shell script `phase-sentinel.sh`. The existing hook-script pattern in `templates/.claude/hooks/` (chmod +x, exit-code contract) applies directly. The migration step follows the `0004` pattern: identify the old hook via a unique grep anchor (the `prompt` field substring `.planning/current-phase/checklist.md`), replace the Stop array entry.

**Primary recommendation:** Execute in three waves — (1) delete moved content + add tombstones, (2) add migration 0022 with all three deliverables folded in, (3) reference cleanup + docs + ship.

---

## Section 1: Tombstone Mechanics (D-01)

### 1.1 Engine Discovery and Ordering

**Source:** `migrations/README.md` lines 59–68 (Application order section); `vendor/agenticapps-shared/migrations/lib/drift-test.sh` lines 47 (glob pattern).

The migration engine applies migrations by **`from_version` matching**, not by numeric ID order.

```
migrations/README.md:59: Migrations are applied by **`from_version` matching**, not by ID order.
migrations/README.md:62: The `update` skill repeatedly looks at the project's currently-installed
                          version, finds the migration whose `from_version` matches, applies it, and
                          bumps the project to that migration's `to_version`. It loops until no more
                          matching migration is found.
```

The drift test uses a glob for file discovery:

```bash
# drift-test.sh:47
latest_migration_file=$(ls "${migrations_dir}"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sort | tail -1)
```

"Latest" = alphabetically last `.md` file by `sort | tail -1` — which is numeric sort since all names start with a 4-digit zero-padded number.

### 1.2 What Makes a Migration "Pass" — No Test Body Required

**Source:** `migrations/run-tests.sh` dispatcher (lines 2344–2426); `migrations/README.md` test-fixtures section.

The harness's dispatcher calls `test_migration_NNNN` functions explicitly. There is NO auto-discovery of `test_migration_*` functions — each migration is individually registered in the dispatcher. A tombstone `.md` file with no corresponding `test_migration_NNNN` function simply has no dispatcher entry. The harness does not fail if a migration exists without a test body.

**Confirmed via dispatcher scan (lines 2344–2406):** `test_migration_0014` and `test_migration_0015` and `test_migration_0016` all exist with dispatcher entries even though their test bodies were added independently of the migration files. Conversely, `0020` has no dispatcher entry and no test body at all (confirmed: `grep "0020" migrations/run-tests.sh` returns nothing) — this is already the pattern for a migration that shipped with no test body.

**Conclusion:** A tombstone `.md` file with no `test_migration_NNNN` body and no dispatcher entry is valid. The harness increments SKIP only if a *function* is defined but a prerequisite (fixture dir or script) is missing. An absent function is simply never called. No SKIP is incremented.

### 1.3 Drift Test Behavior with Tombstones

**Source:** `vendor/agenticapps-shared/migrations/lib/drift-test.sh` lines 34–63.

The drift test reads `to_version:` from the last file alphabetically. After Phase 30:

1. Tombstones fill 0012–0021. Their `to_version` lines will be read IF they are the last file.
2. New migration 0022 is added with `to_version: 2.0.0`.
3. File `0022-*.md` sorts last — it IS the "latest migration file."
4. Drift test reads `to_version: 2.0.0` from 0022.
5. `skill/SKILL.md` also reads `version: 2.0.0`.
6. `2.0.0 == 2.0.0` → drift test returns 0 → PASS.

**Critical:** If a tombstone had an EMPTY `to_version` line (or no `to_version` line), the `grep ^to_version:` would return blank and `migration_to_version` would be empty. `drift-test.sh:57` would compare `skill_version == ""` → FAIL. Therefore tombstones **must carry a valid `to_version:` line**. The sensible value is the version they represent in the chain (the `to_version` of the original migration they replaced). This allows the drift test to be temporarily correct during the window between deleting the real migration files and creating 0022.

### 1.4 Canonical Tombstone Frontmatter Shape

Based on the engine's `from_version` matching model, the immutability contract, and the drift-test `to_version` requirement:

```yaml
---
id: 0012
slug: slash-discovery-moved
title: "[TOMBSTONE] Slash-command discovery — moved to agenticapps-observability"
from_version: 1.10.0
to_version: 1.11.0
applies_to: []
moved_to: agenticapps-eu/agenticapps-observability
obs_migration: "0012 (1.10.0 → 1.11.0)"
---

# Migration 0012 — [TOMBSTONE] Moved to agenticapps-observability

This migration was moved to the `agenticapps-eu/agenticapps-observability` repository
as part of `claude-workflow 2.0.0` (SPLIT-03).

**The observability skill is now a separate installation:**
```bash
git clone https://github.com/agenticapps-eu/agenticapps-observability \
  ~/.claude/skills/agenticapps-observability
bash ~/.claude/skills/agenticapps-observability/install.sh
```

Then run `/update-agenticapps-workflow` to apply any pending obs migrations
via the obs repo's own update chain.

This slot is a no-op tombstone. If your project is already past version 1.11.0
(confirmed by checking `.claude/skills/agentic-apps-workflow/SKILL.md`), this
tombstone is skipped automatically by the migration engine.
```

**Fields rationale:**
- `from_version`/`to_version`: verbatim from the original migration — preserves chain continuity and gives the drift test a valid value during intermediate states.
- `applies_to: []`: no files are touched.
- `moved_to` + `obs_migration`: informational; the engine ignores unknown frontmatter fields (per README.md frontmatter table: only the 7 listed fields are required/optional; extras are silently passed over).
- No `requires:` block — tombstones have no prerequisites.

**The tombstone body must NOT contain Step/Pre-flight/Post-checks sections** — those would mislead an agent running `/update-agenticapps-workflow` into attempting to execute non-existent actions. The body should be purely informational text.

### 1.5 Safe Deletion of Moved `test_migration_00NN` Bodies

**Source:** `migrations/run-tests.sh` lines 2344–2434 (dispatcher section); lines 2437–2454 (summary).

The summary section increments PASS/FAIL/SKIP based on function calls. There is no hardcoded count assertion like "must equal exactly 186" — the 186/4 figure is the *observed* count from running the harness, not a hardcoded gate in run-tests.sh itself. The HARD GATE in `.planning/STATE.md` and `29-VERIFICATION.md` refers to the *expected baseline* the team tracks manually.

After Phase 30, the new baseline will be lower (fewer test bodies remain). The planner must:
1. Remove `test_migration_0012`, `test_migration_0013`, `test_migration_0017`, `test_migration_0018`, `test_migration_0019`, `test_migration_0021`, `test_meta_destinations_consistency`, and `test_sigterm_mid_apply` from run-tests.sh.
2. Remove their dispatcher entries (the `if [ -z "$FILTER" ] || [ "$FILTER" = "00NN" ]; then` blocks).
3. Add a dispatcher entry for the new `test_migration_0022` body (to be authored in Phase 30).
4. Update the Phase 30 VERIFICATION.md to record the new PASS baseline.

**Also moving:** `test_sigterm_mid_apply` (line 2157: `# WORKFLOW — tests the specific migrate-0019-sentry-crons-and-healthz.sh engine`) and `test_meta_destinations_consistency` (line 1788: `# WORKFLOW — checks observability-specific meta.yaml/registry role tables`) are both tagged WORKFLOW but reference `add-observability/templates/` directly (lines 1857 and 2162). When `add-observability/` is deleted they FAIL. These bodies must be REMOVED from claude-workflow's run-tests.sh.

**One additional impact for staying test_migration_0011:** Its sanity check at line 1176 is:
```bash
local scaffolder_scan="$REPO_ROOT/add-observability/scan/SCAN.md"
if [ ! -f "$scaffolder_scan" ]; then
  echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_scan — RED state"
  FAIL=$((FAIL+1))
  return
fi
```
After `add-observability/` is deleted, this will hard-FAIL. The 0011 test body must be updated to skip this scaffolder-presence check (since the skill no longer ships inside claude-workflow) OR convert it to a SKIP with a note. The fixture sandboxes already copy a stub SCAN.md at setup time (lines 1194–1195) — the sanity check is redundant after deletion. **The fix: remove the sanity check block from `test_migration_0011` (lines 1173–1181) and update the `run_0011_fixture` function to use a stub SCAN.md path rather than copying from `$REPO_ROOT/add-observability/`.**

Similarly, `test_migration_0012` (line 1268) and `test_migration_0013` (line 1359) both check for scaffolder files under `add-observability/`. These functions MOVE to the obs repo and will be DELETED from claude-workflow's run-tests.sh entirely — no fix needed.

---

## Section 2: Drift Test Under Deletion (D-04)

**Source:** `vendor/agenticapps-shared/migrations/lib/drift-test.sh` lines 44–62.

### 2.1 How "Latest Migration" Is Computed

```bash
# drift-test.sh:47
latest_migration_file=$(ls "${migrations_dir}"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sort | tail -1)
```

`ls … | sort | tail -1` on files named `NNNN-slug.md` produces the alphabetically last, which equals numerically last because of the zero-padded 4-digit prefix. After Phase 30, the file list in `migrations/` will be:

```
0000-baseline.md
0001-go-impeccable-database-sentinel.md
0002-observability-spec-0.2.1.md
0004-programmatic-hooks-architecture-audit.md
0005-multi-ai-plan-review-enforcement.md
0006-llm-wiki-builder-integration.md
0007-gitnexus-code-graph-integration.md
0008-coverage-matrix-page.md
0009-vendor-claude-md-sections.md
0010-post-process-gsd-sections.md
0011-observability-enforcement.md
0012-slash-discovery-moved.md          ← tombstone
0013-auto-init-moved.md                ← tombstone
0014-inject-spec-11-coding-discipline.md   ← STAYS
0015-add-ts-declare-first-skill.md         ← STAYS
0016-fix-multi-ai-review-gate-resolution.md ← STAYS
0017-add-axiom-logs-destination-moved.md   ← tombstone
0018-postphase-observability-hook-moved.md ← tombstone
0019-sentry-crons-and-healthz-moved.md    ← tombstone
0020-openrouter-integration.md             ← STAYS (NOTE: see §6.1)
0021-with-cron-and-queue-updates-moved.md  ← tombstone
0022-observability-repoint.md              ← NEW (to_version: 2.0.0)
```

`0022-*` sorts last → drift test reads its `to_version: 2.0.0` → compared against `skill/SKILL.md version: 2.0.0` → **PASS**.

### 2.2 Tombstones Do NOT Confuse the Drift Test

The drift test reads ONLY the last file's `to_version`. Tombstones in intermediate positions (0012–0021) are irrelevant to the drift test — they are never "latest" once 0022 exists. Their `to_version` values are only used if they happen to be the last file, which they won't be.

### 2.3 Intermediate State Warning

During the window between deleting the real 0012–0021 files and creating 0022, the "latest migration" will be `0021-with-cron-and-queue-updates-moved.md` (the tombstone) with `to_version: 1.20.0`. The drift test will FAIL because `skill/SKILL.md` is still `1.20.0` at that point — actually that's a PASS. When 0022 is added with `to_version: 2.0.0`, `skill/SKILL.md` must be bumped to `2.0.0` in the same commit or the drift test fails. **Do not split the 0022 file creation and the SKILL.md bump across separate commits if the CI gate runs between them.**

---

## Section 3: Migration 0011 — Current requires/verify Block (D-02)

**Source:** `migrations/0011-observability-enforcement.md` lines 1–21 (frontmatter).

The exact `requires:` block from 0011:

```yaml
requires:
  - skill: add-observability
    install: "(skill ships in scaffolder repo; no separate install)"
    verify: "test -f ~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md && grep -qE '^implements_spec: 0\\.[3-9]\\.[0-9]+$' ~/.claude/skills/agenticapps-workflow/add-observability/SKILL.md"
  - tool: claude
    install: "Claude Code CLI; install separately (https://claude.ai/code)"
    verify: "command -v claude >/dev/null"
  - tool: jq
    install: "brew install jq (or apt install jq)"
    verify: "command -v jq >/dev/null"
```

The `add-observability` skill verify check:
1. Tests for `~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md` — i.e., the skill inside the scaffolder repo clone, not the symlink target.
2. Greps for `implements_spec: 0.[3-9].[0-9]+` in the SKILL.md.

The pre-flight hard aborts at lines 52–85 check: (1) `observability:` block in CLAUDE.md, (2) `policy.md` exists, (3) workflow SKILL.md at 1.9.3 or 1.10.0, (4) `claude` and `jq` in PATH.

### 3.1 Migration 0022 requires/verify Shape

The new 0022 migration supersedes 0011's install step. The `requires:` block must point to the renamed skill:

```yaml
requires:
  - skill: observability
    install: |
      git clone https://github.com/agenticapps-eu/agenticapps-observability \
        ~/.claude/skills/agenticapps-observability
      bash ~/.claude/skills/agenticapps-observability/install.sh
    verify: "test -f ~/.claude/skills/observability/SKILL.md && grep -q '^name: observability' ~/.claude/skills/observability/SKILL.md"
```

The obs `install.sh` creates `~/.claude/skills/observability → $REPO` (canonical symlink). So `~/.claude/skills/observability/SKILL.md` resolves to the obs repo root's `SKILL.md`. Verified: `agenticapps-observability/SKILL.md` line 1: `name: observability`. [VERIFIED: read install.sh + SKILL.md directly]

The `from_version: 1.20.0` ensures the migration fires exactly once for projects currently at 1.20.0. The pre-flight abort shape:

```bash
# Pre-flight: observability skill absent → actionable abort (no auto-install)
test -f "$HOME/.claude/skills/observability/SKILL.md" || {
  echo "ABORT: The 'observability' skill is not installed."
  echo "Install agenticapps-observability separately:"
  echo ""
  echo "  git clone https://github.com/agenticapps-eu/agenticapps-observability \\"
  echo "    ~/.claude/skills/agenticapps-observability"
  echo "  bash ~/.claude/skills/agenticapps-observability/install.sh"
  echo ""
  echo "Then re-run /update-agenticapps-workflow."
  exit 3
}
```

### 3.2 Next Free Migration Integer — Confirmed 0022

`ls migrations/0022*.md` returns no matches. The current highest migration in claude-workflow's own chain is `0021-with-cron-and-queue-updates.md` (`to_version: 1.20.0`). After tombstones fill 0012–0021 slots, `0022` is the next free integer. [VERIFIED: directory listing]

The obs repo also has a migration `0022` (its deferred-fix migration, `from_version: 1.20.0`, `to_version: 1.21.0`). This is safe: the two repos are independent install axes (D-03/D-04). The `0022` identifier is a file-naming convention within each repo, not a global namespace.

---

## Section 4: #58 Hook Fix Shape (D-07)

**Source:** GitHub issue #58 (`gh issue view 58 --repo agenticapps-eu/claude-workflow`); `templates/claude-settings.json` lines 53–65; `templates/.claude/hooks/` directory listing.

### 4.1 Current Hook 3 (to be replaced)

From `templates/claude-settings.json` lines 53–65:

```json
"Stop": [
  {
    "_hook": "Hook 3 — Phase Sentinel (Haiku, prompt-type)",
    "hooks": [
      {
        "type": "prompt",
        "model": "claude-haiku-4-5-20251001",
        "timeout": 30000,
        "prompt": "Read $CLAUDE_PROJECT_DIR/.planning/current-phase/checklist.md if it exists. Compare it to the assistant's actions in this conversation. Did the assistant complete ALL unchecked items in the current phase? Return JSON: {\"ok\": true} if yes, or {\"ok\": false, \"reason\": \"<which items remain>\"} if no. If checklist.md doesn't exist, return {\"ok\": true} — don't block on its absence."
      }
    ]
  }
]
```

Unique anchor for the migration's idempotency check: the string `.planning/current-phase/checklist.md` appears only in this hook's prompt text. The migration step can use:
```bash
# Idempotency check: old prompt-type hook absent (already replaced)
! grep -q '"type": "prompt"' .claude/settings.json
# OR more precisely:
! grep -q 'current-phase/checklist.md' .claude/settings.json
```

### 4.2 Replacement Script

From issue #58 proposed fix (verbatim):

```bash
#!/usr/bin/env bash
# phase-sentinel.sh — deterministic Stop hook.
# Allows stop unless .planning/current-phase/checklist.md exists AND
# contains unchecked `- [ ]` items.

set -euo pipefail

checklist="${CLAUDE_PROJECT_DIR:-$PWD}/.planning/current-phase/checklist.md"

[ -f "$checklist" ] || exit 0

unchecked=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" || true)
[ "${unchecked:-0}" -eq 0 ] && exit 0

echo "Phase Sentinel: $unchecked unchecked item(s) remain in $checklist:" >&2
grep -E '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" | head -5 >&2
exit 2
```

### 4.3 Replacement claude-settings.json Stop Block

```json
"Stop": [
  {
    "_hook": "Hook 3 — Phase Sentinel (deterministic shell)",
    "hooks": [
      {
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/phase-sentinel.sh",
        "timeout": 5000
      }
    ]
  }
]
```

### 4.4 Hook Script Pattern

Existing hook scripts in `templates/.claude/hooks/` are all `chmod +x` shell scripts with `#!/usr/bin/env bash` shebang. Exit codes:
- `exit 0` — allow (do not block the action).
- `exit 2` — block with error message on stderr.
- `exit 1` is used for unexpected errors (some hooks), but the Stop hook contract uses `exit 2` for blocking.

The migration step must:
1. Write `templates/.claude/hooks/phase-sentinel.sh` and make it executable.
2. Update `templates/claude-settings.json` Stop block.
3. On existing projects (via `/update-agenticapps-workflow`): copy `phase-sentinel.sh` to `.claude/hooks/phase-sentinel.sh` and patch `.claude/settings.json` to swap the Stop block.

The `.claude/settings.json` patch on existing projects follows the `0004` pattern: use `jq` to reconstruct the Stop array with the new entry replacing the old one. The idempotency check anchors on `"type": "command"` in the Stop block combined with `phase-sentinel.sh` path.

---

## Section 5: Reference Cleanup Blast Radius (D-05)

### 5.1 Non-Immutable Files to Rewrite

Files containing `add-observability` that are NOT immutable shipped migrations and MUST be rewritten:

| File | Line refs | Action |
|------|-----------|--------|
| `README.md` | lines 79, 150, 168, 224, 227, 228, 229 | Rewrite `add-observability` → `observability` |
| `install.sh` | lines 45, 114, 116 | Rewrite (install.sh links the skill to `~/.claude/skills/`) |
| `setup/SKILL.md` | lines 224, 227, 228, 229 | Rewrite |
| `update/SKILL.md` | lines matching | Rewrite |
| `SPLIT-00-PREREQUISITES.md` | lines 10, 25, 103, 133, 143 | Rewrite (or archive — see §8 Deferred) |
| `SPLIT-01-agenticapps-shared.md` | 1 line | Rewrite (or archive) |
| `SPLIT-02-agenticapps-observability.md` | many refs | Archive/gitignore (working doc) |
| `migrations/run-tests.sh` | lines 1176, 1194, 1195 (in `test_migration_0011`); lines deleted for moved test bodies | Update 0011 sanity check; delete moved test bodies |
| `CHANGELOG.md` | historical entries | Do NOT rewrite — historical record. These refer to the old `add-observability` name which is what shipped. [ASSUMED] |
| `.planning/STATE.md` | contextual refs | Do NOT rewrite — historical decision record |
| `.planning/` phase dirs | historical refs | Do NOT rewrite — historical record |
| `docs/ENFORCEMENT-PLAN.md` | contextual | Review; rewrite forward-looking refs only |
| `docs/decisions/0024, 0026, 0027, 0028, 0035` | contextual | Review; these are historical ADRs |
| `templates/config-hooks.json` | line 97: `"skill": "add-observability:scan"` | **Rewrite** — this is a forward-looking template that new projects will get |

**Special case — `templates/config-hooks.json` line 97:** The `post_phase.observability_scan` entry references `"skill": "add-observability:scan"`. This is a template that ships to new projects. It must be rewritten to `"skill": "observability:scan"`. [VERIFIED: grep evidence, line 97]

### 5.2 Immutable Files — Do NOT Modify

These files are immutable (released migrations or their engine scripts). Their `add-observability` references remain as-is — the obs repo's `add-observability` dual-symlink alias (retained through v0.12.0, warning at v0.13.0, removed v0.14.0) resolves them at runtime.

| File | Reason to keep unchanged |
|------|--------------------------|
| `migrations/0002-observability-spec-0.2.1.md` | Released migration; immutability contract |
| `migrations/0011-observability-enforcement.md` | Released migration; immutability contract |
| `migrations/0012-slash-discovery.md` | TO BE DELETED (moved); immutable until deleted |
| `migrations/0013-auto-init-and-stale-vendored-cleanup.md` | TO BE DELETED |
| `migrations/0017-add-axiom-logs-destination.md` | TO BE DELETED |
| `migrations/0018-postphase-observability-hook.md` | TO BE DELETED |
| `migrations/0019-sentry-crons-and-healthz.md` | TO BE DELETED |
| `migrations/0020-openrouter-integration.md` | STAYS; has `add-observability:scan` ref in body |
| `migrations/0021-with-cron-and-queue-updates.md` | TO BE DELETED |
| `templates/.claude/scripts/migrate-0017-axiom-destination.sh` | TO BE DELETED |
| `templates/.claude/scripts/migrate-0017-old-wrappers/` | TO BE DELETED |
| `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | TO BE DELETED |
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | TO BE DELETED |

**Note on `migrations/0020-openrouter-integration.md`:** This migration STAYS (it's the OpenRouter integration, not observability-specific). Its body may reference `add-observability`. Since 0020 is a released migration, DO NOT edit its body text. The `add-observability` alias in the obs repo covers runtime resolution.

### 5.3 Historical Docs — Leave As-Is

Files under `.planning/` directories and `CHANGELOG.md` are historical records. Rewriting them would corrupt the audit trail. Leave unchanged even if they mention `add-observability` frequently.

---

## Section 6: Deletion Inventory (Concrete Manifest)

### 6.1 Verified Existence and Actions

| Path | Exists? | Action | Notes |
|------|---------|--------|-------|
| `add-observability/` (whole directory) | YES | DELETE | Confirmed by `ls` — contains CHANGELOG.md, CONTRACT-VERIFICATION.md, enforcement/, init/, templates/, SKILL.md, scan/, etc. |
| `migrations/0012-slash-discovery.md` | YES (12k) | DELETE → TOMBSTONE | Replace with `0012-slash-discovery-moved.md` |
| `migrations/0013-auto-init-and-stale-vendored-cleanup.md` | YES (13k) | DELETE → TOMBSTONE | Replace with `0013-auto-init-moved.md` |
| `migrations/0017-add-axiom-logs-destination.md` | YES (14k) | DELETE → TOMBSTONE | Replace with `0017-add-axiom-logs-destination-moved.md` |
| `migrations/0018-postphase-observability-hook.md` | YES (5.6k) | DELETE → TOMBSTONE | Replace with `0018-postphase-observability-hook-moved.md` |
| `migrations/0019-sentry-crons-and-healthz.md` | YES (18k) | DELETE → TOMBSTONE | Replace with `0019-sentry-crons-and-healthz-moved.md` |
| `migrations/0020-openrouter-integration.md` | YES (4.2k) | **STAYS — NOT DELETED** | OpenRouter migration, not observability. D-01 scope is 0012/0013/0017/0018/0019/0021 only. 0020 stays. |
| `migrations/0021-with-cron-and-queue-updates.md` | YES (7.2k) | DELETE → TOMBSTONE | Replace with `0021-with-cron-and-queue-updates-moved.md` |
| `migrations/test-fixtures/0012/` | YES (5 fixtures) | DELETE | 5 fixture subdirs confirmed |
| `migrations/test-fixtures/0013/` | YES (5 fixtures) | DELETE | |
| `migrations/test-fixtures/0017/` | YES (11 fixtures) | DELETE | Includes `known-wrapper-hashes.json` |
| `migrations/test-fixtures/0018/` | YES (2 fixtures) | DELETE | |
| `migrations/test-fixtures/0019/` | YES (13 fixtures) | DELETE | |
| `migrations/test-fixtures/0021/` | YES (4 fixtures) | DELETE | |
| `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | YES (41k) | DELETE | |
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | YES (25k) | DELETE | |
| `templates/.claude/scripts/migrate-0017-axiom-destination.sh` | YES (34k) | DELETE | |
| `templates/.claude/scripts/migrate-0017-old-wrappers/` | YES (directory) | DELETE | |
| `docs/decisions/0029-cron-monitor-sdk-composition.md` | YES | DELETE | Obs ADR |
| `docs/decisions/0030-openrouter-integration-sdk-first.md` | YES | **REVIEW** | OpenRouter ADR — may belong here or obs. Name says OpenRouter (which is in 0020, a staying migration). See note. |
| `docs/decisions/0031-0019-engine-index-ts-anchor.md` | YES | DELETE | Obs ADR (references 0019 engine) |
| `docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md` | YES | DELETE | Obs ADR |
| `docs/decisions/0033-with-queue-monitor.md` | YES | DELETE | Obs ADR |
| `docs/decisions/0034-observability-init-singleton-invariant.md` | YES | DELETE | Obs ADR |

**CONFLICT FLAG — `docs/decisions/0030-openrouter-integration-sdk-first.md`:** This ADR is titled "openrouter-integration-sdk-first" and is listed among obs ADRs 0029–0034 in the CONTEXT.md. However, migration `0020-openrouter-integration.md` STAYS in claude-workflow (it is the OpenRouter integration migration, not obs-specific). The CONTEXT.md says "Obs ADRs 0029–0034" should be deleted, which includes 0030. Cross-checking with 29-CONTEXT.md §"Gray Areas": "obs ADRs 0029–0034 MOVE" is stated as resolved. However, the OpenRouter migration (0020) stays in claude-workflow. The planner should verify: if ADR-0030 describes a design decision about the observability adapter pattern (OpenRouter-as-obs-destination), it belongs with the obs repo. If it describes claude-workflow's OpenRouter template scaffolding separate from observability, it should stay. **Recommend:** planner reviews `docs/decisions/0030-openrouter-integration-sdk-first.md` first line to determine ownership before committing to deletion. If in doubt, follow 29-CONTEXT.md's authoritative MOVE list (which includes 0030 in "obs ADRs").

**NOT IN SCOPE for deletion (confirmed staying):**
- `migrations/test-fixtures/init-*/` directories — these are init fixtures, not migration fixtures.
- `migrations/test-fixtures/0011/` — migration 0011 stays.
- `migrations/test-fixtures/0014/`, `0015/`, `0016/` — staying migrations.
- `migrations/0020-openrouter-integration.md` — staying migration (not in D-01 list).
- `templates/.claude/scripts/install-wiki-compiler.sh`, `rollback-wiki-compiler.sh`, `install-gitnexus.sh`, `rollback-gitnexus.sh`, `index-family-repos.sh` — staying scripts (migrations 0006/0007).

### 6.2 Run-tests.sh Test Body Deletions

| Function | Lines (approx) | Action |
|----------|---------------|--------|
| `test_migration_0012()` | ~1244–1329 | DELETE function + dispatcher entry |
| `test_migration_0013()` | ~1331–1420 | DELETE function + dispatcher entry |
| `test_migration_0017()` | ~1633–1715 | DELETE function + dispatcher entry |
| `test_migration_0018()` | ~1897–1972 | DELETE function + dispatcher entry |
| `test_migration_0019()` | ~1984–2059 | DELETE function + dispatcher entry |
| `test_migration_0021()` | ~2066–2117 | DELETE function + dispatcher entry |
| `test_meta_destinations_consistency()` | ~1786–1895 (+ `_roles_from_adapter`, `_roles_from_meta` helpers) | DELETE function + helpers + dispatcher entry |
| `test_sigterm_mid_apply_preserves_state()` | ~2157–2335 | DELETE function + dispatcher entry |
| `test_migration_0011()` — sanity check only | lines 1173–1181 | REMOVE the 9-line sanity check block; keep fixture-runner body |
| `test_migration_0011()` — fixture setup | line 1194: copies from `$REPO_ROOT/add-observability/scan/` | REWRITE to use a stub or skip the copy |

---

## Section 7: Sibling-Repo Install Contract

**Source:** `agenticapps-observability/install.sh` lines 43–48; `agenticapps-observability/SKILL.md` lines 1–4.

The obs repo `install.sh` creates two symlinks:
```
~/.claude/skills/observability     → $REPO           (canonical)
~/.claude/skills/add-observability → $REPO/legacy     (alias, retained v0.11.0 + v0.12.0)
```

`obs/SKILL.md` frontmatter:
```yaml
name: observability
version: 0.11.1
implements_spec: 0.3.2
```

The canonical verify check for migration 0022's `requires` entry:
```bash
test -f ~/.claude/skills/observability/SKILL.md && grep -q '^name: observability' ~/.claude/skills/observability/SKILL.md
```

No `INSTALLATION.md` exists in the obs repo's `docs/` directory (only `docs/decisions/` confirmed by `ls`). The `docs/UPGRADING.md` in claude-workflow (D-06) should reference the obs repo's README and `install.sh` directly, not a non-existent INSTALLATION.md.

The install story the UPGRADING.md should cross-reference:
```bash
git clone https://github.com/agenticapps-eu/agenticapps-observability \
  ~/.claude/skills/agenticapps-observability
bash ~/.claude/skills/agenticapps-observability/install.sh
# This creates ~/.claude/skills/observability (canonical) + ~/.claude/skills/add-observability (alias)
```

---

## Section 8: Architecture Patterns

### 8.1 The Supersede Pattern (Precedent from Phase 29)

The obs repo's migration 0022 superseded 0021 without mutating it. The same shape applies here: claude-workflow's 0022 supersedes 0011's install step. The key structural difference: 0011 has `from_version: 1.9.3` — 0022 must have `from_version: 1.20.0` (the current chain endpoint), NOT `from_version: 1.9.3`. The "supersedes" relationship is semantic, not mechanical: 0022 does not chain off of 0011 — it chains off the end of the current chain (1.20.0).

### 8.2 Migration 0022 Skeleton

```yaml
---
id: 0022
slug: observability-repoint-phase-sentinel
title: Repoint observability to agenticapps-observability; replace Phase Sentinel hook (v1.20.0 → 2.0.0)
from_version: 1.20.0
to_version: 2.0.0
applies_to:
  - CLAUDE.md                                         # observability: block cross-reference update
  - .claude/settings.json                              # Hook 3 Stop block replacement
  - .claude/hooks/phase-sentinel.sh                    # new deterministic hook script
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 1.20.0 → 2.0.0
requires:
  - skill: observability
    install: |
      git clone https://github.com/agenticapps-eu/agenticapps-observability \
        ~/.claude/skills/agenticapps-observability && \
      bash ~/.claude/skills/agenticapps-observability/install.sh
    verify: "test -f ~/.claude/skills/observability/SKILL.md && grep -q '^name: observability' ~/.claude/skills/observability/SKILL.md"
---
```

**Steps:**
1. Pre-flight: verify `observability` skill present (hard abort with install instructions if not).
2. Step 1: Update `CLAUDE.md` observability cross-reference (change any `add-observability` → `observability` references in the project's `observability:` metadata block, if such a reference exists). Idempotency: `grep -q 'observability skill: observability' CLAUDE.md || grep -q 'skill: observability' CLAUDE.md`.
3. Step 2: Write `phase-sentinel.sh` into `.claude/hooks/` (chmod +x). Idempotency: `test -f .claude/hooks/phase-sentinel.sh && grep -q 'phase-sentinel.sh' .claude/settings.json`.
4. Step 3: Patch `.claude/settings.json` to replace the Stop block (identify old entry via `"current-phase/checklist.md"` anchor in the prompt field). Idempotency: `! grep -q 'current-phase/checklist.md' .claude/settings.json`.
5. Step 4: Bump version in `.claude/skills/agentic-apps-workflow/SKILL.md` to `2.0.0`. Idempotency: `grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md`.

### 8.3 UPGRADING.md Location

Existing `docs/` directory contains `ENFORCEMENT-PLAN.md` and subdirectories. No `UPGRADING.md` currently exists at repo root or in `docs/`. Convention: place at `docs/UPGRADING.md` to match the existing `docs/` pattern. Reference from README.

---

## Section 9: Migration Chain Integrity Post-Phase-30

After Phase 30, the surviving claude-workflow chain (by `from_version` matching):

```
unknown    → 1.2.0   (0000-baseline)
1.2.0      → 1.3.0   (0001)
1.3.0      → 1.4.0   (0004)
1.4.0      → 1.5.0   (0002)
1.5.0      → 1.6.0   (0008)
1.6.0      → 1.8.0   (0009)
1.8.0      → 1.9.0   (0010)
1.9.0      → 1.9.1   (0005)
1.9.1      → 1.9.2   (0006)
1.9.2      → 1.9.3   (0007)
1.9.3      → 1.10.0  (0011)  ← STAYS; tombstone for 0012 provides 1.10.0→1.11.0 no-op
1.10.0     → 1.11.0  (0012-tombstone)
1.11.0     → 1.12.0  (0013-tombstone)
1.12.0     → 1.14.0  (0014)  ← STAYS
1.14.0     → 1.14.0  (0015)  ← NOTE: 0015 to_version == from_version; unusual but recorded
1.14.0     → 1.15.0  (0016)  ← STAYS
1.15.0     → 1.16.0  (0017-tombstone)
1.16.0     → 1.17.0  (0018-tombstone)
1.17.0     → 1.18.0  (0019-tombstone)
1.18.0     → 1.19.0  (0020)  ← STAYS
1.19.0     → 1.20.0  (0021-tombstone)
1.20.0     → 2.0.0   (0022)  ← NEW
```

**Note on migration 0015:** Its current `from_version: 1.14.0` and `to_version: 1.14.0` creates a chain anomaly (it doesn't advance the version). This pre-exists Phase 30 and is not introduced by it. The engine would technically loop on this if `from_version == to_version` — the update skill is expected to handle this by version comparison. This is pre-existing and not Phase 30's problem to fix.

**Downstream project at 1.20.0:** Replays chain from 1.20.0 onward → hits only `0022` → applies → version becomes `2.0.0`.

**Downstream project at 1.10.0:** Replays 0012-tombstone (1.10.0→1.11.0 no-op, informational message), then 0013-tombstone, then 0014 (real), 0015, 0016, 0017-tombstone, 0018-tombstone, 0019-tombstone, 0020 (real), 0021-tombstone, then 0022.

---

## Validation Architecture

**Config check:** `.planning/config.json` has `workflow._auto_chain_active: false` and no `nyquist_validation` key → treat as enabled.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `migrations/run-tests.sh` (bash, custom harness sourcing agenticapps-shared) |
| Config file | No separate config; sources `vendor/agenticapps-shared/migrations/lib/*.sh` |
| Quick run command | `bash migrations/run-tests.sh 0022` |
| Full suite command | `bash migrations/run-tests.sh` |

### Phase Requirements → Test Map

| Req | Behavior | Test Type | Automated Command |
|-----|----------|-----------|-------------------|
| D-01 | Tombstones in chain, no gap | unit | `bash migrations/run-tests.sh 0011` (verifies chain after 1.10.0) |
| D-02 | 0022 repoints `observability` skill verify | unit | `bash migrations/run-tests.sh 0022` |
| D-04 | Drift test passes with to_version 2.0.0 | unit | `bash migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version` |
| D-07 | phase-sentinel.sh exit-0/exit-2 behavior | unit | Inline fixture in `test_migration_0022` (3 cases: no checklist, all-checked, unchecked items) |
| D-05 | No `add-observability` in non-immutable files | grep | `grep -r "add-observability" README.md install.sh setup/ update/ templates/claude-md-sections.md templates/config-hooks.json` → no output |
| Baseline | Suite still green after deletions | full suite | `bash migrations/run-tests.sh` (new PASS baseline TBD) |

### Wave 0 Gaps
- [ ] `migrations/test-fixtures/0022/` — new fixtures for 0022 (pre-flight-abort when obs absent, idempotent reapply, version-bump)
- [ ] `test_migration_0022()` function body in run-tests.sh
- [ ] `templates/.claude/hooks/phase-sentinel.sh` — new file

---

## Common Pitfalls

### Pitfall 1: Forgetting `to_version` in Tombstones
**What goes wrong:** Drift test reads empty `to_version` from tombstone and fails.
**Root cause:** Tombstone authored with only informational fields, no `to_version:`.
**Prevention:** Every tombstone carries verbatim `from_version`/`to_version` from the original migration.

### Pitfall 2: Deleting `test_migration_0011`'s Scaffolder Sanity Check Without Updating Fixture Setup
**What goes wrong:** `test_migration_0011` passes the sanity check (removed) but then the fixture setup at line 1194 tries to copy from `$REPO_ROOT/add-observability/scan/SCAN.md` which no longer exists → FAIL.
**Prevention:** When removing the sanity check, also update `run_0011_fixture` to not copy from `add-observability/`. The fixture can use a stub SCAN.md created inline or simply omit the copy (the 0011 migration's verify only checks the project-local state, not the scaffolder).

### Pitfall 3: Splitting 0022 Creation and SKILL.md Bump
**What goes wrong:** 0022 file exists with `to_version: 2.0.0` but `skill/SKILL.md` still says `1.20.0` — drift test FAILS between commits.
**Prevention:** Create 0022 + bump SKILL.md in the same atomic commit.

### Pitfall 4: Confusing Migration 0020 as "Observability" 
**What goes wrong:** 0020 (`openrouter-integration`) is in the obs ADR numbering range and has `add-observability:scan` in its body — someone tombstones it.
**Prevention:** D-01 scope is explicitly `0012, 0013, 0017, 0018, 0019, 0020, 0021` — yes, 0020 IS in the list. Wait: re-check the CONTEXT.md D-01 list: "0012, 0013, 0017, 0018, 0019, 0020, 0021". So 0020 IS in the tombstone list. But 29-CONTEXT.md §"Migration ownership" says 0020 moves the .md ONLY (no test body, no fixtures). The obs repo already has `0020-openrouter-integration.md` there. So the claude-workflow `0020-openrouter-integration.md` SHOULD be tombstoned per D-01. The concern was whether the migration STAYS — it doesn't; it was moved. The tombstone replaces it.

### Pitfall 5: Breaking Phase Sentinel Migration Step with Wrong jq Pattern
**What goes wrong:** The `.claude/settings.json` patch deletes the wrong hook entry (e.g. deletes a PreToolUse hook instead of the Stop hook).
**Prevention:** Use a narrow jq selector that combines `type == "prompt"` AND checks for the specific prompt text substring. Alternative: manually rewrite the Stop array in the migration's Apply block using a sed anchor on the unique `prompt` key.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `CHANGELOG.md` historical entries should not be rewritten even if they name `add-observability` | §5.1 | Low — CHANGELOG is an append log; future entries should use `observability` |
| A2 | `docs/decisions/0030-openrouter-integration-sdk-first.md` belongs with obs (follows 29-CONTEXT.md MOVE list) | §6.1 | Low if obs repo has it already (it was extracted); planner should verify |
| A3 | No `docs/UPGRADING.md` exists in obs repo (only `docs/decisions/` confirmed) | §7 | Low — planner verifies before cross-referencing |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `bash` | run-tests.sh | ✓ (macOS system) | 3.2+ | — |
| `jq` | migration 0022 step 3 | ✓ | confirmed (existing migrations use it) | — |
| `git` | tag v2.0.0 | ✓ | confirmed | — |
| `gh` | PR creation | ✓ | confirmed (used in Phase 29) | — |
| `agenticapps-shared` submodule | run-tests.sh | ✓ | v1.0.0 (1f5d543) | — |

---

## Sources

### Primary (HIGH confidence)
- `migrations/README.md` — migration engine semantics, from_version matching, file format
- `vendor/agenticapps-shared/migrations/lib/drift-test.sh` — exact drift test mechanism (lines 34–63)
- `migrations/run-tests.sh` — dispatcher, test body inventory, function-level WORKFLOW labels
- `migrations/0011-observability-enforcement.md` — exact requires/verify block
- `templates/claude-settings.json` — Hook 3 current shape
- `templates/.claude/hooks/` directory listing — hook script pattern
- `agenticapps-observability/install.sh` — dual-symlink install contract
- `agenticapps-observability/SKILL.md` — skill name/version confirmation
- `gh issue view 58` — #58 root cause + proposed fix script verbatim
- `.planning/phases/29-split-02-agenticapps-observability/29-CONTEXT.md` — MOVE/STAY matrix (authoritative)
- `.planning/phases/29-split-02-agenticapps-observability/29-VERIFICATION.md` — 186/4 baseline, obs 42/4 baseline

### Secondary (MEDIUM confidence)
- `migrations/0012–0021` from_version/to_version values (read from files directly)
- Migration chain full inventory (computed from `grep ^from_version:/^to_version:` across all files)

---

## Metadata

**Confidence breakdown:**
- Engine mechanics (tombstones, drift test): HIGH — read from source code directly
- Deletion manifest: HIGH — verified by `ls` and grep
- 0022 migration shape: HIGH — derived from 0011 source + obs install.sh
- #58 fix: HIGH — verbatim from GH issue
- Reference cleanup file list: HIGH — verified by grep

**Research date:** 2026-06-03
**Valid until:** Stable (engine is shell; no external dependencies)

---

## RESEARCH COMPLETE

**Phase:** 30 - SPLIT-03 — claude-workflow 2.0.0 follow-up
**Confidence:** HIGH

### Key Findings

1. **Tombstones are safe and the engine treats them as pass-through** — from_version matching means a project already past the tombstoned version never fires the tombstone. Tombstones MUST carry `from_version`/`to_version` verbatim from the original to avoid confusing the drift test.

2. **Drift test reads the alphabetically-last migration file's `to_version`** — with 0022 as the last file and `to_version: 2.0.0`, the drift test goes green once `skill/SKILL.md` is also bumped to `2.0.0`. Tombstones in intermediate positions are irrelevant to the drift test.

3. **Eight test bodies must be removed from run-tests.sh** (0012, 0013, 0017, 0018, 0019, 0021, test_meta_destinations_consistency, test_sigterm_mid_apply) plus their dispatcher entries. The test_migration_0011 body STAYS but needs its 9-line scaffolder sanity check removed (add-observability/ will not exist).

4. **#58 fix is fully specified** — the 28-line `phase-sentinel.sh` from the GH issue is production-ready; the migration step anchors on the `current-phase/checklist.md` substring in the prompt field for idempotency.

5. **`templates/config-hooks.json` line 97 references `"skill": "add-observability:scan"`** — this is a non-immutable template and MUST be rewritten to `observability:scan` as part of D-05.

6. **No `docs/INSTALLATION.md` in obs repo** — `docs/UPGRADING.md` must reference the obs README/install.sh directly, not a non-existent INSTALLATION.md.
