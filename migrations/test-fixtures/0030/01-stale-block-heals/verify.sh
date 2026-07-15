#!/bin/sh
# Verify 0030 heals a stale block AND that the ONLY difference between BEFORE
# and AFTER is the four blank-line insertions the healing restores — nothing
# else added, removed, or changed.
#
# This is the single most important assertion in this fixture set. A region
# mis-pinned to the terminator line (T-1) instead of the last non-blank line
# (E) CONVERGES — it passes fixture 02 (in-sync-noop) and fixture 05
# (converges) — while silently deleting the separator blank line that must
# sit between the healed block and the next `## ` heading. Fixture 05 alone
# does NOT catch that (proven by execution, not assumed); this whole-file
# diff, plus the explicit separator check below, is what does.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

cp CLAUDE.md CLAUDE.md.before

check_step1_idempotent && { echo "FAIL: idempotency check passed on a STALE block"; exit 1; }

apply_step1

# The block itself heals to the mirror's bytes.
awk '/^## Coding Discipline \(NON-NEGOTIABLE\)$/{f=1} f{print} f && /session-level discipline the model brings to every diff\.$/{exit}' CLAUDE.md > got.md
diff "$MIRROR" got.md || { echo "FAIL: block did not heal to mirror bytes"; exit 1; }

# Strict whole-file diff: the ONLY change versus BEFORE may be blank-line
# insertions, and there must be exactly 4 of them (one per healed
# "Anti-patterns this rule prevents:" section). `diff` marks every removed or
# changed line with a leading `<` (a pure change shows both `<` and `>`); a
# region correctly pinned at E can never produce a `<` line, because nothing
# outside the replaced H..E span is touched. A region mis-pinned to T-1
# deletes the separator blank line, which shows up here as a REMOVED (`<`)
# line — that is precisely the T-1 bug this check binds.
diff CLAUDE.md.before CLAUDE.md > diff.out || true

if grep -q '^<' diff.out; then
  echo "FAIL: apply_step1 removed or altered a line outside the healed block."
  echo "      THIS IS THE T-1 BUG: a region pinned to the terminator line"
  echo "      instead of the last non-blank line devours the separator blank"
  echo "      line before the next heading. Diff:"
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

# Explicitly assert the separator blank line before the next heading
# survived — the exact byte the T-1 bug deletes.
head_line=$(grep -n '^## Project Overview$' CLAUDE.md | cut -d: -f1)
sep_line=$((head_line - 1))
sed -n "${sep_line}p" CLAUDE.md | grep -q '^$' || {
  echo "FAIL: THE T-1 BUG: the separator blank line before '## Project"
  echo "      Overview' is gone — the region was pinned to the terminator"
  echo "      line, not the last non-blank line, and consumed the separator."
  exit 1
}

grep -q '^## Project Overview$' CLAUDE.md || { echo "FAIL: content after the block was destroyed"; exit 1; }
grep -q '^Guidance\.$' CLAUDE.md || { echo "FAIL: content before the block was destroyed"; exit 1; }
[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || { echo "FAIL: provenance lost or duplicated"; exit 1; }

echo "OK: stale block healed to mirror bytes; the ONLY change vs BEFORE is"
echo "    the four blank-line insertions; separator blank line before the"
echo "    next heading preserved (T-1 bug not present)"
exit 0
