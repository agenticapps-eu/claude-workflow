# SPLIT-01 — Extract shared infrastructure to `agenticapps-shared`

> **PREREQUISITE:** `SPLIT-00-PREREQUISITES.md` checklist fully GREEN.
> Do not start this file's work until claude-workflow 1.21.0 is stable on main
> for ≥7 days AND all three factiv downstream projects are upgraded to 1.21.0
> AND stable for ≥7 days. Bail and read SPLIT-00 first if any gate is open.

## Mission

Carve the **shared infrastructure** out of `claude-workflow` into a new repo
`agenticapps-eu/agenticapps-shared`. This repo holds the migration runner,
the drift-test machinery, and any common helpers that both `claude-workflow`
and the future `agenticapps-observability` will need. It is NOT an end-user
skill — it ships infrastructure, not user-invocable commands.

## Why this comes first (not observability)

`agenticapps-observability` will need the migration runner to apply its own
migrations (0019, 0021, future). If we extract observability first, it has
to either (a) duplicate the runner, (b) reach into a not-yet-extracted
claude-workflow path, or (c) wait. Option (c) is just SPLIT-01 in a different
order. Option (a) is the worst outcome — duplicated runner means drift
between two copies. So: **shared first, then observability**.

## What lives in `agenticapps-shared`

### Migration framework (canonical paths in claude-workflow shown for reference)

- `migrations/run-tests.sh` — the test dispatcher (currently runs 190 tests
  across all migrations + harness)
- The drift test: `test-skill-md-version-matches-latest-migration-to-version`
  (currently inline in `run-tests.sh`)
- The fixture harness pattern (the `test-fixtures/NNNN/MM-name/{setup.sh, verify.sh, expected-exit}` convention)
- The migration apply machinery — currently distributed across
  `templates/.claude/scripts/migrate-*.sh` (only the framework-generic parts;
  observability-specific scripts move to `agenticapps-observability`)
- Common helpers any migration script can source (logging, dispatcher,
  pass/fail conventions)

### Shared GSD-tools subset (audit before extracting)

> **CORRECTION (Phase 27, ADR-0035):** The extraction target for Phase C is
> `migrations/run-tests.sh` + migration content, NOT `bin/gsd-tools.cjs`.
>
> `bin/gsd-tools.cjs` **does not exist in this repo**. It is the GSD
> framework, installed independently at `~/.claude/get-shit-done/bin/` — it
> is not part of claude-workflow's codebase and is therefore out of scope for
> the claude-workflow repo split.
>
> The function list below (`phase-plan-index`, `state begin-phase`, `init
> phase-op`, `init execute-phase`, etc.) belongs to the GSD framework. These
> are framework commands, not claude-workflow code.
>
> The correct split target is `migrations/run-tests.sh` (~2500+ lines):
> dispatcher, drift-test mechanism, fixture-runner harness, and per-migration
> test bodies. The SHARED/WORKFLOW boundary for that file is defined in
> **ADR-0035** (`docs/decisions/0035-shared-extraction-boundaries.md`) and
> annotated line-by-line in `migrations/run-tests.sh` with `# SHARED` /
> `# WORKFLOW` markers. Phase C executors: read ADR-0035 and the annotations,
> not the superseded section below.
>
> The section below is preserved for historical reference; treat it as
> superseded by ADR-0035.

~~Some bits of `bin/gsd-tools.cjs` are pure migration-framework helpers; some
are workflow-specific (phase orchestration, state management). Audit each
exported function and split:~~
- ~~**Shared**: `verify schema-drift`, `verify key-links`, anything that
  validates files against frontmatter conventions, anything in the migration
  apply pipeline~~
- ~~**Workflow-specific (stays in claude-workflow)**: `phase-plan-index`,
  `state begin-phase`, `phase complete`, `roadmap update-plan-progress`,
  `init phase-op`, `init execute-phase`, `agent-skills`, `commit` (the GSD
  commit wrapper)~~

~~The boundary test: **if `agenticapps-observability` would need to call it
to apply a migration, it goes in shared. If it's only useful for managing
GSD planning artifacts, it stays in claude-workflow.**~~

### Templates that both repos need

- The skill SKILL.md frontmatter template (with `name`, `version`,
  `implements_spec`, `description` keys)
- The migration NNNN-slug.md content-file template
- The fixture test-fixtures/NNNN/MM-name skeleton

## What does NOT live in `agenticapps-shared` (explicit exclusions)

- GSD discipline: `gsd-execute-phase`, `gsd-discuss-phase`, `gsd-plan-phase`,
  `gsd-roadmap`, all `gsd-*` skills, their agents, their reference docs.
  These stay in claude-workflow.
