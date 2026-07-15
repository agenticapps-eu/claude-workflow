---
id: 0029
slug: region-aware-spec-11-placement
title: Anchor the spec §11 block above any GitNexus-managed region (v2.6.0 -> 2.7.0)
from_version: 2.6.0
to_version: 2.7.0
applies_to:
  - CLAUDE.md                                          # §11 block placement healed (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.6.0 -> 2.7.0 (Step 2)
requires:
  - file: templates/spec-mirrors/11-coding-discipline-0.4.0.md
    install: "vendored in the scaffolder repo at claude-workflow/templates/spec-mirrors/; symlinked into $HOME via the same install pattern as migration 0014"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
---

# Migration 0029 — Region-aware §11 placement (v2.6.0 -> 2.7.0)

Migration 0014 injects the canonical §11 block immediately before the first
`## ` heading in `CLAUDE.md`. That is only a safe boundary when the heading
belongs to *project* content. In a `CLAUDE.md` that leads with the GitNexus
block, the first `## ` is `## Always Do` — inside
`<!-- gitnexus:start -->…<!-- gitnexus:end -->`. The block lands in the region,
and the next `gitnexus analyze` regenerates the region and destroys it with no
diagnostic.

Nothing recovers from that. `/update` marks a migration pending iff
`installed >= from_version && installed < to_version`; 0014's `to_version` is
`1.14.0`, so for any 2.x project it is permanently not-pending. Its pre-flight
also refuses the `--migration 0014` force path (it demands `1.12.0`/`1.14.0`).
0014 is immutable and already applied in five repos, so this migration fixes
forward rather than editing it.

**The anchor rule.** Insert immediately before the first line that is **either**
a `## ` heading **or** a line that is *exactly* `<!-- gitnexus:start -->` —
whichever comes first; EOF if neither. Both marker regexes MUST be anchored
(`/^<!-- gitnexus:start -->$/`, `/^<!-- gitnexus:end -->$/`) — an unanchored
substring match also fires on prose that merely *mentions* the marker, which is
exactly what this file's own guidance comment does two lines above this
paragraph's rendered position in a scaffolded project.

This is a one-alternation delta to 0014's awk, but it does **not** preserve
0014's structural invariant — it **replaces** it. 0014 could assume the block
is always followed by a `## ` line or EOF, because its anchor could only ever
be a `## ` heading. Once the anchor can also be a `<!-- gitnexus:start -->`
marker, a healed region-led file has the block followed by that marker, not a
`## ` line. The invariant that actually holds after this migration is: the
block is always followed by a `## ` line, an anchored `<!-- gitnexus:start -->`
marker, or EOF. Every terminator that bounds the managed section — the strip
pass in Step 1 Apply and the Rollback awk below — carries the same alternation
as the anchor, because the anchor rule and the terminator rule are one
decision, not two, and must move together.

