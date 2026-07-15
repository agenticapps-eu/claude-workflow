# Migration 0029 — Region-Aware §11 Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship migration 0029 so the spec §11 canonical block is anchored above any GitNexus-managed region instead of inside it, and so `agenticapps-dashboard` — stamped 2.5.0/spec-0.9.0 with no §11 block at all — is repaired.

**Architecture:** A new forward-fixing migration (0014 is immutable and permanently un-replayable for 2.x repos). Step 1 heals §11 placement in the project's `CLAUDE.md`; Step 2 bumps the installed scaffolder version. The anchor rule adds an anchored marker alternation to 0014's awk — and, because that **breaks** 0014's "block is always followed by a `## `" invariant rather than preserving it, every terminator (strip, Rollback) carries the same alternation. Anchor and terminator are one decision. The identical rule is mirrored into `setup/SKILL.md` step e2 and locked by a new parity guard, because spec §08 requires the setup flow's end state to equal a full replay.

**Tech Stack:** POSIX shell + awk (BSD awk on macOS, GNU awk in CI — no GNU-only constructs). Markdown migration documents. `migrations/run-tests.sh` fixture harness.

## Global Constraints

- **0014 is immutable.** Do not edit `migrations/0014-inject-spec-11-coding-discipline.md`. It is already applied in five repos and its `to_version: 1.14.0` makes it permanently not-pending. This fixes forward.
- **Version chain:** `from_version: 2.6.0`, `to_version: 2.7.0`. Pre-flight gate accepts both: `^version: 2\.(6\.0|7\.0)$`.
- **Anchor rule, verbatim:** insert immediately before the first line that is **either** a `## ` heading **or** a line that is *exactly* `<!-- gitnexus:start -->` — whichever comes first; EOF if neither.
- **Marker regexes MUST be anchored** (`/^<!-- gitnexus:start -->$/`, `/^<!-- gitnexus:end -->$/`) everywhere they appear — idempotency check, insert anchor, strip terminator, Rollback terminator. Unanchored they substring-match *prose mentions*; this repo's own `CLAUDE.md:2` has one inside an HTML comment, and the block would be injected into that comment and silently commented out.
- **Every terminator carries the anchor's alternation.** A healed region-led file has the block followed by the start marker, not a `## `. Any "terminate at next `^## `" consumer corrupts the region. This includes Rollback.
- **The canonical block must be non-empty before use.** `test -f` is insufficient — a zero-byte spec-mirror (an interrupted `git pull` in the scaffolder clone) makes awk's `getline` no-op, awk exit 0, and the strip's block-removal commit as "success", destroying the block permanently and leaving idempotency reporting "already applied". Pre-flight must use `test -s`, and the result must be shape-asserted before `mv`.
- **Provenance string, verbatim:** `<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`. The mirror stays at `@0.4.0` — that is the block's *content* version, unchanged since; it is **not** the spec version (0.9.1).
- **Canonical block source:** `$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md` (same as 0014).
- **Portability:** `sed -i.bak` + `rm -f` (bare `-i` is not portable). No `grep -P`. Env bash is 3.2.
- **Never overwrite a hand-pasted block.** A `## Coding Discipline (NON-NEGOTIABLE)` heading with no provenance comment ⇒ `exit 3`.
- **Three version stamps move together:** `skill/SKILL.md`, `setup/snapshot/VERSION`, `setup/snapshot/agentic-apps-workflow-SKILL.md`. `run-tests.sh`'s `test-skill-md-version-matches-latest-migration-to-version` asserts `skill/SKILL.md` version == latest migration `to_version`, so it fails until all are bumped.
- **Baseline:** `migrations/run-tests.sh` is PASS=176 / FAIL=0 on merged main (`f99f142`). The suite must end green and above that.
- **Branch:** work on `fix/0029-spec-11-region-aware-placement` (already created off `origin/main`; the design spec is committed there at `6a52199`). Never commit to main.

---

## File Structure

| File | Responsibility |
|---|---|
| `migrations/0029-region-aware-spec-11-placement.md` | **Create.** The migration: pre-flight, Step 1 (heal placement), Step 2 (version bump), rollbacks. |
| `migrations/test-fixtures/0029/common-setup.sh` | **Create.** Sandbox BEFORE state: 2.6.0 project skeleton + vendored §11 block in the fake `$HOME`. |
| `migrations/test-fixtures/0029/common-verify.sh` | **Create.** Extracts Step 1's Apply block out of the migration document so fixtures test the migration, not a copy. |
| `migrations/test-fixtures/0029/0{1..6}-*/` | **Create.** Six fixtures: `setup.sh`, `verify.sh`, `expected-exit`. |
| `migrations/run-tests.sh` | **Modify.** Add `test_migration_0029` + dispatch block + `anchor-parity` guard. |
| `setup/SKILL.md` | **Modify.** Step e2's awk (~lines 221–232) gets the identical anchor rule. |
| `skill/SKILL.md` | **Modify.** `version: 2.6.0` → `2.7.0`. |
| `setup/snapshot/VERSION` | **Modify.** → `2.7.0`. |
| `setup/snapshot/agentic-apps-workflow-SKILL.md` | **Modify.** → `2.7.0`. |
| `CHANGELOG.md` | **Modify.** 2.7.0 entry; retire the 0014 "Known issues" entry. |
| `docs/decisions/0041-region-aware-spec-11-placement.md` | **Create.** ADR for the anchor-rule decision. |

---

## Task 1: Fixture harness + six RED fixtures

