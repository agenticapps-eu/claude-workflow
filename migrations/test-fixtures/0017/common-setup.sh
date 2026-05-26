#!/usr/bin/env bash
# Sourced by individual fixture setup.sh scripts for migration 0017.
# Builds a sandboxed downstream-project skeleton in the CWD ($tmp), at workflow
# v1.15.0, ready for the 0017 apply engine. Per-fixture setup.sh layers the
# specific wrapper roots (clean / hand-modified / already-applied) on top.
#
# Env provided by the harness:
#   REPO_ROOT      — claude-workflow repo root
#   FIXTURES_ROOT  — migrations/test-fixtures/0017
#
# Helpers exported for fixture setup.sh use:
#   materialize_clean_worker <root-dir>     — un-modified cf-worker wrapper (main bytes)
#   materialize_clean_react  <root-dir>     — un-modified react-vite wrapper
#   materialize_clean_go     <root-dir>     — un-modified go-fly-http wrapper
#   materialize_dirty_worker <root-dir>     — hand-modified cf-worker wrapper (hash mismatch)
#   materialize_applied_worker <root-dir>   — already-migrated cf-worker root
set -eu

# 1. Project SKILL.md at v1.15.0 (the from_version for 0017).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF'
---
name: agentic-apps-workflow
version: 1.15.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0017
---
EOF

# 2. Materialise an UN-MODIFIED wrapper for a stack into <root-dir> by copying
#    the exact OLD (main-branch) template bytes. These byte-match the baseline
#    hashes in known-wrapper-hashes.json, so the apply engine classifies them
#    CLEAN. (Real projects substitute generator tokens; the engine canonicalises
#    before hashing. Fixtures keep the template form for a hermetic exact match.)
_main_wrapper() {
  # $1=stack  $2=template-wrapper-file  $3=dest-abs-path
  mkdir -p "$(dirname "$3")"
  git -C "$REPO_ROOT" show "main:add-observability/templates/$1/$2" > "$3"
}

materialize_clean_worker() { _main_wrapper ts-cloudflare-worker lib-observability.ts "$1/index.ts"; }
materialize_clean_react()  { _main_wrapper ts-react-vite        lib-observability.ts "$1/index.ts"; }
materialize_clean_go()     { _main_wrapper go-fly-http          observability.go     "$1/observability.go"; }

# Hand-modified: clean wrapper + an extra hand-added line → hash mismatch.
materialize_dirty_worker() {
  materialize_clean_worker "$1"
  printf '\n// HAND-EDIT: bespoke local tweak by the project owner\n' >> "$1/index.ts"
}

# Already-applied: a migrated cf-worker root (registry imported + adapters present).
materialize_applied_worker() {
  mkdir -p "$1/destinations"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$1/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/registry.ts" "$1/destinations/registry.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/sentry.ts"   "$1/destinations/sentry.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/axiom.ts"    "$1/destinations/axiom.ts"
}

# 3. A v0.3.0-shape observability: block in CLAUDE.md (the anchor-managed range
#    0017 rewrites to v0.4.0). Fixture 06 deletes this to exercise the stub path.
cat > CLAUDE.md <<'EOF'
# Downstream project CLAUDE.md (0017 fixture)

Some project preamble.

observability:
  spec_version: 0.3.0
  policy: src/lib/observability/policy.md
  enforcement: { baseline: .observability/baseline.json }

## Other section
Content after the observability block.
EOF
