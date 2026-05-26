#!/usr/bin/env bash
# Verify fixture 07: realistically-substituted, unmodified wrappers classify
# CLEAN and AUTO-APPLY. Exit 0; adapters added; wrapper registry-dispatched;
# CLAUDE.md bumped; version bumped. This is the proof the canonicalisation fix
# makes the migration apply on REAL projects (not just byte-identical fixtures).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"

GO_ROOT="internal/observability"
REACT_ROOT="src/lib/observability"

# Precondition: wrappers are genuinely SUBSTITUTED (no raw {{TOKENS}}), proving
# we are NOT exercising the byte-identical template path.
for entry in "$GO_ROOT/observability.go" "$REACT_ROOT/index.ts"; do
  grep -q '{{' "$entry" && { echo "precondition: $entry still has raw {{tokens}}"; exit 1; }
done
grep -q 'SENTRY_DSN' "$REACT_ROOT/index.ts" || { echo "precondition: react wrapper not substituted (no SENTRY_DSN)"; exit 1; }
grep -q 'cparx-api'  "$REACT_ROOT/index.ts" || { echo "precondition: react wrapper not substituted (no service name)"; exit 1; }
grep -q 'package observability' "$GO_ROOT/observability.go" || { echo "precondition: go wrapper not substituted (no package name)"; exit 1; }

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "expected script exit 0 (clean auto-apply), got $rc"; exit 1; }

# Go root migrated: destinations.go added.
test -f "$GO_ROOT/destinations.go" || { echo "go destinations.go not copied — substituted wrapper was NOT classified clean"; exit 1; }

# React root migrated: adapters present + wrapper dispatches via registry.
test -f "$REACT_ROOT/destinations/registry.ts" || { echo "react registry.ts missing — substituted wrapper was NOT classified clean"; exit 1; }
test -f "$REACT_ROOT/destinations/sentry.ts"   || { echo "react sentry.ts missing"; exit 1; }
test -f "$REACT_ROOT/destinations/axiom.ts"    || { echo "react axiom.ts missing"; exit 1; }
grep -q 'buildRegistry' "$REACT_ROOT/index.ts" || { echo "react wrapper not registry-dispatched after apply"; exit 1; }

# CLAUDE.md observability block bumped to v0.4.0 + destinations line.
grep -q '^  spec_version: 0.4.0' CLAUDE.md || { echo "CLAUDE.md spec_version not bumped"; exit 1; }
grep -q 'destinations:.*errors: sentry.*logs: axiom' CLAUDE.md || { echo "CLAUDE.md destinations line missing"; exit 1; }

# Version bumped.
grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 07 OK — realistically-substituted clean wrappers classified CLEAN and auto-applied"
