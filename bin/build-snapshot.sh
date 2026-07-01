#!/usr/bin/env bash
# build-snapshot.sh — regenerate setup/snapshot/ by replaying the full
# migration chain (0000 → latest) into a throwaway fixture, then capturing the
# resulting project-side artifacts as the snapshot.
#
# This is the ONE step that must run on a host with the scaffolder + GSD +
# gstack installed, because materializing a 20+ migration end-state requires
# executing the migrations. Run it after adding/editing any migration so the
# drift guard (migrations/check-snapshot-parity.sh) stays green.
#
# Usage:
#   bash bin/build-snapshot.sh                 # rebuild snapshot/ from replay
#   bash bin/build-snapshot.sh --check         # replay + diff, no write (CI-ish)
#
# Requires: a working install of this scaffolder at ~/.claude/skills/agenticapps-workflow
# (the migrations read templates from there) and `git`, `jq`.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="$ROOT/setup/snapshot"
MODE="rebuild"
[ "${1:-}" = "--check" ] && MODE="check"

SCAFFOLDER="${HOME}/.claude/skills/agenticapps-workflow"
if [ ! -d "$SCAFFOLDER/migrations" ]; then
  echo "ERROR: scaffolder not installed at $SCAFFOLDER (migrations read templates from there)." >&2
  echo "       Install it (bash install.sh) before generating the snapshot." >&2
  exit 1
fi

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
echo "Replaying migrations into fixture: $WORK"
( cd "$WORK" && git init -q -b main && git commit -q --allow-empty -m init )

# Drive the same per-migration apply logic setup used to use, non-interactively.
# Placeholder substitution uses fixture values so workflow-config.md lands in
# placeholder form for the snapshot (we re-template it afterward).
export AAW_NONINTERACTIVE=1
for m in "$SCAFFOLDER"/migrations/[0-9]*.md; do
  id="$(basename "$m" .md)"
  echo "  apply $id"
  # The migration apply harness lives in the shared submodule; reuse it.
  if [ -x "$SCAFFOLDER/vendor/agenticapps-shared/migrations/lib/apply.sh" ]; then
    bash "$SCAFFOLDER/vendor/agenticapps-shared/migrations/lib/apply.sh" "$m" "$WORK" \
      || { echo "ERROR: migration $id failed to apply non-interactively." >&2; exit 1; }
  else
    echo "ERROR: shared apply harness not found. Update the agenticapps-shared submodule." >&2
    echo "       (git submodule update --init --recursive)" >&2
    exit 1
  fi
done

# Capture end-state → snapshot layout (mirrors setup/snapshot/MANIFEST.md).
capture() { # $1 fixture-path  $2 snapshot-relpath
  local src="$WORK/$1" dst="$SNAP/$2"
  [ -e "$src" ] || { echo "  MISSING in fixture: $1"; return 1; }
  if [ "$MODE" = "check" ]; then
    diff -ru "$dst" "$src" >/dev/null 2>&1 || { echo "  DRIFT: $2"; return 1; }
  else
    mkdir -p "$(dirname "$dst")"; cp -R "$src" "$dst"
  fi
}

rc=0
capture ".claude/skills/agentic-apps-workflow/SKILL.md" "agentic-apps-workflow-SKILL.md" || rc=1
capture ".claude/settings.json"                          "claude-settings.json"          || rc=1
capture ".planning/config.json"                          "planning-config.json"          || rc=1
capture ".claude/claude-md/workflow.md"                  "claude-md-workflow.md"          || rc=1
capture ".claude/hooks"                                  "hooks"                          || rc=1
capture ".claude/scripts"                                "scripts"                        || rc=1

# Version stamp from the materialized skill.
if [ "$MODE" = "rebuild" ]; then
  awk '/^---$/{f++;next} f==1&&/^version:/{print $2;exit}' \
    "$WORK/.claude/skills/agentic-apps-workflow/SKILL.md" > "$SNAP/VERSION"
  echo "snapshot rebuilt at version $(cat "$SNAP/VERSION")"
fi

[ "$rc" -ne 0 ] && { echo "FAIL — snapshot differs from replay end-state."; exit 1; }
echo "OK"
