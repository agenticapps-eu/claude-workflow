#!/usr/bin/env bash
# Migration 0006 — Install LLM wiki compiler plugin + per-family scaffolding.
#
# Idempotent — accepts both 1.9.1 (fresh apply) and 1.9.2 (already-applied)
# baselines. Sandbox-friendly: all paths via $HOME (no CWD dependency).
#
# Exit codes:
#   0  — success (fully applied or already-applied)
#   1  — pre-flight or step failure
#   2  — symlink-target collision (regular file at the path, or wrong-target symlink)
#   3  — `.knowledge` exists as a regular file in some family
#
# Environment overrides (for testing):
#   HOME                  — root for all ~-expansions (sandbox-friendly)
#   WIKI_PLUGIN_SOURCE    — path to vendored plugin (default: $HOME/Sourcecode/agenticapps/wiki-builder/plugin)
#   WIKI_SOURCECODE       — sourcecode root (default: $HOME/Sourcecode)
#   WIKI_SKILL_MD         — path to SKILL.md (default: $HOME/.claude/skills/agentic-apps-workflow/SKILL.md)

set -e

PLUGIN_SOURCE="${WIKI_PLUGIN_SOURCE:-$HOME/Sourcecode/agenticapps/wiki-builder/plugin}"
SOURCECODE_ROOT="${WIKI_SOURCECODE:-$HOME/Sourcecode}"
# Stage 2 NOTE-3: default to absolute path. Prevents the BLOCK-2 CWD-dependency
# bug where a relative path would resolve to wherever the caller chdir'd to.
SKILL_MD="${WIKI_SKILL_MD:-$HOME/.claude/skills/agentic-apps-workflow/SKILL.md}"
PLUGIN_LINK="$HOME/.claude/plugins/llm-wiki-compiler"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

# Stage 2 FLAG-C: require jq up front. Otherwise jq-empty failures get
# misattributed to "invalid JSON" downstream.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for migration 0006 but is not installed" >&2
  echo "       Install via: brew install jq  (macOS) or apt install jq (Debian/Ubuntu)" >&2
  exit 1
fi

# Trim whitespace on extracted version (phase 08 FLAG-E carry-over).
INSTALLED=$(grep -E '^version:' "$SKILL_MD" 2>/dev/null | head -1 | sed 's/version: //' | tr -d '[:space:]' || true)
# Stage 2 BLOCK-1: accept 1.9.1 (apply path) OR 1.9.2 (re-apply, already-applied).
# All downstream steps are individually idempotent.
case "$INSTALLED" in
  1.9.1|1.9.2) : ;;
  *)
    echo "ERROR: installed version is '$INSTALLED', this migration requires 1.9.1 (or 1.9.2 for re-apply)" >&2
    exit 1
    ;;
esac

if [ ! -f "$PLUGIN_SOURCE/.claude-plugin/plugin.json" ]; then
  echo "ERROR: vendored plugin missing at $PLUGIN_SOURCE/.claude-plugin/plugin.json" >&2
  echo "       Clone first: git clone --depth=1 https://github.com/ussumant/llm-wiki-compiler.git $HOME/Sourcecode/agenticapps/wiki-builder" >&2
  exit 1
fi

# ─── Step 1: symlink the plugin into ~/.claude/plugins/ ─────────────────────
# Idempotency check: $PLUGIN_LINK is a symlink pointing at $PLUGIN_SOURCE.

mkdir -p "$HOME/.claude/plugins"

if [ -e "$PLUGIN_LINK" ] && [ ! -L "$PLUGIN_LINK" ]; then
  echo "ERROR: $PLUGIN_LINK exists as a regular file/directory, not a symlink. Refusing to overwrite." >&2
  exit 2
fi

if [ -L "$PLUGIN_LINK" ]; then
  ACTUAL=$(readlink "$PLUGIN_LINK")
  if [ "$ACTUAL" = "$PLUGIN_SOURCE" ]; then
    : # already correct — idempotent no-op
  else
    # codex B2: ABORT on wrong target. Do NOT silently repoint.
    echo "ERROR: $PLUGIN_LINK is a symlink to $ACTUAL; refusing to repoint to $PLUGIN_SOURCE" >&2
    echo "       (rollback first if you want to reinstall: rm -f $PLUGIN_LINK)" >&2
    exit 2
  fi
else
  ln -s "$PLUGIN_SOURCE" "$PLUGIN_LINK"
fi

# ─── Step 2: detect families ────────────────────────────────────────────────
# A "family" is a directory under $SOURCECODE_ROOT that:
#   (a) is a directory (not a file/symlink to elsewhere),
#   (b) is not in the skip-list (case-insensitive: personal/shared/archive/dotfiles),
#   (c) contains at least one immediate child whose `.git` exists as
#       either a directory (regular repo) or a regular file (git worktree).
# codex F2: child-`.git` heuristic prevents scaffolding unrelated buckets.
# Stage 2 FLAG-B: accept worktrees by allowing `.git` to be a file.
# CSO L1: case-insensitive skip-list.

