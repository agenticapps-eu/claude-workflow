#!/usr/bin/env bash
# Fixture 0021/03 — twofold-idempotency SKIP. Seeds a v1.20.0 wrapper
# (cron-monitor.ts at v1.20.0 hash + queue-monitor.ts present). Engine
# 0021 must SKIP_ALREADY per codex M-8 (BOTH idempotency markers satisfied).
# Uses seed_v1_20_0_worker which cp's from LIVE templates — these are the
# v1.20.0 baseline by definition (post Plan 03's edits).
#
# ORDER-OF-OPS NOTE: this fixture only meaningfully tests SKIP behaviour
# AFTER Plan 03 has mutated the live template to v1.20.0 shape. Pre-Plan-03,
# the live cron-monitor.ts still matches the frozen v1.19.0 baseline, so the
# engine would treat this as "already-applied" by mistake (hash matches v1.19.0
# which is also the "should-apply" trigger). This is an intentional RED state;
# the fixture flips to true-GREEN after Plan 03 + Plan 05 land.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_v1_20_0_worker "src/lib/observability"

# Bump SKILL.md to 1.20.0 — completing the "already-applied" simulation.
sed -i.bak 's/^version: 1.19.0$/version: 1.20.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
