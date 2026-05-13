#!/bin/sh
# Same shape as fixture 03 (active phase, plan present, no reviews) but the
# edit target is a non-.planning PLAN.md. FLAG-A fix means the bypass list
# requires .planning/ prefix; basename alone no longer triggers bypass.
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
ln -s .planning/phases/01-fake .planning/current-phase
