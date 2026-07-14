#!/bin/sh
# Fixture 04 — BEFORE: a project that DELIBERATELY wired
# observability-postphase-scan.sh into a real settings.json event. Step 5 must
# leave it alone: the migration removes a DEAD hook, never a live one.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .claude/hooks
printf '#!/bin/sh\nexit 0\n' > .claude/hooks/observability-postphase-scan.sh
chmod +x .claude/hooks/observability-postphase-scan.sh

cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/observability-postphase-scan.sh" }
        ]
      }
    ]
  }
}
EOF_SETTINGS
