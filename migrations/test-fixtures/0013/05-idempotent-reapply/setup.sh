#!/bin/sh
# Fixture 05 — project already at v1.12.0 (post-apply). All 3 steps
# should report "already applied".
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Bump project SKILL.md to v1.12.0 (the to_version state).
sed -i.bak 's/^version: 1\.11\.0$/version: 1.12.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak

# observability: block present (post-init).
cat >> CLAUDE.md <<'EOF_OBS'

observability:
  spec_version: 0.3.0
  policy: lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
EOF_OBS
