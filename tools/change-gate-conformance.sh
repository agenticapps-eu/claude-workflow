#!/usr/bin/env bash
# change-gate-conformance.sh — scores a §18 change-gate implementation
# against the exit-code truth table in spec/18-retargeted-change-gate.md.
#
# §18 requires the gate be "demonstrable by direct script invocation with
# simulated payloads" (spec/18, Conformance). This is that demonstration,
# executable: it builds a throwaway fixture repo, stubs the `openspec` CLI
# on PATH so `validate` can be driven green or red independently of the
# gate's own logic, and drives the gate through every row.
#
# Usage: tools/change-gate-conformance.sh <path-to-gate-script> [...]
#        tools/change-gate-conformance.sh --family     # score every host clone
#
# Exit 0 = every scored gate conforms, 1 = at least one row failed.
# Read-only with respect to the repo and the host clones: all writes land
# in a mktemp dir that is removed on exit.
#
# Sections:
#   A. Truth table (spec/18) — normative for every host. A failure here is
#      a conformance defect.
#   B. Payload shapes — the same policy rows re-driven through each host
#      runtime's payload envelope. A gate that cannot parse a shape fails
#      OPEN on that host, i.e. silently does not enforce.
#   C. Modes — `--pre-commit` / `--ci`. §18 makes the shell script "the
#      real enforcement surface ... including against a human editor";
#      these rows score the agent-agnostic floor. Reported separately
#      because a hook-only gate may legitimately not implement them.
#   D. Reviewer counting — §02/§18 count independent reviewers, not lines
#      matching a heading. Duplicate headings, fenced examples, prose section
#      headers and bare `reviewers:` YAML must not inflate the count past the
#      threshold.
#   E. Self-review exclusion — OPENSPEC_GATE_SELF. Reported separately because
#      a host that does not set it is not thereby non-conformant to §18; the
#      rows pin the behaviour where it IS implemented.

set -uo pipefail

pass=0
fail=0
inconclusive=0
WORK=""

cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# ── fixture construction ─────────────────────────────────────────────────────
# Builds a repo with one active change and returns its path. Callers mutate
# REVIEWS.md / the validate stub per row.
make_fixture() { # $1 = validate exit code (0 green, 1 red)
  local d rc="$1"
  d="$(mktemp -d)"
  mkdir -p "$d/stub" "$d/repo/openspec/changes/add-thing" "$d/repo/src"
  printf '#!/usr/bin/env bash\nexit %s\n' "$rc" > "$d/stub/openspec"
  chmod +x "$d/stub/openspec"
  : > "$d/repo/openspec/changes/add-thing/proposal.md"
  printf 'package main\n' > "$d/repo/src/main.go"
  ( cd "$d/repo" && git init -q . && git config user.email t@t && git config user.name t )
  # A second, symlinked route to the same repo. `git rev-parse --show-toplevel`
  # resolves symlinks and reports the PHYSICAL path; a shell that cd'd through
  # the link reports the LOGICAL one. Reaching the repo this way makes the two
  # differ deterministically on every platform, which is what the absolute-path
  # exemption rows need. (Relying on macOS's /tmp -> /private/tmp symlink would
  # reproduce there and silently pass on Linux.)
  ln -s repo "$d/alias"
  printf '%s' "$d"
}

reviewers() { # $1 = change dir, remaining args = reviewer names
  local dir="$1"; shift
  local f="$dir/REVIEWS.md" n
  : > "$f"
  for n in "$@"; do printf '## Reviewer: %s\n\nLooks fine.\n\n' "$n" >> "$f"; done
}

