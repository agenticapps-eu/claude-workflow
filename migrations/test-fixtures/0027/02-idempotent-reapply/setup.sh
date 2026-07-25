#!/bin/sh
# Fixture 02 — BEFORE: 0027 ALREADY applied (v2.5.0, claim 0.9.0, section
# present, red flags reordered, pointer repointed, dangling hook ref dropped,
# dead hook already gone). Re-running every step must change nothing.
set -eu
SKILL_VERSION=2.5.0 SPEC_CLAIM=0.9.0 RED_FLAGS=fixed . "$FIXTURES_ROOT/common-setup.sh"

# Splice the real section in from the scaffolder, before the ritual tail —
# exactly what a first apply would have produced.
TARGET=.claude/skills/agentic-apps-workflow/SKILL.md
awk '/^## Spec deltas \(spec /{f=1}
     f && /^## Knowledge Capture — Ritual Tail/{exit}
     f' "$REPO_ROOT/skill/SKILL.md" > .section

awk -v secfile=.section '
  /^## Knowledge Capture — Ritual Tail/ && !done {
    while ((getline line < secfile) > 0) print line
    close(secfile)
    done = 1
  }
  { print }
' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
rm -f .section

mkdir -p .planning
cat > .planning/config.json <<'EOF_CFG'
{
  "hooks": {
    "_enforcement_contract": "docs/ENFORCEMENT-PLAN.md",
    "context_warnings": true,
    "post_phase": {
      "observability_scan": {
        "enabled": true,
        "skill": "observability:scan"
      }
    }
  }
}
EOF_CFG

# Post-0027 hook state: the dead hook is gone; the live one remains registered.
mkdir -p .claude/hooks
printf '#!/bin/sh\nexit 0\n' > .claude/hooks/session-bootstrap.sh
chmod +x .claude/hooks/session-bootstrap.sh

cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": ".claude/hooks/session-bootstrap.sh" }
        ]
      }
    ]
  }
}
EOF_SETTINGS
