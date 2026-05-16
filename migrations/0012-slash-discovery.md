---
id: 0012
slug: slash-discovery
title: Slash-command discovery wire-up (closes #22)
from_version: 1.10.0
to_version: 1.11.0
applies_to:
  # NOTE: this migration's applies_to references a path OUTSIDE the project
  # tree (`~/.claude/skills/...`). This is novel for the migrations framework
  # — existing migrations reference project-relative paths only. The verify
  # step uses `test -L` (POSIX) so cross-platform support is fine; the
  # cross-tree path is documented here so a future maintainer doesn't take
  # it as a precedent for arbitrary host-system mutation.
  - ~/.claude/skills/add-observability                 # symlink — creates if missing
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 1.10.0 → 1.11.0
requires:
  - skill: agentic-apps-workflow
    install: "(scaffolder install — see README)"
    verify: "test -d $HOME/.claude/skills/agenticapps-workflow/add-observability"
---

# Migration 0012 — Slash-command discovery wire-up

> **Scope note (for future maintainers):** `init/INIT.md` is delivered
> via the scaffolder skill repo at v1.11.0 (T4 of phase 15 ships it as
> part of the `add-observability` skill itself). **This migration's role
> is discovery wire-up only** — it ensures projects already on v1.10.0
> can invoke `/add-observability init` after the scaffolder updates.
> Issue #26 is closed by the scaffolder skill bump (T12 — `add-observability/SKILL.md`
> version 0.3.0 → 0.3.1), not by this migration.

## Summary

Backports the slash-discovery fix from PR #22 to projects already on
workflow v1.10.0. After this migration:

- `$HOME/.claude/skills/add-observability` is a symlink to
  `$HOME/.claude/skills/agenticapps-workflow/add-observability/`, the
  scaffolder's canonical skill copy.
- Claude Code's skill loader discovers `/add-observability` at HOME-
  global scope, so the slash command is invocable from any session.
- The workflow scaffolder version is bumped 1.10.0 → 1.11.0.

Fresh-install projects (running the full migration chain from baseline)
get the equivalent fix from migration 0002 Step 4 (added in scaffolder
v1.11.0). This migration is the upgrade path for projects that already
applied 0002 in its pre-v1.11.0 form.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at 1.10.0 (or 1.11.0 for re-apply)
grep -qE '^version: 1\.(10\.0|11\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  echo "ABORT: workflow scaffolder version is not 1.10.0."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}

# 2. Scaffolder must be at the canonical global path. Discovery via symlink
#    relies on this.
test -d "$HOME/.claude/skills/agenticapps-workflow/add-observability" || {
  echo "ABORT: scaffolder not installed at \$HOME/.claude/skills/agenticapps-workflow/."
  echo "       Install it:"
  echo "         git clone https://github.com/agenticapps-eu/claude-workflow.git \$HOME/.claude/skills/agenticapps-workflow"
  echo "         \$HOME/.claude/skills/agenticapps-workflow/install.sh"
  echo "       Then re-run /update-agenticapps-workflow."
  exit 3
}

# 3. If $HOME/.claude/skills/add-observability exists and is NOT a symlink,
#    refuse to clobber. The user must remove it manually.
if [ -e "$HOME/.claude/skills/add-observability" ] && [ ! -L "$HOME/.claude/skills/add-observability" ]; then
  echo "ABORT: \$HOME/.claude/skills/add-observability exists and is not a symlink."
  echo "       Inspect it; if safe to replace, run:"
  echo "         rm -rf \$HOME/.claude/skills/add-observability"
  echo "       and re-run /update-agenticapps-workflow."
  exit 3
fi

# 4. If a symlink exists pointing to a wrong target (not the scaffolder's
#    add-observability), hard-abort. NO version bump on this path — the
#    user must resolve manually. This migration installs only a symlink;
#    a wrong-target symlink has nothing valid to fall back to, so the
#    only safe action is to refuse and surface the conflict.
if [ -L "$HOME/.claude/skills/add-observability" ]; then
  EXISTING=$(readlink "$HOME/.claude/skills/add-observability")
  case "$EXISTING" in
    */agenticapps-workflow/add-observability) ;;   # right target — Step 1 will idempotent-skip
    *)
      echo "ABORT: existing symlink at \$HOME/.claude/skills/add-observability points to:"
      echo "         $EXISTING"
      echo "       Expected target ends with /agenticapps-workflow/add-observability."
      echo "       Manual intervention required: remove or move it, then re-run:"
      echo "         rm \$HOME/.claude/skills/add-observability"
      echo "         /update-agenticapps-workflow"
      exit 3
      ;;
  esac
