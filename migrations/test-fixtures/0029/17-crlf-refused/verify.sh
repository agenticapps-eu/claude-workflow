#!/bin/sh
# Verify a CRLF CLAUDE.md is refused cleanly by the clean-text gate rather than
# getting a duplicate §11 block inserted (the anchor `/^## /` matches a heading
# prefix even through CR, so without the gate Apply would append a second block).
# Expect exit 3, file byte-identical, and exactly one provenance line afterwards.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

# Dispatch reachability: idempotency must report NOT-applied (nonzero) on this
# CRLF file so the updater runs Apply and reaches the clean-text gate.
set +e; check_step1_idempotent; idem=$?; set -e
[ "$idem" -ne 0 ] || {
  echo "FAIL: idempotency reports a CRLF file as already-applied; Apply would be skipped"
  exit 1
}

orig="$(mktemp)"; trap 'rm -f "$orig"' EXIT; cp CLAUDE.md "$orig"

before_prov="$(grep -ac 'spec-source: agenticapps-workflow-core' CLAUDE.md)"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: expected exit 3 (clean-text refuse) on CRLF file, got $rc: $out"
  exit 1
}
cmp -s "$orig" CLAUDE.md || {
  echo "FAIL: refused but still modified CLAUDE.md (byte comparison)"
  exit 1
}
after_prov="$(grep -ac 'spec-source: agenticapps-workflow-core' CLAUDE.md)"
[ "$after_prov" = "$before_prov" ] || {
  echo "FAIL: provenance count changed ($before_prov -> $after_prov) — a block was inserted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: a CRLF CLAUDE.md is refused (exit 3) with no duplicate block; file untouched"
exit 0
