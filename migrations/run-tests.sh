#!/usr/bin/env bash
# Migration test harness — verifies idempotency checks behave correctly
# against known before / after reference states extracted from git.
#
# Usage:
#   migrations/run-tests.sh                       # run all testable migrations
#   migrations/run-tests.sh 0001                  # run only migration 0001
#   migrations/run-tests.sh --strict-preflight    # roll the preflight audit
#                                                 # into the global FAIL count
#                                                 # (CI gating mode)
#   STRICT_PREFLIGHT=1 migrations/run-tests.sh    # env-var equivalent
#
# In default (non-strict) mode the preflight-correctness audit is purely
# informational: failures print to a labeled section but do NOT change the
# exit code. This lets developers run the harness on dev machines that may
# be missing some host dependencies without false-positive failures.
#
# In strict mode (--strict-preflight or STRICT_PREFLIGHT=1) audit failures
# DO add to the global FAIL counter and propagate to the exit code. Intended
# for CI environments that have parity with author dev environments and want
# verify-path rot to gate merges (the issue-#18 bug class).
#
# See migrations/test-fixtures/README.md for the per-migration fixture
# contract; see "Preflight-correctness audit" section of migrations/README.md
# for the audit's role + CI guidance.

set -uo pipefail

# ─── Resolve shared lib (D-28e source-and-keep) ──────────────────────────────
# BASH_SOURCE[0] is this script's path; dirname gives migrations/; go up one
# level to the repo root, then descend into vendor/agenticapps-shared.
# Canonicalize through any symlink (review finding 3): resolve BASH_SOURCE so an
# invocation via a symlinked path/dir still anchors _SHARED_LIB at the real repo.
# Portable on macOS/BSD (no `readlink -f`).
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
_SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
_SHARED_LIB="$_SCRIPT_DIR/../vendor/agenticapps-shared/migrations/lib"

# Fail closed on a partial/stale submodule (review finding 1): a present dir with
# a missing lib file would otherwise fail-open under `set -uo pipefail` (a failed
# `source` does not abort without `set -e`) and run with wrong/stale helpers while
# still printing a PASS/FAIL total. Verify the dir AND all four required libs.
if [ ! -d "$_SHARED_LIB" ]; then
  echo "ERROR: agenticapps-shared submodule not initialized." >&2
  echo "Fix: git submodule update --init --recursive" >&2
  exit 1
fi
for _lib in helpers.sh fixture-runner.sh preflight.sh drift-test.sh; do
  if [ ! -f "$_SHARED_LIB/$_lib" ]; then
    echo "ERROR: agenticapps-shared submodule incomplete — missing $_lib." >&2
    echo "Fix: git submodule update --init --recursive" >&2
    exit 1
  fi
done
unset _lib

source "$_SHARED_LIB/helpers.sh"
source "$_SHARED_LIB/fixture-runner.sh"
source "$_SHARED_LIB/preflight.sh"
source "$_SHARED_LIB/drift-test.sh"

# ─── SPLIT TRAP (codex HIGH-2 / R-rev-2) ─────────────────────────────────────
# Set traps AFTER sourcing (helpers.sh defines _runtests_do_cleanup — Risk 2).
# EXIT is silent (no cleanup output on normal harness exit).
# INT → exit 130; TERM → exit 143.
trap '_runtests_do_cleanup'        EXIT
trap '_runtests_do_cleanup; exit 130' INT
trap '_runtests_do_cleanup; exit 143' TERM

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Flag + filter parsing. Order-agnostic: --strict-preflight may appear before
# or after the optional <filter> positional. Unknown flags reject with exit 2.
STRICT_PREFLIGHT="${STRICT_PREFLIGHT:-0}"
FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict-preflight) STRICT_PREFLIGHT=1; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --*)
      echo "unknown flag: $1" >&2
      echo "run \`$0 --help\` for usage" >&2
      exit 2
      ;;
    *)
      if [ -z "$FILTER" ]; then
        FILTER="$1"; shift
      else
        echo "unexpected positional arg: $1 (filter already set to '$FILTER')" >&2
        exit 2
      fi
      ;;
  esac
done

