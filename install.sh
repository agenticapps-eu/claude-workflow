#!/usr/bin/env bash
# install.sh — make the AgenticApps Claude Workflow skills discoverable.
#
# Claude Code's skill loader scans ~/.claude/skills/<name>/SKILL.md (one level
# deep). This repo nests skills in subdirectories (skill/, setup/, update/)
# for logical grouping, so the loader doesn't find them by default. This
# script symlinks each skill subdirectory out to its canonical discoverable
# path.
#
# Run this once after cloning the scaffolder, and again after every `git pull`
# that adds new skill subdirectories. Idempotent — safe to re-run any time.
#
# Refuses to clobber existing non-symlink directories (e.g. a real directory
# at the target path means a project copy or third-party install lives there
# and we shouldn't replace it).

set -euo pipefail

# Resolve scaffolder dir to wherever this script lives, regardless of cwd.
SCAFFOLDER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
AA_BIN="$HOME/.agenticapps/bin"

# ── flags ────────────────────────────────────────────────────────────────────
#   --dry-run         print every action, write nothing
#   --skip-upstream   install the AgenticApps layer only (no `openspec init`)
DRY_RUN=0
SKIP_UPSTREAM=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=1 ;;
    --skip-upstream) SKIP_UPSTREAM=1 ;;
    -h|--help)
      echo "usage: install.sh [--dry-run] [--skip-upstream]"
      exit 0 ;;
    *)
      echo "unknown flag: $arg (see --help)" >&2
      exit 2 ;;
  esac
done
run() { if [ "$DRY_RUN" -eq 1 ]; then echo "    would run: $*"; else "$@"; fi; }

# Advance the agenticapps-shared submodule (idempotent: safe on fresh AND existing clones).
# A3: do NOT guard on VERSION-missing — after a `git pull` an existing clone must move to the
# new gitlink SHA. sync picks up any .gitmodules URL change; update --init advances/initialises.
# Guard on a real .git (review finding 2): a copied/tarball tree carries .gitmodules but no
# git dir, so the refresh would fatal and `set -e` would abort the whole install before any
# skill linking. .git is a dir in a clone, a file in a worktree/submodule — accept both. Keep
# the refresh non-fatal so a transient submodule error still lets skill linking proceed.
if [ "$DRY_RUN" -eq 0 ] && [ -f "$SCAFFOLDER/.gitmodules" ] \
   && { [ -d "$SCAFFOLDER/.git" ] || [ -f "$SCAFFOLDER/.git" ]; }; then
  echo "Syncing git submodule(s) vendor/agenticapps-shared..."
  if ! { git -C "$SCAFFOLDER" submodule sync --recursive \
      && git -C "$SCAFFOLDER" submodule update --init --recursive; }; then
    echo "WARNING: submodule refresh failed — continuing with skill linking." >&2
    echo "  Fix later: git -C \"$SCAFFOLDER\" submodule update --init --recursive" >&2
  fi
fi

# Pairs of "<subdir-in-scaffolder> <skill-name-for-claude-code>".
# Order matters for the install summary; scaffolder name alphabetical.
LINKS=(
  "skill agentic-apps-workflow"
  "setup setup-agenticapps-workflow"
  "update update-agenticapps-workflow"
)

[ "$DRY_RUN" -eq 1 ] || mkdir -p "$SKILLS_DIR"

# Legacy cleanup (claude-workflow 2.0.0 / SPLIT-03): observability moved to the separate
# agenticapps-observability repo and the bundled add-observability/ subdir was deleted, so the
# add-observability skill-pair is no longer installed here. An add-observability symlink from a
# pre-2.0.0 install now dangles. Remove it ONLY if it is a symlink whose target is missing — a valid
# alias created by the obs repo's own install.sh (target exists) is left untouched.
legacy_obs_link="$SKILLS_DIR/add-observability"
if [ -L "$legacy_obs_link" ] && [ ! -e "$legacy_obs_link" ]; then
  run rm -f "$legacy_obs_link"
  echo "  ⊘ removed dangling legacy symlink: add-observability (observability now installs separately)"
fi

echo "Installing AgenticApps workflow skills (dry-run: $DRY_RUN)"
echo "  Scaffolder: $SCAFFOLDER"
echo "  Skills dir: $SKILLS_DIR"
echo ""

LINKED=0
SKIPPED=0
FAILED=0

