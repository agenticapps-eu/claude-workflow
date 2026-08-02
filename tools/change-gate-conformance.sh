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

# ── target screening (capability: conformance-harness-reporting) ─────────────
# A harness must never exit 0 having scored nothing, and must never silently
# skip a target a caller named. `[ -f ]` alone is not enough to decide whether
# a target can be scored:
#
#   * a ZERO-BYTE file passes `[ -f ]`, and an empty script exits 0 on every
#     invocation — so it passes every `expect 0` row and fails only the
#     `expect 2` rows. Partial credit, manufactured out of a file containing no
#     code. This is what a truncated download or a half-finished
#     materialise step leaves behind.
#   * a DIRECTORY passes `[ -s ]`, which reports a non-zero size for one.
#   * an UNREADABLE file is not a false-green risk — the shell refuses it with
#     126 and the rows fail loudly — but it is illegible: the operator is shown
#     forty failing rows when the fault is a file mode. NOTE this check is a
#     no-op under root, where `test -r` is true regardless of mode.
#
# Sets REASON and returns 1 when the target cannot be scored. Precedence is
# fixed — not-found, not-a-regular-file, empty, unreadable — so the report is
# reproducible across platforms whose `test` builtins short-circuit differently.
harness_screen_target() { # $1 = path
  REASON=""
  if [ -L "$1" ] && [ ! -e "$1" ]; then REASON="not a regular file (dangling symlink)"; return 1; fi
  if [ ! -e "$1" ]; then REASON="not found"; return 1; fi
  if [ ! -f "$1" ]; then REASON="not a regular file"; return 1; fi
  if [ ! -s "$1" ]; then REASON="empty"; return 1; fi
  if [ ! -r "$1" ]; then REASON="unreadable"; return 1; fi
  return 0
}

# Renders a path inert for printing. A path is attacker-influenceable in the
# general case, and a harness whose output can be forged with an embedded
# newline can be made to print a line that reads like a PASS.
harness_safe_label() { # $1 = path
  printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '?'
}

# Reports a target that could not be scored, distinguishably from one that was
# scored and failed rows — both make the run red, and they call for different
# responses.
harness_report_unscoreable() { # $1 = label, $2 = reason
  echo "  UNSCOREABLE  $1 — $2"
}

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
  # tasks.md is part of a real change and the tasks-drift rows need it to exist
  # before they can mean anything. Without it those rows scored green against a
  # digest of nothing — which is the failure mode they were added to catch.
  printf '# Tasks\n\n- [ ] 1.1 do it\n' > "$d/repo/openspec/changes/add-thing/tasks.md"
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

# An INDEPENDENT implementation of the digest contract, written from the spec
# text rather than by calling the gate's own function. A harness that built its
# fixtures with the implementation's logic could not detect a wrong
# implementation — both sides would be wrong together. Agreement between this
# and the gate is therefore a real assertion, and it is the same cross-check
# task 7.10 requires of the producer.
fixture_digest() { # $1 = change dir
  local d="$1" ser canon p plen clen hex
  ser="$(mktemp)"
  # proposal.md, design.md, then every specs/**/*.md, ordered bytewise.
  {
    [ -e "$d/proposal.md" ] && printf 'proposal.md\0'
    [ -e "$d/design.md" ]   && printf 'design.md\0'
    [ -d "$d/specs" ] && find "$d/specs" -name '*.md' -print0 2>/dev/null |
      while IFS= read -r -d '' q; do printf '%s\0' "${q#"$d"/}"; done
  } | LC_ALL=C sort -z | while IFS= read -r -d '' p; do
    canon="$(mktemp)"
    LC_ALL=C tr -d '\r' < "$d/$p" > "$canon"
    [ -s "$canon" ] && [ "$(LC_ALL=C tail -c1 "$canon" | od -An -tu1 | tr -d ' \n')" != "10" ] && printf '\n' >> "$canon"
    plen=$(printf '%s' "$p" | LC_ALL=C wc -c | tr -d ' ')
    clen=$(LC_ALL=C wc -c < "$canon" | tr -d ' ')
    { printf '%s\n%s\n%s\n' "$plen" "$p" "$clen"; cat "$canon"; } >> "$ser"
    rm -f "$canon"
  done
  hex="$(LC_ALL=C shasum -a 256 "$ser" 2>/dev/null | awk '{print $1}')"
  [ -n "$hex" ] || hex="$(LC_ALL=C sha256sum "$ser" 2>/dev/null | awk '{print $1}')"
  rm -f "$ser"
  printf 'sha256:%s' "$hex"
}

