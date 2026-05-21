#!/bin/sh
# Fixture 06 — verify the two-step independence: Step 1 idempotency
# returns "already applied" (no-op), but Step 2 still needs to apply.
set -eu

# Pre-flight #1: version 1.12.0 → pass
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored block present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: heading + provenance present → no conflict (managed)
test -f CLAUDE.md || { echo "fixture 06 expects CLAUDE.md present"; exit 1; }
grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
  || { echo "fixture 06 expects §11 heading present (Step 1 already applied)"; exit 1; }

# Step 1 idempotency: provenance with current spec version present → no-op
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  || { echo "STEP 1 idempotency wrong (current-version provenance expected)"; exit 1; }

# Step 2 idempotency: version still 1.12.0 (Step 2 not yet applied)
#   → NEEDS apply. This is the crux of the fixture: Step 1 done, Step 2 not.
grep -q '^version: 1\.12\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 idempotency wrong (version should still be 1.12.0)"; exit 1; }
grep -q '^implements_spec: 0\.3\.2$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 idempotency wrong (implements_spec should still be 0.3.2)"; exit 1; }

echo "fixture 06 — Step 1 already applied (no-op); Step 2 still needs apply"
