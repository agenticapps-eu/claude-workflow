# Materialize the setup snapshot + structural drift guard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #74 — make `migrations/check-snapshot-parity.sh` green, honest, and CI-enforced, so `/setup-agenticapps-workflow` installs a correct snapshot.

**Architecture:** The guard was miscalibrated against factiv's live config (it demanded GSD-owned `.workflow` and a stale `add-observability:scan`). Fix those two assertions; fill the two real gaps (missing `multi-ai-review-gate.sh` binding; template-only keys leaking into the installed shape) at the `templates/` source; rewrite `bin/build-snapshot.sh` as a deterministic assembler (no `apply.sh`); amend ADR-0036 + MANIFEST + `setup/SKILL.md`; add CI. See `docs/superpowers/specs/2026-07-01-materialize-snapshot-drift-guard-design.md`.

**Tech Stack:** bash, `jq`, GitHub Actions YAML. No new dependencies.

---

## File Structure

- Modify: `migrations/check-snapshot-parity.sh` — remove `.workflow` assertion, fix observability assertion (Task 1)
- Modify: `templates/claude-settings.json` — add the multi-ai binding (Task 2)
- Modify: `setup/snapshot/claude-settings.json` — installed shape: binding + no template-only keys (Task 2)
- Rewrite: `bin/build-snapshot.sh` — deterministic assembler, no `apply.sh` (Task 3)
- Modify: `docs/decisions/0036-snapshot-install.md`, `setup/snapshot/MANIFEST.md`, `setup/SKILL.md` (Task 4)
- Create: `.github/workflows/ci.yml` (Task 5)
- Integration + final verification (Task 6)

Baseline before starting: `bash migrations/check-snapshot-parity.sh; echo $?` → **1** (4 FAILs). Keep this terminal handy — the guard is the test harness for Tasks 1–2.

---

### Task 1: Fix the guard's two miscalibrated assertions

**Files:**
- Modify: `migrations/check-snapshot-parity.sh` (the `## ── 3. .planning/config.json` block, ~lines 71–86)

- [ ] **Step 1: Baseline the guard's current failures**

