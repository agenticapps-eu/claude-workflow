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
    'jq -e ".hooks.pre_phase.design_critique // .lifecycle.execute.conditional.design_critique" .planning/config.json >/dev/null' "$before_dir" not-applied
  assert_check "Step 4 idempotency: skip on v1.3.0" \
    'jq -e ".hooks.pre_phase.design_critique // .lifecycle.execute.conditional.design_critique" .planning/config.json >/dev/null' "$after_dir" applied

  # Step 5: post_phase.security.sub_gates in config.json
  # Use `// []` to handle the missing-path case (jq otherwise exits 4 on null
  # path traversal, which still satisfies "non-zero = not applied" but is
  # noisier than the contract intends).
  assert_check "Step 5 idempotency: needs apply on v1.2.0" \
    'jq -e "((.hooks.post_phase.security.sub_gates // []) | any(.skill == \"database-sentinel:audit\")) or (.lifecycle.execute.conditional.database_security.skill == \"database-sentinel:audit\")" .planning/config.json >/dev/null 2>&1' "$before_dir" not-applied
  assert_check "Step 5 idempotency: skip on v1.3.0" \
    'jq -e "((.hooks.post_phase.security.sub_gates // []) | any(.skill == \"database-sentinel:audit\")) or (.lifecycle.execute.conditional.database_security.skill == \"database-sentinel:audit\")" .planning/config.json >/dev/null 2>&1' "$after_dir" applied

  # Step 6: finishing.impeccable_audit and db_pre_launch_audit
  assert_check "Step 6 idempotency: needs apply on v1.2.0" \
    'jq -e "(.hooks.finishing.impeccable_audit and .hooks.finishing.db_pre_launch_audit) or (.lifecycle.execute.conditional.impeccable_audit and .lifecycle.execute.conditional.db_pre_launch_audit)" .planning/config.json >/dev/null' "$before_dir" not-applied
  assert_check "Step 6 idempotency: skip on v1.3.0" \
    'jq -e "(.hooks.finishing.impeccable_audit and .hooks.finishing.db_pre_launch_audit) or (.lifecycle.execute.conditional.impeccable_audit and .lifecycle.execute.conditional.db_pre_launch_audit)" .planning/config.json >/dev/null' "$after_dir" applied

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


# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0032 — Bind the OpenSpec front end (2.9.0 -> 3.0.0)
# WORKFLOW — verify body specific to migration 0032 content; stays in claude-workflow.
# ─────────────────────────────────────────────────────────────────────────────
# Same fixture-replay shape as 0030: setup.sh builds a sandboxed 2.9.0 project
# (fake $HOME, fake scaffolder clone, pre-3.0.0 hook payload, 0.x config),
# verify.sh replays the migration's DETERMINISTIC steps via common-apply.sh and
# asserts the end state via common-verify.sh; expected-exit asserts the rc.
#
# Steps 2 (`openspec init`) and 6 (install the retargeted SKILL.md) are excluded:
# step 2 shells out to a network-installed CLI and step 6 is a plain copy. All
# the branching — the two settings.json rebuilds and the config restructure — is
# in steps 1/3/4/5, which every fixture exercises.
# ─────────────────────────────────────────────────────────────────────────────
# The review producer actually DELIVERS the prompt to each reviewer
# ─────────────────────────────────────────────────────────────────────────────
# Regression for a bug that shipped in the canonical upstream script and was
# copied here: the codex branch was
#
#   printf '%s' "$PROMPT" | timeout N codex exec - </dev/null
#
# In bash, a redirection on the right-hand side of a pipe WINS over the pipe, so
# codex received an EMPTY prompt. `codex exec -` reads its prompt from stdin, so
# the </dev/null that protects the argv-form CLIs from hanging destroys the
# stdin form's only input. It survived manual testing because zsh's MULTIOS
# makes the same line work interactively.
#
# Why it matters more than a broken reviewer: the producer records ANY non-empty
# output as a "## Reviewer:" section, and the §18 gate counts those sections. A
# reviewer that was handed nothing but still emits a banner satisfies the gate
# with a review that never happened — the one failure mode this whole front end
# exists to prevent.
#
# The test uses fake reviewers that echo their stdin, so it asserts delivery
# without calling a real vendor CLI.
# ─────────────────────────────────────────────────────────────────────────────
# No migration installs a payload this repo no longer publishes
# ─────────────────────────────────────────────────────────────────────────────
# Migrations fetch payload files from `main` by raw URL, or copy them out of the
# scaffolder snapshot. Deleting a payload in a later version silently turns those
# URLs into 404s and those copies into missing sources, so replaying the chain on
# an old project breaks — and in the curl case it breaks DANGEROUSLY:
#
#     curl -fsSL <404> > .claude/hooks/some-gate.sh   # `>` truncates FIRST
#     chmod +x .claude/hooks/some-gate.sh             # empty, executable hook
#
# An empty PreToolUse hook exits 0, i.e. allows every edit. The gate is gone and
# nothing says so. That is exactly what deleting multi-ai-review-gate.sh in 3.0.0
# would have done to migrations 0005 and 0016.
#
# This test extracts every payload path a migration pulls from `main` and asserts
# either that the path is still tracked, or that the fetch is GUARDED (writes to a
# temp file / tests for the source before publishing). It is deliberately
# repo-shape-aware rather than network-dependent: no HTTP request is made.
# ─────────────────────────────────────────────────────────────────────────────
# The change-gate stays in lockstep with the canonical upstream copy
# ─────────────────────────────────────────────────────────────────────────────
# §18's whole design is ONE host-agnostic enforcement script that every host
# (claude / codex / opencode / pi), every git pre-commit hook, and every CI check
# calls. That only holds if the copies stay identical — and nothing enforced it,
# so they did not: opencode-workflow re-authored its copy (~256 lines diverged
# from the canonical one) while shipping the same exemption bug.
#
# This guard compares this repo's copy against the canonical one in
# agenticapps-workflow-core, reusing the CORE_SPEC_DIR checkout that the §11
# mirror test already relies on (CI clones core to .core-spec).
#
# Core published the canonical copy in ae90483 (core#33, ADR-0022) at
# reference-implementations/openspec-change-gate/ — NOT the `gate/` path this
# guard originally predicted. It now enforces byte-identity: any local fix that
# has not been upstreamed turns it red, which is exactly the signal we want.
# Fix behaviour in core alongside a harness row, then re-vendor; do not patch
# bin/ in place, because a host-local fix is how the copies diverged the first
# time.
test_gate_matches_core_canonical() {
  echo ""
  echo "${YELLOW}━━━ Change-gate ≡ workflow-core canonical ━━━${RESET}"

  local core_dir="${CORE_SPEC_DIR:-$REPO_ROOT/../agenticapps-workflow-core}"
  local canonical="$core_dir/reference-implementations/openspec-change-gate/openspec-change-gate.sh"
  local ours="$REPO_ROOT/bin/openspec-change-gate.sh"

  if [ ! -f "$ours" ]; then
    echo "  ${RED}✗${RESET} this repo has no bin/openspec-change-gate.sh"
    FAIL=$((FAIL+1)); return
  fi

  if [ ! -d "$core_dir" ]; then
    echo "  ${YELLOW}SKIP${RESET}: workflow-core not available at $core_dir"
    SKIP=$((SKIP+1)); return
  fi

  if [ ! -f "$canonical" ]; then
    # Core HAS published it (ae90483). Absent now means a stale core checkout or
    # a path that moved again — either way the "one shared gate" invariant is
    # unverifiable, and that must not read as "checked and fine".
    echo "  ${RED}✗${RESET} workflow-core has no reference-implementations/openspec-change-gate/openspec-change-gate.sh"
    echo "      Published upstream in ae90483 (core#33). A stale core checkout cannot"
    echo "      certify this gate. Pull core, or update this path if it moved again."
    FAIL=$((FAIL+1)); return
  fi

  # The harness scores the gate, and CI runs it against our vendored copy — so a
  # stale harness certifies a stale gate. Core's vendoring steps require keeping
  # the two in sync; this is what makes "in sync" checkable.
  local harness_ours="$REPO_ROOT/tools/change-gate-conformance.sh"
  local harness_canonical="$core_dir/tools/change-gate-conformance.sh"
  if [ ! -f "$harness_ours" ]; then
    echo "  ${RED}✗${RESET} tools/change-gate-conformance.sh not vendored — CI's conformance step cannot run"
    FAIL=$((FAIL+1))
  elif [ ! -f "$harness_canonical" ]; then
    echo "  ${YELLOW}SKIP${RESET}: workflow-core has no tools/change-gate-conformance.sh to compare against"
    SKIP=$((SKIP+1))
  elif cmp -s "$harness_ours" "$harness_canonical"; then
    echo "  ${GREEN}✓${RESET} conformance harness is byte-identical to core's"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} conformance harness has drifted from core's — a stale harness certifies a stale gate"
    FAIL=$((FAIL+1))
  fi

  # The shared-path arbitration only works if the marker exists and the installer
  # reads it. Without both, install.sh silently reverts to last-writer-wins on
  # ~/.agenticapps/bin — the propagation vector where a host still vendoring an
  # older gate republishes it over a newer one for every agent on the machine.
  if grep -qE '^# gate-version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$ours"; then
    echo "  ${GREEN}✓${RESET} gate carries a version marker (shared-path arbitration)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} gate has no '# gate-version:' marker — installers cannot refuse a downgrade"
    FAIL=$((FAIL+1))
  fi
  if grep -q 'gate_version' "$REPO_ROOT/install.sh" && grep -q 'Refusing to downgrade' "$REPO_ROOT/install.sh"; then
    echo "  ${GREEN}✓${RESET} install.sh arbitrates the shared gate path instead of clobbering it"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} install.sh writes the shared gate unconditionally (last-writer-wins)"
    FAIL=$((FAIL+1))
  fi

  # install.sh is not the only writer. A migration that installs the gate is a
  # second, independent path to the same shared file — and auditing only
  # install.sh reported green while 0032 clobbered it unconditionally. Any
  # migration that writes the shared gate must arbitrate the same way.
  local m unguarded=""
  for m in "$REPO_ROOT"/migrations/[0-9]*.md; do
    grep -q 'agenticapps/bin/openspec-change-gate.sh' "$m" 2>/dev/null || continue
    grep -q 'install .*bin/openspec-change-gate.sh' "$m" 2>/dev/null || continue
    grep -q 'gate_version' "$m" 2>/dev/null || unguarded="$unguarded $(basename "$m")"
  done
  if [ -z "$unguarded" ]; then
    echo "  ${GREEN}✓${RESET} every migration that installs the shared gate arbitrates on version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} migration(s) write the shared gate unconditionally:$unguarded"
    echo "      ~/.agenticapps/bin is shared by claude/codex/opencode/pi. An unguarded"
    echo "      install downgrades it for every agent on the machine. Mirror install.sh's"
    echo "      gate_version arbitration into the migration's Apply block."
    FAIL=$((FAIL+1))
  fi

  if cmp -s "$ours" "$canonical"; then
    echo "  ${GREEN}✓${RESET} gate script is byte-identical to the canonical upstream copy"
    PASS=$((PASS+1))
    if [ -f "$REPO_ROOT/bin/GATE-DIVERGENCE.md" ]; then
      echo "  ${RED}✗${RESET} but bin/GATE-DIVERGENCE.md still exists — the fork is closed, delete it"
      FAIL=$((FAIL+1))
    fi
    return
  fi

  # Diverged. Permitted ONLY while recorded in bin/GATE-DIVERGENCE.md, pinned to
  # the exact diff. That keeps a deliberate, documented fix visible and bounded
  # while any further unrecorded drift still fails.
  local record="$REPO_ROOT/bin/GATE-DIVERGENCE.md"
  if [ ! -f "$record" ]; then
    echo "  ${RED}✗${RESET} gate script has DRIFTED from the canonical upstream copy, unrecorded"
    echo "      One shared enforcement surface is the §18 design; a per-host fork means"
    echo "      each host enforces a subtly different rule. Upstream the change and"
    echo "      re-sync, or record the divergence in bin/GATE-DIVERGENCE.md."
    diff -u "$canonical" "$ours" | head -30 | sed 's/^/        /'
    FAIL=$((FAIL+1)); return
  fi

  local actual expected
  actual="$(diff -u "$canonical" "$ours" | grep -vE '^(---|\+\+\+)' | shasum -a 256 | cut -d' ' -f1)"
  expected="$(grep -oE '^[0-9a-f]{64}$' "$record" | head -n1)"
  if [ "$actual" = "$expected" ]; then
    echo "  ${YELLOW}RECORDED-DIVERGENCE${RESET}: gate differs from canonical, exactly as documented"
    echo "      bin/GATE-DIVERGENCE.md pins this diff; it closes when the fixes are"
    echo "      upstreamed into core and this copy is re-vendored. Not silent, not permanent."
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} gate divergence CHANGED and no longer matches the recorded hash"
    echo "      recorded: ${expected:-<none found>}"
    echo "      actual:   $actual"
    echo "      Either re-sync with upstream, or update bin/GATE-DIVERGENCE.md deliberately."
    FAIL=$((FAIL+1))
  fi
}


