#!/bin/sh
# Fixture 03 — BEFORE: project has NO .prettierignore. Migration 0028 must NOT
# create one (append-if-exists only): a project without a .prettierignore never
# configured Prettier ignores, and creating the file would imply tooling it
# does not use.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
# deliberately no .prettierignore
