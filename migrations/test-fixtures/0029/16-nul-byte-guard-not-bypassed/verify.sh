#!/bin/sh
# Verify a stray NUL byte causes a clean refusal, not a data-losing strip. NUL
# makes grep/awk behave in undefined, locale-dependent ways (guard skipped, or a
# record truncated so the guard validates a canonical prefix while the strip
# deletes the whole line). Step 1's clean-text gate refuses any NUL/CR file
# before the guard or strip runs: exit 3, CLAUDE.md byte-identical, SECRET intact.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

orig="$(mktemp)"; trap 'rm -f "$orig"' EXIT; cp CLAUDE.md "$orig"

set +e
out="$(apply_step1 2>&1)"
rc=$?
set -e

[ "$rc" -eq 3 ] || {
  echo "FAIL: NUL byte not refused by the clean-text gate — expected exit 3, got $rc: $out"
  exit 1
}
# Assert the refusal came from the CLEAN-TEXT GATE specifically, not from the
# guard or the hand-pasted-heading branch. BSD awk's NUL truncation is
# locale-dependent, so on some hosts this shape happens to refuse via the guard
# and on others it silently deletes the suffix; only the byte-level gate refuses
# it uniformly. Binding the gate's message makes this a locale-independent
# mutation test: removing the gate changes which branch refuses (or none does).
printf '%s\n' "$out" | grep -q 'NUL or CR' || {
  echo "FAIL: refusal did not come from the clean-text gate (no 'NUL or CR' in output):"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
}
cmp -s "$orig" CLAUDE.md || {
  echo "FAIL: refused but still modified CLAUDE.md (byte comparison)"
  diff "$orig" CLAUDE.md || true
  exit 1
}
grep -aq 'SECRET USER SUFFIX' CLAUDE.md || {
  echo "FAIL: operator SECRET suffix (hidden after a NUL in the heading) was deleted"
  exit 1
}
grep -aq 'KEEP TAIL' CLAUDE.md || {
  echo "FAIL: the file tail was deleted"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

echo "OK: a stray NUL byte is refused by the clean-text gate (exit 3); file untouched"
exit 0
