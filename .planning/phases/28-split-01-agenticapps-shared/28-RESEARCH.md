# Phase 28: SPLIT-01 agenticapps-shared — Research

**Researched:** 2026-06-02
**Domain:** Bash script carve — `migrations/run-tests.sh` (2579 lines) → `agenticapps-shared/migrations/lib/*.sh` + git submodule wiring
**Confidence:** HIGH (primary source is the annotated file itself, read in full)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-28a — Sharing mechanism = git submodule (LOCKED, user).** Both consumers vendor the shared repo at `vendor/agenticapps-shared/`, SHA/tag-pinned. CI must clone with `--recurse-submodules`. Rejected: npm, vendored copy.
- **D-28b — History preservation = provenance-by-note (LOCKED, user).** `run-tests.sh` is ONE 2579-line file; `git filter-repo` cannot carve SHARED-only functions. Shared helpers are refactored into new `migrations/lib/*.sh` files; `git log --follow` lineage is NOT preserved for carved code. Provenance via CHANGELOG "Migration provenance" section + commit messages referencing the originating SHA(s). `git log --follow` applies only to any WHOLE-FILE moves that exist.
- **D-28c — SHARED/WORKFLOW boundary = ADR-0035 annotations (canonical).** `# SHARED` / `# WORKFLOW` markers IN `migrations/run-tests.sh` are the canonical line-level boundary map. If ADR-0035's tables conflict with the file, the file wins.
- **D-28d — Drift test: MECHANISM shared, POLICY stays.** The generic grep+awk runner (reads SKILL.md `version`, finds latest migration `to_version`, compares) is SHARED. The specific rule "SKILL.md version == latest migration to_version" is claude-workflow POLICY and STAYS. The shared runner takes SKILL.md path + migrations dir as inputs; the consumer owns "PASS is required."
- **D-28e — claude-workflow run-tests.sh becomes a consumer.** After extraction, `migrations/run-tests.sh` SOURCES the shared lib from `vendor/agenticapps-shared/migrations/lib/*.sh`, KEEPS all WORKFLOW per-migration test bodies + the drift POLICY, and stays the entry point developers run. Recommendation from context: source-and-keep (not thin-shim) so per-migration bodies stay co-located with migrations.
- **D-28f — Formal rigor (LOCKED, user).** Full GSD plan cycle: gsd-planner → gsd-plan-checker → /gsd-review.

### Claude's Discretion

- Exact lib file decomposition (`helpers.sh` / `fixture-runner.sh` / `drift-test.sh` / `dispatcher.sh`)
- Whether any whole-file moves go via filter-repo (history-preserved) vs. fresh copy with provenance note — prefer filter-repo where a file moves WHOLE and is genuinely generic.
- Submodule pin: tag `v1.0.0` (cut at ship) vs. commit SHA — recommend tag.

### Deferred Ideas (OUT OF SCOPE)

- `agenticapps-shared` go-public flip + LICENSE choice.
- `add-observability` → `observability` rename, obs fix backports, #58.
- Whether agenticapps-shared needs its OWN drift test.
</user_constraints>

---

## Summary

Phase 28 extracts the SHARED harness layer from `migrations/run-tests.sh` (2579 lines, fully read) into new `migrations/lib/*.sh` files in `agenticapps-eu/agenticapps-shared` (Phase A already done — skeleton at `d136c96`, tag `v1.0.0-pre.0`). The claude-workflow `run-tests.sh` then sources the shared lib and retains all per-migration WORKFLOW test bodies. The boundary is entirely pre-decided by ADR-0035 annotations in the file: 9 SHARED annotations / 20 WORKFLOW annotations, zero unannotated top-level functions.

The key non-obvious finding is a **coupling concern in `setup_fixture`**: the function is annotated SHARED but contains two claude-workflow-specific hardcodings (`agentic-apps-workflow` skill name, `templates/workflow-config.md` git paths) that make it partial-WORKFLOW. This must be resolved by parameterizing the function before landing it in the shared lib.

The actual test suite state: **PASS=186, FAIL=4**. The 4 failures are all in `test_migration_0017` (migration 0017 fxsa-shape fixtures — WORKFLOW-specific, observability-layer, pre-existing). The SHARED harness functions (extract_to, run_check, assert_check) all work correctly. The FAIL=4 baseline must be preserved (not fixed) by this phase — any change to that count is a regression signal.

**Primary recommendation:** Execute the carve in this order: (1) write `lib/helpers.sh` (cleanup trap + assert_check + run_check + color vars), (2) write `lib/fixture-runner.sh` (extract_to + parameterized setup_fixture), (3) write `lib/preflight.sh` (test_preflight_verify_paths), (4) write `lib/drift-test.sh` (parameterized drift runner mechanism), (5) update claude-workflow `run-tests.sh` to source the four lib files, (6) add git submodule, (7) update install.sh.

---

## Standard Stack

No new library dependencies. This is pure bash refactoring + git plumbing.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | ≥3.2 (macOS ships 3.2) | Shell runtime for all lib files | Already required by run-tests.sh |
| git | any modern | Submodule wiring + git show calls in extract_to | Already required |
| git-filter-repo | installed (brew) | Whole-file moves with history | `brew install git-filter-repo` confirmed done per STATE.md |
| python3 + pyyaml | system | test_preflight_verify_paths YAML parsing | Already required by the preflight audit |

[VERIFIED: direct file read of run-tests.sh line 27 — `set -uo pipefail`; confirmed no external deps]

**Installation (submodule wiring only):**
```bash
git submodule add https://github.com/agenticapps-eu/agenticapps-shared vendor/agenticapps-shared
git submodule update --init --recursive
```

---

## Architecture Patterns

### Recommended Lib File Decomposition

```
agenticapps-shared/migrations/lib/
├── helpers.sh         # Color vars, PASS/FAIL/SKIP counters (owned by shared), run_check, assert_check, _runtests_do_cleanup + trap setup
├── fixture-runner.sh  # extract_to, setup_fixture (parameterized — see coupling note below)
├── preflight.sh       # test_preflight_verify_paths (parameterized: takes migrations_dir as arg)
└── drift-test.sh      # run_drift_test (parameterized: takes skill_md_path, migrations_dir)
```

```
claude-workflow/migrations/run-tests.sh  (AFTER extraction)
├── source vendor/agenticapps-shared/migrations/lib/helpers.sh
├── source vendor/agenticapps-shared/migrations/lib/fixture-runner.sh
├── source vendor/agenticapps-shared/migrations/lib/preflight.sh
├── source vendor/agenticapps-shared/migrations/lib/drift-test.sh
├── [preamble: set -uo pipefail, REPO_ROOT, flag parsing — STAYS]
├── [color vars — REMOVED (now in helpers.sh)]
├── [PASS/FAIL/SKIP/RAN_AUDIT — initialized in helpers.sh, reset here if needed]
├── test_migration_0001() ... test_migration_0021() — ALL STAY (WORKFLOW)
├── test_meta_destinations_consistency() + helpers — STAY (WORKFLOW)
├── test_sigterm_mid_apply_preserves_state() — STAYS (WORKFLOW)
├── [dispatcher block — STAYS, calls WORKFLOW functions + shared wrappers]
├── [drift policy invocation: run_drift_test "skill/SKILL.md" "migrations"]
└── [summary + exit — STAYS]
```

