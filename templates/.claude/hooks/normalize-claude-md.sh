#!/usr/bin/env bash
# Migration 0010 — Normalize GSD section markers in CLAUDE.md.
#
# Walks CLAUDE.md, finds `<!-- GSD:{slug}-start[ source:{path}] -->...<!-- GSD:{slug}-end -->`
# blocks, and rewrites each into the self-closing reference form:
#
#     <!-- GSD:{slug} source:{path} /-->
#     ## {Heading}
#     See [`{linkPath}`](./{linkPath}) — auto-synced.
#
# Idempotent. Source-existence-safe (preserves block if source: file
# resolves to a path that doesn't exist on disk). Targets bash 3.2+ and
# POSIX `grep`/`sed`/`awk` so it runs unchanged on macOS and Linux.
#
# Usage:
#   .claude/hooks/normalize-claude-md.sh [path/to/CLAUDE.md]
#
# Defaults to ./CLAUDE.md. Exit codes:
#   0 — success (file modified OR unchanged)
#   1 — input file not found / not readable
#   2 — malformed input (unclosed marker)

set -u
set -o pipefail

INPUT="${1:-./CLAUDE.md}"

if [ ! -f "$INPUT" ]; then
  echo "normalize-claude-md: input not found: $INPUT" >&2
  exit 1
fi
if [ ! -r "$INPUT" ]; then
  echo "normalize-claude-md: input not readable: $INPUT" >&2
  exit 1
fi

# Resolve `source:` label to its real file/directory path (relative to CWD).
# Returns the resolved path on stdout; empty string if no mapping exists
# (caller treats empty as "no link — heading only").
resolve_source_path() {
  local label="$1"
  case "$label" in
    "PROJECT.md")             echo ".planning/PROJECT.md" ;;
    "codebase/STACK.md")      echo ".planning/codebase/STACK.md" ;;
    "research/STACK.md")      echo ".planning/research/STACK.md" ;;
    "STACK.md")               echo ".planning/codebase/STACK.md" ;;
    "CONVENTIONS.md")         echo ".planning/codebase/CONVENTIONS.md" ;;
    "ARCHITECTURE.md")        echo ".planning/codebase/ARCHITECTURE.md" ;;
    "skills/")                echo ".claude/skills/" ;;
    "GSD defaults")           echo "" ;;
    *)                        echo "" ;;
  esac
}

# Map slug → human heading. Mirrors gsd-tools' sectionHeadings constant.
heading_for_slug() {
  case "$1" in
    project)      echo "## Project" ;;
    stack)        echo "## Technology Stack" ;;
    conventions)  echo "## Conventions" ;;
    architecture) echo "## Architecture" ;;
    skills)       echo "## Project Skills" ;;
    workflow)     echo "## GSD Workflow Enforcement" ;;
    profile)      echo "## Developer Profile" ;;
    *)            echo "## ${1}" ;;
  esac
}

# Compute the normalized replacement for a marker block.
# Args: slug, source-label-or-empty.
# Writes the replacement text to stdout.
# Returns 0 if a replacement was generated; 1 if the caller should
# preserve the original block (source file missing).
build_replacement() {
  local slug="$1" source_label="$2"

  # Special case: workflow block becomes redundant once migration 0009
  # has vendored the canonical workflow text into .claude/claude-md/
  # workflow.md. Skip the block entirely.
  if [ "$slug" = "workflow" ]; then
    if [ -f ".claude/claude-md/workflow.md" ]; then
      # No output — caller skips the block (deletes from CLAUDE.md).
      return 0
    fi
    # Fallback: keep heading + no-link reference.
    printf '<!-- GSD:workflow source:GSD defaults /-->\n'
    heading_for_slug workflow
    printf '> Workflow defaults. Migration 0009 not yet applied.\n'
    return 0
  fi

  # Special case: profile has no `source:` attribute and no on-disk
  # source file we can link to; emit a placeholder.
  if [ "$slug" = "profile" ]; then
    printf '<!-- GSD:profile /-->\n'
    heading_for_slug profile
    printf '> Run `/gsd-profile-user` to generate. Managed by `generate-claude-profile`.\n'
    return 0
  fi

  # Standard case: resolve source-label to a real path, verify it exists,
  # emit self-closing form + heading + link.
  local link_path
  link_path="$(resolve_source_path "$source_label")"

  # No mapping → preserve. (Caller signal: return 1.)
  if [ -z "$link_path" ]; then
    return 1
  fi

  # Source-existence safety: if the resolved path doesn't exist on disk,
  # preserve the original block unchanged. Strip optional trailing slash
  # for the existence check (directories check as "exists" via test -e).
  local check_path="${link_path%/}"
  if [ ! -e "$check_path" ]; then
    echo "normalize-claude-md: source missing for slug=$slug source=$source_label (resolved to $link_path); preserving block" >&2
    return 1
  fi

  printf '<!-- GSD:%s source:%s /-->\n' "$slug" "$source_label"
  heading_for_slug "$slug"
  printf 'See [`%s`](./%s) — auto-synced.\n' "$link_path" "$link_path"
  return 0
}

