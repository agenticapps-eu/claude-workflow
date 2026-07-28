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

# A measurement tool must not inherit state from the thing it measures. The
# README's vendoring steps tell hosts to export OPENSPEC_GATE_SELF (so the
# host's own reviews are excluded) and then to run this harness — do both in
# one shell and a fully conformant gate scores one row short: the two-reviewer
# row seeds `claude` and `codex`, and an ambient OPENSPEC_GATE_SELF=codex makes
# the gate correctly drop one, leaving one reviewer and a block. The row fails
# for a gate that is behaving exactly as specified.
#
# Section E sets this per-row (`OPENSPEC_GATE_SELF=pi run_row ...`), which is a
# command-scoped assignment and unaffected by the unset here. So the harness
# never needs the ambient value, and clearing it is free.
unset OPENSPEC_GATE_SELF

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
  # `outside` is a sibling of the repo, not inside it — the destination for the
  # symlink-escape rows, which need somewhere outside $ROOT that actually exists
  # so the kernel can resolve a link into it.
  mkdir -p "$d/stub" "$d/repo/openspec/changes/add-thing" "$d/repo/src" "$d/outside"
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

# Same, but each reviewer is given a verdict: `name:A` approves, `name:R`
# requests changes, a bare `name` writes no verdict line at all. The third form
# matters — a reviewer that ignored the producer's format said nothing, and must
# never be reported as objecting.
reviewers_with_verdicts() { # $1 = change dir, remaining args = name[:A|:R]
  local dir="$1"; shift
  local f="$dir/REVIEWS.md" spec n v
  : > "$f"
  for spec in "$@"; do
    n="${spec%%:*}"; v="${spec#"$n"}"; v="${v#:}"
    printf '## Reviewer: %s\n\n' "$n" >> "$f"
    case "$v" in
      A) printf 'VERDICT: APPROVE\n\nLooks fine.\n\n' >> "$f" ;;
      R) printf 'VERDICT: REQUEST-CHANGES\n\n- something is wrong\n\n' >> "$f" ;;
      *) printf 'Some prose with no verdict line.\n\n' >> "$f" ;;
    esac
  done
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

