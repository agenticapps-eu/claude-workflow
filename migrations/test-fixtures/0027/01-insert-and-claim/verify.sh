#!/bin/sh
# Verify migration 0027 on the BEFORE state (fixture 01): the deterministic
# Step 1..6 shell, replayed exactly, produces the end state — §04 reordered to
# the 0.8.0 composition rule, Spec deltas section inserted from the scaffolder
# source ($REPO_ROOT stands in for the clone) BEFORE the ritual tail, claim
# raised to 0.9.0, config repointed + dangling hook ref dropped, dead hook
# removed, version bumped — and every edit is SURGICAL.
#
# The §04 assertion compares the migrated block against the SCAFFOLDER's own
# skill/SKILL.md rather than against the core spec repo: that sibling repo is
# not guaranteed to exist in CI, and the invariant a migration owes is
# "migrated install == fresh snapshot install". Byte-identity of the
# scaffolder's block against core spec/04-red-flags.md is asserted separately.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

TARGET=.claude/skills/agentic-apps-workflow/SKILL.md

# Pre-conditions (Steps need to apply):
grep -q '^version: 2.4.0$' "$TARGET" || { echo "PRE: expected version 2.4.0"; exit 1; }
grep -q '^implements_spec: 0.4.0$' "$TARGET" || { echo "PRE: expected claim 0.4.0"; exit 1; }
grep -q '^## Spec deltas (spec ' "$TARGET" \
  && { echo "PRE: unexpected Spec deltas section before apply"; exit 1; }
grep -q '^## Knowledge Capture — Ritual Tail' "$TARGET" \
  || { echo "PRE: fixture must carry the ritual-tail anchor"; exit 1; }
grep -q '^8\. `/gsd-review` skipped' "$TARGET" \
  || { echo "PRE: fixture must carry the known-bad red-flag ordering"; exit 1; }
jq -e '.hooks._enforcement_contract == "docs/workflow/ENFORCEMENT-PLAN.md"' \
  .planning/config.json >/dev/null || { echo "PRE: expected the bad pointer"; exit 1; }
[ -e .claude/hooks/observability-postphase-scan.sh ] \
  || { echo "PRE: fixture must carry the dead hook on disk"; exit 1; }

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

# The migrated flag block must be byte-identical to the scaffolder's own —
# a migrated install and a fresh snapshot install must not diverge.
awk '/^## 14 Red Flags/{f=1} f&&/^1\. /{p=1} p&&/^$/{exit} p' \
  "$REPO_ROOT/skill/SKILL.md" > .src-flags
[ -s .src-flags ] || { echo "STEP 1: extracted an empty flag block from the scaffolder"; exit 1; }
awk '/^## 14 Red Flags/{f=1} f&&/^1\. /{p=1} p&&/^$/{exit} p' "$TARGET" > .our-flags
cmp -s .src-flags .our-flags \
  || { echo "STEP 1 failed: migrated flags differ from the scaffolder source"; diff .src-flags .our-flags; exit 1; }

# Canonical 13 at positions 1-13, in the listed order (spec §04 @ 0.8.0).
grep -q '^8\. Two-stage review collapsed into one$' "$TARGET" \
  || { echo "STEP 1 failed: canonical flag 8 not at position 8"; exit 1; }
grep -q '^13\. "This case is different because\.\.\."$' "$TARGET" \
  || { echo "STEP 1 failed: canonical flag 13 not at position 13"; exit 1; }
# The host flag sits at 14, and appears exactly once (not left behind at 8).
grep -q '^14\. Code written under an active change whose `REVIEWS.md` has < 2 reviewers$' "$TARGET" \
  || { echo "STEP 1 failed: host flag not at position 14"; exit 1; }
[ "$(grep -c 'Code written under an active change whose `REVIEWS.md` has < 2 reviewers' "$TARGET")" = "1" ] \
  || { echo "STEP 1 failed: host flag duplicated or left at position 8"; exit 1; }
grep -q '^8\. `/gsd-review` skipped' "$TARGET" \
  && { echo "STEP 1 failed: host flag still at position 8"; exit 1; }
# Exactly 14 flags — no line dropped, none duplicated.
[ "$(grep -c '^[0-9]' .our-flags)" = "14" ] \
  || { echo "STEP 1 failed: flag count is not 14"; exit 1; }
rm -f .src-flags .our-flags

# Surgical: Step 1 must not swallow the section that follows the block.
grep -q '^## Pressure-Test Scenarios — Self-Check' "$TARGET" \
  || { echo "STEP 1 not surgical: following section dropped"; exit 1; }
grep -q '^## Knowledge Capture — Ritual Tail' "$TARGET" \
  || { echo "STEP 1 not surgical: ritual-tail anchor dropped"; exit 1; }

# ── Step 2 (apply) — insert the section extracted from the scaffolder ────────
awk '/^## Spec deltas \(spec /{f=1}
     f && /^## Knowledge Capture — Ritual Tail/{exit}
     f' "$REPO_ROOT/skill/SKILL.md" > "$TARGET.0027.section"

[ -s "$TARGET.0027.section" ] \
  || { echo "STEP 2 failed: extracted an empty section from the scaffolder"; exit 1; }

awk -v secfile="$TARGET.0027.section" '
  /^## Knowledge Capture — Ritual Tail/ && !done {
    while ((getline line < secfile) > 0) print line
    close(secfile)
    done = 1
  }
  { print }
