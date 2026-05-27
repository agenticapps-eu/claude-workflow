#!/usr/bin/env bash
# Sourced by individual fixture setup.sh scripts for migration 0017.
# Builds a sandboxed downstream-project skeleton in the CWD ($tmp), at workflow
# v1.15.0, ready for the 0017 apply engine. Per-fixture setup.sh layers the
# specific wrapper roots (clean / hand-modified / already-applied) on top.
#
# Env provided by the harness:
#   REPO_ROOT      — claude-workflow repo root
#   FIXTURES_ROOT  — migrations/test-fixtures/0017
#
# Helpers exported for fixture setup.sh use:
#   materialize_clean_worker <root-dir>     — un-modified cf-worker wrapper (main bytes)
#   materialize_clean_react  <root-dir>     — un-modified react-vite wrapper
#   materialize_clean_go     <root-dir>     — un-modified go-fly-http wrapper
#   materialize_dirty_worker <root-dir>     — hand-modified cf-worker wrapper (hash mismatch)
#   materialize_applied_worker <root-dir>   — already-migrated cf-worker root
set -eu

# 1. Project SKILL.md at v1.15.0 (the from_version for 0017).
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF'
---
name: agentic-apps-workflow
version: 1.15.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0017
---
EOF

# 2. Materialise an UN-MODIFIED wrapper for a stack into <root-dir>.
#    materialize_clean_* copies the OLD (v0.4.x) template bytes and then
#    substitutes the generator tokens with real values — exactly what a real
#    downstream project's wrapper looks like on disk (init always substitutes;
#    a wrapper with literal {{TOKENS}} never occurs in practice). Its CANONICAL
#    (masked) form matches the masked baseline in known-wrapper-hashes.json, so
#    the engine classifies it CLEAN, and its substituted values are what the
#    engine's token extraction must recover and preserve into the new wrapper.
#    materialize_substituted_* are kept as named aliases for fixtures whose
#    intent is to emphasise the substituted-clean case (e.g. 07).
_main_wrapper() {
  # $1=stack  $2=template-wrapper-file  $3=dest-abs-path
  # Source the OLD (v0.4.x) wrapper from the vendored bytes the apply engine
  # also uses for token extraction, NOT from `git show main:` — `main` now
  # carries the post-1.16.0 registry shape (PR #45), so a moving-ref source
  # silently mis-classifies every clean fixture as already-applied. See
  # templates/.claude/scripts/migrate-0017-old-wrappers/README.md.
  mkdir -p "$(dirname "$3")"
  cp "$REPO_ROOT/templates/.claude/scripts/migrate-0017-old-wrappers/$1/$2" "$3"
}

materialize_clean_worker() { _main_wrapper ts-cloudflare-worker lib-observability.ts "$1/index.ts"; _substitute_tokens "$1/index.ts"; }
materialize_clean_react()  { _main_wrapper ts-react-vite        lib-observability.ts "$1/index.ts"; _substitute_tokens "$1/index.ts"; }
materialize_clean_go()     { _main_wrapper go-fly-http          observability.go     "$1/observability.go"; _substitute_tokens "$1/observability.go"; }

# Substitute generator tokens in a wrapper exactly as `add-observability` would
# for a REAL project — so the on-disk bytes do NOT match the raw template, only
# the CANONICAL (masked) form does. Proves the engine's canonicalisation works
# against genuinely substituted wrappers (the bug P5 review caught: the old
# de-substitution only reversed ENV_VAR_DSN, so real substituted wrappers were
# mis-classified hand-modified and the migration never auto-applied).
#   $1=dest-file  (with tokens already copied in)
_substitute_tokens() {
  local f="$1"
  # Scalar tokens.
  sed -i.bak -E \
    -e 's/\{\{SERVICE_NAME\}\}/cparx-api/g' \
    -e 's/\{\{DESTINATION\}\}/sentry/g' \
    -e 's/\{\{DEBUG_SAMPLE_RATE\}\}/0.1/g' \
    -e 's/\{\{TRACE_SAMPLE_RATE\}\}/0.05/g' \
    -e 's/\{\{ENV_VAR_DSN\}\}/SENTRY_DSN/g' \
    -e 's/\{\{ENV_VAR_ENV\}\}/DEPLOY_ENV/g' \
    -e 's/\{\{ENV_VAR_SERVICE\}\}/SERVICE_NAME/g' \
    -e 's/\{\{PACKAGE_NAME\}\}/observability/g' \
    "$f"
  rm -f "$f.bak"
  # {{REDACTED_KEYS}} expands to a multi-line list inlined from policy.md.
  # Keep the source line's indentation so list elements sit inside the array.
  perl -0pi -e 's/^([ \t]*)\{\{REDACTED_KEYS\}\}\n/${1}"password",\n${1}"token",\n${1}"api_key",\n${1}"authorization",\n${1}"secret",\n/m' "$f"
}

