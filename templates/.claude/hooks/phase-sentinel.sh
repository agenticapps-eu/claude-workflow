#!/usr/bin/env bash
# phase-sentinel.sh — deterministic Stop hook.
# Allows stop unless .planning/current-phase/checklist.md exists AND
# contains unchecked `- [ ]` items.

set -euo pipefail

checklist="${CLAUDE_PROJECT_DIR:-$PWD}/.planning/current-phase/checklist.md"

[ -f "$checklist" ] || exit 0

unchecked=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" || true)
[ "${unchecked:-0}" -eq 0 ] && exit 0

echo "Phase Sentinel: $unchecked unchecked item(s) remain in $checklist:" >&2
# `|| true`: under `set -euo pipefail`, `head -5` closing the pipe early (>5 items)
# kills grep with SIGPIPE, making the pipeline non-zero and exiting the script before
# `exit 2`. Swallowing the status guarantees the block contract (exit 2) always holds.
grep -E '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" | head -5 >&2 || true
exit 2
