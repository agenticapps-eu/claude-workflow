#!/bin/sh
# Verify pre-flight + Step 1/2 idempotency checks behave as expected on the
# BEFORE state (fixture 01). Migration is not yet applied.
set -eu

# Pre-flight #1: version is 1.12.0 → pass (1.12.0 or 1.14.0 for re-apply)
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass (version 1.12.0) but did not"; exit 1; }

# Pre-flight #2: vendored §11 block present in scaffolder bundle → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass (vendored block present) but did not"; exit 1; }

# Pre-flight #3: conflict detect — no §11 heading present, so no conflict
test -f CLAUDE.md \
  || { echo "fixture 01 expects CLAUDE.md present"; exit 1; }
grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
  && { echo "PRE-FLIGHT 3 false positive (no heading expected on fresh apply)"; exit 1; }

# Step 1 idempotency: no provenance comment → NEEDS to apply (inject)
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  && { echo "STEP 1 idempotency wrong (no provenance expected on fresh apply)"; exit 1; }

# Step 2 idempotency: version still 1.12.0 + implements_spec still 0.3.x
#   → NEEDS to apply (bump to 1.14.0 / 0.4.0)
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 idempotency wrong (version still 1.12.0 expected)"; exit 1; }
grep -q '^implements_spec: 0\.4\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 idempotency wrong (implements_spec still 0.3.x expected)"; exit 1; }

echo "fixture 01 — pre-flight passes; Steps 1+2 need to apply"
