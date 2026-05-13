#!/bin/sh
HELPER="${REPO_ROOT:-/}/templates/.claude/scripts/index-family-repos.sh"
if [ ! -x "$HELPER" ]; then
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    [ -f "$cur/migrations/run-tests.sh" ] && HELPER="$cur/templates/.claude/scripts/index-family-repos.sh" && break
    cur=$(dirname "$cur")
  done
fi
OUT=$(PATH="$HOME/bin:$PATH" bash "$HELPER" --help 2>&1)
EXIT=$?
[ "$EXIT" = "0" ] || exit 1
echo "$OUT" | grep -q "Usage:" || exit 1