### Pattern 1: Sourcing shared lib with path resolution

The lib MUST resolve paths relative to the consuming script's location, not cwd. The pattern that works for both the claude-workflow consumer and the agenticapps-shared standalone test:

```bash
# In claude-workflow/migrations/run-tests.sh (consumer)
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../vendor/agenticapps-shared/migrations/lib" && pwd)"
source "$_LIB/helpers.sh"
source "$_LIB/fixture-runner.sh"
source "$_LIB/preflight.sh"
source "$_LIB/drift-test.sh"
```

```bash
# In agenticapps-shared/tests/run-tests.sh (standalone validation)
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../migrations/lib" && pwd)"
source "$_LIB/helpers.sh"
source "$_LIB/fixture-runner.sh"
# etc.
```

Key: use `${BASH_SOURCE[0]}` (not `$0`) so sourcing works even when the script is itself sourced. The `cd … && pwd` pattern is portable and avoids symlink issues.

[VERIFIED: current run-tests.sh uses `git rev-parse --show-toplevel` + `cd "$REPO_ROOT"` at lines 36-37; BASH_SOURCE[0] pattern is the correct generalization for sourced libs]

### Pattern 2: Parameterizing the drift test runner (D-28d)

Current code (lines 2247-2269, hardcoded paths):
```bash
test_skill_md_version_matches_latest_migration_to_version() {
  skill_version=$(grep ^version: skill/SKILL.md | awk '{print $2}')
  latest_migration_file=$(ls migrations/[0-9][0-9][0-9][0-9]-*.md | sort | tail -1)
  migration_to_version=$(grep ^to_version: "$latest_migration_file" | awk '{print $2}')
  ...
}
```

SHARED lib version (`lib/drift-test.sh`) — takes paths as parameters:
```bash
# run_drift_test SKILL_MD_PATH MIGRATIONS_DIR
# Returns: exits 0 if match (PASS), exits 1 if mismatch (emits FAIL message)
# Does NOT increment PASS/FAIL — caller owns that (policy separation)
run_drift_test() {
  local skill_md="$1" migrations_dir="$2"
  local skill_version latest_migration_file migration_to_version
  skill_version=$(grep ^version: "$skill_md" | awk '{print $2}')
  latest_migration_file=$(ls "${migrations_dir}"/[0-9][0-9][0-9][0-9]-*.md | sort | tail -1)
  migration_to_version=$(grep ^to_version: "$latest_migration_file" | awk '{print $2}')
  [ "$skill_version" = "$migration_to_version" ]
}
```

claude-workflow POLICY wrapper (stays in `run-tests.sh`):
```bash
test_skill_md_version_matches_latest_migration_to_version() {
  if run_drift_test "skill/SKILL.md" "migrations"; then
    echo "  ${GREEN}PASS${RESET}: test-skill-md-version-matches-latest-migration-to-version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}FAIL${RESET}: SKILL.md version does not match latest migration to_version"
    FAIL=$((FAIL+1))
  fi
}
```

### Pattern 3: Parameterizing test_preflight_verify_paths (D-28c)

Current code (line 1795): `for migration in "$REPO_ROOT/migrations"/[0-9]*.md; do`

SHARED version should take migrations_dir as parameter:
```bash
run_preflight_verify_paths() {
  local migrations_dir="$1"
  # ... all existing logic but using "$migrations_dir" instead of "$REPO_ROOT/migrations"
}
```

claude-workflow invocation stays as:
```bash
test_preflight_verify_paths() {
  run_preflight_verify_paths "$REPO_ROOT/migrations"
  # ... sets RAN_AUDIT=1, handles STRICT_PREFLIGHT, etc.
}
```

### Anti-Patterns to Avoid

- **Sourcing lib files relative to cwd:** `source migrations/lib/helpers.sh` breaks when the script is run from a different directory. Always use `${BASH_SOURCE[0]}` dirname.
- **Moving global counter initialization into lib without consumer reset:** If `helpers.sh` initializes `PASS=0 FAIL=0 SKIP=0`, sourcing it twice resets the counters. Put initialization in lib, but document that it runs once at source time.
- **Changing the `set -uo pipefail` mode when sourcing:** The lib files are sourced into an existing shell session; they MUST NOT call `set -e` (the current run-tests.sh already avoids this; the run_0005_fixture comment at line ~853 explicitly notes NOT toggling `-e` to avoid leaking it).
- **Assuming `REPO_ROOT` is set in lib files:** Lib files cannot know REPO_ROOT; callers pass paths as parameters.

---

## Critical Research Findings

### CRQ 1: Function Inventory + Boundary Map

Every top-level function in `migrations/run-tests.sh` with line range and boundary:

