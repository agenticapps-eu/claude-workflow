#!/usr/bin/env bash
# reviewer-cli-version: 1.0.0
#
# VERSION MARKER — read by every host installer before writing this file to the
# SHARED path ~/.agenticapps/bin/. That path is written by claude / codex /
# opencode / pi installers alike, so without arbitration it is last-writer-wins:
# a host still vendoring an older copy silently republishes it over a newer one
# and drops capability for every agent on the machine. Installers MUST refuse to
# overwrite a higher version (treat an unmarked file as 0.0.0). Bump this
# whenever behaviour changes.
#
# This is not hypothetical. Before 1.0.0 there was no marker and nobody
# arbitrated: a host installer delivered the correctly-arbitrated 1.2.2 change
# gate and, in the same run, blind-installed a 3-arm reviewer-cli over a 4-arm
# one. The `opencode` arm vanished and the next review that asked for it got
# `unknown vendor` mid-run. Core#41.
#   1.0.0 — first published canonical. Merges the three divergent host copies:
#           pi's structure (stdin pinned inside run_bounded, explicit usage
#           checks, unbounded-run warning) with codex's coverage (four vendor
#           arms and the opencode model-provenance note).
#
# reviewer-cli.sh — defensive wrapper for an external-vendor reviewer CLI (§18).
#
# The §18 change-gate requires the active change to carry independent multi-AI
# review (>= 2 DISTINCT external vendors) in REVIEWS.md before any code edit.
# The review *producer* — each host's `openspec-change-review` skill — calls
# this wrapper once per vendor to run the actual CLI.
#
# This wrapper exists because of cParX pilot friction #3: `codex exec "<prompt>"`
# reads stdin and HANGS without `</dev/null` (a 4-minute stall on first attempt).
# A hanging reviewer must never be able to stall an edit indefinitely, so every
# reviewer invocation here is:
#   - fed `</dev/null` on stdin, and
#   - bounded by a hard wall-clock `timeout`.
#
# Usage:
#   reviewer-cli.sh <vendor> <prompt-file>
#     <vendor>       claude | gemini | opencode | codex
#                    (>= 2 DISTINCT vendors required by §18)
#     <prompt-file>  path to a file holding the full review prompt
#
# Env:
#   REVIEWER_TIMEOUT   hard wall-clock cap in seconds (default 300)
#
# Output: the reviewer's raw verdict text on stdout.
# Exit:   0 on a completed review; 3 on a usage/lookup/timeout error; otherwise
#         the vendor CLI's own code. The producer MUST treat a non-zero vendor as
#         "reviewer unavailable" and say so in REVIEWS.md — it must NEVER be
#         silently counted as a passing reviewer, because that would let one
#         reachable vendor satisfy a rule whose whole purpose is two independent
#         ones.
#
# VENDOR EXCLUSION IS THE PRODUCER'S JOB, NOT THE WRAPPER'S. A host must never
# review its own change, but the arm for a host's own vendor still ships here:
# this file is installed at ONE global path shared by every host, so the codex
# arm exists for the sibling hosts that call it, and so on. Removing an arm
# because "this host would never use it" is what caused core#41 — the wrapper is
# fleet-wide, the exclusion is per-producer.
#
# PROMPT DELIVERY: the prompt is passed as an ARGUMENT, never on stdin, because
# stdin is pinned to /dev/null by the hardening above. Very large prompts are
# bounded by ARG_MAX; a bundle that exceeds it must be trimmed by the producer.

set -u

vendor="${1:-}"
prompt_file="${2:-}"
TIMEOUT="${REVIEWER_TIMEOUT:-300}"

die() { printf 'reviewer-cli: %s\n' "$*" >&2; exit 3; }

# Both arguments are checked explicitly. Letting an empty prompt_file fall
# through to `[ -f "" ]` reports `prompt file not found: ` with nothing after the
# colon, which reads like a corrupted path rather than a missing argument.
[ -n "$vendor" ] || die "usage: reviewer-cli.sh <vendor> <prompt-file>"
[ -n "$prompt_file" ] || die "usage: reviewer-cli.sh <vendor> <prompt-file>"
[ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"

# Resolve a `timeout` binary. macOS ships neither by default; coreutils installs
# `gtimeout`. If neither exists we still run (unbounded) rather than refuse —
# but we say so, because an unbounded reviewer is the exact failure this wraps.
TIMEOUT_BIN=""
if   command -v timeout  >/dev/null 2>&1; then TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN="gtimeout"
else
  printf 'reviewer-cli: WARNING no timeout(1)/gtimeout(1) on PATH — running %s unbounded.\n' "$vendor" >&2
  printf 'reviewer-cli:   install coreutils (brew install coreutils) to bound reviewer CLIs.\n' >&2
fi

# stdin is pinned HERE, in one place, covering both branches — not at each call
# site. Repeating `</dev/null` per arm is one forgotten redirect away from
# reintroducing the hang this wrapper exists to prevent, and the omission is
# invisible until that specific vendor is next called.
run_bounded() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$TIMEOUT" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

prompt="$(cat "$prompt_file")"

case "$vendor" in
  claude)
    command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
    run_bounded claude -p "$prompt"
    ;;
  gemini)
    command -v gemini >/dev/null 2>&1 || die "gemini CLI not found on PATH"
    # gemini -p "<prompt>" worked first-try in the pilot; still bound + stdin-pinned.
    run_bounded gemini -p "$prompt"
    ;;
  opencode)
    command -v opencode >/dev/null 2>&1 || die "opencode CLI not found on PATH"
    # `opencode` is a client, not a provider — the producer records the MODEL it
    # resolved to (e.g. glm-5.2), not just the CLI name, so "distinct vendor" is
    # judged on the model behind the client. Without this, two arms pointed at
    # the same underlying model would count as two independent reviewers and
    # §18's threshold would be satisfied by one opinion wearing two names.
    run_bounded opencode run "$prompt"
    ;;
  codex)
    command -v codex >/dev/null 2>&1 || die "codex CLI not found on PATH"
    # `codex exec` reads stdin and hangs without the pin (pilot friction #3).
    run_bounded codex exec "$prompt"
    ;;
  *)
    die "unknown vendor '$vendor' (expected: claude | gemini | opencode | codex)"
    ;;
esac
rc=$?

[ "$rc" -eq 124 ] && die "$vendor timed out after ${TIMEOUT}s"
exit "$rc"