# Mirror of run_row_stderr_lacks: asserts the marker IS present. Used for the
# verdict NOTE, where the exit code alone cannot distinguish "allowed and told
# the operator about an outstanding rejection" from "allowed silently" — both
# are exit 0, and silence was the defect.
run_row_stderr_has() { # $1=desc $2=expected $3=marker $4=fixture $5=payload $6...=gate args
  local desc="$1" want="$2" marker="$3" fx="$4" payload="$5"; shift 5
  local err got
  err="$(
    cd "$fx/repo" || exit 99
    printf '%s' "$payload" | PATH="$fx/stub:$PATH" bash "$GATE" "$@" 2>&1 >/dev/null
  )"
  got="$(
    cd "$fx/repo" || exit 99
    printf '%s' "$payload" | PATH="$fx/stub:$PATH" bash "$GATE" "$@" >/dev/null 2>&1
    printf '%s' "$?"
  )"
  if [ "$got" = "$want" ] && printf '%s' "$err" | grep -qF -- "$marker"; then
    echo "  PASS  $desc (exit $got)"
    pass=$((pass + 1))
  elif [ "$got" = "$want" ]; then
    echo "  FAIL  $desc — exit $got correct but stderr lacked '$marker'"
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

  # A symlink INSIDE openspec/ followed by `..`. The bare `..` row above is not
  # sufficient to pin this: a gate that collapses `..` textually before
  # resolving passes that row and fails this one, because the textual pass and
  # the kernel disagree about where `openspec/out/..` lands.
  #
  #   openspec/out -> <outside the repo>
  #   textual first -> $ROOT/openspec/victim  => EXEMPT, and the bytes leave the repo
  #   kernel        -> <outside>/../victim
  #
  # The exemption must be decided by the kernel's answer, so this row demands
  # physical resolution ahead of any `..` handling.
  ln -s "$fx/outside" "$fx/repo/openspec/out"
  run_row "symlink-then-.. escape is NOT exempt -> block" 2 "$fx" \
    "$(p_claude 'openspec/out/../victim')"
  # ...and the same shape where the escape sits below a directory that does not
  # exist yet, so nothing can be resolved and the `..` survives into the tail.
  # An unresolvable path must not be exempt — it string-matches the openspec
  # prefix while resolving outside it.
  run_row "unresolvable .. below openspec/ is NOT exempt -> block" 2 "$fx" \
    "$(p_claude 'openspec/nope/../../src/app.ts')"

  # An artifact path that IS a symlink pointing at code. Declining to resolve
  # the final component exempts the write and the writer follows the link,
  # truncating the target under an unsatisfied change. The exemption has to be
  # decided about the destination, not the name used to reach it.
  ln -s "$fx/repo/src/main.go" "$fx/repo/openspec/changes/add-thing/design.md"
  run_row "symlinked artifact pointing at code is NOT exempt -> block" 2 "$fx" \
    "$(p_claude 'openspec/changes/add-thing/design.md')"
  rm -rf "$fx"

  # The Write-target case must survive the above: a genuine artifact that does
  # not exist yet is not a symlink, cannot be resolved, and must stay exempt —
  # otherwise proposal.md can never be authored and the change deadlocks.
  fx="$(make_fixture 0)"
  run_row "not-yet-existing artifact -> allow" 0 "$fx" \
    "$(p_claude 'openspec/changes/add-thing/design.md')"
  rm -rf "$fx"

  # Active change, validate green, no REVIEWS.md → block.
  fx="$(make_fixture 0)"
  run_row "active change, no REVIEWS.md -> block" 2 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # ...and the same decision must hold from a SUBDIRECTORY. A gate that locates
  # `openspec/changes` relative to $PWD instead of `git rev-parse
  # --show-toplevel` finds nothing from below the root, concludes there is no
  # active change, and allows the edit — while logging a line that reads like a
  # correct decision. A PreToolUse hook inherits the session's cwd, which is
  # wherever the user happens to be, so this is the common case rather than the
  # exotic one. Witness: the pre-adoption codex-workflow copy returned 0 here.
  fx="$(make_fixture 0)"; mkdir -p "$fx/repo/sub/dir"
  ROW_CWD="$fx/repo/sub/dir"
  run_row "active change, evaluated from a subdirectory -> block" 2 "$fx" "$(p_claude src/main.go)"
  ROW_CWD=""
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
  # Brace-bearing garbage (above) is not discriminating: a gate whose JSON
  # branch is guarded on `{` skips it and reaches a `TOOL<TAB>PATH` fallback,
  # which on whitespace-only input splits out a plausible path and proceeds to
  # POLICY — blocking on a payload it never understood. That is a fail-CLOSED
  # parse error, the one posture §18 forbids. Only brace-free garbage reaches
  # the fallback, so this row is what separates the two. Witness: the pre-
  # adoption codex-workflow copy returned 2 here where canonical returns 0.
  run_row "brace-free garbage stdin -> allow (fail-open)" 0 "$fx" 'not json at all'
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

  echo "  ── F. Verdict reporting (quorum, not approval; advisory) ──"
  # §18's truth table keys `allow` on the reviewer COUNT and carries no verdict
  # term, so REQUEST-CHANGES must NOT block — a gate that blocked here would be
  # non-conformant. But the producer asks every reviewer for a verdict, and
  # before gate 1.3.0 nothing read the answer: two rejections opened the gate in
  # silence. These rows pin both halves — still allow, but say so.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" gemini:R codex:R
  run_row_stderr_has "2x REQUEST-CHANGES still allows (quorum, not approval)" 0 \
    "NOTE" "$fx" "$(p_claude src/main.go)"
  run_row_stderr_has "...and names every objecting reviewer" 0 \
    "gemini, codex" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Silence on the happy path. A NOTE on every allow is noise that trains the
  # operator to ignore the one that matters.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" gemini:A codex:A
  run_row_stderr_lacks "2x APPROVE allows with no NOTE" 0 "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" gemini:A codex:R
  run_row_stderr_has "mixed verdicts name only the objector" 0 \
    "but codex requested changes" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A reviewer who ignored the producer's format said nothing. Reporting them as
  # objecting would manufacture an objection out of a formatting miss.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" gemini codex
  run_row_stderr_lacks "no verdict line is not a rejection" 0 "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Same fence rule as reviewer counting: a REVIEWS.md quoting the verdict
  # vocabulary inside ``` is documentation, not a rejection.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n'
    printf '## Reviewer: codex\n\nVERDICT: APPROVE\n\n'
    printf 'Reviewers may reply:\n\n```\nVERDICT: REQUEST-CHANGES\n```\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_lacks "fenced verdict is not a rejection" 0 "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Reporting must agree with counting about who is a reviewer. If the excluded
  # self could raise a NOTE, the gate would report on an opinion it refuses to
  # count — the same disagreement OPENSPEC_GATE_SELF exists to prevent.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" pi:R claude:A codex:A
  OPENSPEC_GATE_SELF=pi run_row_stderr_lacks "excluded self's rejection is not reported" 0 \
    "NOTE" "$fx" "$(p_claude src/main.go)"
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
