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
         planning-config.json claude-md-workflow.md claude-md-reference-block.md \
         gitignore VERSION; do
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
  gitnexus-reindex.cjs
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
  # Knowledge capture (spec §15, ADR-0038): block present, enabled boolean, and
  # the note targets the vault folder with the literal <repo-name> placeholder
  # still in place — the SEED keeps the placeholder; setup Step 4d resolves it
  # to the repo directory name at install time.
  jq -e '.knowledge_capture.enabled | type == "boolean"' "$CFG" >/dev/null 2>&1 \
    && ok "config has .knowledge_capture.enabled (boolean)" \
    || bad "config missing .knowledge_capture.enabled boolean (spec §15.2)"
  if jq -er '.knowledge_capture.note' "$CFG" 2>/dev/null | grep -qF '44 Agentic Coding Learnings/<repo-name>.md'; then
    ok "config knowledge_capture.note targets the vault with <repo-name> placeholder"
  else
    bad "config .knowledge_capture.note must target the vault folder and keep the literal <repo-name> placeholder"
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

# ── 6. .gitignore policy: phase artifacts are committed (ADR-0037) ────────────
# The scaffolded .gitignore MUST NOT ignore the .planning/phases tree — phase
# artifacts (CONTEXT/PLAN/VERIFICATION/REVIEW/HANDOFF-LOG) are the shared
# cross-host plan and are committed by default. This end-state invariant stops a
# whole-tree ignore from ever being re-introduced into the seed. Narrow ignores
# of specific scratch files UNDER the tree (e.g. `.planning/phases/*/.codex-review.md`)
# are allowed and do not match the whole-tree patterns below.
GI="$SNAP/gitignore"
if [ -f "$GI" ]; then
  if grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' "$GI" \
     || grep -qE '^[[:space:]]*/?\.planning/?[[:space:]]*$' "$GI" \
     || grep -qE '^[[:space:]]*/?\.planning/\*' "$GI"; then
    bad ".gitignore ignores the .planning/phases tree — phase artifacts must be committed (ADR-0037)"
  else
    ok ".gitignore does not ignore the .planning/phases tree"
  fi
  # Proves it is the canonical baseline (narrow local ignore present), not empty.
  grep -qE '^[[:space:]]*/?\.claude/worktrees/?[[:space:]]*$' "$GI" \
    && ok ".gitignore keeps .claude/worktrees local (narrow ignore)" \
    || bad ".gitignore missing the narrow .claude/worktrees ignore"
else
  bad "missing gitignore (canonical scaffolded ignore baseline)"
fi

# ── 7. knowledge capture (spec §15): the SKILL wires the ritual tail ─────────
# The snapshot SKILL MUST carry the knowledge-capture step that fires at the
# three §15 trigger points (session handoff, plan completion, phase completion)
# and routes the destination through .planning/config.json → knowledge_capture
# (never a hardcoded path). End-state invariant in the §6 style: the step can
# never silently drop out of the seed. See ADR-0038 / core ADR-0017.
SKL="$SNAP/agentic-apps-workflow-SKILL.md"
if [ -f "$SKL" ]; then
  grep -q '^## Knowledge Capture — Ritual Tail' "$SKL" \
    && ok "SKILL carries the knowledge-capture ritual-tail section" \
    || bad "SKILL missing the '## Knowledge Capture — Ritual Tail' section (spec §15)"
  for t in "Session handoff" "Plan completion" "Phase completion"; do
    grep -q "$t" "$SKL" \
      && ok "SKILL wires §15 trigger: $t" \
      || bad "SKILL missing §15 trigger point: $t"
  done
  grep -q 'knowledge_capture' "$SKL" \
    && ok "SKILL routes destination via the knowledge_capture config block" \
    || bad "SKILL does not read .planning/config.json → knowledge_capture (path must be config-routed)"
else
  bad "missing agentic-apps-workflow-SKILL.md"
fi

