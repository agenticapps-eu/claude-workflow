#!/usr/bin/env bash
# gate-version: 1.2.0
#
# VERSION MARKER — read by every host installer before writing this file to the
# SHARED path ~/.agenticapps/bin/. That path is written by claude / codex /
# opencode / pi installers alike, so without arbitration it is last-writer-wins:
# a host still vendoring an older copy silently republishes it over a newer one
# and reverts the fix for every agent on the machine. Installers MUST refuse to
# overwrite a higher version. Bump this whenever the gate's behaviour changes.
#   1.2.0 — OPENSPEC_BIN indirection (makes §18's "demonstrable by direct
#           invocation" clause actually true), multi-host payload shapes
#           (pi `.input.path`, opencode `.args.*`), OPENSPEC_GATE_SELF
#           self-review exclusion
#   1.1.0 — anchor the openspec/ exemption to $ROOT (bypass fix), tighten
#           reviewer counting, honour fail-open on parse errors
#   1.0.0 — initial canonical script (agenticapps-workflow-core)
#
# openspec-change-gate.sh — the AgenticApps enforcement gate (host-agnostic).
#
# THE REFERENCE IMPLEMENTATION of spec/18-retargeted-change-gate.md. Hosts vendor
# this file rather than maintaining their own copy; divergence between host
# copies is what issue #32 documented and this file exists to end. Conformance is
# executable: tools/change-gate-conformance.sh scores any copy against §18's
# truth table. Change behaviour here only with a matching row.
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
#   OPENSPEC_BIN=openspec  override the openspec CLI name/path.
#   OPENSPEC_GATE_SELF     name of the implementing host; its own reviews do not count.
#
# Exit codes follow the Claude Code PreToolUse convention (2 = block) in hook mode.
#
# Documented deviation from §18's truth table: the GSD_SKIP_REVIEWS escape hatch
# is applied AFTER the validate check, so `validate` red + the hatch set still
# blocks. §18's row reads unconditionally. This narrowing is deliberate — the
# hatch exists to bypass the *review* clause in an emergency, not to ship a
# change whose spec delta does not parse — and it is pinned by a harness row.

set -uo pipefail
MIN_REVIEWERS="${MIN_REVIEWERS:-2}"
# Indirect the CLI so the conformance harness can stub `validate` and assert THIS
# script's logic hermetically, rather than testing OpenSpec. §18 requires the gate
# be "demonstrable by direct script invocation with simulated payloads"; a
# hardcoded binary makes the block/allow rows untestable without a real, populated
# OpenSpec repo — i.e. makes the contract unverifiable as written, which is why
# the fleet-wide drift went unmeasured for as long as it did.
OPENSPEC_BIN="${OPENSPEC_BIN:-openspec}"
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

reviewer_count(){                      # $1 = change dir ; echo number of DISTINCT reviewers
  local f="$1/REVIEWS.md"
  [ -f "$f" ] || { echo 0; return; }
  # One "## Reviewer: <name>" heading per reviewer. Three tightenings over the
  # naive `grep -ciE '^##[[:space:]]*reviewer'`, each closing a way to satisfy
  # the gate without two real reviews:
  #
  #   1. Skip fenced code blocks. A REVIEWS.md that merely QUOTES the convention
  #      inside ``` fences counted as reviewers — a doc about the gate satisfied
  #      the gate.
  #   2. Require the colon and a non-empty name (`## Reviewer: x`), so a prose
  #      heading like "## Reviewers" or "## Reviewer guidance" does not count.
  #   3. Count DISTINCT names. Two sections from one vendor is one independent
  #      opinion, not two; §18 wants independent reviewers.
  #
  #   4. Exclude self-review when OPENSPEC_GATE_SELF names the implementing host.
  #      Without it the gate and the §02 evidence verifier DISAGREE about who
  #      counts, and a gate that disagrees with its own verifier is the ADR-0018
  #      drift pattern reappearing inside the tooling. Anchored
  #      (^self([-_ ].*)?$) so a reviewer whose name merely starts with the same
  #      letters is not swallowed. Unset => no exclusion.
  #
  # The `reviewers:` YAML fallback is deliberately GONE: it let a one-line
  # `reviewers: [a, b]` — which no producer writes and which carries no review
  # content at all — clear the gate. It also ran only when the hardened count was
  # BELOW threshold, with no fence skipping and no dedup, so re-adding it defeats
  # all four properties above at once. Do not restore it.
  #
  # OPENSPEC_GATE_SELF is interpolated into an awk regex, so a host name carrying
  # regex metacharacters would not anchor as written. Host names are bare tokens
  # (pi, claude, codex, opencode); documented constraint, not a guard.
  awk -v self="${OPENSPEC_GATE_SELF:-}" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]*[Rr]eviewer[[:space:]]*:[[:space:]]*[^[:space:]]/ {
      name = $0
      sub(/^##[[:space:]]*[Rr]eviewer[[:space:]]*:[[:space:]]*/, "", name)
      sub(/[[:space:]]+$/, "", name)
      name = tolower(name)
      if (self != "" && name ~ ("^" tolower(self) "([-_ ].*)?$")) next
      seen[name] = 1
    }
    END { n = 0; for (k in seen) n++; print n }
  ' "$f" 2>/dev/null || echo 0
}

