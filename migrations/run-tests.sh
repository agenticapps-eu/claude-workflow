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

# Colors for output (skip if not a tty)
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
SKIP=0
RAN_AUDIT=0

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

# ─── SPLIT TRAP (codex HIGH-2 / R-rev-2) ─────────────────────────────────────
# Mirrors the split-trap shape in migrate-0019-sentry-crons-and-healthz.sh.
# EXIT is silent (no cleanup output on normal harness exit).
# INT → exit 130; TERM → exit 143.
_runtests_cleanup_fired=0
_runtests_do_cleanup() {
  [ "$_runtests_cleanup_fired" -eq 1 ] && return 0
  _runtests_cleanup_fired=1
  # harness-level cleanup (intentionally empty — no shared state to tear down)
  :
}
trap '_runtests_do_cleanup'        EXIT
trap '_runtests_do_cleanup; exit 130' INT
trap '_runtests_do_cleanup; exit 143' TERM

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Extract a file from a git ref into a temp path.
# Usage: extract_to <ref> <path-in-repo> <output-path>
extract_to() {
  local ref="$1" path="$2" out="$3"
  mkdir -p "$(dirname "$out")"
  if git show "$ref:$path" >"$out" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Setup a fixture project at $1=tmpdir from git ref $2.
# The fixture mimics a project's on-disk shape: maps scaffolder template
# paths to project paths.
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

# Run an idempotency check shell snippet inside a fixture dir.
# Returns the exit code of the check.
run_check() {
  local fixture="$1" check="$2"
  ( cd "$fixture" && eval "$check" >/dev/null 2>&1 )
  return $?
}

# Assert helper.
# Usage: assert_check "<label>" "<check>" "<fixture>" "<expected: applied|not-applied>"
# Semantic: "applied" means the idempotency check returned 0 (skip — already done).
#          "not-applied" means it returned ANY non-zero (please apply).
# Numeric exit codes beyond 0 vs non-0 don't matter to the migration runtime.
assert_check() {
  local label="$1" check="$2" fixture="$3" expected="$4"
  run_check "$fixture" "$check"
  local actual=$?
  local pass=0
  case "$expected" in
    applied)     [ "$actual" = "0" ] && pass=1 ;;
    not-applied) [ "$actual" != "0" ] && pass=1 ;;
    *) echo "  ${RED}!${RESET} bad expected value: $expected"; FAIL=$((FAIL+1)); return ;;
  esac
  if [ "$pass" = "1" ]; then
    echo "  ${GREEN}✓${RESET} $label (expected $expected, exit=$actual)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} $label (expected $expected, got exit=$actual)"
    echo "      check: $check"
    echo "      fixture: $fixture"
    FAIL=$((FAIL+1))
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0001 — Wire Go skill packs + impeccable + database-sentinel
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
  echo ""
  echo "${YELLOW}━━━ Migration 0005 — Multi-AI plan review enforcement gate ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0005"
  local script="$REPO_ROOT/templates/.claude/hooks/multi-ai-review-gate.sh"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing at $fixtures"
    SKIP=$((SKIP+1))
    return
  fi
  if [ ! -x "$script" ]; then
    echo "  ${RED}✗${RESET} script missing or non-executable at $script — RED state, awaiting GREEN implementation"
    FAIL=$((FAIL+1))
    return
  fi

  # Driver: one fixture invocation.
  run_0005_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0005-${fixname}-XXXXXX")"

    # Run setup.sh (if present) with $tmp as CWD.
    if [ -x "$fixdir/setup.sh" ]; then
      ( cd "$tmp" && "$fixdir/setup.sh" >/dev/null 2>&1 )
    fi

    # Build env-prefix from optional env file.
    local env_args=()
    if [ -f "$fixdir/env" ]; then
      while IFS= read -r kv; do
        [ -z "$kv" ] && continue
        env_args+=("$kv")
      done < "$fixdir/env"
    fi

    # Run the hook.
    # The `${env_args[@]+"${env_args[@]}"}` form is safe under `set -u` for empty arrays.
    # NOTE: parent harness uses `set -uo pipefail` (not `set -e`), so we do NOT
    # toggle `-e` here — doing so would leak `set -e` into later test_migration_*
    # functions and break them on the first non-zero exit (observed crashing 0009).
    local stderr_capture="$tmp/.stderr"
    local actual_exit
    ( cd "$tmp" && env ${env_args[@]+"${env_args[@]}"} bash "$script" < "$fixdir/stdin.json" 2> "$stderr_capture" >/dev/null )
    actual_exit=$?

    # Compare exit.
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

    # Strict stderr line-presence check (codex F1).
    # Each non-blank line of expected-stderr.txt must appear (substring match)
    # somewhere in actual stderr.
    if [ -s "$fixdir/expected-stderr.txt" ]; then
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

    # Fixture 09 — hostile-filename safety check (codex B4).
    # The hostile string contains $(rm -rf /tmp/HOSTILE_MARKER). If command
    # substitution happens, the marker is gone.
    # NOTE-5 fix: cleanup the marker file after the check so it doesn't
    # accumulate on disk across harness runs (the fixture's setup.sh
    # unconditionally touches /tmp/HOSTILE_MARKER per run).
    if [ "$fixname" = "09-hostile-filename-edit" ]; then
      if [ ! -f /tmp/HOSTILE_MARKER ]; then
        echo "  ${RED}✗${RESET} $fixname — /tmp/HOSTILE_MARKER was deleted (command-substitution executed!)"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      fi
      rm -f /tmp/HOSTILE_MARKER
    fi

    echo "  ${GREEN}✓${RESET} $fixname (exit $actual_exit)"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  # Run all 16 fixtures, sorted.
  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0005_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0006 — LLM wiki compiler integration (install + rollback scripts)
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
# test_migration_0007 — GitNexus code-graph integration (setup-only)
# ─────────────────────────────────────────────────────────────────────────────
#
# Exercises every decision branch of templates/.claude/scripts/install-gitnexus.sh
# + index-family-repos.sh + rollback-gitnexus.sh via 18 fixtures under
# migrations/test-fixtures/0007/. Each fixture builds a sandboxed $HOME with
# stubbed node/npm/gitnexus binaries in $HOME/bin (PATH-prepended).