**Files:**
- Create: `migrations/test-fixtures/0029/common-setup.sh`
- Create: `migrations/test-fixtures/0029/common-verify.sh`
- Create: `migrations/test-fixtures/0029/01-gitnexus-led-inject/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0029/02-inside-region-move/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0029/03-healthy-noop/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0029/04-no-claudemd/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0029/05-unmanaged-conflict/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0029/06-no-heading-eof/{setup.sh,verify.sh,expected-exit}`
- Modify: `migrations/run-tests.sh` (add `test_migration_0029` + dispatch)

**Interfaces:**
- Consumes: `REPO_ROOT`, `FIXTURES_ROOT`, `HOME` (all exported per-fixture by `run-tests.sh`); `templates/spec-mirrors/11-coding-discipline-0.4.0.md`.
- Produces: `apply_step1()` (from `common-verify.sh`) — runs the migration document's own Step 1 Apply block in the CWD. Task 2's migration document is what makes it non-empty.

- [ ] **Step 1: Write `common-setup.sh`**

Mirrors 0014's fixture harness (sandboxed `$HOME` + project skeleton), but at 0029's version floor.

```sh
#!/bin/sh
# Sourced by each 0029 fixture setup.sh. Builds the BEFORE state:
#   - a sandboxed $HOME carrying the vendored §11 canonical block (Step 1's
#     apply reads its bytes from there, exactly as 0014 does)
#   - a project skeleton at 2.6.0 (0029's pre-flight floor)
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
version: 2.6.0
implements_spec: 0.9.0
description: synthetic test fixture for migration 0029
---

## Stub
EOF_PROJ_SKILL
```

Make it executable: `chmod +x migrations/test-fixtures/0029/common-setup.sh`

- [ ] **Step 2: Write `common-verify.sh`**

This is the anti-drift mechanism from #87: a fixture that inlines a copy of the migration's shell tests the copy, and the two drift silently. The shape assertion matters — without it, a fence-format change silently locks the extractor onto the Rollback block, which would `eval` a destructive delete and still look non-empty.

```sh
#!/bin/sh
# Sourced by each 0029 fixture verify.sh. Provides the migration's own Step 1
# Apply block, read out of the migration document rather than copied.
#
# Requires: REPO_ROOT (exported by run-tests.sh).
# Provides: apply_step1() — runs Step 1's Apply block in the current directory.

MIGRATION_0029="$REPO_ROOT/migrations/0029-region-aware-spec-11-placement.md"

[ -f "$MIGRATION_0029" ] || {
  echo "PRE: migration doc not found at $MIGRATION_0029"
  exit 1
}

# Pulls the FIRST fenced block following "**Apply:**" within "### Step 1".
# `want` is cleared as soon as a fence opens, so a change from ```bash to ```sh
# cannot make the scan skip past and latch onto Step 1's Rollback fence.
extract_0029_step1_apply() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Apply:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0029"
}

STEP1_APPLY="$(extract_0029_step1_apply)"
[ -n "$STEP1_APPLY" ] || {
  echo "PRE: could not extract Step 1 Apply block from $MIGRATION_0029"
  exit 1
}

# Non-empty is not the same as correct. Assert the block carries the anchor
# rule; anything else means the document's shape moved and the extractor
# followed it somewhere wrong. Fail loudly rather than eval it.
case "$STEP1_APPLY" in
  *'gitnexus:start'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's apply — it carries no"
    echo "     gitnexus:start anchor. The migration's Step 1 shape changed;"
    echo "     fix the extractor rather than trusting this block. Extracted:"
    printf '%s\n' "$STEP1_APPLY" | sed 's/^/       /'
    exit 1
    ;;
esac

apply_step1() { eval "$STEP1_APPLY"; }
```

Make it executable: `chmod +x migrations/test-fixtures/0029/common-verify.sh`

- [ ] **Step 3: Write fixture 01 — gitnexus-led inject (state C)**

`01-gitnexus-led-inject/setup.sh`:

```sh
#!/bin/sh
# Fixture 01 — BEFORE: a gitnexus-LED CLAUDE.md with NO §11 block (state C).
# The first `## ` heading in this file is `## Always Do`, which is INSIDE the
# managed region. This is the exact shape 0014's naive anchor injects into and
# a later `gitnexus analyze` then destroys.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

This file provides guidance to Claude Code.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **demo** (100 symbols).

## Always Do
- MUST run impact analysis before editing any symbol.

## Never Do
- NEVER rename symbols with find-and-replace.
<!-- gitnexus:end -->

## Workflow
Project-specific stuff here.
EOF_CLAUDE
```

`01-gitnexus-led-inject/expected-exit`: a single line containing `0`

`01-gitnexus-led-inject/verify.sh`:

```sh
#!/bin/sh
# Verify 0029 on a gitnexus-led CLAUDE.md with no §11 block: the block is
# injected ABOVE the managed region, and survives a region regeneration.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: no §11, and the first `## ` is inside the region.
grep -q 'Coding Discipline' CLAUDE.md && { echo "PRE: §11 must be absent"; exit 1; }

apply_step1

