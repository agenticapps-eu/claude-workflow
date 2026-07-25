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
# ~/.agenticapps/bin is SHARED by claude / codex / opencode / pi. Writing it
# unconditionally is last-writer-wins: a host vendoring an older gate silently
# republishes it over a newer one and reverts the fix for every agent on the
# machine. The gate's own header requires installers to refuse a downgrade, so
# arbitrate on the version marker exactly as install.sh does.
# ONE awk, no pipeline, anchored X.Y.Z. `sed -n ... | head -n1 | grep . || echo
# 0.0.0` is a downgrade hole twice over, both verified: with enough marker lines
# head closes the pipe, sed takes SIGPIPE, and under `set -o pipefail` the
# fallback fires AFTER the real version printed — returning "9.9.9\n0.0.0", which
# sort -V reads as 0.0.0; and `[0-9][0-9.]*` parses `9.0.0junk` as `9.0.0`.
# Unparseable is 0.0.0, which fails safe in both directions.
gate_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# gate-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_incoming="$(gate_version "$SCAFFOLDER/bin/openspec-change-gate.sh")"
_installed="$(gate_version "$HOME/.agenticapps/bin/openspec-change-gate.sh")"
_older="$(printf '%s\n%s\n' "$_incoming" "$_installed" | sort -V | head -n1)"
if [ "$_installed" != "$_incoming" ] && [ "$_older" = "$_incoming" ]; then
  echo "NOTE: shared gate is $_installed, newer than this repo's $_incoming — refusing to downgrade."
  echo "      Update this scaffolder (git pull) so every host publishes the same version."
else
  install -m 0755 "$SCAFFOLDER/bin/openspec-change-gate.sh" "$HOME/.agenticapps/bin/openspec-change-gate.sh"
fi
install -m 0755 "$SCAFFOLDER/bin/run-plan-review.sh"      "$HOME/.agenticapps/bin/run-plan-review.sh"
# The producer's vendor wrapper is the SAME shared-path hazard as the gate, and
# it already fired: a host installer delivered the arbitrated 1.2.2 gate and, in
# the same run, blind-installed a 3-arm wrapper over the 4-arm one. The
# `opencode` arm vanished and the next review that asked for it was recorded as
# "reviewer unavailable" and waved through with one fewer opinion (core#41).
# Same rule, same reasoning, on `# reviewer-cli-version:`. Unmarked = 0.0.0.
# Same parser shape, and the same reasons, as gate_version above.
reviewer_cli_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# reviewer-cli-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_rc_incoming="$(reviewer_cli_version "$SCAFFOLDER/bin/reviewer-cli.sh")"
_rc_installed="$(reviewer_cli_version "$HOME/.agenticapps/bin/reviewer-cli.sh")"
_rc_older="$(printf '%s\n%s\n' "$_rc_incoming" "$_rc_installed" | sort -V | head -n1)"
if [ "$_rc_installed" != "$_rc_incoming" ] && [ "$_rc_older" = "$_rc_incoming" ]; then
  echo "NOTE: shared reviewer-cli is $_rc_installed, newer than this repo's $_rc_incoming — refusing to downgrade."
  echo "      Update this scaffolder (git pull) so every host publishes the same version."
else
  install -m 0755 "$SCAFFOLDER/bin/reviewer-cli.sh" "$HOME/.agenticapps/bin/reviewer-cli.sh"
fi
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
    # Drop only the RETIRED COMMANDS, not the whole entry. An entry whose hooks
    # array holds both the old gate and a project-owned hook must keep the
    # latter; filtering by entry silently deleted it.
    | .hooks = [ (.hooks // [])[] | select((.command // "") | test("multi-ai-review-gate|openspec-change-gate") | not) ]
    # An entry left with no hooks was only ever the old gate — drop it.
    | select((.hooks | length) > 0)
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
    # Same surgical rule as PreToolUse: remove the gitnexus command, keep any
    # co-registered project hook that shares the entry.
    | .hooks = [ (.hooks // [])[] | select((.command // "") | test("gitnexus") | not) ]
    | select((.hooks | length) > 0)
  ]
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json

# ── Step 5 — restructure .planning/config.json onto the §17 lifecycle ───────
# The `[ -f ]` guard is NOT in the migration's Apply block, and that is not
# drift: the migration declares a **Pre-condition** (`jq -e '.hooks...'`) that
# the update framework evaluates before running Apply, so a project with no
# .planning/config.json never reaches this shell. The fixture replays Apply
# blocks directly and does not run the framework, so it stands in for that
# pre-condition here. Keep the jq itself byte-identical to the migration's —
# that is what apply-parity asserts.
if [ -f .planning/config.json ]; then
  TPL="$SCAFFOLDER/templates/config-hooks.json"
  tmp="$(mktemp)"
  jq --slurpfile tpl "$TPL" \
    '. as $proj | $proj + $tpl[0]
   | if $proj.knowledge_capture then .knowledge_capture = $proj.knowledge_capture else . end
   | del(.hooks)' \
    .planning/config.json > "$tmp" && mv "$tmp" .planning/config.json
fi
