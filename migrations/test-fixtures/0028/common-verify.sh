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

# Pulls the FIRST fenced block following "**Apply:**" within "### Step 1".
#
# `want` is cleared as soon as a fence opens. Without that it latches: if Step
# 1's Apply fence ever stops being exactly ```bash (someone writes ```sh), the
# scan skips past it and locks onto the NEXT ```bash fence in Step 1 — which is
# the Rollback block. apply_step1 would then silently become `sed -i … /d`, a
# destructive delete, and the non-empty guard below would happily pass it.
# Matching any fence, once, removes the failure mode instead of narrowing it.
extract_0028_step1_apply() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Apply:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0028"
}

STEP1_APPLY="$(extract_0028_step1_apply)"
[ -n "$STEP1_APPLY" ] || {
  echo "PRE: could not extract Step 1 Apply block from $MIGRATION_0028"
  exit 1
}

# Non-empty is not the same as correct. Assert the block actually looks like
# Step 1's apply — it must append to .prettierignore. Anything else (the
# rollback's sed, a pre-condition test) means the document's shape moved and
# the extractor followed it somewhere wrong; fail loudly rather than eval it.
case "$STEP1_APPLY" in
  *'>> .prettierignore'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's apply — it does not append to"
    echo "     .prettierignore. The migration's Step 1 shape changed; fix the"
    echo "     extractor rather than trusting this block. Extracted:"
    printf '%s\n' "$STEP1_APPLY" | sed 's/^/       /'
    exit 1
    ;;
esac

apply_step1() { eval "$STEP1_APPLY"; }
