#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0027.
# Builds a sandboxed project (BEFORE state) with a project-local hyphenated
# SKILL.md at a controllable version (default 2.4.0 — Step 6's bump floor) and
# a stub body that carries:
#   - the §15 ritual-tail heading, because 0027's Step 2 inserts *before* it
#     (0025 is its floor, pre-flight 4);
#   - the §04 red-flag block in the PRE-0.8.0 (known-bad) ordering, with the
#     host flag wedged in at position 8, because Step 1 reorders it.
# Each fixture's setup.sh writes its own `.planning/config.json` (or omits it)
# and its own `.claude/hooks/` + `.claude/settings.json` (or omits them).
#
#   SKILL_VERSION=2.5.0 SPEC_CLAIM=0.8.0 RED_FLAGS=fixed . "$FIXTURES_ROOT/common-setup.sh"
#     -> already-applied state, for the idempotency fixture
set -eu

: "${SKILL_VERSION:=2.4.0}"
: "${SPEC_CLAIM:=0.4.0}"
: "${RED_FLAGS:=bad}"

mkdir -p .claude/skills/agentic-apps-workflow

cat > .claude/skills/agentic-apps-workflow/SKILL.md <<EOF_PROJ_SKILL
---
name: agentic-apps-workflow
version: ${SKILL_VERSION}
implements_spec: ${SPEC_CLAIM}
description: synthetic test fixture for migration 0027
---

## Daily Quick Reference

1. stub — the Spec deltas section is inserted before the ritual tail below

## 14 Red Flags — STOP → DELETE → RESTART

EOF_PROJ_SKILL

if [ "$RED_FLAGS" = "fixed" ]; then
  # Post-0027 (canonical 0.8.0) ordering: canonical 13 at 1-13, host flag at 14.
  cat >> .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_FLAGS_FIXED'
1. Code written before the test (for TDD tasks)
2. Test added after implementation
3. Test passes on first run — no RED observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. "Just this once" reasoning
7. Manual testing claimed as verification evidence
8. Two-stage review collapsed into one
9. Framing discipline as "ritual" or "ceremony"
10. Keeping pre-written code as "reference" while writing tests
11. Sunk-cost reasoning about deleting unverified code
12. Describing discipline as "dogmatic"
13. "This case is different because..."
14. `/gsd-review` skipped — no `{phase}-REVIEWS.md` artifact
EOF_FLAGS_FIXED
else
  # Pre-0027 (known-bad) ordering: host flag inserted at position 8, which
  # renumbers canonical 8-13 into 9-14. This is the exact violation core
  # spec 0.8.0's changelog names for claude-workflow.
  cat >> .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_FLAGS_BAD'
1. Code written before the test (for TDD tasks)
2. Test added after implementation
3. Test passes on first run — no RED observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. "Just this once" reasoning
7. Manual testing claimed as verification evidence
8. `/gsd-review` skipped — no `{phase}-REVIEWS.md` artifact
9. Two-stage review collapsed into one
10. Framing discipline as "ritual" or "ceremony"
11. Keeping pre-written code as "reference" while writing tests
12. Sunk-cost reasoning about deleting unverified code
13. Describing discipline as "dogmatic"
14. "This case is different because..."
EOF_FLAGS_BAD
fi

cat >> .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_TAIL'

## Pressure-Test Scenarios — Self-Check

stub — proves Step 1 does not swallow the section after the flag block.

## Knowledge Capture — Ritual Tail (spec §15)

stub ritual tail — 0027 anchors its insert on this heading.
EOF_TAIL