# Digest over tasks.md alone, under the same framing as one member of the set
# above. Independently written rather than shelling out to the gate: a fixture
# that computes its expected value with the code under test can only ever agree
# with it.
fixture_tasks_digest() { # $1 = change dir
  local d="$1" ser canon plen clen hex p=tasks.md
  ser="$(mktemp)"; canon="$(mktemp)"
  LC_ALL=C tr -d '\r' < "$d/$p" > "$canon"
  [ -s "$canon" ] && [ "$(LC_ALL=C tail -c1 "$canon" | od -An -tu1 | tr -d ' \n')" != "10" ] && printf '\n' >> "$canon"
  plen=$(printf '%s' "$p" | LC_ALL=C wc -c | tr -d ' ')
  clen=$(LC_ALL=C wc -c < "$canon" | tr -d ' ')
  { printf '%s\n%s\n%s\n' "$plen" "$p" "$clen"; cat "$canon"; } >> "$ser"
  hex="$(LC_ALL=C shasum -a 256 "$ser" 2>/dev/null | awk '{print $1}')"
  [ -n "$hex" ] || hex="$(LC_ALL=C sha256sum "$ser" 2>/dev/null | awk '{print $1}')"
  rm -f "$ser" "$canon"
  printf 'sha256:%s' "$hex"
}

# Appends a well-formed trailer. Gate 1.5.0 counts ZERO reviewers without one,
# so every fixture that expects its reviewers to count needs this — which is
# precisely the fleet-wide migration the change schedules, rehearsed here.
seed_trailer() { # $1 = change dir  [$2 = implementing host]  [$3 = digest override]
  local dir="$1" host="${2:-pi}" dg="${3:-}"
  [ -n "$dg" ] || dg="$(fixture_digest "$dir")"
  {
    printf '<!-- openspec-review-trailer v1\n'
    printf 'implementing-host: %s\n' "$host"
    printf 'digest: %s\n' "$dg"
    printf 'producer-version: 1.1.0\n'
    printf -- '-->\n'
  } >> "$dir/REVIEWS.md"
}

# As reviewers(), but the trailer also carries a tasks-digest matching the
# fixture's tasks.md as it stands at seeding time. A row that then edits
# tasks.md is the drift case; one that does not is the quiet case.
reviewers_td() { # $1 = change dir, remaining args = reviewer names
  local dir="$1"; shift
  local f="$dir/REVIEWS.md" n
  : > "$f"
  for n in "$@"; do printf '## Reviewer: %s\n\nVERDICT: APPROVE\n\nLooks fine.\n\n' "$n" >> "$f"; done
  {
    printf '<!-- openspec-review-trailer v1\n'
    printf 'implementing-host: pi\n'
    printf 'digest: %s\n' "$(fixture_digest "$dir")"
    printf 'producer-version: 1.2.0\n'
    printf 'tasks-digest: %s\n' "$(fixture_tasks_digest "$dir")"
    printf -- '-->\n'
  } >> "$f"
}

# As reviewers(), but the implementing host is declared explicitly in the
# trailer — which is where gate 1.5.0+ reads it from, and the only way to
# exercise self-exclusion at all.
reviewers_host() { # $1 = change dir, $2 = implementing host, rest = reviewer names
  local dir="$1" host="$2"; shift 2
  local f="$dir/REVIEWS.md" n
  : > "$f"
  for n in "$@"; do printf '## Reviewer: %s\n\nVERDICT: APPROVE\n\nLooks fine.\n\n' "$n" >> "$f"; done
  seed_trailer "$dir" "$host"
}

