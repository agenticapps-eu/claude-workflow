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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── argument parsing ────────────────────────────────────────────────────────
TEMPLATES_DIR=""
HASHES_FILE=""
ALLOW_PARTIAL=0
PROJECT_DIR="$PWD"
OLD_TEMPLATES_DIR=""   # v0.4.x wrapper bytes used as the token-extraction guide

while [ $# -gt 0 ]; do
  case "$1" in
    --templates-dir)     TEMPLATES_DIR="$2"; shift 2 ;;
    --hashes)            HASHES_FILE="$2"; shift 2 ;;
    --allow-partial)     ALLOW_PARTIAL=1; shift ;;
    --project-dir)       PROJECT_DIR="$2"; shift 2 ;;
    --old-templates-dir) OLD_TEMPLATES_DIR="$2"; shift 2 ;;
    *) echo "migrate-0017: unknown arg: $1" >&2; exit 3 ;;
  esac
done

# Default the extraction-guide dir to the engine's co-located runtime data.
OLD_TEMPLATES_DIR="${OLD_TEMPLATES_DIR:-$SCRIPT_DIR/migrate-0017-old-wrappers}"

[ -n "$TEMPLATES_DIR" ] || { echo "migrate-0017: --templates-dir required" >&2; exit 3; }
[ -d "$TEMPLATES_DIR" ] || { echo "migrate-0017: templates dir not found: $TEMPLATES_DIR" >&2; exit 3; }
[ -n "$HASHES_FILE" ] || { echo "migrate-0017: --hashes required" >&2; exit 3; }
[ -f "$HASHES_FILE" ] || { echo "migrate-0017: hashes file not found: $HASHES_FILE" >&2; exit 3; }
[ -d "$OLD_TEMPLATES_DIR" ] || { echo "migrate-0017: old-templates dir not found: $OLD_TEMPLATES_DIR" >&2; exit 3; }
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

  # ── style normalisation (Prettier-insensitive) ───────────────────────────
  # The masking rules below assume the TEMPLATE's style (double quotes, trailing
  # semicolons, one-space indent steps). A downstream `.prettierrc` (single
  # quotes / no semicolons / different print width) would otherwise defeat EVERY
  # rule — not just add line noise — and a clean wrapper would be refused. So we
  # first fold both the guide and the candidate to one canonical style. Applied
  # to both sides, it is hash-neutral; an embedded-quote edge case would mismatch
  # (refuse), which is fail-safe. Line REFLOW (print width) is not normalised —
  # a wrapper whose lines wrap differently still routes to the recovery patch.
  gsub(/\r$/, "", line)                       # CRLF
  gsub(/'/, "\"", line)                       # single → double string quotes
  gsub(/;[ \t]*\/\//, " //", line)            # semicolon before a line comment
  sub(/;[ \t]*$/, "", line)                   # trailing semicolon
  sub(/,[ \t]*$/, "", line)                   # trailing comma (Prettier all)
  gsub(/[ \t][ \t]+/, " ", line)              # collapse 2+ spaces/tabs → 1
  sub(/[ \t]+$/, "", line)                    # trim trailing whitespace

  # Anchor markers (migration 0014 / init wrap the managed region with
  # `// agenticapps:observability:start` … `:end`). Drop them in BOTH modes so
  # an otherwise-pristine anchor-wrapped wrapper classifies CLEAN.
  if (line ~ /agenticapps:observability:(start|end)/) { next }

  # NORMALIZE_ONLY mode: emit the style-normalised line without masking. The
  # token extractor (build_scalar_map / capture_redacted_block) uses this so it
  # aligns guide↔wrapper on identical style, sharing ONE normaliser (no drift).
  if (NORMALIZE_ONLY == "1") { print line; next }

  # REDACTED_KEYS array body — collapse genuine list elements to one placeholder
  # so a project's customised key list never alters the hash.
  if (in_redact) {
    if (line ~ /^[[:space:]]*\]$/ || line ~ /^[[:space:]]*\}$/) { in_redact = 0; print line; next }
    if (line ~ /^[[:space:]]*$/) { next }
    if (line ~ /^[[:space:]]*"[^"]*"$/) { next }
    if (line ~ /^[[:space:]]*\{\{REDACTED_KEYS\}\}$/) { next }
    print line; next
  }
  if (line ~ /REDACTED_KEYS.*=[[:space:]]*\[[[:space:]]*$/ \
      || line ~ /redactedKeys[[:space:]]*=[[:space:]]*\[\]string\{[[:space:]]*$/) {
    print line; print " " P "REDACTED_KEYS" P; in_redact = 1; next
  }

  # header comment Service: / Destination:
  if (line ~ /Service:[[:space:]]/) {
    sub(/Service:[[:space:]].*$/, "Service: " P "SERVICE_NAME" P, line); print line; next
  }
  if (line ~ /Destination:[[:space:]]/) {
    sub(/Destination:[[:space:]].*$/, "Destination: " P "DESTINATION" P, line); print line; next
  }

  # Go package declaration
  if (line ~ /^package [A-Za-z0-9_{}]+$/) { print "package " P "PACKAGE_NAME" P; next }
  if (line ~ /^\/\/ Package /) {
    sub(/Package [A-Za-z0-9_{}]+/, "Package " P "PACKAGE_NAME" P, line); print line; next
  }

  # service-name literal (semicolon already stripped by normalisation)
  if (line ~ /^const SERVICE_DEFAULT = ".*"$/) {
    print "const SERVICE_DEFAULT = \"" P "SERVICE_NAME" P "\""; next
  }
  if (line ~ /^[[:space:]]*serviceName = ".*"$/) {
    sub(/=.*$/, "= \"" P "SERVICE_NAME" P "\"", line); print line; next
  }

  # sample-rate literals
  if (line ~ /^const DEBUG_SAMPLE_RATE = .*$/) {
    print "const DEBUG_SAMPLE_RATE = " P "DEBUG_SAMPLE_RATE" P; next
  }
  if (line ~ /^const TRACE_SAMPLE_RATE = .*$/) {
    print "const TRACE_SAMPLE_RATE = " P "TRACE_SAMPLE_RATE" P; next
  }
  if (line ~ /^[[:space:]]*debugSampleRate = .*$/) {
    sub(/=.*$/, "= " P "DEBUG_SAMPLE_RATE" P, line); print line; next
  }
  if (line ~ /^[[:space:]]*traceSampleRate = .*$/) {
    sub(/=.*$/, "= " P "TRACE_SAMPLE_RATE" P, line); print line; next
  }

  # InitEnv interface fields: `IDENT?: string` (semicolon normalised away)
  if (line ~ /^[[:space:]]*[A-Za-z_{}][A-Za-z0-9_{}]*\?: string$/) {
    sub(/[A-Za-z_{}][A-Za-z0-9_{}]*\?: string/, P "ENV_VAR" P "?: string", line); print line; next
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

# ─── token re-materialisation (the apply must NOT emit raw templates) ─────────
# A clean project wrapper is, by construction, a token-substituted copy of the
# OLD (v0.4.x) template for its stack. To rewrite it to the v1.16.0 target
# WITHOUT discarding the project's real values (service name, sample rates,
# redacted-keys list, env-var names, Go package name), recover each token's
# value from the project wrapper using the OLD template as the alignment guide,
# then inject those values into the NEW template + adapters.
#
# Correctness rests on the clean-classification already proven upstream: every
# byte OUTSIDE a token site is identical between the OLD template and the project
# wrapper (any difference canonicalises to a mismatch → refuse). So for each
# OLD-template line carrying a single `{{TOKEN}}`, the project wrapper has a line
# sharing that line's literal prefix + suffix; the middle is the value. The
# multi-line `{{REDACTED_KEYS}}` list is captured as a block.

# OLD-template guide file for a stack (same basename convention as the NEW one).
old_guide_file() { stack_template_wrapper "$1"; }

# Emit TOKEN<TAB>VALUE for every scalar token, by aligning T (guide) with W.
# A token may appear at several sites; some are AMBIGUOUS — e.g. the cf-worker
# InitEnv interface lists `{{ENV_VAR_DSN}}?: string;`, `{{ENV_VAR_ENV}}?: string;`
# and `{{ENV_VAR_SERVICE}}?: string;`, all sharing prefix "  " + suffix
# "?: string;". Matching W on a shared signature gives every such token the
# FIRST field's value (all three → the DSN env var). So per token we choose an
# occurrence whose (prefix,suffix) signature is UNIQUE across tokens (the env
# vars each have a distinct usage site, e.g. `env.{{ENV_VAR_ENV}} ?? "dev"`),
# falling back to the first occurrence only if every site is ambiguous.
build_scalar_map() {
  # Normalise BOTH guide and wrapper to one style first (shared normaliser), so
  # the literal prefix/suffix alignment is immune to the project's .prettierrc.
  local g w; g=$(mktemp); w=$(mktemp)
  awk -v NORMALIZE_ONLY=1 -f <(canonicalize_awk) "$1" > "$g"
  awk -v NORMALIZE_ONLY=1 -f <(canonicalize_awk) "$2" > "$w"
  awk '
    FNR==NR {
      line=$0
      if (match(line, /\{\{[A-Z_]+\}\}/)) {
        tok=substr(line, RSTART+2, RLENGTH-4); rest=substr(line, RSTART+RLENGTH)
        if (tok != "REDACTED_KEYS" && rest !~ /\{\{[A-Z_]+\}\}/) {
          pre=substr(line,1,RSTART-1); suf=rest; sig=pre SUBSEP suf
          if (!(tok in seen)) { seen[tok]=1; order[++n]=tok }
          oc[tok, ++occn[tok], "p"]=pre; oc[tok, occn[tok], "s"]=suf
          if (!((sig, tok) in sigtok)) { sigtok[sig,tok]=1; sigdistinct[sig]++ }
        }
      }
      next
    }
    { wn++; W[wn]=$0 }
    END {
      # Choose one extraction site per token: prefer an unambiguous signature.
      for (i=1;i<=n;i++) {
        t=order[i]; chosen=0
        for (k=1;k<=occn[t];k++) {
          p=oc[t,k,"p"]; s=oc[t,k,"s"]
          if (sigdistinct[p SUBSEP s]==1) { cpre[t]=p; csuf[t]=s; chosen=1; break }
        }
        if (!chosen) { cpre[t]=oc[t,1,"p"]; csuf[t]=oc[t,1,"s"] }
      }
      # Extract each token from the first W line matching its chosen signature.
      for (wi=1;wi<=wn;wi++) {
        line=W[wi]; ll=length(line)
        for (i=1;i<=n;i++) {
          t=order[i]; if (t in val) continue
          p=cpre[t]; s=csuf[t]; lp=length(p); ls=length(s)
          if (ll < lp+ls) continue
          if (substr(line,1,lp) != p) continue
          if (ls>0 && substr(line, ll-ls+1, ls) != s) continue
          val[t]=substr(line, lp+1, ll-lp-ls)
        }
      }
      for (i=1;i<=n;i++){ t=order[i]; if (t in val) printf "%s\t%s\n", t, val[t] }
    }
  ' "$g" "$w"
  rm -f "$g" "$w"
}

# Emit the redacted-keys list element lines from W (empty if none).
capture_redacted_block() {
  awk '
    state==1 {
      if ($0 ~ /^[[:space:]]*\];?[[:space:]]*$/ || $0 ~ /^[[:space:]]*\}[;,]?[[:space:]]*$/) { state=2; next }
      print; next
    }
    state==0 && ($0 ~ /REDACTED_KEYS.*=[[:space:]]*\[[[:space:]]*$/ || $0 ~ /redactedKeys[[:space:]]*=[[:space:]]*\[\]string\{[[:space:]]*$/) { state=1; next }
  ' "$1"
}

# Substitute tokens in a NEW template ($1) from a scalar map ($2) + redacted
# block file ($3); write the materialised file to stdout.
materialize_tokens() {
  awk -v mapf="$2" -v redf="$3" '
    BEGIN {
      while ((getline ml < mapf) > 0) { ti=index(ml,"\t"); if (ti) { mv[substr(ml,1,ti-1)]=substr(ml,ti+1) } }
      nred=0; while ((getline rl < redf) > 0) { red[++nred]=rl }
    }
    {
      line=$0
      if (line ~ /\{\{REDACTED_KEYS\}\}/) { for (j=1;j<=nred;j++) print red[j]; next }
      while (match(line, /\{\{[A-Z_]+\}\}/)) {
        tok=substr(line, RSTART+2, RLENGTH-4)
        if (tok in mv) { line=substr(line,1,RSTART-1) mv[tok] substr(line, RSTART+RLENGTH) } else break
      }
      print line
    }
  ' "$1"
}

# ─── apply to clean roots ────────────────────────────────────────────────────
# Returns 0 on success (files written), 1 on refuse (ZERO writes for this root).
apply_root() {
  local dir="$1" stack="$2" entry="$3"
  local wf src guide
  wf=$(stack_template_wrapper "$stack")
  src="$TEMPLATES_DIR/$stack"
  guide="$OLD_TEMPLATES_DIR/$stack/$(old_guide_file "$stack")"

  if [ ! -f "$guide" ]; then
    echo "  ERROR: no token-extraction guide for stack '$stack' ($guide)" >&2
    return 1
  fi

  # 1. Recover the project's real token values from its existing wrapper.
  local mapf redf; mapf=$(mktemp); redf=$(mktemp)
  build_scalar_map "$guide" "$entry" > "$mapf"
  capture_redacted_block "$entry" > "$redf"

  # 2. Stage the substituted wrapper + adapters into temps (no writes yet).
  local stage_entry; stage_entry=$(mktemp)
  materialize_tokens "$src/$wf" "$mapf" "$redf" > "$stage_entry"

  local adst=() atmp=()
  if [ -f "$src/destinations/registry.ts" ]; then
    local a t
    for a in registry sentry axiom; do
      t=$(mktemp); materialize_tokens "$src/destinations/$a.ts" "$mapf" "$redf" > "$t"
      adst+=("$dir/destinations/$a.ts"); atmp+=("$t")
    done
  elif [ -f "$src/destinations.go" ]; then
    local t; t=$(mktemp); materialize_tokens "$src/destinations.go" "$mapf" "$redf" > "$t"
    adst+=("$dir/destinations.go"); atmp+=("$t")
  fi

  # 3. Token-free guard (toolchain-independent): refuse with ZERO writes if any
  #    generator token survived extraction (would not compile anyway).
  local bad=0 k
  if grep -q '{{' "$stage_entry"; then
    bad=1; echo "  ERROR: unresolved token(s) after substitution in $entry:" >&2
    grep -oE '\{\{[A-Z_]+\}\}' "$stage_entry" | sort -u | sed 's/^/        /' >&2
  fi
  if [ "${#atmp[@]}" -gt 0 ]; then
    for k in "${!atmp[@]}"; do
      grep -q '{{' "${atmp[$k]}" && { bad=1; echo "  ERROR: unresolved token(s) in ${adst[$k]}" >&2; }
    done
  fi
  if [ "$bad" -ne 0 ]; then
    rm -f "$mapf" "$redf" "$stage_entry" ${atmp[@]+"${atmp[@]}"}
    echo "  REFUSED (zero writes): token extraction incomplete for root $dir" >&2
    return 1
  fi

  # 4. Commit: back up the entry (for smoke rollback), then write staged files.
  cp "$entry" "$entry.0017bak"
  mv "$stage_entry" "$entry"
  if [ "${#atmp[@]}" -gt 0 ]; then
    for k in "${!atmp[@]}"; do
      mkdir -p "$(dirname "${adst[$k]}")"
      mv "${atmp[$k]}" "${adst[$k]}"
    done
  fi
  rm -f "$mapf" "$redf"
  # NOTE: env-file rows (env-additions.md / .dev.vars) are merged by the caller
  # only AFTER the smoke build passes, so a smoke rollback never leaves stray
  # AXIOM_* lines behind.
  echo "  migrated: $entry  (stack: $stack)"
  return 0
}

# Roll a freshly-applied root back to its pre-apply state (smoke-build failure).
# Only the wrapper entry + adapters were written at this point; env-file rows
# are merged post-smoke, so there is nothing else to undo.
rollback_root() {
  local dir="$1" entry="$2"
  [ -f "$entry.0017bak" ] && mv -f "$entry.0017bak" "$entry"
  rm -f "$dir/destinations/registry.ts" "$dir/destinations/sentry.ts" \
        "$dir/destinations/axiom.ts" "$dir/destinations.go"
  rmdir "$dir/destinations" 2>/dev/null || true
}

# Merge Axiom env rows into a root's env files (idempotent). Called only after a
# root's smoke build passes, so failed/rolled-back roots leave env files clean.
merge_axiom_env() {
  local dir="$1"
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

# Smoke-build if a toolchain is present (else skip with a note). FATAL: a failed
# build returns non-zero so the caller rolls the root back. Absent toolchain is
# not a failure (returns 0 with a skip note) — the token-free guard in apply_root
# already guarantees, toolchain-independently, that no raw template shipped.
smoke_build() {
  local stack="$1" dir="$2"
  case "$stack" in
    go-fly-http)
      if command -v go >/dev/null 2>&1 && [ -f go.mod ]; then
        if go build ./... >/dev/null 2>&1; then echo "  smoke: go build ./... OK"; return 0
        else echo "  smoke: go build FAILED on migrated root" >&2; return 1; fi
      else
        echo "  smoke: go toolchain absent — skipped"; return 0
      fi
      ;;
    ts-*)
      if command -v npx >/dev/null 2>&1 && [ -f tsconfig.json ]; then
        if npx --no-install tsc --noEmit >/dev/null 2>&1; then echo "  smoke: tsc --noEmit OK"; return 0
        else echo "  smoke: tsc --noEmit FAILED on migrated root" >&2; return 1; fi
      else
        echo "  smoke: TS toolchain absent — skipped"; return 0
      fi
      ;;
  esac
  return 0
}

CLAUDEMD_DONE=0
MIGRATED=0
APPLY_FAILED=()
for i in "${!CLEAN_DIRS[@]}"; do
  dir="${CLEAN_DIRS[$i]}"; stack="${CLEAN_STACKS[$i]}"; entry="${CLEAN_ENTRIES[$i]}"
  if ! apply_root "$dir" "$stack" "$entry"; then
    APPLY_FAILED+=("$dir")
    continue
  fi
  if smoke_build "$stack" "$dir"; then
    rm -f "$entry.0017bak"
    merge_axiom_env "$dir"
    MIGRATED=$((MIGRATED+1))
    if [ "$CLAUDEMD_DONE" -eq 0 ]; then
      rewrite_claudemd "$dir/policy.md"
      CLAUDEMD_DONE=1
    fi
  else
    echo "  smoke build failed — rolling back root $dir" >&2
    rollback_root "$dir" "$entry"
    APPLY_FAILED+=("$dir")
  fi
done

# Version bump ONLY when at least one root actually migrated. A run that migrated
# zero roots — every clean root failed apply/smoke, OR --allow-partial skipped
# all dirty roots — must NOT claim 1.16.0. (The genuine no-eligible-roots and
# all-already-applied paths bump earlier, before this loop.)
if [ "$MIGRATED" -gt 0 ]; then
  bump_version
fi

# ─── post-run summary + exit ─────────────────────────────────────────────────
echo "migrate-0017: summary — migrated=$MIGRATED failed=${#APPLY_FAILED[@]} already=${#SKIP_ALREADY[@]} unsupported=${#SKIP_UNSUPPORTED[@]} dirty-skipped=${#DIRTY_DIRS[@]}"

if [ ${#APPLY_FAILED[@]} -gt 0 ]; then
  echo "migrate-0017: ${#APPLY_FAILED[@]} clean root(s) FAILED to migrate (token extraction or smoke build) and were rolled back:" >&2
  printf '  failed: %s\n' "${APPLY_FAILED[@]}" >&2
fi
if [ ${#DIRTY_DIRS[@]} -gt 0 ]; then
  echo "migrate-0017: completed with ${#DIRTY_DIRS[@]} dirty root(s) skipped (--allow-partial)." >&2
  printf '  skipped (hand-modified): %s\n' "${DIRTY_DIRS[@]}" >&2
fi
if [ ${#DIRTY_DIRS[@]} -gt 0 ] || [ ${#APPLY_FAILED[@]} -gt 0 ]; then
  exit 2
fi
exit 0