# ── the assertion ────────────────────────────────────────────────────────────
# Runs GATE inside a fixture with the stub on PATH and compares the exit code.
run_row() { # $1=desc $2=expected $3=fixture $4=payload $5...=gate args
  local desc="$1" want="$2" fx="$3" payload="$4"; shift 4
  local got
  got="$(
    cd "${ROW_CWD:-$fx/repo}" || exit 99
    printf '%s' "$payload" | PATH="$fx/stub:$PATH" bash "$GATE" "$@" >/dev/null 2>&1
    printf '%s' "$?"
  )"
  # Section B is only interpretable on a gate that fails OPEN on an unparsed
  # payload. A gate that fails CLOSED blocks whether or not it understood the
  # shape, so a `-> block` row passes for the wrong reason and would certify a
  # parser that never ran. Report those rows as inconclusive rather than
  # banking a false PASS.
  if [ "${ROW_NEEDS_FAILOPEN:-0}" = "1" ] && [ "$FAILS_OPEN" != "1" ]; then
    echo "  ????  $desc — inconclusive (gate fails closed; a block here does not prove the shape parsed)"
    inconclusive=$((inconclusive + 1))
    return
  fi
  if [ "$got" = "$want" ]; then
    echo "  PASS  $desc (exit $got)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $desc — expected $want, got $got"
    fail=$((fail + 1))
  fi
}

# Like run_row, but additionally asserts the gate's stderr does NOT contain a
# marker string. Use where the expected exit code is also what a broken gate
# produces for the wrong reason — the marker distinguishes the two paths.
run_row_stderr_lacks() { # $1=desc $2=expected $3=marker $4=fixture $5=payload $6...=gate args
  local desc="$1" want="$2" marker="$3" fx="$4" payload="$5"; shift 5
  local err got
  err="$(
    cd "$fx/repo" || exit 99
    printf '%s' "$payload" | bash "$GATE" "$@" 2>&1 >/dev/null
  )"
  got="$(
    cd "$fx/repo" || exit 99
    printf '%s' "$payload" | PATH="$fx/stub:$PATH" bash "$GATE" "$@" >/dev/null 2>&1
    printf '%s' "$?"
  )"
  if [ "$got" = "$want" ] && ! printf '%s' "$err" | grep -qF -- "$marker"; then
    echo "  PASS  $desc (exit $got)"
    pass=$((pass + 1))
  elif [ "$got" = "$want" ]; then
    echo "  FAIL  $desc — exit $got is correct but reached via '$marker' (no mode dispatch?)"
    fail=$((fail + 1))
  else
    echo "  FAIL  $desc — expected $want, got $got"
    fail=$((fail + 1))
  fi
}

# Payload envelopes, one per host runtime.
p_claude()  { printf '{"tool_input":{"file_path":"%s"}}' "$1"; }          # Claude PreToolUse
p_pi()      { printf '{"toolName":"edit","input":{"path":"%s"}}' "$1"; }  # pi tool_call
p_opencode(){ printf '{"args":{"filePath":"%s"}}' "$1"; }                 # opencode tool.execute.before
p_generic() { printf '{"path":"%s"}' "$1"; }

