#!/usr/bin/env bash
# migrate-0017-axiom-destination.sh
# ─────────────────────────────────────────────────────────────────────────────
# Executable apply engine for migration 0017 (add Axiom logs destination to
# existing add-observability v0.4.x wrappers). The migration markdown
# (migrations/0017-add-axiom-logs-destination.md) invokes this script; the
# script owns the HIGH-RISK pieces — discovery, content-hash hand-modified
# detection, the all-clean gate, refuse + .patch generation, and the safe-root
# apply — so they can be tested end-to-end by the migration harness.
#
# Usage:
#   migrate-0017-axiom-destination.sh \
#       --templates-dir <dir>          # add-observability/templates source tree
#       --hashes <file>                # known-wrapper-hashes.json baseline
#       [--allow-partial]              # apply clean roots, skip+list dirty ones
#       [--project-dir <dir>]          # default: CWD
#
# Exit codes:
#   0  success: all eligible roots migrated (or idempotent no-op, or no wrapper)
#   2  refused: >=1 hand-modified root. DEFAULT mode = ZERO writes to ANY root.
#               --allow-partial mode  = clean roots applied, dirty skipped.
#   3  pre-flight abort (wrong version / bad inputs) — ZERO writes.
#
# Design contract (mirrors migration 0014's idioms + PLAN P5 review hardening):
#   * Hand-modified detection runs across ALL roots BEFORE any write.
#   * DEFAULT refuse path is atomic: not a single file is created/modified when
#     any root is dirty (review #7 all-clean gate).
#   * Idempotent: roots already carrying destinations/registry are skipped.
#   * Fail-closed: an unrecognised wrapper shape is treated as hand-modified.
set -uo pipefail

# ─── argument parsing ────────────────────────────────────────────────────────
TEMPLATES_DIR=""
HASHES_FILE=""
ALLOW_PARTIAL=0
PROJECT_DIR="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir) TEMPLATES_DIR="$2"; shift 2 ;;
    --hashes)        HASHES_FILE="$2"; shift 2 ;;
    --allow-partial) ALLOW_PARTIAL=1; shift ;;
    --project-dir)   PROJECT_DIR="$2"; shift 2 ;;
    *) echo "migrate-0017: unknown arg: $1" >&2; exit 3 ;;
  esac
done

[ -n "$TEMPLATES_DIR" ] || { echo "migrate-0017: --templates-dir required" >&2; exit 3; }
[ -d "$TEMPLATES_DIR" ] || { echo "migrate-0017: templates dir not found: $TEMPLATES_DIR" >&2; exit 3; }
[ -n "$HASHES_FILE" ] || { echo "migrate-0017: --hashes required" >&2; exit 3; }
[ -f "$HASHES_FILE" ] || { echo "migrate-0017: hashes file not found: $HASHES_FILE" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "migrate-0017: jq is required" >&2; exit 3; }

cd "$PROJECT_DIR" || { echo "migrate-0017: cannot cd to $PROJECT_DIR" >&2; exit 3; }

SKILL_FILE=".claude/skills/agentic-apps-workflow/SKILL.md"

# ─── sha256 helper (portable BSD/GNU) ────────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# ─── version bump (defined early: called from no-wrapper / all-already exits) ─
bump_version() {
  if grep -q '^version: 1.16.0$' "$SKILL_FILE" 2>/dev/null; then
    return 0
  fi
  local tmp; tmp=$(mktemp)
  sed -E 's/^version: 1\.(12|13|14|15)\.[0-9]+$/version: 1.16.0/' "$SKILL_FILE" > "$tmp" && mv "$tmp" "$SKILL_FILE"
  echo "  bumped $SKILL_FILE -> version 1.16.0"
}