- The `agentic-apps-workflow` SKILL.md (top-level workflow skill). Stays in
  claude-workflow.
- Anything in `add-observability/` (whole directory). Moves to
  `agenticapps-observability` in SPLIT-02.
- Observability-specific migration scripts: `migrate-0019-sentry-crons-and-healthz.sh`,
  `migrate-0021-with-cron-and-queue-updates.sh`. Move with observability.
- Observability-specific migration fixtures: `migrations/test-fixtures/0019/`,
  `migrations/test-fixtures/0021/`. Move with observability.
- The `templates/` subdirectory (workflow-specific scaffold templates beyond
  observability). Stays in claude-workflow.

## New repo layout (proposed)

```
agenticapps-shared/
├── README.md                       # what this is, who consumes it, how to update
├── CHANGELOG.md                    # starts at 1.0.0
├── VERSION                         # 1.0.0
├── LICENSE
├── package.json                    # if needed for bin/ tooling deps
├── bin/
│   └── shared-tools.cjs            # CLI surface for the shared helpers
│                                   # (extracted from claude-workflow's gsd-tools.cjs)
├── migrations/
│   ├── README.md                   # how the migration framework works
│   ├── run-tests.sh                # dispatcher (the 190-test runner, generalized)
│   ├── lib/
│   │   ├── apply.sh                # apply machinery
│   │   ├── drift-test.sh           # the SKILL.md version vs to_version check
│   │   ├── fixture-runner.sh       # fixture invocation harness
│   │   └── helpers.sh              # logging, pass/fail conventions, shared utils
│   └── test-fixtures/
│       └── _example/               # a skeleton fixture that consumers can copy
│           ├── setup.sh
│           ├── verify.sh
│           └── expected-exit
├── templates/
│   ├── skill-frontmatter.template.md   # the SKILL.md frontmatter pattern
│   └── migration-content.template.md   # the NNNN-slug.md migration template
└── tests/                          # tests for the shared infrastructure ITSELF
    └── run-tests.sh
```

## How claude-workflow + agenticapps-observability consume it

**Recommendation: git submodule.** Reasoning:

| Mechanism | Pro | Con |
|---|---|---|
| **git submodule** ✓ | Zero runtime dependency (no npm registry). Clean version pinning via commit SHA. Easy to verify "this consumer is using this exact shared revision". | Slightly more friction on clone (`--recurse-submodules`). Submodule UX is rough on first contact for new contributors. |
| npm package | Familiar to JS devs. Automatic version-resolution. | Requires npm publish + registry hosting. The shared code is mostly bash + a tiny Node CLI; npm is overweight for that. |
| vendored copy | Simplest, zero tooling | Drift inevitable. The whole point of extraction is preventing duplication. |
| symlinks | Works for local dev | Doesn't survive CI / fresh-clone scenarios |

Decision: **git submodule at `vendor/agenticapps-shared/`** in both consumers.
Each consumer pins to a specific shared commit SHA; CI fetches with
`--recurse-submodules`. Updates to shared happen via PR-then-bump-submodule.

## Execution plan

### Phase A — New repo bootstrap (~1h)

**A.1 — Create the GitHub repo via gh CLI.**

```bash
# Pre-flight: confirm you're authenticated as a member of agenticapps-eu
gh auth status
gh api orgs/agenticapps-eu/members/$(gh api user --jq .login) --silent && \
  echo "OK: member of agenticapps-eu" || echo "ERROR: not a member of agenticapps-eu"

# Create the repo. Private initially — flip to public after SPLIT-01 verifies clean.
# License: claude-workflow has no LICENSE file at the time of SPLIT-00 authoring;
# decide here. MIT shown as a reasonable default for AgenticApps tooling — swap
# for Apache-2.0 / proprietary if your org policy differs.
gh repo create agenticapps-eu/agenticapps-shared \
  --private \
  --description "Shared infrastructure for AgenticApps: migration runner, drift test, framework helpers. Consumed by claude-workflow and agenticapps-observability as a git submodule." \
  --homepage "https://github.com/agenticapps-eu/agenticapps-shared" \
  --license MIT \
  --add-readme \
  --clone

# `--clone` drops the repo into the current directory. Move it to wherever
# you keep AgenticApps repos (typically a sibling of claude-workflow).
mv agenticapps-shared ~/Sourcecode/agenticapps/
cd ~/Sourcecode/agenticapps/agenticapps-shared
```

If `gh repo create` rejects `--add-readme` + `--license` together on your gh
version, drop `--add-readme` and add the README + LICENSE in A.2 below.

**A.2 — Initialise repo layout + metadata.**