' "$TARGET" > "$TARGET.0027.tmp" && mv "$TARGET.0027.tmp" "$TARGET"

[ "$(grep -c '^## Spec deltas (spec ' "$TARGET")" = "1" ] \
  || { echo "STEP 2 failed: section not inserted exactly once"; exit 1; }

# Ordering: the section lands BEFORE the ritual tail, not after it.
d_line=$(grep -n '^## Spec deltas (spec ' "$TARGET" | cut -d: -f1)
k_line=$(grep -n '^## Knowledge Capture — Ritual Tail' "$TARGET" | cut -d: -f1)
[ "$d_line" -lt "$k_line" ] \
  || { echo "STEP 2 failed: section inserted after the ritual tail ($d_line >= $k_line)"; exit 1; }

# The inserted text is byte-identical to the scaffolder source section.
awk '/^## Spec deltas \(spec /{f=1}
     f && /^## Knowledge Capture — Ritual Tail/{exit}
     f' "$TARGET" > .actual-section
cmp -s "$TARGET.0027.section" .actual-section \
  || { echo "STEP 2 failed: inserted section differs from scaffolder source"; exit 1; }

# All four deltas §09 requires are actually present in the inserted text.
for d in "§13" "§14" "§10" "§08"; do
  grep -q -- "$d" .actual-section || { echo "STEP 2 failed: delta '$d' missing"; exit 1; }
done
# The §08 entry must be recorded as SATISFIED (resolved upstream at core 0.9.0,
# ADR-0018), not as an open delta — and must name the CI guard that satisfies
# the amended §08's "name your guard" requirement for snapshot hosts.
grep -qi 'satisfied' .actual-section \
  || { echo "STEP 2 failed: §08 entry must state the MUST is satisfied"; exit 1; }
grep -qF 'migrations/check-snapshot-parity.sh' .actual-section \
  || { echo "STEP 2 failed: §08 entry must name the guard, migrations/check-snapshot-parity.sh"; exit 1; }
grep -qi 'runs in CI' .actual-section \
  || { echo "STEP 2 failed: §08 entry must state the guard runs in CI"; exit 1; }
grep -qi 'not accepted' .actual-section \
  && { echo "STEP 2 failed: §08 entry still claims the amendment is NOT accepted (stale)"; exit 1; }
rm -f "$TARGET.0027.section" .actual-section

# Surgical: the stub body above the insert survives.
grep -q '^## Daily Quick Reference' "$TARGET" \
  || { echo "STEP 2 not surgical: preceding section dropped"; exit 1; }

# ── Step 3 (apply) — raise the claim ────────────────────────────────────────
sed -i.0027.bak -E 's/^implements_spec: 0\.4\.0$/implements_spec: 0.9.0/' "$TARGET"
rm -f "$TARGET.0027.bak"
[ "$(grep -c '^implements_spec: 0.9.0$' "$TARGET")" = "1" ] \
  || { echo "STEP 3 failed: claim not raised exactly once"; exit 1; }

# ── Step 4 (apply) — repoint the contract + drop the dangling hook ref ───────
jq --indent 2 '
  (if .hooks?._enforcement_contract? == "docs/workflow/ENFORCEMENT-PLAN.md"
   then .hooks._enforcement_contract = "docs/ENFORCEMENT-PLAN.md" else . end)
  | del(.hooks.post_phase.observability_scan.programmatic_hook)
' .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json

jq -e '.hooks._enforcement_contract == "docs/ENFORCEMENT-PLAN.md"' \
  .planning/config.json >/dev/null || { echo "STEP 4 failed: pointer not repointed"; exit 1; }
grep -qF 'docs/workflow/ENFORCEMENT-PLAN.md' .planning/config.json \
  && { echo "STEP 4 failed: dangling pointer survives"; exit 1; }
grep -qF 'observability-postphase-scan.sh' .planning/config.json \
  && { echo "STEP 4 failed: dangling programmatic_hook survives"; exit 1; }
# Surgical: the rest of the hooks block survives, and the REAL skill binding
# (which the parity guard asserts) is NOT collateral damage.
jq -e '.hooks.context_warnings == true' .planning/config.json >/dev/null \
  || { echo "STEP 4 not surgical: hooks block dropped"; exit 1; }
jq -e '.hooks.post_phase.observability_scan.skill == "observability:scan"' \
  .planning/config.json >/dev/null \
  || { echo "STEP 4 not surgical: the real observability:scan binding was dropped"; exit 1; }

# ── Step 5 (apply) — remove the dead hook (unregistered => remove) ───────────
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

[ ! -e "$HOOK" ] || { echo "STEP 5 failed: dead hook survives"; exit 1; }
# Surgical: the LIVE, registered hook must NOT be collateral damage.
[ -x .claude/hooks/session-bootstrap.sh ] \
  || { echo "STEP 5 not surgical: removed a registered hook"; exit 1; }

# ── Step 6 (apply) — version bump ───────────────────────────────────────────
sed -i.0027.bak -E 's/^version: 2\.4\.0$/version: 2.5.0/' "$TARGET"
rm -f "$TARGET.0027.bak"
grep -q '^version: 2.5.0$' "$TARGET" || { echo "STEP 6 failed: version not bumped"; exit 1; }

echo "OK: 0027 applied cleanly to the 2.4.0 fleet state"
exit 0
