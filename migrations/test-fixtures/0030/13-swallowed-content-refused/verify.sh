#!/bin/sh
# Verify the blank-line-drift guard REFUSES when the block's region
# boundary swallows an indented `  ## User Section` heading and the user
# data beneath it, rather than replacing them along with a genuine stale
# block. This neutralises the terminator finding: `^## ` does not recognize
# CommonMark's indented-heading form, so without the guard, the region scan
# runs straight through it and the replacement destroys the user's data.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

USER_DATA='This is my important user data that must survive.'

grep -qF "$USER_DATA" CLAUDE.md || {
  echo "PRE: fixture must start with the user data line present"
  exit 1
}
grep -q '^  ## User Section$' CLAUDE.md || {
  echo "PRE: fixture must start with the indented '  ## User Section' heading"
  exit 1
}

preflight || {
  echo "FAIL: pre-flight refused a well-formed stale block followed by"
  echo "      unrelated (indented-heading) user content"
  exit 1
}

check_step1_idempotent && {
  echo "FAIL: idempotency check reported IN SYNC for a stale block"
  exit 1
}

before="$(cat CLAUDE.md)"

out="$(apply_step1 2>&1)" && {
  echo "DATA LOSS: apply_step1 SUCCEEDED against a block whose region"
  echo "           swallowed the indented '  ## User Section' heading and"
  echo "           the user data beneath it — this is the exact regression"
  echo "           this fixture exists to catch. Output:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

# Assert refusal came from THIS guard, not some unrelated abort.
printf '%s' "$out" | grep -q 'non-blank content' || {
  echo "FAIL: apply_step1 refused, but not via the blank-line-drift guard —"
  echo "      got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

# CLAUDE.md must be byte-untouched.
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "DATA LOSS: apply_step1 refused but still mutated CLAUDE.md."
  exit 1
}

# The swallowed user data must survive, byte-identical.
grep -qF "$USER_DATA" CLAUDE.md || {
  echo "DATA LOSS: the user data beneath the indented heading did not"
  echo "           survive."
  exit 1
}
grep -q '^  ## User Section$' CLAUDE.md || {
  echo "DATA LOSS: the indented '  ## User Section' heading did not survive."
  exit 1
}

echo "OK: 0030 refused a block whose region swallowed an indented heading"
echo "    and user data beneath it; CLAUDE.md byte-untouched; the user data"
echo "    survives"
exit 0
