#!/usr/bin/env bash
# reviewer-cli-conformance.sh — scores a reviewer-cli.sh implementation against
# the contract in reference-implementations/reviewer-cli/README.md.
#
# §18 requires the change-gate be "demonstrable by direct script invocation with
# simulated payloads". The wrapper the gate's review *producer* depends on
# deserves the same bar: a reviewer-cli that silently lost a vendor arm degrades
# the evidence §18 exists to compel, and reports nothing while doing it.
#
# Usage: tools/reviewer-cli-conformance.sh <path-to-reviewer-cli> [...]
#        tools/reviewer-cli-conformance.sh --family    # score every host copy
#
# Exit 0 = every scored copy conforms, 1 = at least one row failed.
# Read-only with respect to the repo and the host clones: every vendor CLI is
# stubbed on PATH in a mktemp dir removed on exit. No real reviewer is invoked.
#
# Sections:
#   A. Argument handling — usage and lookup errors must be exit 3, never a
#      partial run.
#   B. Vendor arms — every vendor in the canonical set must be dispatchable.
#      This is the section that would have caught core#41: a copy missing the
#      `opencode` arm fails here and nowhere else.
#   C. Hardening — the two properties this wrapper exists for. Both are scored
#      per-arm, because the pre-1.0.0 copies pinned stdin at each call site and
#      an arm added later could miss the redirect invisibly.
#   D. Timeout contract — REVIEWER_TIMEOUT honoured, 124 mapped to a die.

set -uo pipefail

pass=0
fail=0

# ── target screening (capability: conformance-harness-reporting) ─────────────
# This harness's explicit-path handling was already correct — it scored a
# missing target as a failure row rather than skipping it, and is the reference
# the other harnesses were fixed against. What it lacked was a REASON: every
# unscoreable target was reported as "file not found", including directories,
# empty files and unreadable ones.
harness_screen_target() { # $1 = path; sets REASON, returns 1 if unscoreable
  REASON=""
  if [ -L "$1" ] && [ ! -e "$1" ]; then REASON="not a regular file (dangling symlink)"; return 1; fi
  if [ ! -e "$1" ]; then REASON="not found"; return 1; fi
  if [ ! -f "$1" ]; then REASON="not a regular file"; return 1; fi
  if [ ! -s "$1" ]; then REASON="empty"; return 1; fi
  if [ ! -r "$1" ]; then REASON="unreadable"; return 1; fi
  return 0
}

harness_safe_label() { # $1 = path
  printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '?'
}

WORK=""

# Used to bound the harness's own invocations of the wrapper under test. Distinct
# from the wrapper's REVIEWER_TIMEOUT, which is what section D scores.
HARNESS_TIMEOUT_BIN=""
if   command -v timeout  >/dev/null 2>&1; then HARNESS_TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then HARNESS_TIMEOUT_BIN="gtimeout"
fi
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# Every vendor the canonical wrapper must dispatch. A copy that cannot reach one
# of these is not "smaller", it is broken for whichever sibling host calls it —
# the wrapper lives at one shared path and vendor exclusion belongs to the
# producer, not here.
VENDORS="claude gemini opencode codex"

# ── fixture ──────────────────────────────────────────────────────────────────
# Stubs every vendor CLI. Each stub records how it was invoked so the rows can
# assert on stdin and argv rather than on the wrapper's stdout alone.
make_fixture() {
  local d v
  d="$(mktemp -d)"
  mkdir -p "$d/stub"
  for v in $VENDORS; do
    cat > "$d/stub/$v" <<'STUB'
#!/usr/bin/env bash
# Records what this vendor was actually handed, on both channels.
#   stdin — must never carry the CALLER's payload (isolation)
#   argv  — must never carry the prompt's CONTENT (the 1.2.0 property)
[ -n "${ARGV_WITNESS:-}" ] && printf '%s\n' "$@" > "$ARGV_WITNESS"
seen="$(cat 2>/dev/null | head -c 200)"
[ -n "${STDIN_WITNESS:-}" ] && printf '%s' "$seen" > "$STDIN_WITNESS"
printf 'VERDICT ok\n'
STUB
    chmod +x "$d/stub/$v"
  done
  printf 'review this change\n' > "$d/prompt.txt"
  printf '%s' "$d"
}

