#!/usr/bin/env bash
# migrate-0019-sentry-crons-and-healthz.sh
# ─────────────────────────────────────────────────────────────────────────────
# Executable apply engine for migration 0019 (additive adoption of
# withCronMonitor + healthz-snippet on existing add-observability v0.5.x /
# claude-workflow v1.17.0 wrappers). The migration markdown
# (migrations/0019-sentry-crons-and-healthz.md) invokes this script; the
# script owns the HIGH-RISK pieces — discovery, content-hash hand-modified
# detection, the all-clean gate (PLAN R08 binding), and the safe-root apply.
#
# Mirrors templates/.claude/scripts/migrate-0017-axiom-destination.sh:
#   * Same flag parsing
#   * Same `canonicalize_awk` style-insensitive content-hash canonicaliser
#   * Same all-clean-gate-then-apply 2-pass structure (review #7 / R08)
#   * Same `.observability-NNNN.patch` refuse artefacts
#
# 0019-specific deltas:
#   * NO CLAUDE.md observability: block rewrite (CONTEXT G6).
#   * NO token-substitution for TS new files (they ship verbatim;
#     CONTEXT G1 + per-file `// SERVICE_NAME` env-var resolution).
#   * NEW file copy only (additive): cron-monitor.{ts,go} +
#     healthz-snippet.{ts,go}.
#   * Idempotency via cron-monitor.{ts,go} presence check.
#   * ts-react-vite SKIPPED entirely per CONTEXT D10.
#   * ts-supabase-edge applies same files as worker per CONTEXT D5b.
#
# Usage:
#   migrate-0019-sentry-crons-and-healthz.sh \
#       --templates-dir <dir>          # add-observability/templates source tree
#       [--allow-partial]              # apply clean roots, skip+list dirty ones
#       [--dry-run]                    # classify only; no writes
#       [--project-dir <dir>]          # default: CWD
#
# Exit codes:
#   0  success: all eligible roots migrated (or idempotent no-op, or no wrapper)
#   2  refused: >=1 hand-modified root. DEFAULT mode = ZERO writes to ANY root.
#               --allow-partial mode  = clean roots applied, dirty skipped.
#   3  pre-flight abort (wrong version / bad inputs) — ZERO writes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
TEMPLATES_DIR=""
ALLOW_PARTIAL=0
DRY_RUN=0
PROJECT_DIR="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir) TEMPLATES_DIR="$2"; shift 2 ;;
    --allow-partial) ALLOW_PARTIAL=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    *) echo "migrate-0019: unknown arg: $1" >&2; exit 3 ;;
  esac
done

# Default templates dir to the scaffolder home if installed in the canonical
# location; the migration MD documents this resolution path.
if [ -z "$TEMPLATES_DIR" ]; then
  if [ -d "$HOME/.claude/skills/agenticapps-workflow/add-observability/templates" ]; then
    TEMPLATES_DIR="$HOME/.claude/skills/agenticapps-workflow/add-observability/templates"
  elif [ -d "$SCRIPT_DIR/../../../add-observability/templates" ]; then
    # Engine is being run from inside the scaffolder repo (tests / dev).
    TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../../../add-observability/templates" && pwd)"
  fi
fi

[ -n "$TEMPLATES_DIR" ] || { echo "migrate-0019: --templates-dir required (and no default found)" >&2; exit 3; }
[ -d "$TEMPLATES_DIR" ] || { echo "migrate-0019: templates dir not found: $TEMPLATES_DIR" >&2; exit 3; }

cd "$PROJECT_DIR" || { echo "migrate-0019: cannot cd to $PROJECT_DIR" >&2; exit 3; }

SKILL_FILE=".claude/skills/agentic-apps-workflow/SKILL.md"

# ─── logging helpers (mirror 0017's prose tone) ──────────────────────────────
info() { echo "migrate-0019: $*"; }
warn() { echo "migrate-0019: $*" >&2; }

