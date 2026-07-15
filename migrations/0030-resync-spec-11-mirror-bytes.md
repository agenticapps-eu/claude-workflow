---
id: 0030
slug: resync-spec-11-mirror-bytes
title: Re-sync stale spec §11 block bytes to the canonical mirror (v2.7.0 -> 2.8.0)
from_version: 2.7.0
to_version: 2.8.0
applies_to:
  - CLAUDE.md                                          # §11 block bytes (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.7.0 -> 2.8.0 (Step 2)
requires:
  - file: templates/spec-mirrors/11-coding-discipline-0.4.0.md
    install: "vendored in the scaffolder repo at claude-workflow/templates/spec-mirrors/; symlinked into $HOME via the same install pattern as add-observability/"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
---

# Migration 0030 — Re-sync stale spec §11 block bytes (v2.7.0 -> 2.8.0)

**Root cause.** Nobody mis-transcribed anything. The mirror was a correct copy
of the spec at every instant. The defect is that §11's canonical prose was
revised upstream *in place*, under an unchanged `spec_version`, and this repo
mirrored that revision without shipping a migration to carry already-migrated
projects forward. Every step below is verifiable from the two repos' histories:

| Date | Commit | Effect |
|---|---|---|
| 2026-05-20 | core `5ea7ea9` | introduces spec §11 **without** the blank lines (v0.4.0) |
| 2026-05-21 | `913360e` (#42) | mirrors it **faithfully** — byte-identical to core at that moment — and ships migration 0014 |
| 2026-05-21 | `e6e44e7b`, `d38a97c` | `cparx` and `fx-signal-agent` run 0014, faithfully receiving §11 **as it then was** |
| 2026-05-25 | core `10f2c96` (#12) | **adds** a blank line after each "Anti-patterns this rule prevents:" — and does **not** bump `spec_version` |
| 2026-05-25 20:31 | callbot `4fa4dac` | runs 0014 against the **still-stale** mirror — receives the same old bytes as the other two |
| 2026-05-25 20:35 | callbot `1149187` | callbot's **own** `prettier --write` pass ("prettier-format injected §11 block to satisfy format:check") reformats the block, independently landing on the bytes core would ship |
| 2026-05-25 20:51 | `34ee72e` (#44) | mirrors core's edit (4 insertions, 1 file) with **no migration** → already-migrated projects stranded |
| 2026-05-26 12:48 | callbot `d2e92db` | PR #31 squash-merges `4fa4dac`+`1149187` to main |

So `cparx` and `fx-signal-agent` are not corrupted. They hold a faithful copy of
spec §11 as it read on 2026-05-21, and the spec moved underneath them.

**Why `callbot` needs no repair, precisely.** Not because it ran 0014 after the
mirror was fixed — it ran 0014 *twenty minutes before* (`4fa4dac`, 20:31 vs
`34ee72e`, 20:51) and received the identical stale block. It self-healed four
minutes later when its own `format:check` ran prettier over `CLAUDE.md`
(`1149187`, 20:35). Reading `d2e92db` alone suggests otherwise, because that
squash commit concatenates both originals under a single 05-26 date.

That is also the whole mechanism in one line: **prettier's "blank lines around
lists" rule is what added the four lines at every site** — core's spec
(`10f2c96`, titled "markdown/prettier-clean"), callbot's `CLAUDE.md`
(`1149187`), and this repo's mirror (`34ee72e`, "prettier-clean the vendored §11
block"). `cparx` and `fx-signal-agent` are stale for exactly one reason: nothing
runs prettier over *their* `CLAUDE.md`. Prettier never stripped anything from
anyone; it added, everywhere it ran, and the two repos it did not reach are the
two that need 0030.

**Why provenance-based idempotency is structurally blind here.** The managed
block's provenance records the spec version it was copied from — `@0.4.0`. Core
`10f2c96` changed §11's normative text *without* bumping `spec_version`, so
`@0.4.0` remained, and remains, a **genuinely correct stamp over bytes that no
longer match**. A check keyed on the provenance version is therefore not merely
unlucky here — it cannot distinguish the two states even in principle. That is
why 0030 derives idempotency from the block's actual bytes: it extracts the
block as it currently sits in `CLAUDE.md` and compares it to the vendored
mirror, byte for byte.

The same fact disabled 0014's own escape hatch. 0014's design notes prescribe
that a future spec revision vendors a new `11-coding-discipline-0.5.0.md` and a
migration swaps the provenance line plus the block bytes. That convention could
never fire: core never shipped 0.5.0. It revised 0.4.0 in place.

**Why no spec-version bump here.** `agenticapps-workflow-core`'s
`spec/11-coding-discipline.md` is `spec_version: 0.4.0` both before and after
`10f2c96`. The mirror's filename was correct throughout, and inventing a
`0.4.1` would stamp a version that does not exist upstream. `implements_spec`
stays `0.9.0`, unchanged.

**The block region.** The bytes being compared and replaced are bounded by
the provenance comment on one side and the *last non-blank line* of the block
on the other — not the line immediately before the terminator:

```
P = the single line matching PROV_RE
H = the line matching `## Coding Discipline (NON-NEGOTIABLE)`, found by
    scanning forward from P. Pre-flight rule 4 requires H at or after P+1,
    with only blank lines (never other content) between P and H — H is not
    required to be exactly P+1.
T = the first line > H matching `^## ` OR `^<!-- gitnexus:start -->$`;
    if none exists, T = EOF+1
E = the last NON-BLANK line in the range H..T-1

The block region is H..E.  Compare lines H..E against the mirror.
On replace, emit lines 1..P, then the mirror's bytes, then lines E+1..EOF.
```

A blank line between P and H is common, not a defect: prettier's "blank
line after an HTML comment" rule inserts exactly one there, and this is the
real, currently-committed shape of `callbot`'s `CLAUDE.md` (provenance at
line 8, heading at line 10) — the same `prettier --write` pass that healed
its §11 block bytes (`1149187`, see the root-cause table above) also
inserted that blank line. Pre-flight rule 4 accepts it; the extract/apply
awk above already tolerates it structurally, since it scans forward from P
looking for H rather than assuming H is literally the next line.

E is the last *non-blank* line, not `T-1`, because the canonical mirror has
no trailing blank line, while a real, in-place block is always followed by a
separator blank line before the next heading or region marker. A region
ending at `T-1` would capture that separator as part of the region, and Apply
would then write the mirror's bytes — which end at `every diff.` — straight
over it, leaving the block's last line butted against the next `## ` heading
with no blank line between them.

That state *converges*: on the next run the `T-1` extraction does match the
mirror and does report "in sync". So a test that only asks "does it converge?"
— apply, then assert the idempotency check now passes — cannot see the damage.
What sees it is an assertion about the whole file: the separator blank line is
gone, and that is a change to bytes *outside* the block region, which no
block-scoped comparison would ever notice. The damage itself is deleting a
blank line around a block — the same defect class `34ee72e` existed to repair,
reintroduced one level up while being healed one level down. Both the
idempotency check's `extract_block`
and the Apply pass's replacement awk implement `H..E` by buffering blank
lines and only emitting them once a later non-blank line proves they were
interior to the block (never trailing).

The terminator that bounds the block admits either a `^## ` heading or a line
that is *exactly* `<!-- gitnexus:start -->` — the same alternation migration
0029 introduced for the anchor itself. A `^## `-only terminator would run the
byte replacement straight through a GitNexus-managed region and destroy it on
any project 0029 already healed.

**Known limitations (not fixed here, shared with 0014/0029):**

- **Prose between the block and its terminator is deleted.** This is the only
  limitation here that destroys data rather than refusing, so it is stated
  first. The managed block has no end marker: the region is implicitly
  "provenance → the last non-blank line before the next `## ` or
  `<!-- gitnexus:start -->`". Anything a user writes *after* the block's closing
  paragraph but *before* that terminator is inside the region and is replaced
  along with it. Migration 0029, already applied across the fleet, deletes the
  identical line — 0030 inherits this boundary, it does not introduce it, and
  fixing it means giving §11 an end marker, which is a change to 0014's on-disk
  contract and belongs in its own migration. All five fleet repos were checked:
  none has content in that position, and every E2E run deletes zero lines.
- **CRLF.** A CRLF `CLAUDE.md` fails the line-oriented anchors, since `^...$`
  never matches a line ending in `\r`. The effect is a clean pre-flight refusal
  (rule 3 counts zero provenance lines), not corruption.
- **Markers inside fenced code blocks.** A provenance or `gitnexus:start` marker
  written literally inside a fence is treated as a real marker, since awk has no
  fence awareness. The effect is a refusal or a no-op, not corruption.

Neither CRLF nor an in-fence marker has a live instance in the fleet today.

## Pre-flight (hard aborts on failure)

```bash
set -eu
SKILL_FILE=".claude/skills/agentic-apps-workflow/SKILL.md"
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

# 1. Vendored mirror present, non-empty, and not truncated. The tail sentinel
#    subsumes `test -s`: an empty file cannot carry the final line either. Both
#    are kept because the -s failure names the actual problem (missing install)
#    while the sentinel names a different one (partial copy).
if [ ! -s "$SPEC_BLOCK" ]; then
  echo "ABORT: vendored §11 mirror missing or empty at $SPEC_BLOCK"
  echo "       Install the scaffolder skill, then re-run."
  exit 1
fi
if ! tail -n 1 "$SPEC_BLOCK" | grep -qF 'session-level discipline the model brings to every diff.'; then
  echo "ABORT: vendored §11 mirror is truncated — its last line is not the"
  echo "       canonical closing line. Refusing to write a partial block."
  exit 1
fi

# 2. CLAUDE.md must exist. 0030 re-syncs an existing block; it never injects.
if [ ! -f CLAUDE.md ]; then
  echo "ABORT: no CLAUDE.md in $(pwd)"
  exit 1
fi

# 3. Exactly one provenance line and exactly one §11 heading.
#    Zero  -> 0014 never ran here; injection is 0029's job, not 0030's.
#    Two+  -> ambiguous; refuse rather than guess which block is canonical.
PROV_COUNT=$(grep -cE "$PROV_RE" CLAUDE.md || true)
HEAD_COUNT=$(grep -cE '^## Coding Discipline \(NON-NEGOTIABLE\)$' CLAUDE.md || true)
if [ "$PROV_COUNT" -ne 1 ] || [ "$HEAD_COUNT" -ne 1 ]; then
  echo "ABORT: expected exactly one §11 provenance line and one §11 heading;"
  echo "       found $PROV_COUNT provenance line(s) and $HEAD_COUNT heading(s)."
  echo "       0030 re-syncs an existing managed block. It does not inject one"
  echo "       (that is 0029) and it will not guess between duplicates."
  exit 1
fi

# 4. The heading must plainly belong to its provenance line. It may sit
#    immediately below the provenance line, or be separated from it by
#    blank lines only — that shape is not a defect, it is prettier's normal
#    output (its "blank line after an HTML comment" rule) and it is the
#    real, currently-committed shape of callbot's CLAUDE.md (provenance at
#    line 8, heading at line 10). Refusing that shape would hard-abort a
#    repo whose block is already byte-identical to the canonical mirror.
#
#    Two shapes are still refused:
#
#    - The heading sits ABOVE its provenance line. This is not merely
#      mis-placed, it is silent non-convergence: extract_block and the
#      Apply awk (Step 1, below) only start looking for the heading AFTER
#      matching the provenance line (`!seen && $0 ~ prov { seen=1; next }`).
#      A heading that already passed by the time the provenance line is
#      reached is never entered — `inb` never becomes 1 — so both the
#      idempotency check and Apply would silently no-op forever while the
#      idempotency check keeps reporting "stale".
#    - Non-blank content sits between the provenance line and the heading
#      (extra prose, another heading, anything). That means the provenance
#      line does not plainly belong to this heading, and 0030 refuses
#      rather than guess which heading it was meant to stamp.
PROV_LINE=$(grep -nE "$PROV_RE" CLAUDE.md | cut -d: -f1)
HEAD_LINE=$(grep -nE '^## Coding Discipline \(NON-NEGOTIABLE\)$' CLAUDE.md | cut -d: -f1)
if [ "$HEAD_LINE" -lt "$PROV_LINE" ]; then
  echo "ABORT: §11 heading is at line $HEAD_LINE, above its provenance line"
  echo "       at line $PROV_LINE. extract/apply only start looking for the"
  echo "       heading AFTER matching the provenance line, so a heading"
  echo "       above it is never entered — this would never converge, not"
  echo "       merely mis-place the block."
  exit 1
fi
# BETWEEN counts non-blank lines strictly between P and H. Computed with awk,
# not `sed -n "$a,$bp"`, because BSD sed's inverted-range behavior (a > b) is
# not "print nothing" as one might assume — verified on this machine: it
# prints the line at address $a, which here is H itself, producing a false
# non-zero BETWEEN on the adjacent case (H == P+1) that must be accepted.
# awk's `NR >= s && NR <= e` is false for every NR when s > e, so it holds
# for the adjacent case without a special-cased guard.
BETWEEN=$(awk -v s="$((PROV_LINE + 1))" -v e="$((HEAD_LINE - 1))" \
  'NR >= s && NR <= e && $0 ~ /[^[:space:]]/ { c++ } END { print c + 0 }' CLAUDE.md)
if [ "$BETWEEN" -ne 0 ]; then
  echo "ABORT: §11 heading is at line $HEAD_LINE but its provenance is at"
  echo "       line $PROV_LINE, with non-blank content between them — the"
  echo "       provenance does not plainly belong to this heading."
  exit 1
fi

# 5. Version floor.
INSTALLED=$(grep -E '^version:' "$SKILL_FILE" 2>/dev/null | sed 's/version: //')
case "$INSTALLED" in
  2.7.0|2.8.0) ;;
  *)
    echo "ABORT: project is at '$INSTALLED'; 0030 requires 2.7.0 (or 2.8.0 for re-apply)."
    echo "       Chain 0028 -> 0029 first."
    exit 1
    ;;
esac
```

## Steps

### Step 1 — Re-sync the §11 block bytes

**Idempotency check:**

```bash
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

extract_block() {
  awk -v prov="$PROV_RE" '
    !seen && $0 ~ prov { seen=1; next }
    seen && !inb && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { inb=1; buf=$0; next }
    inb && (/^## / || /^<!-- gitnexus:start -->$/) { exit }
    inb {
      # Buffer blank lines: they are only emitted once a later non-blank line
      # proves they are interior to the block, never trailing. This is what
      # pins the region to E (last non-blank) instead of T-1.
      if ($0 == "") { pending = pending "\n"; next }
      buf = buf pending "\n" $0; pending = ""
    }
    END { if (inb) print buf }
  ' CLAUDE.md
}

CURRENT="$(extract_block)"
CANON="$(cat "$SPEC_BLOCK")"

[ "$CURRENT" = "$CANON" ]
```

**Apply:**

```bash
set -eu
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

# Emit: lines 1..P (through the provenance line), the mirror's bytes verbatim,
# then lines E+1..EOF (the separator blanks and everything after, untouched).
# The terminator admits `<!-- gitnexus:start -->` as well as `^## ` because
# 0029 anchors §11 above a GitNexus region, breaking 0014's "a `## ` always
# follows" invariant. A `^## `-only terminator would run the replacement
# through the region marker and destroy the region.
#
# `pending_out` buffers blank lines the same way extract_block's `pending`
# does: they are only re-emitted once the terminator proves they are the
# separator, never swallowed as part of the old block's body. If a non-blank
# line follows instead, they were interior to the stale block and are
# discarded with it — this is what pins the region to E (last non-blank)
# instead of T-1; see the rationale's region definition above.
awk -v prov="$PROV_RE" -v block_file="$SPEC_BLOCK" '
  BEGIN { while ((getline l < block_file) > 0) canon = (canon == "" ? l : canon "\n" l) }
  !seen && $0 ~ prov { print; seen=1; next }
  seen && !done && !inb && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
    inb=1; print canon; next
  }
  inb && (/^## / || /^<!-- gitnexus:start -->$/) { inb=0; done=1; print pending_out $0; pending_out=""; next }
  inb {
    if ($0 == "") { pending_out = pending_out "\n"; next }
    pending_out = ""; next
  }
  { print }
  END { if (inb) printf "%s", pending_out }
' CLAUDE.md > CLAUDE.md.0030.tmp

# The tmp must never replace CLAUDE.md unless non-empty (a truncated rewrite
# must never destroy the file) and the `mv` must be atomic; the tmp is
# cleaned up on every path, including a failed `mv`, so it never leaks a
# stray `.0030.tmp` into the project (mirrors 0029's Step 1 Apply idiom).
if [ -s CLAUDE.md.0030.tmp ]; then
  if mv CLAUDE.md.0030.tmp CLAUDE.md; then
    rm -f CLAUDE.md.0030.tmp
    echo "0030: §11 block re-synced to canonical mirror bytes."
  else
    rm -f CLAUDE.md.0030.tmp
    echo "ABORT: migration 0030 Step 1 — mv failed; refusing to report"
    echo "       success. CLAUDE.md left as-is (mv is atomic on failure);"
    echo "       check disk space / permissions."
    exit 1
  fi
else
  rm -f CLAUDE.md.0030.tmp
  echo "ABORT: migration 0030 Step 1 — the re-sync pass produced no output;"
  echo "       refusing to replace CLAUDE.md with a possibly-truncated result."
  exit 1
fi
```

**Rollback:**

Step 1 has no forward inverse. It replaces non-canonical §11 bytes with the
canonical ones the spec mandates; the pre-migration bytes are not recoverable
from the post-migration file, and restoring them would re-introduce the exact
defect 0030 exists to fix. This is safe by construction because Step 1 is
byte-idempotent: if Step 2 fails, the project holds a canonical block and a
2.7.0 stamp, 0030 stays pending, and a re-run is a no-op for Step 1 plus a
retry for Step 2. `migrations/README.md` sanctions this — "partial-state
recovery may be more useful than full revert" and rollback may be "manual".
Rollback is therefore an honest report, not an action: it never removes or
rewrites `CLAUDE.md`, and it never exits the calling shell (an `exit` from an
eval'd Rollback block would terminate the caller, not just this block).

```bash
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

if [ -f CLAUDE.md ] && grep -qE "$PROV_RE" CLAUDE.md; then
  echo "ROLLBACK: Step 1 has no inverse — CLAUDE.md's §11 block is left"
  echo "          canonical (byte-identical to the vendored mirror)."
else
  echo "ROLLBACK: no managed §11 block (spec-source: agenticapps-workflow-core"
  echo "          provenance) present in CLAUDE.md — nothing to do."
fi
```

### Step 2 — Bump the installed scaffolder version 2.7.0 -> 2.8.0

**Idempotency check:**

```bash
grep -q '^version: 2\.8\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -qE '^version: 2\.(7\.0|8\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.0030.bak 's/^version: 2\.7\.0$/version: 2.8.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0030.bak
```

**Rollback:**

```bash
sed -i.0030.bak 's/^version: 2\.8\.0$/version: 2.7.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0030.bak
```

## Downstream

`cparx` and `fx-signal-agent` are the two repos this repairs — both ran
migration 0014 on 2026-05-21, four days before `34ee72e` updated the vendored
mirror, and both stamp `implements_spec: 0.9.0` while carrying a block missing
the four blank lines that edit added. Both are at workflow `version: 2.5.0`
today, so applying 0030 means chaining 0028 → 0029 → 0030; 0029 is expected to
be a positional no-op on each (their §11 already sits above any region) while
bumping the stamp.

`callbot` needs no repair, but **not** because it ran 0014 after the mirror was
updated — see the root-cause table above: it ran 0014 twenty minutes *before*
and self-healed via its own prettier pass. Its block is byte-identical to the
canonical mirror today, so Step 1's idempotency check short-circuits and 0030
writes nothing. Its provenance line is separated from the §11 heading by a
blank line (prettier's HTML-comment rule, from that same pass), which pre-flight
rule 4 accepts by design — an earlier revision of rule 4 required strict
adjacency and hard-aborted on `callbot`, which is the shape fixture
`11-prettier-spaced-provenance-heals` now binds.

`fbc-platform` and `agenticapps-roadmap` also carry verbatim blocks and are
likewise no-ops.
