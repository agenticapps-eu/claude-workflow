#!/usr/bin/env bash
# common-apply.sh — replay migration 0032's DETERMINISTIC steps (1, 3, 4, 5).
#
# Sourced by each fixture's verify.sh. Steps 2 (`openspec init`) and 6 (copy the
# retargeted SKILL.md from the snapshot) are excluded on purpose: step 2 shells
# out to a network-installed CLI, and step 6 is a plain `install`. Neither has
# branching logic worth a fixture; steps 1/3/4/5 carry all the surgery.
#
# Must stay byte-equivalent to the Apply blocks in
# migrations/0032-bind-openspec-v1.md — that is what the fixtures verify.
set -uo pipefail
SCAFFOLDER=~/.claude/skills/agenticapps-workflow

# ── Step 1 — gate + producer + git floor ────────────────────────────────────
mkdir -p "$HOME/.agenticapps/bin"
install -m 0755 "$SCAFFOLDER/bin/openspec-change-gate.sh" "$HOME/.agenticapps/bin/openspec-change-gate.sh"
install -m 0755 "$SCAFFOLDER/bin/run-plan-review.sh"      "$HOME/.agenticapps/bin/run-plan-review.sh"
hooks_dir="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks_dir"
if [ -e "$hooks_dir/pre-commit" ] && ! grep -q 'openspec-change-gate' "$hooks_dir/pre-commit" 2>/dev/null; then
  cp "$hooks_dir/pre-commit" "$hooks_dir/pre-commit.pre-0032"
  echo "NOTE: existing pre-commit saved as pre-commit.pre-0032 — merge it by hand."
fi
install -m 0755 "$SCAFFOLDER/bin/git-hooks/pre-commit" "$hooks_dir/pre-commit"

# ── Step 3 — retarget the PreToolUse gate ───────────────────────────────────
install -m 0755 "$SCAFFOLDER/templates/.claude/hooks/openspec-change-gate.sh" \
  .claude/hooks/openspec-change-gate.sh
rm -f .claude/hooks/multi-ai-review-gate.sh
tmp="$(mktemp)"
jq '
  .hooks.PreToolUse = [
    ( .hooks.PreToolUse // [] )[]
    | select( [ .hooks[]?.command? ] | map(test("multi-ai-review-gate|openspec-change-gate")) | any | not )
  ] + [{
    "_hook": "Hook 7 — OpenSpec Change Gate (spec §18; retarget of the multi-AI plan-review gate)",
    "matcher": "Edit|Write|MultiEdit|NotebookEdit",
    "hooks": [{
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/openspec-change-gate.sh",
      "timeout": 15000
    }]
  }]
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json

# ── Step 4 — remove GitNexus ────────────────────────────────────────────────
rm -f .claude/hooks/gitnexus-reindex.cjs \
      .claude/scripts/install-gitnexus.sh \
      .claude/scripts/rollback-gitnexus.sh \
      .claude/scripts/index-family-repos.sh
rm -rf .gitnexus
tmp="$(mktemp)"
jq '
  .hooks.PostToolUse = [
    ( .hooks.PostToolUse // [] )[]
    | select( [ .hooks[]?.command? ] | map(test("gitnexus")) | any | not )
  ]
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json

# ── Step 5 — restructure .planning/config.json onto the §17 lifecycle ───────
if [ -f .planning/config.json ]; then
  TPL="$SCAFFOLDER/templates/config-hooks.json"
  tmp="$(mktemp)"
  jq --slurpfile tpl "$TPL" \
    '$tpl[0] + (if .knowledge_capture then {knowledge_capture: .knowledge_capture} else {} end)' \
    .planning/config.json > "$tmp" && mv "$tmp" .planning/config.json
fi
