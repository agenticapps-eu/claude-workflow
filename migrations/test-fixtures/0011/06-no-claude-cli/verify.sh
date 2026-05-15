#!/bin/sh
# command -v claude should fail (the stub was deleted).
set -eu

# Force PATH to the sandbox bin only so we don't pick up the host's claude.
export PATH="$HOME/bin:/usr/bin:/bin"

if command -v claude >/dev/null 2>&1; then
  echo "FAIL: claude is still resolvable; fixture setup did not remove it"
  exit 1
fi

# Confirm: pre-flight 4 (requires.tool.claude.verify) would abort.
echo "fixture 06 — claude correctly absent; pre-flight 4 (requires.tool.claude) aborts"