# Setup a fixture project at $1=tmpdir from git ref $2.
# The fixture mimics a project's on-disk shape: maps scaffolder template
# paths to project paths.
# WORKFLOW — claude-workflow wrapper (A1): hardcodes template paths + the 1.3.0 special-case.
# Calls SHARED extract_to (vendor/agenticapps-shared) and layers workflow specifics on top.
setup_fixture() {
  local tmpdir="$1" ref="$2"
  extract_to "$ref" "templates/workflow-config.md"   "$tmpdir/.claude/workflow-config.md"   || return 1
  extract_to "$ref" "templates/config-hooks.json"    "$tmpdir/.planning/config.json"        || return 1
  extract_to "$ref" "templates/claude-md-sections.md" "$tmpdir/CLAUDE.md"                   || return 1

  # Synthesize a SKILL.md with the right version field (the templates
  # don't carry the project's installed-version state — that lives in
  # the project's copy, which we synthesize here).
  mkdir -p "$tmpdir/.claude/skills/agentic-apps-workflow"
  local version="$3"
  cat >"$tmpdir/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF
---
name: agentic-apps-workflow
version: $version
description: synthetic test fixture
---
EOF

  # For the v1.3.0 "after" fixture, also include the new ADR template
  # that migration 0001 Step 9 copies into the project.
  if [ "$version" = "1.3.0" ]; then
    extract_to "$ref" "templates/adr-db-security-acceptance.md" "$tmpdir/templates/adr-db-security-acceptance.md" || true
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0001 — Wire Go skill packs + impeccable + database-sentinel
# WORKFLOW — verify body specific to migration 0001 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────

test_migration_0001() {
  echo ""
  echo "${YELLOW}━━━ Migration 0001 — Wire Go + impeccable + database-sentinel ━━━${RESET}"

  # Anchor before_ref to the v1.2.0 baseline — the parent of the commit that
  # first introduced migration 0001's marker into templates/workflow-config.md.
  # The legacy `git merge-base HEAD origin/main` resolved to HEAD when running
  # on main (post-merge), so both fixtures got the post-0001 template state and
  # every "needs apply on v1.2.0" assertion failed. Anchoring to the marker
  # commit's parent works regardless of branch: on a feature branch testing
  # 0001 itself the historical pre-0001 commit on main is still the v1.2.0
  # baseline we want to compare against.
  git fetch --quiet origin main 2>/dev/null || true
  local marker_commit
  marker_commit="$(git log --reverse --format=%H -S '## Backend language routing' -- templates/workflow-config.md 2>/dev/null | head -1)"
  local before_ref=""
  if [ -n "$marker_commit" ]; then
    before_ref="$(git rev-parse "${marker_commit}^" 2>/dev/null || true)"
  fi
  # Fallback for stripped clones or future history rewrites that lose the marker
  # commit: the legacy merge-base chain still gives a sensible answer on feature
  # branches that haven't merged 0001 yet.
  if [ -z "$before_ref" ]; then
    before_ref="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || git rev-parse main)"
  fi
  local after_ref="HEAD"

  echo "  before ref: $before_ref ($(git log -1 --format='%h %s' "$before_ref"))"
  echo "  after ref:  $after_ref ($(git log -1 --format='%h %s' "$after_ref"))"

  local before_dir="$(mktemp -d -t migration-0001-before-XXXXXX)"
  local after_dir="$(mktemp -d -t migration-0001-after-XXXXXX)"
  trap "rm -rf '$before_dir' '$after_dir'" RETURN

  setup_fixture "$before_dir" "$before_ref" "1.2.0" || {
    echo "  ${RED}SKIP${RESET}: could not extract before fixture from $before_ref"
    SKIP=$((SKIP+1))
    return
  }
  setup_fixture "$after_dir"  "$after_ref"  "1.3.0" || {
    echo "  ${RED}SKIP${RESET}: could not extract after fixture from $after_ref"
    SKIP=$((SKIP+1))
    return
  }

  # Step 1: Backend language routing in workflow-config.md
  assert_check "Step 1 idempotency: needs apply on v1.2.0" \
    'grep -q "^## Backend language routing" .claude/workflow-config.md' "$before_dir" not-applied
  assert_check "Step 1 idempotency: skip on v1.3.0" \
    'grep -q "^## Backend language routing" .claude/workflow-config.md' "$after_dir" applied

  # Step 2: design_critique row in workflow-config.md
  assert_check "Step 2 idempotency: needs apply on v1.2.0" \
    'grep -q "design_critique" .claude/workflow-config.md' "$before_dir" not-applied
  assert_check "Step 2 idempotency: skip on v1.3.0" \
    'grep -q "design_critique" .claude/workflow-config.md' "$after_dir" applied

  # Step 3: cso row replacement in workflow-config.md
  # Anchor on "if Supabase / Postgres / MongoDB touched" — uniquely identifies
  # the post-migration cso row text without depending on backticks.
  assert_check "Step 3 idempotency: needs apply on v1.2.0" \
    'grep -q "if Supabase / Postgres / MongoDB touched" .claude/workflow-config.md' "$before_dir" not-applied
  assert_check "Step 3 idempotency: skip on v1.3.0" \
    'grep -q "if Supabase / Postgres / MongoDB touched" .claude/workflow-config.md' "$after_dir" applied

  # Step 4: design_critique entry in config.json
  assert_check "Step 4 idempotency: needs apply on v1.2.0" \
    'jq -e ".hooks.pre_phase.design_critique" .planning/config.json >/dev/null' "$before_dir" not-applied
  assert_check "Step 4 idempotency: skip on v1.3.0" \
    'jq -e ".hooks.pre_phase.design_critique" .planning/config.json >/dev/null' "$after_dir" applied

  # Step 5: post_phase.security.sub_gates in config.json
  # Use `// []` to handle the missing-path case (jq otherwise exits 4 on null
  # path traversal, which still satisfies "non-zero = not applied" but is
  # noisier than the contract intends).
  assert_check "Step 5 idempotency: needs apply on v1.2.0" \
    'jq -e "(.hooks.post_phase.security.sub_gates // []) | any(.skill == \"database-sentinel:audit\")" .planning/config.json >/dev/null 2>&1' "$before_dir" not-applied
  assert_check "Step 5 idempotency: skip on v1.3.0" \
    'jq -e "(.hooks.post_phase.security.sub_gates // []) | any(.skill == \"database-sentinel:audit\")" .planning/config.json >/dev/null 2>&1' "$after_dir" applied

  # Step 6: finishing.impeccable_audit and db_pre_launch_audit
  assert_check "Step 6 idempotency: needs apply on v1.2.0" \
    'jq -e ".hooks.finishing.impeccable_audit and .hooks.finishing.db_pre_launch_audit" .planning/config.json >/dev/null' "$before_dir" not-applied
  assert_check "Step 6 idempotency: skip on v1.3.0" \
    'jq -e ".hooks.finishing.impeccable_audit and .hooks.finishing.db_pre_launch_audit" .planning/config.json >/dev/null' "$after_dir" applied

  # Step 7: Pre-Phase Hook 1 expansion in CLAUDE.md
  assert_check "Step 7 idempotency: needs apply on v1.2.0" \
    'grep -q "Brainstorm UI plans + design critique" CLAUDE.md' "$before_dir" not-applied
  assert_check "Step 7 idempotency: skip on v1.3.0" \
    'grep -q "Brainstorm UI plans + design critique" CLAUDE.md' "$after_dir" applied

  # Step 8: Post-Phase Hook 8 expansion in CLAUDE.md
  # Anchor on a unique phrase from the inserted Hook 8 paragraph to avoid
  # spurious matches on bare skill-name mentions elsewhere in CLAUDE.md.
  assert_check "Step 8 idempotency: needs apply on v1.2.0" \
    'grep -q "produces exact SQL DDL fixes" CLAUDE.md' "$before_dir" not-applied
  assert_check "Step 8 idempotency: skip on v1.3.0" \
    'grep -q "produces exact SQL DDL fixes" CLAUDE.md' "$after_dir" applied

  # Step 9: ADR template copied into project
  assert_check "Step 9 idempotency: needs apply on v1.2.0" \
    'test -f templates/adr-db-security-acceptance.md' "$before_dir" not-applied
  assert_check "Step 9 idempotency: skip on v1.3.0" \
    'test -f templates/adr-db-security-acceptance.md' "$after_dir" applied

  # Step 10: version bump
  assert_check "Step 10 idempotency: needs apply on v1.2.0" \
    'grep -q "^version: 1.3.0" .claude/skills/agentic-apps-workflow/SKILL.md' "$before_dir" not-applied
  assert_check "Step 10 idempotency: skip on v1.3.0" \
    'grep -q "^version: 1.3.0" .claude/skills/agentic-apps-workflow/SKILL.md' "$after_dir" applied
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0009 — Vendor CLAUDE.md workflow block
# WORKFLOW — verify body specific to migration 0009 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
#
# Unlike 0001, 0009's fixtures are HAND-BUILT (not extracted from git refs).
# The "pre-existing inlined block" state is what consumer projects look like
# *as of today*, not what claude-workflow itself ever shipped.
# See migrations/test-fixtures/0009/README.md for scenario semantics.

test_migration_0009() {
  echo ""
  echo "${YELLOW}━━━ Migration 0009 — Vendor CLAUDE.md workflow block ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0009"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing at $fixtures"
    SKIP=$((SKIP+1))
    return
  fi

  # Copy each scenario into a temp dir (the harness's run_check evals the
  # check inside the fixture; using temp copies keeps the source fixtures
  # read-only and matches 0001's pattern of mutable working dirs.)
  local fresh_dir="$(mktemp -d -t migration-0009-fresh-XXXXXX)"
  local inlined_pristine_dir="$(mktemp -d -t migration-0009-inlpr-XXXXXX)"
  local inlined_customised_dir="$(mktemp -d -t migration-0009-inlcu-XXXXXX)"
  local vendored_dir="$(mktemp -d -t migration-0009-vend-XXXXXX)"
  local idempotent_dir="$(mktemp -d -t migration-0009-idem-XXXXXX)"
  trap "rm -rf '$fresh_dir' '$inlined_pristine_dir' '$inlined_customised_dir' '$vendored_dir' '$idempotent_dir'" RETURN

  cp -R "$fixtures/before-fresh/." "$fresh_dir/"
  cp -R "$fixtures/before-inlined-pristine/." "$inlined_pristine_dir/"
  cp -R "$fixtures/before-inlined-customised/." "$inlined_customised_dir/"
  cp -R "$fixtures/after-vendored/." "$vendored_dir/"
  cp -R "$fixtures/after-idempotent/." "$idempotent_dir/"

  echo "  fresh:                $fresh_dir"
  echo "  inlined-pristine:     $inlined_pristine_dir"
  echo "  inlined-customised:   $inlined_customised_dir"
  echo "  vendored (after):     $vendored_dir"
  echo "  idempotent (after2):  $idempotent_dir"

  # ── Step 1: vendored file exists ──────────────────────────────────────────
  # Idempotency check from migration 0009: `test -f .claude/claude-md/workflow.md`
  assert_check "Step 1 idempotency: needs apply on before-fresh" \
    'test -f .claude/claude-md/workflow.md' "$fresh_dir" not-applied
  assert_check "Step 1 idempotency: needs apply on before-inlined-pristine" \
    'test -f .claude/claude-md/workflow.md' "$inlined_pristine_dir" not-applied
  assert_check "Step 1 idempotency: needs apply on before-inlined-customised" \
    'test -f .claude/claude-md/workflow.md' "$inlined_customised_dir" not-applied
  assert_check "Step 1 idempotency: skip on after-vendored" \
    'test -f .claude/claude-md/workflow.md' "$vendored_dir" applied
  assert_check "Step 1 idempotency: skip on after-idempotent" \
    'test -f .claude/claude-md/workflow.md' "$idempotent_dir" applied

  # ── Step 2: vendored content current (canonical marker present) ──────────
  # Idempotency check: `grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md`
  # Note: when the file doesn't exist, grep returns non-zero — same outcome
  # as "content not current". The migration runtime distinguishes via Step 1
  # ordering (Step 2 only runs after Step 1 succeeds).
  assert_check "Step 2 idempotency: needs apply on before-fresh (no file)" \
    'grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md 2>/dev/null' "$fresh_dir" not-applied
  assert_check "Step 2 idempotency: needs apply on before-inlined-pristine (no file)" \
    'grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md 2>/dev/null' "$inlined_pristine_dir" not-applied
  assert_check "Step 2 idempotency: needs apply on before-inlined-customised (no file)" \
    'grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md 2>/dev/null' "$inlined_customised_dir" not-applied
  assert_check "Step 2 idempotency: skip on after-vendored" \
    'grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md' "$vendored_dir" applied
  assert_check "Step 2 idempotency: skip on after-idempotent" \
    'grep -q "Superpowers Integration Hooks (MANDATORY" .claude/claude-md/workflow.md' "$idempotent_dir" applied

  # ── Step 3: CLAUDE.md links to vendored file ──────────────────────────────
  # Idempotency check: `grep -q "claude-md/workflow.md" CLAUDE.md`
  assert_check "Step 3 idempotency: needs apply on before-fresh" \
    'grep -q "claude-md/workflow.md" CLAUDE.md' "$fresh_dir" not-applied
  assert_check "Step 3 idempotency: needs apply on before-inlined-pristine" \
    'grep -q "claude-md/workflow.md" CLAUDE.md' "$inlined_pristine_dir" not-applied
  assert_check "Step 3 idempotency: needs apply on before-inlined-customised" \
    'grep -q "claude-md/workflow.md" CLAUDE.md' "$inlined_customised_dir" not-applied
  assert_check "Step 3 idempotency: skip on after-vendored" \
    'grep -q "claude-md/workflow.md" CLAUDE.md' "$vendored_dir" applied
  assert_check "Step 3 idempotency: skip on after-idempotent" \
    'grep -q "claude-md/workflow.md" CLAUDE.md' "$idempotent_dir" applied

  # ── Step 4: inlined block absent (extraction complete) ────────────────────
  # Idempotency check: `! grep -q "^## Superpowers Integration Hooks (MANDATORY" CLAUDE.md`
  # "applied" here means the inlined block is GONE from CLAUDE.md (or was
  # never there) — so the step doesn't need to run.
  assert_check "Step 4 idempotency: skip on before-fresh (nothing to extract)" \
    '! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md' "$fresh_dir" applied
  assert_check "Step 4 idempotency: needs apply on before-inlined-pristine (block present)" \
    '! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md' "$inlined_pristine_dir" not-applied
  assert_check "Step 4 idempotency: needs apply on before-inlined-customised (block present)" \
    '! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md' "$inlined_customised_dir" not-applied
  assert_check "Step 4 idempotency: skip on after-vendored" \
    '! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md' "$vendored_dir" applied
  assert_check "Step 4 idempotency: skip on after-idempotent" \
    '! grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md' "$idempotent_dir" applied

  # ── Step 4 detection signature (paste-verbatim smoking gun) ───────────────
  # The verbatim H1 line proves the block was pasted from the deprecated
  # template (vs. inlined some other way). Only before-inlined-pristine has
  # it (modeling fx-signal-agent's case); the customised fixture omits the
  # H1 (modeling cparx, which dropped the H1 during a manual cleanup pass).
  assert_check "Step 4 detection: paste-verbatim absent on before-fresh" \
    '! grep -q "^# CLAUDE.md Sections — paste into your project" CLAUDE.md' "$fresh_dir" applied
  assert_check "Step 4 detection: paste-verbatim PRESENT on before-inlined-pristine" \
    'grep -q "^# CLAUDE.md Sections — paste into your project" CLAUDE.md' "$inlined_pristine_dir" applied
  assert_check "Step 4 detection: paste-verbatim absent on before-inlined-customised" \
    '! grep -q "^# CLAUDE.md Sections — paste into your project" CLAUDE.md' "$inlined_customised_dir" applied
  assert_check "Step 4 detection: paste-verbatim absent on after-vendored" \
    '! grep -q "^# CLAUDE.md Sections — paste into your project" CLAUDE.md' "$vendored_dir" applied

  # ── Step 4 detection (apply-step bash): INLINED variable lands correctly ──
  # FLAG-5 follow-up: exercises the actual detection bash from Step 4's apply
  # block, not just the idempotency check. This catches the heading-level
  # mismatch that BLOCK-1 surfaced — if the regex were wrong, INLINED would
  # not flip to 1 against the legacy-H3 fixtures, and these assertions would
  # fail loudly.
  detect_inlined() {
    local fixture="$1"
    ( cd "$fixture" && \
      INLINED=0 && \
      grep -qE "^#{2,4} Superpowers Integration Hooks \(MANDATORY" CLAUDE.md && INLINED=1
      PASTED_VERBATIM=0
      grep -qE "^# CLAUDE.md Sections [—-] paste into your project's CLAUDE.md" CLAUDE.md \
        && PASTED_VERBATIM=1 \
        && INLINED=1
      echo "$INLINED" )
  }
  local inlined_fresh="$(detect_inlined "$fresh_dir")"
  local inlined_pristine="$(detect_inlined "$inlined_pristine_dir")"
  local inlined_customised="$(detect_inlined "$inlined_customised_dir")"
  local inlined_vendored="$(detect_inlined "$vendored_dir")"
  if [ "$inlined_fresh" = "0" ]; then
    echo "  ${GREEN}✓${RESET} Step 4 apply-bash: INLINED=0 on before-fresh"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Step 4 apply-bash: INLINED=$inlined_fresh on before-fresh (expected 0)"
    FAIL=$((FAIL+1))
  fi
  if [ "$inlined_pristine" = "1" ]; then
    echo "  ${GREEN}✓${RESET} Step 4 apply-bash: INLINED=1 on before-inlined-pristine (H3 marker + smoking-gun H1)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Step 4 apply-bash: INLINED=$inlined_pristine on before-inlined-pristine (expected 1) — REGRESSION OF BLOCK-1"
    FAIL=$((FAIL+1))
  fi
  if [ "$inlined_customised" = "1" ]; then
    echo "  ${GREEN}✓${RESET} Step 4 apply-bash: INLINED=1 on before-inlined-customised (H3 marker only, no smoking-gun H1)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Step 4 apply-bash: INLINED=$inlined_customised on before-inlined-customised (expected 1) — REGRESSION OF BLOCK-1"
    FAIL=$((FAIL+1))
  fi
  if [ "$inlined_vendored" = "0" ]; then
    echo "  ${GREEN}✓${RESET} Step 4 apply-bash: INLINED=0 on after-vendored"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Step 4 apply-bash: INLINED=$inlined_vendored on after-vendored (expected 0)"
    FAIL=$((FAIL+1))
  fi

  # ── Step 4 detection: GSD Workflow Enforcement section presence ───────────
  # BLOCK-2 verification: the inlined block extends through ## GSD Workflow
  # Enforcement and ## Skill routing in legacy projects. The before-* fixtures
  # MUST carry these sections so the extraction-range fix is exercised.
  assert_check "BLOCK-2: inlined-pristine has trailing ## GSD Workflow Enforcement section" \
    'grep -q "^## GSD Workflow Enforcement" CLAUDE.md' "$inlined_pristine_dir" applied
  assert_check "BLOCK-2: inlined-pristine has trailing ## Skill routing section" \
    'grep -q "^## Skill routing" CLAUDE.md' "$inlined_pristine_dir" applied
  assert_check "BLOCK-2: inlined-customised has trailing ## GSD Workflow Enforcement section" \
    'grep -q "^## GSD Workflow Enforcement" CLAUDE.md' "$inlined_customised_dir" applied
  assert_check "BLOCK-2: inlined-customised has trailing ## Skill routing section" \
    'grep -q "^## Skill routing" CLAUDE.md' "$inlined_customised_dir" applied
  assert_check "BLOCK-2: after-vendored has NO trailing ## Skill routing inline (only the reference link)" \
    '! grep -q "^## Skill routing" CLAUDE.md' "$vendored_dir" applied

  # ── Step 5: version bump ──────────────────────────────────────────────────
  # Idempotency check: `grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md`
  assert_check "Step 5 idempotency: needs apply on before-fresh (still 1.6.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$fresh_dir" not-applied
  assert_check "Step 5 idempotency: needs apply on before-inlined-pristine (still 1.6.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$inlined_pristine_dir" not-applied
  assert_check "Step 5 idempotency: needs apply on before-inlined-customised (still 1.6.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$inlined_customised_dir" not-applied
  assert_check "Step 5 idempotency: skip on after-vendored" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$vendored_dir" applied
  assert_check "Step 5 idempotency: skip on after-idempotent" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$idempotent_dir" applied
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0010 — post-process GSD section markers in CLAUDE.md
# WORKFLOW — verify body specific to migration 0010 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
#
# Unlike 0001 and 0009 (which exercise idempotency checks only), 0010 ships
# an actual executable script — `templates/.claude/hooks/normalize-claude-md.sh`.
# The harness can therefore run the script directly and diff its output
# against expected goldens. Fixtures are pair-shaped: <input>/CLAUDE.md plus
# <input>/expected/CLAUDE.md. See migrations/test-fixtures/0010/README.md.

test_migration_0010() {
  echo ""
  echo "${YELLOW}━━━ Migration 0010 — Post-process GSD section markers ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0010"
  local script="$REPO_ROOT/templates/.claude/hooks/normalize-claude-md.sh"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing at $fixtures"
    SKIP=$((SKIP+1))
    return
  fi
  # Missing script is a FAIL (the script IS the migration artifact under
  # test; absent it the migration cannot deliver its contract). Diverges
  # from 0001's and 0009's SKIP-on-missing-fixtures because those tests
  # only verify idempotency-check correctness, not an executable artifact.
  if [ ! -x "$script" ]; then
    echo "  ${RED}✗${RESET} script missing or non-executable at $script — RED state, awaiting GREEN implementation"
    FAIL=$((FAIL+1))
    return
  fi

  # Each scenario gets its own temp dir; the script is invoked with CWD set
  # to that temp dir so source-existence checks resolve relative to the fixture.
  run_normalize() {
    local scenario="$1"
    local tmp="$(mktemp -d -t "migration-0010-${scenario}-XXXXXX")"
    cp -R "$fixtures/$scenario/." "$tmp/"
    rm -rf "$tmp/expected"
    ( cd "$tmp" && "$script" "$tmp/CLAUDE.md" >/dev/null 2>&1 )
    echo "$tmp"
  }

  assert_diff() {
    local label="$1" actual="$2" expected="$3"
    if diff -u "$expected" "$actual" >/dev/null 2>&1; then
      echo "  ${GREEN}✓${RESET} $label"
      PASS=$((PASS+1))
    else
      echo "  ${RED}✗${RESET} $label — diff against expected:"
      diff -u "$expected" "$actual" 2>&1 | head -40 | sed 's/^/      /'
      FAIL=$((FAIL+1))
    fi
  }

  assert_line_count_le() {
    local label="$1" file="$2" max="$3"
    local count="$(wc -l < "$file" | tr -d ' ')"
    if [ "$count" -le "$max" ]; then
      echo "  ${GREEN}✓${RESET} $label (got $count, max $max)"
      PASS=$((PASS+1))
    else
      echo "  ${RED}✗${RESET} $label (got $count, max $max)"
      FAIL=$((FAIL+1))
    fi
  }

  # ── Scenario: fresh ──────────────────────────────────────────────────────
  # No markers; script must be a no-op (output == input).
  local fresh_tmp="$(run_normalize fresh)"
  assert_diff "fresh: no-op preserves content byte-for-byte" \
    "$fresh_tmp/CLAUDE.md" "$fixtures/fresh/expected/CLAUDE.md"

  # ── Scenario: inlined-7-sections ─────────────────────────────────────────
  # All 7 markers inlined with valid sources. Script must normalize each to
  # the self-closing form with reference link.
  local inlined7_tmp="$(run_normalize inlined-7-sections)"
  assert_diff "inlined-7-sections: 7-block normalization matches golden" \
    "$inlined7_tmp/CLAUDE.md" "$fixtures/inlined-7-sections/expected/CLAUDE.md"

  # ── Scenario: inlined-source-missing ─────────────────────────────────────
  # `project` block points to NONEXISTENT.md; must be preserved. `stack` has
  # a valid source; must be normalized.
  local missing_tmp="$(run_normalize inlined-source-missing)"
  assert_diff "inlined-source-missing: preserves block with missing source; normalizes others" \
    "$missing_tmp/CLAUDE.md" "$fixtures/inlined-source-missing/expected/CLAUDE.md"

  # ── Scenario: with-0009-vendored ─────────────────────────────────────────
  # 0009's 5-line workflow reference must be UNTOUCHED (no GSD markers).
  # One inlined `project` block must be normalized.
  local vendored_tmp="$(run_normalize with-0009-vendored)"
  assert_diff "with-0009-vendored: 0009 reference untouched; project block normalized" \
    "$vendored_tmp/CLAUDE.md" "$fixtures/with-0009-vendored/expected/CLAUDE.md"

  # ── Scenario: cparx-shape ────────────────────────────────────────────────
  # Representative-scale fixture (~339L input). Expected output ≤ 200L per
  # PLAN.md Decision F. Documented as the integration test for line-count
  # math. The real cparx end-to-end verification (0009 + 0010 applied to a
  # copy of cparx CLAUDE.md) runs in the phase's VERIFICATION.md step.
  local cparx_tmp="$(run_normalize cparx-shape)"
  assert_line_count_le "cparx-shape: normalized output ≤ 200 lines" \
    "$cparx_tmp/CLAUDE.md" 200

  # ── Idempotency: second run of the script is a no-op ─────────────────────
  # Re-run script against already-normalized output; result must equal the
  # first-pass output byte-for-byte. Proves the self-closing form is stable.
  local idem_tmp="$(mktemp -d -t migration-0010-idem-XXXXXX)"
  cp -R "$fixtures/inlined-7-sections/." "$idem_tmp/"
  rm -rf "$idem_tmp/expected"
  ( cd "$idem_tmp" && "$script" "$idem_tmp/CLAUDE.md" >/dev/null 2>&1 )
  cp "$idem_tmp/CLAUDE.md" "$idem_tmp/CLAUDE.md.pass1"
  ( cd "$idem_tmp" && "$script" "$idem_tmp/CLAUDE.md" >/dev/null 2>&1 )
  if diff -u "$idem_tmp/CLAUDE.md.pass1" "$idem_tmp/CLAUDE.md" >/dev/null 2>&1; then
    echo "  ${GREEN}✓${RESET} idempotency: second run produces identical output"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} idempotency: second run differs from first"
    diff -u "$idem_tmp/CLAUDE.md.pass1" "$idem_tmp/CLAUDE.md" 2>&1 | head -20 | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi

  # ── Script exits cleanly on a non-existent CLAUDE.md ─────────────────────
  local missing_input="$(mktemp -d -t migration-0010-noinput-XXXXXX)"
  if "$script" "$missing_input/NONEXISTENT.md" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} non-existent input: script exited 0 (expected non-zero)"
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} non-existent input: script exits non-zero"
    PASS=$((PASS+1))
  fi

  # ── CSO H1: refuse non-CLAUDE.md basename ────────────────────────────────
  # Phase-07 CSO audit (SECURITY.md finding H1): the script must refuse to
  # write to paths whose basename is not exactly CLAUDE.md. Otherwise a
  # curious user or misconfigured hook could clobber /etc/hosts or similar.
  local h1_tmp="$(mktemp -d -t migration-0010-h1-XXXXXX)"
  cp "$fixtures/inlined-7-sections/CLAUDE.md" "$h1_tmp/NOTCLAUDE.md"
  if "$script" "$h1_tmp/NOTCLAUDE.md" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} CSO H1: script accepted non-CLAUDE.md basename"
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} CSO H1: script refuses non-CLAUDE.md basename"
    PASS=$((PASS+1))
  fi

  # ── CSO M1: refuse symlink ───────────────────────────────────────────────
  # SECURITY.md M1: `cp` would follow a symlink and rewrite the target.
  # A symlink CLAUDE.md → /etc/hosts would clobber the system file.
  local m1_tmp="$(mktemp -d -t migration-0010-m1-XXXXXX)"
  echo "stub target" > "$m1_tmp/real-target.md"
  ln -s "$m1_tmp/real-target.md" "$m1_tmp/CLAUDE.md"
  if "$script" "$m1_tmp/CLAUDE.md" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} CSO M1: script accepted symlink input"
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} CSO M1: script refuses symlink input"
    PASS=$((PASS+1))
  fi

  # ── CSO M2: DoS guard on 5 MiB+ inputs ───────────────────────────────────
  # SECURITY.md M2: a 200k+ line CLAUDE.md exhausts the 5s PostToolUse
  # timeout. Early-exit at 5 MiB.
  local m2_tmp="$(mktemp -d -t migration-0010-m2-XXXXXX)"
  # Generate a >5 MiB file cheaply (no markers, just bulk content).
  yes "X" 2>/dev/null | head -n 5500000 > "$m2_tmp/CLAUDE.md"
  if "$script" "$m2_tmp/CLAUDE.md" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} CSO M2: script processed >5 MiB input (should refuse)"
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} CSO M2: script refuses >5 MiB input"
    PASS=$((PASS+1))
  fi

  # ── Stage-2 BLOCK-1: binary (NUL-containing) input ───────────────────────
  # REVIEW.md Stage 2 finding BLOCK-1: pre-fix, binary input caused
  # `read -r` to stop at the first NUL and the temp output to be empty;
  # `cp` then truncated the original. Fix: refuse NUL-containing input.
  local b1_tmp="$(mktemp -d -t migration-0010-block1-XXXXXX)"
  printf '<!-- GSD:project-start source:PROJECT.md -->\n\x00binary\n<!-- GSD:project-end -->\n' \
    >"$b1_tmp/CLAUDE.md"
  cp "$b1_tmp/CLAUDE.md" "$b1_tmp/CLAUDE.md.original"
  if "$script" "$b1_tmp/CLAUDE.md" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-1: script accepted binary input"
    FAIL=$((FAIL+1))
  else
    if diff -q "$b1_tmp/CLAUDE.md" "$b1_tmp/CLAUDE.md.original" >/dev/null 2>&1; then
      echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-1: script refuses binary; original preserved"
      PASS=$((PASS+1))
    else
      echo "  ${RED}✗${RESET} Stage-2 BLOCK-1: script refused but ALSO mutated the file"
      FAIL=$((FAIL+1))
    fi
  fi

  # ── Stage-2 BLOCK-2: markers inside fenced code blocks ───────────────────
  # Documentation examples inside ``` fences must NOT be normalized.
  local b2_tmp="$(mktemp -d -t migration-0010-block2-XXXXXX)"
  cat >"$b2_tmp/CLAUDE.md" <<'EOF'
