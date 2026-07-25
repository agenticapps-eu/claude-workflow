#!/bin/sh
# Verify migration 0027 is idempotent (fixture 02): the BEFORE state is an
# install where 0027 already applied. Each step's POSITIVE idempotency check
# must report "already applied", and the guarded re-apply must be a byte-level
# no-op on both files.
#
# This fixture is load-bearing: it fails if a step's idempotency check is
# wrong (returns "not applied" on an applied install) OR if the step mutates
# an already-applied file anyway.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

TARGET=.claude/skills/agentic-apps-workflow/SKILL.md

# Pre-conditions: the fixture really is in the already-applied state.
grep -q '^version: 2.5.0$' "$TARGET" || { echo "PRE: expected version 2.5.0"; exit 1; }
grep -q '^implements_spec: 0.9.0$' "$TARGET" || { echo "PRE: expected claim 0.9.0"; exit 1; }
grep -q '^## Spec deltas (spec ' "$TARGET" || { echo "PRE: expected the section"; exit 1; }
grep -q '^8\. Two-stage review collapsed into one$' "$TARGET" \
  || { echo "PRE: expected the reordered red flags"; exit 1; }
jq -e '.hooks._enforcement_contract == "docs/ENFORCEMENT-PLAN.md"' \
  .planning/config.json >/dev/null || { echo "PRE: expected the repointed pointer"; exit 1; }
[ ! -e .claude/hooks/observability-postphase-scan.sh ] \
  || { echo "PRE: expected the dead hook to be gone"; exit 1; }

before_skill=$(shasum "$TARGET" | cut -d' ' -f1)
before_cfg=$(shasum .planning/config.json | cut -d' ' -f1)

# ── Step 1 idempotency check (positive — already reordered) ─────────────────
if grep -q '^8\. Two-stage review collapsed into one$' "$TARGET"; then
  : # already applied — skip the reorder
else
  echo "STEP 1 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi

# ── Step 2 idempotency check (positive — section already present) ───────────
if grep -q '^## Spec deltas (spec ' "$TARGET"; then
  :
else
  echo "STEP 2 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi

# ── Step 3 idempotency check (positive) ─────────────────────────────────────
if grep -q '^implements_spec: 0.9.0$' "$TARGET"; then
  :
else
  echo "STEP 3 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi
# The guarded sed is a no-op anyway: 0.4.0 is not present to match.
sed -i.0027.bak -E 's/^implements_spec: 0\.4\.0$/implements_spec: 0.9.0/' "$TARGET"
rm -f "$TARGET.0027.bak"

# ── Step 4 idempotency check (positive — repointed + key already dropped) ───
if [ ! -f .planning/config.json ] || \
   ! jq -e '(.hooks._enforcement_contract? == "docs/workflow/ENFORCEMENT-PLAN.md")
            or (.hooks.post_phase.observability_scan.programmatic_hook? != null)' \
        .planning/config.json >/dev/null 2>&1; then
  :
else
  echo "STEP 4 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi
# The guarded jq is a no-op anyway: the bad literal and the key are both absent.
jq --indent 2 '
  (if .hooks?._enforcement_contract? == "docs/workflow/ENFORCEMENT-PLAN.md"
   then .hooks._enforcement_contract = "docs/ENFORCEMENT-PLAN.md" else . end)
  | del(.hooks.post_phase.observability_scan.programmatic_hook)
' .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

# ── Step 5 idempotency check (positive — hook already gone) ─────────────────
if [ ! -e .claude/hooks/observability-postphase-scan.sh ]; then
  :
else
  echo "STEP 5 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi

# ── Step 6 idempotency check (positive) ─────────────────────────────────────
if grep -q '^version: 2.5.0$' "$TARGET"; then
  :
else
  echo "STEP 6 idempotency check WRONG: reported not-applied on an applied install"
  exit 1
fi
sed -i.0027.bak -E 's/^version: 2\.4\.0$/version: 2.5.0/' "$TARGET"
rm -f "$TARGET.0027.bak"

# ── Nothing changed ─────────────────────────────────────────────────────────
after_skill=$(shasum "$TARGET" | cut -d' ' -f1)
after_cfg=$(shasum .planning/config.json | cut -d' ' -f1)

[ "$before_skill" = "$after_skill" ] \
  || { echo "NOT IDEMPOTENT: SKILL.md mutated on re-apply"; exit 1; }
[ "$before_cfg" = "$after_cfg" ] \
  || { echo "NOT IDEMPOTENT: config.json mutated on re-apply"; exit 1; }

# Still exactly one of each — no duplicate section, claim line, or host flag.
[ "$(grep -c '^## Spec deltas (spec ' "$TARGET")" = "1" ] \
  || { echo "NOT IDEMPOTENT: duplicate Spec deltas section"; exit 1; }
[ "$(grep -c '^implements_spec: 0.9.0$' "$TARGET")" = "1" ] \
  || { echo "NOT IDEMPOTENT: duplicate claim line"; exit 1; }
[ "$(grep -c 'Code written under an active change whose `REVIEWS.md` has < 2 reviewers' "$TARGET")" = "1" ] \
  || { echo "NOT IDEMPOTENT: duplicate host red flag"; exit 1; }

echo "OK: 0027 re-apply is a byte-level no-op"
exit 0
