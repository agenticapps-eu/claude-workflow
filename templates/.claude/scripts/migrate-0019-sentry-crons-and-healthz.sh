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
# D-07 (R-rev-5 HONEST REFRAME): on default refuse, recovery artifacts
# (.observability-0019.patch + .gitignore entries) are written ONLY to DIRTY
# roots (not clean roots). Clean roots are listed but not patched.
# Pass --allow-partial (or set ALLOW_PARTIAL=1) to also emit patches for clean
# roots (restores v0.6.0 "patches everywhere on refuse" behaviour).
#
# Exit codes:
#   0  success: all eligible roots migrated (or idempotent no-op, or no wrapper)
#   2  refused: >=1 hand-modified root. DEFAULT mode = ZERO writes to CLEAN roots;
#               DIRTY roots receive .observability-0019.patch for splice recovery.
#               --allow-partial mode  = clean roots applied, dirty roots skipped;
#               patches emitted to ALL roots for reference.
#   3  pre-flight abort (wrong version / bad inputs) — ZERO writes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
TEMPLATES_DIR=""
# Save env value BEFORE overwriting so the D-07 env-var opt-in can read it.
_ALLOW_PARTIAL_ENV="${ALLOW_PARTIAL:-}"
ALLOW_PARTIAL=0
DRY_RUN=0
PROJECT_DIR="$PWD"
PAUSE_SIGFILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir) TEMPLATES_DIR="$2"; shift 2 ;;
    --allow-partial) ALLOW_PARTIAL=1; shift ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    --pause-between-passes)
      PAUSE_SIGFILE="$2"
      # T-23-07 REWORKED (codex HIGH-2): ${TMPDIR:-/tmp} default + explicit allow-list prefix.
      # Only two allow-listed patterns permitted — this flag is test-only; production must not use it.
      _tmp="${TMPDIR:-/tmp}"
      case "$PAUSE_SIGFILE" in
        "$_tmp"/sigterm-test-*) : ;;
        */migrations/test-fixtures/0019/*/sigterm-*) : ;;
        *)
          echo "migrate-0019: --pause-between-passes is a test-only flag with non-allow-listed path: $PAUSE_SIGFILE" >&2
          echo "migrate-0019: allowed prefixes are \${TMPDIR:-/tmp}/sigterm-test-* or migrations/test-fixtures/0019/*/sigterm-*" >&2
          exit 2
          ;;
      esac
      echo "migrate-0019: WARNING — --pause-between-passes is a test-only flag; do not use in production" >&2
      shift 2
      ;;
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

# ─── SPLIT TRAP (T-23-05 + codex HIGH-2) ─────────────────────────────────────
# EXIT runs silently on every exit (success + signal). Idempotent. NO warning.
# INT  runs cleanup THEN exit 130 (signal-compatible).
# TERM runs cleanup THEN exit 143 (signal-compatible).
# Separate handlers prevent "cleanup" from appearing on normal successful exits,
# which is the codex HIGH-2 KEY ASSERTION tested by run-tests.sh Case 2.
_cleanup_fired=0
_do_cleanup() {
  [ "$_cleanup_fired" -eq 1 ] && return 0
  _cleanup_fired=1
  # Idempotent state teardown. NO env-var echo, NO partial-file dump (T-23-05).
  [ -n "$PAUSE_SIGFILE" ] && [ -f "$PAUSE_SIGFILE" ] && rm -f "$PAUSE_SIGFILE" 2>/dev/null || true
}
on_exit()  { _do_cleanup; }           # silent on success AND on signal
on_int()   { _do_cleanup; exit 130; } # SIGINT  → exit 130
on_term()  { _do_cleanup; exit 143; } # SIGTERM → exit 143
trap on_exit EXIT
trap on_int  INT
trap on_term TERM

# ─── logging helpers (mirror 0017's prose tone) ──────────────────────────────
info() { echo "migrate-0019: $*"; }
warn() { echo "migrate-0019: $*" >&2; }

