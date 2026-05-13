#!/bin/sh
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
# 3-line stub REVIEWS.md (under the 5-line floor).
printf 'line1\nline2\nline3\n' > .planning/phases/01-fake/01-REVIEWS.md
ln -s .planning/phases/01-fake .planning/current-phase
