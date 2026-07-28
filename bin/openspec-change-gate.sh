#!/usr/bin/env bash
# gate-version: 1.3.1
#
# VERSION MARKER — read by every host installer before writing this file to the
# SHARED path ~/.agenticapps/bin/. That path is written by claude / codex /
# opencode / pi installers alike, so without arbitration it is last-writer-wins:
# a host still vendoring an older copy silently republishes it over a newer one
# and reverts the fix for every agent on the machine. Installers MUST refuse to
# overwrite a higher version. Bump this whenever the gate's behaviour changes.
#   1.3.1 — tolerate markdown emphasis around the verdict label. 1.3.0 anchored
#           on a bare `VERDICT:` and missed `**VERDICT: REQUEST-CHANGES**`,
#           which is what opencode wrote on the first real run after 1.3.0
#           shipped: a genuine rejection, silently absent from the NOTE.
#   1.3.0 — report, but do not act on, outstanding REQUEST-CHANGES verdicts.
#           §18's truth table has no verdict term, so the threshold is a QUORUM:
#           two rejections open the gate exactly as two approvals do, and that
#           stays true here. What changed is the silence — the producer asks
#           every reviewer for a verdict and nothing read the answer, so a
#           change could step over two rejections without a word. Now the gate
#           names the objectors on the allow path. Reporting only; promoting
#           verdicts to blocking is a §18 change, not a gate change.
#   1.2.2 — close two symlink escapes in the openspec/ exemption, both present
#           since 1.2.0. (a) `..` was collapsed textually BEFORE physical
#           resolution, so a symlink inside openspec/ followed by `..` was
#           exempted while the bytes landed outside the repo; resolve
#           physically first, then refuse any `..` that survives. (b) a
#           symlinked artifact path was exempted and the writer followed it
#           into code; resolve the final component when it exists and is a
#           link. The not-yet-existing Write target 1.2.1 fixed is unaffected —
#           `[ -L ]` is false for a path that does not exist.
#   1.2.1 — exempt absolute artifact paths under a symlinked repo root. $ROOT
#           is physical (git resolves it) and hosts pass logical paths, so the
#           prefix test blocked the write of proposal.md itself — an
#           un-authorable change. Claude Code always sends absolute paths, so
#           this was live fleet-wide.
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

