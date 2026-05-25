#!/bin/sh
# current-phase is a DIRECTORY (the design-shotgun/db-sentinel convention),
# not a symlink. This is the real-world state in cparx/fx-signal-agent/callbot.
mkdir -p .planning/current-phase
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
