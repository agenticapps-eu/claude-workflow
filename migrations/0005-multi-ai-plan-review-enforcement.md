---
id: 0005
slug: multi-ai-plan-review-enforcement
title: Enforce multi-AI plan review (/gsd-review) as a contract gate
from_version: 1.9.0
to_version: 1.9.1
applies_to:
  - .claude/hooks/multi-ai-review-gate.sh
  - .claude/settings.json
  - docs/workflow/ENFORCEMENT-PLAN.md (in consumer projects, if vendored)
  - templates/config-hooks.json (workflow repo only)
requires:
  - skill: gsd-review
    install: "test -f ~/.claude/skills/gsd-review/SKILL.md || (echo 'ERROR: /gsd-review Claude Code skill not installed. The skill file must exist at ~/.claude/skills/gsd-review/SKILL.md. Sources vary by setup — see your get-shit-done install or dotfiles.' && exit 1)"
    verify: "test -f ~/.claude/skills/gsd-review/SKILL.md"
optional_for:
  - projects without GSD (no .planning/ directory)
---

# Migration 0005 — Multi-AI plan review enforcement

Brings projects from workflow v1.9.0 to v1.9.1 by installing hook 6 (Multi-AI Plan Review Gate), wiring it into `.claude/settings.json`, and recording it in the enforcement contract. See ADR 0018 for rationale.

## Summary

The multi-AI plan review (`/gsd-review`, producing `{phase}-REVIEWS.md`) was a gsd-patch slash command with no enforcement. Audit of cparx revealed eight consecutive phases (04.9 through 05-handover) executed without it. This migration promotes the review from optional patch to enforced gate.

## Pre-flight

```bash
# FLAG-E fix: trim trailing whitespace / CRLF on the version line so the equality
# check survives slightly malformed SKILL.md.
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.9.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.9.0"; exit 1; }

test -f .claude/settings.json || { echo "ERROR: .claude/settings.json missing — was 0000-baseline applied?"; exit 1; }
jq empty .claude/settings.json 2>/dev/null || { echo "ERROR: .claude/settings.json exists but is not valid JSON"; exit 1; }

# Verify /gsd-review is installed as a Claude Code skill. The slash command
# resolves through ~/.claude/skills/gsd-review/SKILL.md; that skill's
# <execution_context> delegates to ~/.claude/get-shit-done/workflows/review.md.
# The skill file is the load-bearing contract for slash-command discovery, so
# we verify it specifically (not the delegated workflow body).
test -f ~/.claude/skills/gsd-review/SKILL.md \
  || { echo "ERROR: /gsd-review Claude Code skill not installed. The skill file must exist at ~/.claude/skills/gsd-review/SKILL.md. Sources vary by setup — see your get-shit-done install or dotfiles."; exit 1; }

# Verify at least 2 reviewer CLIs are present (otherwise the hook would gate against an unreachable target).
AVAILABLE=0
for cli in gemini codex claude coderabbit opencode; do
  command -v "$cli" >/dev/null 2>&1 && AVAILABLE=$((AVAILABLE+1))
done
test "$AVAILABLE" -ge 2 || { echo "ERROR: need at least 2 reviewer CLIs installed (found $AVAILABLE). See ADR 0018."; exit 1; }
```

## Apply

### Step 1 — install hook 6

**Idempotency check:** `test -x .claude/hooks/multi-ai-review-gate.sh`

**Apply:**
```bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/hooks/multi-ai-review-gate.sh \
  > .claude/hooks/multi-ai-review-gate.sh
# OR if running from a local checkout:
# cp <workflow-repo>/templates/.claude/hooks/multi-ai-review-gate.sh .claude/hooks/
chmod +x .claude/hooks/multi-ai-review-gate.sh
```

### Step 2 — wire into .claude/settings.json

**Idempotency check:** `jq -e '.hooks.PreToolUse[]? | select(.hooks[]?.command? | strings | test("multi-ai-review-gate"))' .claude/settings.json >/dev/null`

**Apply (BLOCK-1 fix — guarded merge, append-only-if-absent):**
```bash
jq 'if (.hooks.PreToolUse // []) | any(.hooks[]?.command? | strings | test("multi-ai-review-gate"))
    then .
    else .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
      "matcher": "Edit|Write|MultiEdit",
      "hooks": [{
        "type": "command",
        "command": "bash .claude/hooks/multi-ai-review-gate.sh"
      }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

The `any(...)` guard checks whether *any* existing PreToolUse hook entry already references `multi-ai-review-gate`; if yes, the jq filter is a no-op. Re-running the migration cannot duplicate the hook entry. This replaces the prior unconditional `+=` which would silently double the entry on re-apply.

### Step 3 — bump skill version

**Idempotency check:** `grep -q '^version: 1.9.1$' .claude/skills/agentic-apps-workflow/SKILL.md`

**Apply (FLAG-C fix — clean up `.bak` immediately):**
```bash
sed -i.bak 's/^version: 1\.9\.0$/version: 1.9.1/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

### Step 4 — record in ENFORCEMENT-PLAN (consumer projects with vendored copy)

**Idempotency check:** `grep -q '/gsd-review' docs/workflow/ENFORCEMENT-PLAN.md` (only relevant if the file is vendored)

If `docs/workflow/ENFORCEMENT-PLAN.md` exists in the project (vendored from workflow), add the gate row described in the workflow repo's diff. Otherwise this step is a no-op.

## Verify

```bash
# Hook installed and executable
test -x .claude/hooks/multi-ai-review-gate.sh || exit 1

# Hook wired in settings.json — exactly one entry (idempotency strict-check)
COUNT=$(jq '[.hooks.PreToolUse[]? | select(.hooks[]?.command? | strings | test("multi-ai-review-gate"))] | length' .claude/settings.json)
test "$COUNT" = "1" || { echo "ERROR: expected 1 multi-ai-review-gate hook entry in settings.json, got $COUNT"; exit 1; }

# Version bumped
grep -q '^version: 1.9.1$' .claude/skills/agentic-apps-workflow/SKILL.md || exit 1

# Smoke test — hook returns 0 when no active phase
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.txt"}}' | bash .claude/hooks/multi-ai-review-gate.sh
test $? -eq 0 || exit 1

echo "Migration 0005 applied successfully."
```

## Rollback

```bash
rm -f .claude/hooks/multi-ai-review-gate.sh
jq '.hooks.PreToolUse |= map(select(.hooks[]?.command? | strings | test("multi-ai-review-gate") | not))' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.0/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Notes

- The hook is **per-project** (lives in `.claude/hooks/`), not global. Hook 5 (commitment re-injector, ADR 0015) is the only global hook.
- Override surfaces are documented in the hook header and ADR 0018. Audit overrides via (NOTE-4 fix — sentinel sits 3 levels deep under `.planning/phases/N/`): `git log --diff-filter=A --all -- '*multi-ai-review-skipped*'` (or `git log -- '**/multi-ai-review-skipped'` if shell globstar is enabled).
- Backfilling old phases that pre-date this migration is optional and out of scope. The hook gates new edits, not old artifacts.
