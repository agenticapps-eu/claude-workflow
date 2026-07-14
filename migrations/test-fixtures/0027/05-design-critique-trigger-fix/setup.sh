#!/bin/sh
# Fixture 05 — BEFORE: project's .planning/config.json still carries the
# inverted pre-0.9.0 design-critique trigger (`ui_hint_yes &&
# design_shotgun_completed`) — the exact violation final-review Finding 1
# describes. design-shotgun's own trigger is `no_ui_spec_yet`, so the two
# conditions are mutually exclusive: critique could never fire once a
# UI-SPEC.md exists, exactly the case spec §02 requires it to.
#
# Task 2 fixed this literal in templates/config-hooks.json, so fresh installs
# get it via the snapshot — but that alone never reaches a project that
# installed or last upgraded before Task 2 shipped. This fixture is that
# project.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

mkdir -p .planning
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "_enforcement_contract": "docs/ENFORCEMENT-PLAN.md",
    "context_warnings": true,
    "pre_phase": {
      "design_shotgun": {
        "enabled": true,
        "skill": "gstack:design-shotgun",
        "trigger": "ui_hint_yes && no_ui_spec_yet"
      },
      "design_critique": {
        "enabled": true,
        "skill": "impeccable:critique",
        "trigger": "ui_hint_yes && design_shotgun_completed"
      }
    },
    "post_phase": {
      "observability_scan": {
        "enabled": true,
        "skill": "observability:scan"
      }
    }
  }
}
EOF_CFG
