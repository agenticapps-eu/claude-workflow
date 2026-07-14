#!/bin/sh
# Verify migration 0027 Step 4's design-critique trigger rewrite (final-review
# Finding 1 on ADR-0040 / migration 0027): an existing install carrying the
# inverted pre-0.9.0 trigger gets it rewritten to match spec §02, sibling
# hooks config survives untouched, and a second application is a no-op
# (idempotent).
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

CFG=.planning/config.json

# Pre-condition: fixture carries the known-bad inverted trigger.
jq -e '.hooks.pre_phase.design_critique.trigger == "ui_hint_yes && design_shotgun_completed"' \
  "$CFG" >/dev/null || { echo "PRE: fixture must carry the inverted trigger"; exit 1; }

# ── Step 4 (apply) — the same jq migration 0027 runs ─────────────────────────
apply_step4() {
  jq --indent 2 '
    (if .hooks?._enforcement_contract? == "docs/workflow/ENFORCEMENT-PLAN.md"
     then .hooks._enforcement_contract = "docs/ENFORCEMENT-PLAN.md" else . end)
    | del(.hooks.post_phase.observability_scan.programmatic_hook)
    | (if .hooks?.pre_phase?.design_critique?.trigger? == "ui_hint_yes && design_shotgun_completed"
       then .hooks.pre_phase.design_critique.trigger = "ui_hint_yes && ui_spec_exists" else . end)
  ' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}

# ── First apply ───────────────────────────────────────────────────────────────
apply_step4

jq -e '.hooks.pre_phase.design_critique.trigger == "ui_hint_yes && ui_spec_exists"' \
  "$CFG" >/dev/null \
  || { echo "STEP 4 failed: design_critique trigger not corrected"; exit 1; }
[ "$(jq -r '.hooks.pre_phase.design_critique.trigger' "$CFG")" != "ui_hint_yes && design_shotgun_completed" ] \
  || { echo "STEP 4 failed: inverted trigger survives"; exit 1; }

# Surgical: sibling hooks config survives untouched — this migration must not
# clobber a project's other hooks config while fixing this one key.
jq -e '.hooks.pre_phase.design_shotgun.trigger == "ui_hint_yes && no_ui_spec_yet"' \
  "$CFG" >/dev/null \
  || { echo "STEP 4 not surgical: design_shotgun trigger clobbered"; exit 1; }
jq -e '.hooks.context_warnings == true' "$CFG" >/dev/null \
  || { echo "STEP 4 not surgical: hooks block dropped"; exit 1; }
jq -e '.hooks.post_phase.observability_scan.skill == "observability:scan"' \
  "$CFG" >/dev/null \
  || { echo "STEP 4 not surgical: unrelated post_phase binding dropped"; exit 1; }

# ── Re-apply (idempotency) ────────────────────────────────────────────────────
before="$(cat "$CFG")"
apply_step4
after="$(cat "$CFG")"
[ "$before" = "$after" ] || {
  echo "STEP 4 not idempotent: re-apply changed the config"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after")
  exit 1
}

echo "OK: 0027 Step 4 corrects the inverted design_critique trigger, surgically, idempotently"
exit 0
