#!/bin/sh
# Verify the blank-line-drift guard REFUSES when the block's region
# boundary swallows a SETEXT-style H2 heading ("User Section" underlined
# with `---`) and the user data beneath it, rather than replacing them
# along with a genuine stale block. This neutralises the terminator
# finding: `^## ` only recognizes ATX headings, so without the guard, the
# region scan runs straight through a setext heading and the replacement
# destroys the user's data.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

USER_DATA='This is my important user data that must survive.'

grep -qF "$USER_DATA" CLAUDE.md || {
  echo "PRE: fixture must start with the user data line present"
  exit 1
}
grep -q '^User Section$' CLAUDE.md || {
  echo "PRE: fixture must start with the setext heading text 'User Section' present"
  exit 1
}
grep -q '^---$' CLAUDE.md || {
  echo "PRE: fixture must start with the setext underline '---' present"
  exit 1
}

preflight || {
  echo "FAIL: pre-flight refused a well-formed stale block followed by"
  echo "      unrelated (setext-heading) user content"
  exit 1
}

check_step1_idempotent && {
  echo "FAIL: idempotency check reported IN SYNC for a stale block"
  exit 1
}

before="$(cat CLAUDE.md)"

out="$(apply_step1 2>&1)" && {
  echo "DATA LOSS: apply_step1 SUCCEEDED against a block whose region"
  echo "           swallowed the setext 'User Section' heading and the"
  echo "           user data beneath it — this is the exact regression"
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
  echo "DATA LOSS: the user data beneath the setext heading did not"
  echo "           survive."
  exit 1
}
grep -q '^User Section$' CLAUDE.md || {
  echo "DATA LOSS: the setext heading text 'User Section' did not survive."
  exit 1
}
grep -q '^---$' CLAUDE.md || {
  echo "DATA LOSS: the setext underline '---' did not survive."
  exit 1
}

echo "OK: 0030 refused a block whose region swallowed a setext heading"
echo "    and user data beneath it; CLAUDE.md byte-untouched; the user data"
echo "    survives"
exit 0
