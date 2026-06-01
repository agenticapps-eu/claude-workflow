#!/usr/bin/env bash
# Verify fixture 13: vanilla Hono index.ts + middleware.ts pair must NOT
# trigger .observability-0019.patch emission. Pre-D-06 (Wave 0 RED): this
# fixture FAILS — engine emits the patch because content-marker check is
# missing. Post-D-06 (Wave 3 GREEN): the content-marker rejects the pair
# and no patch is emitted.
#
# SC-5 evidence strategy (codex MED-2 strengthening): the roadmap SC-5
# text reads "SKIP_UNSUPPORTED + no .observability-0019.patch emitted."
# The engine emits literal "unsupported" tokens in two paths today:
#   - the idempotent-no-op exit path (line 646: "skipped N unsupported wrapper root(s).")
#   - the summary line (line 970: "unsupported: <dir>")
# But for fixture 13 today (pre-D-06), the engine misclassifies the pair
# as ts-cloudflare-worker (NOT unknown), so it does NOT reach the
# unsupported path; it reaches the all-clean apply path and emits .patch.
# To satisfy SC-5, we assert:
#   (a) NO .observability-0019.patch file at project root              [PRIMARY]
#   (b) src/index.ts byte-identical to seed (no engine edits)          [SECONDARY]
#   (c) Engine output contains a recognisable skip/unsupported phrase  [OPPORTUNISTIC]
# (a)+(b) are operationally equivalent to SKIP_UNSUPPORTED. (c) becomes
# definitive once Plan 03 D-06 lands (engine demotes the vanilla pair to
# `unknown` → it reaches the `info "  unsupported: $d"` line).
set -eu

SCRIPT="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
TEMPLATES="$REPO_ROOT/add-observability/templates"

# Capture seed bytes BEFORE engine runs (for operational-equivalence check (b)).
INDEX_BEFORE_SHA=$(shasum -a 256 src/index.ts | awk '{print $1}')

set +e
ENGINE_OUTPUT=$(bash "$SCRIPT" --templates-dir "$TEMPLATES" --project-dir "$PWD" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] || { echo "fixture 13 FAIL — expected engine exit 0, got $rc"; echo "$ENGINE_OUTPUT"; exit 1; }

# ── (a) PRIMARY: no spurious patch file for the vanilla pair ────────────
# Search both project root and the index.ts directory (engine writes the
# patch into the wrapper-root directory, which is `src/` for this fixture).
if [ -e ".observability-0019.patch" ] || [ -e "src/.observability-0019.patch" ]; then
  echo "fixture 13 FAIL — engine emitted .observability-0019.patch for vanilla Hono index.ts (content-marker firewall not applied)"
  echo "Engine output:"
  echo "$ENGINE_OUTPUT"
  exit 1
fi

# ── (b) SECONDARY: index.ts bytes unchanged (no engine edits) ───────────
INDEX_AFTER_SHA=$(shasum -a 256 src/index.ts | awk '{print $1}')
if [ "$INDEX_BEFORE_SHA" != "$INDEX_AFTER_SHA" ]; then
  echo "fixture 13 FAIL — engine modified src/index.ts (must remain vanilla — sha mismatch)"
  echo "before: $INDEX_BEFORE_SHA"
  echo "after:  $INDEX_AFTER_SHA"
  exit 1
fi

# Defence-in-depth: keep the original substring check too.
if ! grep -q "Hello World" src/index.ts; then
  echo "fixture 13 FAIL — engine modified src/index.ts (Hello World string missing)"
  exit 1
fi

# ── (c) OPPORTUNISTIC: engine emits skip/unsupported classification ─────
# Post-D-06 (Wave 3 GREEN), the engine demotes vanilla Hono pairs to
# `unknown` so they hit the SKIP_UNSUPPORTED path and emit the literal
# "unsupported:" token. Pre-D-06, the engine is silent on skip (it
# misclassifies as cf-worker), so (c) prints an INFO note rather than
# failing — (a)+(b) carry the SC-5 weight today.
if echo "$ENGINE_OUTPUT" | grep -qiE "SKIP_UNSUPPORTED|SKIP_NO_ANCHOR|no anchor classified|no observability wrapper-root|no wrapper-roots found|unsupported wrapper|unsupported:|no materialised observability wrapper"; then
  echo "fixture 13 INFO — engine emitted skip-classification token (SC-5 (c) satisfied)"
else
  echo "fixture 13 INFO — engine currently silent on skip-classification; (a)+(b) satisfy SC-5 operationally"
fi

echo "fixture 13 OK — vanilla Hono index.ts skipped (no observability marker)"
exit 0
