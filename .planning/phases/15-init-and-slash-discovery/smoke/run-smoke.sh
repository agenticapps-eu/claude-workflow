#!/usr/bin/env bash
# run-smoke.sh — Phase 15 end-to-end smoke (v1.9.3 → v1.10.0 → v1.11.0).
#
# Exercises the chain that v1.11.0 closes:
#   1. install.sh produces a discoverable add-observability skill (closes #22 fresh path).
#   2. migration 0011 applies cleanly on a v1.9.3 project state (now has init to point at).
#   3. migration 0012 applies cleanly on a v1.10.0 project state and lands at v1.11.0.
#
# The init + scan steps (PLAN T14 steps 2-3) require a real Claude Code
# agentic session with the `claude` CLI installed and an LLM endpoint
# configured. We do NOT invoke `claude` from this script — instead we
# exercise the migration logic on synthetic projects through the
# migration fixture harness, which is the canonical end-to-end test for
# the migration apply path. The manual claude-CLI steps are listed at
# the bottom as procedural documentation for the human operator who
# wants to dogfood the full agentic loop.
#
# Outputs:
#   - Streams to stdout (captured into output.txt by the operator).
#   - Exit 0 on success, non-zero on any failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
hdr()  { echo ""; echo "═══ $1 ═══"; }

# ─── Step 0: install.sh fresh-install symlink (closes #22 fresh path) ─────
hdr "Step 0: install.sh fresh-install symlink test (closes #22 fresh path)"

SANDBOX_HOME="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_HOME"' EXIT

echo "  sandbox HOME=$SANDBOX_HOME"
HOME="$SANDBOX_HOME" ./install.sh > "$SANDBOX_HOME/install.log" 2>&1 || {
  cat "$SANDBOX_HOME/install.log"
  fail "install.sh exited non-zero"
}

if [ -L "$SANDBOX_HOME/.claude/skills/add-observability" ]; then
  target="$(readlink "$SANDBOX_HOME/.claude/skills/add-observability")"
  if [ "$target" = "$REPO_ROOT/add-observability" ]; then
    pass "add-observability symlinked to $target"
  else
    fail "add-observability symlink target wrong: $target (expected $REPO_ROOT/add-observability)"
  fi
else
  fail "add-observability is not a symlink under $SANDBOX_HOME/.claude/skills/"
fi

# Also confirm the three other skills are linked (regression guard).
for name in agentic-apps-workflow setup-agenticapps-workflow update-agenticapps-workflow; do
  if [ -L "$SANDBOX_HOME/.claude/skills/$name" ]; then
    pass "$name symlinked"
  else
    fail "$name not symlinked (regression — install.sh broke other entries)"
  fi
done

# ─── Steps 4 + 6: migrations 0011 and 0012 end-to-end via fixture harness ─
# These are PLAN T14 steps 4-7 (apply 0011 on a v1.9.3 project → assert
# v1.10.0; apply 0012 on a v1.10.0 project → assert v1.11.0). The
# fixture harness puts each migration through its full pre-flight +
# apply + idempotency + rollback loop on synthetic projects, which is
# the canonical end-to-end exercise that the migration's apply path
# produces the expected after-state.

hdr "Steps 4-5: migration 0011 (1.9.3 → 1.10.0) — fixture harness exercise"

if bash migrations/run-tests.sh 0011 > "$SANDBOX_HOME/m0011.log" 2>&1; then
  pass "migrations/run-tests.sh 0011 — all fixtures green"
  grep -E "^Results:|fixtures? (PASS|FAIL)" "$SANDBOX_HOME/m0011.log" | sed 's/^/    /'
else
  cat "$SANDBOX_HOME/m0011.log"
  fail "migrations/run-tests.sh 0011 exited non-zero — POLICY_PATH parser regression?"
fi

hdr "Steps 6-7: migration 0012 (1.10.0 → 1.11.0) — fixture harness exercise"

if bash migrations/run-tests.sh 0012 > "$SANDBOX_HOME/m0012.log" 2>&1; then
  pass "migrations/run-tests.sh 0012 — all fixtures green"
  grep -E "^Results:|fixtures? (PASS|FAIL)" "$SANDBOX_HOME/m0012.log" | sed 's/^/    /'
else
  cat "$SANDBOX_HOME/m0012.log"
  fail "migrations/run-tests.sh 0012 exited non-zero"
fi

