#!/usr/bin/env bash
# common-verify.sh — the post-check assertions shared by the 0032 fixtures.
# Sourced after common-apply.sh. Each failure exits non-zero with a reason.
set -uo pipefail

fail() { echo "FAIL: $*"; exit 1; }

# 1. The gate + producer are installed and executable.
[ -x "$HOME/.agenticapps/bin/openspec-change-gate.sh" ] || fail "gate not installed"
[ -x "$HOME/.agenticapps/bin/run-plan-review.sh" ]      || fail "review producer not installed"

# 2. The git floor is installed and points at the gate.
hooks_dir="$(git rev-parse --git-path hooks)"
[ -x "$hooks_dir/pre-commit" ] || fail "pre-commit not installed"
grep -q 'openspec-change-gate' "$hooks_dir/pre-commit" || fail "pre-commit does not reference the gate"

# 3. The shim replaced the old gate — exactly one PreToolUse binding, old one gone.
[ -x .claude/hooks/openspec-change-gate.sh ] || fail "shim not installed"
[ -e .claude/hooks/multi-ai-review-gate.sh ] && fail "old plan-review gate survived"
n=$(jq '[.hooks.PreToolUse[]?.hooks[]?.command? | select(test("openspec-change-gate"))] | length' .claude/settings.json)
[ "$n" = "1" ] || fail "expected exactly 1 openspec-change-gate binding, got $n"
jq -e '[.hooks.PreToolUse[]?.hooks[]?.command? | select(test("multi-ai-review-gate"))] | length == 0' \
  .claude/settings.json >/dev/null || fail "old gate still bound in settings.json"

# 4. GitNexus is gone from disk AND from every binding.
for f in .claude/hooks/gitnexus-reindex.cjs .claude/scripts/install-gitnexus.sh \
         .claude/scripts/rollback-gitnexus.sh .claude/scripts/index-family-repos.sh .gitnexus; do
  [ -e "$f" ] && fail "gitnexus payload survived: $f"
done
jq -e '[.. | .command? // empty | select(test("gitnexus"))] | length == 0' \
  .claude/settings.json >/dev/null || fail "a gitnexus hook is still bound"

# 5. The config is on the §17 lifecycle with both §18 clauses, and the 0.x tree is gone.
jq -e '.lifecycle.validate.change_gate and .lifecycle.validate.multi_ai_review' \
  .planning/config.json >/dev/null || fail "config missing a §18 validate clause"
jq -e '.implements_spec == "1.0.0" and .front_end == "openspec"' \
  .planning/config.json >/dev/null || fail "config claim/front_end not set to 1.0.0/openspec"
jq -e '(.hooks.pre_execute_gates.multi_ai_plan_review // null) == null' \
  .planning/config.json >/dev/null || fail "standalone plan-review gate survived (§17 MUST NOT)"

# 6. The repo-specific §15 block survived the wholesale restructure.
jq -e '.knowledge_capture.enabled == true' .planning/config.json >/dev/null \
  || fail "knowledge_capture was dropped by the restructure"
jq -er '.knowledge_capture.note' .planning/config.json | grep -q 'sandbox-repo.md' \
  || fail "knowledge_capture.note was replaced by the template default"

# 7. .planning/ is untouched — it is the backup, never a migration target.
[ -f .planning/phases/01-example/PLAN.md ] || fail ".planning/phases was disturbed"