validate_ok(){ ( cd "$ROOT" && "$OPENSPEC_BIN" validate --all >/dev/null 2>&1 ); }

# Core check. Returns: 0 = satisfied, 2 = blocked. Never errors out.
gate_check(){
  local changes; changes="$(active_changes)"
  if [ -z "$changes" ]; then
    if [ "${OPENSPEC_GATE_STRICT:-0}" = "1" ]; then log "no active change (strict mode) — blocked"; return 2; fi
    return 0                                   # permissive default: incidental edits are fine
  fi
  if ! command -v "$OPENSPEC_BIN" >/dev/null 2>&1; then
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

# Every host runtime wraps the same two facts (tool name, target path) in its own
# envelope. A key this function does not know about yields an empty path, which
# fails OPEN below — i.e. the gate silently stops enforcing on that host. Adding a
# host means adding its key here AND a payload-shape row to the conformance
# harness; the harness drives a *code* edit precisely because an artifact write
# passes under fail-open whether or not the parser ran.
#
#   .tool_input.*                    — Claude Code PreToolUse
#   .params.file_path                — generic JSON-RPC shape
#   .input.file_path / .input.path   — pi `tool_call` ({toolName, input:{path}};
#                                      verified against pi-coding-agent 0.80.10)
#   .args.filePath / .args.path / .args.file
#                                    — opencode `tool.execute.before`
#   .file_path / .path               — bare fallback
edited_path_from_stdin(){              # best-effort parse of a tool-call payload
  local payload; payload="$(cat 2>/dev/null || true)"
  [ -n "$payload" ] || { echo ""; return; }
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r '
      (.tool_input.file_path // .tool_input.path // .tool_input.notebook_path //
       .params.file_path //
       .input.file_path // .input.path //
       .args.filePath // .args.path // .args.file //
       .file_path // .path // empty)' 2>/dev/null | head -n1
  else
    printf '%s' "$payload" | grep -oE '"(file_?[pP]ath|path|file)"[[:space:]]*:[[:space:]]*"[^"]+"' \
      | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/'
  fi
}

is_openspec_artifact(){                # edits to the change itself must always be allowed
  # Must be THIS repo's spec slot, not any path that happens to contain a
  # directory called `openspec`. The old glob (`*/openspec/*`) exempted
  # `src/openspec/app.ts` and even `/tmp/openspec/x.ts` — a real bypass: a repo
  # with a source directory of that name could edit code freely while the gate
  # was unsatisfied. Resolve the path against $ROOT and require the
  # $ROOT/openspec/ prefix.
  local p="$1" resolved
  [ -n "$p" ] || return 1
  case "$p" in
    /*) resolved="$p" ;;
    *)  resolved="$ROOT/$p" ;;
  esac
  # Normalise `.` and `..` textually — the target of a Write may not exist yet,
  # so realpath/-e cannot be relied on here.
  resolved="$(printf '%s\n' "$resolved" | awk -F/ '
    { n = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "" || $i == ".") continue
        if ($i == "..") { if (n > 0) n--; continue }
        parts[++n] = $i
      }
      out = ""
      for (i = 1; i <= n; i++) out = out "/" parts[i]
      print (out == "" ? "/" : out)
    }')"
  case "$resolved" in
    "$ROOT"/openspec/*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- modes -----------------------------------------------------------------

case "$MODE" in
  hook)
    # FAIL-OPEN: any unexpected error allows the edit (never brick a live session).
    path="$(edited_path_from_stdin || true)"
    # §18: "malformed / unparseable stdin -> allow (fail-open)". We could not
    # extract a target path, so we cannot reason about this call at all —
    # deciding policy on it would be guessing. Previously an unparseable payload
    # fell through to gate_check and could BLOCK (visible under
    # OPENSPEC_GATE_STRICT=1, or with an unsatisfied active change), which
    # inverts the contract: fail open on a PARSE error, never on policy.
    if [ -z "$path" ]; then exit 0; fi
    if is_openspec_artifact "$path"; then exit 0; fi
    if gate_check; then exit 0; else
      # gate_check returned 2 => block
      log "BLOCKED — no code edits until validate is GREEN and every active change has >= $MIN_REVIEWERS reviewers."
      exit 2
    fi
    ;;

  pre-commit)
    # Only block if the commit stages non-openspec files while the gate is unsatisfied.
    # Anchored at ^: staged paths are repo-relative, and `(^|/)openspec/` also
    # exempted `src/openspec/...` — the same bypass is_openspec_artifact had.
    staged="$(git diff --cached --name-only 2>/dev/null || true)"
    non_spec="$(printf '%s\n' "$staged" | grep -vE '^"?openspec/' | grep -v '^$' || true)"
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
