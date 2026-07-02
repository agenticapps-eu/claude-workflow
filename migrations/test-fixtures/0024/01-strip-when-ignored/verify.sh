#!/bin/sh
# Verify migration 0024 on the BEFORE state (fixture 01): the deterministic
# Step 1 + Step 2 shell, replayed exactly, produces the committed-phases end
# state — and the strip is SURGICAL (siblings + narrow scratch ignore survive).
set -eu

# Pre-conditions (Steps need to apply):
grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore \
  || { echo "PRE: expected a whole-tree .planning/phases/ ignore before apply"; exit 1; }
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.1.0 before apply"; exit 1; }

# ── Step 1 (apply) — the exact sed from 0024 ────────────────────────────────
sed -i.0024.bak -E \
  -e '/^[[:space:]]*\/?\.planning\/phases\/?[[:space:]]*$/d' \
  -e '/^[[:space:]]*\/?\.planning\/?[[:space:]]*$/d' \
  -e '/^[[:space:]]*\/?\.planning\/\*[[:space:]]*$/d' \
  .gitignore
rm -f .gitignore.0024.bak

# Whole-tree ignore GONE
grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore \
  && { echo "STEP 1 failed: whole-tree .planning/phases/ ignore still present"; exit 1; }
# Surgical: stack ignores survive
grep -q '^node_modules/$' .gitignore || { echo "STEP 1 not surgical: node_modules/ dropped"; exit 1; }
grep -q '^dist/$' .gitignore || { echo "STEP 1 not surgical: dist/ dropped"; exit 1; }
grep -q '^\.claude/worktrees/$' .gitignore || { echo "STEP 1 not surgical: .claude/worktrees/ dropped"; exit 1; }
# Surgical: NARROW scratch ignore under the tree survives (anchored patterns spare it)
grep -qF '.planning/phases/*/.codex-review.md' .gitignore \
  || { echo "STEP 1 over-reached: narrow scratch ignore was removed"; exit 1; }

# ── Step 2 (apply) — version bump ───────────────────────────────────────────
sed -i.0024.bak -E 's/^version: 2\.1\.0$/version: 2.2.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0024.bak
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 2 failed: version not bumped to 2.2.0"; exit 1; }

# ── Post-checks (0024) ──────────────────────────────────────────────────────
[ ! -f .gitignore ] || ! grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore \
  || { echo "POST: whole-tree ignore must be gone"; exit 1; }

echo "fixture 01 — whole-tree ignore stripped surgically; version bumped 2.1.0 -> 2.2.0"
