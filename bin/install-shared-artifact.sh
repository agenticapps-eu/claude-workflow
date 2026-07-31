#!/usr/bin/env bash
# shared-install-version: 1.0.1
#
#   1.0.1 — `--allow-downgrade` no longer glob-expands. Unquoted, the value was
#           pathname-expanded as well as split, so `'*'` could authorise a
#           downgrade from a directory that happened to contain a matching
#           filename — against the "there is no wildcard" promise this flag is
#           documented with.
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
shift 3 2>/dev/null || true
LOCK_TIMEOUT="${SHARED_INSTALL_LOCK_TIMEOUT:-30}"
TEST_DELAY="${SHARED_INSTALL_TEST_DELAY:-0}"
INSTALL_LOG="${AGENTICAPPS_INSTALL_LOG:-${HOME:-/tmp}/.agenticapps/install.log}"

# ── opt-in downgrade ─────────────────────────────────────────────────────────
# The arbiter above refuses to overwrite a newer copy, which is what stops an
# older host installer silently reverting a fix for every agent on the machine.
# It also makes every rollback row in every migration plan unexecutable: there
# is no supported way to put 1.0.0 back after 1.1.0 ships.
#
# The escape is deliberately narrow:
#   --allow-downgrade <artifact> --reason <text>
# Both are mandatory together. It authorises exactly the one named artifact for
# exactly this invocation. Repeating the flag authorises several, each named.
# There is no wildcard and NO ENVIRONMENT VARIABLE — an env var would make the
# weakening inheritable by every child process, which is the property this
# exists to deny.
#
# The flag IS the authorisation, and that is stated rather than dressed up:
# anyone who can run this installer can already write the shared directory
# directly. What the flag buys is that a downgrade is deliberate and recorded,
# not that it is privileged.
ALLOW_DOWNGRADE=""
REASON=""
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-downgrade)
      [ $# -ge 2 ] || { printf 'install-shared-artifact: --allow-downgrade requires an artifact name\n' >&2; exit 1; }
      ALLOW_DOWNGRADE="$ALLOW_DOWNGRADE $2"; shift 2 ;;
    --allow-downgrade=*) ALLOW_DOWNGRADE="$ALLOW_DOWNGRADE ${1#*=}"; shift ;;
    --reason)
      [ $# -ge 2 ] || { printf 'install-shared-artifact: --reason requires a value\n' >&2; exit 1; }
      REASON="$2"; shift 2 ;;
    --reason=*) REASON="${1#*=}"; shift ;;
    *) printf 'install-shared-artifact: unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

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
  _dst_name="$(basename "$DST")"
  _authorised=0
  # Unquoted here, the value is GLOB-expanded as well as split, so
  # `--allow-downgrade '*'` run from a directory happening to contain a file
  # named like the artifact authorised the downgrade — directly contradicting
  # the "there is no wildcard" promise above it. Splitting is wanted; globbing
  # is not, so it is disabled for the loop and restored immediately.
  set -f
  for _a in $ALLOW_DOWNGRADE; do [ "$_a" = "$_dst_name" ] && _authorised=1; done
  set +f

  if [ "$_authorised" != "1" ]; then
    if [ -n "$ALLOW_DOWNGRADE" ]; then
      # A typo must not read as a successful authorisation.
      note "keeping $DST at $have — --allow-downgrade named '$(echo $ALLOW_DOWNGRADE | tr -s ' ')', not '$_dst_name'"
    else
      note "keeping $DST at $have (refusing downgrade to $want)"
    fi
    exit 3
  fi

  # Reason is REQUIRED with the flag, and constrained so it cannot forge a
  # second record: a single line, any control character rejected rather than
  # escaped. Rejecting is deliberate — escaping would require every reader to
  # un-escape identically, which is the under-specification this avoids.
  case "$REASON" in
    "") note "--allow-downgrade requires --reason <text>"; exit 1 ;;
  esac
  _trimmed="$(printf '%s' "$REASON" | tr -d '[:space:]')"
  [ -n "$_trimmed" ] || { note "--reason must not be empty"; exit 1; }
  if printf '%s' "$REASON" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    note "--reason must be a single line with no control characters"
    exit 1
  fi
  [ "${#REASON}" -le 200 ] || { note "--reason must be at most 200 characters"; exit 1; }

  # THE LOG WRITE GATES THE REPLACEMENT. Writing the artifact first and the log
  # second loses the audit record in exactly the case it exists for — a full
  # disk, a read-only home, a permissions error — and leaves a silently
  # downgraded shared binary behind. A logged downgrade that then fails to
  # install is a harmless over-record; the reverse is not.
  mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || {
    note "cannot create the install log directory: $(dirname "$INSTALL_LOG")"; exit 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" downgrade "$_dst_name" "$have" "$want" \
    "$(id -un 2>/dev/null || printf unknown)" "$REASON" >> "$INSTALL_LOG" || {
      note "cannot write the audit record to $INSTALL_LOG — refusing the downgrade"; exit 1; }

  note "downgrading $DST from $have to $want (authorised; reason: $REASON)"
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
