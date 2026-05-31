#!/usr/bin/env bash
# migrate-0021-with-cron-and-queue-updates.sh
# ─────────────────────────────────────────────────────────────────────────────
# Migration 0021 apply engine — re-rev cron-monitor.ts + ship queue-monitor.ts
# for already-migrated v1.19.0 projects.
#
# See migrations/0021-with-cron-and-queue-updates.md.
# See docs/decisions/0033-with-queue-monitor.md §"Re-rev rationale" (codex H-7).
#
# Shape vs 0019: re-rev with dirty detection (NOT additive-only). canonicalize_awk
# is a VERBATIM MIRROR of 0019's per migrations/0019-sentry-crons-and-healthz.md:260
# anti-pattern note ("Mirror, not fork, 0017's canonicaliser. Any future refinement
# to the canonicaliser should land in 0017 first and be back-ported here, not
# diverged.") This script propagates that constraint: refinement to 0017 → ported
# to 0019 → ported here.
#
# All-clean-gate: mirrors 0019 — engine refuses to apply if any wrapper root's
# cron-monitor.ts is hand-modified. Twofold idempotency (codex M-8): SKIPs only
# when BOTH queue-monitor.ts presence (cf-worker + cf-pages) AND cron-monitor.ts
# canonical hash matches v1.20.0 baseline.
#
# Usage:
#   migrate-0021-with-cron-and-queue-updates.sh \
#       --templates-dir <dir>          # add-observability/templates source tree
#       [--dry-run]                    # classify only; no writes
#       [--project-dir <dir>]          # default: CWD
#
# Exit codes:
#   0  success: all eligible roots migrated (or idempotent no-op, or no wrapper)
#   1  refused: >=1 hand-modified root (DIRTY — hash matches neither v1.19.0 nor v1.20.0)
#   3  pre-flight abort (wrong version / bad inputs) — ZERO writes.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_ROOT is two levels above templates/.claude/scripts/
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
TEMPLATES_DIR=""
DRY_RUN=0
PROJECT_DIR="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir) TEMPLATES_DIR="$2"; shift 2 ;;
    --dry-run)       DRY_RUN=1; shift ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    *) echo "migrate-0021: unknown arg: $1" >&2; exit 3 ;;
  esac
done

# Default templates dir
if [ -z "$TEMPLATES_DIR" ]; then
  if [ -d "$HOME/.claude/skills/agenticapps-workflow/add-observability/templates" ]; then
    TEMPLATES_DIR="$HOME/.claude/skills/agenticapps-workflow/add-observability/templates"
  elif [ -d "$SCRIPT_DIR/../../../add-observability/templates" ]; then
    TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../../../add-observability/templates" && pwd)"
  fi
fi

[ -n "$TEMPLATES_DIR" ] || { echo "migrate-0021: --templates-dir required (and no default found)" >&2; exit 3; }
[ -d "$TEMPLATES_DIR" ] || { echo "migrate-0021: templates dir not found: $TEMPLATES_DIR" >&2; exit 3; }

cd "$PROJECT_DIR" || { echo "migrate-0021: cannot cd to $PROJECT_DIR" >&2; exit 3; }

SKILL_FILE=".claude/skills/agentic-apps-workflow/SKILL.md"
BASELINES_DIR="$REPO_ROOT/migrations/test-fixtures/0021/baselines/v1.19.0"

# ─── logging helpers ────────────────────────────────────────────────────────
info() { echo "migrate-0021: $*"; }
warn() { echo "migrate-0021: $*" >&2; }

# ─── sha256 helper (portable BSD/GNU) ────────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ─── version bump ───────────────────────────────────────────────────────────
bump_version() {
  if [ ! -f "$SKILL_FILE" ]; then return 0; fi
  if grep -q '^version: 1.20.0$' "$SKILL_FILE" 2>/dev/null; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  (dry-run) would bump $SKILL_FILE -> version 1.20.0"
    return 0
  fi
  local tmp; tmp=$(mktemp)
  sed -E 's/^version: 1\.19\.[0-9]+$/version: 1.20.0/' "$SKILL_FILE" > "$tmp" && mv "$tmp" "$SKILL_FILE"
  info "  bumped $SKILL_FILE -> version 1.20.0"
}