is_family() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local base_lc
  base_lc=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
  case "$base_lc" in
    personal|shared|archive|.*) return 1 ;;
  esac
  # FLAG-B: match `.git` as directory OR file (worktree).
  for c in "$dir"/*/.git; do
    [ -e "$c" ] && return 0
  done
  return 1
}

# Collect families
FAMILIES=()
if [ -d "$SOURCECODE_ROOT" ]; then
  for d in "$SOURCECODE_ROOT"/*/; do
    fam_dir="${d%/}"
    is_family "$fam_dir" && FAMILIES+=("$fam_dir")
  done
fi

# ─── Step 3: per-family .knowledge/{raw,wiki}/ dirs ─────────────────────────

for fam in ${FAMILIES[@]+"${FAMILIES[@]}"}; do
  knowledge="$fam/.knowledge"
  if [ -e "$knowledge" ] && [ ! -d "$knowledge" ]; then
    echo "ERROR: $knowledge exists as a regular file/symlink, not a directory. Refusing to overwrite." >&2
    exit 3
  fi
  mkdir -p "$knowledge/raw" "$knowledge/wiki"
  if [ ! -f "$knowledge/.gitignore" ]; then
    cat > "$knowledge/.gitignore" <<'EOF'
# Wiki output is a derived artifact, regenerable via `/wiki-compile`.
wiki/
EOF
  fi
done

# ─── Step 4: per-family .wiki-compiler.json ─────────────────────────────────
# Idempotency: preserve any existing file (even if malformed; warn).
# CSO M1: JSON-escape the family-name field. Family directories named like
# `foo"bar` would otherwise produce invalid JSON via raw heredoc interpolation.

for fam in ${FAMILIES[@]+"${FAMILIES[@]}"}; do
  fam_name=$(basename "$fam")
  fam_name_titlecase=$(echo "$fam_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  config="$fam/.wiki-compiler.json"

  if [ -f "$config" ]; then
    if jq empty "$config" 2>/dev/null; then
      : # valid existing config — preserve
    else
      echo "warn: $config exists but is not valid JSON; skipping (user must fix manually)" >&2
    fi
    continue
  fi

  # Build via jq to guarantee valid JSON regardless of family-name content (CSO M1 fix).
  jq -n --arg name "$fam_name_titlecase Knowledge" '{
    version: 2,
    name: $name,
    mode: "knowledge",
    sources: [
      {path: "*/docs/decisions", description: "ADRs across repos"},
      {path: "*/README.md", description: "Repo overviews"},
      {path: "*/CLAUDE.md", description: "Per-repo workflow docs"},
      {path: "*/.planning/phases", description: "GSD planning artifacts"}
    ],
    output: ".knowledge/wiki/"
  }' > "$config"
done

# ─── Step 5: per-family CLAUDE.md section ───────────────────────────────────

KNOWLEDGE_SECTION='
## Knowledge wiki

This family has an LLM-compiled wiki at `.knowledge/wiki/`. Slash commands available after install:

- `/wiki-compile` — compile family sources into the wiki (incremental)
- `/wiki-lint` — health check (stale, orphans, contradictions, drift)
- `/wiki-query "<q>"` — ask the wiki a question
- `/wiki-search "<q>"` — full-text search

See migration 0006 / ADR 0019.'

for fam in ${FAMILIES[@]+"${FAMILIES[@]}"}; do
  claudemd="$fam/CLAUDE.md"
  if [ ! -f "$claudemd" ]; then
    echo "note: $claudemd not present, skipping ## Knowledge wiki section addition" >&2
    continue
  fi
  if grep -q '^## Knowledge wiki' "$claudemd"; then
    : # already present — idempotent no-op
  else
    echo "$KNOWLEDGE_SECTION" >> "$claudemd"
  fi
done

# ─── Step 6: bump skill version ─────────────────────────────────────────────
# CSO H1: do NOT use `sed && rm` — `set -e` aborts `&&` chains via the chain's
# overall exit, but a read-only or otherwise unwritable SKILL.md silently
# loses the `rm -f .bak` (sed creates the .bak file, then fails on the write
# of the main file — leaving .bak behind without a chance to clean up).
# Use explicit if/then/else so failures are loud.

if grep -q '^version: 1.9.2$' "$SKILL_MD"; then
  : # already bumped — idempotent no-op
else
  if sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.2/' "$SKILL_MD"; then
    rm -f "${SKILL_MD}.bak"
  else
    rm -f "${SKILL_MD}.bak"
    echo "ERROR: failed to bump version in $SKILL_MD (permission denied? read-only filesystem?)" >&2
    exit 1
  fi
fi

echo "Migration 0006 applied successfully (${#FAMILIES[@]} families processed)."
exit 0