for entry in "${LINKS[@]}"; do
  src="$SCAFFOLDER/${entry%% *}"
  name="${entry##* }"
  link="$SKILLS_DIR/$name"

  if [ ! -d "$src" ]; then
    # Source subdir missing — likely an old scaffolder version (pre-1.3.0
    # repos didn't have update/). Skip silently for forward compat with
    # older installs that don't have all subdirs.
    echo "  ⊘ source missing: $src (skipping $name)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ ! -f "$src/SKILL.md" ]; then
    echo "  ✗ no SKILL.md at $src — refusing to link as $name"
    FAILED=$((FAILED + 1))
    continue
  fi

  if [ -L "$link" ]; then
    existing_target="$(readlink "$link")"
    if [ "$existing_target" = "$src" ]; then
      echo "  ✓ already linked: $name → $src"
      LINKED=$((LINKED + 1))
      continue
    else
      echo "  ↻ existing symlink points elsewhere ($existing_target); replacing"
      run rm "$link"
    fi
  elif [ -e "$link" ]; then
    echo "  ✗ $link exists and is NOT a symlink — refusing to clobber."
    echo "    Inspect it; if safe to replace, run: rm -rf '$link' && rerun this script."
    FAILED=$((FAILED + 1))
    continue
  fi

  run ln -s "$src" "$link"
  echo "  ✓ linked: $name → $src"
  LINKED=$((LINKED + 1))
done

echo ""
echo "Summary: linked=$LINKED skipped=$SKIPPED failed=$FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
  echo "Some links failed. Resolve the conflicts above and re-run."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# The §18 change-gate — the enforcement teeth (spec 1.0.0, ADR-0044)
# ─────────────────────────────────────────────────────────────────────────────
# ONE host-agnostic script does the enforcing; every surface just calls it.
# The per-agent PreToolUse hook is fast feedback, but it only sees one agent and
# cannot gate the session that installed it — so the git pre-commit + CI pair is
# the actual guarantee, and it catches a human editor too.
echo "Installing the OpenSpec change-gate (spec §18)"
echo "  GATE   $AA_BIN/openspec-change-gate.sh   (host-agnostic enforcement surface)"
echo "  GATE   $AA_BIN/run-plan-review.sh        (multi-AI review producer)"
echo "  GATE   $AA_BIN/reviewer-cli.sh           (the producer's vendor wrapper)"
echo "  HOOK   .git/hooks/pre-commit             (agent-agnostic floor)"
run mkdir -p "$AA_BIN"

# ── where the bytes come from (ADR-0047) ─────────────────────────────────────
# This repo does NOT vendor the three artifacts above. It records WHICH core
# revision it trusts and WHAT each file must hash to; resolve-core-artifact.sh
# turns that into verified bytes on disk.
#
# Vendoring is what this replaced. The runtime never read the vendored copies —
# the project hook resolves ~/.agenticapps/bin first — so they existed purely to
# feed this script, and they drifted: on 2026-07-31 the gate here was 1.3.1
# against core's 2.0.0, the producer 1.0.0 against 1.2.0, the wrapper 1.1.0
# against 1.2.0. Three stale copies, one green install, nothing published.
#
# Fails CLOSED, deliberately. An installer that cannot verify what it is about
# to publish into a directory shared by every agent on this machine must stop,
# not fall back to whatever bytes happen to be lying around — a fallback would
# have republished 1.3.1 over 2.0.0 and reverted the fix for every host.
MANIFEST="$SCAFFOLDER/tools/core-vendor.manifest"
RESOLVER="$SCAFFOLDER/bin/resolve-core-artifact.sh"
RESOLVED=()   # temp copies to clean up on the way out
cleanup_resolved() { [ "${#RESOLVED[@]}" -gt 0 ] && rm -f "${RESOLVED[@]}" || true; }
trap cleanup_resolved EXIT

# Prints the path of a verified temp copy, or explains and exits non-zero.
resolve_core() { # $1 = logical path, e.g. bin/run-plan-review.sh
  local out
  if ! out="$("$RESOLVER" "$MANIFEST" "$1" 2>&1)"; then
    echo "  ✗ could not resolve $1 from core:" >&2
    printf '%s\n' "$out" | sed 's/^/      /' >&2
    echo "      Nothing was published. Fix the pin or the source, then re-run." >&2
    echo "      Offline with no core checkout? Clone core beside this repo, or set" >&2
    echo "      CORE_CHECKOUT=/path/to/agenticapps-workflow-core." >&2
    return 1
  fi
  RESOLVED+=("$out")
  printf '%s\n' "$out"
}

if [ ! -x "$RESOLVER" ] || [ ! -f "$MANIFEST" ]; then
  echo "  ✗ missing $([ -x "$RESOLVER" ] || echo "bin/resolve-core-artifact.sh")$([ -f "$MANIFEST" ] || echo " tools/core-vendor.manifest")" >&2
  echo "      This repo publishes core's artifacts by pin, not by copy — without" >&2
  echo "      both files there is nothing to publish. Re-clone or git pull." >&2
  exit 1
fi

