#!/bin/sh
# Fixture 04 — BEFORE: project scaffolder version is below 0031's supported
# floor (2.8.0). Pre-flight rule 1 must refuse before touching anything.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

sed -i.orig 's/^version: 2\.8\.0$/version: 2.6.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.orig

# Also install a stale (old) engine — so a pre-flight bug that skips rule 1
# but still proceeds has something for the verify script's before/after
# comparison to catch (an engine that changes, rather than "stayed absent").
mkdir -p .claude/hooks
make_old_engine > .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
