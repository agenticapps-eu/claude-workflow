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

# Pulls the fenced block following "**Idempotency check:**" within "### Step 1".
# Same want/fence discipline as extract_0029_step1_apply below.
extract_0029_step1_idempotency() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Idempotency check:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0029"
}

STEP1_IDEMPOTENCY="$(extract_0029_step1_idempotency)"
[ -n "$STEP1_IDEMPOTENCY" ] || {
  echo "PRE: could not extract Step 1 Idempotency check block from $MIGRATION_0029"
  exit 1
}

# Shape assertion: the idempotency check greps for the §11 provenance comment.
# Anything else means the extractor latched onto the wrong fence.
case "$STEP1_IDEMPOTENCY" in
  *'spec-source: agenticapps-workflow-core'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's idempotency check — it carries"
    echo "     no spec-source provenance grep. The migration's Step 1 shape"
    echo "     changed; fix the extractor rather than trusting this block."
    echo "     Extracted:"
    printf '%s\n' "$STEP1_IDEMPOTENCY" | sed 's/^/       /'
    exit 1
    ;;
esac

# Returns the idempotency check's own exit status (0 = already applied).
check_step1_idempotent() { eval "$STEP1_IDEMPOTENCY"; }

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

# Pulls the FIRST fenced block following "**Rollback:**" within "### Step 1".
# Same want/fence discipline: `want` clears the instant any fence opens, so it
# cannot skip past Step 1's Rollback and latch onto Step 2's Apply/Rollback.
extract_0029_step1_rollback() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Rollback:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0029"
}

STEP1_ROLLBACK="$(extract_0029_step1_rollback)"
[ -n "$STEP1_ROLLBACK" ] || {
  echo "PRE: could not extract Step 1 Rollback block from $MIGRATION_0029"
  exit 1
}

# Shape assertion: Step 1's rollback greps for the §11 provenance comment
# before removing it. Anything else means the extractor latched onto the
# wrong fence — fail loudly rather than eval it silently.
case "$STEP1_ROLLBACK" in
  *'spec-source: agenticapps-workflow-core'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's rollback — it carries no"
    echo "     spec-source provenance grep. The migration's Step 1 shape"
    echo "     changed; fix the extractor rather than trusting this block."
    echo "     Extracted:"
    printf '%s\n' "$STEP1_ROLLBACK" | sed 's/^/       /'
    exit 1
    ;;
esac

rollback_step1() { eval "$STEP1_ROLLBACK"; }
