#!/usr/bin/env bash
# Migration 0010 — Normalize GSD section markers in CLAUDE.md.
#
# Walks CLAUDE.md, finds `<!-- GSD:{slug}-start[ source:{path}] -->...<!-- GSD:{slug}-end -->`
# blocks where {slug} is one of the seven canonical sections (project,
# stack, conventions, architecture, skills, workflow, profile), and
# rewrites each into the self-closing reference form:
#
#     <!-- GSD:{slug} source:{path} /-->
#     ## {Heading}
#     See [`{linkPath}`](./{linkPath}) — auto-synced.
#
# Idempotent. Source-existence-safe (preserves block if source: file
# resolves to a path that doesn't exist on disk). Markers inside fenced
# markdown code blocks (``` … ```) are NEVER touched — fence-aware
# parsing keeps documentation examples intact. Custom (non-canonical)
# slugs are preserved unchanged with a stderr warning. Nested marker
# blocks are rejected as malformed (exit 2). Targets bash 3.2+ and
# POSIX `grep`/`sed`/`awk` so it runs unchanged on macOS and Linux.
#
# Usage:
#   .claude/hooks/normalize-claude-md.sh [path/to/CLAUDE.md]
#
# Defaults to ./CLAUDE.md. Exit codes:
#   0 — success (file modified OR unchanged)
#   1 — input file not found / not readable / not an accepted path
#       (non-CLAUDE.md basename, symlink, binary, etc.)
#   2 — malformed input (unclosed marker / nested marker)
#   3 — input file too large (DoS guard)

set -u
set -o pipefail

# Security: pin PATH to system locations. Defends against PATH-poisoning
# attacks where a hostile project adds a malicious `awk` (or `cp`, `mv`,
# `diff`, `mktemp`, `rm`) earlier in PATH (CSO audit finding H2).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

INPUT="${1:-./CLAUDE.md}"

# ─── Input validation ────────────────────────────────────────────────────────
# CSO H1: refuse paths whose basename is not exactly CLAUDE.md.
if [ "$(basename -- "$INPUT")" != "CLAUDE.md" ]; then
  echo "normalize-claude-md: refusing to operate on non-CLAUDE.md path: $INPUT" >&2
  exit 1
fi
# CSO M1: refuse symbolic links; `cp`/`mv` would follow them.
if [ -L "$INPUT" ]; then
  echo "normalize-claude-md: refusing to operate on symlink: $INPUT" >&2
  exit 1
fi
if [ ! -f "$INPUT" ]; then
  echo "normalize-claude-md: input not found: $INPUT" >&2
  exit 1
fi
if [ ! -r "$INPUT" ]; then
  echo "normalize-claude-md: input not readable: $INPUT" >&2
  exit 1
fi
# CSO M2: DoS guard. 5 MiB cap covers any plausible CLAUDE.md.
INPUT_SIZE=$(wc -c <"$INPUT" 2>/dev/null | tr -d ' ')
if [ -n "$INPUT_SIZE" ] && [ "$INPUT_SIZE" -gt 5242880 ]; then
  echo "normalize-claude-md: input exceeds 5 MiB DoS guard ($INPUT_SIZE bytes); skipping" >&2
  exit 3
fi
# Stage-2 BLOCK-1: refuse binary input (NUL bytes). Prevents the script
# from silently truncating a non-text file to zero length when `read -r`
# stops at the first NUL. Implementation note: `grep -q $'\x00' …`
# DOES NOT WORK — shells truncate args at the first NUL, so grep
# receives an empty pattern and matches every line. Use `tr -d` size
# comparison instead (portable across BSD/GNU `tr`).
TEXT_SIZE=$(LC_ALL=C tr -d '\000' <"$INPUT" 2>/dev/null | wc -c | tr -d ' ')
if [ -n "$TEXT_SIZE" ] && [ -n "$INPUT_SIZE" ] && [ "$TEXT_SIZE" != "$INPUT_SIZE" ]; then
  echo "normalize-claude-md: refusing to operate on binary (NUL-containing) input: $INPUT" >&2
  exit 1
fi

# ─── Slug allowlist ──────────────────────────────────────────────────────────
# Stage-2 BLOCK-5: only the seven canonical GSD slugs trigger
# normalization. Custom user-authored slugs (e.g., a project adds
# `<!-- GSD:wibble-start -->` to track its own stuff) are preserved
# unchanged so we don't trample non-GSD use of the same comment shape.
is_canonical_slug() {
  case "$1" in
    project|stack|conventions|architecture|skills|workflow|profile) return 0 ;;
    *)                                                               return 1 ;;
  esac
}

