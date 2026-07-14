#!/bin/sh
# Fixture 01 — BEFORE: project at v2.4.0 claiming 0.4.0, red flags in the
# known-bad pre-0.8.0 ordering, a config whose _enforcement_contract still
# points at the path that never existed and which still carries the dangling
# programmatic_hook, plus the dead hook on disk registered in NO settings.json
# event. The typical fleet state 0027 upgrades.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .planning
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "_enforcement_contract": "docs/workflow/ENFORCEMENT-PLAN.md",
    "context_warnings": true,
    "post_phase": {
      "observability_scan": {
        "enabled": true,
        "skill": "observability:scan",
        "programmatic_hook": ".claude/hooks/observability-postphase-scan.sh"
      }
    }
  }
}
EOF_CFG

# The dead hook on disk + a settings.json that registers a DIFFERENT hook.
mkdir -p .claude/hooks
printf '#!/bin/sh\nexit 0\n' > .claude/hooks/observability-postphase-scan.sh
chmod +x .claude/hooks/observability-postphase-scan.sh
printf '#!/bin/sh\nexit 0\n' > .claude/hooks/session-bootstrap.sh
chmod +x .claude/hooks/session-bootstrap.sh

cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-bootstrap.sh" }
        ]
      }
    ]
  }
}
EOF_SETTINGS
