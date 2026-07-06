#!/bin/sh
# Verify migration 0025 with no .planning/config.json (fixture 04): Step 1
# creates the file containing ONLY the knowledge_capture block (GSD adds its
# own sections at its own init), with the repo name resolved.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

[ -f .planning/config.json ] && { echo "PRE: config.json must be absent"; exit 1; }

# ── Step 1 (apply) — the exact shell from 0025, including file creation ─────
REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
mkdir -p .planning
[ -f .planning/config.json ] || printf '{}\n' > .planning/config.json
jq --arg note "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/${REPO_NAME}.md" \
  'if has("knowledge_capture") then . else . + {knowledge_capture: {enabled: true, note: $note}} end' \
  .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

jq -e . .planning/config.json >/dev/null || { echo "STEP 1 failed: invalid JSON"; exit 1; }
[ "$(jq -r 'keys | join(",")' .planning/config.json)" = "knowledge_capture" ] \
  || { echo "STEP 1 failed: created config must contain only the block"; exit 1; }
EXPECTED_NOTE="~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/$(basename "$(pwd)").md"
[ "$(jq -r '.knowledge_capture.note' .planning/config.json)" = "$EXPECTED_NOTE" ] \
  || { echo "STEP 1 failed: note path not resolved to repo dir name"; exit 1; }

# ── Steps 2 + 3 (apply) — unchanged from the standard path ──────────────────
{
  printf '\n'
  awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$REPO_ROOT/skill/SKILL.md"
} >> .claude/skills/agentic-apps-workflow/SKILL.md
[ "$(grep -c '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md)" = "1" ] \
  || { echo "STEP 2 failed: section not appended exactly once"; exit 1; }

sed -i.0025.bak -E 's/^version: 2\.2\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 failed: version not bumped to 2.3.0"; exit 1; }

echo "fixture 04 — config created with only the block (name resolved); section + bump applied"
