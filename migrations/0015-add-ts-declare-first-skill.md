---
id: 0015
slug: add-ts-declare-first-skill
title: Add ts-declare-first skill via user-global slash-discovery symlink (closes spec 0.4.0 §13 conformance)
from_version: 1.14.0
to_version: 1.14.0
applies_to:
  - $HOME/.claude/skills/ts-declare-first                  # user-global symlink → scaffolder's ts-declare-first/ (Step 1)
requires:
  - file: ts-declare-first/SKILL.md
    install: "vendored in the scaffolder repo at claude-workflow/ts-declare-first/; symlinked from the user's global install"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/ts-declare-first/SKILL.md"
optional_for: []
---

# Migration 0015 — Add ts-declare-first skill

Closes spec 0.4.0 §13 conformance for AgenticApps workflow projects
by installing the user-global symlink that makes the
`ts-declare-first` skill discoverable via slash-discovery (mirrors
migration 0012's pattern for `add-observability`).

`ts-declare-first` implements the declare-first TypeScript
discipline §13 codifies: a `declare`-only type-surface file as Phase
1, failing tests against the declared surface as Phase 2, and the
implementation matching the declared signatures exactly as Phase 3.
The three commits are atomic; the migration's skill REFUSES to
bundle them. See `ts-declare-first/SKILL.md` for the full procedure.

This migration is **always-apply**: it installs the skill globally
for any project running `/update-agenticapps-workflow` at 1.14.0,
regardless of whether the project is TS-primary. §13 mandates that
hosts SHIP the skill; per-project triggering (which §13 also
mandates for TS-primary projects) is a separate mechanism the
host's GSD scaffolder will wire up later. Until then, the skill is
explicit-invocation only — operators trigger it manually for new TS
modules.

The version bump baked into 0014 (1.12.0 → 1.14.0,
`implements_spec` 0.3.x → 0.4.0) is the SKILL.md-level claim for
spec 0.4.0 absorption; 0015 rides on it (no further version change).

## Pre-flight (hard aborts on failure)

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md

# 1. Workflow SKILL.md is at full post-0014 state (version 1.14.0 AND
#    implements_spec 0.4.0). 0014 is the sole bumper of both lines;
#    0015 rides on 0014's full state, so we assert both here rather
#    than just version (otherwise a partial-0014 state where version
#    bumped but implements_spec did not could slip through).
grep -qE '^version: 1\.14\.0$' "$SKILL_FILE" \
  && grep -qE '^implements_spec: 0\.4\.0$' "$SKILL_FILE" || {
  INSTALLED=$(grep -E '^version:' "$SKILL_FILE" 2>/dev/null | sed 's/version: //')
  SPEC=$(grep -E '^implements_spec:' "$SKILL_FILE" 2>/dev/null | sed 's/implements_spec: //')
  echo "ABORT: workflow scaffolder state is version=${INSTALLED:-<missing>} implements_spec=${SPEC:-<missing>} (need 1.14.0 / 0.4.0)."
  echo "       Apply migration 0014 first via /update-agenticapps-workflow."
  exit 3
}

# 2. Scaffolder bundle's ts-declare-first source must exist. Step 1's
#    apply makes the user-global symlink point at this path.
SCAFFOLDER_SOURCE="$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
test -f "$SCAFFOLDER_SOURCE/SKILL.md" || {
  echo "ABORT: scaffolder ts-declare-first skill missing at:"
  echo "       $SCAFFOLDER_SOURCE/SKILL.md"
  echo "       The scaffolder bundle is older than 1.14.0 or has been"
  echo "       tampered with. Re-install:"
  echo "         cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only"
  exit 3
}

# 3. Conflict detect: if a NON-SYMLINK (regular file, regular dir)
#    exists at $HOME/.claude/skills/ts-declare-first, refuse. Step 1's
#    apply would otherwise clobber user data via `ln -sfn`.
USER_GLOBAL_LINK="$HOME/.claude/skills/ts-declare-first"
if [ -e "$USER_GLOBAL_LINK" ] && [ ! -L "$USER_GLOBAL_LINK" ]; then
  echo "ABORT: $USER_GLOBAL_LINK exists and is NOT a symlink."
  echo "       This likely means the skill was hand-vendored or"
  echo "       installed by another tool. Refusing to clobber."
  echo ""
  echo "       Resolve manually, then re-run /update-agenticapps-workflow:"
  echo ""
  echo "       (a) If the hand-vendored copy is canonical for you:"
  echo "           leave it. This migration is structurally redundant"
  echo "           for you — the skill is discoverable via the existing"
  echo "           directory. Skip this migration in your config."
  echo "       (b) If you want the scaffolder's canonical version:"
  echo "           rm -rf $USER_GLOBAL_LINK"
  echo "           Then re-run /update-agenticapps-workflow."
  exit 3
fi
```

Pre-flight is permissive on a redirected symlink: if the path is a
SYMLINK (pointing anywhere), Step 1's apply will force-replace via
`ln -sfn`. This mirrors migration 0012's behavior for
`add-observability` — operator-redirected symlinks ARE clobbered on
apply. Rollback preserves operator redirections (see Rollback
below).

## Steps

### Step 1 — Install user-global slash-discovery symlink

**Idempotency check:**

```bash
test -L "$HOME/.claude/skills/ts-declare-first" \
  && readlink "$HOME/.claude/skills/ts-declare-first" \
       | grep -Fxq "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
```

(Returns 0 only when the symlink exists AND points exactly at the
scaffolder source. Returns non-zero if the symlink is absent or
redirected elsewhere — both signal "needs apply".)

**Pre-condition:** pre-flight passed; the non-symlink conflict case
was already refused.

**Apply:**

```bash
ln -sfn "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first" \
        "$HOME/.claude/skills/ts-declare-first"
echo "INFO: migration 0015 Step 1 — installed user-global symlink:"
echo "      $HOME/.claude/skills/ts-declare-first"
echo "      → $HOME/.claude/skills/agenticapps-workflow/ts-declare-first"
echo "      Skill is now discoverable via slash-discovery."
```

The `-f` flag force-overwrites an existing symlink (clobbers
operator redirections, same as 0012). The `-n` flag treats existing
symlinks as files for the purposes of `-f` (avoids the
"target-is-a-symlink-to-a-directory" macOS pitfall where `ln -sf`
creates the new link INSIDE the directory the existing link points
at).

**Rollback:**

```bash
# Only remove the symlink if it points at the scaffolder. Operator-
# redirected symlinks (e.g. to a personal fork) are preserved on
# rollback — same precedent as 0012.
if [ -L "$HOME/.claude/skills/ts-declare-first" ] && \
   readlink "$HOME/.claude/skills/ts-declare-first" \
     | grep -Fxq "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first"; then
  rm "$HOME/.claude/skills/ts-declare-first"
fi
```

## Notes

- **Why one step, not two.** PLAN.md P2 originally specified two
  steps: user-global (always) + project-local (conditional on
  TS-primary). The two-step design was dropped because (a) it
  conflicts with migration 0013's anti-project-local-skill stance
  (project-local copies caused the cparx F1 issue 0013 was written
  to clean up); (b) §13's "ship the skill" obligation doesn't
  require per-project install gating; (c) per-project triggering
  (which §13 DOES mandate for TS-primary projects) is a separate
  mechanism that lives in the GSD scaffolder, not in this migration.
  See the test commit's message for the full rationale.

- **Implicit-trigger wiring is future work.** §13 says the host's
  GSD design phase MUST trigger this skill implicitly when (a) the
  phase plan introduces a new TS module AND (b) the project's
  package.json declares TypeScript as primary. That detection logic
  is NOT in this PR. The skill is explicit-invocation only until
  it's wired up.

- **`-fn` clobbers user redirections.** If an operator redirected
  `$HOME/.claude/skills/ts-declare-first` to a fork of the skill,
  this migration's apply REPLACES the redirection with a link to
  the scaffolder's canonical skill. Same behavior as 0012. The
  rollback path is non-clobbering — it leaves redirections in
  place — but the forward apply path is destructive. Operators
  who maintain forks should pin a different path entirely (e.g.
  `$HOME/.claude/skills/ts-declare-first-fork/`) and reference it
  from their workflow config rather than redirecting the canonical
  path.

- **No version bump.** 0014 already bumped the workflow scaffolder
  to 1.14.0 / `implements_spec: 0.4.0` as the SKILL.md-level claim
  for the 0.4.0 absorption. 0015 inherits the bump and makes no
  further SKILL.md changes.
