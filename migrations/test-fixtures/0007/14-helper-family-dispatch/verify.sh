#!/bin/sh
HELPER="${REPO_ROOT:-/}/templates/.claude/scripts/index-family-repos.sh"
if [ ! -x "$HELPER" ]; then
  cur="$PWD"
  while [ "$cur" != "/" ]; do
    [ -f "$cur/migrations/run-tests.sh" ] && HELPER="$cur/templates/.claude/scripts/index-family-repos.sh" && break
    cur=$(dirname "$cur")
  done
fi
rm -f "$HOME/.gn-record"
PATH="$HOME/bin:$PATH" bash "$HELPER" --family factiv >/dev/null 2>&1 || { echo "helper failed"; exit 1; }
# Expect 2 analyze invocations
ANALYZE_COUNT=$(grep -c "^gitnexus analyze$" "$HOME/.gn-record" 2>/dev/null || echo 0)
test "$ANALYZE_COUNT" = "2" || { echo "expected 2 analyze invocations, got $ANALYZE_COUNT"; cat "$HOME/.gn-record"; exit 1; }
