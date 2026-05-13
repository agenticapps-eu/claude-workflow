#!/usr/bin/env bash
# Migration 0006 — Install LLM wiki compiler plugin + per-family scaffolding.
#
# Idempotent. Sandbox-friendly (all paths via $HOME). Documented in
# migration 0006 + ADR 0019.
#
# Exit codes:
#   0  — success (fully applied or already-applied)
#   1  — pre-flight or step failure
#   2  — wrong-target symlink (codex B2: abort, do not repoint)
#   3  — `.knowledge` exists as a regular file in some family (codex F4)
#
# Environment overrides (for testing):
#   HOME                  — root for all ~-expansions (sandbox-friendly)
#   WIKI_PLUGIN_SOURCE    — path to vendored plugin (default: $HOME/Sourcecode/agenticapps/wiki-builder/plugin)
#   WIKI_SOURCECODE       — sourcecode root (default: $HOME/Sourcecode)
#   WIKI_SKILL_MD         — path to SKILL.md for version bump (default: .claude/skills/agentic-apps-workflow/SKILL.md)

set -e

PLUGIN_SOURCE="${WIKI_PLUGIN_SOURCE:-$HOME/Sourcecode/agenticapps/wiki-builder/plugin}"
SOURCECODE_ROOT="${WIKI_SOURCECODE:-$HOME/Sourcecode}"
SKILL_MD="${WIKI_SKILL_MD:-.claude/skills/agentic-apps-workflow/SKILL.md}"
PLUGIN_LINK="$HOME/.claude/plugins/llm-wiki-compiler"

# ─── Pre-flight ──────────────────────────────────────────────────────────────

# FLAG-E (phase 08 carry-over): trim whitespace on extracted version.
INSTALLED=$(grep -E '^version:' "$SKILL_MD" 2>/dev/null | head -1 | sed 's/version: //' | tr -d '[:space:]' || true)
if [ "$INSTALLED" != "1.9.1" ]; then
  echo "ERROR: installed version is '$INSTALLED', this migration requires 1.9.1" >&2
  exit 1
fi

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
#   (b) is not in the skip-list (personal/shared/archive/dotfiles),
#   (c) contains at least one immediate child that's a git repo (has .git dir).
# codex F2: the child-.git heuristic prevents scaffolding unrelated buckets.

is_family() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  case "$(basename "$dir")" in
    personal|shared|archive|.*) return 1 ;;
  esac
  if find "$dir"/*/.git -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
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
# Idempotency check: directories exist.
# codex F4: abort if .knowledge exists as a regular file.

for fam in ${FAMILIES[@]+"${FAMILIES[@]}"}; do
  knowledge="$fam/.knowledge"
  if [ -e "$knowledge" ] && [ ! -d "$knowledge" ]; then
    echo "ERROR: $knowledge exists as a regular file/symlink, not a directory. Refusing to overwrite." >&2
    exit 3
  fi
  mkdir -p "$knowledge/raw" "$knowledge/wiki"
  # .gitignore for the wiki (regenerable derived artifact)
  if [ ! -f "$knowledge/.gitignore" ]; then
    cat > "$knowledge/.gitignore" <<'EOF'
# Wiki output is a derived artifact, regenerable via `/wiki-compile`.
wiki/
EOF
  fi
done

# ─── Step 4: per-family .wiki-compiler.json ─────────────────────────────────
# Idempotency check: file exists (preserve user customisation per RESEARCH §5).
# codex F4: detect malformed pre-existing config, warn and preserve.

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
  else
    cat > "$config" <<EOF
{
  "version": 2,
  "name": "$fam_name_titlecase Knowledge",
  "mode": "knowledge",
  "sources": [
    {"path": "*/docs/decisions", "description": "ADRs across repos"},
    {"path": "*/README.md", "description": "Repo overviews"},
    {"path": "*/CLAUDE.md", "description": "Per-repo workflow docs"},
    {"path": "*/.planning/phases", "description": "GSD planning artifacts"}
  ],
  "output": ".knowledge/wiki/"
}
EOF
  fi
done

# ─── Step 5: per-family CLAUDE.md section ───────────────────────────────────
# Idempotency check: grep for `## Knowledge wiki` heading.
# codex B3: skip-with-warning if family CLAUDE.md doesn't exist.

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
# Idempotency check: version line reads 1.9.2.

if grep -q '^version: 1.9.2$' "$SKILL_MD"; then
  : # already bumped — idempotent no-op
else
  sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.2/' "$SKILL_MD" && rm -f "$SKILL_MD.bak"
fi

echo "Migration 0006 applied successfully (${#FAMILIES[@]} families processed)."
exit 0
