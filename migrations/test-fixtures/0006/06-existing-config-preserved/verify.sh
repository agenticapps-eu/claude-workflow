#!/bin/sh
# Config still contains the user-customized name
grep -q '"name":"CustomName"' "$HOME/Sourcecode/agenticapps/.wiki-compiler.json" || { echo "config was overwritten"; exit 1; }
