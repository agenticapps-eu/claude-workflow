---
id: 0004
slug: programmatic-hooks-architecture-audit
title: Programmatic hooks layer (5) + architecture audit scheduling hook
from_version: 1.3.0
to_version: 1.4.0
applies_to:
  - .claude/hooks/
  - .claude/settings.json
  - templates/ (project copy)
requires:
  - skill: mattpocock-improve-architecture
    install: "git clone https://github.com/mattpocock/skills /tmp/mattpocock-skills && mkdir -p ~/.claude/skills/mattpocock-improve-architecture && cp -r /tmp/mattpocock-skills/skills/engineering/improve-codebase-architecture/. ~/.claude/skills/mattpocock-improve-architecture/"
    verify: "test -f ~/.claude/skills/mattpocock-improve-architecture/SKILL.md"
  - skill: mattpocock-grill-with-docs
    install: "git clone https://github.com/mattpocock/skills /tmp/mattpocock-skills && mkdir -p ~/.claude/skills/mattpocock-grill-with-docs && cp -r /tmp/mattpocock-skills/skills/engineering/grill-with-docs/. ~/.claude/skills/mattpocock-grill-with-docs/"
    verify: "test -f ~/.claude/skills/mattpocock-grill-with-docs/SKILL.md"
optional_for: []
---

# Migration 0004 — Programmatic hooks layer + architecture audit scheduling

Brings projects from AgenticApps workflow v1.3.0 to v1.4.0 by installing
5 project-scoped programmatic hooks, the architecture-audit-check
SessionStart hook, and supporting infrastructure. **Hook 5 (Commitment
Re-Injector) is GLOBAL** and lives at `~/.claude/hooks/`; this migration
does NOT install it into the project — see ADR-0015 for the rationale.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.3.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.3.0"; exit 1; }

test -f ~/.claude/skills/mattpocock-improve-architecture/SKILL.md \
  || { echo "ERROR: install mattpocock-improve-architecture first (see requires)"; exit 1; }
test -f ~/.claude/skills/mattpocock-grill-with-docs/SKILL.md \
  || { echo "ERROR: install mattpocock-grill-with-docs first (see requires)"; exit 1; }

test -f .claude/settings.json || { echo "ERROR: .claude/settings.json missing — was 0000-baseline applied?"; exit 1; }
```

## Steps

### Step 1: Create `.claude/hooks/` directory

**Idempotency check:** `test -d .claude/hooks`
**Pre-condition:** `.claude/` exists
**Apply:** `mkdir -p .claude/hooks`
**Rollback:** `rmdir .claude/hooks 2>/dev/null || true`

### Step 2: Copy 5 hook scripts into `.claude/hooks/`

**Idempotency check:** `test -f .claude/hooks/database-sentinel.sh && test -f .claude/hooks/design-shotgun-gate.sh && test -f .claude/hooks/skill-router-log.sh && test -f .claude/hooks/session-bootstrap.sh && test -f .claude/hooks/architecture-audit-check.sh`
**Pre-condition:** scaffolder templates present at `~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/`
**Apply:**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
for hook in database-sentinel design-shotgun-gate skill-router-log session-bootstrap architecture-audit-check; do
  cp "$SCAFFOLDER/templates/.claude/hooks/${hook}.sh" ".claude/hooks/${hook}.sh"
  chmod +x ".claude/hooks/${hook}.sh"
done
```
**Rollback:** `rm -f .claude/hooks/{database-sentinel,design-shotgun-gate,skill-router-log,session-bootstrap,architecture-audit-check}.sh`

### Step 3: Merge hook entries into `.claude/settings.json`

