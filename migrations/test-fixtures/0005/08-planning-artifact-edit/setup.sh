#!/bin/sh
# Phase set up exactly like 03 (plan, no reviews). Hook should still allow
# because the file being edited is a planning artifact.
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
ln -s .planning/phases/01-fake .planning/current-phase