# ─── pre-flight: workflow version gate ───────────────────────────────────────
# Project must be at 1.19.0 (or already 1.20.0 for a clean re-run).
if [ ! -f "$SKILL_FILE" ]; then
  warn "ABORT — $SKILL_FILE missing (not an agenticapps-workflow project)"
  exit 3
fi
INSTALLED=$(grep -E '^version:' "$SKILL_FILE" | head -1 | sed 's/version: //' | tr -d '[:space:]')
case "$INSTALLED" in
  1.19.*|1.20.0) : ;;
  *)
    warn "ABORT — workflow version is '$INSTALLED' (need 1.19.0)."
    warn "        Apply prior migrations via /update-agenticapps-workflow first."
    exit 3
    ;;
esac

# ─── discover wrapper roots (VERBATIM MIRROR of 0019 discovery pipeline) ────
#
# Mirror — do NOT fork — of migrate-0019's discovery per
# migrations/0019-sentry-crons-and-healthz.md:260-263. Any refinement to the
# discovery pipeline lands in 0017/0019 first and is back-ported here.

# ─── pre-classify filter: index.ts needs sibling co-anchor AND non-dist path ──
_filter_index_ts_requires_co_anchor() {
  while IFS= read -r f; do
    case "$f" in
      */index.ts)
        case "$f" in
          */dist/*|*/build/*|*/out/*)
            continue
            ;;
        esac
        local parent="${f%/index.ts}"
        if [ -f "$parent/middleware.ts" ] || [ -f "$parent/_middleware.ts" ]; then
          printf '%s\n' "$f"
        fi
        ;;
      *)
        printf '%s\n' "$f"
        ;;
    esac
  done
}

ROOTS=()

SCAFFOLDER_TEMPLATES_REAL=""
if [ -d "$TEMPLATES_DIR" ]; then
  SCAFFOLDER_TEMPLATES_REAL=$(cd "$TEMPLATES_DIR" && pwd -P 2>/dev/null || true)
fi

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  dir=$(dirname "$entry")
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

# Dedupe (bash 3.2-compatible — no associative arrays)
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

if [ ${#ROOTS[@]} -eq 0 ]; then
  info "no materialised observability wrapper found — nothing to migrate."
  bump_version
  exit 0
fi

# ─── classify_stack (VERBATIM MIRROR of 0019 post-Plan-02) ──────────────────
classify_stack() {
  local dir="$1"
  if [ -f "$dir/observability.go" ] && [ -f "$dir/middleware.go" ]; then
    echo "go-fly-http"; return
  fi
  case "$dir" in
    */_shared/observability)
      if [ -f "$dir/index.ts" ] && [ -f "$dir/middleware.ts" ]; then
        echo "ts-supabase-edge"; return
      fi
      ;;
  esac
  case "$dir" in
    */functions/_lib/observability)
      if { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; } && [ -f "$dir/_middleware.ts" ]; then
        echo "ts-cloudflare-pages"; return
      fi
      ;;
  esac
  if [ -f "$dir/_middleware.ts" ] && { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; }; then
    echo "ts-cloudflare-pages"; return
  fi
  if [ -f "$dir/lib-observability.ts" ] \
     && [ -f "$dir/ErrorBoundary.tsx" ]; then
    echo "ts-react-vite"; return
  fi
  if [ -f "$dir/lib-observability.ts" ] \
     && grep -qE '@sentry/react|@sentry/browser|import\.meta\.env' "$dir/lib-observability.ts" 2>/dev/null; then
    echo "ts-react-vite"; return
  fi
  if { [ -f "$dir/index.ts" ] || [ -f "$dir/lib-observability.ts" ]; } && [ -f "$dir/middleware.ts" ]; then
    echo "ts-cloudflare-worker"; return
  fi
  echo "unknown"
}

# ─── resolve_anchor_files (VERBATIM MIRROR of 0019 post-Plan-02) ────────────
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
    go-fly-http)
      echo "observability.go middleware.go"
      ;;
    *)
      return 1
      ;;
  esac
}

