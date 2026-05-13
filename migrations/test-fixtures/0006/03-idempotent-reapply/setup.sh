#!/bin/sh
# Same baseline as 02-fresh-install
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Then run the install once (the harness will run it a second time)
bash "$REPO_ROOT/templates/.claude/scripts/install-wiki-compiler.sh" >/dev/null 2>&1
