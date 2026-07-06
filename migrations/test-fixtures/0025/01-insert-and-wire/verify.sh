#!/bin/sh
# Verify migration 0025 on the BEFORE state (fixture 01): the deterministic
# Step 1 + Step 2 + Step 3 shell, replayed exactly, produces the end state —
# config block inserted with <repo-name> RESOLVED, section appended from the
# scaffolder source ($REPO_ROOT stands in for the clone), version bumped —
# and the insert is SURGICAL (the existing hooks block survives).
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

# Pre-conditions (Steps need to apply):
jq -e 'has("knowledge_capture")' .planning/config.json >/dev/null 2>&1 \
  && { echo "PRE: unexpected knowledge_capture block before apply"; exit 1; }
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.2.0 before apply"; exit 1; }
grep -q '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "PRE: unexpected ritual-tail section before apply"; exit 1; }

# ── Step 1 (apply) — the exact jq insert from 0025 ──────────────────────────
REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
mkdir -p .planning
[ -f .planning/config.json ] || printf '{}\n' > .planning/config.json
jq --arg note "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/${REPO_NAME}.md" \
  'if has("knowledge_capture") then . else . + {knowledge_capture: {enabled: true, note: $note}} end' \
  .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

# Block present, enabled true, placeholder RESOLVED to the repo dir name
jq -e '.knowledge_capture.enabled == true' .planning/config.json >/dev/null \
  || { echo "STEP 1 failed: enabled != true"; exit 1; }
EXPECTED_NOTE="~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/$(basename "$(pwd)").md"
ACTUAL_NOTE="$(jq -r '.knowledge_capture.note' .planning/config.json)"
[ "$ACTUAL_NOTE" = "$EXPECTED_NOTE" ] \
  || { echo "STEP 1 failed: note '$ACTUAL_NOTE' != '$EXPECTED_NOTE'"; exit 1; }
grep -qF '<repo-name>' .planning/config.json \
  && { echo "STEP 1 failed: unresolved <repo-name> placeholder"; exit 1; }
# Surgical: existing hooks block survives
jq -e '.hooks.context_warnings == true' .planning/config.json >/dev/null \
  || { echo "STEP 1 not surgical: hooks block dropped"; exit 1; }

# ── Step 2 (apply) — append the section extracted from the scaffolder ───────
{
  printf '\n'
  awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$REPO_ROOT/skill/SKILL.md"
} >> .claude/skills/agentic-apps-workflow/SKILL.md

[ "$(grep -c '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md)" = "1" ] \
  || { echo "STEP 2 failed: section not appended exactly once"; exit 1; }
# The appended text is byte-identical to the scaffolder source section
awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$REPO_ROOT/skill/SKILL.md" > .expected-section
awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' .claude/skills/agentic-apps-workflow/SKILL.md > .actual-section
cmp -s .expected-section .actual-section \
  || { echo "STEP 2 failed: appended section differs from scaffolder source"; exit 1; }
# Three trigger points are wired in the appended section
for t in "Session handoff" "Plan completion" "Phase completion"; do
  grep -q "$t" .actual-section || { echo "STEP 2 failed: trigger '$t' missing"; exit 1; }
done
rm -f .expected-section .actual-section

# ── Step 3 (apply) — version bump ────────────────────────────────────────────
sed -i.0025.bak -E 's/^version: 2\.2\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 failed: version not bumped to 2.3.0"; exit 1; }

# ── Post-checks (0025) ───────────────────────────────────────────────────────
jq -e '.knowledge_capture.enabled | type == "boolean"' .planning/config.json >/dev/null \
  || { echo "POST: enabled must be boolean"; exit 1; }

echo "fixture 01 — block inserted (name resolved), section wired, version bumped 2.2.0 -> 2.3.0"