# ─── pre-flight ──────────────────────────────────────────────────────────────
# Workflow scaffolder version must be in 1.12.0–1.15.x (project on this track,
# not yet at 1.16.0). 1.16.0 is allowed too so a re-run after a partial apply
# is idempotent rather than a hard abort.
if [ ! -f "$SKILL_FILE" ]; then
  echo "migrate-0017: ABORT — $SKILL_FILE missing (not an agenticapps-workflow project)" >&2
  exit 3
fi
INSTALLED=$(grep -E '^version:' "$SKILL_FILE" | head -1 | sed 's/version: //' | tr -d '[:space:]')
case "$INSTALLED" in
  1.12.*|1.13.*|1.14.*|1.15.*|1.16.0) : ;;
  *)
    echo "migrate-0017: ABORT — workflow version is '$INSTALLED' (need 1.12.0–1.15.x)." >&2
    echo "              Apply prior migrations via /update-agenticapps-workflow first." >&2
    exit 3
    ;;
esac

# ─── discover module-roots ───────────────────────────────────────────────────
# A module-root is a materialised observability wrapper directory: the dir that
# contains the wrapper entry file (index.ts / observability.go). We locate them
# by the canonical materialised paths the generator uses, scanning the project.
# Each discovered root is classified by stack via its entry-file basename + a
# disambiguating content probe, then hash-checked.
#
# We collect, per root: <abs-wrapper-dir>|<stack>|<wrapper-entry-file>
ROOTS=()

# Find candidate wrapper entry files anywhere under the project (excluding the
# scaffolder's own template tree and node_modules / .git).
while IFS= read -r entry; do
  dir=$(dirname "$entry")
  base=$(basename "$entry")
  ROOTS+=("$dir|$base")
done < <(find . \
            -path ./node_modules -prune -o \
            -path ./.git -prune -o \
            -type f \( -name index.ts -o -name observability.go \) \
            -print 2>/dev/null \
          | grep -E '/observability/(index\.ts|observability\.go)$|/_shared/observability/index\.ts$' \
          | sort)

# If no wrapper at all → pre-init project; nothing for 0017 to do. Still bump
# version (the project is on-track) and exit 0. (PLAN: "no wrapper (pre-init)".)
if [ ${#ROOTS[@]} -eq 0 ]; then
  echo "migrate-0017: no materialised observability wrapper found — nothing to migrate."
  bump_version
  exit 0
fi

# ─── per-stack template metadata ─────────────────────────────────────────────
# stack -> wrapper template file (the v1.16.0 target wrapper) under TEMPLATES_DIR.
stack_template_wrapper() {
  case "$1" in
    ts-cloudflare-worker) echo "lib-observability.ts" ;;
    ts-cloudflare-pages)  echo "lib-observability.ts" ;;
    ts-supabase-edge)     echo "index.ts" ;;
    ts-react-vite)        echo "lib-observability.ts" ;;
    go-fly-http)          echo "observability.go" ;;
    *) echo "" ;;
  esac
}

# Classify a discovered root into a stack. We disambiguate the two TS shapes
# (worker/pages/react-vite all materialise to index.ts) via content probes that
# are stable across the OLD (main) wrapper bytes.
classify_stack() {
  local dir="$1" base="$2" f="$1/$2"
  if [ "$base" = "observability.go" ]; then echo "go-fly-http"; return; fi
  # supabase-edge materialises under .../_shared/observability/
  case "$dir" in
    */_shared/observability) echo "ts-supabase-edge"; return ;;
  esac
  # cf-pages materialises under functions/_lib/observability/
  case "$dir" in
    */functions/_lib/observability) echo "ts-cloudflare-pages"; return ;;
  esac
  # Distinguish cf-worker vs react-vite by their OLD wrapper imports.
  if grep -q '@sentry/cloudflare' "$f" 2>/dev/null; then echo "ts-cloudflare-worker"; return; fi
  if grep -qE '@sentry/react|@sentry/browser|import\.meta\.env' "$f" 2>/dev/null; then echo "ts-react-vite"; return; fi
  # cf-worker uses node:async_hooks + withSentry; default TS server guess.
  if grep -q 'node:async_hooks' "$f" 2>/dev/null; then echo "ts-cloudflare-worker"; return; fi
  echo "unknown"
}

