#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0023.
# Builds a sandboxed project (BEFORE state) at workflow v2.0.0 with:
#   - a project-local hyphenated SKILL.md at version 2.0.0 (Step 2's
#     version-bump target),
#   - a CLAUDE.md WITHOUT an `injection_guard:` block (the block is written by
#     the consent-gated /injection-guard init — Step 1's positive anchor; it is
#     deliberately absent on the before-state).
# It does NOT, by itself, place the `injection-guard` skill in $HOME — each
# fixture's setup.sh decides whether to install it (present vs absent), because
# the injection-guard-skill presence is the pre-flight gate under test.
set -eu

# 1. Project-local hyphenated SKILL.md at v2.0.0 (Step 2 bumps this exact path).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 2.0.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0023
---
EOF_PROJ_SKILL

# 2. CLAUDE.md with an observability: block but NO injection_guard: block.
#    Step 1 (delegated to /injection-guard init, consent gate 3) is what adds
#    the injection_guard: block; on the before-state it must be absent.
cat > CLAUDE.md <<'EOF_CLAUDE'
# Test fixture CLAUDE.md (migration 0023)

observability:
  spec_version: 0.4.0
  skill: observability
  policy: lib/observability/policy.md
EOF_CLAUDE

# 3. install the `injection-guard` skill into the sandbox $HOME unless the
#    caller opted out (GUARD_SKILL_ABSENT=1). This models the pre-flight gate:
#    present -> migration may apply; absent -> pre-flight aborts (exit 3).
if [ "${GUARD_SKILL_ABSENT:-0}" != "1" ]; then
  mkdir -p "$HOME/.claude/skills/injection-guard"
  cat > "$HOME/.claude/skills/injection-guard/SKILL.md" <<'EOF_GUARD_SKILL'
---
name: injection-guard
version: 0.13.0
implements_spec: 0.6.0
---
EOF_GUARD_SKILL
fi
