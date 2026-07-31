#!/usr/bin/env bash
# shared-install-version: 1.0.0
#
# install-shared-artifact.sh — serialised, monotonic install of a versioned
# artifact into the shared ~/.agenticapps/bin/ path.
#
# WHY THIS EXISTS
#
# Every host installer (claude / codex / opencode / pi) writes the same shared
# files. Core told them to arbitrate on a version marker and refuse to
# downgrade — and every host implemented that correctly. It is still not enough,
# because the arbitration is a read-compare-write with nothing held across it:
#
#     host A (older, 1.2.1)              host B (newer, 1.2.2)
#     read  have=1.2.0  -> upgrade
#                                        read  have=1.2.0  -> upgrade
#                                        write 1.2.2
#     write 1.2.1                                  <-- older lands last
#
# Both decisions were correct against the state each process observed. The later
# writer wins regardless of version, which is exactly what the marker exists to
# prevent. PER-HOST ARBITRATION DOES NOT COMPOSE INTO MACHINE-WIDE MONOTONICITY.
# Closing it requires mutual exclusion around the whole read-compare-write, which
# no single host can provide for the others — so it belongs here, called by all
# of them, rather than reinvented four times.
#
# Reported as pi-agentic-apps-workflow#13; same shape as core#41 one level down
# (there the write was unguarded, here the decision is).
#
# USAGE
#   install-shared-artifact.sh <src> <dst> <marker-key>
#
#     <src>         file to install
#     <dst>         destination path (typically ~/.agenticapps/bin/<name>)
#     <marker-key>  version comment key, e.g. `gate-version` or
#                   `reviewer-cli-version`. Read as `# <marker-key>: X.Y.Z`
#                   from the first 40 lines of each file.
#
# EXIT
#   0  installed — dst now holds <src>'s version
#   3  skipped — dst already holds a STRICTLY NEWER version (this is success:
#      the postcondition "dst is at least as new as src" holds either way)
#   1  error — missing src, unreadable marker, lock timeout
#
# ENV
#   SHARED_INSTALL_LOCK_TIMEOUT  seconds to wait for the lock (default 30)
#   SHARED_INSTALL_TEST_DELAY    TEST ONLY. Seconds to sleep between the compare
#                                and the write. Exists so the conformance harness
#                                can force the interleave deterministically
#                                instead of hoping to hit it; a correct
#                                implementation is unaffected because the lock is
#                                held across the delay. Defaults to 0 and must
#                                never be set in production.
#
# AN UNMARKED FILE IS 0.0.0. That is deliberate: the pre-marker copies in the
# fleet carried no version, and treating them as "unknown, leave alone" would
# have frozen every machine that had one.

set -u

SRC="${1:-}"
DST="${2:-}"
KEY="${3:-}"
LOCK_TIMEOUT="${SHARED_INSTALL_LOCK_TIMEOUT:-30}"
TEST_DELAY="${SHARED_INSTALL_TEST_DELAY:-0}"

die() { printf 'install-shared-artifact: %s\n' "$*" >&2; exit 1; }
note() { printf 'install-shared-artifact: %s\n' "$*" >&2; }

[ -n "$SRC" ] && [ -n "$DST" ] && [ -n "$KEY" ] || \
  die "usage: install-shared-artifact.sh <src> <dst> <marker-key>"
[ -f "$SRC" ] || die "source not found: $SRC"

# ── version helpers ──────────────────────────────────────────────────────────
# Read `# <key>: X.Y.Z` from the head of a file. Absent or unparseable -> 0.0.0.
version_of() {
  local f="$1" v=""
  [ -f "$f" ] && v="$(head -n 40 "$f" 2>/dev/null \
    | grep -m1 -oE "^#[[:space:]]*${KEY}:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  printf '%s' "${v:-0.0.0}"
}