# ─── stack_template_dir ─────────────────────────────────────────────────────
stack_template_dir() {
  case "$1" in
    ts-cloudflare-worker) echo "$TEMPLATES_DIR/ts-cloudflare-worker" ;;
    ts-cloudflare-pages)  echo "$TEMPLATES_DIR/ts-cloudflare-pages" ;;
    ts-supabase-edge)     echo "$TEMPLATES_DIR/ts-supabase-edge" ;;
    go-fly-http)          echo "$TEMPLATES_DIR/go-fly-http" ;;
    *) echo "" ;;
  esac
}

# ─── canonicalize_awk ─────────────────────────────────────────────────────────
# ⚠️ VERBATIM MIRROR of migrate-0019-sentry-crons-and-healthz.sh ⚠️
# DO NOT MODIFY THIS BLOCK independently. Any refinement to the canonicaliser
# MUST land in migrate-0017's script first, then be back-ported to migrate-0019,
# then re-ported here. Per migrations/0019-sentry-crons-and-healthz.md:260-263.
# Mirror — not fork — of migrate-0017/migrate-0019's canonicaliser.
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

# Canonicalise a file and return its sha256.
canonical_hash() {
  local f="$1"
  local tmp; tmp=$(mktemp)
  awk -f <(canonicalize_awk) "$f" > "$tmp" 2>/dev/null || cp "$f" "$tmp"
  sha256_of "$tmp"
  rm -f "$tmp"
}

# ─── Pre-compute v1.19.0 + v1.20.0 baseline hashes ──────────────────────────
# v1.19.0 baselines: frozen literal files at migrations/test-fixtures/0021/baselines/v1.19.0/
# (codex M-1 — NOT generated from current templates which are already at v1.20.0).
# v1.20.0 baselines: the CURRENT template cron-monitor.ts (post-Plan-03 state).

baseline_hash_v1_19_0() {
  local stack="$1"
  local baseline="$BASELINES_DIR/$stack/cron-monitor.ts"
  [ -f "$baseline" ] || { warn "missing v1.19.0 baseline for $stack at $baseline"; return 1; }
  canonical_hash "$baseline"
}

baseline_hash_v1_20_0() {
  local stack="$1"
  local src; src="$(stack_template_dir "$stack")/cron-monitor.ts"
  [ -f "$src" ] || { warn "missing v1.20.0 template for $stack at $src"; return 1; }
  canonical_hash "$src"
}

# ─── All-clean-gate + twofold idempotency check (codex M-8) ─────────────────
# Returns:
#   0 = clean-to-apply (cron-monitor.ts hash matches v1.19.0 baseline)
#   1 = already-applied (twofold: hash matches v1.20.0 AND queue-monitor.ts present for cf-worker/pages)
#   2 = DIRTY (hash matches neither baseline)
is_clean_to_apply_021() {
  local dir="$1" stack="$2"
  [ -f "$dir/cron-monitor.ts" ] || return 2
  local project_hash
  project_hash=$(canonical_hash "$dir/cron-monitor.ts") || return 2

  local hash_v19 hash_v20
  hash_v19=$(baseline_hash_v1_19_0 "$stack") || return 2
  hash_v20=$(baseline_hash_v1_20_0 "$stack") || return 2

  if [ "$project_hash" = "$hash_v20" ]; then
    # cron-monitor.ts at v1.20.0 — check queue-monitor.ts for twofold idempotency (codex M-8)
    case "$stack" in
      ts-cloudflare-worker|ts-cloudflare-pages)
        if [ -f "$dir/queue-monitor.ts" ]; then
          return 1  # fully already-applied
        else
          return 0  # cron up-to-date but queue missing → re-apply
        fi
        ;;
      ts-supabase-edge)
        return 1  # already-applied (no queue-monitor.ts required for supabase-edge)
        ;;
    esac
  fi

  if [ "$project_hash" = "$hash_v19" ]; then
    return 0  # clean-to-apply
  fi

  return 2  # DIRTY — hash matches neither baseline
}

