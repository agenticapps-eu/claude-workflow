#!/usr/bin/env bash
# build-snapshot.sh — regenerate setup/snapshot/ deterministically from the
# maintained sources (templates/ + skill/SKILL.md). The migration chain cannot
# be shell-replayed (prose/agent/AskUserQuestion steps — see ADR-0036 and
# issue #74), so the snapshot is assembled from source, not replayed.
#
#   bash bin/build-snapshot.sh            # rebuild setup/snapshot/ from source
#   bash bin/build-snapshot.sh --check    # assemble to temp + diff, no write
#
# Requires: jq, and a diff supporting --exclude (GNU/BSD). No scaffolder/GSD/gstack/git needed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="$ROOT/setup/snapshot"
MODE="rebuild"; [ "${1:-}" = "--check" ] && MODE="check"

command -v jq >/dev/null || { echo "ERROR: jq required" >&2; exit 1; }

# Assemble the snapshot into $OUT (either $SNAP for rebuild, or a temp dir).
OUT="$SNAP"
if [ "$MODE" = "check" ]; then OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT; fi

# Prune the wildcard-copied dirs before repopulating them. These three are
# assembled entirely by `cp templates/... "$OUT/<dir>/"` globs below, so their
# contents are wholly derived from source. Without the prune, `cp` only ever
# ADDS: a file deleted from templates/ lingers in the committed snapshot
# forever, --check reports DRIFT, and a plain rebuild can never converge on a
# clean tree. (Hit for real when observability-postphase-scan.sh — a hook
# registered in no settings.json — was removed from the payload at 2.5.0.)
rm -rf "$OUT/hooks" "$OUT/scripts" "$OUT/spec-mirrors"
mkdir -p "$OUT/hooks" "$OUT/scripts" "$OUT/spec-mirrors"

# 1. 1:1 source copies (MANIFEST mapping).
cp "$ROOT/skill/SKILL.md"                              "$OUT/agentic-apps-workflow-SKILL.md"
cp "$ROOT/templates/workflow-config.md"                "$OUT/workflow-config.md"
cp "$ROOT/templates/config-hooks.json"                 "$OUT/planning-config.json"
cp "$ROOT/templates/.claude/claude-md/workflow.md"     "$OUT/claude-md-workflow.md"
cp "$ROOT/templates/adr-db-security-acceptance.md"     "$OUT/adr-db-security-acceptance.md"
cp "$ROOT/templates/global-claude-additions.md"        "$OUT/global-claude-additions.md"
cp "$ROOT/templates/gitignore"                         "$OUT/gitignore"
cp "$ROOT"/templates/.claude/hooks/*.sh                "$OUT/hooks/"
cp "$ROOT"/templates/.claude/hooks/*.cjs               "$OUT/hooks/" 2>/dev/null || true
chmod +x "$OUT"/hooks/*.cjs 2>/dev/null || true
cp "$ROOT"/templates/.claude/scripts/*.sh              "$OUT/scripts/"

# spec-mirrors/ — canonical spec blocks the setup path injects (§11; ADR-0040).
# The migration path (0014) reads its copy from the $HOME scaffolder clone;
# the snapshot path reads it from here, so both produce identical CLAUDE.md.
mkdir -p "$OUT/spec-mirrors"
cp "$ROOT"/templates/spec-mirrors/*.md "$OUT/spec-mirrors/"

# 2. claude-settings.json = template minus template-only annotation keys
#    (the installed shape). The multi-ai binding lives in the template already.
jq 'del(._comment, ._enforcement_contract)' \
  "$ROOT/templates/claude-settings.json" > "$OUT/claude-settings.json"

# 3. claude-md-reference-block.md — the block setup appends to CLAUDE.md.
#    Preserved from the committed snapshot (it has no templates/ source file).
[ "$MODE" = "rebuild" ] || cp "$SNAP/claude-md-reference-block.md" "$OUT/claude-md-reference-block.md"

# 4. VERSION stamp from skill/SKILL.md frontmatter.
awk '/^---$/{f++;next} f==1&&/^version:/{print $2;exit}' \
  "$ROOT/skill/SKILL.md" > "$OUT/VERSION"

if [ "$MODE" = "check" ]; then
  # claude-md-reference-block.md and MANIFEST.md are not regenerated; exclude.
  if diff -ru --exclude=claude-md-reference-block.md --exclude=MANIFEST.md "$SNAP" "$OUT" >/dev/null 2>&1; then
    echo "OK — snapshot matches assembled source."
  else
    echo "DRIFT — setup/snapshot/ differs from assembled source:"
    diff -ru --exclude=claude-md-reference-block.md --exclude=MANIFEST.md "$SNAP" "$OUT" | head -40
    exit 1
  fi
else
  echo "snapshot rebuilt at version $(cat "$SNAP/VERSION")"
  # End a rebuild by running the structural drift guard (the authority).
  # (--check does its own diff above; the guard no longer delegates back here,
  #  so there is no recursion.)
  bash "$ROOT/migrations/check-snapshot-parity.sh"
fi
