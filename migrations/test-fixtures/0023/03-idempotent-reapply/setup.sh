#!/bin/sh
# Fixture 03 — idempotent reapply (AFTER state): the migration has already been
# applied. injection-guard skill present; CLAUDE.md carries the injection_guard:
# block (the §14 scaffold was accepted at init's consent gate 3); project
# SKILL.md at version 2.1.0. A second apply must be a no-op (every positive
# idempotency anchor short-circuits).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Mutate the before-state into the after-state:

# Step 1 applied — /injection-guard init wrote the injection_guard: metadata block.
cat >> CLAUDE.md <<'EOF_GUARD_BLOCK'

injection_guard:
  spec_version: 0.6.0
  skill: injection-guard
  registry: docs/untrusted-input-registry.md
EOF_GUARD_BLOCK

# Step 2 applied — bump project SKILL.md version to 2.1.0.
sed -i.bak -E 's/^version: 2\.0\.0$/version: 2.1.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
