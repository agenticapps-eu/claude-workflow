# Migration 0030 — Spec §11 Mirror Re-sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship migration 0030 (2.7.0 → 2.8.0), which re-syncs a stale spec §11 block to the canonical mirror's bytes, and bind the mirror to workflow-core's spec in CI.

**Architecture:** 0030 follows 0029's document-as-executable shape: the migration markdown carries `## Pre-flight`, `### Step 1` (**Idempotency check:** / **Apply:** / **Rollback:**), and `### Step 2` (version bump) fenced blocks, which the fixtures extract and `eval` rather than copy. Idempotency is derived from the block's **bytes**, never its provenance version. A separate `run-tests.sh` guard diffs `templates/spec-mirrors/11-coding-discipline-0.4.0.md` against workflow-core's `spec/11-coding-discipline.md`, with CI supplying the core spec via a second checkout.

**Tech Stack:** POSIX `sh`, `awk`, `grep`, `diff`; GitHub Actions; the existing `migrations/run-tests.sh` harness.

## Global Constraints

- **Environment bash is 3.2** (macOS). No `mapfile`, no associative arrays, no `${var^^}`. Fixture scripts are `#!/bin/sh`.
- **Scripts get BSD grep, not the ugrep shim.** Do not rely on shim behaviour (e.g. gitignore-awareness) inside any script.
- `from_version: 2.7.0`, `to_version: 2.8.0`. Version floor check mirrors 0029's: `installed >= from_version && installed < to_version`, accepting 2.8.0 for re-apply/partial state.
- **Never edit `migrations/0014-*.md` or `migrations/0029-*.md`.** Both are immutable and applied downstream.
- Canonical mirror path in a consuming project:
  `$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md`
- Provenance regex, **anchored**, copied verbatim from 0029:
  `PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'`
- The mirror's canonical last line, used as the tail sentinel:
  `session-level discipline the model brings to every diff.`
- `setup/snapshot/spec-mirrors/` is **generated** by `bin/build-snapshot.sh` (line 49) from `templates/spec-mirrors/`. Never hand-edit it; never add a second guard for it — `check-snapshot-parity.sh` and `build-snapshot.sh --check` already bind it.

## File Structure

| File | Responsibility |
|---|---|
| `migrations/0030-resync-spec-11-mirror-bytes.md` (create) | The migration: pre-flight, Step 1 (idempotency/apply/rollback), Step 2 (version bump), rationale |
| `migrations/test-fixtures/0030/common-setup.sh` (create) | Builds the BEFORE state: sandboxed `$HOME` with vendored mirror, project skeleton at 2.7.0 |
| `migrations/test-fixtures/0030/common-verify.sh` (create) | Extracts + shape-asserts the migration's own blocks; provides `preflight()`, `check_step1_idempotent()`, `apply_step1()`, `rollback_step1()` |
| `migrations/test-fixtures/0030/NN-*/` (create ×10) | One fixture each: `setup.sh`, `verify.sh`, `expected-exit` |
| `migrations/run-tests.sh` (modify) | Add `test_migration_0030`, `test_mirror_matches_core_spec_11`, dispatch entries |
| `.github/workflows/ci.yml` (modify) | Second checkout of workflow-core at `main`; `CORE_SPEC_REQUIRED=1` |
| `.gitignore` (modify) | Ignore `.core-spec/` |
| `skill/SKILL.md`, `setup/snapshot/VERSION`, `setup/snapshot/agentic-apps-workflow-SKILL.md` (modify) | 2.7.0 → 2.8.0 |
| `CHANGELOG.md` (modify) | 2.8.0 entry |
| `docs/decisions/0042-byte-derived-idempotency-for-spec-mirrors.md` (create) | ADR |
| `migrations/test-fixtures/0029/03-healthy-noop/setup.sh` (modify) | Correct a now-disproven comment (see Task 8) |

---

### Task 1: The block-region contract (the risk center)

This task defines the boundary rule every later task depends on. Implement and
test it as a standalone awk program first; Task 2 embeds it in the migration.

**Files:**
- Create: `migrations/test-fixtures/0030/common-setup.sh`
- Create: `migrations/test-fixtures/0030/common-verify.sh`

**Interfaces:**
- Produces: the region definition below, referenced verbatim by Tasks 2–5.

