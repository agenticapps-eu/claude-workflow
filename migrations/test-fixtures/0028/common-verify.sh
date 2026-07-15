#!/bin/sh
# Sourced by each 0028 fixture verify.sh. Provides the migration's own Step 1
# Apply block, read out of the migration document rather than copied.
#
# Why: a fixture that inlines its own copy of the migration's shell tests the
# copy, not the migration. The two drift silently — a predicate fix can land in
# the document while every fixture goes on exercising the old logic and passing.
# Extracting the block means a change to Step 1 is a change to what these
# fixtures run.
#
# Requires: REPO_ROOT (exported by run-tests.sh).
# Provides: apply_step1() — runs Step 1's Apply block in the current directory.

MIGRATION_0028="$REPO_ROOT/migrations/0028-register-prettierignore.md"

[ -f "$MIGRATION_0028" ] || {
  echo "PRE: migration doc not found at $MIGRATION_0028"
  exit 1
}

# Pulls the first fenced bash block following "**Apply:**" within "### Step 1".
extract_0028_step1_apply() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Apply:\*\*/ { want=1; next }
    want && /^```bash$/ { inb=1; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0028"
}

STEP1_APPLY="$(extract_0028_step1_apply)"
[ -n "$STEP1_APPLY" ] || {
  echo "PRE: could not extract Step 1 Apply block from $MIGRATION_0028"
  exit 1
}

apply_step1() { eval "$STEP1_APPLY"; }