prov=$(grep -n 'spec-source: agenticapps-workflow-core@0.4.0 §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
[ -n "$prov" ] || { echo "FAIL: §11 block not injected"; exit 1; }
[ "$prov" -lt "$start" ] || {
  echo "FAIL: §11 injected at L$prov, at/below region start L$start — this is the bug"
  exit 1
}

# Exactly one block.
n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times, expected 1"; exit 1; }

# The point of the migration: survive a region regeneration.
awk '
  /<!-- gitnexus:start -->/ { print; skip=1; print "# GitNexus — Code Intelligence"; print ""
                              print "## Always Do"; print "- regenerated"; next }
  /<!-- gitnexus:end -->/   { skip=0 }
  !skip { print }
' CLAUDE.md > CLAUDE.md.analyzed && mv CLAUDE.md.analyzed CLAUDE.md

grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md || {
  echo "FAIL: §11 destroyed by a modelled gitnexus analyze"
  exit 1
}

echo "OK: 0029 injects §11 above the region on a gitnexus-led file; survives analyze"
exit 0
```

- [ ] **Step 4: Write fixture 02 — inside-region move (state B)**

`02-inside-region-move/setup.sh`:

```sh
#!/bin/sh
# Fixture 02 — BEFORE: §11 already sits INSIDE the managed region (state B).
# This is what 0014's naive anchor produces on a gitnexus-led file, and what a
# project scaffolded today by setup step e2 still lands in. Not yet eaten;
# 0029 must move it out before the next analyze does.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus — Code Intelligence\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Always Do\n- MUST run impact analysis.\n<!-- gitnexus:end -->\n\n'
  printf '## Workflow\nProject stuff.\n'
} > CLAUDE.md
```

`02-inside-region-move/expected-exit`: a single line containing `0`

`02-inside-region-move/verify.sh`:

```sh
#!/bin/sh
# Verify 0029 moves an at-risk §11 block from inside the region to above it,
# leaving exactly one copy and an intact region.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Pre-condition: the block starts INSIDE the region.
prov=$(grep -n 'spec-source: .* §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
end=$(grep -n 'gitnexus:end' CLAUDE.md | cut -d: -f1)
[ "$prov" -gt "$start" ] && [ "$prov" -lt "$end" ] || {
  echo "PRE: fixture must start with §11 INSIDE the region (prov=$prov start=$start end=$end)"
  exit 1
}

apply_step1

prov=$(grep -n 'spec-source: .* §11' CLAUDE.md | cut -d: -f1)
start=$(grep -n 'gitnexus:start' CLAUDE.md | cut -d: -f1)
[ "$prov" -lt "$start" ] || { echo "FAIL: §11 still at/below region start (prov=$prov start=$start)"; exit 1; }

n=$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)
[ "$n" -eq 1 ] || { echo "FAIL: §11 heading appears $n times after move, expected 1"; exit 1; }

# Region markers intact and still paired.
[ "$(grep -c 'gitnexus:start' CLAUDE.md)" -eq 1 ] || { echo "FAIL: start marker damaged"; exit 1; }
[ "$(grep -c 'gitnexus:end' CLAUDE.md)" -eq 1 ] || { echo "FAIL: end marker damaged"; exit 1; }
# Region content preserved.
grep -q 'MUST run impact analysis' CLAUDE.md || { echo "FAIL: region content lost"; exit 1; }
# Project content preserved.
grep -q '^## Workflow$' CLAUDE.md || { echo "FAIL: project content lost"; exit 1; }

echo "OK: 0029 moves an inside-region §11 block above the region, exactly once"
exit 0
```

- [ ] **Step 5: Write fixture 03 — healthy no-op (state A)**

This is the zero-churn proof for the five healthy repos.

`03-healthy-noop/setup.sh`:

```sh
#!/bin/sh
# Fixture 03 — BEFORE: §11 correctly anchored above a late region (state A).
# This is the shape of cparx / fx-signal / callbot. 0029 must not touch it.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

{
  printf '# CLAUDE.md\n\nGuidance.\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  cat "$BLOCK"
  printf '\n## Project Overview\nStuff.\n\n'
  printf '<!-- gitnexus:start -->\n# GitNexus\n\n## Always Do\n- x\n<!-- gitnexus:end -->\n'
} > CLAUDE.md
```

`03-healthy-noop/expected-exit`: a single line containing `0`

`03-healthy-noop/verify.sh`:

```sh
#!/bin/sh
# Verify 0029 is a byte-for-byte no-op on a correctly-anchored file, and stays
# one on re-apply. Step 2 still bumps SKILL.md; only CLAUDE.md is asserted here.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0029 churned a healthy CLAUDE.md. Diff:"
  # Write the comparison file inside the fixture sandbox (the CWD run-tests.sh
  # created and removes), not /tmp — no stray files, no PID-collision games.
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: 0029 not idempotent on re-apply"; exit 1; }

echo "OK: 0029 is a byte-identical no-op on a healthy CLAUDE.md, idempotently"
exit 0
```

- [ ] **Step 6: Write fixture 04 — absent CLAUDE.md**

`04-no-claudemd/setup.sh`:

```sh
#!/bin/sh
# Fixture 04 — BEFORE: project has no CLAUDE.md at all. 0029 Step 1 must emit an
# informational skip rather than abort, so Step 2 still runs (0014's idiom).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
rm -f CLAUDE.md
```

`04-no-claudemd/expected-exit`: a single line containing `0`

`04-no-claudemd/verify.sh`:

```sh
#!/bin/sh
# Verify 0029 Step 1 skips informationally when there is no CLAUDE.md, creates
# no file, and does not abort.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

[ -f CLAUDE.md ] && { echo "PRE: fixture must have no CLAUDE.md"; exit 1; }

out="$(apply_step1 2>&1)" || { echo "FAIL: Step 1 aborted on absent CLAUDE.md: $out"; exit 1; }

[ -f CLAUDE.md ] && { echo "FAIL: Step 1 created a CLAUDE.md; it must not"; exit 1; }
case "$out" in
  *INFO*) ;;
  *) echo "FAIL: expected an INFO skip message, got: $out"; exit 1 ;;
