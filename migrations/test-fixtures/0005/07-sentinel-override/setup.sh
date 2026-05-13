#!/bin/sh
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
touch .planning/phases/01-fake/multi-ai-review-skipped
ln -s .planning/phases/01-fake .planning/current-phase
