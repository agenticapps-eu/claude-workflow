#!/bin/sh
"$FIXTURES_ROOT/02-fresh-install/setup.sh"
# Write a custom config BEFORE the migration runs
echo '{"version":2,"name":"CustomName","mode":"knowledge","sources":[{"path":"custom-path","description":"user-customized"}],"output":".knowledge/wiki/"}' > "$HOME/Sourcecode/agenticapps/.wiki-compiler.json"