# Resolve `source:` label to its real file/directory path (relative to CWD).
# Returns the resolved path on stdout; empty string if no mapping exists.
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
# preserve the original block (source file missing, unmapped label,
# or non-canonical slug).
build_replacement() {
  local slug="$1" source_label="$2"

  # Stage-2 BLOCK-5: non-canonical slugs are preserved unchanged.
  # Emit a stderr note so the user can audit what was kept.
  if ! is_canonical_slug "$slug"; then
    echo "normalize-claude-md: non-canonical slug '$slug'; preserving block" >&2
    return 1
  fi

  if [ "$slug" = "workflow" ]; then
    if [ -f ".claude/claude-md/workflow.md" ]; then
      return 0  # collapse entirely — 0009 has the canonical copy
    fi
    printf '<!-- GSD:workflow source:GSD defaults /-->\n'
    heading_for_slug workflow
    printf '> Workflow defaults. Migration 0009 not yet applied.\n'
    return 0
  fi

  if [ "$slug" = "profile" ]; then
    printf '<!-- GSD:profile /-->\n'
    heading_for_slug profile
    printf '> Run `/gsd-profile-user` to generate. Managed by `generate-claude-profile`.\n'
    return 0
  fi

  local link_path
  link_path="$(resolve_source_path "$source_label")"

  # Stage-2 FLAG-D: unmapped source labels also emit a warning (not just
  # silent preserve). Makes the fixture README's "MUST warn" claim true
  # in both branches (missing-file AND unmapped-label).
  if [ -z "$link_path" ]; then
    echo "normalize-claude-md: unmapped source label '$source_label' for slug=$slug; preserving block" >&2
    return 1
  fi

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
#
# Fence-aware: lines inside ``` fenced code blocks are passed through
# verbatim (Stage-2 BLOCK-2). Nested marker blocks are rejected as
# malformed (Stage-2 BLOCK-6). CRLF line endings are normalized to LF
# at read time so the marker regex matches on either convention
# (Stage-2 BLOCK-3).
normalize() {
  local input="$1"
  local in_block=0
  local block_slug=""
  local block_source=""
  local block_buf=""
  local in_fence=0  # 1 when inside a ```-fenced markdown code block

  while IFS= read -r line || [ -n "$line" ]; do
    # BLOCK-3: strip trailing CR so CRLF-ended files behave identically.
    line="${line%$'\r'}"

    # BLOCK-2: toggle fence state on any line whose first non-whitespace
    # chars are three or more backticks (CommonMark §4.5). Inside a
    # fence, NEVER process markers — emit lines verbatim.
    if [[ "$line" =~ ^[[:space:]]{0,3}\`\`\`+ ]]; then
      printf '%s\n' "$line"
      in_fence=$((1 - in_fence))
      continue
    fi
    if [ "$in_fence" = "1" ]; then
      printf '%s\n' "$line"
      continue
    fi

    if [ "$in_block" = "0" ]; then
      if [[ "$line" =~ ^\<!--[[:space:]]*GSD:([a-z]+)-start([[:space:]]+source:(.+))?[[:space:]]*--\>$ ]]; then
        in_block=1
        block_slug="${BASH_REMATCH[1]}"
        block_source="${BASH_REMATCH[3]:-}"
        # Trim trailing whitespace the greedy `.+` may have captured.
        block_source="${block_source%"${block_source##*[![:space:]]}"}"
        block_buf="$line"
        continue
      fi
      printf '%s\n' "$line"
    else
      # BLOCK-6: nested -start markers are malformed. Bail out cleanly.
      if [[ "$line" =~ ^\<!--[[:space:]]*GSD:[a-z]+-start ]]; then
        printf '%s\n%s\n' "$block_buf" "$line" >&2
        echo "normalize-claude-md: nested marker block (inner -start while inside slug=$block_slug); malformed input" >&2
        return 2
      fi
      block_buf="$block_buf"$'\n'"$line"
      if [[ "$line" =~ ^\<!--[[:space:]]*GSD:${block_slug}-end[[:space:]]*--\>$ ]]; then
        local replacement
        if replacement="$(build_replacement "$block_slug" "$block_source")"; then
          if [ -n "$replacement" ]; then
            printf '%s\n' "$replacement"
          fi
        else
          printf '%s\n' "$block_buf"
        fi
        in_block=0
        block_slug=""
        block_source=""
        block_buf=""
      fi
    fi
  done <"$input"

  if [ "$in_block" = "1" ]; then
    printf '%s\n' "$block_buf" >&2
    echo "normalize-claude-md: unclosed marker block for slug=$block_slug" >&2
    return 2
  fi
  if [ "$in_fence" = "1" ]; then
    echo "normalize-claude-md: warning — unterminated fenced code block at EOF" >&2
    # Non-fatal; the input may be valid markdown with a missing closing fence.
  fi
  return 0
}

# Collapse runs of 2+ consecutive blank lines down to a single blank line.
collapse_blank_runs() {
  awk 'BEGIN { blank=0 }
       /^[[:space:]]*$/ { if (blank == 0) print ""; blank=1; next }
       { print; blank=0 }'
}

# Stage-2 BLOCK-4: atomic write via mv, not cp. mv within the same
# filesystem is atomic at the POSIX level. The temp file lives in the
# same directory as the input so mv stays on one filesystem. Two
# concurrent invocations now produce a final state that is "one or the
# other's output," never a corrupt mid-write read.
INPUT_DIR="$(dirname -- "$INPUT")"
TMP_OUT="$(mktemp "$INPUT_DIR/.normalize-claude-md.XXXXXX")" || {
  echo "normalize-claude-md: mktemp failed in $INPUT_DIR" >&2
  exit 1
}
trap 'rm -f "$TMP_OUT"' EXIT

if ! normalize "$INPUT" | collapse_blank_runs >"$TMP_OUT"; then
  exit 2
fi

if ! diff -q "$INPUT" "$TMP_OUT" >/dev/null 2>&1; then
  # mv is atomic when source and dest are on the same filesystem (POSIX
  # rename(2) guarantee). Preserves permissions because mv-as-rename
  # doesn't touch file mode of the existing entry being replaced.
  mv -f "$TMP_OUT" "$INPUT"
fi

exit 0