reviewers() { # $1 = change dir, remaining args = reviewer names
  local dir="$1"; shift
  local f="$dir/REVIEWS.md" n
  : > "$f"
  # A verdict AND a body: gate 1.5.0 counts nothing that lacks either, and
  # these rows exist to test counting, not to test the substance rule.
  for n in "$@"; do printf '## Reviewer: %s\n\nVERDICT: APPROVE\n\nLooks fine.\n\n' "$n" >> "$f"; done
  seed_trailer "$dir"
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
  seed_trailer "$dir"
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
  # $2 is a stable logical label supplied by roster mode. Without it the
  # heading printed the resolved absolute path on every entry, which put $HOME
  # and the workspace root into the log regardless of how the coverage line was
  # rendered — so logicalising the coverage line alone bought nothing.
  local heading="${2:-$(harness_safe_label "$GATE")}"
  echo
  echo "═══ $heading"
  echo "    ($(wc -l < "$GATE" | tr -d ' ') lines)"

  local fx

  echo "  ── A. Truth table (spec/18) ──"
  # No active change → allow.
  fx="$(make_fixture 0)"; rm -rf "$fx/repo/openspec/changes/add-thing"
  run_row "no active change -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # OpenSpec artifact write under an unsatisfied change → allow (author the change).
  #
  # THE LEVER IS validate-RED, not "unreviewed". These rows test the openspec/
  # PATH EXEMPTION, and they need the gate to be blocking for a reason so that
  # "exempt" and "not exempt" are distinguishable. Since 2.0.0 an unreviewed
  # change no longer blocks, so a fixture built that way would allow everything
  # and every row here would pass without testing anything.
  fx="$(make_fixture 1)"
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

  # Active change, validate green, no REVIEWS.md → ALLOW, with a note.
  # This row is the 2.0.0 change itself. It asserted `block` for the whole life
  # of the gate; reviewing a plan is worth doing, and refusing to let anyone
  # write code until it has been done is a different claim that cost three
  # rollbacks and a six-repository outage without preventing anything anyone
  # can name.
  fx="$(make_fixture 0)"
  run_row_stderr_has "active change, no REVIEWS.md -> ALLOW with a note" 0 \
    "has no plan review yet" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # ...and the same decision must hold from a SUBDIRECTORY. A gate that locates
  # `openspec/changes` relative to $PWD instead of `git rev-parse
  # --show-toplevel` finds nothing from below the root, concludes there is no
  # active change, and allows the edit — while logging a line that reads like a
  # correct decision. A PreToolUse hook inherits the session's cwd, which is
  # wherever the user happens to be, so this is the common case rather than the
  # exotic one. Witness: the pre-adoption codex-workflow copy returned 0 here.
  fx="$(make_fixture 1)"; mkdir -p "$fx/repo/sub/dir"
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

  echo "  ── B. Payload shapes (code edit under a validate-RED change -> block) ──"
  ROW_NEEDS_FAILOPEN=1
  # A shape the gate cannot parse yields no path, so it fails OPEN and the
  # gate silently does not enforce on that host. Driving a *code* edit (not an
  # artifact write) is what discriminates: under fail-open both exit 0.
  #
  # validate-RED is the lever, for the reason given in section A.
  fx="$(make_fixture 1)"
  run_row "Claude   {tool_input.file_path} -> block" 2 "$fx" "$(p_claude src/main.go)"
  run_row "pi       {input.path}           -> block" 2 "$fx" "$(p_pi src/main.go)"
  run_row "opencode {args.filePath}        -> block" 2 "$fx" "$(p_opencode src/main.go)"
  run_row "generic  {path}                 -> block" 2 "$fx" "$(p_generic src/main.go)"
  rm -rf "$fx"
  ROW_NEEDS_FAILOPEN=0

  echo "  ── C. Modes: the agent-agnostic floor (advisory) ──"
  # validate-RED is the lever here too. Before 2.0.0 these rows used an
  # unreviewed change; a missing review no longer blocks a commit or fails CI,
  # which is the whole point of 2.0.0, so the rows would have passed vacuously.
  fx="$(make_fixture 1)"
  ( cd "$fx/repo" && git add src/main.go >/dev/null 2>&1 )
  run_row "--pre-commit, code staged, validate RED -> block" 1 "$fx" '' --pre-commit
  run_row "--ci, validate RED -> fail"                       1 "$fx" '' --ci
  rm -rf "$fx"

  # And the converse, which is the behaviour change: an UNREVIEWED change with
  # validate green must not block a commit or fail CI.
  fx="$(make_fixture 0)"
  ( cd "$fx/repo" && git add src/main.go >/dev/null 2>&1 )
  run_row "--pre-commit, code staged, unreviewed -> ALLOW" 0 "$fx" '' --pre-commit
  run_row "--ci, unreviewed change -> PASS"                0 "$fx" '' --ci
  rm -rf "$fx"

  # Same exemption hole, second entry point: a nested openspec/ dir must not
  # launder a staged file out of the pre-commit check.
  fx="$(make_fixture 1)"
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
  # These rows assert the COUNTING hardening, not the floor. 1.4.0 moved the
  # default floor to 1, so they pin MIN_REVIEWERS=2 explicitly — otherwise a
  # single valid reviewer allows and the row proves nothing about dedup or
  # fence-skipping.
  # Two headings naming the SAME reviewer is one independent reviewer.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" claude claude
  MIN_REVIEWERS=2 run_row_stderr_has "duplicate reviewer counts once -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A heading inside a fenced code block is an example, not a reviewer.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: claude\n\nReal.\n\n'
    printf 'Template for reviewers to copy:\n\n```markdown\n## Reviewer: codex\n```\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  # Without a trailer the count short-circuits to zero and the row passes even
  # if the fenced heading DOES count — it was vacuous before 2.0.0 too.
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  MIN_REVIEWERS=2 run_row_stderr_has "fenced example is not a reviewer -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A prose section header is not a reviewer. With the colon optional,
  # "## Reviewers" parses to a reviewer literally named "s", so any REVIEWS.md
  # with a section header plus one real review clears a threshold of 2.
  fx="$(make_fixture 0)"
  printf '## Reviewers\n\n## Reviewer: claude\n\nReal.\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  MIN_REVIEWERS=2 run_row_stderr_has "prose '## Reviewers' is not a reviewer -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A `reviewers: [a, b]` YAML line carries no review content. If a fallback
  # honours it, it defeats dedup, fence-skipping and self-exclusion at once,
  # because such fallbacks run only when the hardened count is below threshold.
  fx="$(make_fixture 0)"
  printf '## Reviewer: claude\n\n## Reviewer: claude\n\nreviewers: [claude, claude]\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  MIN_REVIEWERS=2 run_row_stderr_has "YAML 'reviewers:' does not satisfy -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  printf '## Reviewer: claude\n\n```yaml\nreviewers: [a, b]\n```\n' \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  MIN_REVIEWERS=2 run_row_stderr_has "fenced YAML 'reviewers:' does not satisfy -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  echo "  ── E. Self-review exclusion (declared in the trailer) ──"
  # The implementing host reviewing its own change is not an independent second
  # opinion. A gate that counts it disagrees with the §02 evidence verifier,
  # which rejects it — the ADR-0018 drift pattern, inside the tooling.
  #
  # THIS SECTION WAS ENTIRELY VACUOUS and is rewritten. Two independent reasons,
  # either alone sufficient:
  #   * every row prefixed OPENSPEC_GATE_SELF=pi, which gate 1.5.0 ignores. The
  #     exclusion that actually fired came from seed_trailer's DEFAULT host,
  #     which happened to be `pi` too — so the rows passed while exercising a
  #     different mechanism than their names and comments described.
  #   * the self-reviewer was named `pi`, which is a HOST but not a reviewer
  #     vendor. The gate drops any section whose name is outside
  #     claude|codex|gemini|opencode before exclusion is ever consulted, so
  #     nothing was excluded — the section was never counted in the first place.
  # Verified: with the host set to `codex` and no env var, the old fixtures
  # produced an identical result with exclusion never reached.
  #
  # The host is now declared in the trailer, where the gate reads it, and is a
  # name that genuinely counts as a reviewer — so removing the exclusion changes
  # the outcome, which is the only thing that makes these rows worth running.
  fx="$(make_fixture 0)"; reviewers_host "$fx/repo/openspec/changes/add-thing" claude claude gemini
  MIN_REVIEWERS=2 run_row_stderr_has "self + 1 other = 1 independent -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"; reviewers_host "$fx/repo/openspec/changes/add-thing" claude claude gemini codex
  MIN_REVIEWERS=2 run_row "self + 2 others = 2 independent -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Control: the SAME three sections with a host that reviewed nothing. If this
  # did not allow where the first row blocks, the rows above would be measuring
  # the floor rather than the exclusion.
  fx="$(make_fixture 0)"; reviewers_host "$fx/repo/openspec/changes/add-thing" opencode claude gemini
  MIN_REVIEWERS=2 run_row "host that reviewed nothing excludes nothing -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Anchoring is NOT tested here, and pretending otherwise was the old row's
  # sin. No name in the closed reviewer set is a prefix of another, so the
  # property has no expressible fixture; the closed set is what enforces it,
  # and `## Reviewer: codex-2` is covered by the name-filter rows above.

  echo "  ── E2. Reviewer floor vs preference (spec 1.1.0) ──"
  # 1.4.0: MUST >= 1 (blocks), SHOULD >= 2 (reports). The gap must never block.
  fx="$(make_fixture 0)"   # zero reviewers
  run_row_stderr_has "0 reviewers -> noted, never blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" gemini
  run_row_stderr_has "1 reviewer -> ALLOW, and says 2 is preferred" 0 \
    "2 preferred" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" gemini codex
  run_row_stderr_lacks "2 reviewers -> allow, no shortfall note" 0 \
    "preferred" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # The old hard floor stays available for a repo that wants it.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" gemini
  MIN_REVIEWERS=2 run_row_stderr_has "MIN_REVIEWERS=2 raises what is REPORTED, not what blocks" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Preference is reporting only — raising it must never turn into a block.
  fx="$(make_fixture 0)"; reviewers "$fx/repo/openspec/changes/add-thing" gemini codex
  PREFERRED_REVIEWERS=5 run_row "raising PREFERRED alone never blocks" 0 "$fx" "$(p_claude src/main.go)"
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
  # Under 1.5.0 a verdictless section counts zero, so the row pairs one real
  # review with one silent vendor: the floor is met by the reviewer who spoke,
  # and the one who did not is neither counted nor reported as objecting.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" gemini:A codex
  run_row_stderr_lacks "no verdict line is not a rejection" 0 "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Same fence rule as reviewer counting: a REVIEWS.md quoting the verdict
  # vocabulary inside ``` is documentation, not a rejection.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- a finding\n\n'
    printf '## Reviewer: codex\n\nVERDICT: APPROVE\n\n- another finding\n\n'
    printf 'Reviewers may reply:\n\n```\nVERDICT: REQUEST-CHANGES\n```\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_lacks "fenced verdict is not a rejection" 0 "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Markdown emphasis around the verdict label. 1.3.0 anchored on a bare
  # `VERDICT:` and missed `**VERDICT: REQUEST-CHANGES**` — exactly what opencode
  # wrote on the first real run after 1.3.0 shipped. Under-reporting a genuine
  # rejection is the same class of failure as inventing one.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- a finding\n\n'
    printf '## Reviewer: opencode\n\n**VERDICT: REQUEST-CHANGES**\n\n- a finding\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_has "bolded verdict is still a verdict" 0 \
    "but opencode requested changes" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Underscore emphasis, and emphasis on the label only.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- a finding\n\n'
    printf '## Reviewer: codex\n\n__VERDICT: REQUEST-CHANGES__\n\n- a finding\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_has "underscore-emphasised verdict counts" 0 \
    "but codex requested changes" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Emphasis must not turn a mid-prose mention into a rejection: still anchored.
  fx="$(make_fixture 0)"
  {
    printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- a finding\n\n'
    printf '## Reviewer: codex\n\nVERDICT: APPROVE\n\nI nearly said **VERDICT: REQUEST-CHANGES** but did not.\n'
  } > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_lacks "emphasised mention mid-prose is not a rejection" 0 \
    "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Reporting must agree with counting about who is a reviewer. If the excluded
  # self could raise a NOTE, the gate would report on an opinion it refuses to
  # count — the same disagreement OPENSPEC_GATE_SELF exists to prevent.
  fx="$(make_fixture 0)"
  reviewers_with_verdicts "$fx/repo/openspec/changes/add-thing" pi:R claude:A codex:A
  OPENSPEC_GATE_SELF=pi run_row_stderr_lacks "excluded self's rejection is not reported" 0 \
    "NOTE" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # ── F. Evidence integrity (gate 1.5.0) ─────────────────────────────────────
  # Spec 1.3.0 §18's counting terms, asserted at the GATE. The producer harness
  # scores the same rules on the writing side; these score the reading side,
  # because the two are separate processes and only agreement makes the
  # artifact between them meaningful.
  echo "  ── F. Evidence integrity (spec 1.3.0 terms) ──"

  # A verdict with no body. Live on 2026-07-29T07:52:54Z.
  fx="$(make_fixture 0)"
  { printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n'
    printf '## Reviewer: codex\n\nVERDICT: APPROVE\n\n'; } \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_has "verdicts with no body count zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Conflicting verdicts in one section are malformed, not silently resolved.
  fx="$(make_fixture 0)"
  { printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- fine\n\n'
    printf '## Reviewer: codex\n\nVERDICT: APPROVE\n\n- ok\n\nVERDICT: REQUEST-CHANGES\n\n- not ok\n\n'; } \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  MIN_REVIEWERS=2 run_row_stderr_has "a section with conflicting verdicts does not count" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # A vendor's own subheading must not truncate the section above its verdict.
  fx="$(make_fixture 0)"
  { printf '## Reviewer: gemini\n\n### Findings\n\nVERDICT: REQUEST-CHANGES\n\n- a real issue\n\n'; } \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row "a verdict below '### Findings' still counts -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # An arbitrary reviewer name evades exclusion if names are not closed.
  fx="$(make_fixture 0)"
  { printf '## Reviewer: codex-2\n\nVERDICT: APPROVE\n\n- looks fine\n\n'; } \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  seed_trailer "$fx/repo/openspec/changes/add-thing" codex
  run_row_stderr_has "an unrecognised reviewer name does not count -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Trailer: absent, duplicated, non-final, and malformed VALUES all fail closed.
  fx="$(make_fixture 0)"
  { printf '## Reviewer: gemini\n\nVERDICT: APPROVE\n\n- fine\n\n'; } \
    > "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_has "no trailer counts zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  seed_trailer "$fx/repo/openspec/changes/add-thing"
  run_row_stderr_has "two trailers count zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  printf 'trailing prose after the trailer\n' >> "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_has "a non-final trailer counts zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  printf '\n\n  \n' >> "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "trailing blank lines still count as final -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  sed -i.bak 's/^digest: sha256:.*/digest: sha256:NOTHEX/' "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_has "a malformed digest VALUE counts zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  sed -i.bak 's/^producer-version: .*/producer-version: one/' "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_has "a non-semver producer-version counts zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  sed -i.bak 's/^implementing-host: .*/implementing-host: claude, codex/' "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row_stderr_has "a space in the host list counts zero -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # `pi` is a host with no reviewer arm and MUST be nameable, or one of the four
  # hosts can never produce countable evidence.
  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  sed -i.bak 's/^implementing-host: .*/implementing-host: pi/' "$fx/repo/openspec/changes/add-thing/REVIEWS.md"
  run_row "'pi' is a valid implementing host -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Staleness: the review must stop counting when the artifacts move.
  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  printf 'amended after review\n' >> "$fx/repo/openspec/changes/add-thing/proposal.md"
  run_row_stderr_has "an amended change stales its review -> noted, not blocked" 0 \
    "not blocking" "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # …but ticking a checkbox must not, or implementation deadlocks the gate.
  fx="$(make_fixture 0)"
  reviewers "$fx/repo/openspec/changes/add-thing" gemini
  printf '# Tasks\n\n- [x] 1.1 done\n' > "$fx/repo/openspec/changes/add-thing/tasks.md"
  run_row "ticking a checkbox does not stale the review -> allow" 0 "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # The advisory tasks-drift report. The row above pinned only the ALLOW half of
  # the spec's scenario, which the gate satisfied by never reading the field at
  # all — 66/66 green over a normative SHALL with no implementation behind it.
  # These pin the half that was missing: it must SAY so.
  local c
  fx="$(make_fixture 0)"; c="$fx/repo/openspec/changes/add-thing"
  reviewers_td "$c" gemini
  printf '# Tasks\n\n- [ ] 1.1 do it\n- [ ] 1.2 add a debug endpoint\n' > "$c/tasks.md"
  run_row_stderr_has "a task added after review is REPORTED" 0 \
    'tasks.md has changed since review' "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  fx="$(make_fixture 0)"; c="$fx/repo/openspec/changes/add-thing"
  reviewers_td "$c" gemini
  run_row_stderr_lacks "an untouched tasks.md is not reported" 0 \
    'tasks.md has changed' "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  # Absent field is silence, not a warning: the key is optional, and every
  # REVIEWS.md written before producer 1.1.0 lacks it.
  fx="$(make_fixture 0)"; c="$fx/repo/openspec/changes/add-thing"
  reviewers "$c" gemini
  printf '# Tasks\n\n- [ ] 1.9 something else entirely\n' > "$c/tasks.md"
  run_row_stderr_lacks "no tasks-digest recorded -> no report" 0 \
    'tasks.md has changed' "$fx" "$(p_claude src/main.go)"
  rm -rf "$fx"

  local pd=$((pass - p0)) fd=$((fail - f0)) idd=$((inconclusive - i0))
  echo "  ── $pd passed, $fd failed, $idd inconclusive of $((pd + fd + idd)) rows"
}

