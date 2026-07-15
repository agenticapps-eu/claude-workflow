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

**Root cause.** Commit `913360e` (PR #42, "spec 0.4.0 absorption", 2026-05-21)
shipped `templates/spec-mirrors/11-coding-discipline-0.4.0.md` as a faulty
transcription of the core spec: the blank line separating each "Anti-patterns
this rule prevents:" label from its bullet list was dropped, in all four
occurrences. Commit `34ee72e` (PR #44, "prettier-clean the vendored §11
block", 2026-05-25) added those four blank lines back, restoring the mirror's
fidelity to `agenticapps-workflow-core`'s spec — but shipped no re-sync
migration, so any project that had already run migration 0014 against the
pre-fix mirror was left stranded on the stale bytes.

Two repos ran 0014 before the fix landed and carry the stale block: `cparx`
(via commit `e6e44e7b`, 2026-05-21) and `fx-signal-agent` (via `d38a97c`,
2026-05-21) — both four days before `34ee72e`. `callbot` ran 0014 after the
fix (`d2e92db`, 2026-05-26); its block is byte-identical to the canonical
mirror today and is not affected.

**Why provenance-based idempotency fails.** The managed block's provenance
comment records the spec version it was copied from — `@0.4.0` — and that
stamp never changed across the fix, because the underlying spec text never
changed; only the mirror's *transcription* of it did. A check keyed on the
provenance stamp alone reports "already applied" and short-circuits before
ever comparing bytes. 0030 derives its idempotency check from the block's
actual bytes instead: it extracts the block as it currently sits in
`CLAUDE.md` and compares it to the vendored mirror, byte for byte.

**Why no spec-version bump.** `agenticapps-workflow-core`'s
`spec/11-coding-discipline.md` is `spec_version: 0.4.0`, and §11's normative
text did not change — only the vendored mirror's buggy transcription of it
did. `implements_spec` stays `0.9.0`, unchanged.

**The block region.** The bytes being compared and replaced are bounded by
the provenance comment on one side and the *last non-blank line* of the block
on the other — not the line immediately before the terminator:

```
P = the single line matching PROV_RE
H = P+1, which MUST be `## Coding Discipline (NON-NEGOTIABLE)`
T = the first line > H matching `^## ` OR `^<!-- gitnexus:start -->$`;
    if none exists, T = EOF+1
E = the last NON-BLANK line in the range H..T-1

The block region is H..E.  Compare lines H..E against the mirror.
On replace, emit lines 1..P, then the mirror's bytes, then lines E+1..EOF.
```

E is the last *non-blank* line, not `T-1`, because the canonical mirror has
no trailing blank line, while a real, in-place block is always followed by a
separator blank line before the next heading or region marker. A region
ending at `T-1` would capture that separator as part of the region, and Apply
would then write the mirror's bytes — which end at `every diff.` — straight
over it, leaving the block's last line butted against the next `## ` heading
with no blank line between them.

That state *converges*: on the next run the `T-1` extraction matches the
mirror and reports "in sync". So an idempotency or convergence test would
never catch it — the corruption is silent, permanent, and green. What it
actually does is delete a blank line around a block, which is the same defect
class `34ee72e` existed to repair; a `T-1` region would reintroduce it one
level up while healing it one level down. Both the idempotency check's
`extract_block`
and the Apply pass's replacement awk implement `H..E` by buffering blank
lines and only emitting them once a later non-blank line proves they were
interior to the block (never trailing).

The terminator that bounds the block admits either a `^## ` heading or a line
that is *exactly* `<!-- gitnexus:start -->` — the same alternation migration
0029 introduced for the anchor itself. A `^## `-only terminator would run the
byte replacement straight through a GitNexus-managed region and destroy it on
any project 0029 already healed.

**Known limitations (not fixed here, shared with 0014/0029):** a CRLF
`CLAUDE.md` fails the line-oriented anchors, since `^...$` never matches a
line ending in `\r`; and a provenance or `gitnexus:start` marker written
literally inside a fenced code block is treated as a real marker, since awk
has no fence awareness. Neither shape has a live instance in the fleet today.

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

# 4. The heading must sit immediately below the provenance line.
PROV_LINE=$(grep -nE "$PROV_RE" CLAUDE.md | cut -d: -f1)
HEAD_LINE=$(grep -nE '^## Coding Discipline \(NON-NEGOTIABLE\)$' CLAUDE.md | cut -d: -f1)
if [ "$HEAD_LINE" -ne $((PROV_LINE + 1)) ]; then
  echo "ABORT: §11 heading is at line $HEAD_LINE but its provenance is at"
  echo "       line $PROV_LINE — expected the heading immediately below."
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
migration 0014 on 2026-05-21, four days before `34ee72e` fixed the vendored
mirror, and both stamp `implements_spec: 0.9.0` while carrying a block
missing the four blank lines the fix restored. `callbot` ran 0014 after the
fix and needs no repair; its block is already byte-identical to the
canonical mirror, so Step 1's idempotency check short-circuits on it.