# Project docs

Below is an example marker syntax — do NOT rewrite:

```markdown
<!-- GSD:project-start source:PROJECT.md -->
## Project
This is example content inside a code fence.
<!-- GSD:project-end -->
```

End of docs.
EOF
  cp "$b2_tmp/CLAUDE.md" "$b2_tmp/CLAUDE.md.original"
  "$script" "$b2_tmp/CLAUDE.md" >/dev/null 2>&1
  if diff -q "$b2_tmp/CLAUDE.md" "$b2_tmp/CLAUDE.md.original" >/dev/null 2>&1; then
    echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-2: markers inside fenced code block preserved verbatim"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-2: markers inside fenced code block were normalized"
    FAIL=$((FAIL+1))
  fi

  # ── Stage-2 BLOCK-3: CRLF line endings ───────────────────────────────────
  # Pre-fix: regex didn't match `\r` before `$`, so marker detection
  # silently failed but collapse_blank_runs still mutated the file →
  # partial mutation. Post-fix: CR stripped at read time; full
  # normalization happens.
  local b3_tmp="$(mktemp -d -t migration-0010-block3-XXXXXX)"
  printf '# Test\r\n\r\n<!-- GSD:project-start source:PROJECT.md -->\r\n## Project\r\n\r\nInline content.\r\n<!-- GSD:project-end -->\r\n' \
    >"$b3_tmp/CLAUDE.md"
  mkdir -p "$b3_tmp/.planning"
  touch "$b3_tmp/.planning/PROJECT.md"
  ( cd "$b3_tmp" && "$script" "$b3_tmp/CLAUDE.md" >/dev/null 2>&1 )
  if grep -q '<!-- GSD:project source:PROJECT.md /-->' "$b3_tmp/CLAUDE.md"; then
    echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-3: CRLF input normalized to self-closing form"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-3: CRLF input did NOT normalize (regex still doesn't match)"
    FAIL=$((FAIL+1))
  fi

  # ── Stage-2 BLOCK-5: non-canonical slug preserved ────────────────────────
  # `<!-- GSD:wibble-start -->` is custom user-authored; script must
  # preserve, not normalize.
  local b5_tmp="$(mktemp -d -t migration-0010-block5-XXXXXX)"
  cat >"$b5_tmp/CLAUDE.md" <<'EOF'