# ─── Regression guard: full migration suite — no NEW failures ────────────
# The full suite has 9 known pre-existing failures (tracked as carry-over
# work in session-handoff.md's open questions): 8 step-idempotency failures
# in test_migration_0001 (Phase 17 target) + 1 in test_migration_0007's
# 03-no-gitnexus fixture (Phase 18 target, fnm-PATH leak). Phase 15 is
# load-bearing on "no NEW regressions", not "all historical failures are
# fixed". We assert (a) PASS count is at least 122 (the baseline at the
# start of this session — phase 15 added fixtures so it should grow), and
# (b) FAIL count is at most 9 (the known pre-existing set), and (c) every
# failing test is in the known-fail list (no surprises).

hdr "Regression guard: full migration suite — no NEW failures"

bash migrations/run-tests.sh > "$SANDBOX_HOME/m-all.log" 2>&1 || true

pass_count="$(awk '/^[[:space:]]*PASS:/{print $2; exit}' "$SANDBOX_HOME/m-all.log")"
fail_count="$(awk '/^[[:space:]]*FAIL:/{print $2; exit}' "$SANDBOX_HOME/m-all.log")"

echo "    full-suite counts: PASS=$pass_count FAIL=$fail_count"

if [ -z "$pass_count" ] || [ -z "$fail_count" ]; then
  tail -40 "$SANDBOX_HOME/m-all.log"
  fail "could not parse PASS/FAIL counts from full suite output"
elif [ "$pass_count" -ge 122 ] && [ "$fail_count" -le 9 ]; then
  pass "full suite within baseline (PASS≥122 FAIL≤9)"

  # Verify every failure is in the known-pre-existing set (no surprises).
  unknown_fails=0
  while IFS= read -r line; do
    case "$line" in
      *"Step "*" idempotency: needs apply on v1.2.0"*) : ;;  # 0001 carry-over
      *"03-no-gitnexus — exit 0, expected 1"*)        : ;;  # 0007 carry-over
      *)
        unknown_fails=$((unknown_fails + 1))
        echo "    UNKNOWN FAIL: $line"
        ;;
    esac
  done < <(grep -E '^\s*✗' "$SANDBOX_HOME/m-all.log")

  if [ "$unknown_fails" -eq 0 ]; then
    pass "all failures are known carry-over (Phase 17 + Phase 18 targets)"
  else
    fail "found $unknown_fails NEW failure(s) outside the known-fail set"
  fi
else
  tail -40 "$SANDBOX_HOME/m-all.log"
  fail "full suite drifted from baseline: PASS=$pass_count (expected ≥122) FAIL=$fail_count (expected ≤9)"
fi

# ─── Final scaffolder-version asserts ─────────────────────────────────────
hdr "Scaffolder versions at HEAD"

scaffolder_version="$(awk -F': ' '/^version:/{print $2; exit}' skill/SKILL.md)"
addobs_version="$(awk -F': ' '/^version:/{print $2; exit}' add-observability/SKILL.md)"

if [ "$scaffolder_version" = "1.11.0" ]; then
  pass "skill/SKILL.md at v1.11.0"
else
  fail "skill/SKILL.md at v$scaffolder_version (expected 1.11.0)"
fi

if [ "$addobs_version" = "0.3.1" ]; then
  pass "add-observability/SKILL.md at v0.3.1"
else
  fail "add-observability/SKILL.md at v$addobs_version (expected 0.3.1)"
fi

# ─── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "═══ Summary ═══"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "FAIL — stop-the-line bug (per PLAN T14)"
  exit 1
fi

echo "PASS — end-to-end chain v1.9.3 → v1.10.0 → v1.11.0 verified via fixture harness."
echo ""
echo "─── Manual procedural steps (PLAN T14 steps 2-3, require real claude CLI) ───"
echo ""
echo "The following two steps exercise the same end-to-end chain through the"
echo "agentic CLI surface instead of the fixture harness. Run them in a fresh"
echo "Claude Code session against a minimal Worker fixture if you want to dogfood"
echo "the full /add-observability init + scan loop:"
echo ""
echo "  1. mkdir -p /tmp/worker-smoke && cd /tmp/worker-smoke && \\"
echo "     cp -r $REPO_ROOT/migrations/test-fixtures/init-ts-cloudflare-worker/before/* ."
echo "  2. claude /add-observability init     # answer consent gates 1/2/3"
echo "  3. claude /add-observability scan     # expect zero high-confidence gaps"
echo ""
echo "Both should complete without error and produce the same after-state captured"
echo "in migrations/test-fixtures/init-ts-cloudflare-worker/expected-after/."
exit 0