# ─── canonicalisation (structural masking) ───────────────────────────────────
# The recorded baseline in known-wrapper-hashes.json is the sha256 of the
# CANONICAL (masked) form of each stack's OLD template wrapper — NOT the raw
# template bytes. A real materialised wrapper has the generator tokens
# substituted ({{SERVICE_NAME}}→"my-svc", {{DEBUG_SAMPLE_RATE}}→0.1,
# env.{{ENV_VAR_DSN}}→env.SENTRY_DSN, {{REDACTED_KEYS}}→a list, …). To compare
# a substituted wrapper against the template we mask EVERY token-substitution
# site — in both the template and the candidate — down to a fixed placeholder,
# then hash. So:
#   canonical(unmodified template)            ==  canonical(unmodified substituted wrapper)
#   canonical(hand-modified wrapper)          !=  canonical(template)        → refuse
# The masking is purely STRUCTURAL: it collapses the VALUE at each known site
# (service name, destination, sample rates, env-var identifiers, package name,
# the redacted-keys array body). ANY byte OUTSIDE a recognised token site —
# an added import, an altered function body, an extra statement, even a tweak
# to the non-token text on a token-bearing line — survives masking and changes
# the canonical hash. Direction of error is therefore toward REFUSE: an
# unrecognised shape never collapses onto the baseline, so it is treated as
# hand-modified. This implements the metadata-driven canonicalisation that
# HASHING-NOTE.md describes (the substituted VALUES are immaterial; only the
# structural shape is compared).
#
# The masking program (awk) is shared verbatim by the baseline-regeneration
# step (migrations/test-fixtures/0017/regen-hashes.sh) so the recorded hashes
# and the runtime check can never drift.
canonicalize_awk() {
  cat <<'CANON_AWK'
BEGIN { P = "\x00TOK\x00"; in_redact = 0 }
{
  line = $0

  # REDACTED_KEYS array body — collapse ONLY genuine list elements (quoted
  # strings / the template token / blanks). Any non-element line inside the
  # array is a hand modification and is emitted verbatim (alters the hash).
  if (in_redact) {
    if (line ~ /^[[:space:]]*\];[[:space:]]*$/ || line ~ /^[[:space:]]*\}[[:space:]]*$/) {
      in_redact = 0; print line; next
    }
    if (line ~ /^[[:space:]]*$/) { next }
    if (line ~ /^[[:space:]]*"[^"]*",?[[:space:]]*$/) { next }
    if (line ~ /^[[:space:]]*\{\{REDACTED_KEYS\}\},?[[:space:]]*$/) { next }
    print line; next
  }
  if (line ~ /REDACTED_KEYS.*=[[:space:]]*\[[[:space:]]*$/ \
      || line ~ /redactedKeys[[:space:]]*=[[:space:]]*\[\]string\{[[:space:]]*$/) {
    print line; print "  " P "REDACTED_KEYS" P; in_redact = 1; next
  }

  # header comment Service: / Destination:
  if (line ~ /Service:[[:space:]]/) {
    sub(/Service:[[:space:]].*$/, "Service: " P "SERVICE_NAME" P, line); print line; next
  }
  if (line ~ /Destination:[[:space:]]/) {
    sub(/Destination:[[:space:]].*$/, "Destination: " P "DESTINATION" P, line); print line; next
  }

  # Go package declaration
  if (line ~ /^package [A-Za-z0-9_{}]+[[:space:]]*$/) { print "package " P "PACKAGE_NAME" P; next }
  if (line ~ /^\/\/ Package /) {
    sub(/Package [A-Za-z0-9_{}]+/, "Package " P "PACKAGE_NAME" P, line); print line; next
  }

  # service-name literal
  if (line ~ /^const SERVICE_DEFAULT = ".*";[[:space:]]*$/) {
    print "const SERVICE_DEFAULT = \"" P "SERVICE_NAME" P "\";"; next
  }
  if (line ~ /^[[:space:]]*serviceName[[:space:]]*=[[:space:]]*".*"[[:space:]]*$/) {
    sub(/=.*$/, "= \"" P "SERVICE_NAME" P "\"", line); print line; next
  }

  # sample-rate literals
  if (line ~ /^const DEBUG_SAMPLE_RATE = .*;[[:space:]]*$/) {
    print "const DEBUG_SAMPLE_RATE = " P "DEBUG_SAMPLE_RATE" P ";"; next
  }
  if (line ~ /^const TRACE_SAMPLE_RATE = .*;[[:space:]]*$/) {
    print "const TRACE_SAMPLE_RATE = " P "TRACE_SAMPLE_RATE" P ";"; next
  }
  if (line ~ /^[[:space:]]*debugSampleRate[[:space:]]*=[[:space:]]*.*$/) {
    sub(/=.*$/, "= " P "DEBUG_SAMPLE_RATE" P, line); print line; next
  }
  if (line ~ /^[[:space:]]*traceSampleRate[[:space:]]*=[[:space:]]*.*$/) {
    sub(/=.*$/, "= " P "TRACE_SAMPLE_RATE" P, line); print line; next
  }

  # InitEnv interface fields: `  IDENT?: string;`
  if (line ~ /^[[:space:]]+[A-Za-z_{}][A-Za-z0-9_{}]*\?: string;[[:space:]]*$/) {
    sub(/[A-Za-z_{}][A-Za-z0-9_{}]*\?: string;/, P "ENV_VAR" P "?: string;", line); print line; next
  }

  # env-var access — quoted-getenv forms first so the generic env. rule below
  # cannot clobber Deno.env.get(...) / os.Getenv(...).
  if (line ~ /Deno\.env\.get\("[^"]*"\)/) {
    gsub(/Deno\.env\.get\("[^"]*"\)/, "Deno.env.get(\"" P "ENV_VAR" P "\")", line)
  }
  if (line ~ /os\.Getenv\("[^"]*"\)/) {
    gsub(/os\.Getenv\("[^"]*"\)/, "os.Getenv(\"" P "ENV_VAR" P "\")", line)
  }
  if (line ~ /env\.[A-Za-z_{}][A-Za-z0-9_{}]*[^A-Za-z0-9_{}(]/ || line ~ /env\.[A-Za-z_{}][A-Za-z0-9_{}]*$/) {
    gsub(/env\.[A-Za-z_{}][A-Za-z0-9_{}]*\(/, "\x01KEEP\x01", line)
    gsub(/env\.[A-Za-z_{}][A-Za-z0-9_{}]*/, "env." P "ENV_VAR" P, line)
    gsub(/\x01KEEP\x01/, "env.get(", line)
  }

  print line
}
CANON_AWK
}

# Canonicalise a wrapper (template OR substituted) by structural masking, hash.
canonical_hash() {
  local f="$1" stack="$2"   # stack kept for signature stability / future use
  local tmp; tmp=$(mktemp)
  awk -f <(canonicalize_awk) "$f" > "$tmp" 2>/dev/null || cp "$f" "$tmp"
  sha256_of "$tmp"
  rm -f "$tmp"
}

# ─── classify every root: clean | dirty | already | unsupported ──────────────
declare -a CLEAN_DIRS=() CLEAN_STACKS=() CLEAN_ENTRIES=()
declare -a DIRTY_DIRS=() DIRTY_STACKS=() DIRTY_ENTRIES=()
declare -a SKIP_ALREADY=()
declare -a SKIP_UNSUPPORTED=()

for rec in "${ROOTS[@]}"; do
  dir="${rec%%|*}"; base="${rec##*|}"
  entry="$dir/$base"

  # Idempotency: already migrated if a destinations/registry adapter exists
  # alongside (TS) or the wrapper already imports the registry (Go single-file).
  if [ -f "$dir/destinations/registry.ts" ] \
     || [ -f "$dir/destinations.go" ] \
     || grep -q 'buildRegistry' "$entry" 2>/dev/null; then
    SKIP_ALREADY+=("$dir")
    continue
  fi

  stack=$(classify_stack "$dir" "$base")
  if [ "$stack" = "unknown" ]; then
    SKIP_UNSUPPORTED+=("$dir")
    continue
  fi

  # Look up the known baseline hash for this stack (v0.4.x).
  want=$(jq -r --arg s "$stack" '.stacks[$s]["0.4.x"].sha256 // empty' "$HASHES_FILE")
  if [ -z "$want" ]; then
    # Stack has no baseline (e.g. cf-pages) — cannot prove un-modified; refuse.
    DIRTY_DIRS+=("$dir"); DIRTY_STACKS+=("$stack"); DIRTY_ENTRIES+=("$entry")
    continue
  fi

  got=$(canonical_hash "$entry" "$stack")
  if [ "$got" = "$want" ]; then
    CLEAN_DIRS+=("$dir"); CLEAN_STACKS+=("$stack"); CLEAN_ENTRIES+=("$entry")
  else
    DIRTY_DIRS+=("$dir"); DIRTY_STACKS+=("$stack"); DIRTY_ENTRIES+=("$entry")
  fi
done

# ─── all-clean gate (review #7) ──────────────────────────────────────────────
# If there are NO eligible-but-clean roots and nothing dirty, every root was
# already-applied / unsupported → idempotent success.
if [ ${#DIRTY_DIRS[@]} -eq 0 ] && [ ${#CLEAN_DIRS[@]} -eq 0 ]; then
  if [ ${#SKIP_ALREADY[@]} -gt 0 ]; then
    echo "migrate-0017: all ${#SKIP_ALREADY[@]} wrapper root(s) already migrated — idempotent no-op."
  fi
  if [ ${#SKIP_UNSUPPORTED[@]} -gt 0 ]; then
    echo "migrate-0017: skipped ${#SKIP_UNSUPPORTED[@]} unsupported wrapper root(s)."
  fi
  bump_version
  exit 0
fi

# Refuse-path UX: emit diff + .patch for each dirty root (always, regardless of
# mode — the operator needs the artefacts to recover).
emit_refuse_artifacts() {
  local i
  for i in "${!DIRTY_DIRS[@]}"; do
    local dir="${DIRTY_DIRS[$i]}" stack="${DIRTY_STACKS[$i]}" entry="${DIRTY_ENTRIES[$i]}"
    local tmpl="" wf=""
    if [ "$stack" != "unknown" ] && [ -n "$stack" ]; then
      wf=$(stack_template_wrapper "$stack")
      tmpl="$TEMPLATES_DIR/$stack/$wf"
    fi
    echo "  hand-modified: $entry  (stack: $stack)" >&2
    if [ -n "$tmpl" ] && [ -f "$tmpl" ]; then
      # Print the would-be diff (user wrapper vs known baseline template) and
      # write a .patch the operator can re-apply after a clean re-run.
      local patch="$dir/.observability-0017.patch"
      diff -u "$tmpl" "$entry" > "$patch" 2>/dev/null
      echo "      diff vs known baseline (excerpt):" >&2
      diff -u "$tmpl" "$entry" 2>/dev/null | head -20 | sed 's/^/        /' >&2
      echo "      wrote recovery patch: $patch" >&2
      echo "      *** SECURITY: this patch may contain secrets if your wrapper" >&2
      echo "          embeds tokens or API keys. Delete it after use and do NOT" >&2
      echo "          commit it to version control." >&2
      # Idempotently add the patch filename to .gitignore (if one exists).
      local gi="$dir/.gitignore"
      if [ -f "$gi" ]; then
        if ! grep -qF ".observability-0017.patch" "$gi"; then
          printf '\n.observability-0017.patch\n' >> "$gi"
        fi
      fi
      echo "      recover: (a) git stash your wrapper changes;" >&2
      echo "               (b) re-run migration 0017 against the clean wrapper;" >&2
      echo "               (c) re-apply $patch onto the migrated wrapper." >&2
      echo "               (d) delete $patch once done." >&2
    else
      echo "      (no baseline template available for stack '$stack' — manual splice required)" >&2
    fi
  done
}

if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  echo "migrate-0017: detected ${#DIRTY_DIRS[@]} hand-modified wrapper root(s)." >&2
  emit_refuse_artifacts
  if [ "$ALLOW_PARTIAL" -eq 0 ]; then
    # DEFAULT all-clean gate: ZERO writes to ANY root. List clean roots that
    # would have been applied, then abort.
    echo "migrate-0017: ABORT (all-clean gate) — no wrapper files written to ANY root." >&2
    if [ ${#CLEAN_DIRS[@]} -gt 0 ]; then
      echo "              clean roots that WOULD migrate under --allow-partial:" >&2
      printf '                %s\n' "${CLEAN_DIRS[@]}" >&2
    fi
    echo "              Re-run with --allow-partial to migrate clean roots and skip dirty ones." >&2
    exit 2
  fi
  # --allow-partial: fall through to apply clean roots only.
  echo "migrate-0017: --allow-partial — migrating clean roots, skipping dirty ones." >&2
fi

# ─── apply to clean roots ────────────────────────────────────────────────────
apply_root() {
  local dir="$1" stack="$2" entry="$3"
  local wf; wf=$(stack_template_wrapper "$stack")
  local src="$TEMPLATES_DIR/$stack"

  # 1. Copy destination adapters into <root>/destinations/ (TS) or sibling
  #    destinations.go (Go single-file).
  if [ -f "$src/destinations/registry.ts" ]; then
    mkdir -p "$dir/destinations"
    cp "$src/destinations/registry.ts" "$dir/destinations/registry.ts"
    cp "$src/destinations/sentry.ts"   "$dir/destinations/sentry.ts"
    cp "$src/destinations/axiom.ts"    "$dir/destinations/axiom.ts"
  elif [ -f "$src/destinations.go" ]; then
    cp "$src/destinations.go" "$dir/destinations.go"
  fi

  # 2. Rewrite the wrapper entry file to the v1.16.0 registry-dispatched target.
  cp "$src/$wf" "$entry"

  # 3. Merge Axiom env rows into the project's env file if one exists alongside.
  if [ -f "$dir/env-additions.md" ] && ! grep -q 'AXIOM_TOKEN' "$dir/env-additions.md" 2>/dev/null; then
    {
      echo ""
      echo "## Axiom (logs destination — default; added by migration 0017)"
      echo ""
      echo "| \`AXIOM_TOKEN\` | secret | required if logs=axiom | \`xaat-...\` |"
      echo "| \`AXIOM_DATASET\` | env | required if logs=axiom | \`myapp-prod\` |"
      echo "| \`OBS_DESTINATIONS\` | env | optional | \`errors=sentry,logs=axiom\` |"
    } >> "$dir/env-additions.md"
  fi
  if [ -f ".dev.vars" ] && ! grep -q 'AXIOM_TOKEN' .dev.vars 2>/dev/null; then
    printf 'AXIOM_TOKEN=\nAXIOM_DATASET=\n' >> .dev.vars
  fi
  echo "  migrated: $entry  (stack: $stack)"
}

# CLAUDE.md observability: block rewrite v0.3.0 -> v0.4.0 multi-destination.
# The `observability:` YAML block is the anchor-managed range. If absent, write
# a stub block to a (possibly new) CLAUDE.md.
rewrite_claudemd() {
  local policy_path="$1"
  if [ ! -f CLAUDE.md ]; then
    cat > CLAUDE.md <<EOF
# CLAUDE.md

observability:
  spec_version: 0.4.0
  destinations: { errors: sentry, logs: axiom, analytics: none }
  policy: ${policy_path:-src/lib/observability/policy.md}
  enforcement: { baseline: .observability/baseline.json }
EOF
    echo "  wrote stub observability: block to new CLAUDE.md"
    return
  fi
  if ! grep -q '^observability:' CLAUDE.md; then
    cat >> CLAUDE.md <<EOF

observability:
  spec_version: 0.4.0
  destinations: { errors: sentry, logs: axiom, analytics: none }
  policy: ${policy_path:-src/lib/observability/policy.md}
  enforcement: { baseline: .observability/baseline.json }
EOF
    echo "  appended observability: block to CLAUDE.md"
    return
  fi
  # Block present: bump spec_version 0.3.0 -> 0.4.0 and inject destinations line
  # (idempotent — no-op if already 0.4.0 / destinations present).
  local tmp; tmp=$(mktemp)
  awk '
    BEGIN { in_obs=0; have_dest=0 }
    /^observability:/ { in_obs=1; print; next }
    in_obs && /^[^[:space:]]/ {
      # leaving the block: if we never saw a destinations line, add one
      if (!have_dest) print "  destinations: { errors: sentry, logs: axiom, analytics: none }"
      in_obs=0; print; next
    }
    in_obs && /^[[:space:]]*spec_version:/ { sub(/0\.3\.0/, "0.4.0"); print; next }
    in_obs && /^[[:space:]]*destinations:/ { have_dest=1; print; next }
    { print }
    END {
      if (in_obs && !have_dest) print "  destinations: { errors: sentry, logs: axiom, analytics: none }"
    }
  ' CLAUDE.md > "$tmp" && mv "$tmp" CLAUDE.md
  echo "  rewrote CLAUDE.md observability: block to spec_version 0.4.0 + destinations"
}

# Smoke-build if a toolchain is present (else skip with a note).
smoke_build() {
  local stack="$1" dir="$2"
  case "$stack" in
    go-fly-http)
      if command -v go >/dev/null 2>&1 && [ -f go.mod ]; then
        go build ./... >/dev/null 2>&1 && echo "  smoke: go build ./... OK" \
          || echo "  smoke: go build reported issues (review manually)"
      else
        echo "  smoke: go toolchain absent — skipped"
      fi
      ;;
    ts-*)
      if command -v npx >/dev/null 2>&1 && [ -f tsconfig.json ]; then
        npx --no-install tsc --noEmit >/dev/null 2>&1 && echo "  smoke: tsc --noEmit OK" \
          || echo "  smoke: tsc reported issues (review manually)"
      else
        echo "  smoke: TS toolchain absent — skipped"
      fi
      ;;
  esac
}

CLAUDEMD_DONE=0
for i in "${!CLEAN_DIRS[@]}"; do
  dir="${CLEAN_DIRS[$i]}"; stack="${CLEAN_STACKS[$i]}"; entry="${CLEAN_ENTRIES[$i]}"
  apply_root "$dir" "$stack" "$entry"
  if [ "$CLAUDEMD_DONE" -eq 0 ]; then
    rewrite_claudemd "$dir/policy.md"
    CLAUDEMD_DONE=1
  fi
  smoke_build "$stack" "$dir"
done

bump_version

# ─── post-run summary + exit ─────────────────────────────────────────────────
echo "migrate-0017: summary — migrated=${#CLEAN_DIRS[@]} already=${#SKIP_ALREADY[@]} unsupported=${#SKIP_UNSUPPORTED[@]} dirty-skipped=${#DIRTY_DIRS[@]}"

if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  # --allow-partial path: clean roots applied, dirty skipped → non-zero per PLAN.
  echo "migrate-0017: completed with ${#DIRTY_DIRS[@]} dirty root(s) skipped (--allow-partial)." >&2
  printf '  skipped (hand-modified): %s\n' "${DIRTY_DIRS[@]}" >&2
  exit 2
fi
exit 0
