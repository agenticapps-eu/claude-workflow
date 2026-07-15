#!/bin/sh
# Verify migration 0028 is a no-op when .claude/hooks/ is already ignored:
# the idempotency check short-circuits, and applying anyway leaves the file
# byte-identical (no duplicate entry).
set -eu

PI=.prettierignore

# Idempotency check (the exact one 0028 Step 1 uses) must report "already applied".
if [ ! -f "$PI" ] || grep -qE '^\.claude/hooks/?$' "$PI"; then :; else
  echo "PRE: idempotency check should report already-applied for this fixture"; exit 1
fi

apply_step1() {
  if [ -f "$PI" ] && ! grep -qE '^\.claude/hooks/?$' "$PI"; then
    printf '\n# AgenticApps workflow (0028): vendored .claude hooks are .cjs/.sh Node\n# tooling, not app code; exclude from prettier --check.\n.claude/hooks/\n' >> "$PI"
  fi
}

before="$(cat "$PI")"
apply_step1
[ "$before" = "$(cat "$PI")" ] || { echo "not idempotent: apply changed an already-registered .prettierignore"; exit 1; }

n=$(grep -cE '^\.claude/hooks/?$' "$PI")
[ "$n" -eq 1 ] || { echo "duplicate: .claude/hooks/ appears $n times, expected 1"; exit 1; }

echo "OK: 0028 is a no-op when .claude/hooks/ is already ignored (no duplicate)"
exit 0