esac

echo "OK: 0029 skips informationally on an absent CLAUDE.md without creating one"
exit 0
```

- [ ] **Step 7: Write fixture 05 — hand-pasted conflict (state D)**

`05-unmanaged-conflict/setup.sh`:

```sh
#!/bin/sh
# Fixture 05 — BEFORE: a §11 heading with NO provenance comment. The operator
# hand-pasted it outside the migration's management. 0029 must refuse rather
# than silently overwrite (inherits 0014's conflict rule).
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

## Coding Discipline (NON-NEGOTIABLE)

Hand-pasted content the operator wrote themselves. Must not be clobbered.

## Workflow
Stuff.
EOF_CLAUDE
```

`05-unmanaged-conflict/expected-exit`: a single line containing `0`

`05-unmanaged-conflict/verify.sh`:

```sh
#!/bin/sh
# Verify 0029 refuses a hand-pasted §11 block (exit 3) and leaves it untouched.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

before="$(cat CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || { echo "FAIL: expected exit 3 on unmanaged conflict, got $rc: $out"; exit 1; }
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: refused but still modified CLAUDE.md"; exit 1; }
grep -q 'Hand-pasted content' CLAUDE.md || { echo "FAIL: operator content clobbered"; exit 1; }

echo "OK: 0029 refuses a hand-pasted §11 block with exit 3, file untouched"
exit 0
```

- [ ] **Step 8: Write fixture 06 — no heading, EOF fallback**

`06-no-heading-eof/setup.sh`:

```sh
#!/bin/sh
# Fixture 06 — BEFORE: a CLAUDE.md with no `## ` heading and no region at all.
# The anchor scan finds nothing; the END branch must append rather than drop.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > CLAUDE.md <<'EOF_CLAUDE'
# CLAUDE.md

Just prose. No level-2 headings anywhere in this file.
EOF_CLAUDE
```

`06-no-heading-eof/expected-exit`: a single line containing `0`

`06-no-heading-eof/verify.sh`:

```sh
#!/bin/sh
# Verify the EOF fallback: no `## ` and no region means append, not drop.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

apply_step1

grep -q '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md || {
  echo "FAIL: §11 dropped on a file with no anchor"
  exit 1
}
grep -q 'Just prose' CLAUDE.md || { echo "FAIL: original content lost"; exit 1; }

# NOTE: single quotes — backticks inside a double-quoted string would be
# command substitution and try to execute `## `.
echo 'OK: 0029 appends §11 at EOF when there is no "## " heading and no region'
exit 0
```

- [ ] **Step 9: Make every fixture script executable**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
chmod +x migrations/test-fixtures/0029/common-*.sh migrations/test-fixtures/0029/*/setup.sh migrations/test-fixtures/0029/*/verify.sh
```

- [ ] **Step 10: Add `test_migration_0029` to `run-tests.sh`**

Insert immediately **after** the closing `}` of `test_migration_0028()`. This mirrors 0028's runner shape (per-fixture sandboxed `$HOME`, `REPO_ROOT`/`FIXTURES_ROOT` exported).

```bash
test_migration_0029() {
  echo ""
  echo "${YELLOW}━━━ Migration 0029 — Region-aware §11 placement ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0029"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Until the GREEN commit lands the migration body this check fails — that is
  # the RED state the TDD discipline requires (test before unit-under-test).
  local migration_file="$REPO_ROOT/migrations/0029-region-aware-spec-11-placement.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0029_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0029-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
        "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit="$(cat "$fixdir/expected-exit" 2>/dev/null || echo 0)"

    if [ "$verify_exit" -ne "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — exit $verify_exit, expected $expected_exit"
      printf '%s\n' "$verify_out" | sed 's/^/      /'
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0029_fixture "$name"
  done
}
```

- [ ] **Step 11: Wire the dispatch block**

In the dispatch section, immediately after the `0028` block (around `migrations/run-tests.sh:2334-2336`):

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "0029" ]; then
  test_migration_0029
fi
```

- [ ] **Step 12: Run the fixtures to verify they are RED**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
./migrations/run-tests.sh 0029
```

Expected: FAIL — `migration file missing: .../0029-region-aware-spec-11-placement.md — RED state`. This is the required RED. If it passes, the test is not testing anything — stop and fix.

- [ ] **Step 13: Commit the RED state**

```bash
git add migrations/test-fixtures/0029 migrations/run-tests.sh
git commit -m "test(RED): 0029 — fixtures for region-aware §11 placement

Six fixtures covering the states 0029 must heal: gitnexus-led inject (C),
inside-region move (B), healthy no-op (A, zero-churn proof), absent CLAUDE.md,
hand-pasted refusal (D), and the no-heading EOF fallback.

RED: the migration document does not exist yet.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: The migration document (GREEN)

**Files:**
- Create: `migrations/0029-region-aware-spec-11-placement.md`

**Interfaces:**
- Consumes: `apply_step1()` extraction contract from Task 1 — Step 1's Apply block must be the first fenced block after `**Apply:**` inside `### Step 1`, and must contain the literal `gitnexus:start`.
- Produces: the anchor rule literal `(/^## / || /^<!-- gitnexus:start -->$/)`, which Task 3's parity guard greps for in both this file and `setup/SKILL.md`.

- [ ] **Step 1: Write the migration document**

Create `migrations/0029-region-aware-spec-11-placement.md` with exactly this content:

