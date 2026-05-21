#!/bin/sh
# Fixture 04 — verify unmanaged-conflict state: heading present, no
# provenance comment → pre-flight #3 must refuse with exit 3. Step 1 and
# Step 2 do NOT run on the abort path.
set -eu

# Pre-flight #1: version 1.12.0 → pass
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass"; exit 1; }

# Pre-flight #2: vendored block present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: conflict detect — heading present WITHOUT provenance →
#   the migration MUST refuse with exit 3.
test -f CLAUDE.md || { echo "fixture 04 expects CLAUDE.md present"; exit 1; }
grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
  || { echo "fixture 04 expects §11 heading present"; exit 1; }
grep -qE '<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->' CLAUDE.md \
  && { echo "fixture 04 expects NO provenance comment (unmanaged paste)"; exit 1; }
# i.e. the (heading present) AND (NOT provenance present) condition is true →
#   pre-flight #3 HARD ABORTs with exit 3. The downstream verify checks below
#   confirm no mutation took place (BEFORE state preserved).

# State assertion: no mutation happened on the abort path.
# Version still 1.12.0 (Step 2 did not run)
grep -q '^version: 1\.12\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 should NOT have bumped on abort path"; exit 1; }
# implements_spec still 0.3.2 (Step 2 did not run)
grep -q '^implements_spec: 0\.3\.2$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 should NOT have bumped implements_spec on abort path"; exit 1; }

echo "fixture 04 — unmanaged-conflict correctly detected; pre-flight would abort exit 3"
