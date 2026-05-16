---
id: 0013
slug: auto-init-and-stale-vendored-cleanup
title: Auto-init + stale-vendored-skill cleanup (closes cparx F1 + two-update friction)
from_version: 1.11.0
to_version: 1.12.0
applies_to:
  - .claude/skills/add-observability                  # project-local stale copy — REMOVED if present (Step 1)
  - CLAUDE.md                                         # may gain `observability:` block via chained init (Step 2)
  - .claude/skills/agentic-apps-workflow/SKILL.md     # version bump 1.11.0 → 1.12.0 (Step 3)
requires:
  - skill: add-observability
    install: "(skill ships in scaffolder repo at add-observability/; ~/.claude/skills/add-observability symlink installed by 0012)"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/add-observability/init/INIT.md"
  - tool: claude
    install: "Claude Code CLI; install separately (https://claude.ai/code)"
    verify: "command -v claude >/dev/null"
---

# Migration 0013 — Auto-init + stale-vendored cleanup

Closes two adopter-side frictions surfaced by the cparx v1.10.0+v1.11.0
adoption verification (PR #34's
`.planning/cparx-v1.10.0-adoption-verification/REPORT.md`):

1. **Stale project-local `.claude/skills/add-observability/`** —
   projects that installed the skill at v0.2.x via the
   pre-slash-discovery vendoring pattern have a project-local copy at
   `.claude/skills/add-observability/`. Claude Code's project-scope
   skill loader resolves project-local before user-global, so
   `claude /add-observability init` routes through the vendored
   (v0.2.x) skill — which has no `init` subcommand — yielding
   "unknown subcommand". Step 1 detects this and removes the stale
   copy so the global v0.3.2+ skill (via the 0012 symlink) takes over.

2. **Two-`/update-agenticapps-workflow` flow** — projects that have NOT
   yet run `/add-observability init` hit migration 0011's pre-flight
   abort (`no observability: block`), then must run init manually, then
   re-run `/update-agenticapps-workflow`. Step 2 collapses this to one
   `/update-…` invocation by chaining the init procedure inline when
   no `observability:` metadata is detected.

Step 3 bumps the workflow scaffolder version to `1.12.0`.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at 1.11.0 (or 1.12.0 for re-apply)
grep -qE '^version: 1\.(11\.0|12\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  echo "ABORT: workflow scaffolder version is not 1.11.0."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}

# 2. Refuse the confused state: a project-local add-observability skill
#    at the SAME version as the global one. Should never happen in
#    practice (the install pattern that produced project-local copies
#    pinned to v0.2.x; v0.3.x ships via the 0012 symlink, never as a
#    project-local copy). If it does, the user has hand-vendored the
#    current skill — Step 1's remove-and-defer-to-global heuristic is
#    no longer safe, so refuse and surface the conflict.
if [ -d .claude/skills/add-observability ] && [ -f .claude/skills/add-observability/SKILL.md ]; then
  GLOBAL_SKILL="$HOME/.claude/skills/agenticapps-workflow/add-observability/SKILL.md"
  if [ -f "$GLOBAL_SKILL" ]; then
    LOCAL_VER=$(awk '/^version:/{print $2; exit}'  .claude/skills/add-observability/SKILL.md)
    GLOBAL_VER=$(awk '/^version:/{print $2; exit}' "$GLOBAL_SKILL")
    if [ -n "$LOCAL_VER" ] && [ "$LOCAL_VER" = "$GLOBAL_VER" ]; then
      echo "ABORT: project-local add-observability skill is at the same version"
      echo "       as the global skill (v$LOCAL_VER). This is a confused state —"
      echo "       Step 1 cannot safely choose between them."
      echo ""
      echo "       Resolve manually:"
      echo "         git rm -rf .claude/skills/add-observability    # if global is authoritative"
      echo "       Then re-run /update-agenticapps-workflow."
      exit 3
    fi
  fi
fi

# 3. claude CLI is required for the auto-init chain in Step 2.
command -v claude >/dev/null || { echo "ABORT: claude CLI required"; exit 3; }
```

Pre-flight is permissive on Step 2's path: if `observability:` metadata
is missing the migration does NOT abort — instead Step 2's "Apply"
delegates to the consuming agent to run init in-session (same idiom as
0011 Step 1 delegating to SCAN.md).

## Steps

### Step 1 — Remove stale project-local vendored skill (F1 from cparx report)

**Idempotency check:**

```bash
test ! -e .claude/skills/add-observability
```

(Returns 0 if no project-local copy exists; skip the removal.)

**Pre-condition:** pre-flight passed — version is 1.11.0 (or 1.12.0
for re-apply); confused-state same-version case already refused.

**Apply:**

```bash
if [ -e .claude/skills/add-observability ]; then
  VENDORED_VERSION=$(awk '/^version:/{print $2; exit}' \
    .claude/skills/add-observability/SKILL.md 2>/dev/null)
  GLOBAL_VERSION=$(awk '/^version:/{print $2; exit}' \
    "$HOME/.claude/skills/agenticapps-workflow/add-observability/SKILL.md" 2>/dev/null)

  echo "Migration 0013 Step 1: removing stale project-local add-observability"
  echo "  Project-local: v${VENDORED_VERSION:-unknown} at .claude/skills/add-observability/"
  echo "  Global (will take over): v${GLOBAL_VERSION:-unknown} at \$HOME/.claude/skills/add-observability"
  echo ""
  echo "  Project-local copies were the install pattern pre-v1.11.0;"
  echo "  slash-discovery (migration 0012) makes the global symlink"
  echo "  canonical. Project-local copies shadow the global at"
  echo "  Claude Code's project-scope precedence, causing 'unknown"
  echo "  subcommand: init' on older vendored versions."
  echo ""
  echo "  File count being removed:"
  FILES=$(find .claude/skills/add-observability -type f | wc -l | tr -d ' ')
  echo "    $FILES files under .claude/skills/add-observability/"

  # `git rm` if tracked, else plain rm. Some adopters may have the
  # vendored copy gitignored or untracked — fall through cleanly.
  if git ls-files --error-unmatch .claude/skills/add-observability >/dev/null 2>&1; then
    git rm -rf .claude/skills/add-observability >/dev/null
  else
    rm -rf .claude/skills/add-observability
  fi
