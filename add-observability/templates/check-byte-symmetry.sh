#!/usr/bin/env bash
# check-byte-symmetry.sh — TOKEN-SUBSTITUTED byte-symmetry check for the Phase 25 D-21 /
# Phase 26 SC-9 contract pair:
#   ts-cloudflare-worker/lib-observability.ts  <->  openrouter-monitor/src/observability/index.ts
#
# The cf-worker file is a token TEMPLATE ({{TOKENS}}); openrouter is the baked-literal
# resolution. A raw `diff -q` is non-empty BY DESIGN. This script substitutes the tokens to
# cf-worker's openrouter-equivalent resolution and emits the resulting diff to STDOUT.
#
# Usage:
#   bash check-byte-symmetry.sh            # prints the substituted diff (empty == perfect symmetry)
#   bash check-byte-symmetry.sh --snapshot # writes the diff to .byte-symmetry.snapshot for before/after comparison
#
# Phase 27 NOTE (WR-04): there is a KNOWN pre-existing comment-prose drift at the
# `(b) extend InitEnv ... SENTRY_RELEASE` block (cf-worker says "+ meta.yaml with a dedicated
# ... token"; openrouter says "with a dedicated ... field"). This is NOT token-substitutable
# and predates Phase 27. WR-04 edits src/index.ts (the ENTRY, NOT this pair), so the correct
# invariant is: the substituted diff is UNCHANGED by WR-04. Use --snapshot before WR-04 and a
# plain run after, then `diff` the two outputs — they must be identical. The residual comment
# drift is flagged for a future cleanup (the pair files are frozen during the 1.21.0
# cooling-off; do not edit them in Phase 27).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFW="$ROOT/ts-cloudflare-worker/lib-observability.ts"
ORM="$ROOT/openrouter-monitor/src/observability/index.ts"

REDACTED='"password","token","api_key","card_number","cvv","ssn","secret","client_secret","refresh_token","access_token","authorization","bearer","cookie","x-api-key"'

substituted="$(sed \
  -e 's/{{ENV_VAR_DSN}}/SENTRY_DSN/g' \
  -e 's/{{ENV_VAR_ENV}}/DEPLOY_ENV/g' \
  -e 's/{{ENV_VAR_SERVICE}}/SERVICE_NAME/g' \
  -e 's/{{ENV_VAR_RELEASE}}/SENTRY_RELEASE/g' \
  -e 's/{{SERVICE_NAME}}/openrouter-monitor/g' \
  -e 's/{{DESTINATION}}/sentry/g' \
  -e 's/{{DEBUG_SAMPLE_RATE}}/0.1/g' \
  -e 's/{{TRACE_SAMPLE_RATE}}/0.1/g' \
  -e "s|{{REDACTED_KEYS}}|$REDACTED|g" \
  "$CFW")"

out="$(diff <(printf '%s\n' "$substituted") "$ORM" || true)"

if [[ "${1:-}" == "--snapshot" ]]; then
  printf '%s\n' "$out" > "$ROOT/.byte-symmetry.snapshot"
  echo "snapshot written: $ROOT/.byte-symmetry.snapshot ($(printf '%s\n' "$out" | grep -c '^[<>]') diff lines)"
  exit 0
fi

printf '%s' "$out"