# The harness must survive scoring a BROKEN copy — that is its whole job. A
# wrapper that fails to pin stdin lets the vendor stub inherit the harness's own
# stdin and read from it forever, hanging the run. So the harness pins its own
# invocations here (these rows score exit codes, not pinning) and bounds them.
# Pinning is scored separately by run_row_stdin_pinned, which feeds a FINITE
# payload down the pipe: an unpinned wrapper reads it and fails the row instead
# of blocking.
bounded_cli() { # run the wrapper under a wall-clock cap if one is available
  if [ -n "$HARNESS_TIMEOUT_BIN" ]; then
    "$HARNESS_TIMEOUT_BIN" 20 bash "$CLI" "$@"
  else
    bash "$CLI" "$@"
  fi
}

run_row() { # $1=desc $2=expected-exit $3...=argv for the wrapper
  local desc="$1" want="$2"; shift 2
  local got
  got="$(
    PATH="$FX/stub:$PATH" STDIN_WITNESS="$FX/stdin.witness" \
      bounded_cli "$@" >/dev/null 2>&1 </dev/null
    printf '%s' "$?"
  )"
  if [ "$got" = "$want" ]; then
    echo "  PASS  $desc (exit $got)"; pass=$((pass + 1))
  else
    echo "  FAIL  $desc — expected $want, got $got"; fail=$((fail + 1))
  fi
}

# Asserts the wrapper's stderr carries a given substring. An exit code says a
# failure happened; only the message says WHICH failure, and the message is what
# the producer relays to a human. 1.1.0 exists because "reviewer unavailable" was
# printed for a timeout — a correct non-zero exit paired with a wrong diagnosis.
run_row_stderr_matches() { # $1=desc $2=expected-substring $3...=argv
  local desc="$1" want="$2"; shift 2
  local err
  err="$(
    PATH="$FX/stub:$PATH" STDIN_WITNESS="$FX/stdin.witness" \
      bounded_cli "$@" 2>&1 >/dev/null </dev/null
  )"
  case "$err" in
    *"$want"*) echo "  PASS  $desc"; pass=$((pass + 1)) ;;
    *) echo "  FAIL  $desc — stderr lacked '$want'; got: $err"; fail=$((fail + 1)) ;;
  esac
}

# Asserts the wrapper dispatched AND that the CALLER'S ambient stdin never
# reaches the vendor.
#
# At 1.1.0 this row read "stdin is pinned to /dev/null", because the prompt
# travelled in argv and stdin had no job but to reach EOF. At 1.2.0 the prompt
# travels ON stdin — the argv exposure is the defect being fixed — so "the
# vendor read nothing" is no longer the property. What survives, and is what
# the row was really protecting, is ISOLATION: whatever the wrapper's own
# caller happens to have on stdin must not be handed to a third-party CLI.
#
# The never-blocks guarantee is unchanged and still structural: every arm
# redirects stdin from something that reaches EOF — a regular file rather than
# /dev/null. A wrapper that forgot a redirect on one arm would leak the
# caller's payload, which this row sees.
run_row_stdin_isolated() { # $1=vendor
  local v="$1" out
  : > "$FX/stdin.witness"
  out="$(
    printf 'LEAKED PAYLOAD\n' | PATH="$FX/stub:$PATH" STDIN_WITNESS="$FX/stdin.witness" \
      bounded_cli "$v" "$FX/prompt.txt" 2>/dev/null
  )"
  local witness; witness="$(cat "$FX/stdin.witness" 2>/dev/null)"
  if [ "$out" != "VERDICT ok" ]; then
    echo "  FAIL  $v: arm did not dispatch (got '${out:-<empty>}')"; fail=$((fail + 1))
  elif printf '%s' "$witness" | grep -q 'LEAKED PAYLOAD'; then
    echo "  FAIL  $v: caller's stdin REACHED the vendor — '$witness'"; fail=$((fail + 1))
  else
    echo "  PASS  $v: dispatches; caller stdin isolated from the vendor"; pass=$((pass + 1))
  fi
}

