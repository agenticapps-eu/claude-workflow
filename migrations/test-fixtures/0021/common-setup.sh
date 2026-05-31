#!/usr/bin/env bash
# Sourced by 0021 fixture setup.sh. Builds a downstream-project skeleton
# in the CWD at v1.19.0 (post-0019 state): cron-monitor.ts + healthz-snippet.ts
# already installed (using FROZEN baseline files per codex M-1, NOT cp from
# add-observability/templates/ which Plan 03 mutates).
# queue-monitor.ts absent — what 0021 adds.
set -eu

BASELINES_V1_19_0="$REPO_ROOT/migrations/test-fixtures/0021/baselines/v1.19.0"

mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF'
---
name: agentic-apps-workflow
version: 1.19.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0021
---
EOF

# Post-0019 v1.19.0 cf-worker wrapper. cron-monitor.ts cp'd from FROZEN baseline.
# Other files (lib-observability.ts → index.ts; middleware.ts; healthz-snippet.ts)
# cp from live templates — they don't drift in Plan 03's scope.
seed_v1_19_0_worker() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$dir/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/middleware.ts"        "$dir/middleware.ts"
  cp "$BASELINES_V1_19_0/ts-cloudflare-worker/cron-monitor.ts"                          "$dir/cron-monitor.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"   "$dir/healthz-snippet.ts"
}

seed_v1_19_0_pages() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/lib-observability.ts" "$dir/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/_middleware.ts"       "$dir/_middleware.ts"
  cp "$BASELINES_V1_19_0/ts-cloudflare-pages/cron-monitor.ts"                          "$dir/cron-monitor.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-pages/healthz-snippet.ts"   "$dir/healthz-snippet.ts"
}

seed_v1_19_0_supabase() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-supabase-edge/index.ts"           "$dir/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-supabase-edge/middleware.ts"      "$dir/middleware.ts"
  cp "$BASELINES_V1_19_0/ts-supabase-edge/cron-monitor.ts"                        "$dir/cron-monitor.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-supabase-edge/healthz-snippet.ts" "$dir/healthz-snippet.ts"
}

# Seed a v1.20.0 wrapper (post-Plan-05 state): cron-monitor.ts cp'd from
# the LIVE post-Plan-03 template (which IS the v1.20.0 baseline), plus
# queue-monitor.ts cp'd from the live template (cf-worker/cf-pages only).
# Used by fixture 03 (already-1.20.0-skip).
seed_v1_20_0_worker() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$dir/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/middleware.ts"        "$dir/middleware.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/cron-monitor.ts"      "$dir/cron-monitor.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/healthz-snippet.ts"   "$dir/healthz-snippet.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/queue-monitor.ts"     "$dir/queue-monitor.ts"
}