```bash
cd ~/Sourcecode/agenticapps/agenticapps-shared

# Version + changelog
echo "1.0.0" > VERSION
cat > CHANGELOG.md <<'EOF'
# Changelog

All notable changes to agenticapps-shared documented here.
This repo follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - YYYY-MM-DD

### Added
- Initial published version: shared migration runner, drift-test machinery,
  framework helpers extracted from claude-workflow per SPLIT-01.
- Consumed by claude-workflow and agenticapps-observability via git submodule
  at `vendor/agenticapps-shared/`.

### Migration provenance
Files in this repo trace their history to claude-workflow phases 21 through
the latest pre-split phase. Full per-file history preserved via git filter-repo;
use `git log --follow <path>` to walk it.
EOF

# Directory skeleton (empty subdirs as placeholders for Phase B/C content)
mkdir -p bin migrations/lib migrations/test-fixtures/_example templates tests
touch bin/.gitkeep migrations/lib/.gitkeep migrations/test-fixtures/_example/.gitkeep templates/.gitkeep tests/.gitkeep

# README skeleton (will fill in during Phase D)
cat > README.md <<'EOF'
# agenticapps-shared

Shared infrastructure for the AgenticApps tooling ecosystem.
Consumed by [claude-workflow](https://github.com/agenticapps-eu/claude-workflow)
and [agenticapps-observability](https://github.com/agenticapps-eu/agenticapps-observability).

## What's here
- Migration runner + dispatcher
- Drift-test machinery (SKILL.md version vs latest migration to_version)
- Fixture harness (the `test-fixtures/NNNN/MM-name/{setup.sh, verify.sh, expected-exit}` pattern)
- Common helpers consumable from any AgenticApps repo's migration framework

## How to consume
Add as a git submodule:

```bash
git submodule add https://github.com/agenticapps-eu/agenticapps-shared vendor/agenticapps-shared
git submodule update --init --recursive
```

Pin to a specific tag/SHA in your consumer's submodule reference.

## Versioning
Semantic versioning. Breaking changes in shared CLI surface or removed
helpers bump major.

EOF

# .gitignore (conservative — extend during Phase C as needed)
cat > .gitignore <<'EOF'
node_modules/
.DS_Store
*.log
.idea/
.vscode/
EOF

# Initial commit
git add -A
git commit -m "chore: initial repo layout per SPLIT-01 Phase A

Empty skeleton for shared infrastructure extraction. Phase B (filter-repo)
populates migrations/ + bin/. Phase C splits bin/gsd-tools.cjs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"

git tag -a v1.0.0-pre.0 -m "Pre-extraction skeleton — Phase B/C populate this"
git push origin main --tags
```

**A.3 — Verify.**

```bash
gh repo view agenticapps-eu/agenticapps-shared --json url,visibility,description
git log --oneline -5
git tag --list
```

Repo is now live and ready for Phase B (history-preserving extraction from
claude-workflow into the empty layout above).

### Phase B — Extract with history preservation (~2-3h)

Use `git filter-repo` (NOT `git filter-branch`; `filter-repo` is the
modern, fast, history-rewriting tool — install via `brew install git-filter-repo`).

1. Clone claude-workflow into a scratch dir: `git clone … claude-workflow-extract`
2. In that scratch clone, run `git filter-repo --path migrations/run-tests.sh
   --path bin/gsd-tools.cjs --path migrations/lib/ --path-rename
   bin/gsd-tools.cjs:bin/shared-tools.cjs` (illustrative — actual command set
   built incrementally; aim for: keep only files that move to shared, preserve
   their git log).
3. After filter-repo, the scratch clone contains ONLY shared-bound files +
   their full history. Push that to `agenticapps-eu/agenticapps-shared` as
   a new orphan branch, then fast-forward `main`.
4. Verify history: every file moved should have its full commit log accessible
   via `git log --follow`.

### Phase C — Split bin/gsd-tools.cjs (~3-4h, the meaty part)

This is where the bulk of the engineering judgment lives.

1. Audit every exported function in `claude-workflow:bin/gsd-tools.cjs`.
2. For each function, classify per the "boundary test" in the "What lives
   here" section above.
3. Create `agenticapps-shared:bin/shared-tools.cjs` with only the
   shared-classified functions. Preserve CLI argument shapes so calling
   conventions are stable.
4. In claude-workflow, refactor `bin/gsd-tools.cjs` to:
   - Drop the shared functions (now in shared)
   - Import shared functions from `./vendor/agenticapps-shared/bin/shared-tools.cjs`
     where workflow code needs them
   - Keep the workflow-specific functions
5. Run the full claude-workflow test suite. Every gsd-tools call must still
   work. Migration suite must still pass (currently 190/190).