The rule anchors on the region **only when the region comes first**. Anchoring
before `gitnexus:start` whenever a region exists would be wrong: in a project
whose region starts late (cparx's begins at L306) the block would land hundreds
of lines down, violating §12's placement advisory. Validated against six real
repos — the rule re-derives the block's current position exactly in all five
healthy ones (zero churn) and anchors above the region on a gitnexus-led file.

**Fresh installs** get the same rule from the setup flow's step e2, which
carries a byte-identical anchor condition. `migrations/run-tests.sh`'s
`anchor-parity` guard fails the build if the two copies ever disagree
(spec §08: the setup flow's end state must equal a full replay).

## Pre-flight (hard aborts on failure)

```bash
SKILL_FILE=.claude/skills/agentic-apps-workflow/SKILL.md

# 1. Project is at 2.6.0 (or 2.7.0 for re-apply / partial state).
grep -qE '^version: 2\.(6\.0|7\.0)$' "$SKILL_FILE" || {
  INSTALLED=$(grep -E '^version:' "$SKILL_FILE" 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.6.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}

# 2. Vendored §11 block must be present in the global scaffolder bundle.
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
test -f "$SPEC_BLOCK" || {
  echo "ABORT: vendored §11 canonical block missing at:"
  echo "       $SPEC_BLOCK"
  echo "       Re-install: cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only"
  exit 3
}
```

Pre-flight is permissive on the missing-`CLAUDE.md` path: Step 1 emits an
informational message and Step 2 still runs (0014's idiom).

## Steps

### Step 1 — Heal the §11 block's placement

**Idempotency check:**

```bash
[ -f CLAUDE.md ] \
  && grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  && ! awk '
       /^<!-- gitnexus:start -->$/ { r = 1; next }
       /^<!-- gitnexus:end -->$/   { r = 0; next }
       r && /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ { f = 1 }
       END { exit(f ? 0 : 1) }
     ' CLAUDE.md
```

Both marker regexes are anchored (`^...$`) — a bare substring match also fires
on prose that merely *mentions* the marker (this file's own guidance comment
does exactly that), which would misjudge a healthy file as "inside a region."

Returns 0 (already applied — nothing to do) only when the current-version
provenance is present **and** the block is not inside a managed region. That
conjunction is the whole point: a block sitting inside a region carries correct
provenance but is not safe, so provenance alone must not short-circuit the heal.

Returns non-zero when `CLAUDE.md` is absent (routes to the informational-skip
branch), when the block is missing, and when the block is inside a region.

**Pre-condition:** pre-flight passed — the vendored block exists.

**Apply:**

```bash
PROV='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'
PROV_RE='<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->'
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

if [ ! -f CLAUDE.md ]; then
  echo "INFO: migration 0029 Step 1 — no CLAUDE.md in project; §11 heal skipped."
  echo "      Scaffold a CLAUDE.md (e.g. via /setup-agenticapps-workflow) and"
  echo "      re-run /update-agenticapps-workflow to pick up §11 on the next pass."
elif grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md \
     && ! grep -qE "$PROV_RE" CLAUDE.md; then
  echo "ABORT: CLAUDE.md contains a '## Coding Discipline (NON-NEGOTIABLE)'"
  echo "       heading but no provenance comment — it was hand-pasted outside"
  echo "       this migration's management. Refusing to overwrite."
  echo ""
  echo "       (a) Remove that section and re-run /update-agenticapps-workflow, or"
  echo "       (b) add the line"
  echo ""
  echo "             $PROV"
  echo ""
  echo "           immediately above the heading to adopt it as managed."
  exit 3
else
  # Two passes: strip the managed block wherever it currently sits, then
  # re-insert it at the region-aware anchor. Strip is a no-op when the block is
  # absent (state C), so both "inject" and "move" are the same code path.
  #
  # The strip is 0014's rollback logic, widened by one alternation: the
  # terminator recognizes the SAME anchor as the insert pass below (`## ` OR
  # an anchored `<!-- gitnexus:start -->`) — see "The anchor rule" above for
  # why these two must move together. The block contains exactly one `## `
  # line (its own heading), so we swallow that explicitly first; naively
  # stopping at the first `## ` would leave the block body behind (0014
  # fixture 07-byte-identity-replace catches that shape). `swallowed_own_h2`
  # is reset at the terminator so a SECOND provenance line re-enters cleanly
  # instead of inheriting a stale swallow state and leaking its own heading.
  #
  # The strip's output is required non-empty before anything downstream is
  # allowed to consume it. `CLAUDE.md` must never be replaced by a result
  # derived from a truncated or failed strip (awk error, disk full) — on
  # failure this aborts and leaves `CLAUDE.md` untouched, cleaning up any
  # partial temp file rather than leaking it into the project.
  if awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ {
      in_block = 1
      next
    }
    in_block && !swallowed_own_h2 && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
      swallowed_own_h2 = 1
      next
    }
    in_block && swallowed_own_h2 && (/^## / || /^<!-- gitnexus:start -->$/) {
      in_block = 0
      swallowed_own_h2 = 0
      print
      next
    }
    in_block { next }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0029.strip && [ -s CLAUDE.md.0029.strip ]; then
    # Re-insert at the region-aware anchor. The alternation IS the fix: 0014
    # had only /^## /, which selects a heading inside the region on a
    # gitnexus-led file. `whichever comes first` is what keeps the block near
    # the top when the region starts late. The gitnexus:start regex is
    # anchored (`^...$`) so a prose mention of the marker (this file's own
    # guidance comment does exactly that) can never be mistaken for it.
    if awk -v prov="$PROV" -v block_file="$SPEC_BLOCK" '
      BEGIN { inserted = 0 }
      !inserted && (/^## / || /^<!-- gitnexus:start -->$/) {
        print prov
        while ((getline line < block_file) > 0) print line
        close(block_file)
        print ""
        inserted = 1
        print
        next
      }
      { print }
      END {
        if (!inserted) {
          print ""
          print prov
          while ((getline line < block_file) > 0) print line
          close(block_file)
        }
      }
    ' CLAUDE.md.0029.strip > CLAUDE.md.0029.tmp && [ -s CLAUDE.md.0029.tmp ]; then
      mv CLAUDE.md.0029.tmp CLAUDE.md
      rm -f CLAUDE.md.0029.strip CLAUDE.md.0029.tmp
      echo "INFO: migration 0029 Step 1 — §11 block anchored above any managed region."
    else
      rm -f CLAUDE.md.0029.strip CLAUDE.md.0029.tmp
      echo "ABORT: migration 0029 Step 1 — the insert pass produced no output;"
      echo "       refusing to replace CLAUDE.md. Left untouched."
      exit 3
    fi
  else
    rm -f CLAUDE.md.0029.strip
    echo "ABORT: migration 0029 Step 1 — the strip pass produced no output;"
    echo "       refusing to replace CLAUDE.md with a possibly-truncated result."
    exit 3
  fi
fi
```

**Rollback:**

```bash
# Remove the managed block. Same shape as 0014's rollback, widened by the same
# alternation as Step 1's strip: the terminator must recognize a `## ` line OR
# an anchored `<!-- gitnexus:start -->` marker (or EOF) — a healed region-led
# file's block is followed by the marker, not a `## ` line, so a terminator
# that only recognized `## ` swallows past the marker and into the region's
# own content (see "The anchor rule" above). `swallowed_own_h2` resets at the
# terminator so a second provenance line re-enters cleanly. The strip's output
# is required non-empty before it is allowed to replace CLAUDE.md, and any
# temp file is cleaned up on every path — a failed/truncated rollback must not
# destroy the file, and must not leak a stray `.0029.tmp` into the project.
if [ -f CLAUDE.md ]; then
  if awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ {
      in_block = 1
      next
    }
    in_block && !swallowed_own_h2 && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
      swallowed_own_h2 = 1
      next
    }
    in_block && swallowed_own_h2 && (/^## / || /^<!-- gitnexus:start -->$/) {
      in_block = 0
      swallowed_own_h2 = 0
      print
      next
    }
    in_block { next }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0029.tmp && [ -s CLAUDE.md.0029.tmp ]; then
    mv CLAUDE.md.0029.tmp CLAUDE.md
    rm -f CLAUDE.md.0029.tmp
  else
    rm -f CLAUDE.md.0029.tmp
    echo "ABORT: migration 0029 Step 1 rollback — produced no output;"
    echo "       refusing to replace CLAUDE.md. Left untouched."
    exit 3
  fi
fi
```

Rollback removes the block rather than restoring its previous (unsafe)
position. Re-running 0014 is not possible on a 2.x project, so there is no
"put it back inside the region" state worth reconstructing.

### Step 2 — Bump the installed scaffolder version 2.6.0 -> 2.7.0

**Idempotency check:**

```bash
grep -q '^version: 2\.7\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -qE '^version: 2\.(6\.0|7\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.0029.bak 's/^version: 2\.6\.0$/version: 2.7.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0029.bak
```

**Rollback:**

```bash
sed -i.0029.bak 's/^version: 2\.7\.0$/version: 2.6.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0029.bak
```

## Downstream

`agenticapps-dashboard` is the one repo this repairs: snapshot-installed at
2.3.0 before the setup flow's §11 step existed (#84, 2.5.0), and 0014 was
already past, so it carries no §11 block while stamping `implements_spec:
0.9.0`. It sits at 2.5.0, so `/update` chains 0028 (2.5.0 -> 2.6.0) then 0029
(2.6.0 -> 2.7.0). The other five repos are state A and take a version stamp
only.

`codex-workflow` and `opencode-workflow` carry the same naive anchor in their
own §11 injectors and inherit this defect wherever their `AGENTS.md` is
region-led. Both are currently latent (§11 sits above the region in each).
Propagation follows the ADR-0037 pattern and is tracked separately.
