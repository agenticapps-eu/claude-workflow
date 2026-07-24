#!/usr/bin/env bash
# run-plan-review.sh — drive >=2 other-vendor agent CLIs to adversarially review an
# active OpenSpec change and write changes/<slug>/REVIEWS.md. Retarget of ADR-0018.
#
# This is the REVIEW PRODUCER. The §18 change-gate (openspec-change-gate.sh) is the
# VERIFIER: it refuses code edits until this script has written REVIEWS.md with
# >= MIN_REVIEWERS (default 2) `## Reviewer:` sections and `openspec validate --all`
# is green. Producer and verifier are deliberately separate processes.
#
# Usage: run-plan-review.sh <change-slug> [reviewer1 reviewer2 ...]
#   default reviewers tried (any that are installed, excluding the implementing agent):
#     gemini, codex, claude, opencode
#
# Env:
#   AGENT_SELF        implementing agent to exclude (default `claude` on this host, so
#                     the >=2 reviewers are always OTHER vendors — the ADR-0018 property)
#   REVIEW_TIMEOUT    hard wall-clock cap per reviewer, seconds (default 180)
#   MIN_REVIEWERS     reviewers required for a non-warning exit (default 2)
#
# Fixes pilot friction #3: every reviewer CLI is fed </dev/null and time-limited so a
# hanging/prompting CLI can never stall the gate.

set -uo pipefail
SLUG="${1:-}"; shift || true
[ -n "$SLUG" ] || { echo "usage: run-plan-review.sh <change-slug> [reviewers...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGE_DIR="$ROOT/openspec/changes/$SLUG"
[ -d "$CHANGE_DIR" ] || { echo "no such active change: $SLUG" >&2; exit 2; }

TIMEOUT="${REVIEW_TIMEOUT:-180}"                 # seconds per reviewer
SELF="${AGENT_SELF:-claude}"                     # this host IS claude — exclude it by default
REVIEWERS=("$@"); [ ${#REVIEWERS[@]} -gt 0 ] || REVIEWERS=(gemini codex claude opencode)

# Resolve a `timeout` binary. macOS ships neither `timeout` nor `gtimeout` by default
# (they come from GNU coreutils), and this host is darwin-first — a bare `timeout` call
# would fail every reviewer with 127 and silently produce zero reviews.
TIMEOUT_BIN=""
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else
  echo "note: no timeout(1) on PATH (brew install coreutils) — reviewers run unbounded" >&2
fi
bounded() { if [ -n "$TIMEOUT_BIN" ]; then "$TIMEOUT_BIN" "$TIMEOUT" "$@"; else "$@"; fi; }

# Assemble the review prompt from the change artifacts.
read -r -d '' INSTRUCT <<EOF || true
You are an adversarial reviewer. Review this OpenSpec change for correctness, missing
scenarios, wrong assumptions, security/PII issues, and whether the spec delta actually
captures the intent. Reply with a verdict line "VERDICT: APPROVE" or
"VERDICT: REQUEST-CHANGES", then a short bullet list of concrete issues.
EOF
CONTEXT="$(cat "$CHANGE_DIR"/proposal.md "$CHANGE_DIR"/design.md \
             "$CHANGE_DIR"/specs/*/spec.md 2>/dev/null)"
PROMPT="$INSTRUCT

--- CHANGE: $SLUG ---
$CONTEXT"

OUT="$CHANGE_DIR/REVIEWS.md"
# Accumulate into a temp file and only publish at the end. A partial run must not
# destroy the REVIEWS.md an earlier successful run produced — that evidence is what
# the gate reads, and wiping it would silently re-block a reviewed change.
TMP="$(mktemp "${TMPDIR:-/tmp}/reviews.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -f "$TMP"' EXIT
count=0
for r in "${REVIEWERS[@]}"; do
  [ "$r" = "$SELF" ] && continue
  command -v "$r" >/dev/null 2>&1 || continue
  echo "· running reviewer: $r" >&2
  case "$r" in
    codex)    resp="$(printf '%s' "$PROMPT" | bounded codex exec - </dev/null 2>/dev/null || true)" ;;
    gemini)   resp="$(bounded gemini -p "$PROMPT" </dev/null 2>/dev/null || true)" ;;
    claude)   resp="$(bounded claude -p "$PROMPT" </dev/null 2>/dev/null || true)" ;;
    opencode) resp="$(bounded opencode run "$PROMPT" </dev/null 2>/dev/null || true)" ;;
    *)        resp="$(printf '%s' "$PROMPT" | bounded "$r" </dev/null 2>/dev/null || true)" ;;
  esac
  [ -n "$resp" ] || { echo "  (no output from $r — skipped)" >&2; continue; }
  {
    echo "## Reviewer: $r"
    echo "_generated $(date -u +%Y-%m-%dT%H:%M:%SZ) · timeout ${TIMEOUT}s_"
    echo
    printf '%s\n\n' "$resp"
  } >> "$TMP"
  count=$((count+1))
done

if [ "$count" -lt "${MIN_REVIEWERS:-2}" ]; then
  echo "only $count reviewer(s) produced output (need ${MIN_REVIEWERS:-2}) — ${OUT#"$ROOT"/} left unchanged." >&2
  echo "Install another other-vendor agent CLI, or use GSD_SKIP_REVIEWS=1 for a logged emergency override." >&2
  exit 1
fi

cp "$TMP" "$OUT"
echo "wrote $count reviewer section(s) to ${OUT#"$ROOT"/}" >&2