fi
```

Pre-flight uses one-level `readlink` only (no `-f` flag) — BSD readlink
(macOS default) does not support `-f`. Portable on both BSD and GNU.

## Steps

### Step 1 — Install global symlink for slash-discovery

**Idempotency check:**

```bash
test -L "$HOME/.claude/skills/add-observability" \
  && readlink "$HOME/.claude/skills/add-observability" \
       | grep -q '/agenticapps-workflow/add-observability$'
```

**Pre-condition:** pre-flight passed.

**Apply:**

```bash
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
        "$HOME/.claude/skills/add-observability"
```

**Rollback:**

```bash
# Only remove the symlink if it points at the scaffolder (don't clobber
# a symlink the user redirected to a fork of the skill).
if [ -L "$HOME/.claude/skills/add-observability" ] && \
   readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$'; then
  rm "$HOME/.claude/skills/add-observability"
fi
```

### Step 2 — Verify slash-discoverability

**Idempotency check:**

```bash
# Same shape as the Step 1 idempotency + SKILL.md resolves through the symlink.
test -f "$HOME/.claude/skills/add-observability/SKILL.md" \
  && grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md"
```

**Pre-condition:** Step 1 applied.

**Apply:** the consuming agent (Claude Code session running
`/update-agenticapps-workflow`) confirms the symlink resolves and the
target's SKILL.md identifies as `add-observability`. This is a verify-
only step — no state change.

```bash
test -f "$HOME/.claude/skills/add-observability/SKILL.md" || {
  echo "POST-STEP-1 CHECK FAIL: SKILL.md not reachable through the symlink."
  echo "                       Symlink target may be missing or broken."
  exit 3
}
grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md" || {
  echo "POST-STEP-1 CHECK FAIL: SKILL.md target does not identify as add-observability."
  exit 3
}
```

**Rollback:** none — verify-only.

### Step 3 — Bump workflow scaffolder version

**Idempotency check:**

```bash
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.bak 's/^version: 1\.10\.0$/version: 1.11.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

**Rollback:**

```bash
sed -i.bak 's/^version: 1\.11\.0$/version: 1.10.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Post-checks

```bash
# 1. Symlink present at HOME-global scope, pointing at the scaffolder
test -L "$HOME/.claude/skills/add-observability"
readlink "$HOME/.claude/skills/add-observability" | grep -q '/agenticapps-workflow/add-observability$'

# 2. SKILL.md reachable + correctly identified through the symlink
test -f "$HOME/.claude/skills/add-observability/SKILL.md"
grep -q '^name: add-observability' "$HOME/.claude/skills/add-observability/SKILL.md"

# 3. Workflow scaffolder version bumped
grep -q '^version: 1.11.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

All 3 post-checks return 0 on a successful apply. Re-applying the
migration finds them all green and reports "skipped (already applied)".

## Skip cases

- **`from_version` mismatch** (project is not at 1.10.0) → migration
  framework skips silently per the standard rule.
- **Scaffolder not at `$HOME/.claude/skills/agenticapps-workflow/`** →
  pre-flight ABORTS (exit 3) with the install command. NOT a silent
  skip — the user must take action.
- **Existing real directory or wrong-target symlink at
  `$HOME/.claude/skills/add-observability`** → pre-flight ABORTS with
  manual-remediation message. NO version bump on this path.

## Compatibility

- **Slash-discovery contract**: post-migration,
  `~/.claude/skills/add-observability/SKILL.md` is the canonical entry
  for Claude Code's skill loader. Updates via `git pull` in the
  scaffolder repo propagate through the symlink automatically — no
  re-running of this migration needed.
- **Backward compatibility with v1.10.0 projects**: projects that do
  NOT run this migration keep working at v1.10.0 — the per-project
  install at `.claude/skills/add-observability/` (from migration 0002)
  continues to function for explicit-path invocation, just not as a
  slash command at HOME-global scope.
- **Relationship to migration 0002**: scaffolder v1.11.0 added Step 4
  to 0002 (the same symlink registration). Fresh installs running the
  full migration chain get the symlink at the 0002 step; existing
  v1.10.0 projects get it via this migration.

## References

- Issue #22: `/add-observability` slash-discovery gap
- Phase plan: `.planning/phases/15-init-and-slash-discovery/PLAN.md`
- Multi-AI review: `.planning/phases/15-init-and-slash-discovery/15-REVIEWS.md`
- ADR-0013 (migration framework): `claude-workflow/docs/decisions/0013-migration-framework.md`
- Prior migration: `0011-observability-enforcement.md` (1.9.3 → 1.10.0)
- Scaffolder install.sh: `install.sh` — LINKS array carries the same
  symlink for fresh installs (added in v1.11.0).
