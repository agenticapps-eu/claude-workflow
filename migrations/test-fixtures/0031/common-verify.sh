#!/bin/sh
# Sourced by each 0031 fixture verify.sh. Provides the migration's own
# Pre-flight and Step 1 blocks, read out of the migration document rather
# than copied.
#
# Requires: REPO_ROOT (exported by run-tests.sh).
# Provides: preflight()      — runs the Pre-flight block in the current directory.
#           apply_step1()    — runs Step 1's Apply block in the current directory.
#           rollback_step1() — runs Step 1's Rollback block.
#           check_step1_idempotent() — runs Step 1's Idempotency check.

MIGRATION_0031="$REPO_ROOT/migrations/0031-reindex-skip-agents-md.md"

[ -f "$MIGRATION_0031" ] || {
  echo "PRE: migration doc not found at $MIGRATION_0031"
  exit 1
}

# Pulls the fenced bash block under "## Pre-flight", stopping at that block's
# own closing fence. Same want/fence discipline as 0030's harness.
extract_0031_preflight() {
  awk '
    /^## Pre-flight/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0031"
}

PREFLIGHT="$(extract_0031_preflight)"
[ -n "$PREFLIGHT" ] || {
  echo "PRE: could not extract Pre-flight block from $MIGRATION_0031"
  exit 1
}

# Shape assertion: the extracted block must be identifiably the Pre-flight
# block — anchor on the scaffolder path and the engine file it checks for.
# An extractor that silently latches onto the wrong fence is the exact
# failure mode this pattern exists to prevent.
case "$PREFLIGHT" in
  *'SCAFFOLDER=~/.claude/skills/agenticapps-workflow'*'gitnexus-reindex.cjs'*) ;;
  *)
    echo "PRE: extracted block is not the Pre-flight block — it carries no"
    echo "     SCAFFOLDER= assignment against gitnexus-reindex.cjs. The"
    echo "     migration's Pre-flight shape changed; fix the extractor"
    echo "     rather than trusting this block. Extracted:"
    printf '%s\n' "$PREFLIGHT" | sed 's/^/       /'
    exit 1
    ;;
esac

# NOTE ON `( ... )` SUBSHELL WRAPPING
#
# Each of the four functions below runs its eval'd block in a SUBSHELL, NOT a
# brace group — the same discipline 0030's harness documents at length and
# for the same reason: this migration's Pre-flight and Step 1 blocks use
# bare `exit N` on every refusal path, and Step 1's Rollback is designed to
# be an honest no-op that must survive being called directly (see
# 08-rollback-noop/verify.sh). A brace group would leak those `exit`s (and
# any `set -eu`) into the SOURCING fixture, silently killing it and
# producing a vacuous PASS. The subshell contains both while still returning
# the block's exit status and still writing files into the fixture's cwd.
#
# Do not "simplify" these back to brace groups.
preflight() ( eval "$PREFLIGHT"; )

# Pulls the fenced block following "**Idempotency check:**" within "### Step 1".
extract_0031_step1_idempotency() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Idempotency check:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0031"
}

STEP1_IDEMPOTENCY="$(extract_0031_step1_idempotency)"
[ -n "$STEP1_IDEMPOTENCY" ] || {
  echo "PRE: could not extract Step 1 Idempotency check block from $MIGRATION_0031"
  exit 1
}

# Shape assertion: the idempotency check compares the project's engine
# against the vendored one with `cmp`. Anything else means the extractor
# latched onto the wrong fence.
case "$STEP1_IDEMPOTENCY" in
  *'cmp -s'*'gitnexus-reindex.cjs'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's idempotency check — it carries"
    echo "     no 'cmp -s' comparison against gitnexus-reindex.cjs. The"
    echo "     migration's Step 1 shape changed; fix the extractor rather"
    echo "     than trusting this block. Extracted:"
    printf '%s\n' "$STEP1_IDEMPOTENCY" | sed 's/^/       /'
    exit 1
    ;;
esac

# Returns the idempotency check's own exit status (0 = already applied / skip).
check_step1_idempotent() ( eval "$STEP1_IDEMPOTENCY"; )

# Pulls the FIRST fenced block following "**Apply:**" within "### Step 1".
# `want` is cleared as soon as a fence opens, so a change from ```bash to ```sh
# cannot make the scan skip past and latch onto Step 1's Rollback fence.
extract_0031_step1_apply() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Apply:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0031"
}

STEP1_APPLY="$(extract_0031_step1_apply)"
[ -n "$STEP1_APPLY" ] || {
  echo "PRE: could not extract Step 1 Apply block from $MIGRATION_0031"
  exit 1
}

# Non-empty is not the same as correct. Assert the block carries the copy +
# chmod pair. Fail loudly rather than eval it.
case "$STEP1_APPLY" in
  *'cp "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs"'*'chmod +x .claude/hooks/gitnexus-reindex.cjs'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's apply — it carries no"
    echo "     cp+chmod pair against gitnexus-reindex.cjs. The migration's"
    echo "     Step 1 shape changed; fix the extractor rather than trusting"
    echo "     this block. Extracted:"
    printf '%s\n' "$STEP1_APPLY" | sed 's/^/       /'
    exit 1
    ;;
esac

apply_step1() ( eval "$STEP1_APPLY"; )

# Pulls the FIRST fenced block following "**Rollback:**" within "### Step 1".
# Same want/fence discipline: `want` clears the instant any fence opens, so it
# cannot skip past Step 1's Rollback and latch onto Step 2's Apply/Rollback.
extract_0031_step1_rollback() {
  awk '
    /^### Step 1/ { in1=1; next }
    /^### Step 2/ { in1=0 }
    in1 && /^\*\*Rollback:\*\*/ { want=1; next }
    want && /^```/ { inb=1; want=0; next }
    inb && /^```$/ { exit }
    inb { print }
  ' "$MIGRATION_0031"
}

STEP1_ROLLBACK="$(extract_0031_step1_rollback)"
[ -n "$STEP1_ROLLBACK" ] || {
  echo "PRE: could not extract Step 1 Rollback block from $MIGRATION_0031"
  exit 1
}

# Shape assertion: Step 1's rollback is the honest reporting no-op — it
# reports "no inverse" rather than restoring anything. Anything else means
# the extractor latched onto the wrong fence.
case "$STEP1_ROLLBACK" in
  *'Step 1 has no inverse'*) ;;
  *)
    echo "PRE: extracted block is not Step 1's rollback — it carries no"
    echo "     'Step 1 has no inverse' report. The migration's Step 1 shape"
    echo "     changed; fix the extractor rather than trusting this block."
    echo "     Extracted:"
    printf '%s\n' "$STEP1_ROLLBACK" | sed 's/^/       /'
    exit 1
    ;;
esac

rollback_step1() ( eval "$STEP1_ROLLBACK"; )