````markdown
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
a `## ` heading **or** a `<!-- gitnexus:start -->` marker — whichever comes
first; EOF if neither. It is a one-alternation delta to 0014's awk, so 0014's
structural invariant survives: the block is still always followed by a `## `
line or EOF, which is what bounds the managed section for replace and rollback.

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
       /<!-- gitnexus:start -->/ { r = 1; next }
       /<!-- gitnexus:end -->/   { r = 0; next }
       r && /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ { f = 1 }
       END { exit(f ? 0 : 1) }
     ' CLAUDE.md
```

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
  # The strip is 0014's rollback logic verbatim: the block contains exactly one
  # `## ` line (its own heading), so we swallow that explicitly and terminate on
  # the NEXT `## ` — naively stopping at the first `## ` would leave the block
  # body behind (0014 fixture 07-byte-identity-replace catches that shape).
  awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ {
      in_block = 1
      next
    }
    in_block && !swallowed_own_h2 && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
      swallowed_own_h2 = 1
      next
    }
    in_block && swallowed_own_h2 && /^## / {
      in_block = 0
      print
      next
    }
    in_block { next }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0029.strip

  # Re-insert at the region-aware anchor. The alternation IS the fix: 0014 had
  # only /^## /, which selects a heading inside the region on a gitnexus-led
  # file. `whichever comes first` is what keeps the block near the top when the
  # region starts late.
  awk -v prov="$PROV" -v block_file="$SPEC_BLOCK" '
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
  ' CLAUDE.md.0029.strip > CLAUDE.md.0029.tmp \
    && mv CLAUDE.md.0029.tmp CLAUDE.md \
    && rm -f CLAUDE.md.0029.strip
  echo "INFO: migration 0029 Step 1 — §11 block anchored above any managed region."
fi
```

**Rollback:**

```bash
# Remove the managed block. Same shape as 0014's rollback: swallow the block's
# own H2 explicitly, then terminate on the NEXT `## ` (or EOF).
if [ -f CLAUDE.md ]; then
  awk '
    BEGIN { in_block = 0; swallowed_own_h2 = 0 }
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ {
      in_block = 1
      next
    }
    in_block && !swallowed_own_h2 && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ {
      swallowed_own_h2 = 1
      next
    }
    in_block && swallowed_own_h2 && /^## / {
      in_block = 0
      print
      next
    }
    in_block { next }
    !in_block { print }
  ' CLAUDE.md > CLAUDE.md.0029.tmp && mv CLAUDE.md.0029.tmp CLAUDE.md
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
````

- [ ] **Step 2: Run the fixtures to verify they are GREEN**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
./migrations/run-tests.sh 0029
```

Expected: 6 × `✓` (`01-gitnexus-led-inject`, `02-inside-region-move`, `03-healthy-noop`, `04-no-claudemd`, `05-unmanaged-conflict`, `06-no-heading-eof`), FAIL=0.

If `03-healthy-noop` fails with a diff, the strip/re-insert round-trip is not byte-identical — most likely the blank line the insert emits after the block. Fix the awk, not the fixture.

- [ ] **Step 3: Prove the fixtures actually bind (mutation test)**

A green suite means nothing if the fixtures would pass against the old rule. Temporarily revert the anchor to 0014's naive form and confirm RED:

Use `,` as the sed delimiter so the `/` characters in the awk need no escaping,
and do **not** escape `^` — it is literal here because it is not at the start of
the regex, and `\^` is undefined in POSIX BRE (it differs between BSD and GNU
sed). `&` in the *replacement* means "the whole match", so it must be escaped.
`sed -i.mut` leaves the original at `<file>.mut`, which is the restore path.

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
sed -i.mut 's,!inserted && (/^## / || /^<!-- gitnexus:start -->$/),!inserted \&\& /^## /,' \
  migrations/0029-region-aware-spec-11-placement.md
grep -c 'gitnexus:start' migrations/0029-region-aware-spec-11-placement.md
```

Expected: the count drops (the anchor alternation is gone). If it is unchanged,
the sed did not match — fix the command before trusting the result below.

```bash
./migrations/run-tests.sh 0029; echo "exit=$?"
```

Expected: `01-gitnexus-led-inject` and `02-inside-region-move` FAIL. If they pass, the fixtures do not bind the anchor rule — fix them before proceeding.

Restore from the sed backup and re-verify:

```bash
mv migrations/0029-region-aware-spec-11-placement.md.mut \
   migrations/0029-region-aware-spec-11-placement.md
./migrations/run-tests.sh 0029
```

Expected: 6 × `✓` again.

- [ ] **Step 4: Commit the GREEN state**

```bash
git add migrations/0029-region-aware-spec-11-placement.md
git commit -m "feat(migration): 0029 — anchor §11 above any GitNexus region (2.6.0 -> 2.7.0)

Anchor rule: insert before the first `## ` heading OR `<!-- gitnexus:start -->`,
whichever comes first. A one-alternation delta to 0014's awk, so 0014's
followed-by-## invariant survives.

Heals four states: no-op when correctly anchored, move when inside a region,
inject when absent, refuse when hand-pasted. 0014 is immutable and permanently
not-pending for 2.x repos, so this fixes forward.

Repairs agenticapps-dashboard, which carries no §11 block while stamping
implements_spec 0.9.0.

GREEN: 6/6 fixtures pass; mutation-verified that reverting the anchor to
0014's naive form turns fixtures 01 and 02 RED.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Setup-path parity + the anchor-parity guard