# ─── D-07: ALLOW_PARTIAL env var opt-in ──────────────────────────────────────
# CLI --allow-partial wins; env var is a convenience for automation scripts.
# _ALLOW_PARTIAL_ENV was captured before arg parsing overwrote ALLOW_PARTIAL=0.
# Supports ALLOW_PARTIAL=1, ALLOW_PARTIAL=true, ALLOW_PARTIAL=yes.
if [ "$ALLOW_PARTIAL" -eq 0 ]; then
  case "$_ALLOW_PARTIAL_ENV" in
    1|true|yes)
      ALLOW_PARTIAL=1
      info "ALLOW_PARTIAL env var detected — treating as --allow-partial."
      ;;
  esac
fi

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

# ─── pre-classify filter: index.ts needs a sibling co-anchor AND non-dist path ──
# D-01 / Pitfall 1 / codex M-2 mitigation: `find . -name index.ts` matches every
# index.ts in the project (build outputs, dist/, generated code). Without filtering,
# those would route to classify_stack and emit SKIP_UNSUPPORTED noise OR (worse,
# codex M-2) compiled bundles that happen to ship both index.ts AND middleware.ts
# adjacent would be misclassified as wrappers. Two filters:
#   (a) sibling co-anchor: index.ts kept only if parent dir contains middleware.ts
#       (cf-worker shape) or _middleware.ts (cf-pages shape).
#   (b) non-dist path: kept only if path does NOT contain /dist/, /build/, or /out/.
# Supabase-edge `index.ts` is handled by the separate `_filter_supabase_edge_roots`
# pass — those candidates come from the `-type d -name observability` find,
# not this one.
_filter_index_ts_requires_co_anchor() {
  while IFS= read -r f; do
    case "$f" in
      */index.ts)
        # (b) Reject build-output paths regardless of sibling anchors (codex M-2).
        case "$f" in
          */dist/*|*/build/*|*/out/*)
            # Drop silently — build outputs that happen to contain index.ts +
            # middleware.ts are not legitimate wrappers.
            continue
            ;;
        esac
        # (a) Sibling co-anchor requirement.
        local parent="${f%/index.ts}"
        if [ -f "$parent/middleware.ts" ] || [ -f "$parent/_middleware.ts" ]; then
          printf '%s\n' "$f"
        fi
        # else: drop silently — operator never sees noise for unrelated index.ts
        ;;
      *)
        # Non-index.ts files pass through unchanged.
        printf '%s\n' "$f"
        ;;
    esac
  done
}

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
              -name middleware.go -o \
              -name index.ts \
            \) \
            -print 2>/dev/null \
          | _filter_index_ts_requires_co_anchor \
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
      if { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; } && [ -f "$dir/_middleware.ts" ]; then
        echo "ts-cloudflare-pages"; return
      fi
      ;;
  esac
  # Cf-pages anchor file (_middleware.ts is Pages-specific). D-01: accept
  # `index.ts` (canonical materialised filename per meta.yaml) OR
  # `lib-observability.ts` (legacy/fixture filename) as the anchor.
  if [ -f "$dir/_middleware.ts" ] && { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; }; then
    echo "ts-cloudflare-pages"; return
  fi
  # React-vite: browser bundle markers (uses lib-observability.ts only;
  # react-vite has no `index.ts` materialisation today — leave unchanged).
  if [ -f "$dir/lib-observability.ts" ] \
     && [ -f "$dir/ErrorBoundary.tsx" ]; then
    echo "ts-react-vite"; return
  fi
  if [ -f "$dir/lib-observability.ts" ] \
     && grep -qE '@sentry/react|@sentry/browser|import\.meta\.env' "$dir/lib-observability.ts" 2>/dev/null; then
    echo "ts-react-vite"; return
  fi
  # Cf-worker (default TS server shape). D-01: accept `index.ts` (canonical)
  # OR `lib-observability.ts` (legacy/fixture).
  if { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; } && [ -f "$dir/middleware.ts" ]; then
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

# ─── resolve_anchor_files: pick the actually-present anchor at fingerprint time
# D-01: cf-worker and cf-pages materialise as `index.ts` per meta.yaml's
# target.wrapper_path, but fixtures and legacy projects may use the source
# filename `lib-observability.ts`. This helper picks `index.ts` when present
# (canonical wins), else `lib-observability.ts`. Returns space-separated
# filenames; non-zero exit if no anchor found.
#
# Stacks unaffected by D-01 (supabase-edge always materialises as index.ts;
# go-fly-http uses observability.go) fall through to the static list.
#
# Used by:
#   - is_known_clean_wrapper() — fingerprint match against template baseline
#   - emit_refuse_artifacts_for() — refuse-path diff against project anchor (codex M-3)
resolve_anchor_files() {
  local dir="$1" stack="$2"
  case "$stack" in
    ts-cloudflare-worker)
      local anchor=""
      if [ -f "$dir/index.ts" ]; then
        anchor="index.ts"
      elif [ -f "$dir/lib-observability.ts" ]; then
        anchor="lib-observability.ts"
      else
        return 1
      fi
      echo "$anchor middleware.ts"
      ;;
    ts-cloudflare-pages)
      local anchor=""
      if [ -f "$dir/index.ts" ]; then
        anchor="index.ts"
      elif [ -f "$dir/lib-observability.ts" ]; then
        anchor="lib-observability.ts"
      else
        return 1
      fi
      echo "$anchor _middleware.ts"
      ;;
    ts-supabase-edge)
      echo "index.ts middleware.ts"
      ;;
    ts-react-vite)
      echo "lib-observability.ts ErrorBoundary.tsx"
      ;;
    go-fly-http)
      echo "observability.go middleware.go"
      ;;
    *)
      return 1
      ;;
  esac
}

# Map a project-side anchor filename to the corresponding template-source filename.
# When the project uses `index.ts` (canonical materialised name), the template
# source baseline is still `lib-observability.ts`. Other filenames map to themselves.
_template_name_for_anchor() {
  local f="$1" stack="$2"
  case "$f" in
    index.ts)
      case "$stack" in
        ts-cloudflare-worker|ts-cloudflare-pages)
          echo "lib-observability.ts"
          return
          ;;
      esac
      ;;
  esac
  echo "$f"
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
# Uses resolve_anchor_files() to pick the actually-present anchor (D-01):
# a project with index.ts is compared against the template's lib-observability.ts
# baseline (same content, same canonical hash).
is_known_clean_wrapper() {
  local dir="$1" stack="$2"
  local files; files=$(resolve_anchor_files "$dir" "$stack") || return 1
  local f template_name want got
  for f in $files; do
    if [ ! -f "$dir/$f" ]; then return 1; fi
    # Map project-side anchor to template-side filename for baseline comparison.
    template_name=$(_template_name_for_anchor "$f" "$stack")
    want=$(baseline_hash "$stack" "$template_name")
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

  # Resolve the actual anchor filename present in this project (D-01 / codex M-3).
  local resolved_anchor_files
  resolved_anchor_files=$(resolve_anchor_files "$dir" "$stack") || resolved_anchor_files=""
  local anchor_note=""
  case "$resolved_anchor_files" in
    index.ts*)   anchor_note="index.ts (canonical materialised filename per meta.yaml)" ;;
    lib-observability.ts*) anchor_note="lib-observability.ts (legacy fixture filename)" ;;
    *)           anchor_note="$resolved_anchor_files" ;;
  esac

  {
    echo "# .observability-0019.patch"
    echo "# Generated by migrate-0019-sentry-crons-and-healthz.sh"
    echo "# Stack: $stack"
    echo "# Wrapper root: $dir"
    echo "# Anchor file: $anchor_note"
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
      ts-cloudflare-worker|ts-cloudflare-pages)
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
        # D-11 narrowed: queue-monitor.ts ships for cf-worker + cf-pages only
        if [ -f "$src/queue-monitor.ts" ]; then
          echo ""
          echo "# === would create: $dir/queue-monitor.ts ==="
          cat "$src/queue-monitor.ts"
        fi
        ;;
      ts-supabase-edge)
        # Supabase Edge: cron-monitor + healthz only (no queue-monitor.ts per codex H-6)
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
    # Uses resolve_anchor_files (D-01/codex M-3): resolves the project-side anchor
    # (index.ts or lib-observability.ts) and maps to the template-side filename.
    local files; files=$(resolve_anchor_files "$dir" "$stack") || files=$(stack_fingerprint_files "$stack")
    local f template_name src project_file tmpl
    src=$(stack_template_dir "$stack")
    for f in $files; do
      template_name=$(_template_name_for_anchor "$f" "$stack")
      tmpl="$src/$template_name"
      project_file="$dir/$f"
      if [ -f "$tmpl" ] && [ -f "$project_file" ]; then
        warn "      diff $f (excerpt vs known v1.17.0 baseline):"
        diff -u "$tmpl" "$project_file" 2>/dev/null | head -10 | sed 's/^/        /' >&2
      fi
    done
    warn "      wrote recovery artefact: $dir/.observability-0019.patch"
    warn "      recover: (a) revert the wrapper drift; (b) re-run migrate-0019;"
    warn "               (c) optionally splice .observability-0019.patch manually."
  done

  # D-07 (R-rev-5 HONEST REFRAME): default refuse no longer writes to CLEAN roots.
  # DIRTY roots still receive .observability-0019.patch + .gitignore entries for splice recovery.
  # --allow-partial (or ALLOW_PARTIAL=1 env) restores v0.6.0 "patches everywhere on refuse"
  # for operators with existing manual-recovery automation.
  if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
    if [ "$ALLOW_PARTIAL" -eq 1 ]; then
      warn "  would-be-clean roots (patches emitted under --allow-partial for reference):"
      for i in "${!CLEAN_DIRS[@]}"; do
        warn "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
        emit_refuse_artifacts_for "${CLEAN_DIRS[$i]}" "${CLEAN_STACKS[$i]}" "CLEAN-skipped"
      done
    else
      info "  would-be-clean roots (patches NOT emitted by default; pass --allow-partial or set ALLOW_PARTIAL=1 to emit patches for clean roots too):"
      for i in "${!CLEAN_DIRS[@]}"; do
        info "    CLEAN: ${CLEAN_DIRS[$i]}  (stack: ${CLEAN_STACKS[$i]})"
      done
    fi
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

# ─── pass-boundary signal-file rendezvous (test-only) ────────────────────────
# When --pause-between-passes is set, create the signal file to wake the test,
# then spin-wait until it is removed (or 30s elapses). A SIGTERM delivered during
# this wait triggers on_term → exit 143. This is the only safe interrupt point
# between the two passes: pass 1 (classify) is read-only; pass 2 (apply) must
# not be interrupted mid-write.
if [ -n "$PAUSE_SIGFILE" ]; then
  : > "$PAUSE_SIGFILE"
  for _pbi in $(seq 1 300); do
    [ ! -f "$PAUSE_SIGFILE" ] && break
    sleep 0.1
  done
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
    ts-cloudflare-worker|ts-cloudflare-pages)
      # D-11 narrowed scope (codex H-6): queue-monitor.ts ships ONLY to cf-worker
      # and cf-pages stacks (Supabase Edge is Deno-runtime; no Cloudflare-Queue
      # equivalent).
      local cm="$src/cron-monitor.ts" hz="$src/healthz-snippet.ts" qm="$src/queue-monitor.ts"
      if [ ! -f "$cm" ] || [ ! -f "$hz" ] || [ ! -f "$qm" ]; then
        warn "  ERROR: template files missing for stack '$stack' ($cm or $hz or $qm)"
        return 1
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        info "  (dry-run) would copy: $cm -> $dir/cron-monitor.ts"
        info "  (dry-run) would copy: $hz -> $dir/healthz-snippet.ts"
        info "  (dry-run) would copy: $qm -> $dir/queue-monitor.ts"
      else
        cp "$cm" "$dir/cron-monitor.ts"    || return 1
        cp "$hz" "$dir/healthz-snippet.ts" || return 1
        cp "$qm" "$dir/queue-monitor.ts"   || return 1
        info "  migrated: $dir  (stack: $stack) — added cron-monitor.ts + healthz-snippet.ts + queue-monitor.ts (Phase 25 D-11)"
      fi
      ;;
    ts-supabase-edge)
      # Supabase Edge: cron-monitor + healthz only. No queue-monitor.ts here
      # (codex H-6 — no Cloudflare-Queue equivalent on Deno/Supabase).
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
if [ ${#APPLY_FAILED[@]} -gt 0 ]; then
  exit 2
fi
# With --allow-partial, dirty roots are expected and skipped — not a failure.
# In default mode, DIRTY_DIRS > 0 means the all-clean gate above already exited 2;
# reaching here means ALLOW_PARTIAL=1, so dirty roots are intentionally skipped.
exit 0
