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
  - patch: templates/gsd-patches/patches/workflows/review.md
    install: "test -f ~/.claude/get-shit-done/commands/gsd-review.md || (echo 'ERROR: /gsd-review slash command not installed. Run: bash ~/.config/gsd-patches/bin/sync' && exit 1)"
    verify: "test -f ~/.claude/get-shit-done/commands/gsd-review.md"
optional_for:
  - projects without GSD (no .planning/ directory)
---

# Migration 0005 — Multi-AI plan review enforcement

Brings projects from workflow v1.9.0 to v1.9.1 by installing hook 6 (Multi-AI Plan Review Gate), wiring it into `.claude/settings.json`, and recording it in the enforcement contract. See ADR 0018 for rationale.

## Summary

The multi-AI plan review (`/gsd-review`, producing `{phase}-REVIEWS.md`) was a gsd-patch slash command with no enforcement. Audit of cparx revealed eight consecutive phases (04.9 through 05-handover) executed without it. This migration promotes the review from optional patch to enforced gate.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.9.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.9.0"; exit 1; }

test -f .claude/settings.json || { echo "ERROR: .claude/settings.json missing — was 0000-baseline applied?"; exit 1; }

# Verify gsd-review is installed (or installable).
test -f ~/.claude/get-shit-done/commands/gsd-review.md \
  || { echo "ERROR: /gsd-review not installed. Run: bash ~/.config/gsd-patches/bin/sync"; exit 1; }

# Verify at least 2 reviewer CLIs are present (otherwise the hook would gate against an unreachable target).
AVAILABLE=0
for cli in gemini codex claude coderabbit opencode; do
  command -v "$cli" >/dev/null 2>&1 && AVAILABLE=$((AVAILABLE+1))
done
test "$AVAILABLE" -ge 2 || { echo "ERROR: need at least 2 reviewer CLIs installed (found $AVAILABLE). See ADR 0018."; exit 1; }
```

## Apply

### Step 1 — install hook 6

```bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/hooks/multi-ai-review-gate.sh \
  > .claude/hooks/multi-ai-review-gate.sh
# OR if running from a local checkout:
# cp <workflow-repo>/templates/.claude/hooks/multi-ai-review-gate.sh .claude/hooks/
chmod +x .claude/hooks/multi-ai-review-gate.sh
```

### Step 2 — wire into .claude/settings.json

Append to the PreToolUse hooks array (use `jq` for idempotency):

```bash
jq '.hooks.PreToolUse += [{
  "matcher": "Edit|Write",
  "hooks": [{
    "type": "command",
    "command": "bash .claude/hooks/multi-ai-review-gate.sh"
  }]
}]' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

If the matcher already exists with this hook, the apply step is a no-op.

### Step 3 — bump skill version

```bash
sed -i.bak 's/^version: 1\.9\.0$/version: 1.9.1/' .claude/skills/agentic-apps-workflow/SKILL.md
```

### Step 4 — record in ENFORCEMENT-PLAN (consumer projects with vendored copy)

If `docs/workflow/ENFORCEMENT-PLAN.md` exists in the project (vendored from workflow), add the gate row described in the workflow repo's diff. Otherwise this step is a no-op.

## Verify

```bash
# Hook installed and executable
test -x .claude/hooks/multi-ai-review-gate.sh || exit 1

# Hook wired in settings.json
jq -e '.hooks.PreToolUse[] | select(.hooks[]?.command | test("multi-ai-review-gate"))' .claude/settings.json >/dev/null || exit 1

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
jq '.hooks.PreToolUse |= map(select(.hooks[]?.command | test("multi-ai-review-gate") | not))' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.0/' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Notes

- The hook is **per-project** (lives in `.claude/hooks/`), not global. Hook 5 (commitment re-injector, ADR 0015) is the only global hook.
- Override surfaces are documented in the hook header and ADR 0018. Audit overrides via: `git log -- '*/multi-ai-review-skipped'` to find where the sentinel was committed.
- Backfilling old phases that pre-date this migration is optional and out of scope. The hook gates new edits, not old artifacts.
