#!/usr/bin/env bash
# run-template-tests.sh — materialize-and-test harness for add-observability templates
#
# Usage:
#   ./run-template-tests.sh <stack-id>   # test one stack
#   ./run-template-tests.sh all          # test all stacks
#
# Stacks: ts-cloudflare-worker | ts-cloudflare-pages | ts-react-vite |
#         ts-supabase-edge | go-fly-http
#
# For each stack the script:
#   1. Creates a temp dir (named WORKDIR, NOT TMPDIR — Go reads $TMPDIR as
#      os.TempDir() and will refuse to treat any dir equal to it as a module root)
#   2. Copies template files to their materialized paths (from meta.yaml target.*)
#      and substitutes {{PARAM}} tokens with harness defaults
#   3. Generates minimal toolchain config into the work dir
#   4. Runs the stack's test suite
#   5. Cleans up on EXIT via trap
#
# Returns non-zero if any tested stack fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR"

# ─── Colour helpers ───────────────────────────────────────────────────────────

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC} $*"; }
fail() { echo -e "${RED}FAIL${NC} $*"; }
info() { echo -e "${YELLOW}INFO${NC} $*"; }

# ─── Token substitution ───────────────────────────────────────────────────────
# substitute_tokens <src> <dst>
#
# Copies <src> to <dst> while replacing all {{PARAM}} tokens with harness
# defaults drawn from each stack's meta.yaml parameters section.
#
# Defaults used:
#   SERVICE_NAME       → test-service
#   DESTINATION        → sentry
#   DEBUG_SAMPLE_RATE  → 0.1
#   TRACE_SAMPLE_RATE  → 0.1
#   REDACTED_KEYS      → inline string list for the array literal
#   ENV_VAR_DSN        → SENTRY_DSN
#   ENV_VAR_ENV        → DEPLOY_ENV
#   ENV_VAR_SERVICE    → SERVICE_NAME
#   PACKAGE_NAME       → observability   (Go only)
#   MODULE_PATH        → obsharness/internal/observability  (Go only)

substitute_tokens() {
  local SRC="$1"
  local DST="$2"
  # TS/Deno array literal: no trailing comma needed (last element before ] is fine)
  local REDACTED_KEYS='"password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token"'
  sed \
    -e 's/{{SERVICE_NAME}}/test-service/g' \
    -e 's/{{DESTINATION}}/sentry/g' \
    -e 's/{{DEBUG_SAMPLE_RATE}}/0.1/g' \
    -e 's/{{TRACE_SAMPLE_RATE}}/0.1/g' \
    -e "s|{{REDACTED_KEYS}}|$REDACTED_KEYS|g" \
    -e 's/{{ENV_VAR_DSN}}/SENTRY_DSN/g' \
    -e 's/{{ENV_VAR_ENV}}/DEPLOY_ENV/g' \
    -e 's/{{ENV_VAR_SERVICE}}/SERVICE_NAME/g' \
    -e 's/{{PACKAGE_NAME}}/observability/g' \
    -e 's|{{MODULE_PATH}}|obsharness/internal/observability|g' \
    "$SRC" > "$DST"
}

substitute_tokens_go() {
  local SRC="$1"
  local DST="$2"
  # Go slice literal: last element before } on the next line MUST have a trailing comma.
  local REDACTED_KEYS='"password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token",'
  sed \
    -e 's/{{SERVICE_NAME}}/test-service/g' \
    -e 's/{{DESTINATION}}/sentry/g' \
    -e 's/{{DEBUG_SAMPLE_RATE}}/0.1/g' \
    -e 's/{{TRACE_SAMPLE_RATE}}/0.1/g' \
    -e "s|{{REDACTED_KEYS}}|$REDACTED_KEYS|g" \
    -e 's/{{ENV_VAR_DSN}}/SENTRY_DSN/g' \
    -e 's/{{ENV_VAR_ENV}}/DEPLOY_ENV/g' \
    -e 's/{{ENV_VAR_SERVICE}}/SERVICE_NAME/g' \
    -e 's/{{PACKAGE_NAME}}/observability/g' \
    -e 's|{{MODULE_PATH}}|obsharness/internal/observability|g' \
    "$SRC" > "$DST"
}

