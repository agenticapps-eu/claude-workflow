#!/bin/sh
# Fixture 03 — verify stale-anchor state: Step 1 idempotency fails
# (provenance present but not at current version) → migration would
# REPLACE the §11 section. Step 2 still needs to apply.
set -eu

# Pre-flight #1: version is 1.12.0 OR 1.14.0 → pass. Fixture 03's
# concrete state is 1.12.0 (pre-bump, stale §11 anchor); the regex
# is the migration's actual pre-flight regex, kept identical across
# fixtures. Step 2 idempotency below hard-asserts the concrete 1.12.0.
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored block present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: conflict detect — heading present WITH provenance (any
# version) → no conflict; this is a managed section, just at an older
# version. The migration handles it via Step 1's replace branch.
test -f CLAUDE.md || { echo "fixture 03 expects CLAUDE.md present"; exit 1; }
grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
  || { echo "fixture 03 expects §11 heading present"; exit 1; }
grep -qE '<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->' CLAUDE.md \
  || { echo "fixture 03 expects SOME provenance comment present"; exit 1; }

# Step 1 idempotency: current-version provenance is ABSENT (stale version present)
#   → NEEDS to apply (replace)
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  && { echo "STEP 1 idempotency wrong (current @0.4.0 provenance should be absent)"; exit 1; }
# But SOME provenance line is present (the stale one) → confirms this is the
# replace path, not the insert path.
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0-pre §11 -->' CLAUDE.md \
  || { echo "fixture 03 expects stale @0.4.0-pre provenance for the replace path"; exit 1; }

# Step 2 idempotency: version still 1.12.0 → NEEDS apply
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && { echo "STEP 2 idempotency wrong (version still 1.12.0 expected)"; exit 1; }

echo "fixture 03 — Step 1 takes replace path (stale provenance); Step 2 needs apply"
