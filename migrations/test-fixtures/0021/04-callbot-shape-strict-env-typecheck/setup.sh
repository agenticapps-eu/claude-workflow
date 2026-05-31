#!/usr/bin/env bash
# Fixture 0021/04 — D-18 migrated-wrapper SC5 acceptance fixture.
# 1. Seed a v1.19.0 cf-worker wrapper under ./wrapper/ from frozen baseline.
# 2. SKILL.md at 1.19.0 in the project root.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_v1_19_0_worker "wrapper"
