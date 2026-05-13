#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Plant a malformed config
echo 'this is not json {' > "$HOME/Sourcecode/agenticapps/.wiki-compiler.json"
