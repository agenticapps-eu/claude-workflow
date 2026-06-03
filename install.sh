#!/usr/bin/env bash
# install.sh — make the AgenticApps Claude Workflow skills discoverable.
#
# Claude Code's skill loader scans ~/.claude/skills/<name>/SKILL.md (one level
# deep). This repo nests skills in subdirectories (skill/, setup/, update/)
# for logical grouping, so the loader doesn't find them by default. This
# script symlinks each skill subdirectory out to its canonical discoverable
# path.
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

# Advance the agenticapps-shared submodule (idempotent: safe on fresh AND existing clones).
# A3: do NOT guard on VERSION-missing — after a `git pull` an existing clone must move to the
# new gitlink SHA. sync picks up any .gitmodules URL change; update --init advances/initialises.
# Guard on a real .git (review finding 2): a copied/tarball tree carries .gitmodules but no
# git dir, so the refresh would fatal and `set -e` would abort the whole install before any
# skill linking. .git is a dir in a clone, a file in a worktree/submodule — accept both. Keep
# the refresh non-fatal so a transient submodule error still lets skill linking proceed.
if [ -f "$SCAFFOLDER/.gitmodules" ] && { [ -d "$SCAFFOLDER/.git" ] || [ -f "$SCAFFOLDER/.git" ]; }; then
  echo "Syncing git submodule(s) vendor/agenticapps-shared..."
  if ! { git -C "$SCAFFOLDER" submodule sync --recursive \
      && git -C "$SCAFFOLDER" submodule update --init --recursive; }; then
    echo "WARNING: submodule refresh failed — continuing with skill linking." >&2
    echo "  Fix later: git -C \"$SCAFFOLDER\" submodule update --init --recursive" >&2
  fi
fi

# Pairs of "<subdir-in-scaffolder> <skill-name-for-claude-code>".
# Order matters for the install summary; scaffolder name alphabetical.
LINKS=(
  "skill agentic-apps-workflow"
  "setup setup-agenticapps-workflow"
  "update update-agenticapps-workflow"
)

mkdir -p "$SKILLS_DIR"

# Legacy cleanup (claude-workflow 2.0.0 / SPLIT-03): observability moved to the separate
# agenticapps-observability repo and the bundled add-observability/ subdir was deleted, so the
# add-observability skill-pair is no longer installed here. An add-observability symlink from a
# pre-2.0.0 install now dangles. Remove it ONLY if it is a symlink whose target is missing — a valid
# alias created by the obs repo's own install.sh (target exists) is left untouched.
legacy_obs_link="$SKILLS_DIR/add-observability"
if [ -L "$legacy_obs_link" ] && [ ! -e "$legacy_obs_link" ]; then
  rm -f "$legacy_obs_link"
  echo "  ⊘ removed dangling legacy symlink: add-observability (observability now installs separately)"
fi

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
