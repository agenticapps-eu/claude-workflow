#!/bin/sh
# Materialize the 02-no-plans shape in $PWD (test-driver chdirs into a tmp dir first).
mkdir -p .planning/phases/01-fake
ln -s .planning/phases/01-fake .planning/current-phase
