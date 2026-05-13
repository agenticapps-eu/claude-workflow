#!/usr/bin/env bash
# Migration test harness — verifies idempotency checks behave correctly
# against known before / after reference states extracted from git.
#
# Usage:
#   migrations/run-tests.sh                # run all testable migrations
#   migrations/run-tests.sh 0001           # run only migration 0001
#
# See migrations/test-fixtures/README.md for the contract.

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

# Filter (optional first arg)
FILTER="${1:-}"

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

  # Fetch origin/main to avoid stale-clone surprises before computing merge-base.
  git fetch --quiet origin main 2>/dev/null || true
  local before_ref="$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || git rev-parse main)"
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
  assert_check "Step 5 idempotency: needs apply on before-fresh (still 1.7.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$fresh_dir" not-applied
  assert_check "Step 5 idempotency: needs apply on before-inlined-pristine (still 1.7.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$inlined_pristine_dir" not-applied
  assert_check "Step 5 idempotency: needs apply on before-inlined-customised (still 1.7.0)" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$inlined_customised_dir" not-applied
  assert_check "Step 5 idempotency: skip on after-vendored" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$vendored_dir" applied
  assert_check "Step 5 idempotency: skip on after-idempotent" \
    "grep -q '^version: 1.8.0' .claude/skills/agentic-apps-workflow/SKILL.md" "$idempotent_dir" applied
}

# ─────────────────────────────────────────────────────────────────────────────
# Dispatcher
# ─────────────────────────────────────────────────────────────────────────────

if [ -z "$FILTER" ] || [ "$FILTER" = "0001" ]; then
  test_migration_0001
fi

if [ -z "$FILTER" ] || [ "$FILTER" = "0009" ]; then
  test_migration_0009
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
elif [ $PASS -eq 0 ] && [ $SKIP -eq 0 ]; then
  echo "  ${RED}NO TESTS RAN${RESET}"
  exit 1
else
  exit 0
fi