# Walk the file line by line, tracking marker-block state. Emit either
# the original line (outside a block) or, on encountering a -start
# marker, capture the entire block and emit the normalized replacement.
normalize() {
  local input="$1"
  local in_block=0
  local block_slug=""
  local block_source=""
  local block_buf=""

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" = "0" ]; then
      # Detect start marker:
      #   <!-- GSD:{slug}-start -->                    (no source)
      #   <!-- GSD:{slug}-start source:{label} -->     (with source)
      # Optional whitespace before/after attributes is tolerated.
      # Source-label capture (.+?) is greedy in bash but the trailing
      # anchor `[[:space:]]*--\>$` forces backtracking to leave the `-->`
      # closing on its own — which means labels containing spaces
      # (e.g., `source:GSD defaults`) match correctly.
      if [[ "$line" =~ ^\<!--[[:space:]]*GSD:([a-z]+)-start([[:space:]]+source:(.+))?[[:space:]]*--\>$ ]]; then
        in_block=1
        block_slug="${BASH_REMATCH[1]}"
        # Trim trailing whitespace the greedy match may have included.
        block_source="${BASH_REMATCH[3]:-}"
        block_source="${block_source%"${block_source##*[![:space:]]}"}"
        block_buf="$line"
        continue
      fi
      # Pass through every other line, including already self-closing
      # markers (idempotency case).
      printf '%s\n' "$line"
    else
      # Inside a block — accumulate until the matching -end marker.
      block_buf="$block_buf"$'\n'"$line"
      if [[ "$line" =~ ^\<!--[[:space:]]*GSD:${block_slug}-end[[:space:]]*--\>$ ]]; then
        # Block complete. Decide: normalize or preserve?
        local replacement
        if replacement="$(build_replacement "$block_slug" "$block_source")"; then
          # build_replacement succeeded. Output replacement (may be
          # empty — workflow special case strips the block entirely).
          if [ -n "$replacement" ]; then
            printf '%s\n' "$replacement"
          fi
        else
          # Preserve original block byte-for-byte.
          printf '%s\n' "$block_buf"
        fi
        in_block=0
        block_slug=""
        block_source=""
        block_buf=""
      fi
    fi
  done <"$input"

  # Unclosed marker block? Treat as malformed input — emit what we had
  # buffered and exit non-zero.
  if [ "$in_block" = "1" ]; then
    printf '%s\n' "$block_buf" >&2
    echo "normalize-claude-md: unclosed marker block for slug=$block_slug" >&2
    return 2
  fi
  return 0
}

# Collapse runs of 2+ consecutive blank lines down to a single blank
# line. Removing a marker block (workflow special case) leaves the
# blank lines that surrounded it adjacent to each other; this pass
# tidies up. Mirrors `gsd-tools`' `/\n{3,}/g, '\n\n'` normalization.
collapse_blank_runs() {
  awk 'BEGIN { blank=0 }
       /^[[:space:]]*$/ { if (blank == 0) print ""; blank=1; next }
       { print; blank=0 }'
}

# Write the normalized output to a temp file; if it differs from the
# input, replace atomically. Skipping the write when content is unchanged
# avoids retriggering PostToolUse-on-write loops.
TMP_OUT="$(mktemp -t normalize-claude-md.XXXXXX)"
trap 'rm -f "$TMP_OUT"' EXIT

if ! normalize "$INPUT" | collapse_blank_runs >"$TMP_OUT"; then
  exit 2
fi

if ! diff -q "$INPUT" "$TMP_OUT" >/dev/null 2>&1; then
  cp "$TMP_OUT" "$INPUT"
fi

exit 0
