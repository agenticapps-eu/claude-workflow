#!/usr/bin/env bash
# Migration 0007 — Install GitNexus MCP wiring + ship the helper script.
#
# Setup-only: registers the gitnexus MCP server in ~/.claude.json.
# Does NOT run per-repo `gitnexus analyze` — that's the helper script's job,
# user-initiated. Idempotent. Sandbox-friendly (all paths via $HOME).
#
# Exit codes:
#   0 — success (fully applied or already-applied)
#   1 — pre-flight or step failure
#   4 — applied but pre-existing MCP entry has unexpected shape (codex B2)
#
# Environment overrides (for testing):
#   HOME                  — sandbox $HOME
#   WIKI_SKILL_MD         — path to SKILL.md (default: $HOME/.claude/skills/agentic-apps-workflow/SKILL.md)
#   GITNEXUS_VERSION      — expected gitnexus version pin (informational; warn-but-proceed on mismatch)
#   GITNEXUS_BIN          — gitnexus binary path (default: command -v gitnexus)

set -e

SKILL_MD="${WIKI_SKILL_MD:-$HOME/.claude/skills/agentic-apps-workflow/SKILL.md}"
CLAUDE_JSON="$HOME/.claude.json"
GITNEXUS_VERSION="${GITNEXUS_VERSION:-2.4.0}"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for migration 0007 but is not installed" >&2
  echo "       Install via: brew install jq (macOS) or apt install jq (Debian/Ubuntu)" >&2
  exit 1
fi

INSTALLED=$(grep -E '^version:' "$SKILL_MD" 2>/dev/null | head -1 | sed 's/version: //' | tr -d '[:space:]' || true)
case "$INSTALLED" in
  1.9.2|1.9.3) : ;;
  *)
    echo "ERROR: installed version is '$INSTALLED', this migration requires 1.9.2 (or 1.9.3 for re-apply)" >&2
    exit 1
    ;;
esac

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not found. Install Node >= 18." >&2
  exit 1
fi

NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
if [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  echo "ERROR: node version too old (major=$NODE_MAJOR), need >= 18" >&2
  exit 1
fi

GN_BIN="${GITNEXUS_BIN:-$(command -v gitnexus 2>/dev/null || true)}"
if [ -z "$GN_BIN" ] || [ ! -x "$GN_BIN" ]; then
  echo "ERROR: gitnexus not installed (or not executable)" >&2
  echo "       Run: npm install -g gitnexus" >&2
  echo "       (PolyForm Noncommercial 1.0 — see ADR 0020 for license terms)" >&2
  exit 1
fi

# Version mismatch check (gemini F1) — warn but proceed.
ACTUAL_VERSION=$("$GN_BIN" --version 2>/dev/null | head -1 | sed 's/^[^0-9]*//' || true)
if [ -n "$ACTUAL_VERSION" ] && [ "$ACTUAL_VERSION" != "$GITNEXUS_VERSION" ]; then
  echo "warn: gitnexus version $ACTUAL_VERSION installed, migration expects pin $GITNEXUS_VERSION (set GITNEXUS_VERSION env to override)" >&2
fi

# Validate ~/.claude.json — if it exists, it must parse (codex B2/F1 area).
if [ -f "$CLAUDE_JSON" ]; then
  if ! jq empty "$CLAUDE_JSON" 2>/dev/null; then
    echo "ERROR: $CLAUDE_JSON exists but is not valid JSON; refusing to modify" >&2
    exit 1
  fi
fi

# ─── Step 1: register MCP server entry ──────────────────────────────────────
# Codex B1 fix: MCP command uses the verified global binary, not npx.
# Codex B2 fix: shape-validation idempotency check.

# Bootstrap ~/.claude.json if missing (codex F1 fix).
if [ ! -f "$CLAUDE_JSON" ]; then
  echo '{}' > "$CLAUDE_JSON"
fi

EXIT_CODE=0

EXISTING_CMD=$(jq -r '.mcpServers.gitnexus.command // empty' "$CLAUDE_JSON" 2>/dev/null)
EXISTING_ARG0=$(jq -r '.mcpServers.gitnexus.args[0] // empty' "$CLAUDE_JSON" 2>/dev/null)

if [ -n "$EXISTING_CMD" ]; then
  # Pre-existing entry — validate shape.
  if [ "$EXISTING_CMD" = "gitnexus" ] && [ "$EXISTING_ARG0" = "mcp" ]; then
    : # canonical shape — idempotent no-op
  else
    echo "warn: pre-existing gitnexus MCP entry has unexpected shape (command='$EXISTING_CMD', args[0]='$EXISTING_ARG0'); preserving but server may not work as expected" >&2
    EXIT_CODE=4
  fi
else
  # Write canonical entry.
  jq '.mcpServers = (.mcpServers // {}) | .mcpServers.gitnexus = {"command":"gitnexus","args":["mcp"]}' \
    "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
fi

# ─── Step 2: bump skill version ─────────────────────────────────────────────
# Phase 09 CSO H1 lesson: explicit if/then/else, not `sed && rm` chain.

if grep -q '^version: 1.9.3$' "$SKILL_MD"; then
  : # already bumped — idempotent no-op
else
  if sed -i.bak 's/^version: 1\.9\.2$/version: 1.9.3/' "$SKILL_MD"; then
    rm -f "${SKILL_MD}.bak"
  else
    rm -f "${SKILL_MD}.bak"
    echo "ERROR: failed to bump version in $SKILL_MD" >&2
    exit 1
  fi
fi

if [ "$EXIT_CODE" = "0" ]; then
  echo "Migration 0007 applied successfully."
else
  echo "Migration 0007 applied with warnings (exit code $EXIT_CODE — see stderr)."
fi
exit "$EXIT_CODE"
