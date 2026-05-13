#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
bash "$REPO_ROOT/templates/.claude/scripts/install-wiki-compiler.sh" >/dev/null 2>&1
# Add a pre-existing user heading that's similar but distinct, to make sure
# the grep '^## Knowledge wiki' anchor is exact-match-on-line-start.
printf '\n## Knowledge tooling overview\n\nSome user-written content.\n' >> "$HOME/Sourcecode/agenticapps/CLAUDE.md"