# Project

<!-- GSD:wibble-start source:PROJECT.md -->
## Custom Wibble Section

User-authored block; not GSD-canonical. Should be left alone.
<!-- GSD:wibble-end -->

End.
EOF
  cp "$b5_tmp/CLAUDE.md" "$b5_tmp/CLAUDE.md.original"
  mkdir -p "$b5_tmp/.planning"
  touch "$b5_tmp/.planning/PROJECT.md"
  ( cd "$b5_tmp" && "$script" "$b5_tmp/CLAUDE.md" >/dev/null 2>&1 )
  if diff -q "$b5_tmp/CLAUDE.md" "$b5_tmp/CLAUDE.md.original" >/dev/null 2>&1; then
    echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-5: non-canonical slug 'wibble' preserved"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-5: non-canonical slug was modified"
    FAIL=$((FAIL+1))
  fi

  # ── Stage-2 BLOCK-6: nested -start markers rejected ──────────────────────
  local b6_tmp="$(mktemp -d -t migration-0010-block6-XXXXXX)"
  cat >"$b6_tmp/CLAUDE.md" <<'EOF'
<!-- GSD:project-start source:PROJECT.md -->
## Project
Outer content.
<!-- GSD:stack-start source:codebase/STACK.md -->
Inner content that should NOT be consumed silently.
<!-- GSD:stack-end -->
More outer content.
<!-- GSD:project-end -->
EOF
  mkdir -p "$b6_tmp/.planning/codebase"
  touch "$b6_tmp/.planning/PROJECT.md" "$b6_tmp/.planning/codebase/STACK.md"
  if ( cd "$b6_tmp" && "$script" "$b6_tmp/CLAUDE.md" >/dev/null 2>&1 ); then
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-6: nested markers accepted (should exit 2 malformed)"
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-6: nested markers rejected as malformed"
    PASS=$((PASS+1))
  fi

  # ── Stage-2 BLOCK-4 (documented-risk): atomicity smoke test ──────────────
  # mv-based atomicity means two concurrent invocations land on a single
  # final state, never a mid-write read. Full concurrency proof would
  # need parallel goroutines + race detection; here we just confirm one
  # invocation leaves the file in a CONSISTENT (non-empty, non-partial)
  # state. The migration markdown documents the residual risk.
  local b4_tmp="$(mktemp -d -t migration-0010-block4-XXXXXX)"
  cp -R "$fixtures/inlined-7-sections/." "$b4_tmp/"
  rm -rf "$b4_tmp/expected"
  ( cd "$b4_tmp" && "$script" "$b4_tmp/CLAUDE.md" >/dev/null 2>&1 )
  if [ -s "$b4_tmp/CLAUDE.md" ] && diff -q "$b4_tmp/CLAUDE.md" "$fixtures/inlined-7-sections/expected/CLAUDE.md" >/dev/null 2>&1; then
    echo "  ${GREEN}✓${RESET} Stage-2 BLOCK-4: atomic mv leaves file in fully-formed state"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} Stage-2 BLOCK-4: file was partial-written or mismatched"
    FAIL=$((FAIL+1))
  fi

  # Cleanup
  rm -rf "$fresh_tmp" "$inlined7_tmp" "$missing_tmp" "$vendored_tmp" "$cparx_tmp" \
         "$idem_tmp" "$missing_input" "$h1_tmp" "$m1_tmp" "$m2_tmp" \
         "$b1_tmp" "$b2_tmp" "$b3_tmp" "$b4_tmp" "$b5_tmp" "$b6_tmp"
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0005 — Multi-AI plan review enforcement (PreToolUse hook)
# WORKFLOW — verify body specific to migration 0005 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
#
# Exercises every decision branch of templates/.claude/hooks/multi-ai-review-gate.sh
# via 11 fixtures under migrations/test-fixtures/0005/. Per the phase 08
# REVIEWS.md amendments: strict stderr line-presence matching (not substring
# slop), MultiEdit-tool fixture proves matcher closure, hostile-filename
# fixture asserts /tmp/HOSTILE_MARKER survives the run.
#
# Like 0010: FAIL if the script is missing (RED state, the script IS the
# artifact under test). SKIP only if the fixtures dir is missing.

