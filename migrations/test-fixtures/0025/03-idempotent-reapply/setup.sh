#!/bin/sh
# Fixture 03 — AFTER state: migration already applied. Version is 2.3.0, the
# config carries the block (name resolved), and the skill already ends with the
# ritual-tail section (appended from the real scaffolder source, as Step 2
# does). All idempotency anchors are positive; a re-run must be a clean no-op.
set -eu
SKILL_VERSION=2.3.0 . "$FIXTURES_ROOT/common-setup.sh"

{
  printf '\n'
  awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$REPO_ROOT/skill/SKILL.md"
} >> .claude/skills/agentic-apps-workflow/SKILL.md

mkdir -p .planning
cat > .planning/config.json <<EOF_CFG
{
  "hooks": {
    "context_warnings": true
  },
  "knowledge_capture": {
    "enabled": true,
    "note": "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/$(basename "$(pwd)").md"
  }
}
EOF_CFG