# The gate CONSUMES review evidence; reviewer-cli.sh PRODUCES it. Core published
# the gate first and left the producer's wrapper forked — three divergent copies
# at one shared path, no marker, no arbitration. On 2026-07-25 a host installer
# delivered the correctly-arbitrated 1.2.2 gate and, in the SAME run,
# blind-installed a 3-arm wrapper over the 4-arm one. The `opencode` arm vanished
# and the next review that asked for it was recorded as "reviewer unavailable"
# and waved through with one fewer opinion (core#41).
#
# Not a gate bypass — a quiet degradation of the exact evidence §18 exists to
# compel, which is worse, because a drifted producer reports clean. This guard is
# the gate's guard applied to the producer's half: byte-identity with core, a
# harness kept in step, the version marker present, and EVERY writer of the
# shared path arbitrating on it.
test_reviewer_cli_matches_core_canonical() {
  echo ""
  echo "${YELLOW}━━━ reviewer-cli ≡ workflow-core canonical ━━━${RESET}"

  local core_dir="${CORE_SPEC_DIR:-$REPO_ROOT/../agenticapps-workflow-core}"
  local canonical="$core_dir/reference-implementations/reviewer-cli/reviewer-cli.sh"
  local ours="$REPO_ROOT/bin/reviewer-cli.sh"

  if [ ! -f "$ours" ]; then
    echo "  ${RED}✗${RESET} this repo has no bin/reviewer-cli.sh — the producer has nothing to call"
    FAIL=$((FAIL+1)); return
  fi

  if [ ! -d "$core_dir" ]; then
    echo "  ${YELLOW}SKIP${RESET}: workflow-core not available at $core_dir"
    SKIP=$((SKIP+1)); return
  fi

  if [ ! -f "$canonical" ]; then
    echo "  ${RED}✗${RESET} workflow-core has no reference-implementations/reviewer-cli/reviewer-cli.sh"
    echo "      Published upstream in 60cd83f (core#42). A stale core checkout cannot"
    echo "      certify this wrapper. Pull core, or update this path if it moved."
    FAIL=$((FAIL+1)); return
  fi

  # A stale harness certifies a stale wrapper — core's vendoring step 2 requires
  # shipping the two together and keeping them in sync.
  local harness_ours="$REPO_ROOT/tools/reviewer-cli-conformance.sh"
  local harness_canonical="$core_dir/tools/reviewer-cli-conformance.sh"
  if [ ! -f "$harness_ours" ]; then
    echo "  ${RED}✗${RESET} tools/reviewer-cli-conformance.sh not vendored — CI cannot score the wrapper"
    FAIL=$((FAIL+1))
  elif cmp -s "$harness_ours" "$harness_canonical"; then
    echo "  ${GREEN}✓${RESET} conformance harness is byte-identical to core's"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} conformance harness has drifted from core's — a stale harness certifies a stale wrapper"
    FAIL=$((FAIL+1))
  fi

  # The marker is the whole mechanism. Without it every installer reads 0.0.0 and
  # the shared path silently reverts to last-writer-wins — core#41 exactly.
  if grep -qE '^# reviewer-cli-version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$ours"; then
    echo "  ${GREEN}✓${RESET} wrapper carries a version marker (shared-path arbitration)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} wrapper has no '# reviewer-cli-version:' marker — installers cannot refuse a downgrade"
    FAIL=$((FAIL+1))
  fi

  # Both halves, as the gate's row does: reading the marker proves nothing on its
  # own if no branch acts on it. Greping only for the reader passes a file whose
  # refusal path has been deleted — verified by mutation, which is why this row
  # is a conjunction.
  if grep -q 'reviewer_cli_version' "$REPO_ROOT/install.sh" \
     && grep -q 'Refusing to downgrade the shared wrapper' "$REPO_ROOT/install.sh"; then
    echo "  ${GREEN}✓${RESET} install.sh arbitrates the shared wrapper path instead of clobbering it"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} install.sh writes the shared wrapper unconditionally (last-writer-wins)"
    FAIL=$((FAIL+1))
  fi

  # Grep proves the branch is PRESENT; it cannot prove the branch is CORRECT. A
  # marker parser can read the right file and still return a wrong answer — the
  # `sed | head -n1 | grep .` form did exactly that under `set -o pipefail`,
  # returning "9.9.9\n0.0.0" for a many-marker file, which sort -V reads as 0.0.0
  # and hands a downgrade straight through. Every row above stayed green while
  # that was live. So EXECUTE both parsers against hostile inputs.
  local vt; vt="$(mktemp -d -t "marker-parse-XXXXXX")"
  printf '#!/usr/bin/env bash\n# reviewer-cli-version: 1.2.3\n'    > "$vt/good"
  printf '#!/usr/bin/env bash\n# reviewer-cli-version: 9.0.0junk\n'> "$vt/malformed"
  printf '#!/usr/bin/env bash\n# nothing here\n'                   > "$vt/unmarked"
  { printf '#!/usr/bin/env bash\n'
    for _i in $(seq 1 20000); do echo "# reviewer-cli-version: 9.9.9"; done; } > "$vt/many"

  # Extract the parser from install.sh and run it in a pipefail shell, exactly as
  # install.sh does, rather than re-implementing it here (which would test a copy).
  local parser; parser="$(sed -n '/^reviewer_cli_version() {/,/^}/p' "$REPO_ROOT/install.sh")"
  local bad=""
  local case_name expect got
  for case_name in good:1.2.3 malformed:0.0.0 unmarked:0.0.0 many:9.9.9; do
    expect="${case_name#*:}"
    got="$(bash -c "set -uo pipefail
