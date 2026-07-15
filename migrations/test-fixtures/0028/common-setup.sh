#!/bin/sh
# Sourced by each 0028 fixture setup.sh. Builds a sandbox project (BEFORE state)
# with a hyphenated workflow SKILL.md at 2.5.0 (Step 2's bump floor) and a
# vendored .claude/hooks/ dir. Each fixture writes its own .prettierignore
# (or omits it).
set -eu
mkdir -p .claude/skills/agentic-apps-workflow .claude/hooks
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_SKILL'
---
name: agentic-apps-workflow
version: 2.5.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0028
---

## Stub
EOF_SKILL
printf '#!/usr/bin/env node\n/* eslint-disable */\n' > .claude/hooks/gitnexus-reindex.cjs
