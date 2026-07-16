#!/bin/sh
# Verify 0030 is a byte-for-byte no-op on an in-sync block, and stays one on
# re-apply. Modelled on 0029's 03-healthy-noop/verify.sh.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

before="$(cat CLAUDE.md)"

check_step1_idempotent || { echo "FAIL: idempotency check failed on an in-sync block"; exit 1; }

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: 0030 churned an in-sync CLAUDE.md. Diff:"
  printf '%s\n' "$before" > CLAUDE.md.before
  diff CLAUDE.md.before CLAUDE.md || true
  exit 1
}

apply_step1
[ "$before" = "$(cat CLAUDE.md)" ] || { echo "FAIL: 0030 not idempotent on re-apply"; exit 1; }

echo "OK: byte-identical no-op on an in-sync CLAUDE.md, idempotently"
exit 0