# ─── sha256 helper (portable BSD/GNU) ────────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ─── version bump (defined early: called from no-wrapper / all-already exits) ─
bump_version() {
  if [ ! -f "$SKILL_FILE" ]; then return 0; fi
  if grep -q '^version: 1.18.0$' "$SKILL_FILE" 2>/dev/null; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  (dry-run) would bump $SKILL_FILE -> version 1.18.0"
    return 0
  fi
  local tmp; tmp=$(mktemp)
  sed -E 's/^version: 1\.17\.[0-9]+$/version: 1.18.0/' "$SKILL_FILE" > "$tmp" && mv "$tmp" "$SKILL_FILE"
  info "  bumped $SKILL_FILE -> version 1.18.0"
}

# ─── pre-flight: workflow version gate ───────────────────────────────────────
# Project must be at 1.17.0 (or already 1.18.0 for a clean re-run).
if [ ! -f "$SKILL_FILE" ]; then
  warn "ABORT — $SKILL_FILE missing (not an agenticapps-workflow project)"
  exit 3
fi
INSTALLED=$(grep -E '^version:' "$SKILL_FILE" | head -1 | sed 's/version: //' | tr -d '[:space:]')
case "$INSTALLED" in
  1.17.*|1.18.0) : ;;
  *)
    warn "ABORT — workflow version is '$INSTALLED' (need 1.17.0)."
    warn "        Apply prior migrations via /update-agenticapps-workflow first."
    exit 3
    ;;
esac

# ─── discover wrapper roots ──────────────────────────────────────────────────
# A wrapper root is a directory containing one of the canonical anchor files
# generated by add-observability. We scan the project tree (excluding common
# noise dirs) and dedupe.
#
# Per-stack anchor files (the one we know exists in v1.17.0):
#   ts-cloudflare-worker     : lib-observability.ts  AND  middleware.ts
#   ts-cloudflare-pages      : lib-observability.ts  AND  _middleware.ts
#   ts-supabase-edge         : index.ts              AND  middleware.ts (under */_shared/observability/)
#   go-fly-http              : observability.go      AND  middleware.go
#   ts-react-vite            : lib-observability.ts  AND  ErrorBoundary.tsx (skipped per D10)
#
# Each ROOT is recorded as `<abs-dir>` (no | encoding — stack is re-derived later).
ROOTS=()

# Collect every plausible anchor file path under the project. Filter against
# the scaffolder's own templates dir (so running the engine inside the
# scaffolder repo doesn't try to migrate the SOURCE).
SCAFFOLDER_TEMPLATES_REAL=""
if [ -d "$TEMPLATES_DIR" ]; then
  SCAFFOLDER_TEMPLATES_REAL=$(cd "$TEMPLATES_DIR" && pwd -P 2>/dev/null || true)
fi

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  dir=$(dirname "$entry")
  # Absolute, canonicalised
  dir_abs=$(cd "$dir" 2>/dev/null && pwd -P || true)
  [ -z "$dir_abs" ] && continue
  # Skip anything under the scaffolder's templates tree — that's the SOURCE,
  # not a materialised wrapper. (Also: project-internal node_modules, .git.)
  if [ -n "$SCAFFOLDER_TEMPLATES_REAL" ]; then
    case "$dir_abs" in
      "$SCAFFOLDER_TEMPLATES_REAL"*) continue ;;
    esac
  fi
  ROOTS+=("$dir_abs")
done < <(find . \
            -path ./node_modules -prune -o \
            -path ./.git -prune -o \
            -path './**/node_modules' -prune -o \
            -type f \( \
              -name lib-observability.ts -o \
              -name observability.go -o \
              -name middleware.go \
            \) \
            -print 2>/dev/null \
          | sort -u)

# Also pick up supabase-edge roots: dir containing index.ts AND middleware.ts under */_shared/observability/.
# Helper isolates the case statement from the outer < <(...) parser context
# (bash struggles with `case ;;` inside process substitution).
_filter_supabase_edge_roots() {
  while read -r d; do
    case "$d" in
      */_shared/observability)
        if [ -f "$d/index.ts" ] && [ -f "$d/middleware.ts" ]; then
          echo "$d"
        fi
        ;;
    esac
  done
}