**Files:**
- Modify: `setup/SKILL.md` (step e2's awk ~lines 221–232; the byte-identity claim at :198; the branch-count reasoning at :240-243; the END-branch prose at :237-238)
- Modify: `migrations/run-tests.sh` (add the `anchor-parity` guard inside `test_migration_0029`)

**Interfaces:**
- Consumes: the anchor literal `(/^## / || /^<!-- gitnexus:start -->$/)` produced by Task 2.
- Produces: an `anchor-parity` PASS/FAIL line in the 0029 test block.

- [ ] **Step 1: Update `setup/SKILL.md` step e2's awk**

Replace the `emit()`-based awk (currently at ~`setup/SKILL.md:221-232`). Change the anchor condition **only** — leave the surrounding prose and the `emit()` shape alone.

Find:

```awk
       BEGIN { done = 0 }
       !done && /^## / { emit(); done = 1 }
       { print }
       END { if (!done) emit() }
```

Replace with:

```awk
       BEGIN { done = 0 }
       !done && (/^## / || /^<!-- gitnexus:start -->$/) { emit(); done = 1 }
       { print }
       END { if (!done) emit() }
```

- [ ] **Step 1b: Fix step e2's now-false byte-identity claim (`setup/SKILL.md:198`)**

Step 1 makes the existing claim false, so it must move in the same commit. The
sentence currently reads:

```markdown
e2. **§11 canonical block (spec §11 — CLAUDE.md)** — inject the canonical
   "Coding Discipline" block into `CLAUDE.md` behind a provenance anchor,
   byte-identical to what migration 0014 produces on the replay path. §11
```

0014 anchors on the first `## ` heading; after Step 1 setup anchors on the first
`## ` **or** `<!-- gitnexus:start -->`. Setup now deliberately produces something
0014 does not. Replace with a claim that is true and names the guard:

```markdown
e2. **§11 canonical block (spec §11 — CLAUDE.md)** — inject the canonical
   "Coding Discipline" block into `CLAUDE.md` behind a provenance anchor,
   carrying the same region-aware anchor rule as migration 0029 (enforced by
   `migrations/run-tests.sh`'s `anchor-parity` guard). §11
```

Do **not** claim byte-identity with 0029's full output: the `END` fallback
branches genuinely differ (0029 emits a leading blank before the provenance,
setup's `emit()` does not — the pre-existing Minor T1-#1 in
`.superpowers/sdd/progress-0027-spec-0.9.0.md`). That branch is unreachable
because step `e` guarantees a `## ` heading, and fixing it is out of scope here
(Surgical Changes). Claiming only what the `anchor-parity` guard actually proves
is the honest scope.

Also update the stale reasoning at `setup/SKILL.md:240-243`, which counts
"migration 0014's three branches". Replace `0014` with `0029` in both places —
0029 is now the migration whose shape setup mirrors:

```markdown
   Setup needs only two of migration 0029's three branches: setup refuses to
   re-run on an installed project (it routes to `/update`), so a CLAUDE.md
   already carrying OUR provenance anchor is unreachable here. 0029's
   move/replace branch is therefore dead code on this path.
```

- [ ] **Step 2: Update the prose under step e2 to explain the alternation**

Immediately after the fenced block in step e2, replace the sentence that reads
`The `END` branch is the fallback for a `CLAUDE.md` with no `## ` heading at
all — the block is appended rather than dropped.` with:

```markdown
   The `END` branch is the fallback for a `CLAUDE.md` with no `## ` heading at
   all — the block is appended rather than dropped.

   The anchor alternation (`/^## /` **or** `<!-- gitnexus:start -->`, whichever
   comes first) is byte-identical to migration 0029's, and
   `migrations/run-tests.sh`'s `anchor-parity` guard fails the build if the two
   ever disagree. Anchoring on the first `## ` alone would select a heading
   *inside* a GitNexus-managed region on a region-led `CLAUDE.md`, where the
   next `gitnexus analyze` would silently destroy the block.
```

- [ ] **Step 3: Add the `anchor-parity` guard to `run-tests.sh`**

Append inside `test_migration_0029()`, immediately after the fixture `for` loop and before the closing `}`:

```bash
  # ── setup flow ≡ migration replay (spec/08 Conformance) ────────────────────
  # The anchor rule is written twice: migration 0029's Step 1 apply, and the
  # setup flow's step e2. The fixtures only exercise the migration, so the setup
  # copy can drift unnoticed — which is exactly what happened to 0028's
  # predicate (#87). Collect every copy across both files and require exactly
  # one distinct value.
  local setup_file="$REPO_ROOT/setup/SKILL.md"
  local anchors distinct count
  anchors=$(grep -hoF '(/^## / || /^<!-- gitnexus:start -->$/)' "$migration_file" "$setup_file")
  count=$(printf '%s\n' "$anchors" | grep -c .)
  distinct=$(printf '%s\n' "$anchors" | sort -u | grep -c .)

  if [ "$count" -lt 2 ]; then
    echo "  ${RED}✗${RESET} anchor-parity — expected 2 copies of the anchor rule, found $count"
    echo "      (migration 0029 Step 1 apply + setup/SKILL.md step e2)"
    printf '%s\n' "$anchors" | sed 's/^/        /'
    FAIL=$((FAIL+1))
  elif [ "$distinct" -ne 1 ]; then
    echo "  ${RED}✗${RESET} anchor-parity — the $count copies disagree (spec/08 setup ≡ replay)"
    printf '%s\n' "$anchors" | sort -u | sed 's/^/        /'
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} anchor-parity — all $count copies agree (migration + setup)"
    PASS=$((PASS+1))
  fi
```

- [ ] **Step 4: Verify the guard passes**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
./migrations/run-tests.sh 0029
```

Expected: 6 × fixture `✓` plus `✓ anchor-parity — all 2 copies agree (migration + setup)`.

