#!/bin/sh
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
ln -s .planning/phases/01-fake .planning/current-phase
# Marker file: if the hostile string were executed, it would be deleted.
# Driver should assert this file still exists after the hook runs.
mkdir -p /tmp
touch /tmp/HOSTILE_MARKER