# ─── emit_refuse_artifacts_021 ───────────────────────────────────────────────
# On DIRTY: emit .observability-0021.patch in the project root showing
# the diff between project's cron-monitor.ts and the v1.20.0 template.
# For cf-worker + cf-pages: also append the would-be queue-monitor.ts content.
emit_refuse_artifacts_021() {
  local dir="$1" stack="$2"
  local v20_cm; v20_cm="$(stack_template_dir "$stack")/cron-monitor.ts"
  # Emit to project root (not wrapper dir) to be clearly visible.
  local patch="$PWD/.observability-0021.patch"

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "  (dirty, dry-run) would emit: $patch"
    return
  fi

  {
    echo "# .observability-0021.patch"
    echo "# Generated by migrate-0021-with-cron-and-queue-updates.sh"
    echo "# Stack: $stack"
    echo "# Wrapper root: $dir"
    echo "# cron-monitor.ts diff: your hand-modified version vs v1.20.0 template"
    echo "#"
    echo "# Recovery: see migrations/0021-with-cron-and-queue-updates.md §\"Recovery\""
    echo "# Option 1 (recommended for callbot): drop the LOCAL-PATCH, re-run 0021."
    echo "# Option 2: apply this patch manually to your cron-monitor.ts, then re-run."
    echo "#"
    diff -u "$dir/cron-monitor.ts" "$v20_cm" 2>/dev/null || true
    case "$stack" in
      ts-cloudflare-worker|ts-cloudflare-pages)
        local qm_template; qm_template="$(stack_template_dir "$stack")/queue-monitor.ts"
        if [ -f "$qm_template" ]; then
          echo ""
          echo "# === would-add: queue-monitor.ts ==="
          cat "$qm_template"
        fi
        ;;
    esac
  } > "$patch" 2>/dev/null

  # Idempotently add to .gitignore if one exists
  local gi="$PWD/.gitignore"
  if [ -f "$gi" ]; then
    if ! grep -qF ".observability-0021.patch" "$gi"; then
      printf '\n.observability-0021.patch\n' >> "$gi"
    fi
  fi
}

# ─── apply_root_021 ──────────────────────────────────────────────────────────
apply_root_021() {
  local dir="$1" stack="$2"
  local src; src=$(stack_template_dir "$stack")

  if [ ! -d "$src" ]; then
    warn "  ERROR: no template source for stack '$stack' ($src)"
    return 1
  fi

  case "$stack" in
    ts-cloudflare-worker|ts-cloudflare-pages)
      local cm="$src/cron-monitor.ts" qm="$src/queue-monitor.ts"
      [ -f "$cm" ] || { warn "  ERROR: template cron-monitor.ts missing for $stack"; return 1; }
      [ -f "$qm" ] || { warn "  ERROR: template queue-monitor.ts missing for $stack"; return 1; }
      if [ "$DRY_RUN" -eq 1 ]; then
        info "  (dry-run) would copy: $cm -> $dir/cron-monitor.ts (update)"
        info "  (dry-run) would copy: $qm -> $dir/queue-monitor.ts (add)"
      else
        cp "$cm" "$dir/cron-monitor.ts" || return 1
        cp "$qm" "$dir/queue-monitor.ts" || return 1
        info "  migrated: $dir  (stack: $stack) — updated cron-monitor.ts + added queue-monitor.ts (Migration 0021)"
      fi
      ;;
    ts-supabase-edge)
      # Supabase Edge: update cron-monitor.ts ONLY (no queue-monitor.ts per codex H-6)
      local cm="$src/cron-monitor.ts"
      [ -f "$cm" ] || { warn "  ERROR: template cron-monitor.ts missing for $stack"; return 1; }
      if [ "$DRY_RUN" -eq 1 ]; then
        info "  (dry-run) would copy: $cm -> $dir/cron-monitor.ts (update; D-03 only; no queue-monitor.ts per codex H-6)"
      else
        cp "$cm" "$dir/cron-monitor.ts" || return 1
        info "  migrated: $dir  (stack: $stack) — updated cron-monitor.ts (Migration 0021; no queue-monitor.ts per codex H-6)"
      fi
      ;;
    go-fly-http)
      info "  SKIP: go-fly-http out of scope per Phase 25 D-12"
      ;;
    *)
      info "  SKIP_UNSUPPORTED: $dir  (stack: $stack)"
      ;;
  esac
  return 0
}

