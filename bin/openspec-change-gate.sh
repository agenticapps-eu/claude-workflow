#!/usr/bin/env bash
# openspec-change-gate.sh — the AgenticApps enforcement gate (host-agnostic).
#
# Rule: you may not edit code while an OpenSpec change is active unless
#   (1) `openspec validate --all` is GREEN, and
#   (2) every active change carries REVIEWS.md with >= MIN_REVIEWERS reviewers.
# This is the OpenSpec-era retarget of the ADR-0018 multi-AI plan-review gate.
#
# Three modes:
#   (default)      HOOK mode — reads a PreToolUse JSON payload on stdin, decides for ONE edit.
#                  Exit 0 = allow, Exit 2 = block. FAIL-OPEN (never bricks a session on error).
#   --pre-commit   Staged-aware — blocks a commit only if it stages non-openspec files while
#                  the gate is unsatisfied. Exit 0 = allow commit, Exit 1 = block. FAIL-CLOSED.
#   --ci           Whole-repo — every active change must validate + have reviews. Exit 0/1.
#
# Env:
#   GSD_SKIP_REVIEWS=1     bypass the review requirement (emergency escape; still needs validate).
#   OPENSPEC_GATE_STRICT=1 also block edits when there is NO active change ("no code without a change").
#   MIN_REVIEWERS=2        override the reviewer threshold.
#
# Exit codes follow the Claude Code PreToolUse convention (2 = block) in hook mode.

set -uo pipefail
MIN_REVIEWERS="${MIN_REVIEWERS:-2}"
MODE="hook"
case "${1:-}" in
  --ci)         MODE="ci" ;;
  --pre-commit) MODE="pre-commit" ;;
esac

log(){ printf 'openspec-gate: %s\n' "$*" >&2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHANGES_DIR="$ROOT/openspec/changes"

# --- helpers ---------------------------------------------------------------

active_changes(){                      # print each active (non-archived) change dir, one per line
  [ -d "$CHANGES_DIR" ] || return 0
  find "$CHANGES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name archive 2>/dev/null | sort
}

reviewer_count(){                      # $1 = change dir ; echo number of reviewers in REVIEWS.md
  local f="$1/REVIEWS.md" n=0
  [ -f "$f" ] || { echo 0; return; }
  # primary convention: one "## Reviewer: <name>" heading per reviewer
  n=$(grep -ciE '^##[[:space:]]*reviewer' "$f" 2>/dev/null || true); n="${n:-0}"
  if [ "$n" -lt "$MIN_REVIEWERS" ]; then
    # fallback: YAML frontmatter `reviewers: [a, b]` or a `- ` list under `reviewers:`
    local fm
    fm=$(awk '
      /^reviewers:[[:space:]]*\[/ { g=gsub(/,/,","); print g+1; found=1; exit }
      /^reviewers:[[:space:]]*$/  { inlist=1; next }
      inlist && /^[[:space:]]*-[[:space:]]/ { c++; next }
      inlist && /^[^[:space:]-]/ { inlist=0 }
      END { if(!found && c>0) print c }' "$f" 2>/dev/null || true)
    [ -n "${fm:-}" ] && [ "${fm:-0}" -gt "$n" ] && n="$fm"
  fi
  echo "${n:-0}"
}

validate_ok(){ ( cd "$ROOT" && openspec validate --all >/dev/null 2>&1 ); }

# Core check. Returns: 0 = satisfied, 2 = blocked. Never errors out.
gate_check(){
  local changes; changes="$(active_changes)"
  if [ -z "$changes" ]; then
    if [ "${OPENSPEC_GATE_STRICT:-0}" = "1" ]; then log "no active change (strict mode) — blocked"; return 2; fi
    return 0                                   # permissive default: incidental edits are fine
  fi
  if ! command -v openspec >/dev/null 2>&1; then
    log "openspec CLI not found — cannot verify; run 'npm i -g @fission-ai/openspec'"; return 2
  fi
  if ! validate_ok; then log "openspec validate --all FAILED — fix the spec delta first"; return 2; fi
  if [ "${GSD_SKIP_REVIEWS:-0}" = "1" ]; then log "GSD_SKIP_REVIEWS=1 — review requirement bypassed"; return 0; fi
  local blocked=0 d n
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n="$(reviewer_count "$d")"
    if [ "$n" -lt "$MIN_REVIEWERS" ]; then
      log "change '${d#"$ROOT"/}' has $n/$MIN_REVIEWERS reviewers — run plan-review to write REVIEWS.md"
      blocked=1
    fi
  done <<< "$changes"
  [ "$blocked" -eq 0 ] && return 0 || return 2
}

# --- edit-path extraction (hook mode) --------------------------------------

edited_path_from_stdin(){              # best-effort parse of a PreToolUse payload
  local payload; payload="$(cat 2>/dev/null || true)"
  [ -n "$payload" ] || { echo ""; return; }
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '
      (.tool_input.file_path // .tool_input.path // .tool_input.notebook_path //
       .params.file_path // .path // empty)' 2>/dev/null | head -n1
  else
    printf '%s' "$payload" | grep -oE '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]+"' \
      | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/'
  fi
}

is_openspec_artifact(){                # edits to the change itself must always be allowed
  case "$1" in
    */openspec/*|openspec/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- modes -----------------------------------------------------------------

case "$MODE" in
  hook)
    # FAIL-OPEN: any unexpected error allows the edit (never brick a live session).
    path="$(edited_path_from_stdin || true)"
    if [ -n "$path" ] && is_openspec_artifact "$path"; then exit 0; fi
    if gate_check; then exit 0; else
      # gate_check returned 2 => block
      log "BLOCKED — no code edits until validate is GREEN and every active change has >= $MIN_REVIEWERS reviewers."
      exit 2
    fi
    ;;

  pre-commit)
    # Only block if the commit stages non-openspec files while the gate is unsatisfied.
    staged="$(git diff --cached --name-only 2>/dev/null || true)"
    non_spec="$(printf '%s\n' "$staged" | grep -vE '(^|/)openspec/' | grep -v '^$' || true)"
    if [ -z "$non_spec" ]; then exit 0; fi          # only spec artifacts staged -> fine
    if gate_check; then exit 0; else
      log "commit BLOCKED — you are committing code while the change gate is unsatisfied."
      exit 1
    fi
    ;;

  ci)
    if gate_check; then log "OK — all active changes validate and are reviewed."; exit 0; else exit 1; fi
    ;;
esac
