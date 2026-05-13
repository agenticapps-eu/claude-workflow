#!/bin/sh
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
# Write a 6-line REVIEWS.md so it clears the >5 line floor.
printf 'line1\nline2\nline3\nline4\nline5\nline6\n' > .planning/phases/01-fake/01-REVIEWS.md
ln -s .planning/phases/01-fake .planning/current-phase
