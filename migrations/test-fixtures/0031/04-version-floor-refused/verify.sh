#!/bin/sh
# Verify pre-flight rule 1 refuses a project below the 2.8.0 floor, and
# leaves both the SKILL.md version and the engine untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

skill_before="$(cat .claude/skills/agentic-apps-workflow/SKILL.md)"
engine_before="$(cksum .claude/hooks/gitnexus-reindex.cjs)"

out="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted a project at version 2.6.0 (below the"
  echo "      2.8.0 floor)"
  exit 1
}

# Assert refusal came from rule 1 (version floor), not some other rule
# firing by accident on the malformed state rule 1 exists to catch.
printf '%s' "$out" | grep -q 'workflow scaffolder version is' || {
  echo "FAIL: pre-flight refused, but not via rule 1 (version floor) — got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

[ "$skill_before" = "$(cat .claude/skills/agentic-apps-workflow/SKILL.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated SKILL.md"
  exit 1
}
[ "$engine_before" = "$(cksum .claude/hooks/gitnexus-reindex.cjs)" ] || {
  echo "FAIL: refusing pre-flight still mutated the engine file"
  exit 1
}

echo "OK: pre-flight refused a project below the 2.8.0 version floor;"
echo "    SKILL.md and the engine file both left untouched"
exit 0
