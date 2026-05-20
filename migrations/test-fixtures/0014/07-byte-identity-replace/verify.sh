#!/bin/sh
# Fixture 07 — verify the migration's Step 1 apply produces a §11 block
# byte-identical to the vendored canonical block (regression test for
# the replace-path awk bug; covers insert path too via a second pass).
#
# The fixture's setup.sh built a CLAUDE.md with a stale @0.4.0-pre §11
# block plus a trailing `## Workflow` section. This verify.sh:
#   1. Runs Step 1's REPLACE path (the bash is duplicated inline — the
#      migration's bash also lives inside its .md file rather than a
#      sourceable script. Acceptable duplication for one regression
#      test; the cost of divergence is caught by this fixture itself).
#   2. Extracts the resulting §11 block (everything between provenance
#      line and the next ## heading, exclusive of both endpoints) and
#      diffs against the vendored canonical block.
#   3. Verifies the trailing `## Workflow` section was preserved.
#   4. Runs Step 1's INSERT path on a fresh-apply fixture and diffs
#      that too.
set -eu

PROVENANCE='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'
SPEC_BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# Sanity: the stale state was set up correctly.
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0-pre §11 -->' CLAUDE.md \
  || { echo "fixture 07 setup wrong — expected stale provenance"; exit 1; }
grep -q '^## Workflow$' CLAUDE.md \
  || { echo "fixture 07 setup wrong — expected trailing ## Workflow section"; exit 1; }

# ─── REPLACE path ─────────────────────────────────────────────────────
# Duplicated inline from migrations/0014-…md Step 1 "Apply" (replace
# branch). If you change the migration's awk, change this too — fixture
# 07 is the canary.
awk -v prov="$PROVENANCE" -v block_file="$SPEC_BLOCK" '
  BEGIN { in_block = 0; replaced = 0; swallowed_own_h2 = 0 }
  /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ && !replaced {
    print prov
    while ((getline line < block_file) > 0) print line
    close(block_file)
    print ""
    in_block = 1
    replaced = 1
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
' CLAUDE.md > CLAUDE.md.0014.tmp && mv CLAUDE.md.0014.tmp CLAUDE.md

# Assert: current-version provenance is now present.
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  || { echo "REPLACE: current provenance missing after apply"; exit 1; }
# Assert: stale provenance is gone.
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0-pre §11 -->' CLAUDE.md \
  && { echo "REPLACE: stale provenance still present after apply"; exit 1; }
# Assert: trailing ## Workflow section was preserved.
grep -q '^## Workflow$' CLAUDE.md \
  || { echo "REPLACE: trailing ## Workflow section was deleted (bug regression)"; exit 1; }

# Extract the injected §11 block. The block is bounded by:
#   - provenance line (exclusive)
#   - next `## ` line AFTER the block's own ## heading (exclusive)
# We mirror the parser used by the verification-gate script in PLAN.md.
awk '
  /<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->/ { in_block = 1; saw_own_h2 = 0; next }
  in_block && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { saw_own_h2 = 1; print; next }
  in_block && saw_own_h2 && /^## / { exit }
  in_block { print }
' CLAUDE.md > /tmp/0014-replace-extracted.$$

# Trim trailing blank line (the apply emits one for visual separation;
# the spec source does not).
sed -e '$ { /^$/d; }' /tmp/0014-replace-extracted.$$ > /tmp/0014-replace-trimmed.$$

diff -u "$SPEC_BLOCK" /tmp/0014-replace-trimmed.$$ \
  || { echo "REPLACE: §11 block NOT byte-identical to spec source"; rm -f /tmp/0014-replace-*.$$; exit 1; }
rm -f /tmp/0014-replace-extracted.$$ /tmp/0014-replace-trimmed.$$

echo "REPLACE: byte-identical to spec; trailing section preserved"

# ─── INSERT path ──────────────────────────────────────────────────────
# Reset to a fresh-apply state (no §11 anchor) and exercise the insert
# branch.
cat > CLAUDE.md <<'EOF_FRESH'
# Fresh-apply test project

Short preamble paragraph.

## Workflow

Trailing section.
EOF_FRESH

awk -v prov="$PROVENANCE" -v block_file="$SPEC_BLOCK" '
  BEGIN { inserted = 0 }
  !inserted && /^## / {
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
' CLAUDE.md > CLAUDE.md.0014.tmp && mv CLAUDE.md.0014.tmp CLAUDE.md

# Assert provenance present + trailing section preserved.
grep -q '<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->' CLAUDE.md \
  || { echo "INSERT: provenance missing after apply"; exit 1; }
grep -q '^## Workflow$' CLAUDE.md \
  || { echo "INSERT: trailing ## Workflow section was deleted"; exit 1; }

# Extract and diff (same parser as above).
awk '
  /<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->/ { in_block = 1; saw_own_h2 = 0; next }
  in_block && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { saw_own_h2 = 1; print; next }
  in_block && saw_own_h2 && /^## / { exit }
  in_block { print }
' CLAUDE.md > /tmp/0014-insert-extracted.$$
sed -e '$ { /^$/d; }' /tmp/0014-insert-extracted.$$ > /tmp/0014-insert-trimmed.$$

diff -u "$SPEC_BLOCK" /tmp/0014-insert-trimmed.$$ \
  || { echo "INSERT: §11 block NOT byte-identical to spec source"; rm -f /tmp/0014-insert-*.$$; exit 1; }
rm -f /tmp/0014-insert-extracted.$$ /tmp/0014-insert-trimmed.$$

echo "INSERT: byte-identical to spec; trailing section preserved"
echo "fixture 07 — both insert and replace paths produce byte-identical §11 blocks"
