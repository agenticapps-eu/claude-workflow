#!/bin/sh
# Verify the blank-line-drift guard REFUSES a block that carries a lawful
# host-specific addition (spec §11's MAY clause), rather than wholesale
# replacing it. This is the data-loss regression test: if the guard is
# removed or weakened, this fixture must fail RED, because without it 0030
# treats the added bullet as staleness and silently deletes it.
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

ADDED_BULLET='- host-runtime-specific: never swallow a stack trace from the sandboxed shell without echoing it.'

grep -qF -e "$ADDED_BULLET" CLAUDE.md || {
  echo "PRE: fixture must start with the lawful host-specific bullet present"
  exit 1
}

preflight || {
  echo "FAIL: pre-flight refused a well-formed block carrying a lawful"
  echo "      host-specific addition"
  exit 1
}

check_step1_idempotent && {
  echo "FAIL: idempotency check reported IN SYNC for a block carrying an"
  echo "      addition not present in the canonical mirror"
  exit 1
}

before="$(cat CLAUDE.md)"

out="$(apply_step1 2>&1)" && {
  echo "DATA LOSS: apply_step1 SUCCEEDED against a block carrying a lawful"
  echo "           host-specific addition — this is the exact regression"
  echo "           this fixture exists to catch. The added bullet was"
  echo "           wholesale-replaced by the canonical mirror bytes. Output:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

# Assert refusal came from THIS guard, not some unrelated abort — anchor on
# the guard's distinguishing phrase, not merely a non-zero exit.
printf '%s' "$out" | grep -q 'non-blank content' || {
  echo "FAIL: apply_step1 refused, but not via the blank-line-drift guard —"
  echo "      got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}
printf '%s' "$out" | grep -q 'LAWFUL host-specific addition' || {
  echo "FAIL: apply_step1's refusal message did not mention the lawful"
  echo "      host-specific addition (spec §11's MAY clause) — got:"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}

# CLAUDE.md must be byte-untouched.
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "DATA LOSS: apply_step1 refused but still mutated CLAUDE.md."
  exit 1
}

# The lawful addition must survive, byte-identical.
grep -qF -e "$ADDED_BULLET" CLAUDE.md || {
  echo "DATA LOSS: the lawful host-specific addition did not survive."
  exit 1
}

echo "OK: 0030 refused a block carrying a lawful host-specific addition"
echo "    (spec §11 MAY clause); CLAUDE.md byte-untouched; the addition"
echo "    survives"
exit 0