score_gate() {
  # Absolutise: every row runs after a `cd` into the fixture repo, so a relative
  # gate path would resolve to nothing there and score 127 on every row.
  GATE="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  local p0="$pass" f0="$fail" i0="$inconclusive"
  echo
  echo "═══ $GATE"
  echo "    ($(wc -l < "$GATE" | tr -d ' ') lines)"

  local fx

  echo "  ── A. Truth table (spec/18) ──"
  # No active change → allow.
  fx="$(make_fixture 0)"; rm -rf "$fx/repo/openspec/changes/add-thing"
  run_row "no active change -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # OpenSpec artifact write under an unsatisfied change → allow (author the change).
  fx="$(make_fixture 0)"
  run_row "openspec artifact write -> allow" 0 "$fx" \
    "$(p_claude openspec/changes/add-thing/proposal.md)"
  # ...but the exemption must be THIS repo's spec slot, not any path containing a
  # directory called `openspec`. A glob like */openspec/* exempts a source tree
  # with that name, and even paths outside the repo — a repo could then edit code
  # freely while the gate was unsatisfied.
  run_row "src/openspec/ is NOT exempt -> block"   2 "$fx" "$(p_claude src/openspec/app.ts)"
  run_row "/tmp/openspec/ is NOT exempt -> block"  2 "$fx" "$(p_claude /tmp/openspec/x.ts)"
  run_row "..-escape is NOT exempt -> block"       2 "$fx" "$(p_claude openspec/../src/app.ts)"
  # ...and it must survive an ABSOLUTE payload path. Hosts pass them — Claude
  # Code always does — so an exemption that only matches repo-relative paths
  # blocks the write of proposal.md itself, leaving a change that can never be
  # authored, reviewed, or unblocked. That is the deadlock the fail-open
  # posture exists to prevent, arrived at through the exemption instead.
  run_row "absolute artifact path -> allow" 0 "$fx" \
    "$(p_claude "$fx/repo/openspec/changes/add-thing/proposal.md")"
  # The same path reached through a symlink. $ROOT is physical (git resolves
  # it), the payload is logical, and a plain string-prefix test between them
  # fails — so this blocks even though it is the same file as the row above.
  ROW_CWD="$fx/alias"
  run_row "absolute artifact path via symlinked root -> allow" 0 "$fx" \
    "$(p_claude "$fx/alias/openspec/changes/add-thing/proposal.md")"
  # The bypass rows must hold through the symlink too, or a fix could buy the
  # two rows above by widening the exemption back out.
  run_row "src/openspec/ via symlinked root is NOT exempt -> block" 2 "$fx" \
    "$(p_claude "$fx/alias/src/openspec/app.ts")"
  ROW_CWD=""
  rm -rf "$fx"

  # Active change, validate green, no REVIEWS.md → block.
  fx="$(make_fixture 0)"
  run_row "active change, no REVIEWS.md -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Active change, validate fails → block.
  fx="$(make_fixture 1)"; reviewers "$fx/repo/openspec/changes/add-thing" claude codex
  run_row "validate FAILS (reviewed) -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Active change, validate green, >=2 reviewers → allow.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" claude codex
  run_row "validate green + 2 reviewers -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Documented escape hatch → allow.
  fx="$(make_fixture 0)"
  GSD_SKIP_REVIEWS=1 run_row "GSD_SKIP_REVIEWS=1 -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # The hatch bypasses the REVIEW clause, not validate. §18's row reads
  # unconditionally; this narrowing is a documented deviation (see the gate
  # header) and is pinned here so it cannot drift silently in either direction.
  fx="$(make_fixture 1)"
  GSD_SKIP_REVIEWS=1 run_row "GSD_SKIP_REVIEWS=1 + validate RED -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Fail OPEN on parse error — never on policy.
  fx="$(make_fixture 0)"
  local before="$fail"
  run_row "garbage stdin -> allow (fail-open)" 0 "$fx" 'not json {{{'
  run_row "empty stdin -> allow (fail-open)"   0 "$fx" ''
  [ "$fail" -eq "$before" ] && FAILS_OPEN=1 || FAILS_OPEN=0
  rm -rf "$fx"

  echo "  ── B. Payload shapes (code edit under an unsatisfied change -> block) ──"
  ROW_NEEDS_FAILOPEN=1
  # A shape the gate cannot parse yields no path, so it fails OPEN and the
  # gate silently does not enforce on that host. Driving a *code* edit (not an
  # artifact write) is what discriminates: under fail-open both exit 0.
  fx="$(make_fixture 0)"
  run_row "Claude   {tool_input.file_path} -> block" 2 "$fx" "$(p_claude src/main.go)"
  run_row "pi       {input.path}           -> block" 2 "$fx" "$(p_pi src/main.go)"
  run_row "opencode {args.filePath}        -> block" 2 "$fx" "$(p_opencode src/main.go)"
  run_row "generic  {path}                 -> block" 2 "$fx" "$(p_generic src/main.go)"
  rm -rf "$fx"
  ROW_NEEDS_FAILOPEN=0

  echo "  ── C. Modes: the agent-agnostic floor (advisory) ──"
  fx="$(make_fixture 0)"
  ( cd "$fx/repo" && git add src/main.go >/dev/null 2>&1 )
  run_row "--pre-commit, code staged, unsatisfied -> block" 1 "$fx" '' --pre-commit
  run_row "--ci, unsatisfied change -> fail"                1 "$fx" '' --ci
  rm -rf "$fx"

  # Same exemption hole, second entry point: a nested openspec/ dir must not
  # launder a staged file out of the pre-commit check.
  fx="$(make_fixture 0)"
  mkdir -p "$fx/repo/src/openspec"; printf 'x\n' > "$fx/repo/src/openspec/app.ts"
  ( cd "$fx/repo" && git add src/openspec/app.ts >/dev/null 2>&1 )
  run_row "--pre-commit, src/openspec/ staged -> block" 1 "$fx" '' --pre-commit
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  ( cd "$fx/repo" && git add openspec >/dev/null 2>&1 )
  # Discriminating: a gate with NO mode dispatch falls through to hook mode,
  # reads empty stdin, parses no path and fails open with 0 — passing this row
  # for the wrong reason. Assert it did not take the fail-open path.
  run_row_stderr_lacks "--pre-commit, only openspec staged -> allow" 0 'fail-open' "$fx" '' --pre-commit
  rm -rf "$fx"

  echo "  ── D. Reviewer counting ──"
  # Two headings naming the SAME reviewer is one independent reviewer.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" claude claude
  run_row "duplicate reviewer counts once -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A heading inside a fenced code block is an example, not a reviewer.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: claude\n\nReal.\n\n'
    printf 'Template for reviewers to copy:\n\n```markdown\n## Reviewer: codex\n```\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "fenced example is not a reviewer -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A prose section header is not a reviewer. With the colon optional,
  # "## Reviewers" parses to a reviewer literally named "s", so any REVIEWS.md
  # with a section header plus one real review clears a threshold of 2.
  fx="$(make_fixture 0)"
  printf '## Reviewers\n\n## Reviewer: claude\n\nReal.\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "prose '## Reviewers' is not a reviewer -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A `reviewers: [a, b]` YAML line carries no review content. If a fallback
  # honours it, it defeats dedup, fence-skipping and self-exclusion at once,
  # because such fallbacks run only when the hardened count is below threshold.
  fx="$(make_fixture 0)"
  printf '## Reviewer: claude\n\n## Reviewer: claude\n\nreviewers: [claude, claude]\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "YAML 'reviewers:' does not satisfy -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  printf '## Reviewer: claude\n\n```yaml\nreviewers: [a, b]\n```\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "fenced YAML 'reviewers:' does not satisfy -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  echo "  ── E. Self-review exclusion (OPENSPEC_GATE_SELF; advisory) ──"
  # The implementing host reviewing its own change is not an independent second
  # opinion. A gate that counts it disagrees with the §02 evidence verifier,
  # which rejects it — the ADR-0018 drift pattern, inside the tooling.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" pi claude
  OPENSPEC_GATE_SELF=pi run_row "self + 1 other = 1 independent -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" pi claude codex
  OPENSPEC_GATE_SELF=pi run_row "self + 2 others = 2 independent -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Anchored: a reviewer whose name merely starts with the host's is not swallowed.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" pi pilot-crew claude
  OPENSPEC_GATE_SELF=pi run_row "exclusion is anchored, not a prefix -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  local pd=$((pass - p0)) fd=$((fail - f0)) idd=$((inconclusive - i0))
  echo "  ── $pd passed, $fd failed, $idd inconclusive of $((pd + fd + idd)) rows"
}

# ── entry point ──────────────────────────────────────────────────────────────
if [ "${1:-}" = "--family" ]; then
  FAMILY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  set --
  for c in \
    "$FAMILY/agenticapps-workflow-core/reference-implementations/openspec-change-gate/openspec-change-gate.sh" \
    "$FAMILY/claude-workflow/bin/openspec-change-gate.sh" \
    "$FAMILY/codex-workflow/bin/openspec-change-gate.sh" \
    "$FAMILY/opencode-workflow/bin/openspec-change-gate.sh" \
    "$FAMILY/pi-agentic-apps-workflow/bin/openspec-change-gate.sh" \
    "$HOME/.agenticapps/bin/openspec-change-gate.sh"
  do [ -f "$c" ] && set -- "$@" "$c"; done
fi

[ "$#" -gt 0 ] || { echo "usage: $0 <gate-script> [...] | --family" >&2; exit 2; }

for g in "$@"; do
  [ -f "$g" ] || { echo "  SKIP  $g (not found)"; continue; }
  score_gate "$g"
done

echo
echo "═══ TOTAL: $pass passed, $fail failed, $inconclusive inconclusive"
[ "$fail" -eq 0 ]
