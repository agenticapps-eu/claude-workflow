#!/usr/bin/env bash
# install.sh — make the AgenticApps Claude Workflow skills discoverable.
#
# Claude Code's skill loader scans ~/.claude/skills/<name>/SKILL.md (one level
# deep). This repo nests skills in subdirectories (skill/, setup/, update/) for
# logical grouping, so the loader doesn't find them by default. This script
# symlinks each skill subdirectory out to its canonical discoverable path.
#
# Run this once after cloning the scaffolder, and again after every `git pull`
# that adds new skill subdirectories. Idempotent — safe to re-run any time.
#
# Refuses to clobber existing non-symlink directories (e.g. a real directory
# at the target path means a project copy or third-party install lives there
# and we shouldn't replace it).

set -euo pipefail

# Resolve scaffolder dir to wherever this script lives, regardless of cwd.
SCAFFOLDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

# Pairs of "<subdir-in-scaffolder> <skill-name-for-claude-code>".
# Order matters for the install summary; scaffolder name alphabetical.
LINKS=(
  "skill agentic-apps-workflow"
  "setup setup-agenticapps-workflow"
  "update update-agenticapps-workflow"
)

mkdir -p "$SKILLS_DIR"

echo "Installing AgenticApps workflow skills"
echo "  Scaffolder: $SCAFFOLDER"
echo "  Skills dir: $SKILLS_DIR"
echo ""

LINKED=0
SKIPPED=0
FAILED=0

for entry in "${LINKS[@]}"; do
  src="$SCAFFOLDER/${entry%% *}"
  name="${entry##* }"
  link="$SKILLS_DIR/$name"

  if [ ! -d "$src" ]; then
    # Source subdir missing — likely an old scaffolder version (pre-1.3.0
    # repos didn't have update/). Skip silently for forward compat with
    # older installs that don't have all subdirs.
    echo "  ⊘ source missing: $src (skipping $name)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ ! -f "$src/SKILL.md" ]; then
    echo "  ✗ no SKILL.md at $src — refusing to link as $name"
    FAILED=$((FAILED + 1))
    continue
  fi

  if [ -L "$link" ]; then
    existing_target="$(readlink "$link")"
    if [ "$existing_target" = "$src" ]; then
      echo "  ✓ already linked: $name → $src"
      LINKED=$((LINKED + 1))
      continue
    else
      echo "  ↻ existing symlink points elsewhere ($existing_target); replacing"
      rm "$link"
    fi
  elif [ -e "$link" ]; then
    echo "  ✗ $link exists and is NOT a symlink — refusing to clobber."
    echo "    Inspect it; if safe to replace, run: rm -rf '$link' && rerun this script."
    FAILED=$((FAILED + 1))
    continue
  fi

  ln -s "$src" "$link"
  echo "  ✓ linked: $name → $src"
  LINKED=$((LINKED + 1))
done

echo ""
echo "Summary: linked=$LINKED skipped=$SKIPPED failed=$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  echo "Some links failed. Resolve the conflicts above and re-run."
  exit 1
fi

echo "Slash commands now available in any Claude Code session:"
echo "  /agentic-apps-workflow         the workflow itself (auto-triggers on code tasks)"
echo "  /setup-agenticapps-workflow    bootstrap a fresh project"
echo "  /update-agenticapps-workflow   apply pending migrations to an installed project"
echo ""
echo "Verify discovery with: ls -la $SKILLS_DIR | grep -E '(agentic|setup|update)-?(apps-)?workflow'"