# The 1.2.0 property proper: no change content in argv. A vendor CLI's argv is
# world-readable in the process table for as long as it runs, and the prompt is
# the entire change.
run_row_no_argv_leak() { # $1=vendor
  local v="$1"
  : > "$FX/argv.witness"
  PATH="$FX/stub:$PATH" ARGV_WITNESS="$FX/argv.witness" \
    bounded_cli "$v" "$FX/prompt.txt" >/dev/null 2>&1 </dev/null
  if grep -q 'review this change' "$FX/argv.witness" 2>/dev/null; then
    echo "  FAIL  $v: prompt CONTENT appeared in the vendor's argv"; fail=$((fail + 1))
  else
    echo "  PASS  $v: prompt content never enters argv"; pass=$((pass + 1))
  fi
}

score_one() {
  CLI="$1"
  # $2 is a stable logical label from roster mode; without it the heading
  # printed a resolved absolute path, carrying $HOME into CI logs and making
  # two sweeps on different machines undiffable.
  echo "═══ ${2:-$(harness_safe_label "$CLI")}"
  if ! harness_screen_target "$CLI"; then
    echo "  UNSCOREABLE  ${2:-$(harness_safe_label "$CLI")} — $REASON"
    fail=$((fail + 1)); return
  fi
  FX="$(make_fixture)"; WORK="$FX"

  echo "  ── A. Argument handling ──"
  # 1.1.0 splits the old single `exit 3` into three codes. Usage and lookup
  # failures stay 3 (unavailable); an unknown vendor is 5. Asserted separately
  # because the producer reports them differently — see row group D.
  run_row "no arguments -> 3"              3
  run_row "vendor without prompt file -> 3" 3 claude
  run_row "missing prompt file -> 3"       3 claude "$FX/nope.txt"
  run_row "unknown vendor -> 5"            5 nosuchvendor "$FX/prompt.txt"

  echo "  ── B. Vendor arms ──"
  local v
  for v in $VENDORS; do
    run_row "$v arm is dispatchable" 0 "$v" "$FX/prompt.txt"
  done

  echo "  ── C. Hardening (stdin isolated, no argv leak, per arm) ──"
  for v in $VENDORS; do run_row_stdin_isolated "$v"; done
  for v in $VENDORS; do run_row_no_argv_leak "$v"; done

  echo "  ── D. Timeout contract ──"
  # A vendor CLI that outlives the cap must surface as the wrapper's die (3),
  # not as a raw 124 the producer would have to know to interpret.
  cat > "$FX/stub/codex" <<'SLOW'
#!/usr/bin/env bash
sleep 10
SLOW
  chmod +x "$FX/stub/codex"
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    # 4, not 3. A timeout means the vendor was REACHABLE and ran — the operator
    # needs to raise REVIEWER_TIMEOUT, not go looking for a missing binary.
    # Reporting it as 3 sent someone to check PATH for a working opencode.
    REVIEWER_TIMEOUT=1 run_row "REVIEWER_TIMEOUT honoured; 124 -> die_timeout 4" 4 codex "$FX/prompt.txt"
    # The timeout code must be distinguishable from unavailable, not merely
    # non-zero: the whole point of 1.1.0 is that the producer can tell them apart.
    REVIEWER_TIMEOUT=1 run_row_stderr_matches "timeout message names the bound" \
      'timed out after 1s' codex "$FX/prompt.txt"
  else
    echo "  SKIP  timeout contract (no timeout(1)/gtimeout(1) on PATH)"
  fi

  echo "  ── E. Version marker ──"
  if grep -qE '^# reviewer-cli-version: [0-9]+\.[0-9]+\.[0-9]+' "$CLI"; then
    echo "  PASS  carries # reviewer-cli-version:"; pass=$((pass + 1))
  else
    echo "  FAIL  no # reviewer-cli-version: marker — installers treat this as 0.0.0"
    fail=$((fail + 1))
  fi

  rm -rf "$FX"; WORK=""
}