# ── entry point ──────────────────────────────────────────────────────────────
USAGE="usage: $0 <gate-script> [...] | --family [--resolve]"

FAMILY_MODE=0
RESOLVE=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --family)  FAMILY_MODE=1; shift ;;
    --resolve) RESOLVE=1; shift ;;
    *)         break ;;
  esac
done

# A roster flag with explicit paths used to discard the paths silently — the
# same defect this harness exists to close, reached through argument parsing
# instead of a file check.
if [ "$FAMILY_MODE" = "1" ] && [ "$#" -gt 0 ]; then
  echo "$USAGE" >&2
  echo "--family cannot be combined with explicit target paths (got: $(harness_safe_label "$1"))" >&2
  exit 2
fi
if [ "$RESOLVE" = "1" ] && [ "$FAMILY_MODE" != "1" ]; then
  echo "$USAGE" >&2; echo "--resolve requires --family" >&2; exit 2
fi

if [ "$FAMILY_MODE" = "1" ]; then
  FAMILY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  # label|path. Entries are named by a STABLE LOGICAL LABEL throughout roster
  # output. An absolute path differs per machine, so two complete sweeps would
  # produce output that cannot be diffed; it also carries $HOME and workspace
  # roots into CI logs.
  ROSTER="core|$FAMILY/agenticapps-workflow-core/reference-implementations/openspec-change-gate/openspec-change-gate.sh
