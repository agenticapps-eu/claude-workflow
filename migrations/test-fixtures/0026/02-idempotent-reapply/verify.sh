#!/bin/sh
# Re-running each step's guarded apply against the applied state is a no-op:
# the engine cmp-matches (Step 1 skipped), the any() guard short-circuits
# (Step 2 no new entry), and the version is already 2.4.0 (Step 3 skipped).
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

ENGINE_SRC="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
before_count=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$before_count" = "1" ] || { echo "PRE: expected exactly 1 entry in applied state, got $before_count"; exit 1; }

# Step 1 idempotency: engine already identical → cmp match → skip
cmp -s "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs \
  || { echo "PRE: applied-state engine differs from snapshot"; exit 1; }

# Step 2 re-apply (guarded) — must NOT add a second entry
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"x"}]}])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
after_count=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$after_count" = "1" ] || { echo "IDEMPOTENCY failed: entry count $before_count -> $after_count"; exit 1; }

# Step 3 idempotency: version already 2.4.0
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.4.0 in applied state"; exit 1; }

echo "fixture 02 — re-apply is a no-op (engine identical, single entry preserved, version steady)"