### Phase D — Wire claude-workflow as a consumer (~1h)

1. In claude-workflow, add the shared repo as a submodule:
   `git submodule add https://github.com/agenticapps-eu/agenticapps-shared vendor/agenticapps-shared`
2. Pin to the tag from Phase B.
3. Update `install.sh` to ensure submodule is initialised on fresh clones.
4. Update CI workflows (if any) to clone with `--recurse-submodules`.
5. Update `migrations/run-tests.sh` references — they now live at
   `vendor/agenticapps-shared/migrations/run-tests.sh`.
6. Either replace `migrations/run-tests.sh` with a thin shim that delegates
   to the vendored runner, OR remove it entirely and update docs to point
   to the new path.

### Phase E — Verification (~1h)

- [ ] `bash vendor/agenticapps-shared/migrations/run-tests.sh` (or
      equivalent thin-shim wrapper) runs all 190+ tests GREEN
- [ ] Drift test `test-skill-md-version-matches-latest-migration-to-version`
      still PASSES (skill/SKILL.md version still == latest migration's `to_version`)
- [ ] All existing migrations (0001 through latest in 1.21.0) still apply
      cleanly against a fresh fixture
- [ ] `bin/gsd-tools.cjs` still serves all workflow-side callers (gsd-*
      skills still work)
- [ ] No regression in any GSD command (try `/gsd-progress`, `/gsd-stats`,
      `/gsd-help` — they should still produce identical output)
- [ ] The shared repo's own tests pass (`agenticapps-shared:tests/run-tests.sh`)

### Phase F — Ship (~30 min)

1. Tag `agenticapps-shared` v1.0.0 on its main branch.
2. Open PR in claude-workflow with the submodule consumption changes.
3. PR title: `v2.0.0-rc.1 chore: extract shared infrastructure to agenticapps-shared (SPLIT-01)`
4. PR body: link to SPLIT-00, SPLIT-01, the new shared repo, and the
   extraction commit-set.
5. Merge after CodeRabbit + any human reviewers approve.

## Versioning strategy for `agenticapps-shared`

- **1.0.0**: initial published version (this extraction)
- **1.x.x**: additive changes (new shared helpers, new fixture types)
- **2.0.0**: breaking changes (signature changes in shared CLI, removed helpers)
- Drift test in `agenticapps-shared` itself? Probably not — it ships
  infrastructure, not skills. Consumers (claude-workflow,
  agenticapps-observability) each have their own drift test pinned to their
  own SKILL.md.

## What 1.21.0's "preparatory file-level decoupling" should already have done

If 1.21.0 was thorough, this extraction should be mostly mechanical. Things
1.21.0 may have set up:
- File-level boundaries between "framework" and "workflow-specific" code
- Clear export contracts in `bin/gsd-tools.cjs` (named exports rather than
  monolithic exports)
- Documentation comments marking each function as `// SHARED` or `// WORKFLOW`
- Audit list in `docs/decisions/00XX-shared-extraction-boundaries.md`

If 1.21.0 skipped this, Phase C above is where it lands — just at extraction
time instead of preparation time.

## Failure-mode handling

- **History extraction loses files**: rerun `git filter-repo` with explicit
  path list; verify with `git log --all -- <file>` in the new repo
- **Migration suite breaks in claude-workflow after submodule wire-up**:
  most likely cause is hardcoded path. Grep claude-workflow for the old paths
  (`migrations/run-tests.sh`, etc.) and update to the vendored path
- **Drift test fails because SKILL.md is now in a different place**: the
  drift test logic moves to shared, but the SKILL.md it checks against stays
  in claude-workflow. Verify the drift test takes the SKILL.md path as input
  (not hardcoded)
- **gsd command regression**: run `/gsd-help` and walk each gsd command;
  bisect on the gsd-tools refactor commit

## Acceptance criteria for SPLIT-01 done-ness

- [ ] `agenticapps-eu/agenticapps-shared` exists at v1.0.0
- [ ] claude-workflow consumes it as a submodule
- [ ] All claude-workflow tests + GSD commands still work
- [ ] Drift test passes
- [ ] No observability-specific code in shared (clean separation)
- [ ] No GSD-specific code in shared (clean separation the other way)
- [ ] Documentation in shared README explains the consumption pattern
- [ ] claude-workflow CHANGELOG records the extraction
- [ ] PR merged to claude-workflow main; tag bumped to next claude-workflow
      version (probably 2.0.0-rc.X or 1.22.0 — decided at SPLIT-02 ship time)

---

**Status:** Drafted 2026-06-02. Do not execute until SPLIT-00 prerequisites
are GREEN. Read SPLIT-02 next to understand what depends on this.
