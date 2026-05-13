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
# Source: ADR 0018, migration 0005.

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

# CSO L1 fix: ensure REVIEWS.md is a regular file. A FIFO or socket at
# that path would hang `wc -l` until the Claude Code hook timeout. With
# `[ -f ... ]` the non-regular case treats REVIEWS as effectively absent
# and proceeds to the allow path (no stub-warn message — the file isn't
# really there in any meaningful sense).
[ -f "$REVIEWS" ] || exit 0

# Validate REVIEWS.md isn't empty stub. FLAG-D advisory threshold:
# < 5 lines is treated as a stub and triggers a warning, but still allows
# the edit. The hook's stated trust-boundary (ADR 0018) is "REVIEWS.md
# exists." Quality of content is gated by Stage 1 + Stage 2 post-execution
# reviews, not by this hook. A bad-faith 5-line stub would be obvious in
# the eventual review artifact and in git history of the REVIEWS.md file.
if [ "$(wc -l < "$REVIEWS" | tr -d ' ')" -lt 5 ]; then
  echo "⚠ Multi-AI Plan Review Gate: REVIEWS.md present but suspiciously empty" >&2
  echo "   Phase:    $CURRENT_PHASE" >&2
  echo "   REVIEWS:  $REVIEWS ($(wc -l < "$REVIEWS" | tr -d ' ') lines)" >&2
  echo "   Allowing edit, but verify the review actually ran." >&2
  exit 0
fi

exit 0