**The region definition (normative — copy into the migration's rationale):**

```
P = the single line matching PROV_RE
H = P+1, which MUST be `## Coding Discipline (NON-NEGOTIABLE)`
T = the first line > H matching `^## ` OR `^<!-- gitnexus:start -->$`;
    if none exists, T = EOF+1
E = the last NON-BLANK line in the range H..T-1

The block region is H..E.  Compare lines H..E against the mirror.
On replace, emit lines 1..P, then the mirror's bytes, then lines E+1..EOF.
```

**Why `E` is the last non-blank line, not `T-1`:** the mirror's final byte is
`...every diff.\n` with no trailing blank line, but in a real file the block is
followed by a blank line and then `## Project Overview`. Defining the region as
`H..T-1` would capture that separator blank, so the extracted bytes could never
equal the mirror — every apply would rewrite the file and still mismatch, and
the migration would never converge. Anchoring on `E` leaves lines `E+1..T-1`
(the separator) untouched.

**Why `^## ` does not swallow the block's own sub-headings:** the block contains
only `### ` level-3 headings. The regex `^## ` requires the third character to
be a space; in `### 1. Think Before Coding` the third character is `#`, so it
does not match.

**Why the terminator admits `gitnexus:start`:** 0029 deliberately broke 0014's
"a `## ` always follows the block" invariant by anchoring §11 above a GitNexus
region. On such a file a `^## `-only terminator would run the replacement
straight through `<!-- gitnexus:start -->` and destroy the region. This is not
exercised by either real target repo — both end at a `## ` heading — so it is
bound by fixture 03 alone.

- [ ] **Step 1: Write `common-setup.sh`**

```sh
#!/bin/sh
# Sourced by each 0030 fixture setup.sh. Builds the BEFORE state:
#   - a sandboxed $HOME carrying the vendored §11 canonical block (Apply reads
#     its bytes from there, exactly as 0014 and 0029 do)
#   - a project skeleton at 2.7.0 (0030's pre-flight floor)
# Each fixture layers its own CLAUDE.md on top (or deletes it).
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

mkdir -p "$SCAFFOLDER_DIR/templates/spec-mirrors"
cp "$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md" \
   "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 2.7.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0030
---

## Stub
EOF_PROJ_SKILL

# The STALE block: the canonical mirror with the blank line after each
# "Anti-patterns this rule prevents:" removed. This reproduces, byte for byte,
# what migration 0014 wrote into cparx (e6e44e7b) and fx-signal-agent
# (d38a97c) when it read the pre-34ee72e mirror. Derived from the mirror
# rather than pasted so it cannot rot independently of it.
make_stale_block() {
  awk '
    /^Anti-patterns this rule prevents:$/ { print; skip_next_blank=1; next }
    skip_next_blank && /^$/ { skip_next_blank=0; next }
    { skip_next_blank=0; print }
  ' "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
}
```

- [ ] **Step 2: Verify `make_stale_block` reproduces the real committed bytes**

This is the fixture's own correctness gate: if it does not match cparx's real
`HEAD`, every downstream fixture tests a fiction.

Run:

```bash
cd /Users/donald/Sourcecode/agenticapps/claude-workflow
export SCAFFOLDER_DIR=/tmp/0030chk && mkdir -p "$SCAFFOLDER_DIR/templates/spec-mirrors"
cp templates/spec-mirrors/11-coding-discipline-0.4.0.md "$SCAFFOLDER_DIR/templates/spec-mirrors/"
awk '
  /^Anti-patterns this rule prevents:$/ { print; skip_next_blank=1; next }
  skip_next_blank && /^$/ { skip_next_blank=0; next }
  { skip_next_blank=0; print }
' "$SCAFFOLDER_DIR/templates/spec-mirrors/11-coding-discipline-0.4.0.md" > /tmp/stale.md

git -C ~/Sourcecode/factiv/cparx show HEAD:CLAUDE.md \
  | awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' \
  > /tmp/cparx_real.md

diff /tmp/stale.md /tmp/cparx_real.md && echo "MATCH: fixture reproduces cparx's real bytes"
```

Expected: `MATCH: fixture reproduces cparx's real bytes` and exit 0.

- [ ] **Step 3: Write `common-verify.sh`**

Model it on `migrations/test-fixtures/0029/common-verify.sh` — same
`want`/fence discipline, same "non-empty is not the same as correct" shape
assertions. Four extractors: `## Pre-flight`, and within `### Step 1` the
blocks following `**Idempotency check:**`, `**Apply:**`, `**Rollback:**`
(each stopping at `### Step 2`).

Shape assertions — anchor on structure, NOT on guard operators (0029's
`common-verify.sh:37-46` documents why: coupling the shape check to guard text
makes a mutation-test fixture trip the loader for every other fixture, masking
the real signal):

| Extracted block | Must contain |
|---|---|
| Pre-flight | `SKILL_FILE=` and `SPEC_BLOCK=` |
| Idempotency check | `spec-source: agenticapps-workflow-core` |
| Apply | `gitnexus:start` |
| Rollback | `spec-source: agenticapps-workflow-core` |

Provide: `preflight()`, `check_step1_idempotent()`, `apply_step1()`,
`rollback_step1()` — each `eval`ing its extracted block.

- [ ] **Step 4: Commit**

```bash
git add migrations/test-fixtures/0030/common-setup.sh migrations/test-fixtures/0030/common-verify.sh
git commit -m "test(0030): fixture harness — stale-block builder + block extractors"
```

---

### Task 2: The migration document

**Files:**
- Create: `migrations/0030-resync-spec-11-mirror-bytes.md`

**Interfaces:**
- Consumes: the region definition from Task 1.
- Produces: `## Pre-flight`, `### Step 1` (**Idempotency check:** / **Apply:** / **Rollback:**), `### Step 2` — the exact headings Task 1's extractors match.

- [ ] **Step 1: Write the frontmatter and header**

```markdown
---
id: 0030
title: Re-sync stale spec §11 block bytes to the canonical mirror (v2.7.0 -> 2.8.0)
from_version: 2.7.0
to_version: 2.8.0
touches:
  - CLAUDE.md                                          # §11 block bytes (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.7.0 -> 2.8.0 (Step 2)
requires:
  - file: templates/spec-mirrors/11-coding-discipline-0.4.0.md
    install: "vendored in the scaffolder repo at claude-workflow/templates/spec-mirrors/; symlinked into $HOME via the same install pattern as add-observability/"
    verify: "test -f $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
---
```

- [ ] **Step 2: Write the Pre-flight block**

````markdown
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
````

- [ ] **Step 3: Write Step 1 — Idempotency check**

The check extracts the block region (Task 1's definition) and compares bytes.
Exit 0 means "already in sync — nothing to do".

````markdown
### Step 1 — Re-sync the §11 block bytes

**Idempotency check:**

```bash
set -eu
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
````

- [ ] **Step 4: Write Step 1 — Apply**

````markdown
**Apply:**

```bash
set -eu
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

cp CLAUDE.md CLAUDE.md.0030.bak

# Emit: lines 1..P (through the provenance line), the mirror's bytes verbatim,
# then lines E+1..EOF (the separator blanks and everything after, untouched).
# The terminator admits `<!-- gitnexus:start -->` as well as `^## ` because
# 0029 anchors §11 above a GitNexus region, breaking 0014's "a `## ` always
# follows" invariant. A `^## `-only terminator would run the replacement
# through the region marker and destroy the region.
awk -v prov="$PROV_RE" -v block_file="$SPEC_BLOCK" '
  BEGIN { while ((getline l < block_file) > 0) canon = (canon == "" ? l : canon "\n" l) }
  !seen && $0 ~ prov { print; seen=1; next }
  seen && !done && !inb && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
    inb=1; print canon; next
  }
  inb && (/^## / || /^<!-- gitnexus:start -->$/) { inb=0; done=1; print pending_out $0; pending_out=""; next }
  inb {
    # Hold blanks; if a non-blank follows, they were interior to the old block
    # and are discarded with it. If the terminator follows, they are the
    # separator and are re-emitted ahead of it.
    if ($0 == "") { pending_out = pending_out "\n"; next }
    pending_out = ""; next
  }
  { print }
  END { if (inb) printf "%s", pending_out }
' CLAUDE.md > CLAUDE.md.0030.new

mv CLAUDE.md.0030.new CLAUDE.md
rm -f CLAUDE.md.0030.bak
echo "0030: §11 block re-synced to canonical mirror bytes."
```
````

> **Implementer note:** the `pending_out` bookkeeping above is the subtlest
> code in this migration. Do not accept it on reading — Task 3 fixture 02
> (`in-sync noop`) and fixture 05 (`converges`) are what prove it. If they are
> red, fix the awk, never the fixture.
>
> **This awk was executed during planning, not merely written.** It was run
> against all four shapes (trailing `## ` heading, `gitnexus:start` terminator
> with a `## Always Do` line *inside* the region, EOF-terminated, and
> already-in-sync) and E2E against cparx's and fx-signal-agent's real
> `HEAD:CLAUDE.md`. In every case the block healed to the mirror byte-for-byte
> and the **only** change to the file was the four blank-line insertions;
> re-apply was a byte-identical no-op. Transcribe it verbatim. If you change
> it, re-run all four shapes — the trailing-blank convergence bug is invisible
> to fixture 02 and only fixture 05 catches it.

- [ ] **Step 5: Write Step 1 — Rollback**

````markdown
**Rollback:**

```bash
set -eu
PROV_RE='^<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->$'

if [ ! -f CLAUDE.md.0030.bak ]; then
  echo "ROLLBACK: no CLAUDE.md.0030.bak — nothing to restore."
  exit 0
fi
if ! grep -qE "$PROV_RE" CLAUDE.md.0030.bak; then
  echo "ROLLBACK ABORT: backup carries no §11 provenance line; refusing to"
  echo "                restore a file that is not a managed CLAUDE.md."
  exit 1
fi
mv CLAUDE.md.0030.bak CLAUDE.md
echo "0030: rolled back — CLAUDE.md restored from backup."
```
````

- [ ] **Step 6: Write Step 2 — version bump**

Model on 0029's Step 2: `sed -i.0030.bak -E 's/^version: 2\.7\.0$/version: 2.8.0/'`
on `$SKILL_FILE`, with the Rollback reversing it. `implements_spec` is
**unchanged at 0.9.0** — the spec version did not move.

- [ ] **Step 7: Write the rationale section**

Must state, each claim verifiable from git:
- Root cause: `913360e` shipped a faulty transcription; `34ee72e` (#44) restored
  spec fidelity without a re-sync migration.
- Why provenance-based idempotency fails: `@0.4.0` is a **correct stamp over
  wrong bytes**.
- Why no spec-version bump: `spec/11-coding-discipline.md` is `spec_version: 0.4.0`.
- The region definition from Task 1, verbatim.
- Known limitations, recorded not fixed: CRLF; a marker at column 0 inside a
  code fence. Both shared with 0014/0029, neither introduced here.

**Write no claim you have not run.** Six review passes on 0029 were spent on
prose asserting what the shell does not do — almost always in the rationale,
not the operative text.

- [ ] **Step 8: Commit**

```bash
git add migrations/0030-resync-spec-11-mirror-bytes.md
git commit -m "feat(migration): 0030 — re-sync stale spec §11 block bytes (2.7.0 -> 2.8.0)"
```

---

### Task 3: Fixtures

**Files:**
- Create: `migrations/test-fixtures/0030/NN-*/{setup.sh,verify.sh,expected-exit}` ×10

**Interfaces:**
- Consumes: `common-setup.sh` (`make_stale_block`), `common-verify.sh`
  (`preflight`, `check_step1_idempotent`, `apply_step1`, `rollback_step1`).

| # | Fixture | BEFORE | Asserts | exit |
|---|---|---|---|---|
| 01 | `stale-block-heals` | `make_stale_block` + `## Project Overview` after | block == mirror; bytes outside region untouched | 0 |
| 02 | `in-sync-noop` | mirror verbatim | `apply_step1` leaves file **byte-identical**; twice | 0 |
| 03 | `gitnexus-terminator` | stale block, then `<!-- gitnexus:start -->` region, **no** `## ` between | block heals; region byte-identical | 0 |
| 04 | `eof-terminated` | stale block at EOF, nothing after | block heals; no trailing-byte churn | 0 |
| 05 | `converges` | stale block | `apply_step1`; then `check_step1_idempotent` returns **0** | 0 |
| 06 | `no-provenance-refused` | §11 heading, no provenance line | `preflight` exits 1; CLAUDE.md untouched | 0 |
| 07 | `two-provenance-refused` | two provenance lines + two headings | `preflight` exits 1; CLAUDE.md untouched | 0 |
| 08 | `rollback-restores` | stale block | `apply_step1`; `rollback_step1`; file == BEFORE bytes | 0 |
| 09 | `corrupt-mirror-refused` | mirror truncated mid-block | `preflight` exits 1; CLAUDE.md untouched | 0 |
| 10 | `detached-heading-refused` | provenance line, blank line, then heading | `preflight` exits 1 (rule 4) | 0 |

Fixture 05 is the convergence proof and is **not** redundant with 02: 02 proves
a healthy file is not churned; 05 proves a *healed* file reaches that state.
The trailing-blank bug would pass 02 and fail 05.

**On numbering vs the spec:** the spec's fixture list ends with
"`CORE_SPEC_REQUIRED=1` + absent core spec → suite red". That is not a
migration fixture — it exercises the guard, not the migration, and does not use
this harness — so it lives in **Task 5, Step 4, Mutation B**. Its slot here is
taken by `10-detached-heading-refused`, which binds pre-flight rule 4. Rule 4
is not a scope addition: the spec's Apply already requires the heading to sit
"immediately below the provenance line", and rule 4 is what enforces that
precondition instead of assuming it.

- [ ] **Step 1: Write fixture 01**

```sh
#!/bin/sh
# Fixture 01 — BEFORE: the stale block (cparx's real committed bytes) followed
# by a `## ` heading. This is the exact shape of both real targets.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md
```

```sh
#!/bin/sh
# Verify 0030 heals a stale block and touches nothing outside the region.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

check_step1_idempotent && { echo "FAIL: idempotency check passed on a STALE block"; exit 1; }

apply_step1

awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' CLAUDE.md > got.md
diff "$MIRROR" got.md || { echo "FAIL: block did not heal to mirror bytes"; exit 1; }

grep -q '^## Project Overview$' CLAUDE.md || { echo "FAIL: content after the block was destroyed"; exit 1; }
grep -q '^Guidance\.$' CLAUDE.md || { echo "FAIL: content before the block was destroyed"; exit 1; }
grep -qc '^<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->$' CLAUDE.md || { echo "FAIL: provenance lost"; exit 1; }

echo "OK: stale block healed to mirror bytes; surrounding content intact"
exit 0
```

`expected-exit`: `0`

- [ ] **Step 2: Write fixture 02 (`in-sync-noop`)**

BEFORE: as fixture 01 but `cat "$MIRROR"` instead of `make_stale_block`.
Verify (modelled on 0029's `03-healthy-noop/verify.sh`):

```sh
before="$(cat CLAUDE.md)"
check_step1_idempotent || { echo "FAIL: idempotency check failed on an in-sync block"; exit 1; }
apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0030 churned an in-sync CLAUDE.md. Diff:"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}
apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: 0030 not idempotent on re-apply"; exit 1; }
echo "OK: byte-identical no-op on an in-sync CLAUDE.md, idempotently"
```

- [ ] **Step 3: Write fixture 03 (`gitnexus-terminator`)**

BEFORE:

```sh
{
  printf '# CLAUDE.md\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  make_stale_block
  printf '\n<!-- gitnexus:start -->\n# GitNexus\n\n## Always Do\n- x\n<!-- gitnexus:end -->\n'
} > CLAUDE.md
```

Verify: capture the region between `gitnexus:start` and `gitnexus:end` before
and after `apply_step1`; assert byte-identical AND that the block healed. Note
the region body contains `## Always Do` — a `^## ` line that must **not** be
mistaken for the terminator, because `gitnexus:start` precedes it.

- [ ] **Step 4: Write fixtures 04, 05, 08**

04 (`eof-terminated`): BEFORE ends after `make_stale_block` with no trailing
content. Assert block heals and the file does not gain or lose trailing bytes.

05 (`converges`):

```sh
apply_step1
check_step1_idempotent || { echo "FAIL: 0030 did not converge — a healed block still reports out-of-sync"; exit 1; }
after="$(cat CLAUDE.md)"
apply_step1
[ "$after" = "$(cat CLAUDE.md)" ] || { echo "FAIL: second apply churned a healed file"; exit 1; }
echo "OK: heals, then converges to a stable byte-identical state"
```

08 (`rollback-restores`):

```sh
before="$(cat CLAUDE.md)"
apply_step1
rollback_step1
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: rollback did not restore original bytes"; exit 1; }
echo "OK: rollback restores the pre-apply bytes"
```

- [ ] **Step 5: Write the refusal fixtures 06, 07, 09, 10**

Each: build the BEFORE, snapshot `before="$(cat CLAUDE.md)"`, then

```sh
if preflight 2>/dev/null; then echo "FAIL: pre-flight accepted <condition>"; exit 1; fi
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: refusing pre-flight still mutated CLAUDE.md"; exit 1; }
echo "OK: pre-flight refused <condition>, file untouched"
```

For 09, truncate the vendored mirror after `common-setup.sh` runs:

```sh
head -n 20 "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md" > /tmp/trunc.$$
mv /tmp/trunc.$$ "$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
```

- [ ] **Step 6: Commit**

```bash
git add migrations/test-fixtures/0030/
git commit -m "test(0030): 10 fixtures — heal, converge, no-op, refusals, rollback"
```

---

### Task 4: Wire fixtures into `run-tests.sh`

**Files:**
- Modify: `migrations/run-tests.sh` (add `test_migration_0030` after `test_migration_0029`, which ends ~line 1970; add dispatch near line 2481)

- [ ] **Step 1: Add `test_migration_0030`**

Copy `test_migration_0029`'s body (lines 1827–1895) verbatim, substituting
`0029`→`0030` and the migration filename, and **omit** the anchor-parity guard
(that guard is 0029's; 0030 adds no setup-flow twin).

- [ ] **Step 2: Add the dispatch entry**

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "0030" ]; then
  test_migration_0030
fi
```

- [ ] **Step 3: Run RED, then GREEN**

```bash
bash migrations/run-tests.sh 0030
```

Before Task 2 lands the migration: `✗ migration file missing — RED state`.
After: all 10 fixtures `✓`, `FAIL=0`.

- [ ] **Step 4: Run the full suite**

```bash
bash migrations/run-tests.sh
```

Expected: `FAIL=0`, PASS ≥ 198 (188 at 2.7.0 + 10 new fixtures).

- [ ] **Step 5: Commit**

```bash
git add migrations/run-tests.sh
git commit -m "test(0030): wire fixtures into the suite"
```

---

### Task 5: The mirror ↔ core-spec guard

**Files:**
- Modify: `migrations/run-tests.sh` (add `test_mirror_matches_core_spec_11` near `test_claude_md_reproduces_spec_11_verbatim`, ~line 2364; dispatch ~line 2505)
- Modify: `.github/workflows/ci.yml`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `CORE_SPEC_DIR` (default `../agenticapps-workflow-core`), `CORE_SPEC_REQUIRED` (unset locally, `1` in CI).

- [ ] **Step 1: Write the guard**

```bash
test_mirror_matches_core_spec_11() {
  echo ""
  echo "${YELLOW}━━━ Mirror ≡ workflow-core spec §11 ━━━${RESET}"

  local core_dir="${CORE_SPEC_DIR:-$REPO_ROOT/../agenticapps-workflow-core}"
  local core_spec="$core_dir/spec/11-coding-discipline.md"

  if [ ! -f "$core_spec" ]; then
    if [ "${CORE_SPEC_REQUIRED:-}" = "1" ]; then
      echo "  ${RED}✗${RESET} core spec not found at $core_spec"
      echo "      CORE_SPEC_REQUIRED=1 — a missing core spec is a hard failure."
      FAIL=$((FAIL+1))
    else
      echo "  ${YELLOW}SKIP${RESET}: workflow-core not cloned at $core_dir"
      echo "      (set CORE_SPEC_DIR, or CORE_SPEC_REQUIRED=1 to make this fatal)"
      SKIP=$((SKIP+1))
    fi
    return
  fi

  local mirror="$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  local tmp; tmp="$(mktemp -t core-spec-11-XXXXXX)"
  awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' \
    "$core_spec" > "$tmp"

  if [ ! -s "$tmp" ]; then
    echo "  ${RED}✗${RESET} could not extract the §11 block from $core_spec"
    FAIL=$((FAIL+1)); rm -f "$tmp"; return
  fi

  if diff -u "$tmp" "$mirror" > /dev/null; then
    echo "  ${GREEN}✓${RESET} mirror matches workflow-core spec §11 byte-for-byte"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} mirror has DRIFTED from workflow-core spec §11:"
    diff -u "$tmp" "$mirror" | sed 's/^/      /'
    echo "      The spec moved, or the mirror was transcribed wrong. Re-sync the"
    echo "      mirror AND ship a migration to carry consumers forward — a mirror"
    echo "      edit without one is what stranded cparx and fx-signal-agent."
    FAIL=$((FAIL+1))
  fi
  rm -f "$tmp"
}
```

- [ ] **Step 2: Dispatch it**

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "spec11" ]; then
  test_mirror_matches_core_spec_11
fi
```

- [ ] **Step 3: Verify it passes locally**

```bash
bash migrations/run-tests.sh spec11
```

Expected: `✓ mirror matches workflow-core spec §11 byte-for-byte`
(workflow-core is cloned at `~/Sourcecode/agenticapps/agenticapps-workflow-core`).

- [ ] **Step 4: Mutation-test the guard — MANDATORY**

A guard without a mutation proof is decoration. 0029's anchor-parity guard
could never fire and was caught only because this step was mandatory.

```bash
# Mutation A: perturb the mirror -> guard MUST go red
printf '\nMUTATION\n' >> templates/spec-mirrors/11-coding-discipline-0.4.0.md
bash migrations/run-tests.sh spec11; echo "exit=$?"   # expect ✗ and FAIL
git checkout templates/spec-mirrors/11-coding-discipline-0.4.0.md

# Mutation B: CORE_SPEC_REQUIRED=1 with core absent -> hard failure, not SKIP
CORE_SPEC_DIR=/nonexistent CORE_SPEC_REQUIRED=1 bash migrations/run-tests.sh spec11; echo "exit=$?"

# Mutation C: core absent WITHOUT the flag -> SKIP, not failure
CORE_SPEC_DIR=/nonexistent bash migrations/run-tests.sh spec11; echo "exit=$?"
```

Expected: A red, B red, C skip. If any disagrees, the guard is wrong — fix the
guard, not the expectation.

- [ ] **Step 5: Update `ci.yml`**

```yaml
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: Check out workflow-core (canonical spec)
        uses: actions/checkout@v4
        with:
          repository: agenticapps-eu/agenticapps-workflow-core
          ref: main
          path: .core-spec
```

and on the `Migration test suite` step:

```yaml
      - name: Migration test suite
        env:
          CORE_SPEC_DIR: ${{ github.workspace }}/.core-spec
          CORE_SPEC_REQUIRED: "1"
        run: bash migrations/run-tests.sh
```

`ref: main` is deliberate and unpinned: a spec change must turn this red
immediately. Pinning would leave CI green against a frozen copy and relocate
the hole to "who bumps the pin" — the same silent desync, one layer up.

- [ ] **Step 6: Verify the sibling checkout does not read as drift**

The design flags this as an assumption to verify, not assert. `.core-spec/`
lands inside the workspace where `check-snapshot-parity.sh` and
`build-snapshot.sh --check` also run.

```bash
mkdir -p .core-spec/spec && cp ~/Sourcecode/agenticapps/agenticapps-workflow-core/spec/11-coding-discipline.md .core-spec/spec/
bash migrations/check-snapshot-parity.sh; echo "parity exit=$?"
bash bin/build-snapshot.sh --check; echo "snapshot exit=$?"
rm -rf .core-spec
```

Expected: both exit 0. If either walks into `.core-spec/`, add an explicit
exclusion **in that script** and note it in the ADR.

- [ ] **Step 7: Add `.gitignore` entry**

```
.core-spec/
```

- [ ] **Step 8: Commit**

```bash
git add migrations/run-tests.sh .github/workflows/ci.yml .gitignore
git commit -m "test: bind the §11 mirror to workflow-core's spec in CI"
```

---

### Task 6: Version bump + CHANGELOG

**Files:**
- Modify: `skill/SKILL.md`, `setup/snapshot/VERSION`, `setup/snapshot/agentic-apps-workflow-SKILL.md`, `CHANGELOG.md`

- [ ] **Step 1: Bump the three stamps 2.7.0 → 2.8.0**

- [ ] **Step 2: Rebuild the snapshot**

```bash
bash bin/build-snapshot.sh && bash bin/build-snapshot.sh --check && bash migrations/check-snapshot-parity.sh
```

Expected: all exit 0.

- [ ] **Step 3: Write the CHANGELOG 2.8.0 entry**

State the true root cause (faulty transcription in `913360e`, fidelity restored
by `34ee72e` with no re-sync migration) — **not** "prettier stripped blank
lines", which is false.

- [ ] **Step 4: Full suite**

```bash
bash migrations/run-tests.sh
```

Expected: `FAIL=0`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore(release): 2.8.0 — spec §11 mirror re-sync"
```

---

### Task 7: ADR

**Files:**
- Create: `docs/decisions/0042-byte-derived-idempotency-for-spec-mirrors.md`

- [ ] **Step 1: Write the ADR**

Follow the format of `docs/decisions/0041-*.md`. Decision: **idempotency for
vendored spec-mirror payloads is derived from block bytes, never from the
provenance version stamp**, and **any mirror edit must ship a re-sync
migration**. Context: `913360e` → `34ee72e` stranded two consumers because the
provenance recorded a version that was still correct while the bytes were not.
Consequence: `test_mirror_matches_core_spec_11` makes a mirror edit fail CI
until the migration exists.

- [ ] **Step 2: Commit**

```bash
git add docs/decisions/0042-byte-derived-idempotency-for-spec-mirrors.md
git commit -m "docs: ADR-0042 — byte-derived idempotency for vendored spec mirrors"
```

---

### Task 8: Correct the disproven comment in 0029's fixture

**Files:**
- Modify: `migrations/test-fixtures/0029/03-healthy-noop/setup.sh`

Its header currently reads that cparx / fx-signal / callbot blocks *"have since
lost the blank line ... to prettier normalization"*. Both halves are disproven:
the loss was a faulty transcription in `913360e`, not prettier, and **callbot's
block is verbatim** — it is not one of the affected repos.

This is the only edit outside 0030's own files. It is in scope because 0030's
rationale contradicts it directly, and leaving both would put two mutually
exclusive accounts of the same defect in one test suite. **Comment text only —
no behaviour change**, so `run-tests.sh 0029` must stay green.

- [ ] **Step 1: Rewrite the comment**

```sh
# Fixture 03 — BEFORE: §11 correctly anchored above a late region (state A).
# This is the POSITIONAL shape of cparx / fx-signal-agent (block above a late
# region) — not their byte content: this fixture builds its block from the
# canonical mirror verbatim, whereas those two repos carry the pre-34ee72e
# mirror's bytes (four blank lines short) because 913360e transcribed the spec
# wrongly and 34ee72e fixed it without a re-sync migration. Migration 0030
# heals that; 0029 must not touch this fixture's file at all (idempotency
# short-circuits).
```

- [ ] **Step 2: Confirm 0029 stays green**

```bash
bash migrations/run-tests.sh 0029
```

Expected: `FAIL=0`.

- [ ] **Step 3: Commit**

```bash
git add migrations/test-fixtures/0029/03-healthy-noop/setup.sh
git commit -m "docs(0029): correct the disproven prettier/callbot claim in fixture 03"
```

---

### Task 9: End-to-end against the real repos

Fixtures are synthetic. This proves 0030 against the actual committed bytes it
must heal — the same E2E discipline 0029 used for agenticapps-dashboard.

**Files:** none modified (read-only sandbox run)

- [ ] **Step 1: Run 0030 against each real CLAUDE.md in a sandbox**

```bash
for repo in ~/Sourcecode/factiv/cparx ~/Sourcecode/factiv/fx-signal-agent; do
  name=$(basename "$repo")
  tmp=$(mktemp -d -t "e2e-0030-$name-XXXXXX"); home="$tmp/home"
  mkdir -p "$home/.claude/skills/agenticapps-workflow/templates/spec-mirrors"
  cp templates/spec-mirrors/11-coding-discipline-0.4.0.md \
     "$home/.claude/skills/agenticapps-workflow/templates/spec-mirrors/"
  mkdir -p "$tmp/.claude/skills/agentic-apps-workflow"
  printf -- '---\nname: agentic-apps-workflow\nversion: 2.7.0\nimplements_spec: 0.9.0\n---\n' \
    > "$tmp/.claude/skills/agentic-apps-workflow/SKILL.md"
  git -C "$repo" show HEAD:CLAUDE.md > "$tmp/CLAUDE.md"

  ( cd "$tmp" && HOME="$home" REPO_ROOT="$PWD" sh -c '
      . '"$PWD"'/migrations/test-fixtures/0030/common-verify.sh
      preflight && apply_step1 && check_step1_idempotent
    ' ) && echo "$name: E2E OK" || echo "$name: E2E FAILED"

  awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' \
    "$tmp/CLAUDE.md" > "$tmp/got.md"
  diff templates/spec-mirrors/11-coding-discipline-0.4.0.md "$tmp/got.md" \
    && echo "$name: block == mirror" || echo "$name: BLOCK MISMATCH"
  rm -rf "$tmp"
done
```

Expected, for both: `E2E OK` and `block == mirror`.

> The `REPO_ROOT` juggling above is written against this repo's checkout; adapt
> paths as needed. What must not be adapted is the assertion: healed block ==
> mirror, and `check_step1_idempotent` returns 0 afterwards.

- [ ] **Step 2: Confirm nothing outside the block moved**

```bash
# For cparx: the ONLY diff vs HEAD must be the four inserted blank lines.
diff <(git -C ~/Sourcecode/factiv/cparx show HEAD:CLAUDE.md) "$tmp/CLAUDE.md"
```

Expected: exactly four `>` blank-line insertions, nothing else.

---

### Task 10: Ship

- [ ] **Step 1: Full suite + snapshot guards**

```bash
bash migrations/run-tests.sh && bash migrations/check-snapshot-parity.sh && bash bin/build-snapshot.sh --check
```

Expected: `FAIL=0`, all exit 0.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin fix/0030-spec-11-mirror-resync
```

PR body scope: **this repo's own work only**. The repo is PUBLIC — do not name
client repos' conformance failures in the PR body (the 0029 precedent; in-repo
docs may keep naming them).

- [ ] **Step 3: `/gsd-review`**

Non-skippable. Cross-AI review catches structural blind spots a same-LLM
checker misses.

---

## Downstream application (after 0030 merges — NOT part of this plan)

Both targets are at `version: 2.5.0`, so `/update-agenticapps-workflow` chains
0028 → 0029 → 0030. 0029 is expected to be a positional no-op on both (their
§11 already sits above any region — fixture 03's shape) while bumping the
stamp; 0030 then heals the bytes.

Branch each from **`origin/main`**, not the repos' current WIP branches: cparx
is on `chore/workflow-2.5.0` and both carry ~10 unrelated dirty files that must
not leak into the PR.