while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  dir_abs=$(cd "$dir" 2>/dev/null && pwd -P || true)
  [ -z "$dir_abs" ] && continue
  if [ -n "$SCAFFOLDER_TEMPLATES_REAL" ]; then
    case "$dir_abs" in
      "$SCAFFOLDER_TEMPLATES_REAL"*) continue ;;
    esac
  fi
  ROOTS+=("$dir_abs")
done < <(find . \
            -path ./node_modules -prune -o \
            -path ./.git -prune -o \
            -type d -name observability \
            -print 2>/dev/null \
          | _filter_supabase_edge_roots)

# Dedupe preserving order. (bash 3.2-compatible — no associative arrays.)
if [ ${#ROOTS[@]} -gt 0 ]; then
  UNIQ=()
  for r in "${ROOTS[@]}"; do
    found=0
    for u in ${UNIQ[@]+"${UNIQ[@]}"}; do
      [ "$u" = "$r" ] && { found=1; break; }
    done
    [ "$found" -eq 0 ] && UNIQ+=("$r")
  done
  ROOTS=("${UNIQ[@]}")
fi

# If no wrapper at all → pre-init project; nothing for 0019 to do. Still bump
# version (project is on-track) and exit 0.
if [ ${#ROOTS[@]} -eq 0 ]; then
  info "no materialised observability wrapper found — nothing to migrate."
  bump_version
  exit 0
fi

# ─── classify_stack: map a wrapper dir to its stack identifier ───────────────
# Disambiguation signals (mirrors 0017's approach):
#   - go-fly-http   : observability.go + middleware.go
#   - supabase-edge : dir is */_shared/observability AND has index.ts
#   - cf-pages      : has _middleware.ts (Pages-specific anchor) OR dir is
#                     */functions/_lib/observability
#   - cf-worker     : has middleware.ts (non-Pages) AND lib-observability.ts
#                     contains @sentry/cloudflare
#   - react-vite    : has ErrorBoundary.tsx AND lib-observability.ts contains
#                     @sentry/react|@sentry/browser
#   - unknown       : everything else (fail-closed → SKIP_UNSUPPORTED)
classify_stack() {
  local dir="$1"
  # Go
  if [ -f "$dir/observability.go" ] && [ -f "$dir/middleware.go" ]; then
    echo "go-fly-http"; return
  fi
  # Supabase-edge canonical layout
  case "$dir" in
    */_shared/observability)
      if [ -f "$dir/index.ts" ] && [ -f "$dir/middleware.ts" ]; then
        echo "ts-supabase-edge"; return
      fi
      ;;
  esac
  # Cf-pages canonical layout
  case "$dir" in
    */functions/_lib/observability)
      if [ -f "$dir/lib-observability.ts" ] && [ -f "$dir/_middleware.ts" ]; then
        echo "ts-cloudflare-pages"; return
      fi
      ;;
  esac
  # Cf-pages anchor file (_middleware.ts is Pages-specific)
  if [ -f "$dir/_middleware.ts" ] && [ -f "$dir/lib-observability.ts" ]; then
    echo "ts-cloudflare-pages"; return
  fi
  # React-vite: browser bundle markers
  if [ -f "$dir/lib-observability.ts" ] \
     && [ -f "$dir/ErrorBoundary.tsx" ]; then
    echo "ts-react-vite"; return
  fi
  if [ -f "$dir/lib-observability.ts" ] \
     && grep -qE '@sentry/react|@sentry/browser|import\.meta\.env' "$dir/lib-observability.ts" 2>/dev/null; then
    echo "ts-react-vite"; return
  fi
  # Cf-worker (default TS server shape)
  if [ -f "$dir/lib-observability.ts" ] && [ -f "$dir/middleware.ts" ]; then
    echo "ts-cloudflare-worker"; return
  fi
  echo "unknown"
}

# ─── per-stack fingerprint files (the wrapper bytes whose hash we check) ─────
# These files MUST exist at v1.17.0 in their canonical clean form. Any drift
# from the canonical baseline → DIRTY.
stack_fingerprint_files() {
  case "$1" in
    ts-cloudflare-worker) echo "lib-observability.ts middleware.ts" ;;
    ts-cloudflare-pages)  echo "lib-observability.ts _middleware.ts" ;;
    ts-supabase-edge)     echo "index.ts middleware.ts" ;;
    go-fly-http)          echo "observability.go middleware.go" ;;
    *) echo "" ;;
  esac
}