$parser
reviewer_cli_version '$vt/${case_name%%:*}'" 2>/dev/null)"
    [ "$got" = "$expect" ] || bad="$bad ${case_name%%:*}(want $expect, got '${got//$'\n'/\\n}')"
  done
  rm -rf "$vt"

  if [ -z "$bad" ]; then
    echo "  ${GREEN}✓${RESET} the marker parser survives malformed, unmarked, and many-marker files"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} marker parser returns a wrong version:$bad"
    echo "      A wrong version is a silent downgrade — the arbitration branch runs,"
    echo "      compares garbage, and installs anyway. Parse with one anchored awk,"
    echo "      never a pipeline that can SIGPIPE under 'set -o pipefail'."
    FAIL=$((FAIL+1))
  fi

  # install.sh is not the only writer. Auditing it alone reported green while
  # 0032 clobbered the gate unconditionally; the same blind spot applies here.
  # Any migration or setup path that installs the wrapper must arbitrate too.
  local f unguarded=""
  for f in "$REPO_ROOT"/migrations/[0-9]*.md "$REPO_ROOT"/migrations/test-fixtures/0032/common-apply.sh \
           "$REPO_ROOT"/setup/SKILL.md; do
    [ -f "$f" ] || continue
    grep -q 'install .*bin/reviewer-cli.sh' "$f" 2>/dev/null || continue
    grep -q 'reviewer_cli_version' "$f" 2>/dev/null || unguarded="$unguarded $(basename "$f")"
  done
  if [ -z "$unguarded" ]; then
    echo "  ${GREEN}✓${RESET} every installer that writes the shared wrapper arbitrates on version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} installer(s) write the shared wrapper unconditionally:$unguarded"
    echo "      ~/.agenticapps/bin is shared by claude/codex/opencode/pi. An unguarded"
    echo "      install strips vendor arms from every agent on the machine (core#41)."
    FAIL=$((FAIL+1))
  fi

  # The producer must not keep a private copy of the arms — that IS the fork.
  # Matches a DIRECT vendor invocation in any form, not just the `bounded X`
  # wrapper the arms happened to use before: greping only for `bounded codex`
  # would wave through a re-added bare `codex exec` or `gemini -p`, which is the
  # same fork with the helper inlined.
  if grep -qE '(^|[^-[:alnum:]_])(codex exec|gemini -p|claude -p|opencode run)' \
       "$REPO_ROOT/bin/run-plan-review.sh" 2>/dev/null; then
    echo "  ${RED}✗${RESET} run-plan-review.sh still dispatches vendors itself — a second copy of the arms"
    echo "      Delegate to reviewer-cli.sh. A private copy of a shared artifact is a race,"
    echo "      and it drifts the moment core adds or changes an arm."
    FAIL=$((FAIL+1))
  else
    echo "  ${GREEN}✓${RESET} producer delegates dispatch to the wrapper (no second copy of the arms)"
    PASS=$((PASS+1))
  fi

  if cmp -s "$ours" "$canonical"; then
    echo "  ${GREEN}✓${RESET} wrapper is byte-identical to the canonical upstream copy"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} wrapper has DRIFTED from the canonical upstream copy"
    echo "      One shared wrapper is the design; a per-host fork is how the opencode arm"
    echo "      went missing. Change it in core alongside a harness row, then re-vendor."
    diff -u "$canonical" "$ours" | head -30 | sed 's/^/        /'
    FAIL=$((FAIL+1))
  fi
}


