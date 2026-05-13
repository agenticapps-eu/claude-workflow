#!/bin/sh
# Should still be exactly one '## Knowledge wiki' heading
COUNT=$(grep -c '^## Knowledge wiki' "$HOME/Sourcecode/agenticapps/CLAUDE.md")
test "$COUNT" = "1" || { echo "duplicate Knowledge wiki heading count=$COUNT"; exit 1; }
# User's own '## Knowledge tooling overview' preserved
grep -q '^## Knowledge tooling overview' "$HOME/Sourcecode/agenticapps/CLAUDE.md" || { echo "user heading lost"; exit 1; }
