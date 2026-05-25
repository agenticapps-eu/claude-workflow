#!/usr/bin/env bash
# Hook 6 — Multi-AI Plan Review Gate (PreToolUse)
#
# Blocks code-touching Edit/Write/MultiEdit operations during a GSD phase
# if the phase has produced a *-PLAN.md but no *-REVIEWS.md (the multi-AI
# plan review, produced by `/gsd-review`).
#
# Rationale: ADR 0018. Plan reviews must run BEFORE execution begins.
# This hook detects the drift pattern observed in cparx phases 04.9 →
# 05 where /gsd-review was silently skipped.
#
# Fires on PreToolUse matcher: Edit|Write|MultiEdit
# Exit 2 = BLOCK; Exit 0 = ALLOW.
# Latency budget: sub-100ms (measured 22-48ms avg on bash 3.2/arm64).
#
# Override (emergency / non-phase work):
#   export GSD_SKIP_REVIEWS=1
# Or place a sentinel:
#   touch .planning/current-phase/multi-ai-review-skipped
#
# Source: ADR 0018 (gate), ADR 0025 (hybrid phase resolver), migrations 0005 + 0016.

set -e

INPUT=$(cat)

# FLAG-B fix: fail-open on malformed JSON instead of crashing with exit 5.
# A broken hook invocation should never silently disable the gate while
# spamming jq parse errors; instead, allow the operation and surface a
# clear single-line warning.
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  echo "[multi-ai-review-gate] malformed JSON on stdin, allowing edit (fail-open)" >&2
  exit 0
