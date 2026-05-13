#!/usr/bin/env bash
# Migration 0007 helper — invoke `gitnexus analyze` per family repo.
# User-initiated (NOT run by migration apply). See ADR 0020 for license.
#
# Usage:
#   index-family-repos.sh [--family <name> | --all | --default-set | --help]
#
# Defaults to printing usage. Forces the caller to choose scope explicitly
# to avoid surprise mass-indexing (which makes LLM calls + costs time).

set -e

SOURCECODE_ROOT="${WIKI_SOURCECODE:-$HOME/Sourcecode}"
GN_BIN="${GITNEXUS_BIN:-$(command -v gitnexus 2>/dev/null || true)}"

# Curated default-set: repos that benefit most from cross-repo code graph.
DEFAULT_SET=(
  "agenticapps/claude-workflow"
  "factiv/cparx"
  "factiv/fx-signal-agent"
  "neuroflash/neuroapi"
  "neuroflash/neuroflash_api"
  "neuroflash/mcp-server"
  "neuroflash/frontend-nextjs"
)

usage() {
  cat <<'EOF'
Usage: index-family-repos.sh [--family <name> | --all | --default-set | --help]

  --family <name>    Index repos under ~/Sourcecode/<name>/
  --all              Index agenticapps + factiv + neuroflash (~30-90 minutes)
  --default-set      Index a curated active-development subset (~10-20 minutes)
  --help             This message

⚠ WARNING — `gitnexus analyze` invokes a third-party LLM to build the code
  graph. Repository content is sent to the LLM provider configured in your
  gitnexus settings. Credentials and config are managed by gitnexus itself.

⚠ LICENSE — GitNexus is PolyForm Noncommercial 1.0. Using it to develop
  commercial products is permitted; embedding the runtime in a shipped
  product requires an enterprise license. See ADR 0020.

A typical 50k-LOC repo takes 1-3 minutes. Plan accordingly.
EOF
}

is_family() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local base_lc
  base_lc=$(basename "$dir" | tr '[:upper:]' '[:lower:]')
  case "$base_lc" in
    personal|shared|archive|.*) return 1 ;;
  esac
  for c in "$dir"/*/.git; do
    [ -e "$c" ] && return 0
  done
  return 1
}

index_repo() {
  local repo="$1"
  if [ ! -d "$repo/.git" ] && [ ! -f "$repo/.git" ]; then
    echo "skip: $repo (not a git repo)" >&2
    return 0
  fi
  echo "==> gitnexus analyze $repo" >&2
  (cd "$repo" && "$GN_BIN" analyze) || echo "warn: gitnexus analyze failed for $repo" >&2
}

index_family() {
  local fam_dir="$1"
  if ! is_family "$fam_dir"; then
    echo "skip: $fam_dir (not a family — no child git repos)" >&2
    return 0
  fi
  for repo_d in "$fam_dir"/*/; do
    repo="${repo_d%/}"
    if [ -d "$repo/.git" ] || [ -f "$repo/.git" ]; then
      index_repo "$repo"
    fi
  done
}

# ─── Argument dispatch ─────────────────────────────────────────────────────

[ $# -eq 0 ] && { usage; exit 0; }

if [ -z "$GN_BIN" ] || [ ! -x "$GN_BIN" ]; then
  echo "ERROR: gitnexus not installed. Run: npm install -g gitnexus" >&2
  exit 1
fi

case "$1" in
  --help|-h)
    usage
    exit 0
    ;;
  --family)
    [ -n "${2:-}" ] || { echo "ERROR: --family requires a name argument" >&2; exit 1; }
    fam_dir="$SOURCECODE_ROOT/$2"
    [ -d "$fam_dir" ] || { echo "ERROR: $fam_dir does not exist" >&2; exit 1; }
    index_family "$fam_dir"
    ;;
  --all)
    if [ -d "$SOURCECODE_ROOT" ]; then
      for fd in "$SOURCECODE_ROOT"/*/; do
        index_family "${fd%/}"
      done
    fi
    ;;
  --default-set)
    for rel in "${DEFAULT_SET[@]}"; do
      index_repo "$SOURCECODE_ROOT/$rel"
    done
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage
    exit 1
    ;;
esac

echo "Done."
exit 0
