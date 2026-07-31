#!/usr/bin/env bash
# resolve-core-artifact-version: 1.0.0
#
# resolve-core-artifact.sh — produce a VERIFIED local copy of a core artifact
# named by a pin, without the calling repo vendoring that artifact's bytes.
#
# WHY THIS EXISTS
#
# Every host (claude / codex / opencode / pi) carried byte-copies of the change
# gate, the reviewer wrapper, and both conformance harnesses, purely so its
# `install.sh` had something to publish into the shared ~/.agenticapps/bin/.
# The runtime never reads those copies — the project-level hook resolves
# ~/.agenticapps/bin first and only falls back to a repo-local path — so the
# copies existed to feed the installer and for nothing else.
#
# The cost was a re-vendor PR in four repos for every core release. On
# 2026-07-28 the gate shipped 1.2.2 -> 1.3.0 -> 1.3.1 -> 1.4.0 in a single day:
# twelve mechanical PRs, each one a diff nobody reads, each one a chance to
# forget a file and have a drift check catch it later. The drift checks existed
# precisely because the copies drift.
#
# A pin replaces the copies. The host records WHICH core revision it trusts and
# WHAT each file should hash to; this script turns that into bytes on disk.
#
# TRUST MODEL
#
# The pin is the trust anchor, not the transport. Bytes are accepted only if
# they hash to the sha256 recorded in the manifest, so a hostile or broken
# network cannot substitute content — it can only fail the resolve. This is the
# same guarantee vendoring gave (you reviewed the bytes once), expressed as a
# hash instead of a copy.
#
# Fails CLOSED. A missing manifest entry, an unreachable source, or a hash
# mismatch is a non-zero exit and no output. An installer that cannot resolve
# must not silently publish nothing, and must never publish unverified bytes.
#
# USAGE
#   resolve-core-artifact.sh <manifest> <logical-path>
#
#     <manifest>      path to a core-vendor.manifest
#     <logical-path>  a `file=` key in that manifest, e.g.
#                     `bin/openspec-change-gate.sh`
#
#   Prints the path of a verified temp copy on stdout. The caller owns it.
#
# ENV
#   CORE_CHECKOUT   explicit path to a core working copy; tried first.
#   CORE_OFFLINE=1  never reach the network; fail if no local source resolves.
#
# EXIT
#   0  resolved and verified; path on stdout
#   2  usage / manifest error
#   3  no source could supply the file
#   4  HASH MISMATCH — bytes found but not the pinned ones

set -uo pipefail

die()      { printf 'resolve-core-artifact: %s\n' "$*" >&2; exit 2; }
die_src()  { printf 'resolve-core-artifact: %s\n' "$*" >&2; exit 3; }
die_hash() { printf 'resolve-core-artifact: %s\n' "$*" >&2; exit 4; }

MANIFEST="${1:-}"; LOGICAL="${2:-}"
[ -n "$MANIFEST" ] || die "usage: resolve-core-artifact.sh <manifest> <logical-path>"
[ -n "$LOGICAL" ]  || die "usage: resolve-core-artifact.sh <manifest> <logical-path>"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

# --- read the pin ------------------------------------------------------------
# Anchored reads. A manifest is a trust anchor; a loose grep that matched a
# commented-out or prose line would pin the installer to whatever a comment
# happened to say.
manifest_value() { # $1=key
  awk -v k="$1" '$0 ~ "^"k"=" { sub("^"k"=", ""); gsub(/[[:space:]]+$/, ""); print; exit }' "$MANIFEST"
}
CORE_REPO="$(manifest_value core_repo)"
CORE_COMMIT="$(manifest_value core_commit)"
[ -n "$CORE_REPO" ]   || die "manifest has no core_repo"
[ -n "$CORE_COMMIT" ] || die "manifest has no core_commit"
case "$CORE_COMMIT" in
  *[!0-9a-f]* | "") die "core_commit is not a hex sha: $CORE_COMMIT" ;;
esac
[ "${#CORE_COMMIT}" -ge 40 ] || die "core_commit must be a full 40-char sha (got ${#CORE_COMMIT})"

WANT_SHA="$(awk -v f="$LOGICAL" '
  $0 ~ "^file="f"[[:space:]]" {
    for (i = 1; i <= NF; i++) if ($i ~ /^sha256=/) { sub(/^sha256=/, "", $i); print $i; exit }
  }' "$MANIFEST")"
