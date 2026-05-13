#!/usr/bin/env bash
# Hook 6 — Multi-AI Plan Review Gate (PreToolUse)
#
# Blocks code-touching Edit/Write operations during a GSD phase if the
# phase has produced a *-PLAN.md but no *-REVIEWS.md (the multi-AI plan
# review, produced by `/gsd-review`).
#
# Rationale: ADR 0018. Plan reviews must run BEFORE execution begins.
# This hook detects the drift pattern observed in cparx phases 04.9 →
# 05 where /gsd-review was silently skipped.
#
# Fires on PreToolUse matcher: Edit|Write
# Exit 2 = BLOCK; Exit 0 = ALLOW.
# Latency budget: sub-100ms.
#
# Override (emergency / non-phase work):
#   export GSD_SKIP_REVIEWS=1
# Or place a sentinel:
#   touch .planning/current-phase/multi-ai-review-skipped
#
# Source: ADR 0018, migration 0005.

set -e

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only Edit/Write are subject to this gate.
[ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ] || exit 0
[ -n "$FILE" ] || exit 0

# Emergency override.
[ "${GSD_SKIP_REVIEWS:-}" = "1" ] && exit 0

# Allow edits to planning artifacts themselves (PLAN.md, REVIEWS.md, ROADMAP.md,
# PROJECT.md, REQUIREMENTS.md, CONTEXT.md, RESEARCH.md) — these are the inputs
# to the review, not the outputs the review is supposed to gate.
case "$(basename "$FILE")" in
  *PLAN.md|*PLAN-*.md|*REVIEWS.md|ROADMAP.md|PROJECT.md|REQUIREMENTS.md|*CONTEXT.md|*RESEARCH.md)
    exit 0
    ;;
esac

# Resolve current phase directory.
CURRENT_PHASE=$(readlink .planning/current-phase 2>/dev/null || true)
if [ -z "$CURRENT_PHASE" ] || [ ! -d "$CURRENT_PHASE" ]; then
  # No active phase pointer — allow (workflow not in active phase execution).
  exit 0
fi

# If current phase has a skip sentinel, allow.
[ -f "$CURRENT_PHASE/multi-ai-review-skipped" ] && exit 0

# If no PLAN.md exists yet, planning hasn't happened — allow.
PLANS=$(find "$CURRENT_PHASE" -maxdepth 2 -name "*-PLAN.md" 2>/dev/null | head -1)
[ -z "$PLANS" ] && exit 0

# Plans exist. Check for REVIEWS.md.
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
  echo "   $CURRENT_PHASE/multi-ai-review-skipped" >&2
  exit 2
fi

# Validate REVIEWS.md isn't empty stub.
if [ "$(wc -l < "$REVIEWS" | tr -d ' ')" -lt 5 ]; then
  echo "⚠ Multi-AI Plan Review Gate: REVIEWS.md present but suspiciously empty" >&2
  echo "   Phase:    $CURRENT_PHASE" >&2
  echo "   REVIEWS:  $REVIEWS ($(wc -l < "$REVIEWS" | tr -d ' ') lines)" >&2
  echo "   Allowing edit, but verify the review actually ran." >&2
  exit 0
fi

exit 0
