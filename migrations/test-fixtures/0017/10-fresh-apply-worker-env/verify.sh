#!/usr/bin/env bash
# Verify fixture 10: a clean cf-worker migrates token-free with each env var
# landing at its OWN site — regression guard for the InitEnv signature collapse.
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"
HASHES="$REPO_ROOT/migrations/test-fixtures/0017/known-wrapper-hashes.json"
ROOT="src/lib/observability"

set +e
bash "$SCRIPT" --templates-dir "$TEMPLATES" --hashes "$HASHES" --project-dir "$PWD" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "clean cf-worker not auto-applied (exit $rc)"; exit 1; }

test -f "$ROOT/destinations/registry.ts" || { echo "registry.ts missing"; exit 1; }
grep -q 'buildRegistry' "$ROOT/index.ts" || { echo "wrapper not registry-dispatched"; exit 1; }
grep -q '{{' "$ROOT/index.ts" && { echo "apply left raw {{tokens}}"; exit 1; }

# Env-var extraction must NOT collapse — each env var at its own usage site.
grep -q 'env.SERVICE_NAME' "$ROOT/index.ts" \
  || { echo "ENV_VAR_SERVICE collapsed — service name reads the wrong env var (signature-collapse bug)"; exit 1; }
grep -q 'env.DEPLOY_ENV' "$ROOT/index.ts" \
  || { echo "ENV_VAR_ENV collapsed — deploy env reads the wrong env var (signature-collapse bug)"; exit 1; }
# InitEnv must declare three DISTINCT fields, not three copies of the DSN var.
DISTINCT=$(grep -E '^  (SENTRY_DSN|DEPLOY_ENV|SERVICE_NAME)\?: string;' "$ROOT/index.ts" | sort -u | wc -l | tr -d ' ')
[ "$DISTINCT" -eq 3 ] || { echo "InitEnv fields collapsed: expected 3 distinct env vars, got $DISTINCT"; exit 1; }

grep -q '^version: 1.16.0$' .claude/skills/agentic-apps-workflow/SKILL.md || { echo "version not bumped"; exit 1; }

echo "fixture 10 OK — clean cf-worker applied token-free with distinct env-var sites"
