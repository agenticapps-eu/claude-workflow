#!/bin/sh
# Fixture 10 — pre-flight rule 4's two remaining refusal shapes. A blank
# line between provenance and heading is NOT one of them (see fixture 11 —
# that is prettier's normal spacing and callbot's real committed shape).
# Both shapes below still refuse:
#   (a) the heading sits ABOVE its provenance line — silent non-convergence,
#       since extract_block/Apply only start looking for the heading AFTER
#       matching the provenance line.
#   (b) non-blank content sits between the provenance line and the heading —
#       the provenance does not plainly belong to this heading.
# Testing two distinct malformed shapes needs two distinct CLAUDE.md files,
# so verify.sh builds each one itself; this setup.sh only lays down the
# common scaffolder + SKILL.md state both shapes need.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