# ─── Phase 1: all-clean-gate ─────────────────────────────────────────────────
declare -a CLEAN_DIRS=() CLEAN_STACKS=()
declare -a DIRTY_DIRS=() DIRTY_STACKS=()
declare -a ALREADY_DIRS=()
declare -a SKIP_UNSUPPORTED=()

for dir in "${ROOTS[@]}"; do
  stack=$(classify_stack "$dir")

  case "$stack" in
    unknown)
      SKIP_UNSUPPORTED+=("$dir (unknown wrapper shape)")
      continue
      ;;
    ts-react-vite)
      SKIP_UNSUPPORTED+=("$dir (react-vite — no cron-monitor.ts)")
      continue
      ;;
    go-fly-http)
      # go-fly-http is in-scope for discovery (we want to classify) but out-of-scope
      # for 0021 (D-12). Skip silently — don't bother checking its cron_monitor.go hash.
      SKIP_UNSUPPORTED+=("$dir (go-fly-http — D-12 out of scope for Migration 0021)")
      continue
      ;;
  esac

  # Check if cron-monitor.ts exists (required for re-rev detection)
  if [ ! -f "$dir/cron-monitor.ts" ]; then
    warn "  WARNING: $dir (stack: $stack) has no cron-monitor.ts — project may not have run Migration 0019 yet. Skipping."
    SKIP_UNSUPPORTED+=("$dir (no cron-monitor.ts — run Migration 0019 first)")
    continue
  fi

  is_clean_to_apply_021 "$dir" "$stack"
  case $? in
    0) CLEAN_DIRS+=("$dir");  CLEAN_STACKS+=("$stack") ;;
    1) ALREADY_DIRS+=("$dir") ;;
    2) DIRTY_DIRS+=("$dir");  DIRTY_STACKS+=("$stack") ;;
  esac
done

# ─── DIRTY → REFUSE ──────────────────────────────────────────────────────────
if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  warn "Migration 0021 REFUSE — ${#DIRTY_DIRS[@]} wrapper(s) have hand-modified cron-monitor.ts"
  warn "(canonical hash matches neither v1.19.0 nor v1.20.0 template baseline)"
  for i in "${!DIRTY_DIRS[@]}"; do
    local_dir="${DIRTY_DIRS[$i]}"
    local_stack="${DIRTY_STACKS[$i]}"
    emit_refuse_artifacts_021 "$local_dir" "$local_stack"
    warn "  $local_dir — see .observability-0021.patch"
  done
  warn ""
  warn "Recovery: see migrations/0021-with-cron-and-queue-updates.md §\"Recovery\""
  exit 1
fi

# ─── All already-applied → SKIP_ALREADY ────────────────────────────────────
if [ ${#CLEAN_DIRS[@]} -eq 0 ]; then
  if [ ${#ALREADY_DIRS[@]} -gt 0 ]; then
    info "all ${#ALREADY_DIRS[@]} wrapper(s) already at v1.20.0 — SKIP_ALREADY (codex M-8 twofold idempotency)"
  else
    info "no eligible wrapper roots found — nothing to migrate."
  fi
  bump_version
  exit 0
fi

# ─── Phase 3: apply ──────────────────────────────────────────────────────────
EXIT_CODE=0
for i in "${!CLEAN_DIRS[@]}"; do
  dir="${CLEAN_DIRS[$i]}"; stack="${CLEAN_STACKS[$i]}"
  apply_root_021 "$dir" "$stack" || EXIT_CODE=1
done

# ALREADY roots are skipped silently (already at v1.20.0 per twofold check)

if [ "$EXIT_CODE" -eq 0 ]; then
  bump_version
  info "Migration 0021 complete — version 1.20.0"
else
  warn "Migration 0021 had errors; version NOT bumped"
fi
exit $EXIT_CODE
