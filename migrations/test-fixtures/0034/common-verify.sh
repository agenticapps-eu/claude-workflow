#!/usr/bin/env bash
# common-verify.sh — migration 0034's Post-checks, replayed against the sandbox.
# Every assertion mirrors a numbered clause of the migration's `## Post-checks`.
set -uo pipefail
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
fail() { echo "FAIL: $*"; exit 1; }

# 1. The vendored file is the companion, byte-identical to the scaffolder's copy.
if [ -f .claude/claude-md/workflow.md ]; then
  cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md \
    || fail "post-check 1: workflow.md is not byte-identical to the vendored source"
  grep -q '^> \*\*Authoritative source:' .claude/claude-md/workflow.md \
    || fail "post-check 1: companion is missing the Authoritative-source sentinel"
fi

# 2. It no longer duplicates the SKILL's rule blocks.
if [ -f .claude/claude-md/workflow.md ]; then
  grep -qE '^#{2,4} [0-9]+ Red Flags' .claude/claude-md/workflow.md \
    && fail "post-check 2: workflow.md still restates a Red Flags block"
  grep -q '^## Workflow commitment$' .claude/claude-md/workflow.md \
    && fail "post-check 2: workflow.md still restates the commitment ritual"
  grep -q 'If you think\.\.\.' .claude/claude-md/workflow.md \
    && fail "post-check 2: workflow.md still restates the rationalization table"
fi

# 3. The SKILL still carries them.
grep -q '^## 14 Red Flags — STOP → DELETE → RESTART$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 3: the installed SKILL lost the canonical §04 block"
grep -q 'If you think\.\.\.' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 3: the installed SKILL lost the rationalization table"

# 4. 0033's guarantee is not regressed.
for f in .claude/claude-md/workflow.md .claude/workflow-config.md; do
  if [ -f "$f" ]; then
    grep -qiE '/gsd-|GSD state|gsd-execute-phase' "$f" \
      && fail "post-check 4: $f re-acquired a GSD reference"
  fi
done

# 5. ADVISORY, not an assertion — see the migration's post-check 5. 0034 never
#    touches CLAUDE.md, and four consuming repos deliberately stopped linking
#    the vendored file, which would fail a migration that did nothing wrong.
if [ -f .claude/claude-md/workflow.md ] && ! grep -q "claude-md/workflow.md" CLAUDE.md; then
  echo "NOTE: CLAUDE.md does not link the vendored companion — it is orphaned here."
fi

# 6. Version bumped; spec claim unchanged.
grep -q '^version: 3.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 6: SKILL.md is not at version 3.2.0"
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || fail "post-check 6: implements_spec moved off 1.0.0"
