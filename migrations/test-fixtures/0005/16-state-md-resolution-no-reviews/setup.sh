#!/bin/sh
# No current-phase symlink or dir at all. Active phase known only from STATE.md.
mkdir -p .planning/phases/02-active
touch .planning/phases/02-active/02-PLAN.md
cat > .planning/STATE.md <<'EOF'
---
status: executing
---

## Current Phase

Phase 02 — active, executing now.
EOF