test_migration_0005() {
  retired_migration 0005 "Multi-AI plan review enforcement gate" 'multi-ai-review-gate.sh'
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0006 — LLM wiki compiler integration (install + rollback scripts)
# WORKFLOW — verify body specific to migration 0006 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
#
# Exercises every decision branch of templates/.claude/scripts/install-wiki-compiler.sh
# via 15 fixtures under migrations/test-fixtures/0006/. Each fixture builds a
# sandboxed $HOME and runs the install script against it; the harness asserts
# exit code, stderr matching, and (if verify.sh present) post-apply state.
#
# codex F1: sandbox-escape guard — the harness greps the install script for
# non-sandboxed absolute paths after each invocation. If the script wrote to
# the real /Users/.../.claude or /Users/.../Sourcecode, the guard fails.

test_migration_0006() {
  echo ""
  echo "${YELLOW}━━━ Migration 0006 — LLM wiki compiler integration ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0006"
  local install_script="$REPO_ROOT/templates/.claude/scripts/install-wiki-compiler.sh"
  local rollback_script="$REPO_ROOT/templates/.claude/scripts/rollback-wiki-compiler.sh"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing at $fixtures"
    SKIP=$((SKIP+1))
    return
  fi
  if [ ! -x "$install_script" ]; then
    echo "  ${RED}✗${RESET} install script missing or non-executable at $install_script — RED state"
    FAIL=$((FAIL+1))
    return
  fi
  if [ ! -x "$rollback_script" ]; then
    echo "  ${RED}✗${RESET} rollback script missing or non-executable at $rollback_script — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # codex F1: sandbox-escape pre-check. Grep the install script for hardcoded
  # /Users/donald paths (would indicate accidental real-home write).
  if grep -E '/(Users/donald|home/[a-z][a-z]*/)' "$install_script" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} install script contains hardcoded real-home paths — sandbox escape risk"
    FAIL=$((FAIL+1))
    return
  fi

  run_0006_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0006-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # Setup (runs with HOME=$fake_home, REPO_ROOT, FIXTURES_ROOT visible)
    if [ -x "$fixdir/setup.sh" ]; then
      ( cd "$tmp" && HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" "$fixdir/setup.sh" >/dev/null 2>&1 )
    fi

    # Run install
    local stderr_capture="$tmp/.stderr"
    local actual_exit
    ( cd "$fake_home" && HOME="$fake_home" bash "$install_script" 2> "$stderr_capture" >/dev/null )
    actual_exit=$?

    # Compare exit
    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$actual_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — exit $actual_exit, expected $expected_exit"
      if [ -s "$stderr_capture" ]; then
        echo "      actual stderr:"
        sed 's/^/        /' "$stderr_capture" | head -10
      fi
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    # Strict stderr line-presence check (carry-over from phase 08 F1)
    if [ -f "$fixdir/expected-stderr.txt" ] && [ -s "$fixdir/expected-stderr.txt" ]; then
      local missing_line=""
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        if ! grep -F -q -- "$line" "$stderr_capture"; then
          missing_line="$line"
          break
        fi
      done < "$fixdir/expected-stderr.txt"
      if [ -n "$missing_line" ]; then
        echo "  ${RED}✗${RESET} $fixname — stderr missing line: $missing_line"
        echo "      actual stderr:"
        sed 's/^/        /' "$stderr_capture" | head -10
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      fi
    fi

    # verify.sh — post-apply assertions
    if [ -x "$fixdir/verify.sh" ]; then
      local verify_out
      verify_out=$( cd "$fake_home" && HOME="$fake_home" REPO_ROOT="$REPO_ROOT" bash "$fixdir/verify.sh" 2>&1 )
      local verify_exit=$?
      if [ "$verify_exit" != "0" ]; then
        echo "  ${RED}✗${RESET} $fixname — verify.sh failed: $verify_out"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      fi
    fi

    # Stage 2 FLAG-D: the sandbox-escape post-check was structurally inert
    # (no code writes a `-PHASE09-LEAK-CANARY` file). The real sandbox guard
    # is the pre-grep on line ~879 (no hardcoded /Users/donald paths in the
    # install script). Removed the theater check.

    echo "  ${GREEN}✓${RESET} $fixname (exit $actual_exit)"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0006_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# Retired migrations (v3.0.0, ADR-0044 / migration 0032)
# ─────────────────────────────────────────────────────────────────────────────
# Two families of migration lost their subject in 3.0.0:
#   * gitnexus — 0007 (integration), 0026 (background reindex), 0031
#     (--skip-agents-md re-sync). GitNexus left the workflow entirely.
#   * the PLAN.md-era plan-review gate — 0005 (the gate), 0016 (its ADR-0025
#     phase resolver). Spec §17 MUST NOT ships a standalone plan-review gate
#     under 1.0.0; the obligation moved into stage 2 and is enforced by the
#     §18 change-gate, so multi-ai-review-gate.sh is replaced by
#     openspec-change-gate.sh rather than kept alongside it.
# All are retained on disk as history (§08 supersede-don't-delete) but the
# scaffolder no longer ships their payload, so their fixtures have no subject
# left to exercise.
#
# We do NOT delete the tests and we do NOT stub the payload. Migration 0011's
# SPLIT-03 precedent stubs a payload the scaffolder stopped shipping, but that
# works because 0011's subject is project-local state the stub stands in for.
# 0026/0031's subject IS the engine binary and its behaviour; a stub would only
# assert that the stub works. Instead each retired migration asserts the two
# invariants that must hold forever after removal:
#   1. the migration doc still exists  (history was superseded, not erased)
#   2. no gitnexus payload ships       (the removal is real, not just unwired)
# A revert that reintroduces the engine therefore fails the suite.
retired_migration() {
  local id="$1" label="$2" pattern="$3"
  echo ""
  echo "${YELLOW}━━━ Migration $id — $label (RETIRED in 3.0.0) ━━━${RESET}"

  local doc
  doc="$(find "$REPO_ROOT/migrations" -maxdepth 1 -name "$id-*.md" -print -quit 2>/dev/null)"
  if [ -n "$doc" ] && [ -f "$doc" ]; then
    echo "  ${GREEN}✓${RESET} migration doc retained as history: $(basename "$doc")"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} migration $id doc missing — history must be superseded, not deleted (§08)"
    FAIL=$((FAIL+1))
  fi

  local stray
  stray="$(find "$REPO_ROOT/templates" "$REPO_ROOT/setup/snapshot" \
             -name "$pattern" -print 2>/dev/null | head -5)"
  if [ -z "$stray" ]; then
    echo "  ${GREEN}✓${RESET} no '$pattern' payload ships from templates/ or the snapshot"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} '$pattern' payload reappeared (removed in 3.0.0 — ADR-0044):"
    printf '%s\n' "$stray" | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi

  echo "  ${YELLOW}note${RESET}: fixtures under test-fixtures/$id/ are kept for the record;"
  echo "        migration 0032 removes gitnexus from already-installed projects."
}


# test_migration_0007 — GitNexus code-graph integration (setup-only)
# WORKFLOW — verify body specific to migration 0007 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
#
# Exercises every decision branch of templates/.claude/scripts/install-gitnexus.sh
# + index-family-repos.sh + rollback-gitnexus.sh via 18 fixtures under
# migrations/test-fixtures/0007/. Each fixture builds a sandboxed $HOME with
# stubbed node/npm/gitnexus binaries in $HOME/bin (PATH-prepended).

