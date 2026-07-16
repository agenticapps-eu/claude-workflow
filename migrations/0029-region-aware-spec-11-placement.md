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
    verify: "test -s $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
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
exactly what a scaffolded project's own CLAUDE.md guidance comment does (not
this migration document itself) — e.g. this repo's own CLAUDE.md, which
mentions the `gitnexus:start` marker in a guidance comment at line 2, 94
lines above its actual, anchored occurrence at line 96.

The same discipline applies to the provenance marker that locates the
managed block itself. The strip pass (Apply) and Rollback both enter the
managed region on `/^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+
§11 -->$/`; that trigger is anchored for the identical reason — a guidance
comment can quote the provenance marker in prose above the real block (e.g.
"the block is anchored behind `<!-- spec-source: ... §11 -->` below"), and an
unanchored trigger would enter the managed region at that prose line instead
of the real one, deleting every line up to the next terminator.

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
repos — the rule re-derives the block's current *position* exactly in all
five healthy ones and anchors above the region on a gitnexus-led file. The
position claim holds, but a strip+re-insert round-trip is not byte-identical
on three of the five (cparx, fx-signal-agent, callbot): their on-disk blocks
have lost the blank line after each `Anti-patterns this rule prevents:`
heading to prettier normalization, which the canonical mirror re-adds. The
actual zero-churn guarantee for all five is the idempotency check
short-circuiting Apply entirely — each already reads "already applied," so
Apply never runs against them.

**Fresh installs** get the same rule from the setup flow's step e2, which
carries a byte-identical anchor condition. This migration carries five
copies of the rule (Step 1 Apply's strip pass, Step 1 Apply's insert pass,
Step 1 Apply's prose-preservation guard, Step 1 Rollback, and Step 1
Rollback's guard) and setup carries one; each guard's `extract_block` bounds
the region with the same terminator alternation, so it must agree with the
strip it gates. `migrations/run-tests.sh`'s `anchor-parity` guard fails the
build if setup's copy diverges from the migration's shared value, or if
either file's copy count drifts from 5/1 (spec §08: the setup flow's end
state must equal a full replay).

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

# 2. Vendored §11 block must be present AND non-empty in the global scaffolder
#    bundle. `test -f` alone passes on a zero-byte file — exactly what an
#    interrupted `git pull` in the scaffolder clone produces — and a zero-byte
#    block would strip the project's existing §11 block on Apply and insert
#    nothing in its place. `test -s` catches that before Apply ever runs.
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
test -s "$SPEC_BLOCK" || {
  echo "ABORT: vendored §11 canonical block missing or empty at:"
  echo "       $SPEC_BLOCK"
  echo "       Re-install: cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only"
  exit 3
}

