#!/bin/sh
# Verify migration 0025 idempotency (fixture 03): already applied. All three
# positive anchors hold, so every step reports "already applied" and nothing
# mutates — in particular the section is NOT appended a second time.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

# All positive anchors hold (the migration flow would skip every step)
jq -e 'has("knowledge_capture")' .planning/config.json >/dev/null 2>&1 \
  || { echo "PRE: expected the block in applied state"; exit 1; }
grep -q '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected the section in applied state"; exit 1; }
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version already 2.3.0"; exit 1; }

cfg_before="$(jq -S . .planning/config.json)"

# Replay Step 1 jq (guarded) — must be a no-op
REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
jq --arg note "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/${REPO_NAME}.md" \
  'if has("knowledge_capture") then . else . + {knowledge_capture: {enabled: true, note: $note}} end' \
  .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json
[ "$cfg_before" = "$(jq -S . .planning/config.json)" ] \
  || { echo "STEP 1 not idempotent on applied state"; exit 1; }

# Step 2 anchor is positive -> the migration flow skips the append entirely.
# Guard rail: the section exists exactly once and the file stays intact.
[ "$(grep -c '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md)" = "1" ] \
  || { echo "STEP 2 idempotency wrong: section duplicated"; exit 1; }

# Step 3 replay on 2.3.0 — the sed matches nothing; version unchanged
sed -i.0025.bak -E 's/^version: 2\.2\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 idempotency wrong: version drifted"; exit 1; }

echo "fixture 03 — already at 2.3.0 with block + section; re-run is a clean no-op"
