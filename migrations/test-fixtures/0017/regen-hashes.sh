#!/usr/bin/env bash
# Regenerate migration 0017's known-wrapper-hashes.json.
#
# The recorded sha256 per stack is the hash of the CANONICAL (structurally
# masked) form of that stack's OLD (pre-1.16.0) template wrapper, read from the
# vendored bytes under old-wrappers/ (add-observability v0.4.x, pinned from
# commit 34ee72e). The masking program is IMPORTED verbatim from the apply
# engine (canonicalize_awk) so the baseline and the runtime check cannot drift.
#
# Usage:  bash migrations/test-fixtures/0017/regen-hashes.sh [--check]
#   (no args)  rewrite known-wrapper-hashes.json in place
#   --check    print the digests; non-zero exit if any differ from the file
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
ENGINE="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
OUT="$HERE/known-wrapper-hashes.json"

# Extract the masking awk program from the engine verbatim (the block between
# the CANON_AWK heredoc markers) so the baseline and the runtime check share
# one source of truth. We do NOT source the engine (it runs top-level code).
AWK_PROG="$(awk '/<<'\''CANON_AWK'\''/{f=1;next} /^CANON_AWK$/{f=0} f' "$ENGINE")"
[ -n "$AWK_PROG" ] || { echo "regen: could not extract CANON_AWK program from engine" >&2; exit 1; }
canonicalize_awk() { printf '%s\n' "$AWK_PROG"; }

sha256_of_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}';
  else shasum -a 256 | awk '{print $1}'; fi
}

# stack -> wrapper template file, materialized path (for the JSON metadata)
declare -a STACKS=(
  "ts-cloudflare-worker|lib-observability.ts|src/lib/observability/index.ts"
  "ts-supabase-edge|index.ts|supabase/functions/_shared/observability/index.ts"
  "ts-react-vite|lib-observability.ts|src/lib/observability/index.ts"
  "go-fly-http|observability.go|internal/observability/observability.go"
)

canon_hash_of_template() {
  local stack="$1" wf="$2"
  # Read the OLD (v0.4.x) wrapper from the vendored bytes, NOT `git show main:`
  # — `main` now carries the post-1.16.0 registry shape (PR #45). See
  # old-wrappers/README.md.
  awk -f <(canonicalize_awk) "$HERE/old-wrappers/$stack/$wf" \
    | sha256_of_stdin
}

if [ "${1:-}" = "--check" ]; then
  rc=0
  for rec in "${STACKS[@]}"; do
    IFS='|' read -r stack wf _mat <<<"$rec"
    got="$(canon_hash_of_template "$stack" "$wf")"
    want="$(jq -r --arg s "$stack" '.stacks[$s]["0.4.x"].sha256 // empty' "$OUT")"
    if [ "$got" = "$want" ]; then
      echo "OK   $stack  $got"
    else
      echo "DRIFT $stack  recorded=$want  computed=$got"; rc=1
    fi
  done
  exit $rc
fi

# Rewrite the JSON.
tmp="$(mktemp)"
{
  echo '{'
  echo '  "_comment": "Migration 0017 hand-modified detection baseline. See HASHING-NOTE.md for the canonicalisation (structural masking) method, version coverage rationale, and the token-substitution handling. Keys: <stack> -> <add-observability-wrapper-version> -> { wrapper_file, materialized_path, sha256 }. sha256 is the digest of the CANONICAL (masked) form of the OLD (pre-1.16.0) template wrapper, vendored under test-fixtures/0017/old-wrappers/ (add-observability v0.4.x, pinned from commit 34ee72e). Masking collapses every token-substitution site to a fixed placeholder so a real substituted wrapper canonicalises to the same digest, while any change outside a token site differs (fail-closed). Regenerate with migrations/test-fixtures/0017/regen-hashes.sh, which imports the masking program verbatim from the apply engine. cf-cloudflare-pages is intentionally absent: it never shipped a wrapper before 1.16.0.",'
  echo '  "hash_algorithm": "sha256",'
  echo '  "canonicalization": "structural-masking-v1",'
  echo '  "schema_version": 2,'
  echo '  "stacks": {'
  n=${#STACKS[@]}; i=0
  for rec in "${STACKS[@]}"; do
    IFS='|' read -r stack wf mat <<<"$rec"
    h="$(canon_hash_of_template "$stack" "$wf")"
    i=$((i+1)); sep=','; [ "$i" -eq "$n" ] && sep=''
    printf '    "%s": {\n' "$stack"
    printf '      "0.4.x": {\n'
    printf '        "wrapper_file": "%s",\n' "$wf"
    printf '        "materialized_path": "%s",\n' "$mat"
    printf '        "sha256": "%s"\n' "$h"
    printf '      }\n'
    printf '    }%s\n' "$sep"
  done
  echo '  }'
  echo '}'
} > "$tmp"

jq -e . < "$tmp" >/dev/null
mv "$tmp" "$OUT"
echo "wrote $OUT"
