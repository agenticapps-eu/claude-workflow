#!/usr/bin/env bash
# Sourced by individual fixture setup.sh scripts for migration 0019.
# Builds a sandboxed downstream-project skeleton in the CWD ($tmp), at workflow
# v1.17.0, ready for the 0019 apply engine. Per-fixture setup.sh layers the
# specific wrapper roots (clean / hand-modified / already-applied) on top.
#
# Env provided by the harness:
#   REPO_ROOT      — claude-workflow repo root
#   FIXTURES_ROOT  — migrations/test-fixtures/0019
#
# Helpers exported for fixture setup.sh use:
#   seed_clean_worker  <root-dir>   — un-modified v1.17.0 cf-worker fingerprint
#   seed_clean_pages   <root-dir>   — un-modified v1.17.0 cf-pages fingerprint
#   seed_clean_supabase <root-dir>  — un-modified v1.17.0 supabase-edge fingerprint
#   seed_clean_go      <root-dir>   — un-modified v1.17.0 go-fly-http fingerprint
#   seed_clean_react   <root-dir>   — un-modified v1.17.0 react-vite fingerprint (D10 skip)
#   seed_dirty_worker  <root-dir>   — clean worker fingerprint + hand-edit on middleware.ts
#
# Each "seed" helper copies ONLY the v1.17.0 fingerprint files the engine
# checks (lib-observability.ts + middleware.ts for worker, etc.) — explicitly
# NOT cron-monitor.{ts,go} / healthz-snippet.{ts,go} (those are what 0019
# installs; pre-existing them would make the wrapper already-applied) and NOT
# the *.test.ts companions (test scaffolds are template-only).
set -eu

# 1. Project SKILL.md at v1.17.0 (the from_version for 0019).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF'
---
name: agentic-apps-workflow
version: 1.17.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0019
---
EOF

# 2. Materialise an UN-MODIFIED v1.17.0 wrapper for a stack into <root-dir>.
#    Copies the production-source bytes verbatim. The engine canonicalises both
#    the project wrapper and the source-of-truth baseline through the same
#    masking awk; byte-identical inputs yield byte-identical canonical hashes →
#    CLEAN classification.
seed_clean_worker() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$dir/lib-observability.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/middleware.ts"        "$dir/middleware.ts"
}

seed_clean_pages() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/lib-observability.ts" "$dir/lib-observability.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/_middleware.ts"       "$dir/_middleware.ts"
}

# Supabase-edge canonical layout: <something>/_shared/observability/{index.ts,middleware.ts}
seed_clean_supabase() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-supabase-edge/index.ts"      "$dir/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-supabase-edge/middleware.ts" "$dir/middleware.ts"
}

seed_clean_go() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/go-fly-http/observability.go" "$dir/observability.go"
  cp "$REPO_ROOT/add-observability/templates/go-fly-http/middleware.go"    "$dir/middleware.go"
}

# React-vite v1.17.0 wrapper: lib-observability.ts + ErrorBoundary.tsx. The
# engine classifies this as ts-react-vite and SKIP_UNSUPPORTED-s it (D10).
seed_clean_react() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-react-vite/lib-observability.ts" "$dir/lib-observability.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-react-vite/ErrorBoundary.tsx"    "$dir/ErrorBoundary.tsx"
}

# Hand-modified: clean cf-worker fingerprint with a bespoke comment line
# appended to middleware.ts → canonical hash diverges → DIRTY.
seed_dirty_worker() {
  local dir="$1"
  seed_clean_worker "$dir"
  printf '\n// HAND-MODIFIED — should refuse (0019 fixture)\n' >> "$dir/middleware.ts"
}