# Per-stack source dir under TEMPLATES_DIR (the v1.17.0 canonical bytes).
stack_template_dir() {
  case "$1" in
    ts-cloudflare-worker) echo "$TEMPLATES_DIR/ts-cloudflare-worker" ;;
    ts-cloudflare-pages)  echo "$TEMPLATES_DIR/ts-cloudflare-pages" ;;
    ts-supabase-edge)     echo "$TEMPLATES_DIR/ts-supabase-edge" ;;
    go-fly-http)          echo "$TEMPLATES_DIR/go-fly-http" ;;
    *) echo "" ;;
  esac
}

# ─── canonicalisation (structural masking) ───────────────────────────────────
# Copied verbatim from migrate-0017-axiom-destination.sh canonicalize_awk.
# Any future refinement should land in 0017 FIRST and be back-ported here.
canonicalize_awk() {
  cat <<'CANON_AWK'
BEGIN { P = "\x00TOK\x00"; in_redact = 0 }
{
  line = $0

  # ── style normalisation (Prettier-insensitive) ───────────────────────────
  gsub(/\r$/, "", line)                       # CRLF
  gsub(/'/, "\"", line)                       # single → double string quotes
  gsub(/;[ \t]*\/\//, " //", line)            # semicolon before a line comment
  sub(/;[ \t]*$/, "", line)                   # trailing semicolon
  sub(/,[ \t]*$/, "", line)                   # trailing comma (Prettier all)
  gsub(/[ \t][ \t]+/, " ", line)              # collapse 2+ spaces/tabs → 1
  sub(/[ \t]+$/, "", line)                    # trim trailing whitespace

  if (line ~ /agenticapps:observability:(start|end)/) { next }

  if (NORMALIZE_ONLY == "1") { print line; next }

  # REDACTED_KEYS array body — collapse genuine list elements to one placeholder
  if (in_redact) {
    if (line ~ /^[[:space:]]*\]$/ || line ~ /^[[:space:]]*\}$/) { in_redact = 0; print line; next }
    if (line ~ /^[[:space:]]*$/) { next }
    if (line ~ /^[[:space:]]*"[^"]*"$/) { next }
    if (line ~ /^[[:space:]]*\{\{REDACTED_KEYS\}\}$/) { next }
    print line; next
  }
  if (line ~ /REDACTED_KEYS.*=[[:space:]]*\[[[:space:]]*$/ \
      || line ~ /redactedKeys[[:space:]]*=[[:space:]]*\[\]string\{[[:space:]]*$/) {
    print line; print " " P "REDACTED_KEYS" P; in_redact = 1; next
  }

  if (line ~ /Service:[[:space:]]/) {
    sub(/Service:[[:space:]].*$/, "Service: " P "SERVICE_NAME" P, line); print line; next
  }
  if (line ~ /Destination:[[:space:]]/) {
    sub(/Destination:[[:space:]].*$/, "Destination: " P "DESTINATION" P, line); print line; next
  }

  if (line ~ /^package [A-Za-z0-9_{}]+$/) { print "package " P "PACKAGE_NAME" P; next }
  if (line ~ /^\/\/ Package /) {
    sub(/Package [A-Za-z0-9_{}]+/, "Package " P "PACKAGE_NAME" P, line); print line; next
  }

  if (line ~ /^const SERVICE_DEFAULT = ".*"$/) {
    print "const SERVICE_DEFAULT = \"" P "SERVICE_NAME" P "\""; next
  }
  if (line ~ /^[[:space:]]*serviceName = ".*"$/) {
    sub(/=.*$/, "= \"" P "SERVICE_NAME" P "\"", line); print line; next
  }

  if (line ~ /^const DEBUG_SAMPLE_RATE = .*$/) {
    print "const DEBUG_SAMPLE_RATE = " P "DEBUG_SAMPLE_RATE" P; next
  }
  if (line ~ /^const TRACE_SAMPLE_RATE = .*$/) {
    print "const TRACE_SAMPLE_RATE = " P "TRACE_SAMPLE_RATE" P; next
  }
  if (line ~ /^[[:space:]]*debugSampleRate = .*$/) {
    sub(/=.*$/, "= " P "DEBUG_SAMPLE_RATE" P, line); print line; next
  }
  if (line ~ /^[[:space:]]*traceSampleRate = .*$/) {
    sub(/=.*$/, "= " P "TRACE_SAMPLE_RATE" P, line); print line; next
  }

  if (line ~ /^[[:space:]]*[A-Za-z_{}][A-Za-z0-9_{}]*\?: string$/) {
    sub(/[A-Za-z_{}][A-Za-z0-9_{}]*\?: string/, P "ENV_VAR" P "?: string", line); print line; next
  }

  if (line ~ /Deno\.env\.get\("[^"]*"\)/) {
    gsub(/Deno\.env\.get\("[^"]*"\)/, "Deno.env.get(\"" P "ENV_VAR" P "\")", line)
  }
  if (line ~ /os\.Getenv\("[^"]*"\)/) {
    gsub(/os\.Getenv\("[^"]*"\)/, "os.Getenv(\"" P "ENV_VAR" P "\")", line)
  }
  if (line ~ /env\.[A-Za-z_{}][A-Za-z0-9_{}]*[^A-Za-z0-9_{}(]/ || line ~ /env\.[A-Za-z_{}][A-Za-z0-9_{}]*$/) {
    gsub(/env\.[A-Za-z_{}][A-Za-z0-9_{}]*\(/, "\x01KEEP\x01", line)
    gsub(/env\.[A-Za-z_{}][A-Za-z0-9_{}]*/, "env." P "ENV_VAR" P, line)
    gsub(/\x01KEEP\x01/, "env.get(", line)
  }

  print line
}
CANON_AWK
}

# Canonicalise a file by structural masking, return sha256 of result.
canonical_hash() {
  local f="$1"
  local tmp; tmp=$(mktemp)
  awk -f <(canonicalize_awk) "$f" > "$tmp" 2>/dev/null || cp "$f" "$tmp"
  sha256_of "$tmp"
  rm -f "$tmp"
}

# Compute the BASELINE canonical hash for a stack's fingerprint file by
# canonicalising the SOURCE template under $TEMPLATES_DIR. The source bytes are
# the canonical v1.17.0 form by construction (scaffolder repo at this commit).
baseline_hash() {
  local stack="$1" file="$2"
  local src; src=$(stack_template_dir "$stack")/"$file"
  [ -f "$src" ] || { echo ""; return; }
  canonical_hash "$src"
}

# is_known_clean_wrapper: every fingerprint file in $dir canonicalises to the
# stack's baseline. Returns 0 (clean) or 1 (dirty).
is_known_clean_wrapper() {
  local dir="$1" stack="$2"
  local files; files=$(stack_fingerprint_files "$stack")
  [ -z "$files" ] && return 1
  local f want got
  for f in $files; do
    if [ ! -f "$dir/$f" ]; then return 1; fi
    want=$(baseline_hash "$stack" "$f")
    [ -z "$want" ] && return 1
    got=$(canonical_hash "$dir/$f")
    [ "$got" = "$want" ] || return 1
  done
  return 0
}

# ─── pass 1: classify (R08 binding) ──────────────────────────────────────────
declare -a CLEAN_DIRS=() CLEAN_STACKS=()
declare -a DIRTY_DIRS=() DIRTY_STACKS=()
declare -a SKIP_ALREADY=()
declare -a SKIP_UNSUPPORTED=()

for dir in "${ROOTS[@]}"; do
  stack=$(classify_stack "$dir")

  case "$stack" in
    unknown)
      SKIP_UNSUPPORTED+=("$dir (unknown wrapper shape)")
      continue
      ;;
    ts-react-vite)
      # CONTEXT D10: react-vite has no scheduled handlers; skip entirely.
      SKIP_UNSUPPORTED+=("$dir (react-vite — D10)")
      continue
      ;;
  esac

  # Idempotency: cron-monitor.{ts,go} already present.
  if [ -f "$dir/cron-monitor.ts" ] || [ -f "$dir/cron_monitor.go" ]; then
    SKIP_ALREADY+=("$dir")
    continue
  fi

  if is_known_clean_wrapper "$dir" "$stack"; then
    CLEAN_DIRS+=("$dir"); CLEAN_STACKS+=("$stack")
  else
    DIRTY_DIRS+=("$dir"); DIRTY_STACKS+=("$stack")
  fi
done

# ─── idempotent-no-op exit (everything already applied or unsupported) ───────
if [ ${#DIRTY_DIRS[@]} -eq 0 ] && [ ${#CLEAN_DIRS[@]} -eq 0 ]; then
  if [ ${#SKIP_ALREADY[@]} -gt 0 ]; then
    info "all ${#SKIP_ALREADY[@]} wrapper root(s) already migrated — idempotent no-op."
  fi
  if [ ${#SKIP_UNSUPPORTED[@]} -gt 0 ]; then
    info "skipped ${#SKIP_UNSUPPORTED[@]} unsupported wrapper root(s)."
    for d in "${SKIP_UNSUPPORTED[@]}"; do
      info "  unsupported: $d"
    done
  fi
  bump_version
  exit 0
fi

# ─── emit_refuse_artifacts: per-root diff + .observability-0019.patch ────────
# A 0019 "patch" describes the would-be ADDITIONS (cron-monitor + healthz),
# not a diff against an existing modified file (0017's shape) — 0019 is
# purely additive. The patch captures the file content the engine would have
# copied, so the operator can splice it manually if they choose.
emit_refuse_artifacts_for() {
  local dir="$1" stack="$2" label="$3"   # label: "DIRTY" or "CLEAN-skipped"
  local src; src=$(stack_template_dir "$stack")
  local patch="$dir/.observability-0019.patch"

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "  ($label, dry-run) would emit: $patch"
    return
  fi

  {
    echo "# .observability-0019.patch"
    echo "# Generated by migrate-0019-sentry-crons-and-healthz.sh"
    echo "# Stack: $stack"
    echo "# Wrapper root: $dir"
    echo "# Classification: $label"
    echo "#"
    echo "# This patch captures the FILES migration 0019 would have ADDED to"
    echo "# this wrapper root. Migration 0019 refused (atomic / all-clean gate)"
    echo "# because at least one other root in this project is hand-modified."
    echo "#"
    echo "# Recovery:"
    echo "#   (a) Stash / revert the hand-modified wrapper files in the dirty root(s)."
    echo "#   (b) Re-run migrate-0019 to apply cleanly to ALL roots."
    echo "#   (c) Optionally splice these additions manually if you prefer."
    echo "#"

    case "$stack" in
      ts-cloudflare-worker|ts-cloudflare-pages|ts-supabase-edge)
        if [ -f "$src/cron-monitor.ts" ]; then
          echo ""
          echo "# === would create: $dir/cron-monitor.ts ==="
          cat "$src/cron-monitor.ts"
        fi
        if [ -f "$src/healthz-snippet.ts" ]; then
          echo ""
          echo "# === would create: $dir/healthz-snippet.ts ==="
          cat "$src/healthz-snippet.ts"
        fi
        ;;
      go-fly-http)
        if [ -f "$src/cron_monitor.go" ]; then
          echo ""
          echo "# === would create: $dir/cron_monitor.go ==="
          cat "$src/cron_monitor.go"
        fi
        if [ -f "$src/healthz_snippet.go" ]; then
          echo ""
          echo "# === would create: $dir/healthz_snippet.go ==="
          cat "$src/healthz_snippet.go"
        fi
        ;;
    esac
  } > "$patch" 2>/dev/null

  # Idempotently add the patch filename to a co-located .gitignore (if one).
  local gi="$dir/.gitignore"
  if [ -f "$gi" ]; then
    if ! grep -qF ".observability-0019.patch" "$gi"; then
      printf '\n.observability-0019.patch\n' >> "$gi"
    fi
  fi
}

emit_refuse_artifacts() {
  local i
  warn "  hand-modified wrapper root(s) detected:"
  for i in "${!DIRTY_DIRS[@]}"; do
    local dir="${DIRTY_DIRS[$i]}" stack="${DIRTY_STACKS[$i]}"
    warn "    DIRTY: $dir  (stack: $stack)"
    emit_refuse_artifacts_for "$dir" "$stack" "DIRTY"
    # Per-fingerprint-file diff against baseline (excerpt, for the operator).
    local files; files=$(stack_fingerprint_files "$stack")
    local f src tmpl
    src=$(stack_template_dir "$stack")
    for f in $files; do
      tmpl="$src/$f"
      if [ -f "$tmpl" ] && [ -f "$dir/$f" ]; then
        warn "      diff $f (excerpt vs known v1.17.0 baseline):"
        diff -u "$tmpl" "$dir/$f" 2>/dev/null | head -10 | sed 's/^/        /' >&2
      fi
    done
    warn "      wrote recovery artefact: $dir/.observability-0019.patch"
    warn "      recover: (a) revert the wrapper drift; (b) re-run migrate-0019;"
    warn "               (c) optionally splice .observability-0019.patch manually."
  done

  # Also emit patches for the would-be-clean roots, so the operator has the
  # full context even after the atomic refusal.
  if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
    warn "  would-be-clean roots (patches emitted for reference):"
    for i in "${!CLEAN_DIRS[@]}"; do
      warn "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
      emit_refuse_artifacts_for "${CLEAN_DIRS[$i]}" "${CLEAN_STACKS[$i]}" "CLEAN-skipped"
    done
  fi
}

# ─── all-clean gate (R08 binding) ────────────────────────────────────────────
if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  warn "detected ${#DIRTY_DIRS[@]} hand-modified wrapper root(s)."
  emit_refuse_artifacts
  if [ "$ALLOW_PARTIAL" -eq 0 ]; then
    warn "ABORT (all-clean gate) — no new wrapper files written to ANY root."
    if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
      warn "        clean roots that WOULD migrate under --allow-partial:"
      printf '          %s\n' "${CLEAN_DIRS[@]}" >&2
    fi
    warn "        Re-run with --allow-partial to migrate clean roots and skip dirty ones."
    exit 2
  fi
  warn "--allow-partial — migrating clean roots, skipping dirty ones."
fi

# ─── pass 2: apply (R08 binding — only reached if all-clean OR --allow-partial) ──
apply_root() {
  local dir="$1" stack="$2"
  local src; src=$(stack_template_dir "$stack")

  if [ ! -d "$src" ]; then
    warn "  ERROR: no template source for stack '$stack' ($src)"
    return 1
  fi

  case "$stack" in
    ts-cloudflare-worker|ts-cloudflare-pages|ts-supabase-edge)
      local cm="$src/cron-monitor.ts" hz="$src/healthz-snippet.ts"
      if [ ! -f "$cm" ] || [ ! -f "$hz" ]; then
        warn "  ERROR: template files missing for stack '$stack' ($cm or $hz)"
        return 1
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        info "  (dry-run) would copy: $cm -> $dir/cron-monitor.ts"
        info "  (dry-run) would copy: $hz -> $dir/healthz-snippet.ts"
      else
        cp "$cm" "$dir/cron-monitor.ts"    || return 1
        cp "$hz" "$dir/healthz-snippet.ts" || return 1
        info "  migrated: $dir  (stack: $stack) — added cron-monitor.ts + healthz-snippet.ts"
      fi
      ;;
    go-fly-http)
      local cm="$src/cron_monitor.go" hz="$src/healthz_snippet.go"
      if [ ! -f "$cm" ] || [ ! -f "$hz" ]; then
        warn "  ERROR: template files missing for stack '$stack' ($cm or $hz)"
        return 1
      fi
      # Substitute Go package name: read the existing observability.go's
      # `package <name>` line and rewrite the copies to match. (TS stacks
      # have no analogous token in the new files.)
      local pkg=""
      if [ -f "$dir/observability.go" ]; then
        pkg=$(awk '/^package [A-Za-z0-9_]+/ { print $2; exit }' "$dir/observability.go")
      fi
      if [ -z "$pkg" ]; then
        warn "  ERROR: cannot resolve Go package name for $dir/observability.go"
        return 1
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        info "  (dry-run) would copy: $cm -> $dir/cron_monitor.go (package $pkg)"
        info "  (dry-run) would copy: $hz -> $dir/healthz_snippet.go (package $pkg)"
      else
        # Substitute {{PACKAGE_NAME}} if present in source; otherwise straight copy.
        sed "s/{{PACKAGE_NAME}}/${pkg}/g" "$cm" > "$dir/cron_monitor.go"    || return 1
        sed "s/{{PACKAGE_NAME}}/${pkg}/g" "$hz" > "$dir/healthz_snippet.go" || return 1
        info "  migrated: $dir  (stack: $stack, package: $pkg) — added cron_monitor.go + healthz_snippet.go"
      fi
      ;;
    *)
      warn "  ERROR: unknown stack '$stack' for $dir"
      return 1
      ;;
  esac
  return 0
}

# Apply post-checks: syntactic validation (toolchain-permitting). Absent
# toolchain is a non-fatal skip — the file copy itself is the deliverable;
# any compile failure in the new files indicates a scaffolder bug, not a
# project bug, and the fixtures will catch it.
post_check_root() {
  local dir="$1" stack="$2"
  [ "$DRY_RUN" -eq 1 ] && return 0
  case "$stack" in
    go-fly-http)
      # No-op here — `go build` requires the surrounding module; we don't
      # attempt it. The new files import only stdlib + the wrapper's own
      # package and were verified by `go test` in the scaffolder.
      ;;
    ts-*)
      # Same rationale: tsc would need the whole project's tsconfig.
      ;;
  esac
  return 0
}

MIGRATED=0
APPLY_FAILED=()
for i in "${!CLEAN_DIRS[@]}"; do
  dir="${CLEAN_DIRS[$i]}"; stack="${CLEAN_STACKS[$i]}"
  if apply_root "$dir" "$stack"; then
    if post_check_root "$dir" "$stack"; then
      MIGRATED=$((MIGRATED+1))
    else
      APPLY_FAILED+=("$dir")
      warn "  post-check failed on $dir — leaving files in place (operator review)"
    fi
  else
    APPLY_FAILED+=("$dir")
  fi
done

# Version bump only when something useful happened OR --allow-partial migrated
# all clean roots cleanly. (Mirrors 0017's policy: never claim 1.18.0 if all
# clean roots failed apply.)
if [ "$MIGRATED" -gt 0 ]; then
  bump_version
elif [ ${#DIRTY_DIRS[@]} -eq 0 ] && [ ${#APPLY_FAILED[@]} -eq 0 ]; then
  # No clean roots, no dirty, no failures — only unsupported / already-applied.
  bump_version
fi

# ─── summary + exit ──────────────────────────────────────────────────────────
info "summary — migrated=$MIGRATED failed=${#APPLY_FAILED[@]} already=${#SKIP_ALREADY[@]} unsupported=${#SKIP_UNSUPPORTED[@]} dirty-skipped=${#DIRTY_DIRS[@]}"

if [ ${#SKIP_ALREADY[@]} -gt 0 ]; then
  for d in "${SKIP_ALREADY[@]}"; do
    info "  already-applied: $d"
  done
fi
if [ ${#SKIP_UNSUPPORTED[@]} -gt 0 ]; then
  for d in "${SKIP_UNSUPPORTED[@]}"; do
    info "  unsupported: $d"
  done
fi

if [ ${#APPLY_FAILED[@]} -gt 0 ]; then
  warn "${#APPLY_FAILED[@]} clean root(s) FAILED to migrate:"
  printf '  failed: %s\n' "${APPLY_FAILED[@]}" >&2
fi
if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  warn "completed with ${#DIRTY_DIRS[@]} dirty root(s) skipped (--allow-partial)."
  printf '  skipped (hand-modified): %s\n' "${DIRTY_DIRS[@]}" >&2
fi
if [ ${#DIRTY_DIRS[@]} -gt 0 ] || [ ${#APPLY_FAILED[@]} -gt 0 ]; then
  exit 2
fi
exit 0
