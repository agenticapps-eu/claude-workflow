#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Plant .knowledge as a regular file in the family dir
echo "user data" > "$HOME/Sourcecode/agenticapps/.knowledge"
