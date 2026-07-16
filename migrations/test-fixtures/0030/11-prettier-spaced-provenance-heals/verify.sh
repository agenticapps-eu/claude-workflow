#!/bin/sh
# Verify pre-flight ACCEPTS callbot's real shape — provenance, one blank
# line, then the heading — and that 0030 heals the stale block exactly as
# fixture 01 does, while preserving the blank line between provenance and
# heading (a byte outside the block region; a careless re-tightening of
# rule 4 back to strict adjacency, or an extract/apply that swallowed that
# blank line, would both be caught here).
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# Pre-condition: exactly one provenance line and one heading, with exactly
# one blank line between them (callbot's real shape — not adjacent).
[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: fixture must start with exactly one provenance line"
  exit 1
}
[ "$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: fixture must start with exactly one §11 heading"
  exit 1
}
prov_line=$(grep -n '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md | cut -d: -f1)
head_line=$(grep -n '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md | cut -d: -f1)
[ "$head_line" -eq $((prov_line + 2)) ] || {
  echo "PRE: fixture must place the heading exactly one blank line below"
  echo "     the provenance line (prov=$prov_line, head=$head_line)"
  exit 1
}
sed -n "$((prov_line + 1))p" CLAUDE.md | grep -q '^$' || {
  echo "PRE: fixture must have a blank line between provenance and heading"
  exit 1
}

# Pre-flight must ACCEPT this shape outright — the production bug this
# fixture closes was pre-flight hard-aborting on exactly this shape.
preflight || {
  echo "FAIL: pre-flight refused callbot's real shape (provenance, one"
  echo "      blank line, then heading) — this shape is not a defect"
  exit 1
}

cp CLAUDE.md CLAUDE.md.before

check_step1_idempotent && { echo "FAIL: idempotency check passed on a STALE block"; exit 1; }

apply_step1

# The block itself heals to the mirror's bytes.
awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' CLAUDE.md > got.md
diff "$MIRROR" got.md || { echo "FAIL: block did not heal to mirror bytes"; exit 1; }

# Strict whole-file diff: the ONLY change versus BEFORE may be the four
# blank-line insertions inside the block. Same discipline as fixture 01 —
# any `<` line means something outside the block region was touched, which
# here specifically includes the blank line between provenance and heading.
diff CLAUDE.md.before CLAUDE.md > diff.out || true

if grep -q '^<' diff.out; then
  echo "FAIL: apply_step1 removed or altered a line outside the healed"
  echo "      block (possibly the provenance/heading blank line). Diff:"
  cat diff.out
  exit 1
fi

inserted_count=$(grep -c '^>' diff.out || true)
if [ "$inserted_count" -ne 4 ]; then
  echo "FAIL: expected exactly 4 inserted lines (the four healed blank"
  echo "      lines), got $inserted_count. Diff:"
  cat diff.out
  exit 1
fi

if grep '^>' diff.out | grep -qv '^> $'; then
  echo "FAIL: an inserted diff line was non-blank — expected only blank-line"
  echo "      insertions. Diff:"
  cat diff.out
  exit 1
fi

# The blank line between provenance and heading must survive untouched, at
# the same line number, still blank — and the heading must not have moved.
sed -n "$((prov_line + 1))p" CLAUDE.md | grep -q '^$' || {
  echo "FAIL: the blank line between provenance and heading was lost or"
  echo "      moved by the heal"
  exit 1
}
head_line_after=$(grep -n '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md | cut -d: -f1)
[ "$head_line_after" -eq "$head_line" ] || {
  echo "FAIL: the heading moved from line $head_line to $head_line_after —"
  echo "      the provenance/heading spacing was not preserved"
  exit 1
}

# It now converges: re-running the idempotency check reports in sync.
check_step1_idempotent || {
  echo "FAIL: block healed but idempotency check still reports stale —"
  echo "      does not converge"
  exit 1
}

grep -q '^## Project Overview$' CLAUDE.md || { echo "FAIL: content after the block was destroyed"; exit 1; }
grep -q '^Guidance\.$' CLAUDE.md || { echo "FAIL: content before the block was destroyed"; exit 1; }
[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || { echo "FAIL: provenance lost or duplicated"; exit 1; }

echo "OK: pre-flight accepted callbot's real prettier-spaced shape; stale"
echo "    block healed to mirror bytes; only the four blank-line insertions"
echo "    changed; blank line between provenance and heading preserved;"
echo "    converges"
exit 0