test_migration_payloads_still_published() {
  echo ""
  echo "${YELLOW}━━━ Migration payloads — nothing fetches a deleted file ━━━${RESET}"

  local raw='raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/'
  local any=0 bad=0 path file

  while IFS= read -r line; do
    file="${line%%:*}"
    path="$(printf '%s' "$line" | sed -E "s|.*${raw}([^ \\\"']*).*|\\1|")"
    [ -n "$path" ] || continue
    any=$((any+1))
    if git -C "$REPO_ROOT" ls-tree -r --name-only HEAD -- "$path" 2>/dev/null | grep -q .; then
      continue                                   # still published — fine
    fi
    # Not published. Only acceptable if the fetch cannot leave a truncated file.
    if grep -q 'mktemp' "$file" && grep -qE '\[ -s "\$_tmp" \]' "$file"; then
      echo "  ${GREEN}✓${RESET} $(basename "$file"): '$path' is retired, and its fetch is guarded"
      PASS=$((PASS+1))
    else
      echo "  ${RED}✗${RESET} $(basename "$file") fetches '$path', which is no longer published,"
      echo "      and the fetch is UNGUARDED — '>' truncates before curl fails, leaving an"
      echo "      empty executable hook that exits 0 and allows every edit."
      FAIL=$((FAIL+1)); bad=1
    fi
  done <<< "$(grep -rn "$raw" "$REPO_ROOT"/migrations/*.md 2>/dev/null || true)"

  # Snapshot-copy payloads: same hazard, louder failure mode (cp fails aloud
  # rather than truncating, but a chain replay still dies on it).
  local src
  while IFS= read -r src; do
    [ -n "$src" ] || continue
    any=$((any+1))
    [ -e "$REPO_ROOT/setup/snapshot/hooks/$src" ] && continue
    local users guarded
    users="$(grep -ln "setup/snapshot/hooks/$src" "$REPO_ROOT"/migrations/*.md 2>/dev/null || true)"
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      # Guarded = the copy is wrapped in an existence test for the same source.
      if grep -qF "if [ -f \"\$SCAFFOLDER/setup/snapshot/hooks/$src\" ]" "$file"; then
        echo "  ${GREEN}✓${RESET} $(basename "$file"): snapshot payload '$src' is retired, copy is guarded"
        PASS=$((PASS+1))
      else
        echo "  ${RED}✗${RESET} $(basename "$file") copies snapshot payload '$src', which no"
        echo "      longer ships, with no existence guard — a chain replay aborts here."
        FAIL=$((FAIL+1)); bad=1
      fi
    done <<< "$users"
  done <<< "$(grep -rhoE 'setup/snapshot/hooks/[A-Za-z0-9._-]+' "$REPO_ROOT"/migrations/*.md 2>/dev/null \
               | sed 's|.*/||' | sort -u || true)"

  if [ "$any" -eq 0 ]; then
    echo "  ${YELLOW}note${RESET}: no migration payload references found to check"
  elif [ "$bad" -eq 0 ]; then
    echo "  ${GREEN}✓${RESET} every migration payload is either still published or safely guarded"
    PASS=$((PASS+1))
  fi
}


test_review_producer_delivers_prompt() {
  echo ""
  echo "${YELLOW}━━━ Review producer — prompt reaches the reviewer ━━━${RESET}"

  local producer="$REPO_ROOT/bin/run-plan-review.sh"
  if [ ! -x "$producer" ]; then
    echo "  ${RED}✗${RESET} producer missing or non-executable at $producer — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  local tmp; tmp="$(mktemp -d -t "review-producer-XXXXXX")"
  local marker="MARKER-PROMPT-REACHED-REVIEWER"
  (
    cd "$tmp" || exit 1
    git init -q . && git config user.email t@t.t && git config user.name t
    mkdir -p openspec/changes/demo fakebin
    printf '# proposal\n%s\n' "$marker" > openspec/changes/demo/proposal.md

    # Shadow the two REAL vendor names so the producer reaches the wrapper's
    # named arms. Since the producer delegates to reviewer-cli.sh, BOTH arms are
    # argv-form and stdin is pinned to /dev/null — a stub that echoed stdin
    # would now correctly print nothing. Each stub echoes the prompt ARGUMENT:
    #   codex  <- `codex exec "$P"`  -> $2
    #   gemini <- `gemini -p "$P"`   -> $2
    printf '#!/usr/bin/env bash\nprintf "%%s" "$2"\n' > fakebin/codex
    printf '#!/usr/bin/env bash\nprintf "%%s" "$2"\n' > fakebin/gemini
    chmod +x fakebin/codex fakebin/gemini
    # Point at the repo's vendored wrapper: the fixture repo has no bin/, and the
    # global install may be absent or a different version on a dev machine.
    PATH="$tmp/fakebin:$PATH" MIN_REVIEWERS=2 AGENT_SELF=none \
      REVIEWER_CLI="$REPO_ROOT/bin/reviewer-cli.sh" \
      bash "$producer" demo codex gemini >/dev/null 2>&1
  )

  local out="$tmp/openspec/changes/demo/REVIEWS.md"
  if [ ! -f "$out" ]; then
    echo "  ${RED}✗${RESET} producer wrote no REVIEWS.md"
    FAIL=$((FAIL+1)); rm -rf "$tmp"; return
  fi

  # 1. The reviewer must have RECEIVED the change's content. The delivery path is
  #    now producer -> prompt FILE -> reviewer-cli.sh -> vendor argv; a break
  #    anywhere along it (unwritten file, wrong arg position, wrapper not
  #    resolved) surfaces here as a review of nothing.
  if grep -qF "$marker" "$out"; then
    echo "  ${GREEN}✓${RESET} prompt reached the reviewer through the wrapper (argv delivery)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} reviewer got an EMPTY prompt — the file->wrapper->argv path is broken"
    echo "      REVIEWS.md contains no '$marker' from the change's proposal.md"
    FAIL=$((FAIL+1))
  fi

  # 2. Both reviewers must be recorded, in the shape the gate counts.
  local n; n="$(grep -ciE '^##[[:space:]]*reviewer' "$out" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -eq 2 ]; then
    echo "  ${GREEN}✓${RESET} both reviewers recorded as '## Reviewer:' sections (gate counts $n)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} expected 2 reviewer sections, got $n"
    FAIL=$((FAIL+1))
  fi

  rm -rf "$tmp"
}


test_migration_0032() {
  echo ""
  echo "${YELLOW}━━━ Migration 0032 — Bind the OpenSpec front end ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0032"
  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  local migration_file="$REPO_ROOT/migrations/0032-bind-openspec-v1.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0032_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0032-${fixname}-XXXXXX")"
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
    run_0032_fixture "$name"
  done

  # The fixtures replay a COPY of the migration's Apply blocks, so the two can
  # drift and the fixtures would then prove something the migration does not do.
  # The old check looked for four fixed substrings, which could not notice a
  # changed path, a changed timeout, or an ADDED destructive command. Compare
  # every executable line instead: each non-comment, non-blank line of
  # common-apply.sh must appear verbatim somewhere in the migration doc.
  local apply_file="$fixtures/common-apply.sh"
  local drift=0 checked=0 line norm
  while IFS= read -r line; do
    norm="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$norm" in
      ''|'#'*|'set -uo pipefail'|'fi'|'else'|'done'|'}'|"'"*) continue ;;
      # Fixture-only scaffolding that legitimately has no migration counterpart.
      SCAFFOLDER=*|'if [ -f .planning/config.json ]; then'|TPL=*) continue ;;
    esac
    checked=$((checked+1))
    if ! grep -qF "$norm" "$migration_file"; then
      echo "  ${RED}✗${RESET} apply-parity — fixture line absent from the migration doc:"
      echo "        $norm"
      drift=1
    fi
  done < "$apply_file"

  if [ "$drift" -eq 0 ]; then
    echo "  ${GREEN}✓${RESET} apply-parity — all $checked fixture lines appear in the migration"
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
  fi
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

# Each suite gets its own filter token. These were all wedged under the "0031"
# guard, so `run-tests.sh 0032` reported "NO TESTS RAN" while `0031` silently ran
# five unrelated suites — a filter that lies about what it covered.
if [ -z "$FILTER" ] || [ "$FILTER" = "0031" ]; then
  test_migration_0031
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0032" ]; then
  test_migration_0032
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0032" ] || [ "$FILTER" = "review-producer" ]; then
  test_review_producer_delivers_prompt
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "payloads" ]; then
  test_migration_payloads_still_published
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "gate-parity" ]; then
  test_gate_matches_core_canonical
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "reviewer-parity" ]; then
  test_reviewer_cli_matches_core_canonical
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
