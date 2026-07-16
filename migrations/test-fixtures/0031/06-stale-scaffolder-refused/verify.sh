#!/bin/sh
# Verify pre-flight rule 2 refuses a scaffolder clone that predates 0031 (no
# vendored engine at setup/snapshot/hooks/gitnexus-reindex.cjs), and leaves
# the project's engine and SKILL.md untouched.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0031/common-verify.sh"

test ! -f "$HOME/.claude/skills/agenticapps-workflow/setup/snapshot/hooks/gitnexus-reindex.cjs" || {
  echo "FAIL: fixture setup left a vendored engine in place — this fixture"
  echo "      cannot exercise the stale-scaffolder-clone case."
  exit 1
}

skill_before="$(cat .claude/skills/agentic-apps-workflow/SKILL.md)"
engine_before="$(cksum .claude/hooks/gitnexus-reindex.cjs)"

out="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted a scaffolder clone with no vendored engine"
  exit 1
}

# Assert refusal came from rule 2 (stale scaffolder clone), not rule 1.
printf '%s' "$out" | grep -q 'predates 0031' || {
  echo "FAIL: pre-flight refused, but not via rule 2 (stale scaffolder"
  echo "      clone) — got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

[ "$skill_before" = "$(cat .claude/skills/agentic-apps-workflow/SKILL.md)" ] || {
  echo "FAIL: refusing pre-flight still mutated SKILL.md"
  exit 1
}
[ "$engine_before" = "$(cksum .claude/hooks/gitnexus-reindex.cjs)" ] || {
  echo "FAIL: refusing pre-flight still mutated the project's engine file"
  exit 1
}

echo "OK: pre-flight refused a scaffolder clone predating 0031 (no vendored"
echo "    engine); project's SKILL.md and engine both left untouched"
exit 0
