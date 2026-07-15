#!/bin/sh
# Verify 0029 refuses a corrupt/truncated vendored §11 mirror rather than
# silently committing a maimed CLAUDE.md (I-A, C-1). Binds every guard that
# closes C-1, and is honest about which layer catches which corruption shape
# (I-B) rather than asserting a uniform refusal that isn't actually true:
#
#   Pre-flight (the fix): `test -s "$SPEC_BLOCK"` catches a zero-byte mirror;
#   the tail-sentinel grep for the block's final section catches a truncated
#   one. Both corruption modes must make Pre-flight refuse (exit 3), and a
#   healthy mirror must make it pass (exit 0) — asserted in both directions.
#
#   Step 1 Apply's pre-`mv` shape assertion (existing defence-in-depth,
#   unchanged by this fix): it only greps the INSERT pass's output for the
#   §11 heading. A zero-byte mirror produces no heading in the insert, so
#   Apply also refuses there — that's the "last line of defense" the
#   migration document already describes. A truncated-but-headed mirror
#   (head -5: keeps line 1's heading, loses the tail) still produces a
#   heading in the insert, so Apply's own guard is blind to it by
#   construction — closing that gap is Pre-flight's job, not Apply's, per
#   finding I-A ("guard the SOURCE in pre-flight"). Fixtures call apply_step1
#   directly, bypassing Pre-flight (see common-verify.sh's header note), so
#   this is the one shape where Apply is exercised in isolation and is
#   expected to still succeed — Pre-flight is what stops it from ever
#   running in real operation.
#
# The good mirror is restored between modes so mode (b) does not depend on
# mode (a) having run first, and the mirror is left healthy for any fixture
# that runs after this one in the same sandboxed $HOME.
set -eu

. "$REPO_ROOT/migrations/test-fixtures/0029/common-verify.sh"

BLOCK="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
GOOD_BLOCK_BACKUP="$(mktemp -t 0029-good-block-XXXXXX)"
cp "$BLOCK" "$GOOD_BLOCK_BACKUP"
trap 'rm -f "$GOOD_BLOCK_BACKUP"' EXIT

restore_good_mirror() {
  cp "$GOOD_BLOCK_BACKUP" "$BLOCK"
}

before="$(cat CLAUDE.md)"

# Direction 1: Pre-flight passes on the healthy mirror common-setup.sh vendored.
set +e
pf_out="$(preflight 2>&1)"
pf_rc=$?
set -e
[ "$pf_rc" -eq 0 ] || {
  echo "FAIL: pre-flight refused a HEALTHY mirror (exit $pf_rc): $pf_out"
  exit 1
}

# Mode (a): zero-byte mirror. Both guard layers must refuse.
: > "$BLOCK"

set +e
pf_out="$(preflight 2>&1)"
pf_rc=$?
set -e
[ "$pf_rc" -eq 3 ] || {
  echo "FAIL: [zero-byte] pre-flight did not refuse (exit $pf_rc): $pf_out"
  exit 1
}

set +e
ap_out="$(apply_step1 2>&1)"
ap_rc=$?
set -e
[ "$ap_rc" -eq 3 ] || {
  echo "FAIL: [zero-byte] Step 1 Apply did not refuse (exit $ap_rc): $ap_out"
  exit 1
}
[ "$before" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: [zero-byte] Step 1 Apply refused but still modified CLAUDE.md"
  exit 1
}
if ls CLAUDE.md.0029.* >/dev/null 2>&1; then
  echo "FAIL: [zero-byte] Step 1 Apply left a stray CLAUDE.md.0029.* temp file behind"
  exit 1
fi

restore_good_mirror

# Mode (b): truncated mirror — keeps the line-1 heading, loses the tail.
# Only Pre-flight is asserted to refuse here (see header note): Apply's
# pre-mv shape assertion greps the insert for the heading alone, which a
# head-preserving truncation still supplies, so Apply itself is not, and is
# not expected to be, a backstop for this shape.
head -5 "$GOOD_BLOCK_BACKUP" > "$BLOCK"

set +e
pf_out="$(preflight 2>&1)"
pf_rc=$?
set -e
[ "$pf_rc" -eq 3 ] || {
  echo "FAIL: [truncated] pre-flight did not refuse (exit $pf_rc): $pf_out"
  exit 1
}

restore_good_mirror

echo "OK: 0029 pre-flight refuses a zero-byte or truncated vendored §11 mirror" \
     "(and passes a healthy one); Step 1 Apply's own shape assertion additionally" \
     "refuses the zero-byte case, CLAUDE.md untouched, no stray temps"
exit 0
