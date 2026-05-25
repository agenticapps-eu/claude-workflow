#!/bin/sh
mkdir -p .planning/current-phase
mkdir -p .planning/phases/01-fake
touch .planning/phases/01-fake/01-PLAN.md
# SUMMARY present => phase already executed => grandfathered, must NOT block.
touch .planning/phases/01-fake/01-01-SUMMARY.md
