---
id: 0028
slug: register-prettierignore
title: Register .claude/hooks in the project's .prettierignore (v2.5.0 -> 2.6.0)
from_version: 2.5.0
to_version: 2.6.0
applies_to:
  - .prettierignore                                    # append .claude/hooks/ (only if the file already exists)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.5.0 -> 2.6.0
---

# Migration 0028 — Register .claude/hooks in .prettierignore (v2.5.0 -> 2.6.0)

The GitNexus background-reindex hook shipped by migration 0026
(`.claude/hooks/gitnexus-reindex.cjs`) is a CommonJS Node hook. Repos whose
formatter runs over `.claude/` — e.g. a `prettier --check .` in a `format:check`
CI step — fail on the hook's formatting.

The sibling ESLint failure (`@typescript-eslint/no-require-imports`) is already
handled at the source: the shipped hook carries a file-level `eslint-disable`
header, which is honored by any ESLint config. Prettier has **no equivalent
whole-file ignore comment** (`// prettier-ignore` only affects the next node),
so the only portable fix is a `.prettierignore` entry. This migration adds it.

**Append-if-exists, never create.** The step touches `.prettierignore` only when
the project already has one. A project without a `.prettierignore` either does
not use Prettier or accepts its defaults; creating the file would imply tooling
the project never configured (the same conservative stance §15 takes with an
absent vault). A project that format-checks `.claude/` and has no
`.prettierignore` is rare; it can add the one line by hand.

Fresh installs get this from the setup flow, which performs the same
append-if-exists step against the target project's `.prettierignore` (see
`setup/SKILL.md`). The `.prettierignore` is a *project* file, not part of the
snapshot payload, so both the setup and update flows converge on the same
conditional edit rather than on a shipped artifact.

## Pre-flight

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md
grep -qE '^version: 2\.(5\.0|6\.0)$' "$SKILL_FILE" || {
  INSTALLED=$(grep -E '^version:' "$SKILL_FILE" 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.5.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}
```

## Steps

### Step 1 — Register `.claude/hooks/` in an existing `.prettierignore`

**Idempotency check:**

```bash
[ ! -f .prettierignore ] || grep -qE '^\.claude/hooks/?$' .prettierignore
```

Returns 0 (already applied — nothing to do) when there is no `.prettierignore`
(permanent skip) OR the `.claude/hooks/` entry is already present. Returns
non-zero only when a `.prettierignore` exists without the entry — the one case
that needs an apply.

**Pre-condition:**

```bash
[ ! -e .prettierignore ] || [ -f .prettierignore ]
```

`.prettierignore`, if it exists at all, is a regular file we can append to
(guards the pathological case of a directory or symlink at that path).

**Apply:**

```bash
if [ -f .prettierignore ] && ! grep -qE '^\.claude/hooks/?$' .prettierignore; then
  printf '\n# AgenticApps workflow (0028): vendored .claude hooks are .cjs/.sh Node\n# tooling, not app code; exclude from prettier --check.\n.claude/hooks/\n' >> .prettierignore
  echo "INFO: 0028 — appended .claude/hooks/ to .prettierignore"
else
  echo "INFO: 0028 — no .prettierignore (or entry already present); skipped"
fi
```

**Rollback:**

Delete the appended block — the two comment lines plus the `.claude/hooks/`
entry, anchored by the unique marker `# AgenticApps workflow (0028):`:

```bash
[ -f .prettierignore ] && sed -i.0028.bak '/^# AgenticApps workflow (0028):/,/^\.claude\/hooks\/$/d' .prettierignore && rm -f .prettierignore.0028.bak
```

### Step 2 — Bump the installed scaffolder version 2.5.0 -> 2.6.0

**Idempotency check:**

```bash
grep -q '^version: 2\.6\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -qE '^version: 2\.(5\.0|6\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.0028.bak 's/^version: 2\.5\.0$/version: 2.6.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0028.bak
```

**Rollback:**

```bash
sed -i.0028.bak 's/^version: 2\.6\.0$/version: 2.5.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0028.bak
```

## Downstream

`codex-workflow` and `opencode-workflow` ship the same reindex-hook family and
will hit the same Prettier interaction wherever a host format-checks their
vendored tooling. Each mirrors this append-if-exists step in its own idiom
(ADR-0037 propagation pattern).
