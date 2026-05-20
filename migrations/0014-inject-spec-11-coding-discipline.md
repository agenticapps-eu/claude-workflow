---
id: 0014
slug: inject-spec-11-coding-discipline
title: Inject spec §11 "Coding Discipline" canonical block (closes spec 0.4.0 §11 conformance)
from_version: 1.12.0
to_version: 1.14.0
applies_to:
  - CLAUDE.md                                              # §11 anchor + provenance + verbatim block injected/replaced (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md          # version 1.12.0 → 1.14.0; implements_spec 0.3.x → 0.4.0 (Step 2)
requires:
  - file: templates/spec-mirrors/11-coding-discipline-0.4.0.md
    install: "vendored in the scaffolder repo at claude-workflow/templates/spec-mirrors/; symlinked into $HOME via the same install pattern as add-observability/"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
optional_for: []
---

# Migration 0014 — Inject spec §11 canonical block

Closes spec 0.4.0 §11 conformance for AgenticApps workflow projects by
injecting the canonical "Coding Discipline (NON-NEGOTIABLE)" block
verbatim into the project's CLAUDE.md, behind a provenance-managed
anchor that supports drift detection and clean re-injection across
spec revisions.

The block content is the four-rule Karpathy-distilled discipline
("Think Before Coding / Simplicity First / Surgical Changes /
Goal-Driven Execution"). §11 mandates verbatim reproduction in the
host's primary project-instruction file; the block is intentionally
short ("reread every session because the failure modes they prevent
recur every session") and lives near the top of CLAUDE.md per §12's
placement advisory ("not appended below long appendices").

This migration also bumps the workflow scaffolder version
(1.12.0 → 1.14.0) and the spec-version stamp
(`implements_spec: 0.3.x → 0.4.0`). The version bump is bundled here
because 0.4.0 absorption is the only structural change in 1.14.0
that requires a SKILL.md-level claim — migration 0015 (the
`ts-declare-first` skill scaffold) lands at the same target version
and rides on this bump.

## Pre-flight (hard aborts on failure)

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md

# 1. Workflow SKILL.md is at 1.12.0 (or 1.14.0 for re-apply / partial state).
grep -qE '^version: 1\.(12\.0|14\.0)$' "$SKILL_FILE" || {
  INSTALLED=$(grep -E '^version:' "$SKILL_FILE" 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 1.12.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}

# 2. Vendored §11 block must be present in the global scaffolder bundle.
#    The block is byte-identical to the spec's canonical block (§11 line 26-102
#    between the ```` fences). Step 1's apply reads from this file.
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
test -f "$SPEC_BLOCK" || {
  echo "ABORT: vendored §11 canonical block missing at:"
  echo "       $SPEC_BLOCK"
  echo "       The scaffolder bundle is older than 1.14.0 or has been"
  echo "       tampered with. Re-install:"
  echo "         cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only"
  exit 3
}

# 3. Conflict detect: a §11 heading present WITHOUT the provenance
#    comment indicates the operator hand-pasted the canonical block
#    (or some other content under the same heading) outside this
#    migration's anchor system. Refuse rather than silently overwrite.
if [ -f CLAUDE.md ] \
   && grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
   && ! grep -qE '<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->' CLAUDE.md; then
  echo "ABORT: CLAUDE.md contains a '## Coding Discipline (NON-NEGOTIABLE)'"
  echo "       heading but no provenance comment. This means the block"
  echo "       was hand-pasted (or otherwise introduced) outside migration"
  echo "       0014's management."
  echo ""
  echo "       Resolve manually, then re-run /update-agenticapps-workflow:"
  echo ""
  echo "       (a) Remove the existing '## Coding Discipline (NON-NEGOTIABLE)'"
  echo "           section from CLAUDE.md. Migration 0014 will then inject"
  echo "           under provenance management on the next /update run."
  echo "       (b) Or accept the manually-pasted block as canonical: add"
  echo "           the line"
  echo ""
  echo "             <!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->"
  echo ""
  echo "           immediately above the heading. The migration will"
  echo "           recognise the block as managed (Step 1 will no-op)."
  exit 3
fi
```

Pre-flight is permissive on the missing-CLAUDE.md path: if `CLAUDE.md`
does not exist the migration does NOT abort — instead Step 1's apply
emits an informational message and Step 2 still runs (the same idiom
0013 Step 2 uses for the chained-init path).

## Steps

### Step 1 — Inject (or replace) the §11 canonical block

**Idempotency check:**

```bash
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md
```

(Returns 0 if the current-version provenance comment is present in
CLAUDE.md — the block is already injected at the current spec version,
no work to do. Note: this idempotency check intentionally short-
circuits when `CLAUDE.md` does not exist, because `grep` returns
non-zero on missing file — that's the "needs apply" signal which
routes into the informational-no-op branch of the apply below.)

**Pre-condition:** pre-flight passed — vendored block exists; conflict
case (heading without provenance) was already refused.

**Apply:**

```bash
PROVENANCE='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

if [ ! -f CLAUDE.md ]; then
  echo "INFO: migration 0014 Step 1 — no CLAUDE.md in project; §11 injection skipped."
  echo "      Scaffold a CLAUDE.md (e.g. via /setup-agenticapps-workflow) and"
  echo "      re-run /update-agenticapps-workflow to pick up §11 on the next pass."
elif grep -qE '<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->' CLAUDE.md; then
  # Provenance present at some version. If it were the current version,
  # the idempotency check above would have returned 0 and we wouldn't be
  # here. So the provenance is STALE — replace the managed section.
  #
  # Replacement range: from the provenance line, through the existing
  # block, up to (but not including) the next ## heading. The §11 block
  # has only ### sub-headings internally, so the next `## ` line is the
  # natural terminator.
  awk -v prov="$PROVENANCE" -v block_file="$SPEC_BLOCK" '
    BEGIN { in_block = 0; replaced = 0 }
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ && !replaced {
      print prov
      while ((getline line < block_file) > 0) print line
      close(block_file)
      in_block = 1
      replaced = 1
      next
    }
    in_block && /^## / { in_block = 0; print; next }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0014.tmp && mv CLAUDE.md.0014.tmp CLAUDE.md
  echo "INFO: migration 0014 Step 1 — replaced stale §11 block with @0.4.0 canonical."
else
  # No provenance present. Pre-flight #3 already refused the
  # heading-without-provenance conflict case, so we're safe to insert.
  # Insertion point: after the first H1 line + the first blank line that
  # follows it (places §11 near the top per §12 placement advisory).
  # Fallback: append at EOF if the file has no H1+blank shape.
  awk -v prov="$PROVENANCE" -v block_file="$SPEC_BLOCK" '
    BEGIN { inserted = 0; saw_h1 = 0 }
    !inserted && saw_h1 && /^$/ {
      print
      print prov
      while ((getline line < block_file) > 0) print line
      close(block_file)
      print ""
      inserted = 1
      next
    }
    /^# / { saw_h1 = 1 }
    { print }
    END {
      if (!inserted) {
        print ""
        print prov
        while ((getline line < block_file) > 0) print line
        close(block_file)
      }
    }
  ' CLAUDE.md > CLAUDE.md.0014.tmp && mv CLAUDE.md.0014.tmp CLAUDE.md
  echo "INFO: migration 0014 Step 1 — injected §11 block at @0.4.0 (after H1 + blank)."
fi
```

**Rollback:**

```bash
# Remove the provenance line through the end of the managed block (the
# next ## heading is the natural terminator, same as the replace path).
if [ -f CLAUDE.md ]; then
  awk '
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ { in_block = 1; next }
    in_block && /^## / { in_block = 0 }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0014.tmp && mv CLAUDE.md.0014.tmp CLAUDE.md
fi
```

### Step 2 — Bump workflow SKILL.md version + implements_spec

**Idempotency check:**

```bash
grep -qE '^version: 1\.14\.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  && grep -qE '^implements_spec: 0\.4\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

(Returns 0 only when BOTH fields are already at the post-apply state.
A partial state — version bumped but implements_spec not, or vice
versa — leaves the check non-zero and the apply re-runs the bumps
idempotently for whichever field needs it. The sed expressions below
are no-ops on already-bumped fields because the source regex no longer
matches.)

**Pre-condition:** pre-flight passed; Step 1 ran (or skipped on the
no-CLAUDE.md path).

**Apply:**

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md

# Portable in-place edit: `-i.0014.bak` works on both macOS BSD sed
# and GNU sed; the .bak file is removed immediately. (Bare `-i` is
# not portable.)
sed -i.0014.bak -E 's/^version: 1\.12\.0$/version: 1.14.0/' "$SKILL_FILE"
if grep -q '^implements_spec:' "$SKILL_FILE"; then
  sed -i.0014.bak -E 's/^implements_spec: 0\.3\.[0-9]+$/implements_spec: 0.4.0/' "$SKILL_FILE"
fi
rm -f "$SKILL_FILE.0014.bak"
echo "INFO: migration 0014 Step 2 — workflow scaffolder bumped to 1.14.0 / implements_spec 0.4.0."
```

**Rollback:**

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md
sed -i.0014.bak -E 's/^version: 1\.14\.0$/version: 1.12.0/' "$SKILL_FILE"
sed -i.0014.bak -E 's/^implements_spec: 0\.4\.0$/implements_spec: 0.3.2/' "$SKILL_FILE"
rm -f "$SKILL_FILE.0014.bak"
```

(Rollback restores the pre-apply 0.3.2 state. If the original was
0.3.0 or 0.3.1, the operator must hand-edit; in practice 1.13.x→1.14.0
projects come from 1.12.0/0.3.2 — the from_version constraint above
gates this.)

## Notes

- **Why the block is inlined, not vendored as a sibling file.** §11
  is intentionally short and designed to be reread every session.
  Migration 0009's pattern (vendor `workflow.md` into
  `.claude/claude-md/` and reference from CLAUDE.md) exists for *long*
  on-demand content; §11 has the opposite design intent. §12's
  placement advisory explicitly calls out CLAUDE.md as the §11
  block's home.

- **Provenance comment placement.** The provenance is written on the
  line immediately above `## Coding Discipline (NON-NEGOTIABLE)`,
  not inside the canonical block. Putting it inside the block would
  alter §11's verbatim prose, which the spec's conformance section
  prohibits ("alteration of any surrounding prose, including the
  rule numbers and the anti-pattern bullets, is non-conformant").

- **Replacement boundary.** The managed section ends at the next
  `## ` (level-2) heading. The canonical block has only `### ` (level
  3) sub-headings internally, so any project content following the
  block — typically the `## Workflow` block migration 0009 injects,
  or other host-specific level-2 sections — naturally terminates the
  replacement range.

- **Drift detection across future spec revisions.** When
  workflow-core ships spec 0.5.0+, a future migration vendors the
  new block under
  `templates/spec-mirrors/11-coding-discipline-0.5.0.md` and the new
  migration's apply branch swaps the provenance line + block bytes.
  The existing replace path handles this idempotently because the
  stale-provenance regex matches any non-empty version stamp.