claude-workflow|$FAMILY/claude-workflow/bin/openspec-change-gate.sh
codex-workflow|$FAMILY/codex-workflow/bin/openspec-change-gate.sh
opencode-workflow|$FAMILY/opencode-workflow/bin/openspec-change-gate.sh
pi-agentic-apps-workflow|$FAMILY/pi-agentic-apps-workflow/bin/openspec-change-gate.sh
shared-install|$HOME/.agenticapps/bin/openspec-change-gate.sh"

  roster_total=0
  roster_scored=0
  roster_unscored=""

  # The absence filter runs AFTER this point, never before the argument count
  # is checked. Filtering first made a fully-absent roster collapse to zero
  # arguments and report a usage error — telling the operator their command
  # line was malformed when in fact their fleet was missing.
  while IFS='|' read -r label path; do
    [ -n "$label" ] || continue
    roster_total=$((roster_total + 1))
    if harness_screen_target "$path"; then
      p0="$pass"; f0="$fail"
      score_gate "$path" "$label"
      # An entry counts as scored only if it contributed at least one scored
      # row. Counting it because the harness reached it would permit
      # `scored 6 of 6` over a run whose scored total is zero.
      if [ $((pass - p0 + fail - f0)) -gt 0 ]; then
        roster_scored=$((roster_scored + 1))
      else
        roster_unscored="$roster_unscored  $label — reached but produced no scored row"$'\n'
      fi
      continue
    fi

    # "Not vendored" and "unscoreable" are different facts. A host that moved
    # to pin-and-resolve did not become unmeasurable; the harness merely
    # declined to go and get the bytes.
    host_dir="${path%/bin/openspec-change-gate.sh}"
    if [ "$REASON" = "not found" ] &&
       [ -f "$host_dir/bin/resolve-core-artifact.sh" ] &&
       [ -f "$host_dir/tools/core-vendor.manifest" ]; then
      if [ "$RESOLVE" = "1" ]; then
        # The resolver's stdout is a PATH THIS HARNESS WILL EXECUTE, and it
        # comes from a script in another repository. The pin makes the resolver
        # trustworthy about BYTES — it accepts nothing that does not hash to the
        # manifest — but it says nothing about where it puts them. Treating that
        # stdout as an arbitrary filesystem path meant executing whatever it
        # named and then deleting it.
        #
        # So: the resolve runs into a scratch directory this harness owns, the
        # returned path must land inside it, and the path is screened like any
        # other target before it is scored. Cleanup removes the scratch
        # directory, never a path the resolver chose.
        rdir="$(mktemp -d)"
        resolved="$(cd "$rdir" && TMPDIR="$rdir" bash \
                      "$host_dir/bin/resolve-core-artifact.sh" \
                      "$host_dir/tools/core-vendor.manifest" \
                      bin/openspec-change-gate.sh 2>/dev/null)"
        rrc=$?
        # Absolutise before comparing: a relative path from the resolver would
        # otherwise never match the prefix and would be rejected as an escape.
        case "$resolved" in
          /*) rabs="$resolved" ;;
          *)  rabs="$rdir/$resolved" ;;
        esac
        if [ "$rrc" -eq 0 ] && [ -n "$resolved" ] &&
           [ "${rabs#"$rdir"/}" != "$rabs" ] && harness_screen_target "$rabs"; then
          p0="$pass"; f0="$fail"
          score_gate "$rabs" "$label (resolved from pin)"
          [ $((pass - p0 + fail - f0)) -gt 0 ] && roster_scored=$((roster_scored + 1))
          rm -rf "$rdir"
          continue
        fi
        rm -rf "$rdir"
        if [ "$rrc" -eq 0 ] && [ -n "$resolved" ]; then
          roster_unscored="$roster_unscored  $label — resolver returned a path outside its scratch dir; refused"$'\n'
        else
          roster_unscored="$roster_unscored  $label — resolve from pin FAILED"$'\n'
        fi
      else
        roster_unscored="$roster_unscored  $label — not vendored; resolvable from pin, not attempted (--resolve)"$'\n'
      fi
    else
      roster_unscored="$roster_unscored  $label — $REASON"$'\n'
    fi
  done <<< "$ROSTER"

  echo
  # Emitted on EVERY roster run, including complete ones. A line that appears
  # only when something is wrong becomes the signal, and its absence then has
  # to be noticed to mean anything.
  echo "═══ COVERAGE: scored $roster_scored of $roster_total roster entries"
  if [ -n "$roster_unscored" ]; then
    printf '%s' "$roster_unscored"
  fi
else
  [ "$#" -gt 0 ] || { echo "$USAGE" >&2; exit 2; }

  for g in "$@"; do
    # Naming a target is the caller asserting it should be there. Skipping it
    # and exiting 0 converts that assertion into this harness's silence.
    if harness_screen_target "$g"; then
      score_gate "$g"
    else
      harness_report_unscoreable "$(harness_safe_label "$g")" "$REASON"
      fail=$((fail + 1))
    fi
  done
fi

echo
echo "═══ TOTAL: $pass passed, $fail failed, $inconclusive inconclusive"
# The backstop, folded into the one place the exit code is computed. An
# inconclusive row is NOT a scored row — it is reported precisely when the
# answer could not be determined, and counting it as evidence gathered would
# turn "I could not tell" into "I checked".
if [ $((pass + fail)) -eq 0 ]; then
  echo "openspec-conformance: certified NOTHING — no row reached a verdict" >&2
  exit 1
fi
[ "$fail" -eq 0 ]