| Line Range | Function | Annotation | Boundary | Notes |
|-----------|----------|------------|----------|-------|
| 77–85 | `_runtests_do_cleanup()` | `# SHARED` L75 | SHARED | Signal trap handler; idempotent via `_runtests_cleanup_fired` flag |
| 86–91 | *(section comment)* | `# SHARED` L89 | — | Section header for helpers block |
| 96–104 | `extract_to()` | `# SHARED` L95 | SHARED | Generic git-ref extraction; no workflow-specific paths |
| 110–134 | `setup_fixture()` | `# SHARED` L109 | **SHARED with coupling** | Hardcodes `agentic-apps-workflow` skill name (L119-123) — see CRQ 2 |
| 139–143 | `run_check()` | `# SHARED` L138 | SHARED | Generic eval runner; no coupling |
| 151–170 | `assert_check()` | `# SHARED` L150 | SHARED | Generic PASS/FAIL counter; no coupling |
| 177–288 | `test_migration_0001()` | `# WORKFLOW` L174 | WORKFLOW | 20 tests; uses extract_to + setup_fixture |
| 300–481 | `test_migration_0009()` | `# WORKFLOW` L292 | WORKFLOW | 38 tests; hand-built fixtures |
| 494–795 | `test_migration_0010()` | `# WORKFLOW` L485 | WORKFLOW | 16 tests; runs normalize-claude-md.sh |
| 811–923 | `test_migration_0005()` | `# WORKFLOW` L799 | WORKFLOW | 16 tests; runs multi-ai-review-gate.sh |
| 939–1051 | `test_migration_0006()` | `# WORKFLOW` L927 | WORKFLOW | 15 tests; sandboxed HOME |
| 1063–1173 | `test_migration_0007()` | `# WORKFLOW` L1055 | WORKFLOW | 18 tests; hermetic env -i sandbox |
| 1196–1277 | `test_migration_0011()` | `# WORKFLOW` L1177 | WORKFLOW | 6 tests; checks add-observability/scan/SCAN.md |
| 1289–1364 | `test_migration_0012()` | `# WORKFLOW` L1281 | WORKFLOW | 5 tests; checks add-observability/SKILL.md |
| 1378–1455 | `test_migration_0013()` | `# WORKFLOW` L1368 | WORKFLOW | 5 tests; checks add-observability/init/INIT.md |
| 1470–1552 | `test_migration_0014()` | `# WORKFLOW` L1459 | WORKFLOW | 7 tests; sandboxed HOME |
| 1566–1646 | `test_migration_0015()` | `# WORKFLOW` L1556 | WORKFLOW | 4 tests; checks ts-declare-first/SKILL.md |
| 1668–1751 | `test_migration_0017()` | `# WORKFLOW` L1650 | WORKFLOW | 7 tests (4 PASS, 4 FAIL pre-existing) |
| 1767–1851 | `test_preflight_verify_paths()` | `# SHARED` L1755 | SHARED | Parameterization needed — see CRQ 5 |
| 1862–1899 | `test_migration_0016()` | `# WORKFLOW` L1855 | WORKFLOW | 2 tests; checks multi-ai-review-gate.sh |
| 1921–1943 | `_roles_from_adapter()` | `# WORKFLOW` L1920 | WORKFLOW | Helper for destinations consistency |
| 1948–1966 | `_roles_from_meta()` | `# WORKFLOW` L1947 | WORKFLOW | Helper for destinations consistency |
| 1968–2010 | `test_meta_destinations_consistency()` | `# WORKFLOW` L1903 | WORKFLOW | 5 tests; checks add-observability/templates |
| 2022–2087 | `test_migration_0018()` | `# WORKFLOW` L2014 | WORKFLOW | 3 tests; checks observability hook |
| 2099–2174 | `test_migration_0019()` | `# WORKFLOW` L2091 | WORKFLOW | 13 tests; runs migrate-0019 engine |
| 2181–2232 | `test_migration_0021()` | `# WORKFLOW` L2178 | WORKFLOW | 4 tests; runs migrate-0021 engine |
| 2247–2269 | `test_skill_md_version_matches_latest_migration_to_version()` | `# SHARED` L2237 | SHARED (mechanism) / WORKFLOW (policy) | See CRQ 5 |
| 2282–2460 | `test_sigterm_mid_apply_preserves_state()` | `# WORKFLOW` L2278 | WORKFLOW | Tests specific migrate-0019 engine |
| 2468–2560 | Dispatcher block | `# SHARED` L2464 | SHARED (shape) / WORKFLOW (calls) | The `if [ -z "$FILTER" ]` pattern is SHARED; the function calls are WORKFLOW |
| 2562–2579 | Summary + exit | — | WORKFLOW (stays) | PASS/FAIL print + exit code |

**Annotation gap check:** Zero unannotated top-level functions. All 27 top-level functions have an explicit `# SHARED` or `# WORKFLOW` annotation in the section header immediately above them. [VERIFIED: grep -c confirms 9 SHARED / 20 WORKFLOW annotations; manual cross-check of each function declaration]

Inner (nested) helper functions (`detect_inlined`, `run_normalize`, `assert_diff`, `run_0005_fixture`, etc.) are all defined inside WORKFLOW test functions and go with their parent function. No inner functions require separate annotation.

---

### CRQ 2: Call-Graph / Coupling Analysis

**Expected WORKFLOW → SHARED calls (correct direction):**
- `test_migration_0001` (L177) calls `setup_fixture` (SHARED) + `assert_check` (SHARED) — correct
- `test_migration_0009` (L300) calls `run_check` (SHARED) + `assert_check` (SHARED) — correct
- All other WORKFLOW test functions call `run_check` / `assert_check` / (some) `extract_to` — correct

**CRITICAL: SHARED → WORKFLOW coupling (breaks clean extraction):**

1. **`setup_fixture` hardcodes `agentic-apps-workflow` (lines 119–123):**
   ```bash
   mkdir -p "$tmpdir/.claude/skills/agentic-apps-workflow"
   cat >"$tmpdir/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF
   ---
   name: agentic-apps-workflow
   version: $version
   ```
   This is pure workflow-specific content in a SHARED-annotated function. The function is called only by WORKFLOW tests (0001), but its body assumes the skill being installed is `agentic-apps-workflow`.

   **Proposed fix:** Parameterize via a 4th argument:
   ```bash
   setup_fixture() {
     local tmpdir="$1" ref="$2" version="$3" skill_name="${4:-agentic-apps-workflow}"
     ...
     mkdir -p "$tmpdir/.claude/skills/$skill_name"
     cat >"$tmpdir/.claude/skills/$skill_name/SKILL.md" ...
   ```
   Claude-workflow callers continue to work unchanged (4th arg defaults to `agentic-apps-workflow`).

