#!/usr/bin/env bash
# common-verify.sh — migration 0033's Post-checks, replayed against the sandbox.
#
# Sourced by each fixture's verify.sh AFTER common-apply.sh. Every assertion
# here mirrors a numbered clause of the migration's `## Post-checks` block.
set -uo pipefail
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
fail() { echo "FAIL: $*"; exit 1; }

# 1. No GSD command reference survives in either vendored document.
for f in .claude/claude-md/workflow.md .claude/workflow-config.md; do
  if [ -f "$f" ]; then
    grep -qiE '/gsd-|GSD state|gsd-execute-phase' "$f" \
      && fail "post-check 1: $f still carries a GSD reference"
  fi
done

# 2. The vendored workflow reference is byte-identical to the scaffolder's copy.
if [ -f .claude/claude-md/workflow.md ]; then
  cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md \
    || fail "post-check 2: workflow.md is not byte-identical to the vendored source"
fi

# 3. Both documents now teach the OpenSpec lifecycle.
if [ -f .claude/claude-md/workflow.md ]; then
  grep -q 'openspec/changes/' .claude/claude-md/workflow.md \
    || fail "post-check 3: workflow.md does not mention openspec/changes/"
fi
if [ -f .claude/workflow-config.md ]; then
  grep -q '`lifecycle`' .claude/workflow-config.md \
    || fail "post-check 3: workflow-config.md does not mention the lifecycle block"
fi

# 4. Step 2 preserved the project's substituted config.
if [ -f .claude/workflow-config.md ]; then
  grep -q '{{PROJECT_NAME}}' .claude/workflow-config.md \
    && fail "post-check 4: the template's placeholders were copied back in"
  grep -q '^## Project$' .claude/workflow-config.md \
    || fail "post-check 4: the project's own config section was clobbered"
fi

# 5. §04 reconciled: the red-flag block in the vendored workflow reference is
#    byte-identical to the canonical block in the installed trigger skill.
if [ -f .claude/claude-md/workflow.md ]; then
  _rf() {
    awk '/^## 14 Red Flags — STOP → DELETE → RESTART$/ { f=1; print; next }
         f && /^## / { exit }
         f { print }' "$1"
  }
  _x="$(mktemp)"; _y="$(mktemp)"
  _rf .claude/skills/agentic-apps-workflow/SKILL.md > "$_x"
  _rf .claude/claude-md/workflow.md > "$_y"
  [ -s "$_x" ] || fail "post-check 5: no canonical red-flag block in the installed SKILL.md"
  # Absent is as correct as identical: 0034's companion removed the duplicate
  # instead of keeping two copies pinned. Only present-and-different is a defect.
  if [ -s "$_y" ]; then
    cmp -s "$_x" "$_y" || fail "post-check 5: red-flag block diverges from the canonical"
  fi
  rm -f "$_x" "$_y"
fi

# 6. Version bumped; spec claim unchanged.
cmp -s "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
       .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 6: SKILL.md is not the scaffolder's copy"
_v="$(awk '/^version:/{print $2; exit}' .claude/skills/agentic-apps-workflow/SKILL.md)"
[ "$(printf '3.1.0\n%s\n' "$_v" | sort -V | head -n1)" = "3.1.0" ] \
  || fail "post-check 6: SKILL.md is at $_v, below the 3.1.0 floor this migration sets"
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 6: implements_spec moved off 1.0.0"

# 7. Nothing else moved.
[ -f .planning/phases/01-example/PLAN.md ] || fail "post-check 7: .planning/ was touched"
