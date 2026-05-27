#!/usr/bin/env bash
# observability-postphase-scan.sh — advisory GSD post-phase observability delta scan.
#
# Migration 0018 (workflow v1.17.0). Wired into the GSD post-phase chain
# (.planning/config.json → hooks.post_phase.observability_scan), alongside the
# spec_review / code_quality_review / qa gates. On phase completion it runs the
# add-observability delta scan against the phase-base commit and WARNS (never
# blocks) when this phase introduced new high-confidence §10 gaps.
#
# ADVISORY BY DESIGN — issue #50. The scan is LLM-driven today (add-observability
# is at implements_spec 0.3.2; the deterministic Node scanner port is unshipped),
# so a hard gate would add per-phase LLM cost + nondeterminism. This hook ALWAYS
# exits 0; promote it to blocking only once the deterministic scanner lands.
#
# No-op (silent, exit 0) outside a GSD project. EXPLICIT no-op (one line, exit 0)
# when the project has not adopted §10.9 enforcement (no .observability/baseline.json).

# An advisory hook must never break the phase: disable errexit and pin the exit
# code to 0 no matter how we leave (including an unexpected error mid-script).
set +e
trap 'exit 0' EXIT

# 0. Re-entry guard. This hook runs `claude -p` headlessly below; refuse nested
#    invocations so a scan can never re-trigger the hook (the env var is
#    exported, so any child claude process inherits it).
[ -n "${OBS_POSTPHASE_SCAN_ACTIVE:-}" ] && exit 0
export OBS_POSTPHASE_SCAN_ACTIVE=1

# 1. GSD project? Silent no-op otherwise (matches the other post-phase gates).
[ -d .planning ] || exit 0

# 2. Enforcement adopted? EXPLICIT no-op when no baseline (acceptance criterion):
#    a project that hasn't run `/add-observability` has nothing to delta against.
if [ ! -f .observability/baseline.json ]; then
  echo "ℹ️  observability post-phase scan: no .observability/baseline.json — project"
  echo "    has not adopted §10.9 enforcement; skipping. Adopt with:"
  echo "      claude -p \"/add-observability scan --update-baseline\""
  exit 0
fi

# 3. Resolve the phase-base commit for the delta window. Prefer a GSD-recorded
#    base if one exists; otherwise the merge-base of HEAD against the default
#    branch. If neither resolves, skip (advisory — never error).
PHASE_BASE=""
if [ -f .planning/current-phase/phase-base ]; then
  PHASE_BASE=$(tr -d '[:space:]' < .planning/current-phase/phase-base 2>/dev/null)
fi
if [ -z "$PHASE_BASE" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
  PHASE_BASE=$(git merge-base HEAD "origin/$DEFAULT_BRANCH" 2>/dev/null \
            || git merge-base HEAD "$DEFAULT_BRANCH" 2>/dev/null || true)
fi
if [ -z "$PHASE_BASE" ]; then
  echo "ℹ️  observability post-phase scan: could not resolve a phase-base commit; skipping."
  exit 0
fi
# Defence-in-depth: only ever pass a bare commit SHA onward. Anything else
# (a branch name, a ref expression, an injected payload) is rejected, not run.
case "$PHASE_BASE" in
  *[!0-9a-fA-F]*)
    echo "ℹ️  observability post-phase scan: phase-base is not a commit SHA; skipping."
    exit 0 ;;
esac

# 4. Run the delta scan headlessly. If the claude CLI isn't on PATH, print the
#    command for the operator to run by hand and stop (still exit 0).
if command -v claude >/dev/null 2>&1; then
  claude -p "/add-observability scan --since-commit $PHASE_BASE" >/dev/null 2>&1 || true
else
  echo "ℹ️  observability post-phase scan: 'claude' CLI not found — run the delta scan manually:"
  echo "      claude -p \"/add-observability scan --since-commit $PHASE_BASE\""
  exit 0
fi

# 5. Read the machine-readable delta and WARN on new high-confidence gaps. The
#    scan only writes delta.json when --since-commit is set (which it always is
#    here); a missing file means nothing to report.
DELTA=.observability/delta.json
[ -f "$DELTA" ] || exit 0

GAPS=0
if command -v jq >/dev/null 2>&1; then
  GAPS=$(jq -r '.counts.high_confidence_gaps // 0' "$DELTA" 2>/dev/null || echo 0)
fi
case "$GAPS" in ''|*[!0-9]*) GAPS=0 ;; esac

if [ "$GAPS" -gt 0 ]; then
  echo ""
  echo "## ⚠️  Observability post-phase scan — $GAPS new high-confidence §10 gap(s)"
  echo ""
  echo "Code this phase introduced has high-confidence observability gaps"
  echo "(details in $DELTA). Advisory only — the phase is NOT blocked."
  echo ""
  echo "→ Review and apply the high-confidence findings:"
  echo "      claude -p \"/add-observability scan-apply --confidence high\""
fi

exit 0
