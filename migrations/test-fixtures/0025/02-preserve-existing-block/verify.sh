#!/bin/sh
# Verify migration 0025 on a project with a user-configured block (fixture 02):
# Step 1's positive idempotency anchor holds, and replaying the guarded jq
# changes nothing — user opt-out (enabled:false) and custom note survive.
# Steps 2 and 3 still apply (section + version are independent of the block).
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

# Step 1 idempotency anchor already positive
jq -e 'has("knowledge_capture")' .planning/config.json >/dev/null 2>&1 \
  || { echo "PRE: expected an existing knowledge_capture block"; exit 1; }

before="$(jq -S . .planning/config.json)"

# Replay Step 1 jq — the has() guard must make it a no-op here
REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
jq --arg note "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/${REPO_NAME}.md" \
  'if has("knowledge_capture") then . else . + {knowledge_capture: {enabled: true, note: $note}} end' \
  .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

after="$(jq -S . .planning/config.json)"
[ "$before" = "$after" ] || { echo "STEP 1 not idempotent: modified a user-configured block"; exit 1; }
jq -e '.knowledge_capture.enabled == false' .planning/config.json >/dev/null \
  || { echo "STEP 1 clobbered user opt-out (enabled must stay false)"; exit 1; }
[ "$(jq -r '.knowledge_capture.note' .planning/config.json)" = "/custom/vault/notes/my-repo.md" ] \
  || { echo "STEP 1 clobbered the custom note path"; exit 1; }

# ── Step 2 (apply) — section append still applies ────────────────────────────
{
  printf '\n'
  awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$REPO_ROOT/skill/SKILL.md"
} >> .claude/skills/agentic-apps-workflow/SKILL.md
[ "$(grep -c '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md)" = "1" ] \
  || { echo "STEP 2 failed: section not appended exactly once"; exit 1; }

# ── Step 3 (apply) — version bump still applies ──────────────────────────────
sed -i.0025.bak -E 's/^version: 2\.2\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 failed: version not bumped to 2.3.0"; exit 1; }

echo "fixture 02 — user-configured block preserved verbatim; section + bump applied"