# ── 8. spec §11 canonical block (setup path) ────────────────────────────────
# §11 mandates the canonical "Coding Discipline" block verbatim in the
# project's primary instruction file. Migration 0014 injects it on the REPLAY
# path; since ADR-0036 the SETUP path is the snapshot, which must therefore
# carry the mirror AND wire the injection — otherwise every fresh install
# silently loses a canonical-prose block (§09 item 1). See ADR-0040.
M11_SRC="$ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
M11_SNAP="$SNAP/spec-mirrors/11-coding-discipline-0.4.0.md"
if [ -f "$M11_SNAP" ]; then
  ok "snapshot ships the §11 canonical mirror"
  if diff -q "$M11_SRC" "$M11_SNAP" >/dev/null 2>&1; then
    ok "§11 mirror byte-identical to templates/spec-mirrors/ source"
  else
    bad "§11 mirror drifted from templates/spec-mirrors/ (rebuild: bash bin/build-snapshot.sh)"
  fi
  grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' "$M11_SNAP" \
    && ok "§11 mirror carries the canonical heading" \
    || bad "§11 mirror missing the canonical '## Coding Discipline (NON-NEGOTIABLE)' heading"
else
  bad "snapshot missing spec-mirrors/11-coding-discipline-0.4.0.md — §11 never reaches fresh installs"
fi
if grep -q 'spec-mirrors' "$ROOT/setup/SKILL.md"; then
  ok "setup wires the §11 injection step"
else
  bad "setup/SKILL.md never references spec-mirrors — §11 laid down but never injected"
fi

# ── 9. design-critique fires on the spec §02 trigger ─────────────────────────
# §02 triggers design-critique on a UI plan WITH an existing UI-SPEC.md.
# Gating it on design_shotgun_completed inverts this: shotgun's own trigger is
# no_ui_spec_yet, so with a UI-SPEC.md present shotgun never fires and critique
# never fires either — exactly when the spec says it must. See ADR-0040.
if [ "$have_jq" = 1 ]; then
  dc="$(jq -r '.hooks.pre_phase.design_critique.trigger // empty' "$CFG")"
  case "$dc" in
    *design_shotgun_completed*)
      bad "design_critique trigger '$dc' is inverted vs spec §02 (never fires when UI-SPEC.md exists)" ;;
    *ui_spec_exists*)
      ok "design_critique triggers on an existing UI-SPEC.md (spec §02)" ;;
    *)
      bad "design_critique trigger unrecognised: '$dc'" ;;
  esac
fi

echo

# ── 8. gitnexus background reindex (migration 0026): engine + Bash binding ────
# The snapshot MUST ship the reindex engine (executable, node shebang) and bind
# it on a PostToolUse Bash matcher. §4's referential-integrity loop is .sh-only,
# so the .cjs engine needs its own end-state invariant here.
GNH="$SNAP/hooks/gitnexus-reindex.cjs"
if [ -f "$GNH" ]; then
  ok "gitnexus reindex engine present in snapshot"
  [ -x "$GNH" ] && ok "gitnexus reindex engine is executable" \
                || bad "gitnexus reindex engine not executable"
  head -1 "$GNH" | grep -q '^#!/usr/bin/env node' \
    && ok "gitnexus reindex engine has a node shebang" \
    || bad "gitnexus reindex engine missing '#!/usr/bin/env node' shebang"
else
  bad "missing hooks/gitnexus-reindex.cjs (migration 0026 engine)"
fi
if [ "$have_jq" = 1 ]; then
  jq -e '.hooks.PostToolUse[]? | select(.matcher=="Bash")
         | .hooks[]?.command? | select(test("gitnexus-reindex"))' "$SET" >/dev/null 2>&1 \
    && ok "settings binds gitnexus-reindex.cjs on a Bash PostToolUse matcher" \
    || bad "settings.json does not bind gitnexus-reindex.cjs on a Bash PostToolUse matcher"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — snapshot drifted or still the raw seed. Materialize it: bash bin/build-snapshot.sh"
  exit 1
fi
echo "PASS"
