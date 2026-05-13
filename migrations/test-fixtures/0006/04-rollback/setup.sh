#!/bin/sh
# Build the applied state. The harness will re-run install (idempotent no-op).
# verify.sh then performs rollback and asserts the post-rollback state.
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
bash "$REPO_ROOT/templates/.claude/scripts/install-wiki-compiler.sh" >/dev/null 2>&1
