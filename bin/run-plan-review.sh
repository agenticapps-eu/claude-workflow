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
#   REVIEWER_CLI      override the wrapper path (default: the shared install, then bin/)
#
# Pilot friction #3 — a reviewer CLI that reads stdin and hangs — is fixed in
# reviewer-cli.sh, not here. This script picks the vendor set and records the
# evidence; the wrapper pins stdin and bounds the clock for every arm. The
# vendor set is core's: claude | gemini | opencode | codex. A name outside it is
# reported unavailable rather than run unbounded.

set -uo pipefail
SLUG="${1:-}"; shift || true
[ -n "$SLUG" ] || { echo "usage: run-plan-review.sh <change-slug> [reviewers...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# $SLUG is pasted straight into a path and the result is later written to, so a
# traversing or absolute slug would make this script overwrite an arbitrary file
# (`run-plan-review.sh ../../src` -> writes src/REVIEWS.md). Accept only a plain
# change-directory name.
case "$SLUG" in
  */*|.|..|-*|"") echo "invalid change slug: '$SLUG' (expected a single directory name)" >&2; exit 2 ;;
esac

CHANGE_DIR="$ROOT/openspec/changes/$SLUG"
[ -d "$CHANGE_DIR" ] || { echo "no such active change: $SLUG" >&2; exit 2; }
# Refuse a symlinked change dir for the same reason: REVIEWS.md must land inside
# the repo's spec slot, not wherever a link points.
[ -L "$CHANGE_DIR" ] && { echo "change dir is a symlink, refusing: $SLUG" >&2; exit 2; }

TIMEOUT="${REVIEW_TIMEOUT:-180}"                 # seconds per reviewer
SELF="${AGENT_SELF:-claude}"                     # this host IS claude — exclude it by default
REVIEWERS=("$@"); [ ${#REVIEWERS[@]} -gt 0 ] || REVIEWERS=(gemini codex claude opencode)

# Vendor dispatch, the stdin pin, and the wall-clock bound all live in
# reviewer-cli.sh — core's reference implementation, vendored at
# `# reviewer-cli-version: 1.0.0` and scored by tools/reviewer-cli-conformance.sh.
# This script used to carry its own copy of the four vendor arms. That is exactly
# the shape that produced core#41: three divergent copies of one wrapper, one of
# them missing the `opencode` arm, all writing the same shared path. A private
# copy of a shared artifact is not a fork, it is a race. Fix behaviour in core
# alongside a harness row and re-vendor; never patch the arms back in here.
#
# Same resolution order as the PreToolUse gate shim, for the same reason: the
# global install is what a scaffolded project gets, and the repo copy is what a
# scaffolder checkout runs before anything is installed.
REVIEWER_CLI="${REVIEWER_CLI:-$HOME/.agenticapps/bin/reviewer-cli.sh}"
[ -x "$REVIEWER_CLI" ] || REVIEWER_CLI="$ROOT/bin/reviewer-cli.sh"
[ -x "$REVIEWER_CLI" ] || {
  echo "reviewer-cli.sh not found (looked at \$REVIEWER_CLI, ~/.agenticapps/bin, $ROOT/bin)." >&2
  echo "Run install.sh, or apply migration 0032 Step 1, to install the shared wrapper." >&2
  exit 2
}

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
# The wrapper takes the prompt as a FILE and hands it to the vendor as an
# argument — stdin is pinned to /dev/null on every arm, so it can never be the
# delivery channel. Write it once; every reviewer reads the same bytes.
PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/review-prompt.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
printf '%s' "$PROMPT" > "$PROMPT_FILE"
trap 'rm -f "$TMP" "$PROMPT_FILE"' EXIT
count=0
for r in "${REVIEWERS[@]}"; do
  [ "$r" = "$SELF" ] && continue
  command -v "$r" >/dev/null 2>&1 || continue
  echo "· running reviewer: $r" >&2
  # REVIEW_TIMEOUT is this producer's knob; REVIEWER_TIMEOUT is the wrapper's.
  # Map one onto the other so the cap documented at the top of this file is the
  # cap actually applied.
  resp="$(REVIEWER_TIMEOUT="$TIMEOUT" "$REVIEWER_CLI" "$r" "$PROMPT_FILE" 2>/dev/null)"
  rc=$?
  # A non-zero wrapper exit means "reviewer unavailable" — unknown vendor, CLI
  # absent, or a timeout. It must never be counted, because §18's whole purpose
  # is TWO independent opinions and one reachable vendor scored twice is one
  # opinion wearing two names. Checked explicitly rather than inferred from
  # empty output: a vendor can fail late and still have printed something.
  if [ "$rc" -ne 0 ]; then
    echo "  (reviewer unavailable: $r exited $rc — not counted)" >&2
    continue
  fi
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