_gate_src="$(resolve_core bin/openspec-change-gate.sh)" || exit 1
_rp_src="$(resolve_core bin/run-plan-review.sh)"        || exit 1
_rc_src="$(resolve_core bin/reviewer-cli.sh)"           || exit 1

# $AA_BIN is SHARED by every host installer (claude / codex / opencode / pi), so
# writing it unconditionally is last-writer-wins: a host still vendoring an older
# gate silently republishes it over a newer one and reverts the fix for every
# agent on the machine. Arbitrate on the `# gate-version:` marker and refuse to
# downgrade. An unmarked file counts as 0.0.0 so any marked copy upgrades it.
# ONE awk, no pipeline, anchored X.Y.Z. The obvious form —
# `sed -n 's/.../\1/p' "$1" | head -n1 | grep . || echo 0.0.0` — is a downgrade
# hole in two independent ways, both verified:
#   1. With enough marker lines, `head -n1` closes the pipe, `sed` takes SIGPIPE,
#      and under `set -o pipefail` the `|| echo 0.0.0` fallback fires AFTER the
#      real version already printed. The function returns "9.9.9\n0.0.0", which
#      `sort -V` reads as 0.0.0 — so an installed 9.9.9 is silently overwritten.
#   2. `[0-9][0-9.]*` parses `9.0.0junk` as `9.0.0`, letting a malformed marker
#      claim any version it likes.
# Unparseable is 0.0.0, which fails in the safe direction: a bad INSTALLED file
# gets overwritten by a good one, and a bad INCOMING file refuses to overwrite.
gate_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# gate-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_incoming="$(gate_version "$_gate_src")"
_installed="$(gate_version "$AA_BIN/openspec-change-gate.sh")"
_older="$(printf '%s\n%s\n' "$_incoming" "$_installed" | sort -V | head -n1)"
if [ "$_installed" != "$_incoming" ] && [ "$_older" = "$_incoming" ]; then
  echo "  SKIP   gate: installed $_installed is NEWER than the pinned $_incoming"
  echo "         Refusing to downgrade the shared gate. Advance core_commit in"
  echo "         tools/core-vendor.manifest so every host publishes the same version."
else
  run install -m 0755 "$_gate_src" "$AA_BIN/openspec-change-gate.sh"
  [ "$_installed" = "$_incoming" ] || echo "  OK     gate: $_installed -> $_incoming"
fi
# The PRODUCER is the third artifact in this shared directory, and until now the
# only one installed blind — this line was a bare `install` sitting between the
# gate's arbitration block above and the reviewer-cli's below, both of which
# exist because of core#41. It never bit only because no sibling host ships a
# producer to overwrite it with. Same rule, same parser shape, same reasons.
run_plan_review_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# run-plan-review-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_rp_incoming="$(run_plan_review_version "$_rp_src")"
_rp_installed="$(run_plan_review_version "$AA_BIN/run-plan-review.sh")"
_rp_older="$(printf '%s\n%s\n' "$_rp_incoming" "$_rp_installed" | sort -V | head -n1)"
if [ "$_rp_installed" != "$_rp_incoming" ] && [ "$_rp_older" = "$_rp_incoming" ]; then
  echo "  SKIP   run-plan-review: installed $_rp_installed is NEWER than the pinned $_rp_incoming"
  echo "         Refusing to downgrade the shared producer. Advance core_commit in"
  echo "         tools/core-vendor.manifest so every host publishes the same version."
else
  run install -m 0755 "$_rp_src" "$AA_BIN/run-plan-review.sh"
  [ "$_rp_installed" = "$_rp_incoming" ] || echo "  OK     run-plan-review: $_rp_installed -> $_rp_incoming"
fi

# The producer's vendor wrapper is the SAME shared-path hazard as the gate, and
# it is not hypothetical: on 2026-07-25 a host installer delivered the correctly
# arbitrated 1.2.2 gate and, in the same run, blind-installed a 3-arm wrapper
# over the 4-arm one. The `opencode` arm vanished and the next review that asked
# for it got `unknown vendor` mid-run — recorded as "reviewer unavailable" and
# waved through with one fewer opinion (core#41). The gate survived only because
# it carries a marker every host arbitrates on. Same rule, same reasoning, on
# `# reviewer-cli-version:`. Unmarked counts as 0.0.0.
# Same parser shape, and the same reasons, as gate_version above.
reviewer_cli_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# reviewer-cli-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_rc_incoming="$(reviewer_cli_version "$_rc_src")"
_rc_installed="$(reviewer_cli_version "$AA_BIN/reviewer-cli.sh")"
_rc_older="$(printf '%s\n%s\n' "$_rc_incoming" "$_rc_installed" | sort -V | head -n1)"
if [ "$_rc_installed" != "$_rc_incoming" ] && [ "$_rc_older" = "$_rc_incoming" ]; then
  echo "  SKIP   reviewer-cli: installed $_rc_installed is NEWER than the pinned $_rc_incoming"
  echo "         Refusing to downgrade the shared wrapper. Advance core_commit in"
  echo "         tools/core-vendor.manifest so every host publishes the same version."
