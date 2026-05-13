#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
PATH="$HOME/bin:$PATH" bash "$REPO_ROOT/templates/.claude/scripts/install-gitnexus.sh" >/dev/null 2>&1