- [ ] **Step 5: Mutation-test the guard**

A parity guard that cannot fail is decoration. Break the setup copy and confirm it catches it:

Same sed-delimiter rules as Task 2 Step 3: `,` delimiter, unescaped `^`,
escaped `\&` in the replacement. `sed -i.mut` leaves the original at
`setup/SKILL.md.mut`.

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
sed -i.mut 's,!done && (/^## / || /^<!-- gitnexus:start -->$/),!done \&\& /^## /,' setup/SKILL.md
./migrations/run-tests.sh 0029
```

Expected: `✗ anchor-parity — expected 2 copies of the anchor rule, found 1`.

Restore from the sed backup and re-verify:

```bash
mv setup/SKILL.md.mut setup/SKILL.md
./migrations/run-tests.sh 0029
```

Expected: `✓ anchor-parity`.

- [ ] **Step 6: Commit**

```bash
git add setup/SKILL.md migrations/run-tests.sh
git commit -m "fix(setup): mirror 0029's region-aware anchor into step e2, guarded

spec §08 requires the setup flow's end state to equal a full replay. The anchor
rule now lives in two places, so add an anchor-parity guard that collects every
copy across the migration and setup/SKILL.md and requires exactly one distinct
value — the same shape as #87's predicate-parity guard, added because that
exact drift already shipped once and no fixture caught it.

Mutation-verified: reverting the setup copy to the naive anchor turns the guard
RED.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Version stamps, CHANGELOG, ADR

**Files:**
- Modify: `skill/SKILL.md`
- Modify: `setup/snapshot/VERSION`
- Modify: `setup/snapshot/agentic-apps-workflow-SKILL.md`
- Modify: `CHANGELOG.md`
- Create: `docs/decisions/0041-region-aware-spec-11-placement.md`

**Interfaces:**
- Consumes: `to_version: 2.7.0` from Task 2's migration frontmatter — `run-tests.sh`'s `test-skill-md-version-matches-latest-migration-to-version` asserts `skill/SKILL.md` matches it.
- Produces: nothing downstream; this is the release-stamp task.

- [ ] **Step 1: Confirm the version guard is currently RED**

Adding 0029 with `to_version: 2.7.0` breaks the stamp invariant until the bumps land. Prove it:

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
./migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version
```

Expected: `FAIL: SKILL.md version does not match latest migration to_version`.

- [ ] **Step 2: Bump all three version stamps**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
sed -i.bak 's/^version: 2\.6\.0$/version: 2.7.0/' skill/SKILL.md && rm -f skill/SKILL.md.bak
sed -i.bak 's/^version: 2\.6\.0$/version: 2.7.0/' setup/snapshot/agentic-apps-workflow-SKILL.md && rm -f setup/snapshot/agentic-apps-workflow-SKILL.md.bak
printf '2.7.0\n' > setup/snapshot/VERSION
```

Verify all three moved:

```bash
grep -H '^version:' skill/SKILL.md setup/snapshot/agentic-apps-workflow-SKILL.md; cat setup/snapshot/VERSION
```

Expected: `2.7.0` three times.

- [ ] **Step 3: Verify the version guard is GREEN**

```bash
./migrations/run-tests.sh test-skill-md-version-matches-latest-migration-to-version
```

Expected: `PASS: test-skill-md-version-matches-latest-migration-to-version`.

- [ ] **Step 4: Verify snapshot parity**

```bash
./migrations/check-snapshot-parity.sh; echo "exit=$?"
```

Expected: exit 0. If it reports drift, the snapshot and `migrations/` sources disagree — reconcile the snapshot rather than weakening the guard. This is the named §08 guard; it must not be bypassed.

- [ ] **Step 5: Write ADR-0041**

Create `docs/decisions/0041-region-aware-spec-11-placement.md`:

```markdown
# ADR-0041: Region-aware §11 block placement

**Status**: Accepted  **Date**: 2026-07-15  **Linear**: —

## Context

Migration 0014 anchors the spec §11 canonical block immediately before the first
`## ` heading in `CLAUDE.md`. That placement is deliberate — it guarantees the
block is followed by a `## ` line, which bounds the managed section for 0014's
replace and rollback logic.

It assumes the first `## ` belongs to project content. In a `CLAUDE.md` that
leads with the GitNexus block that heading is `## Always Do`, inside
`<!-- gitnexus:start -->…<!-- gitnexus:end -->`. The block is injected into the
region and the next `gitnexus analyze` destroys it silently. Recovery is closed:
0014's `to_version: 1.14.0` makes it permanently not-pending for 2.x repos, and
its pre-flight refuses the `--migration` force path.

A separate instance of the same confusion: `agenticapps-dashboard` was
snapshot-installed at 2.3.0, before the setup flow gained its §11 step (#84,
2.5.0), while 0014 was already past — so it carries no §11 block at all while
stamping `implements_spec: 0.9.0`.

## Decision

Anchor the block before the first line that is **either** a `## ` heading **or**
a `<!-- gitnexus:start -->` marker — whichever comes first; EOF if neither.
Ship it as migration 0029 (`from_version: 2.6.0`), which reaches installed
repos and repairs the dashboard. 0014 stays immutable.

Mirror the identical rule into `setup/SKILL.md` step e2, locked by an
`anchor-parity` guard (spec §08: setup end-state ≡ full replay).

## Alternatives Rejected

- **Anchor before `gitnexus:start` whenever a region exists.** The obvious
  reading of "put it above the region", and wrong. cparx's region starts at
  L306, so §11 would land ~300 lines down the file, violating §12's placement
  advisory. The region is only the anchor when it comes *first*.