else
  run install -m 0755 "$_rc_src" "$AA_BIN/reviewer-cli.sh"
  [ "$_rc_installed" = "$_rc_incoming" ] || echo "  OK     reviewer-cli: $_rc_installed -> $_rc_incoming"
fi
if [ -d "$SCAFFOLDER/.git" ] || [ -f "$SCAFFOLDER/.git" ]; then
  # `--git-path` may answer relative to the repo root OR absolutely, depending on
  # cwd and on whether this is a worktree/submodule. Resolve to an absolute path
  # exactly once — blindly prefixing $SCAFFOLDER doubles an already-absolute answer.
  hookdir="$(git -C "$SCAFFOLDER" rev-parse --git-path hooks 2>/dev/null || true)"
  case "$hookdir" in
    "")  : ;;
    /*)  ;;                                   # already absolute
    *)   hookdir="$SCAFFOLDER/$hookdir" ;;    # relative to the repo root
  esac
  if [ -n "$hookdir" ]; then
    run mkdir -p "$hookdir"
    # Never destroy a pre-commit hook the repo already owns. Migration 0032 backs
    # one up; install.sh overwrote it silently, which is the same data loss with
    # a different entry point.
    if [ -e "$hookdir/pre-commit" ] && ! grep -q 'openspec-change-gate' "$hookdir/pre-commit" 2>/dev/null; then
      echo "  note: existing pre-commit preserved as pre-commit.pre-agenticapps — merge it by hand"
      run cp "$hookdir/pre-commit" "$hookdir/pre-commit.pre-agenticapps"
    fi
    run install -m 0755 "$SCAFFOLDER/bin/git-hooks/pre-commit" "$hookdir/pre-commit"
  fi
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Bind OpenSpec upstream (spec §16) — the planning front end
# ─────────────────────────────────────────────────────────────────────────────
# The CLI is a standalone, agent-agnostic binary. This repo does NOT vendor or
# re-port it: `openspec init` generates the slot and the per-tool command files.
echo "Binding OpenSpec — openspec init --tools claude --profile core"
echo "  generates openspec/ (specs + changes) and .claude/commands/opsx/"
if [ "$SKIP_UPSTREAM" -eq 1 ]; then
  echo "  ⊘ --skip-upstream: leaving the spec slot alone"
elif ! command -v openspec >/dev/null 2>&1; then
  echo "  ! openspec CLI not found. Install it, then re-run:"
  echo "      npm i -g @fission-ai/openspec"
  echo "      openspec init --tools claude --profile core"
elif [ -d "$SCAFFOLDER/openspec/changes" ] && [ -d "$SCAFFOLDER/openspec/specs" ]; then
  echo "  ✓ openspec slot already initialised (skipping init)"
else
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "    would run: openspec init --tools claude --profile core"
  else
    ( cd "$SCAFFOLDER" && openspec init --tools claude --profile core ) \
      && echo "  ✓ spec slot + /opsx:* commands generated" \
      || echo "  ! openspec init failed — run it by hand in this repo."
  fi
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# The collapsed gate set (spec §17) — declared in the installed config
# ─────────────────────────────────────────────────────────────────────────────
echo "Gate set (spec §17 — installed into a project by /setup-agenticapps-workflow):"
echo "  collapsed →  spec-review, plan-review  ⇒  stage 2 (validate + multi-AI review)"
echo "  retained  →  code-review, tdd, verification, security (/cso), branch-close"
echo "  condition →  database-sentinel, qa, ui-preview, design-critique,"
echo "               design-shotgun, impeccable, observability-scan"
echo "  lint      →  ts-declare-first"
echo ""

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run only — nothing was written."
  echo ""
fi

echo "Slash commands now available in any Claude Code session:"
echo "  /agentic-apps-workflow         the workflow itself (auto-triggers on code tasks)"
echo "  /setup-agenticapps-workflow    bootstrap a fresh project"
echo "  /update-agenticapps-workflow   apply pending migrations to an installed project"
echo "  /opsx:propose | :apply | :archive   the OpenSpec lifecycle (per repo, after init)"
echo ""
echo "Workflow explainer: docs/WORKFLOW.md   ·   Gate contract: docs/ENFORCEMENT-PLAN.md"
echo "Verify discovery with: ls -la $SKILLS_DIR | grep -E '(agentic|setup|update)-?(apps-)?workflow'"