fi

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only Edit/Write/MultiEdit are subject to this gate.
[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || [ "$TOOL" = "MultiEdit" ] || exit 0
[ -n "$FILE" ] || exit 0

# Emergency override.
[ "${GSD_SKIP_REVIEWS:-}" = "1" ] && exit 0

# FLAG-A fix: bypass list is gated on both path-prefix AND basename. Previous
# basename-only check matched `docs/IMPLEMENTATION-PLAN.md` (and any other
# repo file ending in those basenames), defeating the gate by filename
# trivially. Now only `.planning/`-rooted GSD canonical artifacts bypass.
case "$FILE" in
  .planning/*|*/.planning/*)
    case "$(basename "$FILE")" in
      *PLAN.md|*PLAN-*.md|*REVIEWS.md|ROADMAP.md|PROJECT.md|REQUIREMENTS.md|*CONTEXT.md|*RESEARCH.md)
        exit 0
        ;;
    esac
    ;;
esac

# Resolve the active phase directory. The historical resolver assumed
# `.planning/current-phase` was a SYMLINK to the phase dir. But the
# design-shotgun and database-sentinel gates use `.planning/current-phase/`
# as a DIRECTORY holding approval sentinels, so in practice readlink returns
# empty and the gate never fired (ADR 0025). Resolver is now a fail-open
# chain: symlink -> GSD state -> STATE.md -> newest PLAN -> allow.
# resolver: hybrid (ADR 0025)

# Match a phase number (e.g. "2" or "04.9") to a phases/<dir>. Tries the raw
# value and a zero-padded-to-2 integer form. Echoes the dir or nothing.
_match_phase_dir() {
  local num="$1" d
  [ -n "$num" ] || return 0
  d=$(find .planning/phases -maxdepth 1 -type d -name "${num}-*" 2>/dev/null | head -1)
  [ -n "$d" ] && { echo "$d"; return 0; }
  case "$num" in
    [0-9]) d=$(find .planning/phases -maxdepth 1 -type d -name "0${num}-*" 2>/dev/null | head -1)
           [ -n "$d" ] && { echo "$d"; return 0; } ;;
  esac
  return 0
}

resolve_phase() {
  local p cp d

  # 1. Legacy symlink (back-compat for any repo that does symlink current-phase).
  p=$(readlink .planning/current-phase 2>/dev/null || true)
  if [ -n "$p" ]; then
    [ -d "$p" ] && { echo "$p"; return 0; }
    [ -d ".planning/$p" ] && { echo ".planning/$p"; return 0; }
  fi

  # 2. GSD state: gsd-tools.cjs state json -> .current_phase
  if command -v node >/dev/null 2>&1 && [ -f "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" ]; then
    cp=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state json 2>/dev/null \
          | jq -r '.current_phase // empty' 2>/dev/null || true)
    d=$(_match_phase_dir "$cp")
    [ -n "$d" ] && { echo "$d"; return 0; }
  fi

  # 3. Parse STATE.md '## Current Phase' — first phase-number-looking token after the heading.
  if [ -f .planning/STATE.md ]; then
    cp=$(awk '/^##[[:space:]]+Current Phase/{f=1; next}
              f && match($0, /[0-9]+(\.[0-9]+)?/){print substr($0, RSTART, RLENGTH); exit}' \
              .planning/STATE.md 2>/dev/null || true)
    d=$(_match_phase_dir "$cp")
    [ -n "$d" ] && { echo "$d"; return 0; }
  fi

  # 4. Newest *-PLAN.md by mtime -> its phase dir.
  local newest
  newest=$(find .planning/phases -maxdepth 2 -name '*-PLAN.md' 2>/dev/null \
            | xargs ls -t 2>/dev/null | head -1 || true)
  [ -n "$newest" ] && { dirname "$newest"; return 0; }

  # 5. Nothing resolved.
  return 0
}

CURRENT_PHASE=$(resolve_phase)
if [ -z "$CURRENT_PHASE" ] || [ ! -d "$CURRENT_PHASE" ]; then
  # No active phase pointer — allow (workflow not in active phase execution).
  exit 0
fi

# Skip sentinel — check both the documented override location (current-phase/)
# and the resolved phase dir.
[ -f ".planning/current-phase/multi-ai-review-skipped" ] && exit 0
[ -f "$CURRENT_PHASE/multi-ai-review-skipped" ] && exit 0

# If no PLAN.md exists yet, planning hasn't happened — allow.
PLANS=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-PLAN.md" 2>/dev/null | head -1)
[ -z "$PLANS" ] && exit 0

# Grandfather guard (ADR 0025): a phase that already produced a *-SUMMARY.md was
# executed before this gate worked. Blocking it would brick repos that shipped
# every phase without reviews (fx-signal-agent, callbot). Allow — enforcement is
# go-forward only, on phases planned but not yet executed.
SUMMARY=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-SUMMARY.md" 2>/dev/null | head -1)
[ -n "$SUMMARY" ] && exit 0

# Plans exist, phase not yet executed. Check for REVIEWS.md.
REVIEWS=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-REVIEWS.md" 2>/dev/null | head -1)
if [ -z "$REVIEWS" ]; then
  echo "❌ Multi-AI Plan Review Gate: blocked edit during execution" >&2
  echo "" >&2
  echo "   Phase:     $CURRENT_PHASE" >&2
  echo "   File:      $FILE" >&2
  echo "   Missing:   $CURRENT_PHASE/<padded>-REVIEWS.md" >&2
  echo "" >&2
  echo "   The phase has *-PLAN.md files but no multi-AI plan review." >&2
  echo "   Run /gsd-review before continuing with execution." >&2
  echo "" >&2
  echo "   Override (emergency only): GSD_SKIP_REVIEWS=1 or touch" >&2
  echo "   .planning/current-phase/multi-ai-review-skipped" >&2
  exit 2
fi

# Ensure REVIEWS.md is a regular file (a FIFO/socket would hang wc -l).
[ -f "$REVIEWS" ] || exit 0

# Advisory stub check: < 5 lines warns but still allows (trust boundary is
# "REVIEWS.md exists"; content quality is gated by post-execution reviews).
if [ "$(wc -l < "$REVIEWS" | tr -d ' ')" -lt 5 ]; then
  echo "⚠ Multi-AI Plan Review Gate: REVIEWS.md present but suspiciously empty" >&2
  echo "   Phase:    $CURRENT_PHASE" >&2
  echo "   REVIEWS:  $REVIEWS ($(wc -l < "$REVIEWS" | tr -d ' ') lines)" >&2
  echo "   Allowing edit, but verify the review actually ran." >&2
  exit 0
fi

exit 0