# $1 > $2 ? Numeric per component. Avoids `sort -V`, which is GNU-only in the
# versions that matter here and silently misorders on some BSD builds.
version_gt() {
  local a="$1" b="$2" i av bv
  i=1
  while [ "$i" -le 3 ]; do
    av="$(printf '%s' "$a" | cut -d. -f"$i")"; av="$(printf '%s' "${av:-0}" | tr -cd '0-9')"
    bv="$(printf '%s' "$b" | cut -d. -f"$i")"; bv="$(printf '%s' "${bv:-0}" | tr -cd '0-9')"
    [ -n "$av" ] || av=0
    [ -n "$bv" ] || bv=0
    [ "$av" -gt "$bv" ] && return 0
    [ "$av" -lt "$bv" ] && return 1
    i=$((i + 1))
  done
  return 1   # equal is not greater
}

# ── the lock ─────────────────────────────────────────────────────────────────
# `mkdir` is atomic on POSIX filesystems: exactly one caller creates it. Chosen
# over flock(1), which macOS does not ship. Per-ARTIFACT rather than per-dir, so
# installing the gate does not serialise against installing reviewer-cli.
#
# Caveat worth knowing: mkdir atomicity is not guaranteed over NFS. The shared
# path is a local home directory, so this holds in practice; a host installing
# to network storage needs a different primitive.
LOCKDIR="$DST.lock"
LOCK_HELD=0

release_lock() { [ "$LOCK_HELD" -eq 1 ] && rm -rf "$LOCKDIR"; }
trap release_lock EXIT INT TERM

acquire_lock() {
  local waited=0 lpid
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    # Break a lock whose owner is gone. Without this, one killed installer
    # wedges every future install on the machine — a worse failure than the
    # race, because it is permanent and silent.
    lpid="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
    if [ -n "$lpid" ] && ! kill -0 "$lpid" 2>/dev/null; then
      note "breaking stale lock from dead pid $lpid"
      rm -rf "$LOCKDIR"
      continue
    fi
    waited=$((waited + 1))
    [ "$waited" -ge "$LOCK_TIMEOUT" ] && \
      die "timed out after ${LOCK_TIMEOUT}s waiting for $LOCKDIR"
    sleep 1
  done
  LOCK_HELD=1
  printf '%s' "$$" > "$LOCKDIR/pid" 2>/dev/null || true
}

# ── arbitrate ────────────────────────────────────────────────────────────────
# Destination directory first: the lock lives beside the artifact, so the parent
# has to exist before there is anywhere to take a lock. Kept out of
# acquire_lock() so that function does exactly one thing.
mkdir -p "$(dirname "$DST")" 2>/dev/null || die "cannot create $(dirname "$DST")"

acquire_lock

want="$(version_of "$SRC")"
[ "$want" = "0.0.0" ] && die "source carries no '# $KEY: X.Y.Z' marker: $SRC"
have="$(version_of "$DST")"

if [ -f "$DST" ] && version_gt "$have" "$want"; then
  note "keeping $DST at $have (refusing downgrade to $want)"
  exit 3
fi

# TEST ONLY — see ENV above. Held INSIDE the lock, which is the whole point: a
# correct implementation is unaffected by any delay here.
[ "$TEST_DELAY" != "0" ] && sleep "$TEST_DELAY"

# Write via a temp file in the SAME directory, then rename. rename(2) is atomic
# within a filesystem, so a concurrent reader — an agent whose PreToolUse hook
# fires mid-install — sees either the old file or the new one, never a truncated
# script. The lock gives monotonicity; this gives readers integrity.
tmp="$DST.tmp.$$"
cp "$SRC" "$tmp" || die "copy failed: $SRC -> $tmp"
chmod 0755 "$tmp" || die "chmod failed: $tmp"
if ! mv -f "$tmp" "$DST"; then
  rm -f "$tmp"
  die "atomic rename failed: $tmp -> $DST"
fi

note "installed $DST at $want (was $have)"
exit 0
