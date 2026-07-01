#!/usr/bin/env bash
# check-snapshot-parity.sh — drift guard for the snapshot install path.
#
# One authoritative layer: the structural checks below.
#   JSON validity, version stamp, settings.json hook bindings,
#   .planning/config.json key shape, hook referential integrity + hashes,
#   and END-STATE INVARIANTS derived from real installed projects (factiv)
#   so the seed template can't false-green.
#
# The snapshot is assembled deterministically from templates/ + skill/SKILL.md
# by bin/build-snapshot.sh (NOT replayed from the migration chain — replay is
# impossible; see ADR-0036 / issue #74). These checks need no scaffolder, GSD,
# agent, or network. A FAIL means real drift that must be fixed.
#
# See docs/decisions/0036-snapshot-install.md and setup/snapshot/MANIFEST.md.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP="$ROOT/setup/snapshot"
SET="$SNAP/claude-settings.json"
CFG="$SNAP/planning-config.json"
fail=0
ok()   { printf '  ok:   %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

have_jq=0; command -v jq >/dev/null && have_jq=1

echo "Snapshot parity check"
echo "  snapshot: $SNAP"

# ── 0. required files + version ──────────────────────────────────────────────
for f in agentic-apps-workflow-SKILL.md workflow-config.md claude-settings.json \
         planning-config.json claude-md-workflow.md claude-md-reference-block.md VERSION; do
  [ -e "$SNAP/$f" ] && ok "present $f" || bad "missing $f"
done
ver="$(cat "$SNAP/VERSION" 2>/dev/null)"; [ -n "$ver" ] && ok "version $ver" || bad "no VERSION"

# ── 1. JSON validity ─────────────────────────────────────────────────────────
if [ "$have_jq" = 1 ]; then
  for j in "$SET" "$CFG"; do
    jq -e . "$j" >/dev/null 2>&1 && ok "valid json $(basename "$j")" || bad "invalid json $(basename "$j")"
  done
fi

# ── 2. settings.json: hook bindings (shape, not strings) ─────────────────────
# Enumerate every hook command bound in settings.json and check the workflow's
# programmatic hooks are all wired. Catches the factiv finding that the seed
# template was missing the multi-ai-review-gate binding.
REQUIRED_HOOK_BINDINGS=(
  phase-sentinel.sh
  multi-ai-review-gate.sh
  normalize-claude-md.sh
)
if [ "$have_jq" = 1 ]; then
  bound="$(jq -r '.. | .command? // empty' "$SET" 2>/dev/null)"
  for h in "${REQUIRED_HOOK_BINDINGS[@]}"; do
    printf '%s\n' "$bound" | grep -q "$h" && ok "settings binds $h" || bad "settings.json does not bind $h"
  done
  # Template-only annotations must not leak into an installed project.
  for leak in _comment _enforcement_contract; do
    jq -e "has(\"$leak\")" "$SET" >/dev/null 2>&1 \
      && bad "settings.json carries template-only key \"$leak\" (raw template, not installed shape)" \
      || ok "no template-leak key $leak"
  done
fi

# ── 3. .planning/config.json: end-state key shape ────────────────────────────
if [ "$have_jq" = 1 ]; then
  for sec in hooks; do
    jq -e ".$sec" "$CFG" >/dev/null 2>&1 && ok "config has .$sec" || bad "config missing .$sec"
  done
  # NOTE: `.workflow` is GSD-owned config (research/plan_check/verifier/…),
  # written by GSD at its own init — NOT part of the AgenticApps snapshot, which
  # owns only `.hooks`. Setup merges `.hooks` into any GSD-written config. So we
  # do NOT assert `.workflow` here.
  #
  # Observability skill id: 0022 repointed `add-observability` -> `observability`
  # (the obs repo keeps `add-observability` as an alias). Accept either the
  # current `observability:scan` or the legacy `add-observability:scan`; fail
  # only if the scan ref is absent entirely.
  if grep -q '"observability:scan"' "$CFG" || grep -q '"add-observability:scan"' "$CFG"; then
    ok "observability scan ref present (current or aliased)"
  else
    bad "config missing an observability scan skill ref"
  fi
fi

# ── 4. hooks: referential integrity + hashes ─────────────────────────────────
# Every hook bound in settings.json must exist as a file in the snapshot, and
# we print hashes so a reviewer can compare against a known-good replay.
if [ "$have_jq" = 1 ]; then
  for h in $(printf '%s\n' "$bound" | grep -oE '[a-z0-9-]+\.sh' | sort -u); do
    [ -f "$SNAP/hooks/$h" ] && ok "hook file present: $h" || bad "settings binds $h but hooks/$h missing"
  done
fi
if command -v sha256sum >/dev/null 2>&1; then
  echo "  hook hashes (compare to a build-snapshot replay):"
  ( cd "$SNAP/hooks" 2>/dev/null && sha256sum ./*.sh 2>/dev/null | sed 's/^/    /' )
fi

# ── 5. snapshot is at the latest version ─────────────────────────────────────
# Real evidence the snapshot reflects every migration through the latest: its
# VERSION must equal the highest-numbered migration's to_version (the same
# coupling migrations/run-tests.sh enforces for skill/SKILL.md). The old
# feature-name greps were a false-green — they matched MANIFEST.md's own prose,
# and neither 0015 (a user-global symlink) nor 0023 (skill-delegated
# /injection-guard init) leaves a static string in the project snapshot.
latest_file="$(ls "$ROOT"/migrations/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sort | tail -1)"
latest_to="$(grep '^to_version:' "$latest_file" 2>/dev/null | awk '{print $2}')"
snap_ver="$(cat "$SNAP/VERSION" 2>/dev/null)"
if [ -n "$latest_to" ] && [ "$snap_ver" = "$latest_to" ]; then
  ok "snapshot VERSION ($snap_ver) == latest migration to_version"
else
  bad "snapshot VERSION ($snap_ver) != latest migration to_version ($latest_to)"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — snapshot drifted or still the raw seed. Materialize it: bash bin/build-snapshot.sh"
  exit 1
fi
echo "PASS"