fi
```

**Rollback:** the removal can be undone via `git restore` (if tracked)
or by re-vendoring from a prior tag. Documented for completeness; in
practice rollback isn't useful — the v0.2.x vendored copy was the
blocker. Restoring it just re-introduces the blocker.

```bash
# Best-effort: restore from git if the path was tracked at HEAD.
git restore --staged --worktree .claude/skills/add-observability 2>/dev/null || true
```

### Step 2 — Chain init if observability metadata missing (collapses two-update flow)

**Idempotency check:**

```bash
grep -q '^observability:' CLAUDE.md
```

(Returns 0 if `observability:` block already exists; skip the init
chain.)

**Pre-condition:** pre-flight passed; `claude` CLI on PATH (asserted
by pre-flight #3).

**Apply:** the consuming agent (Claude Code session running
`/update-agenticapps-workflow`) follows the init procedure in
`~/.claude/skills/agenticapps-workflow/add-observability/init/INIT.md`,
Phases 1-9, with the working directory set to the project root. This
materialises the wrapper, middleware, policy, entry-file rewrites, and
the `observability:` metadata block in CLAUDE.md.

INIT.md ships 3 consent gates (scaffold, entry-file rewrite, CLAUDE.md
metadata). If the user declines any gate, the migration exits cleanly
with exit 3 and the same rollback hints as a direct
`/add-observability init` invocation.

Concretely:

```
Read ~/.claude/skills/agenticapps-workflow/add-observability/init/INIT.md
Execute Phases 1, 2, 3, 4, 5, 6, 7, 8, 9.
End-state assertion:
  grep -q '^observability:' CLAUDE.md
  (& policy.md exists at the metadata-declared path — Phase 4 invariant)
```

After init returns, re-check the end-state:

```bash
grep -q '^observability:' CLAUDE.md || {
  echo "ABORT: init returned but observability: block not in CLAUDE.md."
  echo "       Migration 0013 cannot continue. Inspect CLAUDE.md and run"
  echo "       'claude /add-observability init' manually to diagnose."
  exit 3
}
```

This step is a no-op on projects that already ran init manually (the
idempotency check passes immediately, no chain occurs).

**Rollback:** the init procedure is itself atomically committable per
Phase 4-6 of INIT.md (each phase commits separately). Rollback of
Step 2 means `git revert` of the init phase commits, which is the
adopter's standard remediation for a declined-after-the-fact init.
Step 2 of this migration does NOT add a separate rollback action.

### Step 3 — Bump workflow scaffolder version

**Idempotency check:**

```bash
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.bak 's/^version: 1\.11\.0$/version: 1.12.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

**Rollback:**

```bash
sed -i.bak 's/^version: 1\.12\.0$/version: 1.11.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Post-checks

```bash
# 1. No project-local add-observability copy lingers
test ! -e .claude/skills/add-observability

# 2. observability: metadata block exists in CLAUDE.md (either pre-
#    existing or created by Step 2's chained init)
grep -q '^observability:' CLAUDE.md

# 3. Workflow scaffolder version bumped
grep -q '^version: 1.12.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

All 3 post-checks return 0 on a successful apply. Re-applying the
migration finds them all green and reports "skipped (already applied)".

## Skip cases

- **`from_version` mismatch** (project is not at 1.11.0) → migration
  framework skips silently per the standard rule.
- **Project-local vendored skill at CURRENT version** → pre-flight #2
  ABORTS with the confused-state message. The user must decide whether
  to delete or keep the local copy.
- **`claude` CLI not in PATH** → pre-flight #3 ABORTS via the standard
  `requires.tool.<name>.verify` path.
- **User declines init consent gate** (Step 2) → migration exits
  3 cleanly. Step 3 does NOT run. Re-running the migration after
  resolving the decline (or running init manually) resumes from Step 2.

## Compatibility

- **Relationship to migration 0011**: 0011's pre-flight #1 ("project
  has run init first") remains correct for v1.9.3 → v1.10.0 path
  (projects on the legacy chain still need to run init manually before
  the v1.10.0 migration). 0013 only chains init forward from v1.11.0.
  0011's pre-flight abort message is updated (in this PR) to mention
  that v1.11.0+ projects get auto-init via 0013.

- **Relationship to migration 0012**: 0012 installs the
  `~/.claude/skills/add-observability` symlink at HOME-global scope.
  Step 1 of 0013 removes the stale project-local copy that would
  otherwise shadow the symlink. Order matters: 0012 must apply first.

- **Spec target**: 0013 makes no spec changes. It's purely a
  user-experience improvement on the migration framework's adopter
  path.

## References

- cparx v1.10.0+v1.11.0 adoption verification: PR #34's
  `.planning/cparx-v1.10.0-adoption-verification/REPORT.md` (F1 +
  the implicit two-update friction in the "How to reproduce" section)
- INIT.md procedure: `add-observability/init/INIT.md` (chained by Step 2)
- Prior migration: `0012-slash-discovery.md` (1.10.0 → 1.11.0)
- ADR-0013 (migration framework): `claude-workflow/docs/decisions/0013-migration-framework.md`