# ── entry ────────────────────────────────────────────────────────────────────
USAGE="usage: $0 <path-to-reviewer-cli> [...]  |  --family"

FAMILY_MODE=0
if [ "${1:-}" = "--family" ]; then FAMILY_MODE=1; shift; fi

# A roster flag with explicit paths used to discard the paths silently — the
# same defect this harness exists to close, reached through argument parsing.
if [ "$FAMILY_MODE" = "1" ] && [ "$#" -gt 0 ]; then
  echo "$USAGE" >&2
  echo "--family cannot be combined with explicit target paths (got: $(harness_safe_label "$1"))" >&2
  exit 2
fi

if [ "$FAMILY_MODE" = "1" ]; then
  root="$(cd "$(dirname "$0")/../.." && pwd)"
  # label|path. The canonical goes first so a fleet run reads as "the bar,
  # then the fleet". Entries are named by a stable logical label throughout.
  ROSTER="core|$(dirname "$0")/../reference-implementations/reviewer-cli/reviewer-cli.sh
claude-workflow|$root/claude-workflow/bin/reviewer-cli.sh
codex-workflow|$root/codex-workflow/bin/reviewer-cli.sh
opencode-workflow|$root/opencode-workflow/bin/reviewer-cli.sh
pi-agentic-apps-workflow|$root/pi-agentic-apps-workflow/bin/reviewer-cli.sh
shared-install|$HOME/.agenticapps/bin/reviewer-cli.sh"

  roster_total=0 roster_scored=0 roster_unscored=""
  # The absence filter runs AFTER the argument-count check, never before it.
  while IFS='|' read -r label path; do
    [ -n "$label" ] || continue
    roster_total=$((roster_total + 1))
    if harness_screen_target "$path"; then
      p0="$pass"; f0="$fail"
      score_one "$path" "$label"
      # An entry counts as scored only if it contributed a scored row —
      # otherwise `scored 6 of 6` is reachable with a scored total of zero.
      if [ $((pass - p0 + fail - f0)) -gt 0 ]; then
        roster_scored=$((roster_scored + 1))
      else
        roster_unscored="$roster_unscored  $label — reached but produced no scored row"$'\n'
      fi
    else
      host_dir="${path%/bin/reviewer-cli.sh}"
      if [ "$REASON" = "not found" ] &&
         [ -f "$host_dir/bin/resolve-core-artifact.sh" ] &&
         [ -f "$host_dir/tools/core-vendor.manifest" ]; then
        roster_unscored="$roster_unscored  $label — not vendored; resolvable from pin, not attempted"$'\n'
      else
        roster_unscored="$roster_unscored  $label — $REASON"$'\n'
      fi
    fi
  done <<< "$ROSTER"

  echo
  # Emitted on every roster run, complete ones included: a line that appears
  # only when something is wrong becomes the signal, and its absence then has
  # to be noticed to mean anything.
  echo "═══ COVERAGE: scored $roster_scored of $roster_total roster entries"
  [ -n "$roster_unscored" ] && printf '%s' "$roster_unscored"
else
  [ "$#" -ge 1 ] || { echo "$USAGE" >&2; exit 2; }
  for target in "$@"; do score_one "$target"; done
fi

echo
echo "═══ TOTAL: $pass passed, $fail failed"
# Backstop, folded into the one place the exit code is computed.
if [ $((pass + fail)) -eq 0 ]; then
  echo "openspec-conformance: certified NOTHING — no row reached a verdict" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
