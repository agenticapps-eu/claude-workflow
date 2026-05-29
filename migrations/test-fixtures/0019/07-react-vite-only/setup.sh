#!/usr/bin/env bash
# Fixture 07 (R09 binding) — project with ONLY a react-vite wrapper (no
# worker / pages / supabase-edge / go). The engine discovers the wrapper,
# classifies it ts-react-vite, marks it SKIP_UNSUPPORTED (D10), exits 0 with
# no files written into any wrapper dir.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

seed_clean_react "src/lib/observability"
