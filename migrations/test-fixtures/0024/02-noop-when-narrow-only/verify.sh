#!/bin/sh
# Verify migration 0024 on a project that already commits phases (fixture 02):
# Step 1's positive idempotency anchor holds before apply, and replaying the
# Step 1 sed changes nothing (narrow scratch ignore under the tree is spared).
set -eu

# Step 1 idempotency anchor already positive (no whole-tree ignore)
grep -qE '^[[:space:]]*/?\.planning/phases/?[[:space:]]*$' .gitignore \
  && { echo "PRE: unexpected whole-tree ignore in a should-be-clean fixture"; exit 1; }

before="$(cat .gitignore)"

# Replay Step 1 sed — must be a no-op here
sed -i.0024.bak -E \
  -e '/^[[:space:]]*\/?\.planning\/phases\/?[[:space:]]*$/d' \
  -e '/^[[:space:]]*\/?\.planning\/?[[:space:]]*$/d' \
  -e '/^[[:space:]]*\/?\.planning\/\*[[:space:]]*$/d' \
  .gitignore
rm -f .gitignore.0024.bak

after="$(cat .gitignore)"
[ "$before" = "$after" ] || { echo "STEP 1 not idempotent: modified an already-clean .gitignore"; exit 1; }

# Narrow scratch ignore under the tree preserved
grep -qF '.planning/phases/*/.review-prompt.md' .gitignore \
  || { echo "STEP 1 over-reached: narrow scratch ignore removed"; exit 1; }

echo "fixture 02 — already commits phases; Step 1 is a no-op, narrow ignore preserved"
