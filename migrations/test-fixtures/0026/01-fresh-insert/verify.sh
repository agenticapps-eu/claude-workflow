#!/bin/sh
# Replays 0026 Step 1 + Step 2 + Step 3 exactly (engine copied from the snapshot
# — $REPO_ROOT stands in for the scaffolder clone — PostToolUse Bash entry wired,
# version bumped) and asserts a surgical insert: the pre-existing PostToolUse
# entry survives and exactly one gitnexus-reindex entry is added.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

ENGINE_SRC="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
test -f "$ENGINE_SRC" || { echo "PRE: snapshot engine missing at $ENGINE_SRC"; exit 1; }

# Pre-conditions:
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.3.0 before apply"; exit 1; }
jq -e '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length == 0' \
  .claude/settings.json >/dev/null || { echo "PRE: unexpected gitnexus-reindex entry before apply"; exit 1; }
test -e .claude/hooks/gitnexus-reindex.cjs && { echo "PRE: engine present before apply"; exit 1; }

# ── Step 1 (apply) — copy engine from the scaffolder snapshot ────────────────
mkdir -p .claude/hooks
cp "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
test -x .claude/hooks/gitnexus-reindex.cjs || { echo "STEP 1 failed: engine not executable"; exit 1; }
cmp -s "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs \
  || { echo "STEP 1 failed: installed engine differs from snapshot source"; exit 1; }

# ── Step 2 (apply) — wire the PostToolUse Bash entry ────────────────────────
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Exactly one gitnexus-reindex entry, matcher Bash, correct command + timeout
COUNT=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$COUNT" = "1" ] || { echo "STEP 2 failed: expected 1 entry, got $COUNT"; exit 1; }
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .matcher == "Bash"' \
  .claude/settings.json >/dev/null || { echo "STEP 2 failed: matcher != Bash"; exit 1; }
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .hooks[0].timeout == 5000' \
  .claude/settings.json >/dev/null || { echo "STEP 2 failed: timeout != 5000"; exit 1; }
# Surgical: the pre-existing skill-router entry survives
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("skill-router-log"))' \
  .claude/settings.json >/dev/null || { echo "STEP 2 not surgical: pre-existing entry dropped"; exit 1; }

# ── Step 3 (apply) — version bump ────────────────────────────────────────────
sed -i.0026.bak -E 's/^version: 2\.3\.0$/version: 2.4.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 failed: version not bumped to 2.4.0"; exit 1; }

echo "fixture 01 — engine copied (identical), Bash entry wired (surgical), version 2.3.0 -> 2.4.0"
