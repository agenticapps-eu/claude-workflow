#!/bin/sh
# Fixture 03 — idempotent reapply (AFTER state): the migration has already been
# applied. obs skill present; CLAUDE.md repointed to `skill: observability`;
# deterministic phase-sentinel.sh present+executable; Stop block is type:command;
# project SKILL.md at version 2.0.0. A second apply must be a no-op (every
# positive idempotency anchor short-circuits).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Mutate the before-state into the after-state:

# Step 1 applied — repoint add-observability -> observability in CLAUDE.md.
sed -i.bak -E 's/(skill: )add-observability/\1observability/' CLAUDE.md
rm -f CLAUDE.md.bak

# Step 2 applied — write the deterministic phase-sentinel.sh + chmod +x.
mkdir -p .claude/hooks
cat > .claude/hooks/phase-sentinel.sh <<'EOF_PS'
#!/usr/bin/env bash
# phase-sentinel.sh — deterministic Stop hook.
set -euo pipefail
checklist="${CLAUDE_PROJECT_DIR:-$PWD}/.planning/current-phase/checklist.md"
[ -f "$checklist" ] || exit 0
unchecked=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" || true)
[ "${unchecked:-0}" -eq 0 ] && exit 0
echo "Phase Sentinel: $unchecked unchecked item(s) remain in $checklist:" >&2
grep -E '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" | head -5 >&2
exit 2
EOF_PS
chmod +x .claude/hooks/phase-sentinel.sh

# Step 3 applied — swap Stop block to the type:command phase-sentinel hook.
jq '
  .hooks.Stop = (
    [ .hooks.Stop[]
      | select(
          ( [ .hooks[]?
              | select(.type? == "prompt"
                       and ((.prompt? // "") | test("current-phase/checklist.md"))) ]
            | length ) == 0
        )
    ]
    + [ {
          "_hook": "Hook 3 — Phase Sentinel (deterministic shell)",
          "hooks": [
            { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/phase-sentinel.sh", "timeout": 5000 }
          ]
        } ]
  )
' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json

# Step 4 applied — bump project SKILL.md version to 2.0.0.
sed -i.bak -E 's/^version: 1\.(20|21)\.0$/version: 2.0.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
