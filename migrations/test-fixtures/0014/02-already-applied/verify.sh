#!/bin/sh
# Fixture 02 — verify post-apply state idempotency: all checks return
# "already applied"; the migration would no-op on re-run.
set -eu

# Pre-flight #1: version is 1.12.0 OR 1.14.0 → pass. Fixture 02's
# concrete state is 1.14.0 (the re-apply path); the regex is the
# migration's actual pre-flight regex, kept identical across fixtures.
grep -qE '^version: 1\.(12\.0|14\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE-FLIGHT 1 should pass on re-apply (1.14.0)"; exit 1; }

# Pre-flight #2: vendored block present → pass
test -f "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
  || { echo "PRE-FLIGHT 2 should pass"; exit 1; }

# Pre-flight #3: conflict detect — §11 heading present WITH provenance →
#   no conflict (managed by this migration's anchor system).
test -f CLAUDE.md || { echo "fixture 02 expects CLAUDE.md present"; exit 1; }
grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
  || { echo "fixture 02 expects §11 heading present"; exit 1; }
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  || { echo "fixture 02 expects current-version provenance comment"; exit 1; }

# Step 1 idempotency: provenance with current spec version present → no-op
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  || { echo "STEP 1 idempotency wrong (provenance @0.4.0 expected)"; exit 1; }

# Step 2 idempotency: version is 1.14.0 + implements_spec is 0.4.0 → no-op
grep -q '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 idempotency wrong (version 1.14.0 expected)"; exit 1; }
grep -q '^implements_spec: 0\.4\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 idempotency wrong (implements_spec 0.4.0 expected)"; exit 1; }

echo "fixture 02 — all idempotency checks return 'already applied'; migration would no-op"