[ -n "$WANT_SHA" ] || die "manifest has no sha256 for '$LOGICAL' — every resolved file must be pinned"

sha_of() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else die "no sha256sum/shasum on PATH — cannot verify, refusing to resolve"; fi
}

# The logical path in the manifest is the HOST's layout (bin/…, tools/…); core
# stores the same artifact under reference-implementations/. Map it here so the
# manifest stays readable to the host that owns it.
core_path_for() {
  case "$1" in
    bin/openspec-change-gate.sh) echo reference-implementations/openspec-change-gate/openspec-change-gate.sh ;;
    bin/reviewer-cli.sh)         echo reference-implementations/reviewer-cli/reviewer-cli.sh ;;
    bin/run-plan-review.sh)      echo reference-implementations/run-plan-review/run-plan-review.sh ;;
    bin/install-shared-artifact.sh) echo reference-implementations/shared-install/install-shared-artifact.sh ;;
    bin/resolve-core-artifact.sh)   echo reference-implementations/shared-install/resolve-core-artifact.sh ;;
    *) echo "$1" ;;   # tools/* and anything else share core's layout
  esac
}
CORE_PATH="$(core_path_for "$LOGICAL")"

OUT="$(mktemp "${TMPDIR:-/tmp}/core-artifact.XXXXXX")" || die "mktemp failed"
cleanup_fail() { rm -f "$OUT"; }

# --- source 1: an explicit or sibling checkout, AT THE PINNED COMMIT ---------
# `git show <sha>:<path>` — not a working-tree read. A sibling checkout may sit
# on any branch with uncommitted edits; reading its worktree would resolve
# whatever the developer happens to have open, which is the opposite of a pin.
try_checkout() {
  local repo="$1"
  [ -d "$repo/.git" ] || return 1
  git -C "$repo" cat-file -e "${CORE_COMMIT}^{commit}" 2>/dev/null || return 1
  git -C "$repo" show "${CORE_COMMIT}:${CORE_PATH}" > "$OUT" 2>/dev/null || return 1
  [ -s "$OUT" ] || return 1
  return 0
}

resolved_from=""
if [ -n "${CORE_CHECKOUT:-}" ] && try_checkout "$CORE_CHECKOUT"; then
  resolved_from="CORE_CHECKOUT=$CORE_CHECKOUT"
else
  for guess in \
    "$(dirname "$(cd "$(dirname "$MANIFEST")" && pwd)")/../agenticapps-workflow-core" \
    "$(cd "$(dirname "$MANIFEST")/../.." 2>/dev/null && pwd)/agenticapps-workflow-core"
  do
    [ -n "$guess" ] || continue
    if try_checkout "$guess"; then resolved_from="sibling checkout $guess"; break; fi
  done
fi

# --- source 2: the network, at the pinned commit -----------------------------
if [ -z "$resolved_from" ]; then
  if [ "${CORE_OFFLINE:-0}" = "1" ]; then
    cleanup_fail
    die_src "no local core checkout has $CORE_COMMIT and CORE_OFFLINE=1 — cannot resolve $LOGICAL"
  fi
  url="https://raw.githubusercontent.com/${CORE_REPO}/${CORE_COMMIT}/${CORE_PATH}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 30 "$url" -o "$OUT" 2>/dev/null && [ -s "$OUT" ] && resolved_from="$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$OUT" --timeout=30 "$url" 2>/dev/null && [ -s "$OUT" ] && resolved_from="$url"
  fi
fi

[ -n "$resolved_from" ] || { cleanup_fail; die_src "could not obtain $LOGICAL at $CORE_COMMIT from any source"; }

# --- verify: the only thing that makes any of the above trustworthy ----------
GOT_SHA="$(sha_of "$OUT")"
if [ "$GOT_SHA" != "$WANT_SHA" ]; then
  cleanup_fail
  die_hash "HASH MISMATCH for $LOGICAL
    source:   $resolved_from
    expected: $WANT_SHA
    actual:   $GOT_SHA
  Refusing to install unverified bytes. Either the manifest is stale (re-pin it)
  or the source is not what the pin claims."
fi

printf '%s\n' "$OUT"
