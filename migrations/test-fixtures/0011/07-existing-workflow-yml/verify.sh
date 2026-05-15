#!/bin/sh
# After Step 1 simulated apply: workflow matches scaffolder; backup file exists.
set -eu

cmp -s "$HOME/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml" .github/workflows/observability.yml || { echo "FAIL: workflow doesn't match scaffolder copy after Step 1"; exit 1; }

BAK_COUNT=$(ls .github/workflows/observability.yml.bak.* 2>/dev/null | wc -l | tr -d ' ')
[ "$BAK_COUNT" -ge 1 ] || { echo "FAIL: no .bak backup file produced"; exit 1; }

# Confirm backup content matches the original (custom) workflow, not the new one.
BAK_FILE=$(ls .github/workflows/observability.yml.bak.* | head -1)
grep -q 'Custom observability' "$BAK_FILE" || { echo "FAIL: backup doesn't contain pre-existing content"; exit 1; }

echo "fixture 07 — pre-existing workflow backed up to .bak, overwritten with scaffolder copy"
