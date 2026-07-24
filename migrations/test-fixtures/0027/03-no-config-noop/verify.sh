#!/bin/sh
# Verify migration 0027 on a project with NO .planning/config.json and no hooks
# (fixture 03): Steps 4 and 5 must no-op silently — and must NOT create a config
# file or a hooks dir. Steps 1/2/3/6 still complete, so the skill reaches
# 2.5.0 / 0.9.0 with reordered flags regardless.
#
# The pointer is optional metadata; a project that never had one must not
# acquire one from a claim-correction migration.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

TARGET=.claude/skills/agentic-apps-workflow/SKILL.md

# Pre-conditions:
[ -f .planning/config.json ] && { echo "PRE: fixture must have no config"; exit 1; }
grep -q '^version: 2.4.0$' "$TARGET" || { echo "PRE: expected version 2.4.0"; exit 1; }
grep -q '^8\. `/gsd-review` skipped' "$TARGET" \
  || { echo "PRE: fixture must carry the known-bad red-flag ordering"; exit 1; }

# ── Step 1 (apply) — reorder the §04 red-flag block ──────────────────────────
awk '
  /^## 14 Red Flags — STOP → DELETE → RESTART$/ { print; inblock=1; next }
  inblock && /^$/ && !emitted {
    print ""
    print "1. Code written before the test (for TDD tasks)"
    print "2. Test added after implementation"
    print "3. Test passes on first run — no RED observed"
    print "4. Cannot explain why the test should have failed"
    print "5. Tests marked for \"later\" addition"
    print "6. \"Just this once\" reasoning"
    print "7. Manual testing claimed as verification evidence"
    print "8. Two-stage review collapsed into one"
    print "9. Framing discipline as \"ritual\" or \"ceremony\""
    print "10. Keeping pre-written code as \"reference\" while writing tests"
    print "11. Sunk-cost reasoning about deleting unverified code"
    print "12. Describing discipline as \"dogmatic\""
    print "13. \"This case is different because...\""
    print "14. Code written under an active change whose `REVIEWS.md` has < 2 reviewers"
    emitted=1; skipping=1; next
  }
  skipping && /^[0-9]+\. / { next }
  skipping && /^$/ { skipping=0; print; next }
  skipping { skipping=0 }
  { print }
' "$TARGET" > "$TARGET.0027.tmp" && mv "$TARGET.0027.tmp" "$TARGET"

grep -q '^8\. Two-stage review collapsed into one$' "$TARGET" \
  || { echo "STEP 1 failed: canonical flag 8 not restored"; exit 1; }
grep -q '^14\. Code written under an active change' "$TARGET" \
  || { echo "STEP 1 failed: host flag not at position 14"; exit 1; }

# ── Step 2 (apply) ──────────────────────────────────────────────────────────
awk '/^## Spec deltas \(spec /{f=1}
     f && /^## Knowledge Capture — Ritual Tail/{exit}
     f' "$REPO_ROOT/skill/SKILL.md" > "$TARGET.0027.section"
awk -v secfile="$TARGET.0027.section" '
  /^## Knowledge Capture — Ritual Tail/ && !done {
    while ((getline line < secfile) > 0) print line
    close(secfile)
    done = 1
  }
  { print }
' "$TARGET" > "$TARGET.0027.tmp" && mv "$TARGET.0027.tmp" "$TARGET"
rm -f "$TARGET.0027.section"

[ "$(grep -c '^## Spec deltas (spec ' "$TARGET")" = "1" ] \
  || { echo "STEP 2 failed: section not inserted exactly once"; exit 1; }

# ── Step 3 (apply) ──────────────────────────────────────────────────────────
sed -i.0027.bak -E 's/^implements_spec: 0\.4\.0$/implements_spec: 0.9.0/' "$TARGET"
rm -f "$TARGET.0027.bak"
grep -q '^implements_spec: 0.9.0$' "$TARGET" || { echo "STEP 3 failed"; exit 1; }

# ── Step 4 (apply) — guarded on the config existing; must no-op ─────────────
[ -f .planning/config.json ] && \
jq --indent 2 '
  (if .hooks?._enforcement_contract? == "docs/workflow/ENFORCEMENT-PLAN.md"
   then .hooks._enforcement_contract = "docs/ENFORCEMENT-PLAN.md" else . end)
  | del(.hooks.post_phase.observability_scan.programmatic_hook)
' .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

# The migration must not have conjured a config into existence.
[ -f .planning/config.json ] \
  && { echo "STEP 4 failed: created a config.json that did not exist"; exit 1; }
[ -f .planning/config.json.tmp ] \
  && { echo "STEP 4 failed: left a stray tmp file"; exit 1; }

# ── Step 5 (apply) — guarded on the hook existing; must no-op ───────────────
HOOK=.claude/hooks/observability-postphase-scan.sh
if [ -e "$HOOK" ]; then
  REGISTERED=0
  if [ -f .claude/settings.json ] && jq empty .claude/settings.json 2>/dev/null; then
    if jq -e '[.hooks // {} | .[]? | .[]? | .hooks[]? | .command?]
              | map(select(type == "string"))
              | map(select(test("observability-postphase-scan\\.sh")))
              | length > 0' .claude/settings.json >/dev/null 2>&1; then
      REGISTERED=1
    fi
  fi
  [ "$REGISTERED" -eq 1 ] || rm -f "$HOOK"
fi

# The migration must not have conjured a hooks dir or settings.json into being.
[ -d .claude/hooks ] \
  && { echo "STEP 5 failed: created a hooks dir that did not exist"; exit 1; }
[ -f .claude/settings.json ] \
  && { echo "STEP 5 failed: created a settings.json that did not exist"; exit 1; }

# ── Step 6 (apply) ──────────────────────────────────────────────────────────
sed -i.0027.bak -E 's/^version: 2\.4\.0$/version: 2.5.0/' "$TARGET"
rm -f "$TARGET.0027.bak"
grep -q '^version: 2.5.0$' "$TARGET" || { echo "STEP 6 failed: version not bumped"; exit 1; }

echo "OK: 0027 completes with no config/hooks present; Steps 4 and 5 no-op"
exit 0
