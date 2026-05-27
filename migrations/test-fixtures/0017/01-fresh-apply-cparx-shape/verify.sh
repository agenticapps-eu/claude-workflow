#!/usr/bin/env bash
# Verify fixture 01: both clean roots migrated, CLAUDE.md v0.4.0, exit 0.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0, got $rc"; exit 1; }

# Go root migrated: destinations.go present + wrapper imports registry.
test -f internal/observability/destinations.go \
  || { echo "go destinations.go not copied"; exit 1; }

# React root migrated: destinations/ adapters present + wrapper dispatches via registry.
test -f src/lib/observability/destinations/registry.ts || { echo "react registry.ts missing"; exit 1; }
test -f src/lib/observability/destinations/sentry.ts   || { echo "react sentry.ts missing"; exit 1; }
test -f src/lib/observability/destinations/axiom.ts    || { echo "react axiom.ts missing"; exit 1; }
grep -q 'buildRegistry' src/lib/observability/index.ts || { echo "react wrapper not registry-dispatched"; exit 1; }

# Bug #1 — apply must MATERIALISE generator tokens, never ship a raw template.
for f in src/lib/observability/index.ts \
         src/lib/observability/destinations/registry.ts \
         src/lib/observability/destinations/sentry.ts \
         src/lib/observability/destinations/axiom.ts \
         internal/observability/observability.go \
         internal/observability/destinations.go; do
  [ -f "$f" ] && grep -q '{{' "$f" && { echo "apply left raw {{tokens}} in $f"; exit 1; }
done
# Bug #1 — the project's real values are preserved (sample rate 0.05, not a default).
grep -q 'const TRACE_SAMPLE_RATE = 0.05;' src/lib/observability/index.ts \
  || { echo "react TRACE_SAMPLE_RATE (0.05) not preserved through migration"; exit 1; }

# CLAUDE.md observability block bumped to v0.4.0 + destinations line added.
grep -q '^  spec_version: 0.4.0' CLAUDE.md || { echo "CLAUDE.md spec_version not bumped"; exit 1; }
grep -q 'destinations:.*errors: sentry.*logs: axiom' CLAUDE.md || { echo "CLAUDE.md destinations line missing"; exit 1; }

# Version bumped.
grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 01 OK — both roots migrated, CLAUDE.md v0.4.0"