**Idempotency check:** `jq -e '.hooks.PreToolUse[]? | select(.hooks[].command | contains("database-sentinel"))' .claude/settings.json >/dev/null 2>&1`
**Pre-condition:** `.claude/settings.json` parses as JSON; scaffolder template at `~/.claude/skills/agenticapps-workflow/templates/claude-settings.json`
**Apply (deterministic via jq):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
HOOKS_TPL=$(jq '.hooks' "$SCAFFOLDER/templates/claude-settings.json")
jq --argjson tpl "$HOOKS_TPL" '
  .hooks //= {} |
  .hooks.PreToolUse = ((.hooks.PreToolUse // []) + ($tpl.PreToolUse // [])) |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) + ($tpl.PostToolUse // [])) |
  .hooks.Stop = ((.hooks.Stop // []) + ($tpl.Stop // [])) |
  .hooks.SessionStart = ((.hooks.SessionStart // []) + ($tpl.SessionStart // []))
' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

The merge is **append**, not replace — projects with existing
SessionStart hooks (or others) keep them; the AgenticApps hooks are
added alongside. Deduplication: re-running this step would re-append,
but the idempotency check above catches that (database-sentinel only
gets registered once).

**Rollback (filter out our entries by command path):**
```bash
jq '
  .hooks.PreToolUse |= map(select(.hooks[].command | contains("$CLAUDE_PROJECT_DIR/.claude/hooks/") | not)) |
  .hooks.PostToolUse |= map(select(.hooks[].command | contains("$CLAUDE_PROJECT_DIR/.claude/hooks/") | not)) |
  .hooks.Stop |= map(select((.hooks[].type // "command") != "prompt" or ((.hooks[].prompt // "") | contains(".planning/current-phase/checklist.md") | not))) |
  .hooks.SessionStart |= map(select(.hooks[].command | contains("$CLAUDE_PROJECT_DIR/.claude/hooks/") | not))
' .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

### Step 4: Bump installed version field

**Idempotency check:** `grep -q '^version: 1.4.0' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** `.claude/skills/agentic-apps-workflow/SKILL.md` exists with `version: 1.3.0`
**Apply:** Edit the file frontmatter to change `version: 1.3.0` → `version: 1.4.0`.
**Rollback:** Edit `version: 1.4.0` → `version: 1.3.0`.

## Post-checks

```bash
# Hook scripts present
test -f .claude/hooks/database-sentinel.sh
test -f .claude/hooks/design-shotgun-gate.sh
test -f .claude/hooks/skill-router-log.sh
test -f .claude/hooks/session-bootstrap.sh
test -f .claude/hooks/architecture-audit-check.sh

# All executable
test -x .claude/hooks/database-sentinel.sh
test -x .claude/hooks/design-shotgun-gate.sh
test -x .claude/hooks/skill-router-log.sh
test -x .claude/hooks/session-bootstrap.sh
test -x .claude/hooks/architecture-audit-check.sh

# Settings has all hook registrations
jq -e '.hooks.PreToolUse[]? | select(.hooks[].command | contains("database-sentinel"))' .claude/settings.json >/dev/null
jq -e '.hooks.PreToolUse[]? | select(.hooks[].command | contains("design-shotgun-gate"))' .claude/settings.json >/dev/null
jq -e '.hooks.PostToolUse[]? | select(.hooks[].command | contains("skill-router-log"))' .claude/settings.json >/dev/null
jq -e '.hooks.Stop[]? | select(.hooks[].type == "prompt")' .claude/settings.json >/dev/null
jq -e '.hooks.SessionStart[]? | select(.hooks[].command | contains("session-bootstrap"))' .claude/settings.json >/dev/null
jq -e '.hooks.SessionStart[]? | select(.hooks[].command | contains("architecture-audit-check"))' .claude/settings.json >/dev/null

# Version bumped
grep -q '^version: 1.4.0' .claude/skills/agentic-apps-workflow/SKILL.md
```

The update skill runs each post-check and reports any failures.

## ADR opportunities

After this migration, the update skill prompts: "Want to draft project
ADRs for the new gates? Three options: (a) ADRs per hook (5 ADRs), (b)
one bundled ADR, (c) skip — accept upstream ADRs as the rationale."
Default: (c). Upstream ADRs (0014–0017 in the workflow scaffolder repo)
are the canonical rationale; per-project ADRs are only needed for
overrides (e.g. weakening a regex pattern in database-sentinel.sh, or
disabling Hook 3 entirely).

## Skip cases

- **Project not at v1.3.0** — pre-flight blocks. The update skill chains
  earlier migrations first.
- **Required mattpocock skills not installed** — pre-flight blocks. User
  must install via the `requires` block commands.
- **`.claude/settings.json` missing** — pre-flight blocks; suggests
  re-running setup.
- **Already at 1.4.0** — every step's idempotency check returns 0;
  migration short-circuits to "0 of 4 steps applied".

## Notes

This migration does NOT install **Hook 5 (Commitment Re-Injector)** —
that hook is GLOBAL (lives at `~/.claude/hooks/commitment-reinject.sh`)
and registered in `~/.claude/settings.json`. Per ADR-0015 + Q5, Hook 5
is a one-time-per-machine install, not a per-project migration step.
The user is expected to install it once via:

```bash
cp ~/.claude/skills/agenticapps-workflow/templates/global-hooks/commitment-reinject.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/commitment-reinject.sh
# Then add a SessionStart matcher: compact entry to ~/.claude/settings.json
```

Or — for the ergonomic path — Phase 5 ships `bin/install-global-hooks.sh`
that handles this. (Future improvement: roll Hook 5 install into
this migration's pre-flight.)