test_migration_0007() {
  echo ""
  echo "${YELLOW}━━━ Migration 0007 — GitNexus code-graph integration ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0007"
  local install_script="$REPO_ROOT/templates/.claude/scripts/install-gitnexus.sh"
  local rollback_script="$REPO_ROOT/templates/.claude/scripts/rollback-gitnexus.sh"
  local helper_script="$REPO_ROOT/templates/.claude/scripts/index-family-repos.sh"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi
  for s in "$install_script" "$rollback_script" "$helper_script"; do
    if [ ! -x "$s" ]; then
      echo "  ${RED}✗${RESET} script missing: $s — RED state"
      FAIL=$((FAIL+1))
      return
    fi
  done

  # Sandbox-escape guard
  if grep -E '/(Users/donald|home/[a-z][a-z]*/)' "$install_script" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} install script contains hardcoded real-home paths"
    FAIL=$((FAIL+1))
    return
  fi

  run_0007_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0007-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # setup.sh runs with HOME=fake_home + REPO_ROOT + FIXTURES_ROOT
    if [ -x "$fixdir/setup.sh" ]; then
      ( cd "$tmp" && HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" "$fixdir/setup.sh" >/dev/null 2>&1 )
    fi

    # Run install in a hermetic env: env -i strips host PATH (so an
    # fnm-managed `gitnexus` on the developer's $PATH can't shadow the
    # missing-stub case in 03-no-gitnexus) and also clears any host
    # GITNEXUS_* / WIKI_SKILL_MD env vars that the script reads. Only
    # HOME + a curated PATH ($fake_home/bin for stubs, /usr/bin:/bin
    # for coreutils + system jq) cross the sandbox boundary.
    local stderr_capture="$tmp/.stderr"
    local actual_exit
    ( cd "$fake_home" && env -i HOME="$fake_home" PATH="$fake_home/bin:/usr/bin:/bin" bash "$install_script" 2> "$stderr_capture" >/dev/null )
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

    # Strict stderr line-presence
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

    # verify.sh — same hermetic env as install (plus REPO_ROOT which several
    # verify scripts need to locate rollback/helper scripts).
    if [ -x "$fixdir/verify.sh" ]; then
      local verify_out
      verify_out=$( cd "$fake_home" && env -i HOME="$fake_home" REPO_ROOT="$REPO_ROOT" PATH="$fake_home/bin:/usr/bin:/bin" bash "$fixdir/verify.sh" 2>&1 )
      local verify_exit=$?
      if [ "$verify_exit" != "0" ]; then
        echo "  ${RED}✗${RESET} $fixname — verify.sh failed: $verify_out"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      fi
    fi

    echo "  ${GREEN}✓${RESET} $fixname (exit $actual_exit)"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0007_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0011 — Spec §10.9 observability enforcement (1.9.3 → 1.10.0)
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

  # Sanity-check that the scaffolder ships the scan/SCAN.md the migration
  # references. The enforcement/observability.yml.example is NOT installed
  # by this migration (local-only enforcement) so we don't need to check it.
  local scaffolder_scan="$REPO_ROOT/add-observability/scan/SCAN.md"
  if [ ! -f "$scaffolder_scan" ]; then
    echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_scan — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0011_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0011-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # The scaffolder-side files the migration references must live under
    # $HOME/.claude/skills/agenticapps-workflow/ in the sandbox. Pre-create
    # with the REAL scan/SCAN.md from this branch so fixtures referring to
    # the scan procedure see the actual shipped file.
    mkdir -p "$fake_home/.claude/skills/agenticapps-workflow/add-observability/scan"
    cp "$scaffolder_scan" "$fake_home/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md"

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
# Migration 0012 — Slash-command discovery wire-up
# ─────────────────────────────────────────────────────────────────────────────
# Same state-comparison pattern as 0011. Each fixture builds a sandboxed
# $HOME with the scaffolder skill tree, a per-project workflow SKILL.md
# at v1.10.0, and a fixture-specific $HOME/.claude/skills/add-observability
# state. verify.sh asserts pre-flight + step idempotency checks return
# what they should for that state.

test_migration_0012() {
  echo ""
  echo "${YELLOW}━━━ Migration 0012 — Slash-command discovery wire-up ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0012"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity-check that the scaffolder ships the add-observability/SKILL.md
  # the migration's Step 2 verify references via the symlink.
  local scaffolder_skill="$REPO_ROOT/add-observability/SKILL.md"
  if [ ! -f "$scaffolder_skill" ]; then
    echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_skill — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0012_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0012-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # The scaffolder-side files the migration references live at
    # $HOME/.claude/skills/agenticapps-workflow/add-observability/. The
    # fixture's common-setup.sh handles the SKILL.md stub directly (kept
    # in-sandbox for hermeticity, just like 0011's common-setup).

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
    run_0012_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0013 — Auto-init + stale-vendored cleanup (closes cparx F1)
# ─────────────────────────────────────────────────────────────────────────────
# Same state-comparison pattern as 0011/0012. Each fixture builds a sandboxed
# $HOME with the scaffolder skill tree + a stub init/INIT.md (the migration's
# requires.verify checks for the latter), a per-project workflow SKILL.md
# at v1.11.0 (or v1.12.0 for re-apply), and a fixture-specific project-local
# .claude/skills/add-observability state + CLAUDE.md observability metadata.
# verify.sh asserts pre-flight + step idempotency checks return what they
# should for that state.

test_migration_0013() {
  echo ""
  echo "${YELLOW}━━━ Migration 0013 — Auto-init + stale-vendored cleanup ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0013"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity-check that the scaffolder ships the init/INIT.md the migration's
  # Step 2 chains into. (We use a STUB INIT.md inside the sandbox to keep
  # tests hermetic, but the real file must exist in the scaffolder repo for
  # `requires.verify` to mean anything.)
  local scaffolder_init="$REPO_ROOT/add-observability/init/INIT.md"
  if [ ! -f "$scaffolder_init" ]; then
    echo "  ${RED}✗${RESET} scaffolder source missing: $scaffolder_init — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0013_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0013-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    # The scaffolder-side files the migration references live under
    # $HOME/.claude/skills/agenticapps-workflow/. The fixture's common-setup.sh
    # populates the stub layout directly (kept in-sandbox for hermeticity,
    # same as 0011/0012).

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
    run_0013_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0014 — Inject spec §11 canonical block (closes spec 0.4.0 §11)
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
# Migration 0017 — Adopt Axiom logs destination on existing v0.4.x wrappers
# ─────────────────────────────────────────────────────────────────────────────
# UNLIKE the idempotency-only migrations (0014/0015), 0017 ships an executable
# apply engine (templates/.claude/scripts/migrate-0017-axiom-destination.sh)
# that owns the HIGH-RISK pieces: wrapper discovery, content-hash hand-modified
# detection, the all-clean gate, refuse + .observability-0017.patch generation,
# and the safe-root apply. The harness therefore runs the engine END-TO-END per
# fixture (like 0005/0006/0010 run their scripts) rather than only probing
# idempotency checks.
#
# Each fixture: setup.sh builds a sandboxed downstream project (v1.15.0) with
# specific wrapper roots; verify.sh invokes the engine and asserts the full
# behaviour (files written / NOT written, .patch produced, CLAUDE.md block,
# version bump), returning its own exit code which is compared to expected-exit.
#
# RED gate: until the migration markdown AND the apply engine both land (GREEN
# commit), the sanity checks below FAIL — the TDD discipline the phase requires.

test_migration_0017() {
  echo ""
  echo "${YELLOW}━━━ Migration 0017 — Adopt Axiom logs destination ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0017"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity: the apply engine the fixtures invoke must exist + be executable.
  local engine="$REPO_ROOT/templates/.claude/scripts/migrate-0017-axiom-destination.sh"
  if [ ! -x "$engine" ]; then
    echo "  ${RED}✗${RESET} apply engine missing/non-executable: $engine — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # Sanity: migration 0017 markdown itself exists (RED until GREEN commit).
  local migration_file="$REPO_ROOT/migrations/0017-add-axiom-logs-destination.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # Sanity: known-wrapper-hashes.json exists and is valid JSON.
  local hashes="$fixtures/known-wrapper-hashes.json"
  if ! jq -e . < "$hashes" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} known-wrapper-hashes.json missing or invalid JSON — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0017_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0017-${fixname}-XXXXXX")"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
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
      REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -15
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
    run_0017_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Preflight-correctness audit (Phase 13)
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
  local audit_pass=0 audit_fail=0 audit_skip=0
  RAN_AUDIT=1

  local mode_label="informational"
  [ "$STRICT_PREFLIGHT" = "1" ] && mode_label="strict — failures gate exit"

  echo ""
  echo "${YELLOW}━━━ Preflight-correctness audit ($mode_label) ━━━${RESET}"
  echo "  Exercises each migration's requires.verify against THIS machine."
  echo "  Failures may mean either a broken verify path (real bug) OR a"
  echo "  missing local dependency (expected on fresh machines)."
  echo ""

  # Sanity-check that python3 + pyyaml are available; skip the whole audit
  # cleanly if not (degrades gracefully on minimal CI images). In strict
  # mode this is a real failure — CI should install PyYAML or accept
  # missing audit coverage as a regression.
  if ! python3 -c 'import yaml' 2>/dev/null; then
    if [ "$STRICT_PREFLIGHT" = "1" ]; then
      echo "  ${RED}✗${RESET} python3 with PyYAML not available — audit cannot run (strict)"
      FAIL=$((FAIL+1))
    else
      echo "  ${YELLOW}~${RESET} python3 with PyYAML not available — preflight audit skipped"
    fi
    return 0
  fi

  for migration in "$REPO_ROOT/migrations"/[0-9]*.md; do
    local id
    id="$(basename "$migration" | sed 's/-.*//')"
    local verifies
    verifies=$(python3 - "$migration" <<'PY'
import sys, re, yaml
text = open(sys.argv[1]).read()
m = re.search(r'^---\n(.*?)\n---', text, re.DOTALL | re.MULTILINE)
if not m:
    sys.exit(0)
try:
    fm = yaml.safe_load(m.group(1))
except Exception:
    sys.exit(0)
requires = fm.get('requires') if isinstance(fm, dict) else None
if not isinstance(requires, list):
    sys.exit(0)
for entry in requires:
    if isinstance(entry, dict) and 'verify' in entry:
        v = entry['verify']
        if isinstance(v, str) and v.strip():
            print(v)
PY
    )

    if [ -z "$verifies" ]; then
      audit_skip=$((audit_skip+1))
      continue
    fi

    while IFS= read -r v; do
      [ -z "$v" ] && continue
      if eval "$v" >/dev/null 2>&1; then
        printf "  ${GREEN}✓${RESET} %s: %s\n" "$id" "$v"
        audit_pass=$((audit_pass+1))
      else
        local rc=$?
        printf "  ${RED}✗${RESET} %s: %s (exit %d)\n" "$id" "$v" "$rc"
        audit_fail=$((audit_fail+1))
      fi
    done <<< "$verifies"
  done

  echo ""
  printf "  Audit summary: ${GREEN}PASS=%d${RESET} ${RED}FAIL=%d${RESET} ${YELLOW}SKIP=%d${RESET}\n" \
    "$audit_pass" "$audit_fail" "$audit_skip"
  if [ "$STRICT_PREFLIGHT" = "1" ]; then
    if [ "$audit_fail" -gt 0 ]; then
      FAIL=$((FAIL + audit_fail))
      echo "  (counted in suite totals — strict mode: $audit_fail FAIL rolled into global FAIL.)"
    else
      echo "  (counted in suite totals — strict mode: 0 audit FAIL to roll in.)"
    fi
  else
    echo "  (NOT counted in suite totals — pass --strict-preflight to gate.)"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0016 — Review gate phase-resolution fix (ADR 0025)
# ─────────────────────────────────────────────────────────────────────────────
# The resolver behavior is exercised in detail by fixtures 14/15/16 under
# test-fixtures/0005 (run by test_migration_0005 — they share the hook script).
# This function validates migration 0016's own guarantees: the template hook
# carries the ADR-0025 marker (the idempotency anchor), and a directory-style
# current-phase with an unreviewed/unexecuted plan blocks (the Verify smoke test).
test_migration_0016() {
  echo ""
  echo "${YELLOW}━━━ Migration 0016 — Review gate phase-resolution fix (ADR 0025) ━━━${RESET}"

  local script="$REPO_ROOT/templates/.claude/hooks/multi-ai-review-gate.sh"

  if [ ! -x "$script" ]; then
    echo "  ${RED}✗${RESET} hook missing or non-executable at $script"
    FAIL=$((FAIL+1))
    return
  fi

  # 1. Idempotency marker present (the string migration 0016 greps for).
  if grep -q 'resolver: hybrid (ADR 0025)' "$script"; then
    echo "  ${GREEN}✓${RESET} hook carries ADR-0025 resolver marker"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} hook missing 'resolver: hybrid (ADR 0025)' marker"
    FAIL=$((FAIL+1))
  fi

  # 2. Verify smoke test: directory-style current-phase blocks (exit 2).
  local tmp; tmp="$(mktemp -d -t "migration-0016-XXXXXX")"
  ( cd "$tmp" \
    && mkdir -p .planning/current-phase .planning/phases/01-x \
    && touch .planning/phases/01-x/01-PLAN.md \
    && echo '{"tool_name":"Edit","tool_input":{"file_path":"src/a.go"}}' \
       | bash "$script" >/dev/null 2>&1 )
  local rc=$?
  if [ "$rc" = "2" ]; then
    echo "  ${GREEN}✓${RESET} dir-style current-phase blocks (exit 2)"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} dir-style current-phase did not block (exit $rc, expected 2)"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmp"
}

# ─────────────────────────────────────────────────────────────────────────────
# meta.yaml ↔ adapter role-table consistency (Phase 21 / P4.3)
# ─────────────────────────────────────────────────────────────────────────────
#
# `init` (add-observability/init/INIT.md) is an agent-followed markdown runbook,
# not an executable binary, so there is no `add-observability init` command a
# shell fixture can invoke. The automatable backstop for Phase 1.5's
# destination role assignment is this consistency check: every stack's
# meta.yaml `destinations.roles_supported` MUST exactly match that stack's
# wrapper adapter role table (`ADAPTER_SUPPORTED_ROLES` for TS,
# `adapterSupportedRoles` for Go). init reads `roles_supported` to validate
# `--destinations` fail-closed; the wrapper's runtime `resolveConfig` reads the
# adapter table. If they drift, init would accept/reject overrides differently
# from the wrapper — this test makes that drift a failure.

# Extract "sentry=errors,logs;axiom=logs,analytics" from a TS registry.ts
# ADAPTER_SUPPORTED_ROLES block or a Go adapterSupportedRoles map.
_roles_from_adapter() {
  local file="$1"
  # Scope to the role table ONLY (not the ADAPTER_FACTORIES map, which also has
  # sentry:/axiom: keys). TS: ADAPTER_SUPPORTED_ROLES with [...] arrays;
  # Go: adapterSupportedRoles with {...} maps.
  #   TS:  sentry: ["errors", "logs"],   axiom: ["logs", "analytics"],
  #   Go:  destSentry: {RoleErrors, RoleLogs},  destAxiom: {RoleLogs, RoleAnalytics},
  awk '
    function emit(dest, body,   n, parts, i, role, out) {
      gsub(/[][{}"]/, "", body); gsub(/[ \t]/, "", body)
      gsub(/Role/, "", body)            # Go: RoleErrors -> Errors
      n = split(body, parts, ","); out = ""
      for (i = 1; i <= n; i++) { role = tolower(parts[i]); if (role != "") out = out (out==""?"":",") role }
      print dest "=" out
    }
    # Start ONLY at the declaration line (TS `const ... = {`, Go `var ... = map...{`),
    # not at comment mentions of the constant name elsewhere in the file.
    /(const ADAPTER_SUPPORTED_ROLES|var adapterSupportedRoles).*\{[ \t]*$/ { in_tbl = 1; next }
    in_tbl && /^[ \t]*}/                            { in_tbl = 0 }
    in_tbl && /^[ \t]*(sentry|destSentry)[ \t]*:/   { sub(/^[^:]*:/, ""); emit("sentry", $0) }
    in_tbl && /^[ \t]*(axiom|destAxiom)[ \t]*:/     { sub(/^[^:]*:/, ""); emit("axiom",  $0) }
  ' "$file" | sort | tr '\n' ';'
}

# Extract "sentry=errors,logs;axiom=logs,analytics" from a meta.yaml
# destinations.roles_supported block.
_roles_from_meta() {
  local file="$1"
  awk '
    /^destinations:/            { in_d = 1; next }
    in_d && /^[^[:space:]]/     { in_d = 0; in_r = 0 }      # left the top-level block
    in_d && /roles_supported:/  { in_r = 1; next }
    in_r && /^[^[:space:]]/     { in_r = 0 }
    in_r && /^[ \t]+(sentry|axiom)[ \t]*:/ {
      line = $0
      split(line, kv, ":"); dest = kv[1]; gsub(/[ \t]/, "", dest)
      body = substr(line, index(line, ":") + 1)
      # strip trailing inline comment, brackets, quotes, whitespace
      sub(/#.*/, "", body); gsub(/[]["]/, "", body); gsub(/[ \t]/, "", body)
      n = split(body, parts, ","); out = ""
      for (i = 1; i <= n; i++) { r = tolower(parts[i]); if (r != "") out = out (out==""?"":",") r }
      print dest "=" out
    }
  ' "$file" | sort | tr '\n' ';'
}

test_meta_destinations_consistency() {
  echo ""
  echo "${YELLOW}━━━ Phase 21 / P4 — meta.yaml ↔ adapter role-table consistency ━━━${RESET}"

  local tdir="$REPO_ROOT/add-observability/templates"
  # stack -> adapter role-table source file (TS registry.ts / Go destinations.go)
  local stacks="ts-cloudflare-worker ts-cloudflare-pages ts-supabase-edge ts-react-vite go-fly-http"

  for s in $stacks; do
    local meta="$tdir/$s/meta.yaml"
    local adapter=""
    if [ -f "$tdir/$s/destinations/registry.ts" ]; then
      adapter="$tdir/$s/destinations/registry.ts"
    elif [ -f "$tdir/$s/destinations.go" ]; then
      adapter="$tdir/$s/destinations.go"
    fi

    if [ ! -f "$meta" ]; then
      echo "  ${RED}✗${RESET} $s: meta.yaml missing"; FAIL=$((FAIL+1)); continue
    fi
    if [ -z "$adapter" ]; then
      echo "  ${RED}✗${RESET} $s: adapter role-table source not found"; FAIL=$((FAIL+1)); continue
    fi

    local meta_roles adapter_roles
    meta_roles="$(_roles_from_meta "$meta")"
    adapter_roles="$(_roles_from_adapter "$adapter")"

    # Expected canonical shape (guards against the awk silently emitting "").
    local expected="axiom=logs,analytics;sentry=errors,logs;"
    if [ "$meta_roles" != "$expected" ]; then
      echo "  ${RED}✗${RESET} $s: meta roles_supported = '$meta_roles' (want '$expected')"
      FAIL=$((FAIL+1)); continue
    fi
    if [ "$meta_roles" = "$adapter_roles" ]; then
      echo "  ${GREEN}✓${RESET} $s: roles_supported matches adapter table ($meta_roles)"
      PASS=$((PASS+1))
    else
      echo "  ${RED}✗${RESET} $s: meta '$meta_roles' != adapter '$adapter_roles'"
      FAIL=$((FAIL+1))
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0018 — Post-phase observability scan hook (advisory)
# ─────────────────────────────────────────────────────────────────────────────
# Like 0014/0015 this is an idempotency-only migration (no apply engine). The
# fixtures probe the three steps' idempotency checks on pre-apply (01) and
# post-apply (02) states. PLUS a direct advisory-contract smoke test of the
# shipped template hook: it MUST exit 0 outside a GSD project AND without a
# baseline (the no-op-but-explicit acceptance criterion).

test_migration_0018() {
  echo ""
  echo "${YELLOW}━━━ Migration 0018 — Post-phase observability scan hook (advisory) ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0018"
  local migration_file="$REPO_ROOT/migrations/0018-postphase-observability-hook.md"
  local hook="$REPO_ROOT/templates/.claude/hooks/observability-postphase-scan.sh"

  # Sanity (RED until the GREEN commit lands all three artifacts).
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"; FAIL=$((FAIL+1)); return
  fi
  if [ ! -x "$hook" ]; then
    echo "  ${RED}✗${RESET} hook template missing/non-executable: $hook — RED state"; FAIL=$((FAIL+1)); return
  fi
  if ! jq -e '.hooks.post_phase.observability_scan' "$REPO_ROOT/templates/config-hooks.json" >/dev/null 2>&1; then
    echo "  ${RED}✗${RESET} config-hooks.json missing post_phase.observability_scan — RED state"; FAIL=$((FAIL+1)); return
  fi

  # Advisory contract: never exits non-zero.
  local smoke; smoke="$(mktemp -d -t migration-0018-smoke-XXXXXX)"
  ( cd "$smoke" && bash "$hook" >/dev/null 2>&1 ); local rc_outside=$?
  ( cd "$smoke" && mkdir -p .planning && bash "$hook" >/dev/null 2>&1 ); local rc_nobaseline=$?
  rm -rf "$smoke"
  if [ "$rc_outside" -eq 0 ] && [ "$rc_nobaseline" -eq 0 ]; then
    echo "  ${GREEN}✓${RESET} hook is advisory — exit 0 outside GSD and without a baseline"
    PASS=$((PASS+1))
  else
    echo "  ${RED}✗${RESET} hook must always exit 0 (outside=$rc_outside, no-baseline=$rc_nobaseline)"
    FAIL=$((FAIL+1))
  fi

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"; SKIP=$((SKIP+1)); return
  fi

  run_0018_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0018-${fixname}-XXXXXX")"

    if [ -x "$fixdir/setup.sh" ]; then
      ( cd "$tmp" && REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" "$fixdir/setup.sh" >/dev/null 2>&1 ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"; FAIL=$((FAIL+1)); rm -rf "$tmp"; return
      }
    fi

    local verify_out verify_exit
    verify_out=$( cd "$tmp" && REPO_ROOT="$REPO_ROOT" bash "$fixdir/verify.sh" 2>&1 )
    verify_exit=$?

    local expected_exit; expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -10
      FAIL=$((FAIL+1)); rm -rf "$tmp"; return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"; PASS=$((PASS+1)); rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name; name="$(basename "${fix%/}")"
    run_0018_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Migration 0019 — Sentry Crons withCronMonitor + healthz snippets
# ─────────────────────────────────────────────────────────────────────────────
# Same harness shape as test_migration_0017 / 0018: per-fixture setup.sh
# materialises a synthetic v1.17.0 project; per-fixture verify.sh invokes the
# 0019 apply engine, asserts engine exit code + post-state, and exits 0/non-0.
# expected-exit is the verify.sh exit code (0 across all current fixtures —
# refuse-path fixtures still exit 0 from verify.sh once they have confirmed
# the engine itself exited 2).
test_migration_0019() {
  echo ""
  echo "${YELLOW}━━━ Migration 0019 — Sentry Crons + healthz (additive) ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0019"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  # Sanity: the apply engine the fixtures invoke must exist + be executable.
  local engine="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
  if [ ! -x "$engine" ]; then
    echo "  ${RED}✗${RESET} apply engine missing/non-executable: $engine — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  # Sanity: migration 0019 markdown itself exists (RED until GREEN commit).
  local migration_file="$REPO_ROOT/migrations/0019-sentry-crons-and-healthz.md"
  if [ ! -f "$migration_file" ]; then
    echo "  ${RED}✗${RESET} migration file missing: $migration_file — RED state"
    FAIL=$((FAIL+1))
    return
  fi

  run_0019_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0019-${fixname}-XXXXXX")"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
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
      REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -15
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
    run_0019_fixture "$name"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# F4 — SKILL.md version drift test (D-06 / G4)
# Asserts skill/SKILL.md version equals the highest-numbered migration's to_version.
# ─────────────────────────────────────────────────────────────────────────────

test_skill_md_version_matches_latest_migration_to_version() {
  # NOTE (D-04): intentionally minimal grep + awk parser. Fragile against
  # YAML variations (quoted values, indented keys, trailing comments).
  # SKILL.md frontmatter is fixed-shape (`version: X.Y.Z` on its own line);
  # if that ever changes, this test must be updated.

  local skill_version latest_migration_file migration_to_version

  skill_version=$(grep ^version: skill/SKILL.md | awk '{print $2}')
  latest_migration_file=$(ls migrations/[0-9][0-9][0-9][0-9]-*.md | sort | tail -1)
  migration_to_version=$(grep ^to_version: "$latest_migration_file" | awk '{print $2}')

  local migration_num
  migration_num=$(basename "$latest_migration_file" | cut -c1-4)

  if [ "$skill_version" = "$migration_to_version" ]; then
    echo "  ${GREEN}PASS${RESET}: test-skill-md-version-matches-latest-migration-to-version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}FAIL${RESET}: SKILL.md at v${skill_version} but migration ${migration_num} declares to_version: v${migration_to_version}"
    FAIL=$((FAIL+1))
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# F3 — SIGTERM split-trap + path-validated --pause-between-passes (R-rev-2)
# Verifies:
#   Case 1 — SIGTERM mid-apply: engine exits 143, no half-written files.
#   Case 2 — silent-on-success: EXIT trap emits NO "cleanup" output on exit 0.
#   Case 3 — no secret leak: SIGTERM stderr has no SENTRY_DSN/API_KEY/TOKEN.
#   Case 4 — path validation: /etc/passwd rejected (exit 2), allow-listed OK.
# ─────────────────────────────────────────────────────────────────────────────

test_sigterm_mid_apply_preserves_state() {
  echo ""
  echo "${YELLOW}━━━ F3 SIGTERM split-trap + --pause-between-passes ━━━${RESET}"

  local ENGINE="$REPO_ROOT/templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh"
  local TEMPLATES="$REPO_ROOT/add-observability/templates"

  # ── Shared project setup helper ─────────────────────────────────────────────
  _setup_sigterm_project() {
    local dir="$1"
    mkdir -p "$dir/.claude/skills/agentic-apps-workflow"
    cat > "$dir/.claude/skills/agentic-apps-workflow/SKILL.md" <<'EOF'
---
name: agentic-apps-workflow
version: 1.17.0
implements_spec: 0.4.0
description: synthetic test fixture for migration 0019
---
EOF
    local wroot="$dir/src/lib/observability"
    mkdir -p "$wroot"
    cp "$TEMPLATES/ts-cloudflare-worker/lib-observability.ts" "$wroot/lib-observability.ts"
    cp "$TEMPLATES/ts-cloudflare-worker/middleware.ts"        "$wroot/middleware.ts"
  }

  # ── Case 4 — path validation (cheapest; no signal needed) ──────────────────
  # 4a. /etc/passwd must be rejected with exit 2 + expected error message.
  local bad_stderr; bad_stderr=$(mktemp)
  local bad_exit
  set +e
  bash "$ENGINE" --pause-between-passes /etc/passwd 2>"$bad_stderr"
  bad_exit=$?
  set -e
  if [ "$bad_exit" -ne 2 ]; then
    echo "  ${RED}✗${RESET} path validation: expected exit 2 for /etc/passwd, got $bad_exit"
    FAIL=$((FAIL+1))
    rm -f "$bad_stderr"
    return
  fi
  if ! grep -q "test-only flag with non-allow-listed path" "$bad_stderr"; then
    echo "  ${RED}✗${RESET} path validation: expected 'test-only flag with non-allow-listed path' in stderr"
    FAIL=$((FAIL+1))
    rm -f "$bad_stderr"
    return
  fi
  rm -f "$bad_stderr"

  # 4b. With TMPDIR unset: /etc/passwd still rejected (${TMPDIR:-/tmp} default used).
  local bad_exit2
  set +e
  ( unset TMPDIR; bash "$ENGINE" --pause-between-passes /etc/passwd >/dev/null 2>&1 )
  bad_exit2=$?
  set -e
  if [ "$bad_exit2" -ne 2 ]; then
    echo "  ${RED}✗${RESET} path validation (TMPDIR unset): expected exit 2, got $bad_exit2"
    FAIL=$((FAIL+1))
    return
  fi

  # 4c. Allow-listed TMPDIR path: engine must NOT emit the path-validation error.
  #     (Engine may still exit non-zero for other reasons — e.g. all-clean gate —
  #     when run without --project-dir pointing at a clean sandbox. What matters is
  #     the absence of the path-validation rejection message in stderr.)
  local allowed_sig="${TMPDIR:-/tmp}/sigterm-test-pathcheck"
  local allowed_stderr; allowed_stderr=$(mktemp)
  set +e
  bash "$ENGINE" --pause-between-passes "$allowed_sig" >/dev/null 2>"$allowed_stderr"
  set -e
  if grep -q "test-only flag with non-allow-listed path" "$allowed_stderr"; then
    echo "  ${RED}✗${RESET} path validation: allow-listed TMPDIR path incorrectly rejected (path-validation message present)"
    FAIL=$((FAIL+1))
    rm -f "$allowed_stderr"
    return
  fi
  rm -f "$allowed_stderr"

  # 4d. Allow-listed fixture prefix: no path-validation rejection message.
  local fixture_sig="$REPO_ROOT/migrations/test-fixtures/0019/06-multi-root-mixed-clean-dirty-refuses-all/sigterm-foo"
  local fixture_stderr; fixture_stderr=$(mktemp)
  set +e
  bash "$ENGINE" --pause-between-passes "$fixture_sig" >/dev/null 2>"$fixture_stderr"
  set -e
  if grep -q "test-only flag with non-allow-listed path" "$fixture_stderr"; then
    echo "  ${RED}✗${RESET} path validation: allow-listed fixture path incorrectly rejected (path-validation message present)"
    FAIL=$((FAIL+1))
    rm -f "$fixture_stderr"
    return
  fi
  rm -f "$fixture_stderr"

  # ── Case 2 — silent-on-success (EXIT trap must emit nothing on exit 0) ──────
  local clean_dir; clean_dir=$(mktemp -d "${TMPDIR:-/tmp}/sigterm-test-clean-XXXX")
  _setup_sigterm_project "$clean_dir"
  local normal_stderr; normal_stderr=$(mktemp)
  local normal_exit
  set +e
  bash "$ENGINE" --templates-dir "$TEMPLATES" --project-dir "$clean_dir" \
    >/dev/null 2>"$normal_stderr"
  normal_exit=$?
  set -e
  if [ "$normal_exit" -ne 0 ]; then
    echo "  ${RED}✗${RESET} silent-on-success: normal run expected exit 0, got $normal_exit"
    FAIL=$((FAIL+1))
    rm -rf "$clean_dir"; rm -f "$normal_stderr"
    return
  fi
  if grep -q "cleanup" "$normal_stderr"; then
    echo "  ${RED}✗${RESET} silent-on-success: EXIT trap leaked 'cleanup' output on exit 0 (codex HIGH-2)"
    echo "      stderr was:"
    sed 's/^/        /' "$normal_stderr" | head -10
    FAIL=$((FAIL+1))
    rm -rf "$clean_dir"; rm -f "$normal_stderr"
    return
  fi
  rm -rf "$clean_dir"; rm -f "$normal_stderr"

  # ── Case 1 + 3 — SIGTERM: exit 143 + no secrets in cleanup output ───────────
  local sig_dir; sig_dir=$(mktemp -d "${TMPDIR:-/tmp}/sigterm-test-XXXX")
  local SIG="$sig_dir/sigterm-test-signal"
  _setup_sigterm_project "$sig_dir"

  local sigterm_stderr; sigterm_stderr=$(mktemp)
  bash "$ENGINE" --templates-dir "$TEMPLATES" --project-dir "$sig_dir" \
    --pause-between-passes "$SIG" \
    >/dev/null 2>"$sigterm_stderr" &
  local ENGINE_PID=$!

  # Wait up to 10 seconds for the signal file to appear.
  local i
  for i in $(seq 1 50); do
    [ -f "$SIG" ] && break
    sleep 0.2
  done

  if [ ! -f "$SIG" ]; then
    echo "  ${RED}✗${RESET} SIGTERM: engine never reached pause (signal file absent after 10s)"
    kill -9 "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
    FAIL=$((FAIL+1))
    rm -rf "$sig_dir"; rm -f "$sigterm_stderr"
    return
  fi

  kill -TERM "$ENGINE_PID" 2>/dev/null || true
  local engine_exit
  set +e
  wait "$ENGINE_PID"
  engine_exit=$?
  set -e

  # Case 1: SIGTERM must produce exit 143.
  if [ "$engine_exit" -ne 143 ]; then
    echo "  ${RED}✗${RESET} SIGTERM: expected exit 143, got $engine_exit"
    FAIL=$((FAIL+1))
    rm -rf "$sig_dir"; rm -f "$sigterm_stderr"
    return
  fi

  # Case 1b: no half-written cron-monitor.ts.
  if find "$sig_dir" -name "cron-monitor.ts" -type f | grep -q .; then
    echo "  ${RED}✗${RESET} SIGTERM: cron-monitor.ts found (half-written after SIGTERM)"
    FAIL=$((FAIL+1))
    rm -rf "$sig_dir"; rm -f "$sigterm_stderr"
    return
  fi

  # Case 3: no secrets in cleanup output (T-23-05).
  if grep -qE "(SENTRY_DSN|API_KEY|TOKEN)=" "$sigterm_stderr"; then
    echo "  ${RED}✗${RESET} T-23-05: secret variable leaked in SIGTERM stderr"
    FAIL=$((FAIL+1))
    rm -rf "$sig_dir"; rm -f "$sigterm_stderr"
    return
  fi

  rm -rf "$sig_dir"; rm -f "$sigterm_stderr"

  echo "  ${GREEN}PASS${RESET}: test-sigterm-mid-apply-preserves-state"
  PASS=$((PASS+1))
}

# ─────────────────────────────────────────────────────────────────────────────
# Dispatcher
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

if [ -z "$FILTER" ] || [ "$FILTER" = "0012" ]; then
  test_migration_0012
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0013" ]; then
  test_migration_0013
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

if [ -z "$FILTER" ] || [ "$FILTER" = "0017" ]; then
  test_migration_0017
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0018" ]; then
  test_migration_0018
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0019" ]; then
  test_migration_0019
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "preflight" ]; then
  test_preflight_verify_paths
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "destinations" ]; then
  test_meta_destinations_consistency
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

if [ -z "$FILTER" ] || [ "$FILTER" = "test-sigterm-mid-apply-preserves-state" ]; then
  if declare -F test_sigterm_mid_apply_preserves_state >/dev/null 2>&1; then
    test_sigterm_mid_apply_preserves_state
  elif [ -n "$FILTER" ]; then
    echo "${YELLOW}SKIP${RESET}: test-sigterm-mid-apply-preserves-state (function not yet defined)"
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