# ─── vitest count parser ──────────────────────────────────────────────────────
# Reads the "  Tests  N passed" summary from vitest stdout; echoes "PASSED FAILED".
parse_vitest_counts() {
  local OUTPUT="$1"
  local PASSED=0 FAILED=0
  local LINE
  LINE=$(echo "$OUTPUT" | grep -E '^\s+Tests\s+[0-9]+ passed' | tail -1 || true)
  if [[ -n "$LINE" ]]; then
    PASSED=$(echo "$LINE" | grep -oE '[0-9]+ passed' | grep -oE '^[0-9]+' || echo "0")
    local F
    F=$(echo "$LINE" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+' || echo "0")
    FAILED="$F"
  fi
  echo "$PASSED $FAILED"
}

# ─── Stack runner: ts-cloudflare-worker ──────────────────────────────────────

run_ts_cloudflare_worker() {
  local STACK="ts-cloudflare-worker"
  local SRC="$TEMPLATES_DIR/$STACK"
  local WORKDIR
  WORKDIR="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  info "[$STACK] materializing into $WORKDIR"

  # Materialized paths (meta.yaml target.*):
  #   lib-observability.ts      → src/lib/observability/index.ts
  #   middleware.ts             → src/lib/observability/middleware.ts
  #   lib-observability.test.ts → src/lib/observability/index.test.ts
  local OBS_DIR="$WORKDIR/src/lib/observability"
  mkdir -p "$OBS_DIR"
  substitute_tokens "$SRC/lib-observability.ts"      "$OBS_DIR/index.ts"
  substitute_tokens "$SRC/middleware.ts"              "$OBS_DIR/middleware.ts"
  substitute_tokens "$SRC/lib-observability.test.ts" "$OBS_DIR/index.test.ts"

  # Phase 22 — Sentry Crons wrapper (T02 GREEN).
  # cron-monitor.ts holds the implementation; cron-monitor.test.ts holds the
  # contract suite. No existence gates per PLAN R02 — the runner materializes
  # both unconditionally because they're now part of the worker template's
  # canonical file set.
  substitute_tokens "$SRC/cron-monitor.ts"          "$OBS_DIR/cron-monitor.ts"
  substitute_tokens "$SRC/cron-monitor.test.ts"     "$OBS_DIR/cron-monitor.test.ts"

  # Phase 22 — healthz snippet (T06). COPY-ONLY template (D9): operator copies
  # into routes layer + adapts probes. Materialized with cron-monitor pair so
  # the in-repo contract suite catches regressions at template-edit time.
  # T18/R12: existence gates removed — files are part of the canonical set now.
  substitute_tokens "$SRC/healthz-snippet.test.ts" "$OBS_DIR/healthz-snippet.test.ts"
  substitute_tokens "$SRC/healthz-snippet.ts"      "$OBS_DIR/healthz-snippet.ts"

  # Phase 24 — recordLLMResponseMeta helper (T24.1.1). Test file wired in RED;
  # impl file wired in GREEN (TDD discipline per workflow skill).
  substitute_tokens "$SRC/llm-response-meta.test.ts" "$OBS_DIR/llm-response-meta.test.ts"
  substitute_tokens "$SRC/llm-response-meta.ts"      "$OBS_DIR/llm-response-meta.ts"

  # destinations/ sub-dir (role-based registry + adapters, phase 21).
  # Copy every .ts file (registry, adapters, and their tests) into the
  # materialized destinations/ dir so the registry tests run.
  if [[ -d "$SRC/destinations" ]]; then
    local DEST_DIR="$OBS_DIR/destinations"
    mkdir -p "$DEST_DIR"
    for f in "$SRC/destinations"/*.ts; do
      [[ -f "$f" ]] || continue
      substitute_tokens "$f" "$DEST_DIR/$(basename "$f")"
    done
  fi

  cat > "$WORKDIR/package.json" << 'PKGJSON'
{
  "name": "obs-harness-ts-cloudflare-worker",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "devDependencies": {
    "vitest": "^3.0.0"
  },
  "dependencies": {
    "@sentry/cloudflare": "^8.0.0"
  }
}
PKGJSON

  cat > "$WORKDIR/tsconfig.json" << 'TSCFG'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "lib": ["ES2022"]
  }
}
TSCFG

  cat > "$WORKDIR/vitest.config.ts" << 'VITCFG'
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { environment: "node" } });
VITCFG

  info "[$STACK] npm install..."
  local SETUP_OUT SETUP_EXIT=0
  SETUP_OUT=$(cd "$WORKDIR" && npm install --no-fund --no-audit --loglevel=error 2>&1) || SETUP_EXIT=$?
  if [[ $SETUP_EXIT -ne 0 ]]; then
    fail "[$STACK] npm install failed (exit $SETUP_EXIT)"
    echo "$SETUP_OUT" | tail -20
    trap - EXIT; rm -rf "$WORKDIR"
    return 1
  fi

  info "[$STACK] vitest run..."
  local OUTPUT EXIT_CODE=0
  OUTPUT=$(cd "$WORKDIR" && npx vitest run 2>&1) || EXIT_CODE=$?

  local COUNTS PASSED FAILED
  COUNTS=$(parse_vitest_counts "$OUTPUT")
  PASSED=$(echo "$COUNTS" | awk '{print $1}')
  FAILED=$(echo "$COUNTS" | awk '{print $2}')

  if [[ $EXIT_CODE -eq 0 ]]; then
    pass "[$STACK] ${PASSED} tests passed"
    echo "$OUTPUT" | grep -E 'Tests |Test Files' | tail -5 || true
  else
    fail "[$STACK] tests FAILED (exit $EXIT_CODE)"
    echo "$OUTPUT" | tail -50
  fi

  trap - EXIT
  rm -rf "$WORKDIR"
  return $EXIT_CODE
}

# ─── Stack runner: ts-cloudflare-pages ───────────────────────────────────────

run_ts_cloudflare_pages() {
  local STACK="ts-cloudflare-pages"
  local SRC="$TEMPLATES_DIR/$STACK"
  local WORKDIR
  WORKDIR="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  info "[$STACK] materializing into $WORKDIR"

  # Materialized paths (meta.yaml target.*):
  #   lib-observability.ts      → functions/_lib/observability/index.ts
  #   _middleware.ts            → functions/_middleware.ts
  #   lib-observability.test.ts → functions/_lib/observability/index.test.ts
  #
  # Pages Functions run on the Workers runtime; the wrapper module is identical
  # in shape to ts-cloudflare-worker (env arg + ctx.waitUntil + @sentry/cloudflare).
  local OBS_DIR="$WORKDIR/functions/_lib/observability"
  mkdir -p "$OBS_DIR"
  substitute_tokens "$SRC/lib-observability.ts"      "$OBS_DIR/index.ts"
  substitute_tokens "$SRC/lib-observability.test.ts" "$OBS_DIR/index.test.ts"

  # Phase 22 — Sentry Crons wrapper (T03 GREEN). Pages variant: no scheduled
  # handler signature; wrapper accepts a generic () => Promise<R> per D5c.
  # Materialized unconditionally as part of the pages template's canonical
  # file set.
  substitute_tokens "$SRC/cron-monitor.ts"          "$OBS_DIR/cron-monitor.ts"
  substitute_tokens "$SRC/cron-monitor.test.ts"     "$OBS_DIR/cron-monitor.test.ts"

  # Phase 22 — healthz snippet (T07). Pages variant: PagesFunction export
  # of `onRequest` instead of a bare handler. COPY-ONLY template per D9.
  # T18/R12: existence gates removed — files are part of the canonical set now.
  substitute_tokens "$SRC/healthz-snippet.test.ts" "$OBS_DIR/healthz-snippet.test.ts"
  substitute_tokens "$SRC/healthz-snippet.ts"      "$OBS_DIR/healthz-snippet.ts"

  # Phase 24 — recordLLMResponseMeta helper (T24.1.2). Test wired in RED;
  # impl in GREEN. Byte-identical to worker stack.
  substitute_tokens "$SRC/llm-response-meta.test.ts" "$OBS_DIR/llm-response-meta.test.ts"

  # destinations/ sub-dir (role-based registry + adapters, phase 21).
  if [[ -d "$SRC/destinations" ]]; then
    local DEST_DIR="$OBS_DIR/destinations"
    mkdir -p "$DEST_DIR"
    for f in "$SRC/destinations"/*.ts; do
      [[ -f "$f" ]] || continue
      substitute_tokens "$f" "$DEST_DIR/$(basename "$f")"
    done
  fi

  cat > "$WORKDIR/package.json" << 'PKGJSON'
{
  "name": "obs-harness-ts-cloudflare-pages",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "devDependencies": {
    "vitest": "^3.0.0"
  },
  "dependencies": {
    "@sentry/cloudflare": "^8.0.0"
  }
}
PKGJSON

  cat > "$WORKDIR/tsconfig.json" << 'TSCFG'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true,
    "lib": ["ES2022"]
  }
}
TSCFG

  cat > "$WORKDIR/vitest.config.ts" << 'VITCFG'
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { environment: "node" } });
VITCFG

  info "[$STACK] npm install..."
  local SETUP_OUT SETUP_EXIT=0
  SETUP_OUT=$(cd "$WORKDIR" && npm install --no-fund --no-audit --loglevel=error 2>&1) || SETUP_EXIT=$?
  if [[ $SETUP_EXIT -ne 0 ]]; then
    fail "[$STACK] npm install failed (exit $SETUP_EXIT)"
    echo "$SETUP_OUT" | tail -20
    trap - EXIT; rm -rf "$WORKDIR"
    return 1
  fi

  info "[$STACK] vitest run..."
  local OUTPUT EXIT_CODE=0
  OUTPUT=$(cd "$WORKDIR" && npx vitest run 2>&1) || EXIT_CODE=$?

  local COUNTS PASSED FAILED
  COUNTS=$(parse_vitest_counts "$OUTPUT")
  PASSED=$(echo "$COUNTS" | awk '{print $1}')
  FAILED=$(echo "$COUNTS" | awk '{print $2}')

  if [[ $EXIT_CODE -eq 0 ]]; then
    pass "[$STACK] ${PASSED} tests passed"
    echo "$OUTPUT" | grep -E 'Tests |Test Files' | tail -5 || true
  else
    fail "[$STACK] tests FAILED (exit $EXIT_CODE)"
    echo "$OUTPUT" | tail -50
  fi

  trap - EXIT
  rm -rf "$WORKDIR"
  return $EXIT_CODE
}

# ─── Stack runner: ts-react-vite ─────────────────────────────────────────────

run_ts_react_vite() {
  local STACK="ts-react-vite"
  local SRC="$TEMPLATES_DIR/$STACK"
  local WORKDIR
  WORKDIR="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  info "[$STACK] materializing into $WORKDIR"

  # Materialized paths (meta.yaml target.*):
  #   lib-observability.ts      → src/lib/observability/index.ts
  #   ErrorBoundary.tsx         → src/lib/observability/ErrorBoundary.tsx
  #   lib-observability.test.ts → src/lib/observability/index.test.ts
  local OBS_DIR="$WORKDIR/src/lib/observability"
  mkdir -p "$OBS_DIR"
  substitute_tokens "$SRC/lib-observability.ts"      "$OBS_DIR/index.ts"
  substitute_tokens "$SRC/ErrorBoundary.tsx"          "$OBS_DIR/ErrorBoundary.tsx"
  substitute_tokens "$SRC/lib-observability.test.ts" "$OBS_DIR/index.test.ts"
  # Phase-21 axiom role-dispatch + browser-no-token suite.
  if [[ -f "$SRC/axiom.test.ts" ]]; then
    substitute_tokens "$SRC/axiom.test.ts" "$OBS_DIR/axiom.test.ts"
  fi

  # destinations/ sub-dir (role-based registry + adapters, phase 21).
  if [[ -d "$SRC/destinations" ]]; then
    local DEST_DIR="$OBS_DIR/destinations"
    mkdir -p "$DEST_DIR"
    for f in "$SRC/destinations"/*.ts; do
      [[ -f "$f" ]] || continue
      substitute_tokens "$f" "$DEST_DIR/$(basename "$f")"
    done
  fi

  cat > "$WORKDIR/package.json" << 'PKGJSON'
{
  "name": "obs-harness-ts-react-vite",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "devDependencies": {
    "vitest": "^3.0.0",
    "jsdom": "^25.0.0"
  },
  "dependencies": {
    "@sentry/react": "^8.0.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0"
  }
}
PKGJSON

  cat > "$WORKDIR/tsconfig.json" << 'TSCFG'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "lib": ["ES2022", "DOM"]
  }
}
TSCFG

  cat > "$WORKDIR/vitest.config.ts" << 'VITCFG'
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { environment: "jsdom" } });
VITCFG

  info "[$STACK] npm install..."
  local SETUP_OUT SETUP_EXIT=0
  SETUP_OUT=$(cd "$WORKDIR" && npm install --no-fund --no-audit --loglevel=error 2>&1) || SETUP_EXIT=$?
  if [[ $SETUP_EXIT -ne 0 ]]; then
    fail "[$STACK] npm install failed (exit $SETUP_EXIT)"
    echo "$SETUP_OUT" | tail -20
    trap - EXIT; rm -rf "$WORKDIR"
    return 1
  fi

  info "[$STACK] vitest run..."
  local OUTPUT EXIT_CODE=0
  OUTPUT=$(cd "$WORKDIR" && npx vitest run 2>&1) || EXIT_CODE=$?

  local COUNTS PASSED FAILED
  COUNTS=$(parse_vitest_counts "$OUTPUT")
  PASSED=$(echo "$COUNTS" | awk '{print $1}')
  FAILED=$(echo "$COUNTS" | awk '{print $2}')

  if [[ $EXIT_CODE -eq 0 ]]; then
    pass "[$STACK] ${PASSED} tests passed"
    echo "$OUTPUT" | grep -E 'Tests |Test Files' | tail -5 || true
  else
    fail "[$STACK] tests FAILED (exit $EXIT_CODE)"
    echo "$OUTPUT" | tail -50
  fi

  trap - EXIT
  rm -rf "$WORKDIR"
  return $EXIT_CODE
}

# ─── Stack runner: ts-supabase-edge ──────────────────────────────────────────

run_ts_supabase_edge() {
  local STACK="ts-supabase-edge"
  local SRC="$TEMPLATES_DIR/$STACK"
  local WORKDIR
  WORKDIR="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  info "[$STACK] materializing into $WORKDIR"

  # Materialized paths (meta.yaml target.*):
  #   index.ts      → supabase/functions/_shared/observability/index.ts
  #   middleware.ts → supabase/functions/_shared/observability/middleware.ts
  #   index.test.ts → supabase/functions/_shared/observability/index.test.ts
  local OBS_DIR="$WORKDIR/supabase/functions/_shared/observability"
  mkdir -p "$OBS_DIR"
  substitute_tokens "$SRC/index.ts"      "$OBS_DIR/index.ts"
  substitute_tokens "$SRC/middleware.ts"  "$OBS_DIR/middleware.ts"
  # Phase 22 — Sentry Crons wrapper (T04 GREEN). cron-monitor.ts holds the
  # implementation that cron-monitor.test.ts (covered by the *.test.ts glob
  # below) imports. No existence gate per PLAN R02.
  substitute_tokens "$SRC/cron-monitor.ts" "$OBS_DIR/cron-monitor.ts"

  # Phase 22 — healthz snippet (T08). COPY-ONLY template (D9). Impl is
  # `.ts` (not `.test.ts`) so the test-glob below misses it — explicit
  # copy. The test file IS picked up by the *.test.ts glob.
  # T18/R12: existence gate removed — file is part of the canonical set now.
  substitute_tokens "$SRC/healthz-snippet.ts" "$OBS_DIR/healthz-snippet.ts"

  # Copy every *.test.ts (index contract suite + phase-21 axiom suite +
  # phase-22 cron-monitor suite + phase-22 healthz-snippet suite).
  for f in "$SRC"/*.test.ts; do
    [[ -f "$f" ]] || continue
    substitute_tokens "$f" "$OBS_DIR/$(basename "$f")"
  done

  # destinations/ sub-dir (role-based registry + adapters, phase 21).
  if [[ -d "$SRC/destinations" ]]; then
    local DEST_DIR="$OBS_DIR/destinations"
    mkdir -p "$DEST_DIR"
    for f in "$SRC/destinations"/*.ts; do
      [[ -f "$f" ]] || continue
      substitute_tokens "$f" "$DEST_DIR/$(basename "$f")"
    done
  fi

  cat > "$WORKDIR/deno.json" << 'DENOJSON'
{
  "compilerOptions": {
    "lib": ["ES2022", "deno.ns"],
    "strict": true
  },
  "nodeModulesDir": "auto"
}
DENOJSON

  info "[$STACK] deno test..."
  local OUTPUT EXIT_CODE=0
  OUTPUT=$(cd "$WORKDIR" && deno test -A --no-check "$OBS_DIR"/*.test.ts 2>&1) || EXIT_CODE=$?

  # Deno summary: "ok | N passed | 0 failed | ..."
  local PASSED=0 FAILED=0
  local PS FS
  PS=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '^[0-9]+' || echo "0")
  FS=$(echo "$OUTPUT" | grep -oE '[0-9]+ failed' | tail -1 | grep -oE '^[0-9]+' || echo "0")
  PASSED="${PS:-0}"
  FAILED="${FS:-0}"

  if [[ $EXIT_CODE -eq 0 ]]; then
    pass "[$STACK] ${PASSED} tests passed"
    echo "$OUTPUT" | tail -5
  else
    fail "[$STACK] tests FAILED (exit $EXIT_CODE)"
    echo "$OUTPUT" | tail -50
  fi

  trap - EXIT
  rm -rf "$WORKDIR"
  return $EXIT_CODE
}

# ─── Stack runner: go-fly-http ────────────────────────────────────────────────

run_go_fly_http() {
  local STACK="go-fly-http"
  local SRC="$TEMPLATES_DIR/$STACK"
  local WORKDIR
  # NOTE: Do NOT name this variable TMPDIR. On macOS, $TMPDIR is an exported
  # env var; a bash 'local TMPDIR=...' will propagate the new value to child
  # processes (since the env var is already exported). Go's os.TempDir() reads
  # $TMPDIR, and Go refuses to build a module whose root equals os.TempDir().
  # Using a different variable name avoids the collision entirely.
  WORKDIR="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$WORKDIR'" EXIT

  info "[$STACK] materializing into $WORKDIR"

  # Materialized paths (meta.yaml target.*):
  #   observability.go      → internal/observability/observability.go
  #   middleware.go         → internal/observability/middleware.go
  #   observability_test.go → internal/observability/observability_test.go
  #
  # {{PACKAGE_NAME}} → observability  (meta.yaml parameters.PACKAGE_NAME default)
  local OBS_DIR="$WORKDIR/internal/observability"
  mkdir -p "$OBS_DIR"
  # Copy every *.go file (wrapper, middleware, destinations layer, and their
  # _test.go suites) so the destinations registry/adapter tests added in
  # phase 21 (destinations.go / destinations_test.go) run alongside the
  # baseline observability suite. go test ./... covers them all in one package.
  for f in "$SRC"/*.go; do
    [[ -f "$f" ]] || continue
    substitute_tokens_go "$f" "$OBS_DIR/$(basename "$f")"
  done

  cat > "$WORKDIR/go.mod" << 'GOMOD'
module obsharness

go 1.22

require github.com/getsentry/sentry-go v0.31.0
GOMOD

  info "[$STACK] go mod tidy..."
  local SETUP_OUT SETUP_EXIT=0
  SETUP_OUT=$(cd "$WORKDIR" && go mod tidy 2>&1) || SETUP_EXIT=$?
  if [[ $SETUP_EXIT -ne 0 ]]; then
    fail "[$STACK] go mod tidy failed (exit $SETUP_EXIT)"
    echo "$SETUP_OUT" | tail -20
    trap - EXIT; rm -rf "$WORKDIR"
    return 1
  fi

  info "[$STACK] go test..."
  local OUTPUT EXIT_CODE=0
  OUTPUT=$(cd "$WORKDIR" && go test ./... -v 2>&1) || EXIT_CODE=$?

  local PASSED FAILED
  PASSED=$(echo "$OUTPUT" | grep -c '^--- PASS' || echo "0")
  FAILED=$(echo "$OUTPUT" | grep -c '^--- FAIL' || echo "0")

  if [[ $EXIT_CODE -eq 0 ]]; then
    pass "[$STACK] ${PASSED} tests passed"
    echo "$OUTPUT" | grep -E '^(ok|FAIL|---) ' | tail -20 || true
  else
    fail "[$STACK] tests FAILED (exit $EXIT_CODE)"
    echo "$OUTPUT" | tail -50
  fi

  trap - EXIT
  rm -rf "$WORKDIR"
  return $EXIT_CODE
}

# ─── Dispatcher ───────────────────────────────────────────────────────────────

run_stack() {
  local STACK="$1"
  case "$STACK" in
    ts-cloudflare-worker) run_ts_cloudflare_worker ;;
    ts-cloudflare-pages)  run_ts_cloudflare_pages ;;
    ts-react-vite)        run_ts_react_vite ;;
    ts-supabase-edge)     run_ts_supabase_edge ;;
    go-fly-http)          run_go_fly_http ;;
    *)
      echo "Unknown stack: $STACK"
      echo "Valid stacks: ts-cloudflare-worker ts-cloudflare-pages ts-react-vite ts-supabase-edge go-fly-http"
      exit 1
      ;;
  esac
}

# ─── Phase 22 / T18 / R12 — structural assertion: withCronMonitor export presence
#
# Asserts each of the 4 phase-22 stacks ships a `cron-monitor.{ts,go}` file
# carrying the expected export. Catches a regression where an editor deletes
# the impl while leaving the test file in place (the test would compile-fail
# with an unrelated error; this assertion gives a clear top-of-run failure).
#
# Worker / pages / supabase-edge: `export function withCronMonitor`
# Go: `func WithCronMonitor`
# ──────────────────────────────────────────────────────────────────────────────
TEMPLATES_ROOT="$SCRIPT_DIR"
EXPECTED_TS_CRON_MONITORS=(
  "$TEMPLATES_ROOT/ts-cloudflare-worker/cron-monitor.ts"
  "$TEMPLATES_ROOT/ts-cloudflare-pages/cron-monitor.ts"
  "$TEMPLATES_ROOT/ts-supabase-edge/cron-monitor.ts"
)
EXPECTED_GO_CRON_MONITOR="$TEMPLATES_ROOT/go-fly-http/cron_monitor.go"
ASSERTION_FAILED=0
for f in "${EXPECTED_TS_CRON_MONITORS[@]}"; do
  if ! grep -q "export function withCronMonitor" "$f" 2>/dev/null; then
    fail "T18 export-presence: missing 'export function withCronMonitor' in $f"
    ASSERTION_FAILED=1
  fi
done
if ! grep -q "func WithCronMonitor" "$EXPECTED_GO_CRON_MONITOR" 2>/dev/null; then
  fail "T18 export-presence: missing 'func WithCronMonitor' in $EXPECTED_GO_CRON_MONITOR"
  ASSERTION_FAILED=1
fi
if [[ $ASSERTION_FAILED -ne 0 ]]; then
  fail "T18 structural assertion failed — refusing to run stack tests"
  exit 1
fi

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <stack-id|all>"
  echo "Stacks: ts-cloudflare-worker ts-cloudflare-pages ts-react-vite ts-supabase-edge go-fly-http"
  exit 1
fi

TARGET="$1"

if [[ "$TARGET" == "all" ]]; then
  OVERALL_EXIT=0
  ALL_STACKS=(ts-cloudflare-worker ts-cloudflare-pages ts-react-vite ts-supabase-edge go-fly-http)
  for STACK in "${ALL_STACKS[@]}"; do
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo " Stack: $STACK"
    echo "══════════════════════════════════════════════════════════════"
    run_stack "$STACK" || OVERALL_EXIT=1
  done
  echo ""
  echo "══════════════════════════════════════════════════════════════"
  if [[ $OVERALL_EXIT -eq 0 ]]; then
    pass "All stacks passed (or pending)"
  else
    fail "One or more stacks FAILED"
  fi
  exit $OVERALL_EXIT
else
  run_stack "$TARGET"
fi