# Names the reviewers whose section carries a REQUEST-CHANGES verdict, comma
# separated; empty when none do. REPORTING ONLY — nothing here can block, and
# nothing here may ever change an exit code. §18's truth table has no verdict
# term, so a gate that blocked on this would be non-conformant.
#
# Deliberately mirrors reviewer_count's parsing rather than sharing it: fences
# are skipped for the same reason (a REVIEWS.md quoting the convention inside
# ``` must not register), self-exclusion applies for the same reason (the
# implementing host's own verdict is not an independent opinion), and both walk
# the file once. Divergence between the two would mean the gate counts one set
# of reviewers and reports on another.
#
# A section with no verdict line at all is NOT a rejection. Reviewers that
# ignore the producer's format, or vendors whose output was truncated, must not
# be reported as objecting when they said nothing.
pending_rejections(){
  local f="$1/REVIEWS.md"
  [ -f "$f" ] || { echo ""; return; }
  awk -v self="${OPENSPEC_GATE_SELF:-}" '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^##[[:space:]]*[Rr]eviewer[[:space:]]*:[[:space:]]*[^[:space:]]/ {
      name = $0
      sub(/^##[[:space:]]*[Rr]eviewer[[:space:]]*:[[:space:]]*/, "", name)
      sub(/[[:space:]]+$/, "", name)
      name = tolower(name)
      cur = (self != "" && name ~ ("^" tolower(self) "([-_ ].*)?$")) ? "" : name
      next
    }
    # Anchored at line start so a reviewer QUOTING the verdict vocabulary mid
    # prose ("...I nearly said REQUEST-CHANGES here...") does not register as
    # one. The producer asks for it on its own line.
    #
    # Markdown emphasis is tolerated around the label. 1.3.0 anchored on a bare
    # `VERDICT:` and missed `**VERDICT: REQUEST-CHANGES**` — which is what
    # opencode actually wrote on the first real run after 1.3.0 shipped. The
    # rejection was genuine and the gate silently under-reported it, which is
    # the same class of failure as reporting one that was never made. Reviewers
    # are told the vocabulary, not the formatting; a bolded verdict is still a
    # verdict.
    cur != "" && /^[[:space:]]*[*_]*[[:space:]]*VERDICT[[:space:]]*:[[:space:]]*[*_]*[[:space:]]*REQUEST-CHANGES/ {
      if (!(cur in flagged)) { flagged[cur] = 1; order[++k] = cur }
    }
    END {
      out = ""
      for (i = 1; i <= k; i++) out = (out == "" ? order[i] : out ", " order[i])
      print out
    }
  ' "$f" 2>/dev/null || echo ""
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
  local blocked=0 d n v
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n="$(reviewer_count "$d")"
    if [ "$n" -lt "$MIN_REVIEWERS" ]; then
      log "change '${d#"$ROOT"/}' has $n/$MIN_REVIEWERS reviewers — run plan-review to write REVIEWS.md"
      blocked=1
      continue
    fi
    # The threshold is a QUORUM, not an approval: §18's truth table keys `allow`
    # on the reviewer COUNT and carries no verdict term, so two REQUEST-CHANGES
    # verdicts open the gate exactly as two APPROVEs would. That is deliberate —
    # promoting verdicts to blocking needs a re-review trigger, a staleness rule
    # for an edited proposal, and an override path, none of which §18 defines.
    #
    # But silently stepping over a rejection is its own failure. The producer
    # ASKS every reviewer for "VERDICT: APPROVE" or "VERDICT: REQUEST-CHANGES",
    # so the answer is always there; before this the gate simply never read it.
    # On the run that surfaced this, both reviewers said REQUEST-CHANGES — one
    # of them having found a 77-record identity-migration hazard the plan missed
    # entirely — and the gate allowed the edit without a word.
    #
    # So: still allow, but say so. Reporting only, never blocking; a change to
    # that is a §18 change, not a gate change.
    v="$(pending_rejections "$d")"
    [ -n "$v" ] && log "NOTE change '${d#"$ROOT"/}' has $n reviewer(s) but $v requested changes — allowed on quorum; address or record why not"
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

physical_prefix(){       # print $1 with its deepest existing ANCESTOR DIRECTORY resolved physically
  # Only directories can be resolved with cd/pwd -P, so the final component is
  # split off first and the walk goes up to the deepest existing directory.
  #
  # The final component IS resolved when it exists and is a symlink. An earlier
  # version declined to, reasoning that resolving it "would follow a symlinked
  # file out of the tree" — that is backwards. The *writer* follows it either
  # way; declining to resolve is what let a symlinked artifact path be exempted
  # and the write land on its target (`openspec/changes/x/design.md -> src/app.go`
  # truncated app.go under an unsatisfied change). The exemption has to be
  # decided about the bytes' destination, not about the name used to reach it.
  #
  # The other half of that reasoning was sound and is preserved: a Write target
  # often does not exist yet, and `[ -L ]` is false for a non-existent path, so
  # the chase below simply does not run and the not-yet-created case behaves
  # exactly as before.
  local head="$1" rest depth=0 target parent
  case "$head" in /*) ;; *) printf '%s' "$head"; return ;; esac
  # Bounded: a symlink cycle would otherwise spin here. On hitting the bound we
  # fall through with `head` partly resolved, which cannot match the openspec
  # prefix spuriously — an unresolvable path is not exempt, which is the safe
  # direction.
  while [ -L "$head" ] && [ "$depth" -lt 40 ]; do
    depth=$((depth + 1))
    target="$(readlink "$head" 2>/dev/null)" || break
    [ -n "$target" ] || break
    parent="${head%/*}"
    [ -z "$parent" ] && parent=/
    case "$target" in
      /*) head="$target" ;;
      *)  head="$parent/$target" ;;
    esac
  done
  rest="${head##*/}"
  head="${head%/*}"
  [ -z "$head" ] && head=/
  while [ ! -d "$head" ]; do
    case "$head" in /|"") break ;; esac
    rest="${head##*/}/$rest"
    head="${head%/*}"
    [ -z "$head" ] && head=/
  done
  [ -d "$head" ] && head="$(cd -P "$head" 2>/dev/null && pwd -P)"
  printf '%s' "${head%/}/$rest"
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
  # Compare physical-to-physical. $ROOT comes from `git rev-parse
  # --show-toplevel`, which resolves symlinks; hosts pass the logical path they
  # were given. Where the repo is reached through a symlink a plain string
  # prefix test fails and the gate blocks the write of proposal.md itself,
  # leaving a change that can never be authored.
  #
  # Resolve PHYSICALLY FIRST, then reject leftover `..`. An earlier version
  # collapsed `..` textually up front and resolved afterwards, with a comment
  # claiming that order "is what keeps the escape rows blocked". It keeps the
  # BARE escapes blocked (`openspec/../src/app.ts` — still blocked, pinned
  # below); it is not sufficient on its own. Where a symlink inside openspec/
  # precedes the `..`, the textual pass and the kernel disagree and the kernel
  # wins:
  #
  #   $ROOT/openspec/out -> /tmp/outdir
  #   openspec/out/../victim
  #     textual first -> $ROOT/openspec/victim  => EXEMPT  (wrong)
  #     kernel        -> /tmp/outdir/../victim  => /tmp/victim, outside the repo
  #
  # `cd -P` asks the kernel, so resolving first gets this right. The reason the
  # textual pass existed — a Write target that does not exist yet cannot be
  # realpath'd — is handled by physical_prefix walking up to the deepest
  # existing ancestor instead.
  local root_phys
  root_phys="$(cd -P "$ROOT" 2>/dev/null && pwd -P)" || root_phys="$ROOT"
  resolved="$(physical_prefix "$resolved")"
  # A `..` that survived physical resolution sits in the unresolved tail, i.e.
  # below a directory that does not exist yet, so where it lands is unknowable
  # (`openspec/nope/../../src/app.ts` string-matches the openspec prefix while
  # resolving outside it). Refuse the exemption rather than guess: the write is
  # then judged on policy like any other, which is the safe direction.
  case "/$resolved/" in
    */../*) return 1 ;;
  esac
  case "$resolved" in
    "${root_phys%/}"/openspec/*) return 0 ;;
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