- **Always anchor immediately after the H1.** Moves the block in all five
  healthy repos for no benefit, and breaks 0014's followed-by-`## ` invariant.
- **Edit 0014 in place.** It is immutable, already applied in five repos, and
  permanently not-pending — editing it would change nothing anywhere.
- **Vendor the anchor as a shared script both paths call.** Eliminates drift
  structurally rather than detecting it, but adds a payload file to every
  scaffolded project and pulls in 0014's `requires:`/install machinery. Larger
  blast radius than the defect warrants; the parity guard is the cheaper control.

## Consequences

- Validated against all six real repo shapes: the rule re-derives the block's
  current position exactly in the five healthy repos (zero churn), and anchors
  above the region on a gitnexus-led file.
- Five repos take a version stamp only; the dashboard gains its missing block
  and becomes conformant with the 0.9.0 it already claims.
- `codex-workflow` and `opencode-workflow` carry the same naive anchor in their
  own injectors and inherit the defect wherever their `AGENTS.md` is region-led.
  Both are currently latent. Propagation follows ADR-0037 and is tracked
  separately.
```

- [ ] **Step 6: Update the CHANGELOG**

Add a `## [2.7.0] — 2026-07-15 — Region-aware §11 placement` entry above `## [2.6.0]`, and **delete** the `### Known issues` entry describing the 0014 defect (it is now fixed — leaving it would make the CHANGELOG lie).

```markdown
## [2.7.0] — 2026-07-15 — Region-aware §11 placement

### Fixed
- **Migration 0029 — §11 could be injected inside a GitNexus-managed region.**
  0014 anchors the block before the first `## ` heading; in a `CLAUDE.md` that
  leads with the GitNexus block that heading is inside
  `<!-- gitnexus:start -->…<!-- gitnexus:end -->`, so a later `gitnexus analyze`
  destroyed the block silently. Recovery was closed — 0014's `to_version`
  (1.14.0) makes it permanently not-pending for 2.x repos, and its pre-flight
  refuses the `--migration` force path. 0029 fixes forward: anchor before the
  first `## ` heading **or** `<!-- gitnexus:start -->`, whichever comes first.
  Heals four states (no-op / move / inject / refuse-hand-pasted). Retires the
  Known issue recorded under 2.6.1.
- **`agenticapps-dashboard` carried no §11 block while stamping
  `implements_spec: 0.9.0`.** Snapshot-installed at 2.3.0, before the setup
  flow's §11 step existed (#84, 2.5.0), with 0014 already past — so neither
  install path ever gave it the block. 0029 repairs it (`/update` chains 0028
  then 0029).
- **`setup/SKILL.md` step e2 carried the same naive anchor.** Mirrored to the
  region-aware rule and locked by a new `anchor-parity` guard (spec §08: setup
  end-state ≡ full replay), modelled on #87's predicate-parity guard.
```

- [ ] **Step 7: Run the full suite**

```bash
cd ~/Sourcecode/agenticapps/claude-workflow
./migrations/run-tests.sh
```

Expected: FAIL=0, PASS ≥ 183 (the 176 baseline + 6 new fixtures + `anchor-parity`).

- [ ] **Step 8: Verify the §11 self-conformance guard still passes**

This repo's own `CLAUDE.md` carries the §11 block above its gitnexus region (#88). Nothing in 0029 should touch it — confirm:

```bash
./migrations/run-tests.sh spec-11-self-conformance
```

Expected: `PASS: spec-11-self-conformance — CLAUDE.md reproduces §11 verbatim`.

- [ ] **Step 9: Commit**

```bash
git add skill/SKILL.md setup/snapshot/VERSION setup/snapshot/agentic-apps-workflow-SKILL.md CHANGELOG.md docs/decisions/0041-region-aware-spec-11-placement.md
git commit -m "chore(release): 2.7.0 — region-aware §11 placement

Bumps the three version stamps (skill/SKILL.md, setup/snapshot/VERSION,
setup/snapshot/agentic-apps-workflow-SKILL.md) to match 0029's to_version, per
the versioning-tracks-migrations invariant that run-tests.sh enforces.

Adds ADR-0041 recording the anchor rule and the rejected alternatives — notably
'anchor before gitnexus:start whenever a region exists', which is the tempting
reading and is wrong (it drops §11 ~300 lines down cparx's file).

Retires the 0014 Known issues entry; it is fixed by 0029.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation gates (from the workflow commitment)

These are not optional and are not part of any task above.

- [ ] **`/review`** — stage 1, spec compliance, on the full branch diff.
- [ ] **`superpowers:requesting-code-review`** — stage 2, independent reviewer, code quality. Do **not** collapse the two stages.
- [ ] **`/gsd-review`** — cross-AI plan review. Per [[gsd-review-non-skippable]] this is required; codex catches structural blind spots a same-LLM checker misses. Note [[codex-exec-stdin-hang]]: `codex exec` needs `< /dev/null` or it hangs in the background.
- [ ] **`superpowers:verification-before-completion`** — before any completion claim, with posted evidence.
- [ ] **End-to-end repair proof** — build a sandbox with the dashboard's exact shape (a `CLAUDE.md` with no §11, region at L82, first `## ` at L5, project at 2.5.0), chain 0028 then 0029, and confirm §11 lands above the region. This is the claim the whole migration exists to make; do not ship on fixtures alone.
- [ ] **`superpowers:finishing-a-development-branch`** — compose the PR to main.

Not applicable: `/cso` (no auth/storage/API/LLM surface), `/qa` (no dev server).
