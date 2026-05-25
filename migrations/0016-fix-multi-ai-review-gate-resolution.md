---
id: 0016
slug: fix-multi-ai-review-gate-resolution
title: Fix multi-AI review gate phase resolution (hybrid resolver + grandfather guard)
from_version: 1.14.0
to_version: 1.15.0
applies_to:
  - .claude/hooks/multi-ai-review-gate.sh
optional_for:
  - projects without GSD (no .planning/ directory)
---

# Migration 0016 — Fix multi-AI review gate phase resolution

Brings projects from workflow v1.14.0 to v1.15.0 by replacing the
multi-ai-review-gate hook with the ADR 0025 hybrid resolver. The prior hook
assumed `.planning/current-phase` was a symlink and silently never fired in
repos that use it as a sentinel directory. See ADR 0025.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.14.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.14.0"; exit 1; }
test -x .claude/hooks/multi-ai-review-gate.sh || { echo "ERROR: multi-ai-review-gate.sh missing — was 0005 applied?"; exit 1; }
```

## Apply

### Step 1 — replace the hook with the ADR 0025 resolver

**Idempotency check:** `grep -q 'resolver: hybrid (ADR 0025)' .claude/hooks/multi-ai-review-gate.sh`

**Apply:**
```bash
mkdir -p .claude/hooks
curl -fsSL https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/hooks/multi-ai-review-gate.sh \
  > .claude/hooks/multi-ai-review-gate.sh
# OR from a local checkout:
# cp <workflow-repo>/templates/.claude/hooks/multi-ai-review-gate.sh .claude/hooks/
chmod +x .claude/hooks/multi-ai-review-gate.sh
```

### Step 2 — bump skill version

**Idempotency check:** `grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md`

**Apply:**
```bash
sed -i.bak 's/^version: 1\.14\.0$/version: 1.15.0/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Verify

```bash
grep -q 'resolver: hybrid (ADR 0025)' .claude/hooks/multi-ai-review-gate.sh || exit 1
grep -q '^version: 1.15.0$' .claude/skills/agentic-apps-workflow/SKILL.md || exit 1

# Smoke: directory-style current-phase + planned/unreviewed/unexecuted blocks.
tmp=$(mktemp -d) && ( cd "$tmp" \
  && mkdir -p .planning/current-phase .planning/phases/01-x \
  && touch .planning/phases/01-x/01-PLAN.md \
  && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' \
     | bash "$OLDPWD/.claude/hooks/multi-ai-review-gate.sh" >/dev/null 2>&1; \
  test $? -eq 2 ) || { echo "ERROR: gate did not block dir-style current-phase"; rm -rf "$tmp"; exit 1; }
rm -rf "$tmp"

echo "Migration 0016 applied successfully."
```

## Rollback

```bash
# Restore the pre-0016 hook from the workflow repo's 1.14.0 release commit
# (the repo is not git-tagged; use the commit that was HEAD before this
# migration's template change), then revert the version:
sed -i.bak 's/^version: 1\.15\.0$/version: 1.14.0/' .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Notes

- Settings wiring is unchanged (the hook command path is identical to 0005), so
  no `.claude/settings.json` edit is needed.
- Apply order: this migration must run after 0005 (which installs the hook) and
  after 0015. The migration runner applies migrations in ascending id order, so
  0015 → 0016 is automatic; no manual sequencing needed.
- Backfilling pre-existing unreviewed phases stays optional and out of scope.