test_migration_0007() {
  retired_migration 0007 "GitNexus code-graph integration" '*gitnexus*'
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0011 — Spec §10.9 observability enforcement (1.9.3 → 1.10.0)
# WORKFLOW — verify body specific to migration 0011 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
# Migration 0011 is markdown-only (no install script). v1.10.0 ships
# local-only enforcement — no CI workflow installed. The fixture pattern is
# state-comparison: each fixture's setup.sh produces a target sandbox state
# (before-apply, after-apply, or a pre-flight-abort state), and verify.sh
# asserts the migration's idempotency markers + side-effect presence/absence
# behave correctly for that state.
#
# 6 fixtures:
#   01-fresh-apply              — before state; all 4 step idempotency
#                                 checks return non-zero (= "needs apply")
#   02-idempotent-reapply       — after state; all 4 return zero (= "skip")
#   03-no-observability-metadata — pre-flight 1 fails (no observability:)
#   04-no-policy-md             — pre-flight 2 fails (policy.md missing)
#   05-baseline-already-present — Step 1 idempotency catches; Steps 2/3/4
#                                 still need apply
#   06-no-claude-cli            — requires.tool.claude.verify fails

test_migration_0011() {
  echo ""
  echo "${YELLOW}━━━ Migration 0011 — Spec §10.9 observability enforcement ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0011"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # NOTE (SPLIT-03): observability moved to agenticapps-observability, so the
  # scaffolder no longer ships add-observability/scan/SCAN.md inside this repo.
  # The 0011 migration's verify only checks project-local state, not the
  # scaffolder source, so the fixture sandbox uses an inline stub SCAN.md
  # (created in run_0011_fixture below). The old scaffolder-presence sanity
  # check has been removed.

  run_0011_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0011-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # The scaffolder-side files the migration references must live under
    # $HOME/.claude/skills/agenticapps-workflow/ in the sandbox. Observability
    # moved to agenticapps-observability (SPLIT-03), so the scaffolder no longer
    # ships scan/SCAN.md inside this repo — create an inline stub instead. The
    # path is NON-hyphenated to match migration 0011's requires.verify path
    # (~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md).
    mkdir -p "$fake_home/.claude/skills/agenticapps-workflow/add-observability/scan"
    printf '%s\n' '# SCAN (stub — observability moved to agenticapps-observability)' > "$fake_home/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
        REAL_SCAFFOLDER_FILES=1 \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    # No install script to run for a markdown-only migration. Go straight
    # to verify.sh.
    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
      PATH="$fake_home/bin:$PATH" bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0011_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# Migration 0022 — Observability repoint + Phase Sentinel hook (v1.20.0 -> 2.0.0)
# WORKFLOW — verify body specific to migration 0022 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
# Same fixture-runner shape as 0011/0014: each fixture builds a sandboxed $HOME
# (with or without the separately-installed `observability` skill) plus a
# project skeleton at v1.20.0 with a prompt-type Stop hook + an `observability:`
# CLAUDE.md block. verify.sh asserts the migration's POSITIVE idempotency anchors
# and pre-flight behave as expected for that state (command hook present,
# ^version: 2.0.0 present, `skill: observability` present, exit-3 abort message
# when the obs skill is absent).

test_migration_0022() {
  echo ""
  echo "${YELLOW}━━━ Migration 0022 — Observability repoint + Phase Sentinel hook ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0022"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity-check that migration 0022's file itself exists. Until the GREEN
  # commit lands the migration body, this fails — the RED state TDD requires.
  local migration_file="$REPO_ROOT/migrations/0022-observability-repoint-phase-sentinel.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0022_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0022-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0022_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0023 — Prompt-injection defense via injection-guard (2.0.0 -> 2.1.0)
# WORKFLOW — verify body specific to migration 0023 content; stays in claude-workflow.
# Same fixture-replay shape as test_migration_0022: each fixture's setup.sh builds
# a sandboxed before/after/abort state, verify.sh replays the migration's
# deterministic pre-flight / idempotency shell, expected-exit asserts the rc.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0023() {
  echo ""
  echo "${YELLOW}━━━ Migration 0023 — Prompt-injection defense via injection-guard ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0023"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0023-prompt-injection-defense.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0023_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0023-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0023_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0024 — Commit phase artifacts / un-ignore .planning/phases (2.1.0 -> 2.2.0)
# WORKFLOW — verify body specific to migration 0024 content; stays in claude-workflow.
# Same fixture-replay shape as 0022/0023: each fixture's setup.sh builds a
# sandboxed before/after state, verify.sh replays the migration's deterministic
# Step 1/Step 2 shell (and asserts the surgical strip + idempotency),
# expected-exit asserts the rc.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0024() {
  echo ""
  echo "${YELLOW}━━━ Migration 0024 — Commit phase artifacts (un-ignore .planning/phases) ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0024"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0024-commit-planning-phases.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0024_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0024-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0024_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0025 — Knowledge capture / spec §15 (2.2.0 -> 2.3.0)
# WORKFLOW — verify body specific to migration 0025 content; stays in claude-workflow.
# Same fixture-replay shape as 0022/0023/0024: each fixture's setup.sh builds a
# sandboxed before/after state, verify.sh replays the migration's deterministic
# Step 1/2/3 shell (config-block insert, section append extracted from
# $REPO_ROOT/skill/SKILL.md standing in for the scaffolder clone, version bump)
# and asserts surgical insert + idempotency; expected-exit asserts the rc.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0025() {
  echo ""
  echo "${YELLOW}━━━ Migration 0025 — Knowledge capture (spec §15) ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0025"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0025-knowledge-capture.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0025_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0025-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0025_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0026 — GitNexus background reindex hook (2.3.0 -> 2.4.0)
# WORKFLOW — verify body specific to migration 0026 content; stays in claude-workflow.
# Same fixture-replay shape as 0025: each fixture's setup.sh builds a sandboxed
# before state, verify.sh replays the migration's deterministic Step 1/2/3 shell
# (copy engine from $REPO_ROOT/setup/snapshot/hooks, wire the PostToolUse Bash
# entry, bump version) or drives the engine directly (05-engine-behaviour), and
# asserts idempotency + surgical insert; expected-exit asserts the rc.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0026() {
  retired_migration 0026 "GitNexus background reindex" '*gitnexus*'
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0027 — Spec 0.9.0 conformance claim (2.4.0 -> 2.5.0)
# WORKFLOW — verify body specific to migration 0027 content; stays in claude-workflow.
# Same fixture-replay shape as 0025/0026: each fixture's setup.sh builds a
# sandboxed before state, verify.sh replays the migration's deterministic
# Step 1-6 shell (§04 red-flag reorder, Spec deltas insert extracted from
# $REPO_ROOT/skill/SKILL.md standing in for the scaffolder clone, claim raise,
# config repoint + dangling-hook-ref drop, dead-hook removal, version bump) and
# asserts surgical edits + ordering + idempotency; expected-exit asserts the rc.
#
# Coexists with test_migration_0026 (gitnexus background reindex): 0027 was
# rebased onto it when that branch landed first and took the 0026/2.4.0 slot.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0027() {
  echo ""
  echo "${YELLOW}━━━ Migration 0027 — Spec 0.9.0 conformance claim ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0027"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0027-spec-0.9.0-conformance.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0027_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0027-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0027_fixture "$name"
  done
}


# test_migration_0028 — Register .claude/hooks in .prettierignore (2.5.0 -> 2.6.0)
# WORKFLOW — verify body specific to migration 0028; stays in claude-workflow.
# Coexists with test_migration_0026 / test_migration_0027.
test_migration_0028() {
  echo ""
  echo "${YELLOW}━━━ Migration 0028 — Register .claude/hooks in .prettierignore ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0028"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0028-register-prettierignore.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0028_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0028-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0028_fixture "$name"
  done

  # ── setup flow ≡ migration replay (spec/08 Conformance) ────────────────────
  # .prettierignore is a project file, not snapshot payload, so
  # check-snapshot-parity.sh does not compare these two. Nothing else would
  # notice them diverging: the fixtures exercise the migration, and the setup
  # flow has no fixture at all. A predicate fix landing in one and not the
  # other silently breaks §08's end-state equivalence — which is exactly what
  # happened when 0028's predicate was widened for subsuming `.claude` entries.
  # The predicate is written THREE times: the migration's Step 1 idempotency
  # check, the migration's Step 1 apply condition, and the setup flow's copy.
  # The fixtures only ever execute the apply block, so the other two can drift
  # unnoticed — mutation-proven: reverting the idempotency copy alone leaves all
  # four fixtures green. Rather than compare a chosen pair, collect every copy
  # across both files and require exactly one distinct value.
  local setup_file="$REPO_ROOT/setup/SKILL.md"
  local preds distinct count
  preds=$(grep -ho "grep -qE '[^']*' \.prettierignore" "$migration_file" "$setup_file")
  count=$(printf '%s\n' "$preds" | grep -c .)
  distinct=$(printf '%s\n' "$preds" | sort -u | grep -c .)

  if [ "$count" -lt 3 ]; then
    echo "  ${RED}✗${RESET} predicate-parity — expected 3 copies of the predicate, found $count"
    echo "      (migration idempotency + migration apply + setup flow)"
    printf '%s\n' "$preds" | sed 's/^/        /'
    FAIL=$((FAIL+1))
  elif [ "$distinct" -ne 1 ]; then
    echo "  ${RED}✗${RESET} predicate-parity — the $count copies disagree (spec/08 setup ≡ replay)"
    printf '%s\n' "$preds" | sort -u | sed 's/^/        /'
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} predicate-parity — all $count copies agree (migration + setup)"
    PASS=$((PASS+1))
  fi
}

test_migration_0029() {
  echo ""
  echo "${YELLOW}━━━ Migration 0029 — Region-aware §11 placement ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0029"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Until the GREEN commit lands the migration body this check fails — that is
  # the RED state the TDD discipline requires (test before unit-under-test).
  local migration_file="$REPO_ROOT/migrations/0029-region-aware-spec-11-placement.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0029_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0029-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
        "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit="$(cat "$fixdir/expected-exit" 2>/dev/null || echo 0)"

    if [ "$verify_exit" -ne "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — exit $verify_exit, expected $expected_exit"
      printf '%s\n' "$verify_out" | sed 's/^/      /'
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0029_fixture "$name"
  done

  # ── setup flow ≡ migration replay (spec/08 Conformance) ────────────────────
  # The anchor rule lives in two files: migration 0029, which carries 5
  # copies (Step 1 Apply's strip pass, Step 1 Apply's insert pass, Step 1
  # Apply's prose-preservation guard, Step 1 Rollback, and Step 1 Rollback's
  # guard — Rollback is a sibling of Apply, not part of it; each guard re-runs
  # the strip's state machine in reverse and carries the same terminator
  # alternation, so it must agree with the strip it gates), and the setup
  # flow's step e2, which carries 1. The fixtures only exercise the
  # migration, so the setup copy can drift unnoticed — which is exactly what
  # happened to 0028's predicate (#87). Collect every copy across both files
  # and require exactly one distinct value, AND require each file to carry
  # its documented count exactly (3 for the migration, 1 for setup) — a
  # `-lt 1` floor would pass a migration whose copies were partially
  # rewritten to some other shape (2 of 3 dropped, 1 left), since the
  # remaining copy alone still satisfies "at least one" and the surviving
  # value trivially agrees with itself. An exact count turns that partial
  # drift into a direct FAIL instead of leaving it to fixtures 01/02/08 to
  # catch indirectly. Each side still needs its own count and its own
  # failure message — an aggregate-only check can't tell "setup dropped its
  # copy" apart from "migration dropped its copies" (both just make the
  # total go down).
  #
  # Capture by SHAPE — any two-branch `(/^.../ || /^.../)` awk alternation —
  # rather than one hardcoded literal. A fixed-literal search can only prove
  # "this exact byte string appears somewhere"; it can never observe two
  # copies that actually differ (every match IS the literal, by construction,
  # so `distinct` was permanently 1 whenever count was >=1 — dead code), and
  # it false-fails on a *legitimate* co-evolution where both files move
  # together to a newly agreed anchor text that no longer matches the old
  # hardcoded literal. Shape capture fixes both: a genuine disagreement
  # (e.g. one file's branches reordered relative to the other) now shows up
  # as >1 distinct value, and a synchronized re-anchor still agrees.
  #
  # Hazard shared with predicate-parity above: a prose sentence that happens
  # to quote the anchor condition verbatim (e.g. in backticks) would also
  # match and silently count toward parity. No such prose copy exists today.
  #
  # $anchor_shape encodes the STRUCTURE, not the current marker text — a
  # synchronized change to the marker names (e.g. a new region-start comment)
  # needs no update here. Only a structural change (a third alternative, a
  # different grouping) requires updating $anchor_shape itself, in lockstep
  # with both files.
  local setup_file="$REPO_ROOT/setup/SKILL.md"
  local anchor_shape='\(/\^[^/]*/ \|\| /\^[^/]*/\)'
  local anchors mig_matches setup_matches distinct count mig_count setup_count
  anchors=$(grep -hoE "$anchor_shape" "$migration_file" "$setup_file")
  mig_matches=$(grep -hoE "$anchor_shape" "$migration_file")
  setup_matches=$(grep -hoE "$anchor_shape" "$setup_file")
  count=$(printf '%s\n' "$anchors" | grep -c .)
  distinct=$(printf '%s\n' "$anchors" | sort -u | grep -c .)
  mig_count=$(printf '%s\n' "$mig_matches" | grep -c .)
  setup_count=$(printf '%s\n' "$setup_matches" | grep -c .)

  if [ "$mig_count" -ne 5 ]; then
    echo "  ${RED}✗${RESET} anchor-parity — migration 0029 carries $mig_count copies of the anchor rule, expected 5"
    echo "      (Step 1 Apply's strip pass, insert pass, and prose-preservation guard;"
    echo "      Step 1 Rollback and its guard; setup/SKILL.md step e2 has $setup_count)"
    FAIL=$((FAIL+1))
  elif [ "$setup_count" -ne 1 ]; then
    echo "  ${RED}✗${RESET} anchor-parity — setup/SKILL.md step e2 carries $setup_count copies of the anchor rule, expected 1"
    echo "      (migration 0029 has $mig_count copies)"
    FAIL=$((FAIL+1))
  elif [ "$distinct" -ne 1 ]; then
    echo "  ${RED}✗${RESET} anchor-parity — the anchor rule disagrees between migration and setup (spec/08 setup ≡ replay)"
    echo "      migration 0029 ($mig_count copies):"
    printf '%s\n' "$mig_matches" | sort -u | sed 's/^/        /'
    echo "      setup/SKILL.md step e2 ($setup_count copies):"
    printf '%s\n' "$setup_matches" | sort -u | sed 's/^/        /'
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} anchor-parity — all $count copies agree (migration + setup)"
    PASS=$((PASS+1))
  fi
}


test_migration_0030() {
  echo ""
  echo "${YELLOW}━━━ Migration 0030 — Re-sync stale spec §11 block bytes ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0030"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Until the GREEN commit lands the migration body this check fails — that is
  # the RED state the TDD discipline requires (test before unit-under-test).
  local migration_file="$REPO_ROOT/migrations/0030-resync-spec-11-mirror-bytes.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0030_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0030-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
        "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit="$(cat "$fixdir/expected-exit" 2>/dev/null || echo 0)"

    if [ "$verify_exit" -ne "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — exit $verify_exit, expected $expected_exit"
      printf '%s\n' "$verify_out" | sed 's/^/      /'
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0030_fixture "$name"
  done
}


test_migration_0031() {
  retired_migration 0031 "Re-sync the reindex engine with --skip-agents-md" '*gitnexus*'
}


# ─────────────────────────────────────────────────────────────────────────────
# Phase Sentinel hook (GH #58 / D-07) — deterministic Stop gate exit-code cases
# WORKFLOW — inline test (no fixture dir): runs the template hook under a temp
#   CLAUDE_PROJECT_DIR across 3 cases and asserts exit 0/0/2.
# ─────────────────────────────────────────────────────────────────────────────
# Cases:
#   1. no checklist.md                          -> exit 0 (allow)
#   2. checklist.md, all items checked          -> exit 0 (allow)
#   3. checklist.md, >=1 unchecked `- [ ]` item -> exit 2 (block) + prints item

test_phase_sentinel() {
  echo ""
  echo "${YELLOW}━━━ Phase Sentinel hook — deterministic Stop gate (GH #58) ━━━${RESET}"

  local hook="$REPO_ROOT/templates/.claude/hooks/phase-sentinel.sh"
  if [ ! -x "$hook" ]; then
    echo "  ${RED}✗${RESET} hook missing or not executable: $hook — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_sentinel_case() {
    local casename="$1" expected="$2" setup_fn="$3"
    local tmp; tmp="$(mktemp -d -t "phase-sentinel-${casename}-XXXXXX")"
    mkdir -p "$tmp/.planning/current-phase"
    "$setup_fn" "$tmp"
    local out exit_code
    out=$(CLAUDE_PROJECT_DIR="$tmp" bash "$hook" 2>&1)
    exit_code=$?
    if [ "$exit_code" != "$expected" ]; then
      echo "  ${RED}✗${RESET} $casename — exit $exit_code, expected $expected"
      printf '%s\n' "$out" | sed 's/^/        /' | head -5
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi
    echo "  ${GREEN}✓${RESET} $casename (exit $exit_code)"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  # Case 1 — no checklist.md present -> allow (exit 0)
  _setup_no_checklist() { :; }
  run_sentinel_case "no-checklist" 0 _setup_no_checklist

  # Case 2 — checklist with all items checked -> allow (exit 0)
  _setup_all_checked() {
    cat > "$1/.planning/current-phase/checklist.md" <<'EOF_CK'
# Checklist
- [x] task one done
- [x] task two done
EOF_CK
  }
  run_sentinel_case "all-checked" 0 _setup_all_checked

  # Case 3 — checklist with >=1 unchecked item -> block (exit 2)
  _setup_unchecked() {
    cat > "$1/.planning/current-phase/checklist.md" <<'EOF_CK'
# Checklist
- [x] task one done
- [ ] task two NOT done
EOF_CK
  }
  run_sentinel_case "unchecked-blocks" 2 _setup_unchecked

  # Case 4 — huge unchecked list (grep output exceeds the ~64KB pipe buffer) -> still
  # block (exit 2). Regression for the SIGPIPE bug (codex review, SPLIT-03): when grep's
  # matched output overflows the pipe buffer, `head -5` closes the pipe early, grep dies
  # on SIGPIPE, and under `set -euo pipefail` the hook exited 141 before reaching `exit 2`.
  # The line count/length here is deliberately large enough to overflow the buffer; the
  # earlier small unchecked cases fit in the buffer and do NOT exercise this path.
  _setup_many_unchecked() {
    {
      echo "# Checklist"
      for i in $(seq 1 5000); do
        echo "- [ ] task $i NOT done — padding text to push matched output past the pipe buffer"
      done
    } > "$1/.planning/current-phase/checklist.md"
  }
  run_sentinel_case "many-unchecked-blocks-sigpipe" 2 _setup_many_unchecked
}



# ─────────────────────────────────────────────────────────────────────────────
# Migration 0014 — Inject spec §11 canonical block (closes spec 0.4.0 §11)
# WORKFLOW — verify body specific to migration 0014 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
# Same state-comparison pattern as 0013. Each fixture builds a sandboxed
# $HOME with the scaffolder skill tree + a stub vendored §11 block (the
# migration's requires.verify checks for the latter), a per-project workflow
# SKILL.md at v1.12.0 (or v1.14.0 for re-apply), and a fixture-specific
# CLAUDE.md state (§11 anchor present/absent, provenance current/stale,
# heading-without-provenance for the conflict-refuse case).
# verify.sh asserts pre-flight + step idempotency checks return what they
# should for that state.

test_migration_0014() {
  echo ""
  echo "${YELLOW}━━━ Migration 0014 — Inject spec §11 canonical block ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0014"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity-check that the scaffolder ships the vendored §11 block the
  # migration's Step 1 reads bytes from. (We use a STUB copy inside the
  # sandbox to keep tests hermetic, but the real file must exist in the
  # scaffolder repo for `requires.verify` to mean anything.)
  local scaffolder_block="$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  if [ ! -f "$scaffolder_block" ]; then
    echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_block — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # Sanity-check that migration 0014's file itself exists. Until the GREEN
  # commit lands the migration body, this check fails — that's the RED state
  # the TDD discipline requires (test before unit-under-test).
  local migration_file="$REPO_ROOT/migrations/0014-inject-spec-11-coding-discipline.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0014_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0014-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0014_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0015 — Scaffold ts-declare-first skill (closes spec 0.4.0 §13)
# WORKFLOW — verify body specific to migration 0015 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
# Same state-comparison pattern as 0013/0014. Each fixture builds a
# sandboxed $HOME with the scaffolder skill tree containing a stub
# ts-declare-first/SKILL.md (the migration's requires.verify checks for
# the latter), and a fixture-specific $HOME/.claude/skills/ts-declare-first
# state (absent, correct symlink, non-symlink directory, redirected
# symlink). verify.sh asserts pre-flight + Step 1 idempotency checks
# behave as expected for that state.

test_migration_0015() {
  echo ""
  echo "${YELLOW}━━━ Migration 0015 — Scaffold ts-declare-first skill ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0015"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity-check that the scaffolder ships the ts-declare-first skill
  # the migration's Step 1 symlinks to. (Stub copy in sandbox keeps
  # tests hermetic; the real file must exist in the scaffolder repo for
  # `requires.verify` to mean anything.)
  local scaffolder_skill="$REPO_ROOT/ts-declare-first/SKILL.md"
  if [ ! -f "$scaffolder_skill" ]; then
    echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_skill — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # Sanity-check that migration 0015's file itself exists.
  local migration_file="$REPO_ROOT/migrations/0015-add-ts-declare-first-skill.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0015_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0015-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0015_fixture "$name"
  done
}


# ─────────────────────────────────────────────────────────────────────────────
# Preflight-correctness audit (Phase 13)
# SHARED — generic verify-path auditor; walks migration frontmatter and checks
#   requires[*].verify paths on the host; repo-agnostic mechanism
# ─────────────────────────────────────────────────────────────────────────────
# Walks every migration and executes each `requires[*].verify` shell command
# against the host environment. Informational only — failures DO NOT add to
# the suite's global PASS/FAIL counters, since CI environments without all
# host dependencies installed will see expected non-zero counts.
#
# Catches the issue-#18 bug class: a verify path that points at a location
# which doesn't exist on any system. Run pre-PR to surface verify rot before
# it ships.

test_preflight_verify_paths() {
  # WORKFLOW policy wrapper (D-28e / Pattern 3): delegates mechanism to shared lib.
  # run_preflight_verify_paths reads ${STRICT_PREFLIGHT:-0} internally (A5 set -u safe).
  run_preflight_verify_paths "$REPO_ROOT/migrations"
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0016 — Review gate phase-resolution fix (ADR 0025)
# WORKFLOW — verify body specific to migration 0016 content; stays in claude-workflow
# ─────────────────────────────────────────────────────────────────────────────
# The resolver behavior is exercised in detail by fixtures 14/15/16 under
# test-fixtures/0005 (run by test_migration_0005 — they share the hook script).
# This function validates migration 0016's own guarantees: the template hook
# carries the ADR-0025 marker (the idempotency anchor), and a directory-style
# current-phase with an unreviewed/unexecuted plan blocks (the Verify smoke test).
test_migration_0016() {
  retired_migration 0016 "Review gate phase-resolution fix (ADR-0025)" 'multi-ai-review-gate.sh'
}





# ─────────────────────────────────────────────────────────────────────────────
# F4 — SKILL.md version drift test (D-06 / G4)
# Asserts skill/SKILL.md version equals the highest-numbered migration's to_version.
# SHARED — drift-test RUNNER mechanism: the generic grep+awk pattern for comparing
#   a SKILL.md version field against the latest migration to_version is reusable
#   by any repo with the same migration discipline.
#   POLICY NOTE (ADR-0035): the specific coupling rule enforced here —
#   "SKILL.md version == latest migration to_version" — is a WORKFLOW-owned policy,
#   not a repo-agnostic invariant. It encodes claude-workflow's versioning-tracks-
#   migrations discipline. SPLIT-01 may extract the runner mechanism, but the
#   version-coupling rule stays owned by the consumer repo. See ADR-0035.
# ─────────────────────────────────────────────────────────────────────────────

test_skill_md_version_matches_latest_migration_to_version() {
  # WORKFLOW policy wrapper (D-28d / Pattern 2 / ADR-0035 MECHANISM vs POLICY):
  # run_drift_test is the shared mechanism (returns 0/1 only, no PASS/FAIL mutation).
  # This function owns the POLICY: "SKILL.md version == latest migration to_version"
  # is a claude-workflow versioning-tracks-migrations invariant (not a universal law).
  if run_drift_test "$REPO_ROOT/skill/SKILL.md" "$REPO_ROOT/migrations"; then
    echo "  ${GREEN}PASS${RESET}: test-skill-md-version-matches-latest-migration-to-version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}FAIL${RESET}: SKILL.md version does not match latest migration to_version"
    FAIL=$((FAIL+1))
  fi
}


# ─────────────────────────────────────────────────────────────────────────────
# F5 — spec §11 self-conformance test
# Asserts THIS repo's own CLAUDE.md reproduces the §11 canonical block verbatim.
# WORKFLOW — policy specific to this repo's conformance claim; stays here.
#
# Why this exists: §11 binds its block to the host's "primary project-instruction
# file", and this host injects it into every project it scaffolds (migration 0014)
# while — until 2026-07-15 — not reproducing it in its own CLAUDE.md. Nothing
# noticed for the life of the repo: core's drift-report grepped the whole clone
# and kept finding the block in templates/, setup/ and 0014 — payload shipped INTO
# other projects, which instructs nobody here. The source of canonical prose was
# the one host not carrying it.
#
# The block is compared byte-for-byte against templates/spec-mirrors/, which is
# itself byte-identical to the spec's canonical block. That makes this a real
# guard rather than a spot-check: reword one bullet and it fails.
# ─────────────────────────────────────────────────────────────────────────────

test_claude_md_reproduces_spec_11_verbatim() {
  local claude_md="$REPO_ROOT/CLAUDE.md"
  local mirror="$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  local provenance='<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->'

  if [ ! -f "$claude_md" ] || [ ! -f "$mirror" ]; then
    echo "  ${RED}FAIL${RESET}: spec-11-self-conformance — CLAUDE.md or the spec mirror is missing"
    FAIL=$((FAIL+1))
    return
  fi

  if ! grep -qF "$provenance" "$claude_md"; then
    echo "  ${RED}FAIL${RESET}: spec-11-self-conformance — CLAUDE.md carries no §11 provenance anchor"
    echo "      expected: $provenance"
    echo "      §11 MUSTs the block in this host's primary project-instruction file."
    FAIL=$((FAIL+1))
    return
  fi

  # Extract from the provenance line to the end of the block. The block contains
  # exactly one `## ` line (its own heading) and no HTML comments, so the block
  # ends at whichever comes first: the next `## ` after its own heading, the next
  # HTML-comment marker, or EOF.
  #
  # Migration 0014 terminates on `## ` alone, which it can afford because it
  # inserts immediately before the first `## ` heading — guaranteeing one follows.
  # That invariant does not hold here: this file's §11 block sits ABOVE the
  # `<!-- gitnexus:start -->` region (see CLAUDE.md for why), so what follows the
  # block is a marker and an H1, and the next `## ` is several paragraphs down
  # inside the GitNexus section. Terminating on `## ` alone swallowed that
  # preamble — the same over-capture 0014's fixture 07-byte-identity-replace was
  # written to catch.
  local extracted
  extracted=$(awk '
    /<!-- spec-source: agenticapps-workflow-core@[^[:space:]]+ §11 -->/ && !seen { seen=1; next }
    seen && !own && /^## Coding Discipline \(NON-NEGOTIABLE\)$/ { own=1; print; next }
    seen && own && /^## / { exit }
    seen && /^<!--/ { exit }
    seen { print }
  ' "$claude_md" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}')

  if [ "$extracted" = "$(cat "$mirror")" ]; then
    echo "  ${GREEN}PASS${RESET}: spec-11-self-conformance — CLAUDE.md reproduces §11 verbatim"
    PASS=$((PASS+1))
  else
    echo "  ${RED}FAIL${RESET}: spec-11-self-conformance — CLAUDE.md's §11 block is not verbatim"
    echo "      diff (expected = templates/spec-mirrors/, actual = CLAUDE.md):"
    diff "$mirror" <(printf '%s\n' "$extracted") 2>&1 | head -10 | sed 's/^/        /'
    FAIL=$((FAIL+1))
  fi
}


# ─────────────────────────────────────────────────────────────────────────────
# Binds templates/spec-mirrors/11-coding-discipline-0.4.0.md to the upstream
# spec it transcribes: agenticapps-workflow-core's spec/11-coding-discipline.md.
# WORKFLOW — policy specific to this repo's mirror-fidelity claim; stays here.
#
# Why this exists: on 2026-05-25 upstream core 10f2c96 added four blank lines to
# §11's canonical prose WITHOUT bumping spec_version, and this repo mirrored that
# edit in 34ee72e with no migration to carry already-migrated projects forward.
# cparx and fx-signal-agent had run 0014 four days earlier and were stranded on
# the older — and, at the time, entirely correct — bytes. Nobody mis-transcribed
# anything: 913360e's mirror was byte-identical to core at the moment it shipped.
#
# Nothing detected the drift for seven weeks. test_claude_md_reproduces_spec_11_-
# verbatim above binds this repo's CLAUDE.md TO THE MIRROR, but the mirror itself
# was unbound to the spec it claims to transcribe. This guard closes that hole by
# diffing the mirror against a live extraction of core's spec on every run.
#
# This is also why ref: main is deliberately unpinned in ci.yml. But ci.yml only
# runs on push/pull_request to THIS repo — an upstream commit to core cannot
# start this workflow by itself. ci.yml also carries a daily schedule: trigger
# (see the workflow file) for exactly this reason: it re-runs this guard when
# nobody is pushing here. It promises no latency — GitHub delays scheduled
# events under load, may drop queued runs, and disables schedules after a
# period of repo inactivity. The honest statement: drift is caught on the next
# run of this workflow — a PR, a push to main, or the timer, whichever actually
# happens first. What unpinning buys is that whenever that run happens, it
# compares against upstream's CURRENT main rather than a frozen copy. A pinned
# SHA would have stayed green through the drift entirely and only moved the
# hole to "who remembers to bump
# the pin".
#
# The extraction below is anchored to the FOUR-BACKTICK fence in core's spec
# (the canonical block's own delimiter — see spec/11-coding-discipline.md),
# not to any prose sentence inside it. A prose anchor breaks the moment
# upstream adds a paragraph after the anchor line but before the fence;
# the fence is the one boundary the spec itself commits to.
#
# CORE_SPEC_DIR defaults to the sibling clone so local runs work unchanged.
# CORE_SPEC_REQUIRED is a declared flag, not an inferred "am I in CI?" check —
# unset it SKIPs loudly when the sibling clone isn't present; CI sets it to 1
# so a missing core spec there is a hard failure, not a silent no-op.
# ─────────────────────────────────────────────────────────────────────────────

test_mirror_matches_core_spec_11() {
  echo ""
  echo "${YELLOW}━━━ Mirror ≡ workflow-core spec §11 ━━━${RESET}"

  local core_dir="${CORE_SPEC_DIR:-$REPO_ROOT/../agenticapps-workflow-core}"
  local core_spec="$core_dir/spec/11-coding-discipline.md"

  if [ ! -f "$core_spec" ]; then
    if [ "${CORE_SPEC_REQUIRED:-}" = "1" ]; then
      echo "  ${RED}✗${RESET} core spec not found at $core_spec"
      echo "      CORE_SPEC_REQUIRED=1 — a missing core spec is a hard failure."
      FAIL=$((FAIL+1))
    else
      echo "  ${YELLOW}SKIP${RESET}: workflow-core not cloned at $core_dir"
      echo "      (set CORE_SPEC_DIR, or CORE_SPEC_REQUIRED=1 to make this fatal)"
      SKIP=$((SKIP+1))
    fi
    return
  fi

  local mirror="$REPO_ROOT/templates/spec-mirrors/11-coding-discipline-0.4.0.md"
  local tmp; tmp="$(mktemp -t core-spec-11-XXXXXX)"

  # The canonical block is delimited by a line of exactly four backticks
  # (````) on each side — not by any prose sentence inside it — because the
  # block's own content may legitimately contain three-backtick fences, and
  # upstream can append prose after the closing sentence but before the
  # closing fence without moving that fence. The fence is the boundary the
  # spec itself commits to; anchor the extractor there.
  local fence_count
  fence_count="$(grep -c '^````$' "$core_spec")"
  if [ "$fence_count" -ne 2 ]; then
    echo "  ${RED}✗${RESET} expected exactly 2 four-backtick fence lines delimiting"
    echo "      the canonical block in $core_spec, found $fence_count"
    FAIL=$((FAIL+1)); rm -f "$tmp"; return
  fi

  awk '
    /^````$/ {
      if (started) { exit }
      started = 1
      next
    }
    started { print }
  ' "$core_spec" > "$tmp"

  if [ ! -s "$tmp" ]; then
    echo "  ${RED}✗${RESET} could not extract the §11 block from $core_spec"
    echo "      (fence lines found, but nothing between them)"
    FAIL=$((FAIL+1)); rm -f "$tmp"; return
  fi

  if diff -u "$tmp" "$mirror" > /dev/null; then
    echo "  ${GREEN}✓${RESET} mirror matches workflow-core spec §11 byte-for-byte"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} mirror has DRIFTED from workflow-core spec §11:"
    diff -u "$tmp" "$mirror" | sed 's/^/      /'
    echo "      The spec moved, or the mirror was transcribed wrong. Re-sync the"
    echo "      mirror AND ship a migration to carry consumers forward — a mirror"
    echo "      edit without one is what stranded cparx and fx-signal-agent."
    FAIL=$((FAIL+1))
  fi
  rm -f "$tmp"
}


# ─────────────────────────────────────────────────────────────────────────────
# Dispatcher
# SHARED — generic filter-driven test dispatcher; the if/FILTER pattern is
#   repo-agnostic framework machinery; consumer repos replace the per-migration
#   calls with their own test functions while keeping this dispatch shape
# ─────────────────────────────────────────────────────────────────────────────

if [ -z "$FILTER" ] || [ "$FILTER" = "0001" ]; then
  test_migration_0001
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0005" ]; then
  test_migration_0005
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0006" ]; then
  test_migration_0006
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0007" ]; then
  test_migration_0007
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0009" ]; then
  test_migration_0009
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0010" ]; then
  test_migration_0010
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0011" ]; then
  test_migration_0011
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0022" ]; then
  test_migration_0022
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0023" ]; then
  test_migration_0023
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0024" ]; then
  test_migration_0024
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0025" ]; then
  test_migration_0025
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0026" ]; then
  test_migration_0026
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0027" ]; then
  test_migration_0027
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0028" ]; then
  test_migration_0028
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0029" ]; then
  test_migration_0029
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0030" ]; then
  test_migration_0030
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0031" ]; then
  test_migration_0031
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "phase-sentinel" ]; then
  test_phase_sentinel
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0014" ]; then
  test_migration_0014
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0015" ]; then
  test_migration_0015
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0016" ]; then
  test_migration_0016
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "preflight" ]; then
  test_preflight_verify_paths
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "spec-11-self-conformance" ]; then
  test_claude_md_reproduces_spec_11_verbatim
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "spec11" ]; then
  test_mirror_matches_core_spec_11
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "test-skill-md-version-matches-latest-migration-to-version" ]; then
  # Function exists after Task 1.3 lands. Guard with declare -F so this commit doesn't
  # try to run it before Task 1.3 defines it. Increments SKIP when not yet defined
  # so the harness exits 0 rather than "NO TESTS RAN" during the Wave 0 → Wave 1 window.
  if declare -F test_skill_md_version_matches_latest_migration_to_version >/dev/null 2>&1; then
    test_skill_md_version_matches_latest_migration_to_version
  elif [ -n "$FILTER" ]; then
    echo "${YELLOW}SKIP${RESET}: test-skill-md-version-matches-latest-migration-to-version (function not yet defined)"
    SKIP=$((SKIP+1))
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "${YELLOW}━━━ Summary ━━━${RESET}"
echo "  ${GREEN}PASS${RESET}: $PASS"
[ $FAIL -gt 0 ] && echo "  ${RED}FAIL${RESET}: $FAIL"
[ $SKIP -gt 0 ] && echo "  ${YELLOW}SKIP${RESET}: $SKIP"

if [ $FAIL -gt 0 ]; then
  exit 1
elif [ $PASS -eq 0 ] && [ $SKIP -eq 0 ] && [ $RAN_AUDIT -eq 0 ]; then
  echo "  ${RED}NO TESTS RAN${RESET}"
  exit 1
else
  exit 0
fi