Run: `bash migrations/check-snapshot-parity.sh 2>&1 | grep FAIL`
Expected (4 lines):
```
  FAIL: settings.json does not bind multi-ai-review-gate.sh
  FAIL: settings.json carries template-only key "_comment" ...
  FAIL: settings.json carries template-only key "_enforcement_contract" ...
  FAIL: config missing .workflow block (present in real installs)
  FAIL: config uses stale 'observability:scan' (end-state is 'add-observability:scan')
```
(5 FAIL lines — two are the guard's own bug, fixed here.)

- [ ] **Step 2: Remove the `.workflow` assertion and fix the observability check**

Replace this block in `migrations/check-snapshot-parity.sh`:
```bash
  # End-state invariants confirmed against installed factiv projects:
  jq -e '.workflow' "$CFG" >/dev/null 2>&1 \
    && ok "config has .workflow block" \
    || bad "config missing .workflow block (present in real installs)"
  # observability skill was renamed observability:* -> add-observability:* —
  # the bare old name in the snapshot means it lags the chain.
  if grep -q '"observability:scan"' "$CFG" && ! grep -q '"add-observability:scan"' "$CFG"; then
    bad "config uses stale 'observability:scan' (end-state is 'add-observability:scan')"
  else
    ok "observability skill id is current"
  fi
```
with:
```bash
  # NOTE: `.workflow` is GSD-owned config (research/plan_check/verifier/…),
  # written by GSD at its own init — NOT part of the AgenticApps snapshot, which
  # owns only `.hooks`. Setup merges `.hooks` into any GSD-written config. So we
  # do NOT assert `.workflow` here.
  #
  # Observability skill id: 0022 repointed `add-observability` -> `observability`
  # (the obs repo keeps `add-observability` as an alias). Accept either the
  # current `observability:scan` or the legacy `add-observability:scan`; fail
  # only if the scan ref is absent entirely.
  if grep -q '"observability:scan"' "$CFG" || grep -q '"add-observability:scan"' "$CFG"; then
    ok "observability scan ref present (current or aliased)"
  else
    bad "config missing an observability scan skill ref"
  fi
```

- [ ] **Step 3: Re-run the guard — the two guard-bug FAILs are gone**

Run: `bash migrations/check-snapshot-parity.sh 2>&1 | grep -c FAIL`
Expected: `3` (was 5). The remaining FAILs are the two real gaps (multi-ai binding + the two template-only keys). Confirm `.workflow` and observability no longer appear:
Run: `bash migrations/check-snapshot-parity.sh 2>&1 | grep -E 'workflow|observability'`
Expected: only the `ok:` line `observability scan ref present ...`

- [ ] **Step 4: Commit**

```bash
git add migrations/check-snapshot-parity.sh
git commit -m "fix(parity): drop GSD-owned .workflow assertion; accept current observability:scan (#74)"
```

---

### Task 2: Fill the two real snapshot gaps (multi-ai binding + installed shape)

**Files:**
- Modify: `templates/claude-settings.json` (the source of truth)
- Modify: `setup/snapshot/claude-settings.json` (the installed shape)

- [ ] **Step 1: Confirm the gap — neither file binds the gate; both carry template keys**

Run:
```bash
for f in templates/claude-settings.json setup/snapshot/claude-settings.json; do
  echo "$f: multi-ai=$(grep -c multi-ai-review-gate "$f") keys=$(grep -c '_comment\|_enforcement_contract' "$f")"
done
```
Expected: both show `multi-ai=0 keys=2`.

- [ ] **Step 2: Add the multi-ai-review-gate binding to `templates/claude-settings.json`**

Cross-check the exact shape against migration `0005-multi-ai-plan-review-enforcement.md`'s Apply block; it must match the installed shape verified in cparx: a `PreToolUse` entry. Use `jq` to append it idempotently:
```bash
jq '
  .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
    {
      "_hook": "Hook 6 — Multi-AI Plan Review Gate (/gsd-review)",
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [
        { "type": "command",
          "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/multi-ai-review-gate.sh",
          "timeout": 5000 }
      ]
    }
  ])
' templates/claude-settings.json > templates/claude-settings.json.tmp \
  && mv templates/claude-settings.json.tmp templates/claude-settings.json
```

- [ ] **Step 3: Verify the template is valid JSON and now binds the gate**

Run: `jq -e '.. | .command? // empty' templates/claude-settings.json | grep -c multi-ai-review-gate`
Expected: `1`
Run: `jq empty templates/claude-settings.json && echo VALID`
Expected: `VALID`

- [ ] **Step 4: Derive the snapshot's installed shape (binding + strip template-only keys)**

```bash
jq 'del(._comment, ._enforcement_contract)' templates/claude-settings.json \
  > setup/snapshot/claude-settings.json.tmp \
  && mv setup/snapshot/claude-settings.json.tmp setup/snapshot/claude-settings.json
```

- [ ] **Step 5: Run the guard — expect fully green (exit 0)**

Run: `bash migrations/check-snapshot-parity.sh; echo "exit=$?"`
Expected: no `FAIL:` lines; `exit=0`.

- [ ] **Step 6: Confirm the full test suite still passes**

Run: `bash migrations/run-tests.sh 2>&1 | tail -3`
Expected: `PASS: <N>` with no `FAIL:` in the summary (N ≥ 153).

- [ ] **Step 7: Commit**

```bash
git add templates/claude-settings.json setup/snapshot/claude-settings.json
git commit -m "fix(snapshot): bind multi-ai-review-gate; snapshot is the stripped installed shape (#74)"
```

---

### Task 3: Rewrite `bin/build-snapshot.sh` as a deterministic assembler

**Files:**
- Rewrite: `bin/build-snapshot.sh`

- [ ] **Step 1: Confirm current script references the non-existent apply harness**

Run: `grep -n 'apply.sh' bin/build-snapshot.sh`
Expected: a line invoking `vendor/agenticapps-shared/migrations/lib/apply.sh` (the file that never existed).

- [ ] **Step 2: Replace the script body with a deterministic assembler**

Overwrite `bin/build-snapshot.sh` with:
```bash
#!/usr/bin/env bash
# build-snapshot.sh — regenerate setup/snapshot/ deterministically from the
# maintained sources (templates/ + skill/SKILL.md). The migration chain cannot
# be shell-replayed (prose/agent/AskUserQuestion steps — see ADR-0036 and
# issue #74), so the snapshot is assembled from source, not replayed.
#
#   bash bin/build-snapshot.sh            # rebuild setup/snapshot/ from source
#   bash bin/build-snapshot.sh --check    # assemble to temp + diff, no write
#
# Requires: git, jq. Runs anywhere (no scaffolder/GSD/gstack needed).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="$ROOT/setup/snapshot"
MODE="rebuild"; [ "${1:-}" = "--check" ] && MODE="check"

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }

# Assemble the snapshot into $OUT (either $SNAP for rebuild, or a temp dir).
OUT="$SNAP"
if [ "$MODE" = "check" ]; then OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT; fi

mkdir -p "$OUT/hooks" "$OUT/scripts"

# 1. 1:1 source copies (MANIFEST mapping).
cp "$ROOT/skill/SKILL.md"                              "$OUT/agentic-apps-workflow-SKILL.md"
cp "$ROOT/templates/workflow-config.md"                "$OUT/workflow-config.md"
cp "$ROOT/templates/config-hooks.json"                 "$OUT/planning-config.json"
cp "$ROOT/templates/.claude/claude-md/workflow.md"     "$OUT/claude-md-workflow.md"
cp "$ROOT/templates/adr-db-security-acceptance.md"     "$OUT/adr-db-security-acceptance.md"
cp "$ROOT/templates/global-claude-additions.md"        "$OUT/global-claude-additions.md"
cp "$ROOT"/templates/.claude/hooks/*.sh                "$OUT/hooks/"
cp "$ROOT"/templates/.claude/scripts/*.sh              "$OUT/scripts/"

# 2. claude-settings.json = template minus template-only annotation keys
#    (the installed shape). The multi-ai binding lives in the template already.
jq 'del(._comment, ._enforcement_contract)' \
  "$ROOT/templates/claude-settings.json" > "$OUT/claude-settings.json"

# 3. claude-md-reference-block.md — the block setup appends to CLAUDE.md.
#    Preserved from the committed snapshot (it has no templates/ source file).
[ "$MODE" = "rebuild" ] || cp "$SNAP/claude-md-reference-block.md" "$OUT/claude-md-reference-block.md"

# 4. VERSION stamp from skill/SKILL.md frontmatter.
awk '/^---$/{f++;next} f==1&&/^version:/{print $2;exit}' \
  "$ROOT/skill/SKILL.md" > "$OUT/VERSION"

if [ "$MODE" = "check" ]; then
  # claude-md-reference-block.md is not regenerated; exclude from the diff.
  if diff -ru --exclude=claude-md-reference-block.md --exclude=MANIFEST.md "$SNAP" "$OUT" >/dev/null 2>&1; then
    echo "OK — snapshot matches assembled source."
  else
    echo "DRIFT — setup/snapshot/ differs from assembled source:"
    diff -ru --exclude=claude-md-reference-block.md --exclude=MANIFEST.md "$SNAP" "$OUT" | head -40
    exit 1
  fi
else
  echo "snapshot rebuilt at version $(cat "$SNAP/VERSION")"
fi

# 5. Always end by running the structural drift guard (the authority).
bash "$ROOT/migrations/check-snapshot-parity.sh"
```

- [ ] **Step 3: Make it executable and run `--check` against the just-materialized snapshot**

Run: `chmod +x bin/build-snapshot.sh && bash bin/build-snapshot.sh --check; echo "exit=$?"`
Expected: `OK — snapshot matches assembled source.` then the parity check green; `exit=0`. It must NOT print "shared apply harness not found".

- [ ] **Step 4: Confirm no reference to the non-existent apply harness remains**

Run: `grep -c 'apply.sh' bin/build-snapshot.sh`
Expected: `0`

- [ ] **Step 5: Commit**

```bash
git add bin/build-snapshot.sh
git commit -m "refactor(build-snapshot): deterministic assembler from templates/, drop non-existent apply.sh (#74)"
```

---

### Task 4: Amend the docs

**Files:**
- Modify: `docs/decisions/0036-snapshot-install.md`
- Modify: `setup/snapshot/MANIFEST.md`
- Modify: `setup/SKILL.md`

- [ ] **Step 1: Update ADR-0036 "How the snapshot stays correct"**

In `docs/decisions/0036-snapshot-install.md`, replace the two bullets under
"How the snapshot stays correct" with:
```markdown
- **`bin/build-snapshot.sh`** deterministically assembles `snapshot/` from the
  maintained sources (`templates/` + `skill/SKILL.md`) — a 1:1 copy per the
  MANIFEST mapping, plus a `jq` transform for `claude-settings.json` (strip
  template-only annotation keys). The migration chain is **not** shell-replayed:
  it contains `AskUserQuestion` (0000) and agent-only steps (0023 →
  `/injection-guard init`), so a deterministic `apply.sh` is infeasible (#74).
- **`migrations/check-snapshot-parity.sh`** (CI, every PR) is the authoritative
  guard: structural checks (JSON validity, version stamp, hook bindings, hook
  presence + hashes, feature markers) that need no scaffolder or agent. A
  mismatch fails the build.
```

- [ ] **Step 2: Flip the MANIFEST "seed vs verified" section**

In `setup/snapshot/MANIFEST.md`, replace the "## ⚠️ Seed vs verified" section
body with a "## Verified" note: the snapshot is assembled from source by
`bin/build-snapshot.sh` and enforced by `check-snapshot-parity.sh` in CI; to
regenerate after changing a migration or template, run `bash bin/build-snapshot.sh`
and commit the result. Remove the "not yet verified latest / drift guard will
FAIL" warning.

- [ ] **Step 3: Fix setup Step 4d to MERGE hooks (not overwrite GSD's config)**

In `setup/SKILL.md` Step 4d, replace the "copy `$SNAP/planning-config.json` →
`.planning/config.json`" instruction with a merge: if `.planning/config.json`
already exists (GSD wrote it, incl. its `.workflow` block), merge the snapshot's
`.hooks` into it with `jq -s '.[0] * .[1]'` (snapshot second, so `.hooks` lands)
rather than overwriting; only copy wholesale when no config exists. Add a note:
the snapshot owns only `.hooks`; `.workflow` is GSD-owned.

- [ ] **Step 4: Verify docs reference no non-existent mechanism**

Run: `grep -rn 'apply.sh' docs/decisions/0036-snapshot-install.md setup/snapshot/MANIFEST.md`
Expected: no output (0 matches), or only prose explaining it was rejected.

- [ ] **Step 5: Commit**

```bash
git add docs/decisions/0036-snapshot-install.md setup/snapshot/MANIFEST.md setup/SKILL.md
git commit -m "docs(#74): ADR-0036 + MANIFEST reflect deterministic assembly; setup merges hooks into GSD config"
```

---

### Task 5: CI wiring

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the workflow**

Write `.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  migrations-and-snapshot:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Install jq
        run: sudo apt-get update && sudo apt-get install -y jq
      - name: Migration test suite
        run: bash migrations/run-tests.sh
      - name: Snapshot drift guard
        run: bash migrations/check-snapshot-parity.sh
      - name: Snapshot assembles from source (no drift)
        run: bash bin/build-snapshot.sh --check
```

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK`

- [ ] **Step 3: Locally simulate the three CI commands**

Run:
```bash
bash migrations/run-tests.sh >/tmp/ci1.log 2>&1; echo "run-tests=$?"
bash migrations/check-snapshot-parity.sh >/tmp/ci2.log 2>&1; echo "parity=$?"
bash bin/build-snapshot.sh --check >/tmp/ci3.log 2>&1; echo "build-check=$?"
```
Expected: `run-tests=0` (check `tail -3 /tmp/ci1.log` shows FAIL: 0), `parity=0`, `build-check=0`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci(#74): run migration suite + snapshot drift guard on every PR"
```

---

### Task 6: Integrate the #75 setup guard and final verification

**Files:** none new — integration + verification.

- [ ] **Step 1: Bring in the #75 fail-closed guard**

The #75 guard (`setup/SKILL.md` Step 1 runs `check-snapshot-parity.sh` and
refuses on failure) must be present in the final branch. If PR #75 is already
merged to `main`: `git rebase main`. If not: `git merge --no-ff origin/fix/setup-refuse-unverified-snapshot` (or cherry-pick its commit). Resolve any `setup/SKILL.md` conflict by keeping BOTH the Step 1 guard (#75) and the Step 4d merge change (Task 4). Do not remove the guard.

- [ ] **Step 2: Prove the guard now PASSES (snapshot is green, so setup proceeds)**

Run: `bash migrations/check-snapshot-parity.sh; echo "exit=$?"`
Expected: `exit=0` — so the #75 Step-1 guard no longer refuses; setup can install.

- [ ] **Step 3: Full green sweep**

Run:
```bash
bash migrations/run-tests.sh 2>&1 | tail -2
bash migrations/check-snapshot-parity.sh >/dev/null 2>&1; echo "parity=$?"
bash bin/build-snapshot.sh --check >/dev/null 2>&1; echo "build-check=$?"
```
Expected: suite `PASS: N` / no FAIL; `parity=0`; `build-check=0`.

- [ ] **Step 4: Confirm `detect_changes` is low risk, then push + PR**

```bash
git push -u origin feat/74-materialize-snapshot
gh pr create --base main \
  --title "feat(#74): materialize snapshot + fix drift guard + CI" \
  --body "Closes #74. Fixes the guard's two miscalibrated assertions (GSD-owned .workflow; stale add-observability:scan), fills the two real gaps (multi-ai binding + installed-shape stripping), rewrites build-snapshot.sh as a deterministic assembler (no apply.sh), amends ADR-0036/MANIFEST/setup, wires CI, and retains the #75 setup guard. Verification: run-tests green, parity exit 0, build-snapshot --check exit 0."
```

- [ ] **Step 5: Confirm the PR links and closes #74**

Run: `gh pr view --json body -q .body | grep -i 'Closes #74'`
Expected: the "Closes #74" line.

---

## Notes for the executor

- The guard is your test harness for Tasks 1–2: after each change, `bash migrations/check-snapshot-parity.sh` and watch FAIL count drop 5 → 3 → 0.
- Never let any file reference `vendor/agenticapps-shared/migrations/lib/apply.sh` — it does not exist in any release.
- Keep the change scoped: do NOT add `.workflow` to the snapshot, do NOT rename `observability:scan`, do NOT reshape migrations, do NOT touch the `update` path.