# 3. Non-empty is not the same as un-truncated. The block's heading sits on
#    line 1, so a mirror truncated to just a few lines still satisfies
#    `test -s` above, and still satisfies Step 1's pre-`mv` shape assertion
#    (which only greps for that same line-1 heading) — both are single-point
#    guards on a continuum, not a guard against truncation. Assert the
#    block's LAST section is present too; a real truncation or a corrupt
#    mirror loses the tail long before it loses the head. This is not a
#    byte-identity or checksum check — vendored-file integrity is git's
#    job — it is the cheapest guard that closes the gap between "has a
#    heading" and "is the whole block."
grep -q '^### 4\. Goal-Driven Execution$' "$SPEC_BLOCK" || {
  echo "ABORT: vendored §11 canonical block at:"
  echo "       $SPEC_BLOCK"
  echo "       is missing its final section — it looks truncated or corrupt."
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
  && grep -q '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md \
  && ! awk '
       /^<!-- gitnexus:start -->$/ { r = 1; next }
       /^<!-- gitnexus:end -->$/   { r = 0; next }
       r && /^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$/ { f = 1 }
       END { exit(f ? 0 : 1) }
     ' CLAUDE.md
```

All three marker regexes are anchored (`^...$`) — a bare substring match also
fires on prose that merely *mentions* a marker, and that includes the
provenance comment itself: a scaffolded project's own CLAUDE.md guidance
comment can quote `<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`
in prose above the real block (not this migration document), and an
unanchored `PROV_RE` would enter `in_block`/`r` state at that prose line
instead of the real one. Anchoring requires the *entire* line to be exactly
the marker, which a prose sentence embedding it never is.

Returns 0 (already applied — nothing to do) only when the current-version
provenance is present **and** the block is not inside a managed region. That
conjunction is the whole point: a block sitting inside a region carries correct
provenance but is not safe, so provenance alone must not short-circuit the heal.

Returns non-zero when `CLAUDE.md` is absent (routes to the informational-skip
branch), when the block is missing, and when the block is inside a region.

**Pre-condition:** pre-flight passed — the vendored block exists, is
non-empty, and is not truncated (its final section is present).

**Apply:**

```bash
PROV='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'
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
  # Guard: refuse to strip a §11 region that is not the canonical block. §11
  # has no end marker, so the strip below (and the re-anchor after it) treats
  # everything from the provenance line to the next `## `/`<!-- gitnexus:start
  # -->` terminator as the block — region H..E: the heading through the last
  # non-blank line before the terminator. Anything a user placed after the
  # block's closing paragraph but before that terminator — operator prose, or a
  # lawful host-added anti-pattern bullet (spec §11 permits hosts to add them;
  # they layer on top of the canonical bullets) — falls inside H..E and would be
  # deleted, then the canonical mirror re-inserted without it. The `[ -s ]`
  # checks below cannot see that loss: the whole-file output stays non-empty.
  #
  # So when a block is present, re-extract H..E exactly as migration 0030's
  # re-sync does (buffering blank lines so they are only kept when a later
  # non-blank line proves them interior — this pins the region to E, the last
  # non-blank line, not T-1), strip blank lines from it and the mirror, and diff
  # the remainder. Identical → only the canonical block occupies the region,
  # safe to strip and re-anchor. Anything else → refuse, print the diff, and
  # leave CLAUDE.md untouched for the operator to reconcile by hand. Skipped
  # entirely when no provenance line is present: that is the greenfield inject
  # path (state C), which has no block to protect. This matches 0030's guard,
  # including its first-block scope — a second provenance block's region is not
  # independently validated here (0030 carries the identical limitation).
  if grep -qE "$PROV_RE" CLAUDE.md; then
    CURRENT_BLOCK="$(awk -v prov="$PROV_RE" '
      !seen && $0 ~ prov { seen=1; next }
      seen && !inb && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { inb=1; buf=$0; next }
      inb && (/^## / || /^<!-- gitnexus:start -->$/) { exit }
      inb {
        if ($0 == "") { pending = pending "\n"; next }
        buf = buf pending "\n" $0; pending = ""
      }
      END { if (inb) print buf }
    ' CLAUDE.md)"
    printf '%s\n' "$CURRENT_BLOCK" | sed '/^[[:space:]]*$/d' > CLAUDE.md.0029.guard-current.tmp
    sed '/^[[:space:]]*$/d' "$SPEC_BLOCK" > CLAUDE.md.0029.guard-canon.tmp
    if ! diff -u CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard-current.tmp \
         > CLAUDE.md.0029.guard.diff.tmp 2>&1; then
      echo "ABORT: migration 0029 Step 1 — the §11 block's non-blank content"
      echo "       differs from the canonical mirror. Refusing to strip and"
      echo "       re-anchor it, which would delete the divergent content."
      echo ""
      echo "       This may be operator prose written after the block, or a"
      echo "       LAWFUL host-specific addition (spec §11 permits hosts to add"
      echo "       anti-pattern bullets: they layer on top of the canonical"
      echo "       ones). §11 has no end marker, so the strip cannot tell such"
      echo "       content apart from the block itself. Reconcile manually: move"
      echo "       any local addition or prose out from under the §11 block"
      echo "       (above the next '## ' heading) and re-run. Diff of non-blank"
      echo "       content (- canonical mirror / + current CLAUDE.md block):"
      echo ""
      sed 's/^/       /' CLAUDE.md.0029.guard.diff.tmp
      rm -f CLAUDE.md.0029.guard-current.tmp CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard.diff.tmp
      exit 3
    fi
    rm -f CLAUDE.md.0029.guard-current.tmp CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard.diff.tmp
  fi

  # Two passes: strip the managed block wherever it currently sits, then
  # re-insert it at the region-aware anchor. Strip is a no-op when the block is
  # absent (state C), so both "inject" and "move" are the same code path.
  #
  # The strip is 0014's rollback logic, widened by one alternation: the
  # terminator recognizes the SAME anchor as the insert pass below (`## ` OR
  # an anchored `<!-- gitnexus:start -->`) — see "The anchor rule" above for
  # why these two must move together. The `in_block` trigger itself is also
  # anchored (`^...$`): a prose line that merely MENTIONS the provenance
  # marker (e.g. a guard comment reading "the block is anchored behind
  # <!-- spec-source: ... §11 --> below") would otherwise substring-match
  # and enter `in_block` at that prose line instead of the real one,
  # deleting everything up to the next terminator. The block contains
  # exactly one `## ` line (its own heading), so we swallow that explicitly
  # first; naively stopping at the first `## ` would leave the block body
  # behind (0014 fixture 07-byte-identity-replace catches that shape).
  # `swallowed_own_h2` is reset at the terminator so a SECOND provenance
  # line re-enters cleanly instead of inheriting a stale swallow state and
  # leaking its own heading.
  #
  # The strip's output is required non-empty before anything downstream is
  # allowed to consume it. `CLAUDE.md` must never be replaced by a result
  # derived from a truncated or failed strip (awk error, disk full) — on
  # failure this aborts and leaves `CLAUDE.md` untouched, cleaning up any
  # partial temp file rather than leaking it into the project.
  if awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$/ {
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
    # anchored (`^...$`) so a prose mention of the marker (a scaffolded
    # project's own CLAUDE.md guidance comment does exactly that — not this
    # migration document) can never be mistaken for it.
    #
    # Non-empty is not the same as correct: a zero-byte $SPEC_BLOCK (e.g. an
    # interrupted `git pull` in the scaffolder clone — pre-flight's `test -s`
    # guards the common case, but this is the last line of defense) makes the
    # `while ((getline ...))` loop below read nothing, yet awk still exits 0
    # with non-empty output (the rest of the file, plus an orphaned provenance
    # line). `[ -s ]` alone would pass and commit that data loss. Requiring
    # the result to actually contain the block's own heading catches it.
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
    ' CLAUDE.md.0029.strip > CLAUDE.md.0029.tmp && [ -s CLAUDE.md.0029.tmp ] \
      && grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md.0029.tmp; then
      if mv CLAUDE.md.0029.tmp CLAUDE.md; then
        rm -f CLAUDE.md.0029.strip CLAUDE.md.0029.tmp
        echo "INFO: migration 0029 Step 1 — §11 block anchored above any managed region."
      else
        rm -f CLAUDE.md.0029.strip CLAUDE.md.0029.tmp
        echo "ABORT: migration 0029 Step 1 — mv failed; refusing to report"
        echo "       success. CLAUDE.md left as-is (mv is atomic on failure);"
        echo "       check disk space / permissions."
        exit 3
      fi
    else
      rm -f CLAUDE.md.0029.strip CLAUDE.md.0029.tmp
      echo "ABORT: migration 0029 Step 1 — the insert pass produced no output,"
      echo "       or its result is missing the §11 heading. The vendored"
      echo "       spec-mirror block is likely empty or corrupt:"
      echo "       $SPEC_BLOCK"
      echo "       Refusing to replace CLAUDE.md. Left untouched."
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
# terminator so a second provenance line re-enters cleanly. Rollback has no
# strip pass of its own — this removal pass is the entirety of Rollback — and
# its output is required non-empty before it is allowed to replace CLAUDE.md.
# Any temp file is cleaned up on every path, including a failed `mv`: a
# failed/truncated rollback must not destroy the file, and must not leak a
# stray `.0029.tmp` into the project.
if [ -f CLAUDE.md ]; then
  # Same guard as Step 1 Apply, and for the same reason: Rollback's removal pass
  # (below) strips the entire region H..E between the provenance line and its
  # terminator, so operator prose or a lawful host-added §11 bullet placed under
  # the block would be deleted along with it. Before removing, when a block is
  # present, re-extract H..E, strip blank lines from it and the mirror, and diff
  # the remainder. Identical → only the canonical block is in the region, safe
  # to remove. Anything else → refuse and leave CLAUDE.md untouched. Skipped
  # when no provenance line is present (nothing to remove). Matches 0030's guard
  # and its first-block scope.
  if grep -qE '^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$' CLAUDE.md; then
    ROLLBACK_SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
    CURRENT_BLOCK="$(awk -v prov='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$' '
      !seen && $0 ~ prov { seen=1; next }
      seen && !inb && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { inb=1; buf=$0; next }
      inb && (/^## / || /^<!-- gitnexus:start -->$/) { exit }
      inb {
        if ($0 == "") { pending = pending "\n"; next }
        buf = buf pending "\n" $0; pending = ""
      }
      END { if (inb) print buf }
    ' CLAUDE.md)"
    printf '%s\n' "$CURRENT_BLOCK" | sed '/^[[:space:]]*$/d' > CLAUDE.md.0029.guard-current.tmp
    sed '/^[[:space:]]*$/d' "$ROLLBACK_SPEC_BLOCK" > CLAUDE.md.0029.guard-canon.tmp
    if ! diff -u CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard-current.tmp \
         > CLAUDE.md.0029.guard.diff.tmp 2>&1; then
      echo "ABORT: migration 0029 Step 1 rollback — the §11 block's non-blank"
      echo "       content differs from the canonical mirror. Refusing to remove"
      echo "       it, which would delete the divergent content (operator prose,"
      echo "       or a lawful host-added §11 anti-pattern bullet). Reconcile"
      echo "       manually: move any local addition or prose out from under the"
      echo "       §11 block (above the next '## ' heading) and re-run. Diff of"
      echo "       non-blank content (- canonical mirror / + current block):"
      echo ""
      sed 's/^/       /' CLAUDE.md.0029.guard.diff.tmp
      rm -f CLAUDE.md.0029.guard-current.tmp CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard.diff.tmp
      exit 3
    fi
    rm -f CLAUDE.md.0029.guard-current.tmp CLAUDE.md.0029.guard-canon.tmp CLAUDE.md.0029.guard.diff.tmp
  fi
  if awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$/ {
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
    if mv CLAUDE.md.0029.tmp CLAUDE.md; then
      rm -f CLAUDE.md.0029.tmp
    else
      rm -f CLAUDE.md.0029.tmp
      echo "ABORT: migration 0029 Step 1 rollback — mv failed; refusing to"
      echo "       report success. CLAUDE.md left as-is (mv is atomic on"
      echo "       failure); check disk space / permissions."
      exit 3
    fi
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

`cparx`, `callbot`, and `fx-signal-agent` carry §11 blocks that are no longer
byte-identical to the canonical mirror (prettier has stripped the blank line
after each `Anti-patterns this rule prevents:` heading) while stamping
`implements_spec: 0.9.0`. This migration does not heal that drift — the
idempotency check's provenance-presence test short-circuits before any
byte-comparison runs — and it is out of scope here. Tracked as a follow-up.

**Known limitations (no live instance, not fixed by design):** the marker
regexes are line-oriented (`^...$` on `$0`), so (1) a CRLF `CLAUDE.md` fails
every anchor — `/^<!-- gitnexus:start -->$/` does not match a line ending in
`\r`, and the unanchored `## Always Do` fallback then matches instead,
reproducing the original region-led defect; and (2) a `<!-- gitnexus:start -->`
or provenance marker written literally inside a fenced code block is treated
as a real marker, since awk has no fence awareness. Neither shape exists in
the fleet today; 0014 shares both flaws. Not worth widening the diff for a
shape with no live instance.