2. **`setup_fixture` hardcodes `templates/workflow-config.md`, `templates/config-hooks.json`, `templates/claude-md-sections.md` (lines 112–114):**
   These are passed as `git show "$ref:$path"` calls — they're path strings within the git repository being tested, not claude-workflow source paths. When `setup_fixture` is used by `agenticapps-observability`, it would need DIFFERENT template paths. This coupling is subtler: the function signature shows `ref` (a git ref) but the template paths are hardcoded.

   **Proposed fix:** Extract the path mapping as an override array or set of optional parameters. For the SPLIT-01 scope, document this as a known limitation — `agenticapps-observability` will override `setup_fixture` or pass different paths. The function as-is is still useful to move to shared (it works for claude-workflow's WORKFLOW tests), with the understanding that its hardcoded paths are a "blessed defaults" approach.

   ⚠️ **Decision concern:** The CONTEXT.md annotates `setup_fixture` as purely SHARED ("generic fixture-runner harness; agenticapps-observability needs this"). However the function body is only generic in structure — the git-ref paths and skill name are workflow-specific. The planner should note that `agenticapps-observability` will need to either (a) call `setup_fixture` with overrides or (b) define its own wrapper. This does not block SPLIT-01.

3. **`test_skill_md_version_matches_latest_migration_to_version` hardcodes paths `skill/SKILL.md` and `migrations/[0-9][0-9][0-9][0-9]-*.md` (lines 2255–2257):**
   Works because of the `cd "$REPO_ROOT"` at line 37. After extraction the runner must be parameterized (see Pattern 2 above). [VERIFIED: lines 2255-2257 confirmed via direct read]

4. **`test_preflight_verify_paths` uses `"$REPO_ROOT/migrations"` (line 1795):**
   Works in current context because REPO_ROOT is set globally. Must be parameterized for the shared lib. [VERIFIED: line 1795 confirmed]

**No SHARED function calls any WORKFLOW function.** Confirmed by reading all SHARED function bodies — they only call each other (e.g., `assert_check` calls `run_check`) or core shell builtins. The call graph is clean in that direction.

---

### CRQ 3: Shared Global State

These shell-level globals are read/written by SHARED functions and must be owned by the shared lib:

| Variable | Initialized At | Type | SHARED Functions That Write It | Notes |
|----------|---------------|------|-------------------------------|-------|
| `PASS` | L39 (`PASS=0`) | counter | `assert_check` (+1 on pass) | Incremented by L162 |
| `FAIL` | L40 (`FAIL=0`) | counter | `assert_check` (+1 on fail), `test_preflight_verify_paths` (in strict mode) | Incremented by L166 |
| `SKIP` | L41 (`SKIP=0`) | counter | NOT written by SHARED functions | WORKFLOW functions increment SKIP directly |
| `RAN_AUDIT` | L42 (`RAN_AUDIT=0`) | flag | `test_preflight_verify_paths` sets it to 1 | Used by exit code logic at L2574 |
| `STRICT_PREFLIGHT` | L46 (`STRICT_PREFLIGHT="${STRICT_PREFLIGHT:-0}"`) | env/flag | `test_preflight_verify_paths` reads it | Consumer repo controls via env var or `--strict-preflight` flag |
| `FILTER` | L47 (`FILTER=""`) | string | Not written by SHARED functions | Dispatcher reads it |
| `RED`, `GREEN`, `YELLOW`, `RESET` | L31–34 | color strings | `assert_check` uses all four | Set at preamble; tty-conditional |
| `_runtests_cleanup_fired` | L76 | idempotency flag | `_runtests_do_cleanup` reads/writes | Required for trap idempotency |
| `REPO_ROOT` | L36 (`git rev-parse --show-toplevel`) | path | `test_preflight_verify_paths` reads it | WORKFLOW-side global; SHARED lib must not assume it exists |

**Shell modes:** `set -uo pipefail` at L27. The `set -u` is relevant for submodule sourcing: any variable referenced in sourced lib files that is not yet initialized will trip `set -u`. Sourcing order matters — `helpers.sh` must be sourced FIRST (it initializes `PASS`, `FAIL`, etc.) before any lib that reads those counters.

**Trap state:** Lines 83–85 set three traps (EXIT, INT, TERM). These traps reference `_runtests_do_cleanup`. After sourcing `helpers.sh`, the trap setup must still run in the consumer script (traps are not inherited across source). The lib can define the function; the consumer script sets the trap:

```bash
# In helpers.sh: define _runtests_do_cleanup
# In consumer run-tests.sh: set the traps (after sourcing helpers.sh)
trap '_runtests_do_cleanup'        EXIT
trap '_runtests_do_cleanup; exit 130' INT
trap '_runtests_do_cleanup; exit 143' TERM
```

[VERIFIED: lines 83-85 confirm trap setup; line 76 confirms `_runtests_cleanup_fired=0` initialization]

---

### CRQ 4: Sourcing Mechanism

**Concrete bash pattern for claude-workflow consumer:**

```bash
#!/usr/bin/env bash
set -uo pipefail

# ─── Resolve shared lib ─────────────────────────────────────────────────────
# BASH_SOURCE[0] is this script's path; dirname gives migrations/; go up one
# level to get the repo root, then descend into vendor/agenticapps-shared.
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_LIB="$_SCRIPT_DIR/../vendor/agenticapps-shared/migrations/lib"

if [ ! -d "$_SHARED_LIB" ]; then
  echo "ERROR: shared lib not found at $_SHARED_LIB" >&2
  echo "Run: git submodule update --init --recursive" >&2
  exit 1
fi

source "$_SHARED_LIB/helpers.sh"
source "$_SHARED_LIB/fixture-runner.sh"
source "$_SHARED_LIB/preflight.sh"
source "$_SHARED_LIB/drift-test.sh"
```

**Why `${BASH_SOURCE[0]}` not `$0`:** `$0` is the name the script was invoked by (may be a relative path or alias). `${BASH_SOURCE[0]}` is the path to the file containing the code currently executing, even when the script is `source`d itself. For a script that is always executed (not sourced), both work, but `BASH_SOURCE[0]` is safer and conventional for lib resolution.

**Submodule path resolution from a fresh clone:**
```bash
git clone https://github.com/agenticapps-eu/claude-workflow my-project
cd my-project
git submodule update --init --recursive
# Now vendor/agenticapps-shared/ exists and migrations/lib/*.sh are present
# migrations/run-tests.sh can source them via the pattern above
```

**agenticapps-shared standalone test (`tests/run-tests.sh`):**
```bash
#!/usr/bin/env bash
set -uo pipefail
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_LIB="$_SCRIPT_DIR/../migrations/lib"
source "$_SHARED_LIB/helpers.sh"
source "$_SHARED_LIB/fixture-runner.sh"
source "$_SHARED_LIB/preflight.sh"
source "$_SHARED_LIB/drift-test.sh"
# Then define agenticapps-shared's own (minimal) test suite
# testing the lib functions themselves, not migration content
```

[ASSUMED: `${BASH_SOURCE[0]}` behavior in sourced-script context — standard bash behavior, confirmed in training knowledge; not verified against a live fresh-clone scenario]

---

### CRQ 5: Drift Test Mechanism vs Policy Split (D-28d)

**Current code (lines 2247–2269):**
```bash
test_skill_md_version_matches_latest_migration_to_version() {
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
```

How it reads the data:
- `skill/SKILL.md`: relative path from cwd (which is `REPO_ROOT` after line 37's `cd`)
- `migrations/[0-9][0-9][0-9][0-9]-*.md`: glob relative to cwd
- Both use `grep ^version:` / `grep ^to_version:` + `awk '{print $2}'`

**Proposed SHARED runner signature (`lib/drift-test.sh`):**

```bash
# run_drift_test SKILL_MD_PATH MIGRATIONS_DIR
# Compares SKILL_MD_PATH's `version:` field against the `to_version:` field
# of the highest-numbered *.md file in MIGRATIONS_DIR.
# Outputs a human-readable result line.
# Returns: 0 if versions match, 1 if mismatch or files missing.
# Does NOT increment PASS/FAIL counters — caller owns that (policy).
run_drift_test() {
  local skill_md="$1" migrations_dir="$2"
  local skill_version latest_migration_file migration_to_version migration_num

  if [ ! -f "$skill_md" ]; then
    echo "  run_drift_test: SKILL.md not found: $skill_md" >&2
    return 1
  fi

  skill_version=$(grep ^version: "$skill_md" | awk '{print $2}')
  latest_migration_file=$(ls "${migrations_dir}"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sort | tail -1)

  if [ -z "$latest_migration_file" ]; then
    echo "  run_drift_test: no migration files found in $migrations_dir" >&2
    return 1
  fi

  migration_to_version=$(grep ^to_version: "$latest_migration_file" | awk '{print $2}')
  migration_num=$(basename "$latest_migration_file" | cut -c1-4)

  if [ "$skill_version" = "$migration_to_version" ]; then
    return 0
  else
    echo "  drift mismatch: SKILL.md at v${skill_version} but migration ${migration_num} declares to_version: ${migration_to_version}" >&2
    return 1
  fi
}
```

**What WORKFLOW side keeps** (the policy wrapper in `run-tests.sh`):

```bash
test_skill_md_version_matches_latest_migration_to_version() {
  if run_drift_test "$REPO_ROOT/skill/SKILL.md" "$REPO_ROOT/migrations"; then
    echo "  ${GREEN}PASS${RESET}: test-skill-md-version-matches-latest-migration-to-version"
    PASS=$((PASS+1))
  else
    echo "  ${RED}FAIL${RESET}: SKILL.md version does not match latest migration to_version"
    FAIL=$((FAIL+1))
  fi
}
```

The policy ("PASS is required for shipping") is enforced by putting this test in the WORKFLOW dispatcher and having it increment the global FAIL counter on mismatch.

---

### CRQ 6: Whole-File Move Candidates

Files that can be moved WHOLE (history-preservable via `git filter-repo`):

| File | Classification | History Move | Rationale |
|------|---------------|--------------|-----------|
| `migrations/test-fixtures/init-*` | **WORKFLOW — stays in claude-workflow** | None | init fixtures are observability-specific; they test adding obs to a project. Each contains a `before/` with obs-related project structure. |
| `migrations/test-fixtures/0019/` | **WORKFLOW — moves to SPLIT-02** | Deferred | Observability migration; CONTEXT.md explicitly lists as SPLIT-02 scope |
| `migrations/test-fixtures/0021/` | **WORKFLOW — moves to SPLIT-02** | Deferred | Observability migration; CONTEXT.md explicitly lists as SPLIT-02 scope |
| `migrations/test-fixtures/0001/` through `0018/` (excluding 0019) | **WORKFLOW — stays in claude-workflow** | None | These are workflow-specific migration test fixtures; not shared |
| `templates/.claude/scripts/migrate-0017-axiom-destination.sh` | **WORKFLOW — moves to SPLIT-02** | Deferred | Observability-specific apply engine |
| `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh` | **WORKFLOW — moves to SPLIT-02** | Deferred | Observability-specific apply engine |
| `templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh` | **WORKFLOW — moves to SPLIT-02** | Deferred | Observability-specific apply engine |
| `migrations/test-fixtures/_example/` (planned) | **SHARED — goes to agenticapps-shared** | Created fresh | Does not exist in claude-workflow yet; will be created directly in agenticapps-shared skeleton |

**Key finding: there are NO framework-generic `migrate-*.sh` scripts that qualify for SPLIT-01 whole-file moves.** All three existing `migrate-*.sh` scripts are observability-specific and belong in SPLIT-02. SPLIT-01 documents in ADR-0035 noted possible "framework-generic parts" but examination confirms all three are obs-specific engines. [VERIFIED: direct listing of `templates/.claude/scripts/migrate-*.sh` — only 0017, 0019, 0021 exist]

**The `_example` fixture:** per CONTEXT.md §Specific Ideas, this will be created fresh in `agenticapps-shared/migrations/test-fixtures/_example/` (setup.sh, verify.sh, expected-exit). No filter-repo needed.

**filter-repo scope for SPLIT-01:** Only needed if the planner decides any file moves WHOLE. Given the analysis above, SPLIT-01 has NO whole-file moves that use filter-repo. The `migrations/lib/*.sh` files are NEW files carved from `run-tests.sh`. The CHANGELOG provenance-by-note approach (D-28b) covers this.

---

### CRQ 7: Test Suite Shape and Count

**Actual current state (verified by running the suite):**
- `PASS: 186`
- `FAIL: 4`
- Total attempted: 190 (PASS + FAIL)
- SKIP: 0 in normal run

**Breakdown by migration:**

| Migration | PASS | Status | Boundary |
|-----------|------|--------|---------|
| 0001 | 20 | GREEN | WORKFLOW |
| 0005 | 16 | GREEN | WORKFLOW |
| 0006 | 15 | GREEN | WORKFLOW |
| 0007 | 18 | GREEN | WORKFLOW |
| 0009 | 38 | GREEN | WORKFLOW |
| 0010 | 16 | GREEN | WORKFLOW |
| 0011 | 6 | GREEN | WORKFLOW |
| 0012 | 5 | GREEN | WORKFLOW |
| 0013 | 5 | GREEN | WORKFLOW |
| 0014 | 7 | GREEN | WORKFLOW |
| 0015 | 4 | GREEN | WORKFLOW |
| 0016 | 2 | GREEN | WORKFLOW |
| 0017 | 7 PASS / **4 FAIL** | RED (pre-existing) | WORKFLOW |
| 0018 | 3 | GREEN | WORKFLOW |
| 0019 | 13 | GREEN | WORKFLOW |
| 0021 | 4 | GREEN | WORKFLOW |
| drift test | 1 | GREEN | SHARED (mechanism) |
| sigterm test | 1 | GREEN | WORKFLOW |
| destinations | 5 | GREEN | WORKFLOW |
| preflight audit | 21 PASS / 1 FAIL (informational only — NOT in global counters) | informational | SHARED |

**The 4 FAIL pre-existing:** All in `test_migration_0017` — fixtures `02-fresh-apply-fxsa-shape`, `06-no-claudemd`, `10-fresh-apply-worker-env`, `11-prettier-style-clean-applies`. These are FIX-0017-ENGINE scope (see `FIX-0017-ENGINE.md`). SPLIT-01 must preserve FAIL=4 — it must not accidentally fix or worsen them.

**The 1 preflight audit FAIL:** Migration 0008's `curl` verify command (`curl -H 'Authorization: Bearer $TOKEN' http://127.0.0.1:5193/api/coverage`) fails because the local service is not running. This is informational and does NOT contribute to the global FAIL counter (it's inside `test_preflight_verify_paths` which handles it separately from PASS/FAIL).

**GREEN/RED contract for the planner:**
```
PRE-EXTRACTION baseline:  PASS=186 FAIL=4
POST-EXTRACTION required: PASS=186 FAIL=4 (identical)
```
If PASS drops or FAIL increases, something broke. If FAIL decreases (0017 accidentally fixed), that's acceptable only if it was intentional.

**Tests OUT of scope for SPLIT-01 (SPLIT-02 territory):**
- `test_meta_destinations_consistency()` — checks `add-observability/templates` (WORKFLOW, stays for now; moves in SPLIT-02)
- `test_sigterm_mid_apply_preserves_state()` — tests migrate-0019 engine (WORKFLOW, stays; engine moves in SPLIT-02)
- `test_migration_0019()` — 13 tests for obs migration (WORKFLOW, stays; moves in SPLIT-02)
- `test_migration_0021()` — 4 tests for obs migration (WORKFLOW, stays; moves in SPLIT-02)
- preflight audit entry for 0008 curl check — informational only, stays

---

### CRQ 8: Consumer Wiring Touchpoints

**CI workflows:** None. [VERIFIED: `ls .github/workflows/` returned "NO_CI_WORKFLOWS"] No CI workflow files exist in claude-workflow. No `--recurse-submodules` CI changes needed.

**`install.sh`:** Currently symlinks skill subdirectories to `~/.claude/skills/`. Contains NO submodule handling. [VERIFIED: `grep -n "submodule\|vendor\|--recurse" install.sh` returned "NO_SUBMODULE_IN_INSTALL"] The install.sh must be updated to init the submodule for fresh clones:

```bash
# Add after the SCAFFOLDER + SKILLS_DIR setup, before the LINKS array:
# Init submodule if vendor/ is empty (fresh clone scenario)
if [ -f "$SCAFFOLDER/.gitmodules" ] && [ ! -f "$SCAFFOLDER/vendor/agenticapps-shared/VERSION" ]; then
  echo "Initialising git submodule vendor/agenticapps-shared..."
  git -C "$SCAFFOLDER" submodule update --init --recursive
fi
```

**References to `migrations/run-tests.sh` across the project:**

All references found by grep — classified by action needed:

| File | Line | Reference | Action |
|------|------|-----------|--------|
| `session-handoff.md` | L41 | Documentation mention | No code change needed |
| `FIX-0017-ENGINE.md` | L98 | `migrations/run-tests.sh 0017` invocation | Path stays the same — no change |
| `CHANGELOG.md` | Multiple | Historical references | No change needed |
| `SPLIT-01-agenticapps-shared.md` | L29, L32, etc. | Design doc | No code change needed |

**Key conclusion:** `migrations/run-tests.sh` keeps its path unchanged (D-28e decision: source-and-keep, not thin-shim). Developers continue to run `bash migrations/run-tests.sh`. NO external path reference requires updating after the carve.

**vendor/ directory:** Does not exist yet. [VERIFIED: `ls vendor/` returned "NO_VENDOR_DIR"] The submodule add command creates it:
```bash
git submodule add https://github.com/agenticapps-eu/agenticapps-shared vendor/agenticapps-shared
```

**`.gitmodules`:** Does not exist yet. [VERIFIED] Created automatically by `git submodule add`.

**`agenticapps-shared` current state:** Local repo exists at `~/Sourcecode/agenticapps/agenticapps-shared/`. [VERIFIED: directory listing confirmed] Tag `v1.0.0-pre.0` exists. `migrations/lib/` directory exists but contains only `.gitkeep`. Ready for the carved lib files.

---

### CRQ 9: Risk/Failure Modes

**Risk 1 — `set -u` tripping on unset variables after sourcing**

`set -uo pipefail` is active when the lib files are sourced. Any variable referenced in lib files that is not set at source time will cause an immediate fatal exit.

Mitigation: `helpers.sh` must initialize ALL variables it defines (`PASS=0`, `FAIL=0`, `SKIP=0`, `RAN_AUDIT=0`, `_runtests_cleanup_fired=0`) at the TOP of the file. Color vars (`RED`, `GREEN`, etc.) must also be defined (or empty-string defaulted) before any function that uses them is called.

Detection: Add a `--dry-run` smoke test that sources each lib file in isolation: `bash -c 'set -u; source lib/helpers.sh; echo OK'`

**Risk 2 — Trap inheritance across sourcing**

Traps set in the consumer script's session are NOT inherited by subshells spawned by sourced lib functions. But `_runtests_do_cleanup` must be callable from the traps set in the consumer. Since the function is defined in `helpers.sh` and the consumer sets the traps AFTER sourcing, this works correctly IF the trap setup code moves from the lib (where it would try to fire before all other libs are sourced) to the consumer script.

Correct order:
```bash
source helpers.sh        # defines _runtests_do_cleanup; does NOT set traps
# then set traps in consumer:
trap '_runtests_do_cleanup'         EXIT
trap '_runtests_do_cleanup; exit 130' INT
trap '_runtests_do_cleanup; exit 143' TERM
```

Do NOT include `trap` calls in `helpers.sh` — the lib doesn't know if it's being sourced in a context where these traps are appropriate.

**Risk 3 — Relative-path breakage in drift test and preflight**

The current drift test uses `skill/SKILL.md` (relative to cwd = `REPO_ROOT`). After parameterization, it uses `"$REPO_ROOT/skill/SKILL.md"`. If the consumer forgets to pass the absolute path and passes a relative one while cwd has changed (e.g., inside a subshell), the function silently reads from the wrong location.

Mitigation: The `run_drift_test` function should validate that `$skill_md` exists (see proposed signature in CRQ 5). Add `[ -f "$skill_md" ] || { echo "ERROR: ..."; return 1; }` at function entry.

**Risk 4 — Suite count drifting post-extraction**

If any sourced lib file contains `PASS=$((PASS+1))` calls at the file level (not inside a function), they execute at source time and inflate the counter before any test runs.

Mitigation: Ensure ALL counter-incrementing code in lib files is inside function bodies. Never at file level.

**Risk 5 — set -e leaking from lib into WORKFLOW test functions**

The current run_0005_fixture comment at line ~853 explicitly notes: "NOTE: parent harness uses `set -uo pipefail` (not `set -e`), so we do NOT toggle `-e` here — doing so would leak `set -e` into later test_migration_* functions and break them on the first non-zero exit."

If any lib file calls `set -e`, this will break any WORKFLOW test that legitimately expects a non-zero exit (like `run_check` which is designed to capture non-zero exits). Lib files must NEVER call `set -e`.

**Risk 6 — Submodule not initialized in a dev's clone**

A developer who ran `git clone` without `--recurse-submodules` will have `vendor/agenticapps-shared/` as an empty directory. The `migrations/run-tests.sh` sourcing will fail with "ERROR: shared lib not found."

Mitigation: The guard block (see CRQ 4 sourcing pattern) prints a clear error with the fix command. This is better than a cryptic `source: file not found` error.

**Risk 7 — Circular sourcing**

If `helpers.sh` sources `fixture-runner.sh` and `fixture-runner.sh` sources `helpers.sh`, the second source call re-initializes `PASS=0` etc. mid-run.

Mitigation: Lib files must NOT source each other. The consumer (claude-workflow `run-tests.sh`) sources all four libs in the correct order. Use a `_HELPERS_LOADED` guard if needed:
```bash
# In helpers.sh top:
[ -n "${_AGENTICAPPS_HELPERS_LOADED:-}" ] && return 0
_AGENTICAPPS_HELPERS_LOADED=1
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Submodule path resolution | Custom path-finding logic | `${BASH_SOURCE[0]}` + `cd … && pwd` | Portable, handles symlinks, handles sourced context |
| Submodule initialization | Custom init scripts | `git submodule update --init --recursive` | Git manages this correctly |
| History preservation for carved code | filter-repo gymnastics for partial-file extraction | Provenance-by-note (D-28b) | filter-repo is whole-file; partial-function extraction is not a git operation |
| Drift test YAML parsing | Full YAML parser for migration frontmatter | `grep ^version:` + `awk '{print $2}'` | The comment at line 2250 ("intentionally minimal grep + awk parser") is a documented decision (D-04); the frontmatter shape is fixed |

---

## Runtime State Inventory

> Phase is a refactor/extraction, not a rename. Runtime state section applies in a limited way.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — run-tests.sh is a script, not a data store | None |
| Live service config | None — no external service registers this script | None |
| OS-registered state | None — no launchd/systemd entries for run-tests.sh | None |
| Secrets/env vars | `STRICT_PREFLIGHT` env var read by `test_preflight_verify_paths` | Code change only — the env var name stays the same; behavior unchanged |
| Build artifacts | `vendor/agenticapps-shared/` submodule dir — will be new | Created by `git submodule add` |

Nothing found in "stored data," "live service config," or "OS-registered state." [VERIFIED: no launchd/systemd entries searched; no CI workflows found]

---

## Common Pitfalls

### Pitfall 1: Moving color var initialization into lib but forgetting tty check

**What goes wrong:** `helpers.sh` initializes `RED`, `GREEN`, etc. without the tty check. When run in CI (non-tty stdout), color codes appear as literal escape sequences in output.

**Why it happens:** The current tty check is at lines 30–34 of `run-tests.sh` — it's the consumer's responsibility. Moving the vars to helpers.sh without the check breaks CI output.

**How to avoid:** Move the ENTIRE block (tty check + conditional assignment) into `helpers.sh`:
```bash
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi
```

**Warning signs:** CI output shows `[31m` literal strings.

### Pitfall 2: setup_fixture's $3 argument (version) is positional

**What goes wrong:** `setup_fixture "$before_dir" "$before_ref" "1.2.0"` — the version is the 3rd positional arg. After parameterizing the skill name as arg 4, any existing callers with `"$3"` must still work.

**Why it happens:** The function signature change must be backward-compatible; adding `${4:-agentic-apps-workflow}` default ensures existing callers with 3 args still work.

**How to avoid:** Use `local skill_name="${4:-agentic-apps-workflow}"` NOT `local skill_name="$4"` (the latter would fail with `set -u` when called with only 3 args).

**Warning signs:** `test_migration_0001()` failing with "parameter not set" under `set -u`.

### Pitfall 3: Sourcing order and counter reset

**What goes wrong:** `helpers.sh` is sourced after some test functions have already run (impossible in the sequential model, but worth noting). Counter reset.

**Why it happens:** Developers might reorganize the source block. The `_AGENTICAPPS_HELPERS_LOADED` guard prevents double-sourcing.

**How to avoid:** Document in `helpers.sh`'s header that it must be sourced once, before any test functions run. Add the idempotency guard.

**Warning signs:** PASS count starts at 0 mid-test run (only visible if guard is absent and helpers is sourced twice).

### Pitfall 4: Dispatcher block is SHARED in shape but WORKFLOW in calls

**What goes wrong:** The planner moves the ENTIRE dispatcher block to agenticapps-shared, including the `test_migration_0001` calls. These function calls reference WORKFLOW-only functions that won't exist in the shared repo.

**Why it happens:** The `# SHARED` annotation says "the if/FILTER PATTERN is repo-agnostic framework machinery." The function calls themselves are not shared.

**How to avoid:** The SHARED element is the PATTERN (the `if [ -z "$FILTER" ] || [ "$FILTER" = "key" ]; then fn; fi` idiom). The dispatcher STAYS in claude-workflow's `run-tests.sh`. The agenticapps-shared `tests/run-tests.sh` implements its OWN dispatcher calling its OWN test functions (which test the shared lib itself).

**Warning signs:** `test_migration_0001: command not found` errors when running agenticapps-shared's test suite.

---

## Code Examples

### Sourcing pattern (verified against current run-tests.sh structure)

```bash
# In claude-workflow/migrations/run-tests.sh — AFTER extraction
#!/usr/bin/env bash
set -uo pipefail

# Resolve shared lib relative to this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_LIB="$_SCRIPT_DIR/../vendor/agenticapps-shared/migrations/lib"
if [ ! -d "$_SHARED_LIB" ]; then
  echo "ERROR: agenticapps-shared submodule not initialized." >&2
  echo "Fix: git submodule update --init --recursive" >&2
  exit 1
fi
source "$_SHARED_LIB/helpers.sh"
source "$_SHARED_LIB/fixture-runner.sh"
source "$_SHARED_LIB/preflight.sh"
source "$_SHARED_LIB/drift-test.sh"

# Set traps AFTER sourcing (helpers.sh defines _runtests_do_cleanup)
trap '_runtests_do_cleanup'         EXIT
trap '_runtests_do_cleanup; exit 130' INT
trap '_runtests_do_cleanup; exit 143' TERM

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Flag + filter parsing [STAYS — not moved to lib]
STRICT_PREFLIGHT="${STRICT_PREFLIGHT:-0}"
FILTER=""
while [ $# -gt 0 ]; do
  # ... [same as current lines 48-69]
done

# [All WORKFLOW test functions go here, unchanged]
test_migration_0001() { ... }
...
# [Dispatcher stays here, calling WORKFLOW functions + shared wrappers]
```

### helpers.sh skeleton

```bash
#!/usr/bin/env bash
# agenticapps-shared: common harness helpers
# Source: extracted from claude-workflow migrations/run-tests.sh
# Provenance: claude-workflow commit [SHA at extraction time]

# Idempotency guard (safe to source multiple times)
[ -n "${_AGENTICAPPS_HELPERS_LOADED:-}" ] && return 0
_AGENTICAPPS_HELPERS_LOADED=1

# Colors (tty-conditional)
if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

# Global counters (initialized once at source time)
PASS=0; FAIL=0; SKIP=0; RAN_AUDIT=0

# Idempotency state for cleanup trap
_runtests_cleanup_fired=0

# [_runtests_do_cleanup() function body from lines 77-85]
_runtests_do_cleanup() {
  [ "$_runtests_cleanup_fired" -eq 1 ] && return 0
  _runtests_cleanup_fired=1
  :
}

# [run_check() from lines 139-143]
run_check() {
  local fixture="$1" check="$2"
  ( cd "$fixture" && eval "$check" >/dev/null 2>&1 )
  return $?
}

# [assert_check() from lines 151-170]
assert_check() { ... }
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| All test functions in one file | SHARED/WORKFLOW annotated; lib extraction planned | Phase 27 / ADR-0035 | Extraction is now mechanical |
| `git filter-branch` for history moves | `git filter-repo` | Several years ago | filter-repo is 10-100x faster; filter-branch deprecated |
| Submodule clone without `--recurse` | `git clone --recurse-submodules` | N/A (convention) | Without this, vendor/ dir is empty |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `${BASH_SOURCE[0]}` resolves correctly in all invocation contexts for claude-workflow | CRQ 4 (Sourcing) | Path resolution fails; lib not found. Mitigation: guard block with clear error message. |
| A2 | No CI workflows exist (only checked `.github/workflows/`) | CRQ 8 | CI might be in another location (e.g. `.circleci/`). Impact: low — no evidence found in any doc. |
| A3 | `agenticapps-shared` remote URL is `https://github.com/agenticapps-eu/agenticapps-shared` | CRQ 8 | Wrong URL in `git submodule add` command. Verify with `gh repo view agenticapps-eu/agenticapps-shared` before executing. |

---

## Open Questions

1. **`setup_fixture` parameterization scope for SPLIT-01**
   - What we know: `setup_fixture` hardcodes `agentic-apps-workflow` skill name and `templates/` git paths.
   - What's unclear: Should SPLIT-01 fully parameterize it (making it truly generic for obs consumers) or just move it as-is with a note that obs will override it?
   - Recommendation: Parameterize the skill name (4th arg with default) in SPLIT-01. Leave the git-ref paths as a known limitation documented in `agenticapps-shared/migrations/lib/fixture-runner.sh` header. Full parameterization of template paths is SPLIT-02 work.

2. **Counter ownership — reset vs initialize**
   - What we know: `helpers.sh` will initialize `PASS=0 FAIL=0 SKIP=0 RAN_AUDIT=0`. If a consumer wants to run the suite in two sections, it needs to reset counters.
   - What's unclear: Should helpers.sh expose a `reset_counters()` function?
   - Recommendation: Yes, add a `reset_counters()` function in `helpers.sh` so consumers can reset for isolated runs. Not needed for SPLIT-01's single use case but good API design.

3. **agenticapps-shared tests/run-tests.sh content**
   - What we know: It should exercise the shared lib in isolation.
   - What's unclear: What specific tests should it contain? The lib functions are framework machinery, not migration content — testing them means writing synthetic fixtures.
   - Recommendation: Minimal smoke tests: (1) source all four lib files without error, (2) call `run_check` with a trivial check (3) call `assert_check` and verify PASS counter increments, (4) call `run_drift_test` with synthetic test data. This is enough to prove the lib is loadable and functional without claude-workflow context.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| git | `extract_to()`, submodule wiring | Yes | system git | — |
| git-filter-repo | Whole-file moves (if any) | Yes (brew installed per STATE.md) | current | — |
| bash | All lib files | Yes | 3.2 (macOS) | — |
| python3 + pyyaml | `test_preflight_verify_paths` | Yes | system python3 | Preflight skips gracefully if absent |
| GitHub access (agenticapps-eu org member) | `git submodule add` | Assumed yes (Phase A done) | — | — |

[VERIFIED: git-filter-repo installed per STATE.md "git-filter-repo installed" note; actual binary availability not re-verified in this session — tagged as assumed]

---

## Project Constraints (from CLAUDE.md)

The project CLAUDE.md (`/Users/donald/Sourcecode/agenticapps/claude-workflow/CLAUDE.md`) requires:

1. **GitNexus impact analysis before editing any symbol.** Before modifying `_runtests_do_cleanup`, `extract_to`, `setup_fixture`, `run_check`, `assert_check`, or `test_preflight_verify_paths`, run `gitnexus_impact({target: "functionName", direction: "upstream"})` and report blast radius.

2. **`gitnexus_detect_changes()` before committing.** Run after all edits to verify only expected symbols and execution flows are affected.

3. **`gitnexus_rename` for symbol renames.** If any function is renamed during extraction (e.g., `test_preflight_verify_paths` → `run_preflight_verify_paths`), use `gitnexus_rename` not find-and-replace.

4. **Feature branches + PRs to main.** All SPLIT-01 work must be on a feature branch. Never commit directly to main.

> Note: `migrations/run-tests.sh` is bash, not a language GitNexus indexes deeply (it's primarily designed for JavaScript/TypeScript/Go). The impact analysis will be limited for bash functions. The planner should note this and plan for manual review of callers instead.

---

## Sources

### Primary (HIGH confidence)
- `migrations/run-tests.sh` — read in full, all 2579 lines. Line numbers cited throughout are VERIFIED.
- `.planning/phases/28-split-01-agenticapps-shared/28-CONTEXT.md` — decisions D-28a through D-28f
- `docs/decisions/0035-shared-extraction-boundaries.md` — SHARED/WORKFLOW boundary + MECHANISM/POLICY
- `SPLIT-01-agenticapps-shared.md` — execution plan with Phase A done / Phase C SUPERSEDED note
- `SPLIT-00-PREREQUISITES.md` — gate conditions, end-state repo map
- `.planning/STATE.md` — current milestone state, Phase B/C reconciliation finding
- Live test run: `bash migrations/run-tests.sh` → PASS=186 FAIL=4 [VERIFIED 2026-06-02]

### Secondary (MEDIUM confidence)
- `install.sh` — full file read; no submodule handling confirmed
- `agenticapps-shared/` local repo — directory listing + git log confirmed Phase A state
- `migrations/test-fixtures/` — directory listing for fixture inventory

### Tertiary (LOW confidence — training knowledge)
- `${BASH_SOURCE[0]}` behavior in sourced scripts (A1)
- `git submodule` init/update behavior on fresh clones (A3)

---

## Metadata

**Confidence breakdown:**
- Function boundary map: HIGH — every annotation read directly from the file
- Call-graph coupling: HIGH — body-level read of all SHARED functions
- Global state: HIGH — verified by file read
- Sourcing mechanism: MEDIUM — BASH_SOURCE[0] pattern is standard but not live-tested in this session
- Test counts: HIGH — actual live run of `bash migrations/run-tests.sh`
- Whole-file move candidates: HIGH — confirmed by `ls` of migrate-*.sh

**Research date:** 2026-06-02
**Valid until:** 2026-07-02 (the file won't change during the split; this research is specific to the 1.21.0 baseline)

---

## RESEARCH COMPLETE

**Phase:** 28 — SPLIT-01 agenticapps-shared extraction
**Confidence:** HIGH

### Key Findings

1. **Boundary map is complete and annotated.** 9 SHARED / 20 WORKFLOW top-level functions. Zero annotation gaps. The planner can lift the table in CRQ 1 directly into PLAN.md tasks.

2. **`setup_fixture` has a coupling concern that requires a fix before it lands in the shared lib.** The function is annotated SHARED but hardcodes `agentic-apps-workflow` skill name (lines 119–123). Fix: parameterize with `${4:-agentic-apps-workflow}` default. This is a 3-line change.

3. **Actual test baseline is PASS=186 FAIL=4 (not "190+ tests all GREEN").** The 4 FAIL are pre-existing in `test_migration_0017` (FIX-0017-ENGINE scope). SPLIT-01 must preserve this exact baseline, not fix it.

4. **No CI workflows, no vendor/ dir, no existing .gitmodules.** The submodule wiring is a fresh addition. `install.sh` needs a submodule init block.

5. **No whole-file moves qualify for filter-repo in SPLIT-01.** All three `migrate-*.sh` scripts are observability-specific (SPLIT-02). The `_example` fixture is created fresh in agenticapps-shared. D-28b provenance-by-note approach covers all SPLIT-01 carved code.

6. **Drift test parameterization is straightforward.** Current code uses relative paths that work because of `cd "$REPO_ROOT"`. Proposed `run_drift_test(skill_md, migrations_dir)` signature is a clean extraction.

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Function boundary map (CRQ 1) | HIGH | Read all 2579 lines; grep-verified annotation counts |
| Call-graph coupling (CRQ 2) | HIGH | Body-level read of all SHARED functions |
| Global state (CRQ 3) | HIGH | Line numbers verified in file |
| Sourcing mechanism (CRQ 4) | MEDIUM | Standard pattern, not live-tested in fresh-clone scenario |
| Drift test split (CRQ 5) | HIGH | Current code fully read; proposed split is mechanical |
| Whole-file moves (CRQ 6) | HIGH | Verified by listing migrate-*.sh files |
| Test counts (CRQ 7) | HIGH | Live run of test suite |
| Consumer wiring (CRQ 8) | HIGH | install.sh read + grep for references |
| Risk analysis (CRQ 9) | MEDIUM | Analysis based on code reading; some risks require runtime validation |

### Open Questions (that may need user input before execution)

- None are blockers. The `setup_fixture` parameterization decision is noted but the recommended fix (4th-arg default) is safe and backward-compatible. The planner can proceed without user input.

### Ready for Planning

Research complete. Planner can create PLAN.md using the function boundary table (CRQ 1) as the task decomposition, the lib decomposition structure, and the sourcing patterns directly as task actions.
