#!/bin/sh
# Verify pre-flight rule 4 (relaxed in the 0030 fix to accept blank-line
# spacing between provenance and heading — see fixture 11) still refuses
# two malformed placements, and leaves CLAUDE.md untouched in both cases:
#   (a) the heading sits ABOVE its provenance line
#   (b) non-blank content sits between the provenance line and the heading
# Each assertion matches the specific ABORT text for its shape, not merely
# a non-zero exit — a fixture that only checks status would stay green if
# rule 4 refused for the wrong reason (or if some other rule fired instead).
set -eu
. "$REPO_ROOT/migrations/test-fixtures/0030/common-verify.sh"

MIRROR="$HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md"

# --- Shape (a): heading precedes its provenance line -----------------------
{
  printf '# CLAUDE.md\n\n'
  cat "$MIRROR"
  printf '\n<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md

[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: shape (a) fixture must carry exactly one provenance line"
  exit 1
}
[ "$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: shape (a) fixture must carry exactly one §11 heading"
  exit 1
}
prov_line=$(grep -n '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md | cut -d: -f1)
head_line=$(grep -n '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md | cut -d: -f1)
[ "$head_line" -lt "$prov_line" ] || {
  echo "PRE: shape (a) fixture must place the heading before the provenance"
  echo "     line — got heading at $head_line, provenance at $prov_line"
  exit 1
}

before_a="$(cat CLAUDE.md)"
out_a="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted a §11 heading above its provenance line"
  exit 1
}
printf '%s' "$out_a" | grep -q 'above its provenance line' || {
  echo "FAIL: pre-flight refused shape (a), but not for the"
  echo "      heading-precedes-provenance reason — got:"
  printf '%s\n' "$out_a" | sed 's/^/    /'
  exit 1
}
[ "$before_a" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight on shape (a) still mutated CLAUDE.md"
  exit 1
}

# --- Shape (b): non-blank content between provenance and heading -----------
{
  printf '# CLAUDE.md\n\n'
  printf '<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->\n'
  printf 'Unexpected prose between them.\n'
  cat "$MIRROR"
  printf '\n## Project Overview\nStuff.\n'
} > CLAUDE.md

[ "$(grep -c '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: shape (b) fixture must carry exactly one provenance line"
  exit 1
}
[ "$(grep -c '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md)" -eq 1 ] || {
  echo "PRE: shape (b) fixture must carry exactly one §11 heading"
  exit 1
}
prov_line=$(grep -n '^<!-- spec-source: agenticapps-workflow-core@0\.4\.0 §11 -->$' CLAUDE.md | cut -d: -f1)
head_line=$(grep -n '^## Coding Discipline (NON-NEGOTIABLE)$' CLAUDE.md | cut -d: -f1)
[ "$head_line" -gt "$prov_line" ] || {
  echo "PRE: shape (b) fixture must place the heading after the provenance"
  echo "     line — got heading at $head_line, provenance at $prov_line"
  exit 1
}
between=$(awk -v s="$((prov_line + 1))" -v e="$((head_line - 1))" \
  'NR >= s && NR <= e && $0 ~ /[^[:space:]]/ { c++ } END { print c + 0 }' CLAUDE.md)
[ "$between" -ne 0 ] || {
  echo "PRE: shape (b) fixture must carry non-blank content between the"
  echo "     provenance line and the heading"
  exit 1
}

before_b="$(cat CLAUDE.md)"
out_b="$(preflight 2>&1)" && {
  echo "FAIL: pre-flight accepted non-blank content between the provenance"
  echo "      line and the §11 heading"
  exit 1
}
printf '%s' "$out_b" | grep -q 'non-blank content between them' || {
  echo "FAIL: pre-flight refused shape (b), but not for the"
  echo "      non-blank-content-between reason — got:"
  printf '%s\n' "$out_b" | sed 's/^/    /'
  exit 1
}
[ "$before_b" = "$(cat CLAUDE.md)" ] || {
  echo "FAIL: refusing pre-flight on shape (b) still mutated CLAUDE.md"
  exit 1
}

echo "OK: pre-flight rule 4 refused a heading above its provenance line"
echo "    (shape a) and non-blank content between provenance and heading"
echo "    (shape b); CLAUDE.md untouched in both cases"
exit 0