# Named aliases — materialize_clean_* already substitutes (see note above), so
# these are equivalent; kept so fixtures can signal "substituted-clean" intent.
materialize_substituted_react() { materialize_clean_react "$1"; }
materialize_substituted_go()    { materialize_clean_go "$1"; }

# Prettier-styled clean worker: a substituted-but-unmodified cf-worker wrapper
# reformatted to a non-default style (single quotes, no semicolons), as a
# project with `{ "singleQuote": true, "semi": false }` produces. Must still
# classify CLEAN — the canonicaliser normalises style before hashing.
materialize_prettier_worker() {
  materialize_clean_worker "$1"
  local f="$1/index.ts" tmp; tmp=$(mktemp)
  sed -E "s/\"/'/g; s/;([[:space:]]*\/\/)/\1/g; s/;[[:space:]]*\$//" "$f" > "$tmp" && mv "$tmp" "$f"
}

# Anchor-wrapped (migration 0014 / init idiom): a substituted-clean wrapper whose
# content is bracketed by `// agenticapps:observability:start/end` markers. Must
# still classify CLEAN — the canonicaliser strips the markers before hashing.
materialize_anchored_react() {
  materialize_clean_react "$1"
  local f="$1/index.ts" tmp; tmp=$(mktemp)
  { echo "// agenticapps:observability:start"; cat "$f"; echo "// agenticapps:observability:end"; } > "$tmp"
  mv "$tmp" "$f"
}

# Hand-modified: clean wrapper + an extra hand-added line → hash mismatch.
materialize_dirty_worker() {
  materialize_clean_worker "$1"
  printf '\n// HAND-EDIT: bespoke local tweak by the project owner\n' >> "$1/index.ts"
}

# Hand-modified on a REALISTICALLY-SUBSTITUTED wrapper: substitute tokens like a
# real project, THEN inject a bespoke statement OUTSIDE any token site. The
# canonical (masked) form must still differ from the baseline → refuse. This
# proves refuse is not merely "didn't match the raw template" but survives
# correct canonicalisation of a real wrapper.
materialize_dirty_substituted_worker() {
  _main_wrapper ts-cloudflare-worker lib-observability.ts "$1/index.ts"
  _substitute_tokens "$1/index.ts"
  # Inject a hand statement into the emit() body (not a token site).
  perl -0pi -e 's/(function emit\(envelope: Envelope, ctx: TraceContext \| null\): void \{\n)/${1}  exfiltrate(envelope);  \/\/ HAND-EDIT: bespoke side effect\n/' "$1/index.ts"
}

# Already-applied: a migrated cf-worker root (registry imported + adapters present).
materialize_applied_worker() {
  mkdir -p "$1/destinations"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/lib-observability.ts" "$1/index.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/registry.ts" "$1/destinations/registry.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/sentry.ts"   "$1/destinations/sentry.ts"
  cp "$REPO_ROOT/add-observability/templates/ts-cloudflare-worker/destinations/axiom.ts"    "$1/destinations/axiom.ts"
}

# 3. A v0.3.0-shape observability: block in CLAUDE.md (the anchor-managed range
#    0017 rewrites to v0.4.0). Fixture 06 deletes this to exercise the stub path.
cat > CLAUDE.md <<'EOF'
# Downstream project CLAUDE.md (0017 fixture)

Some project preamble.

observability:
  spec_version: 0.3.0
  policy: src/lib/observability/policy.md
  enforcement: { baseline: .observability/baseline.json }

## Other section
Content after the observability block.
EOF
