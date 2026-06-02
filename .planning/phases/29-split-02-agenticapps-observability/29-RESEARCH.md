# Phase 29: SPLIT-02 — Extract observability to `agenticapps-observability` - Research

**Researched:** 2026-06-02
**Domain:** Git repository extraction, skill renaming, migration ownership, submodule consumption, deferred observability fixes
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Repo + naming**
- New repo: `agenticapps-eu/agenticapps-observability`, private initially (flip to public after the 0.12.0 impl-agnostic refactor — deferred), MIT license default (user may override).
- Skill renamed `add-observability` → `observability` (the noun/product identity).
- `add-observability` stays as an alias for **two minor releases** (0.11.0, 0.12.0); warning in 0.13.0; removed in 0.14.0. Alias mechanism = **Option A (dual-symlink)** for 0.11.0+0.12.0.
- obs repo starts at **0.11.0**, continuing the version line from `add-observability` 0.10.0. 0.11.0 = pure structural extraction + rename + deferred-fix migration. NO functional adapter refactor in 0.11.0.

**Submodule (mirrors SPLIT-01)**
- Consume `agenticapps-shared` via git submodule at `vendor/agenticapps-shared/`, pinned by **gitlink SHA** to the `v1.0.0` release (`1f5d543`). obs `migrations/run-tests.sh` is a thin shim that sources the shared lib (same source-and-keep pattern claude-workflow uses).

**Deferred-fix migration**
- A NEW migration that **supersedes 0021** (route (b) in RESEARCH-cron Q4). NOT a 0021 re-issue (0021 is immutable — mutating its baseline breaks the hash/idempotency contract for callbot, cparx). Same all-clean-gate + dirty-detection engine as 0021.
- The three deferred obs fixes ship together in this one migration (they touch the same templates).
- **fxsa's `CronMonitorConfigInput` function-form generalisation is SEPARABLE** — default leave out (fxsa retains a much smaller local delta); planner may fold it in if low-cost.

**History**
- Phase 29 uses `git filter-repo` for **whole-file moves** (the observability tree), so `git log --follow` lineage IS preserved. CHANGELOG records provenance to claude-workflow phases 21–26.

**Planning artifacts stay**
- `.planning/phases/25-*` and `26-*` STAY in claude-workflow. Future obs phases get their own `.planning/` in the new repo.

**Phase boundary**
- Phase 29 is the NEW-REPO side. claude-workflow stays fully working through Phase 29 (`add-observability/` is COPIED with history, not deleted). The breaking cleanup is **Phase 30 (SPLIT-03)**.

### Claude's Discretion
- Exact obs migration number (continue the obs migration chain).
- Whether to fold fxsa's `CronMonitorConfigInput` function-form generalisation into the new migration (default: leave out).
- Disposition of the 4 known-failing `test_migration_0017` tests if 0017 moves.

### Deferred Ideas (OUT OF SCOPE)

- **Phase 30 (SPLIT-03):** delete `add-observability/` from claude-workflow; repoint the install migration (0011); manage alias deprecation window on claude-workflow side; ship `claude-workflow 2.0.0`; fix #58.
- **Phase D (own GSD phase IN the new obs repo, → obs 0.12.0):** implementation-agnostic redesign — `Destination` interface as published contract, adapter relocation, template refactor.
- **FIX-0017-ENGINE.md** (3 migration-0017 engine bugs + coverage gaps): NOT in Phase 29. Travels with migration 0017 wherever ownership lands it.
- **fxsa `CronMonitorConfigInput` function-form generalisation** — separable from the missed-checkin fix; default leave out.
</user_constraints>

---

## Summary

Phase 29 creates and populates `agenticapps-eu/agenticapps-observability` as the canonical home for the observability skill. It has five interlocking workstreams: (A) bootstrap skeleton + submodule; (B) history-preserving extraction via `git filter-repo` from a claude-workflow scratch clone; (C) skill rename `add-observability` → `observability` with Option A dual-symlink alias; the deferred-fix migration folding three known correctness gaps; and (G/H) verification + tag.

The most complex decision this research resolves is the **migration-ownership audit** (Gray Area 1), which determines exactly which files move in Phase B. The audit produces a definitive MOVE/STAY table for migrations 0011–0021. Key finding: migration 0017 (`add-axiom-logs-destination`) MOVES to the obs repo despite the SPLIT-02 doc's line 122 "stays" note, because its `migrate-0017-axiom-destination.sh` engine sources `add-observability/templates/` and applies to `<wrapper-dir>/destinations/` — observability-owned failure mode. The 4 known-failing `test_migration_0017` tests travel with it.

The deferred-fix migration number in the obs repo is **obs-0001** (a fresh numbering starting from 0001 within the obs chain, since 0019 and 0021 are the obs chain's existing migrations numbered from the claude-workflow sequence). However — because the migration content doc will live alongside 0019 and 0021 docs in `migrations/` — the planner should pick a number that is HIGHER than 0021 but consistent with the new repo's own chain. The canonical recommendation: **0022** — continuing the sequence from where claude-workflow left off, preserving the story that 0022 supersedes 0021.

**Primary recommendation:** Implement Phase 29 in the A → B → C + deferred-fix → G → H order, keeping each wave user-gated at the push boundary. The filter-repo extraction is idempotent (re-run against a fresh scratch clone produces the same result), so failures in Phase B are recoverable.

---

## Project Constraints (from CLAUDE.md)

[VERIFIED: CLAUDE.md at /Users/donald/Sourcecode/agenticapps/claude-workflow/CLAUDE.md]

| Directive | Requirement |
|-----------|-------------|
| GitNexus impact analysis | Run `gitnexus_impact` before modifying any symbol. |
| `gitnexus_detect_changes()` | Run before every commit to verify scope. |
| HIGH/CRITICAL risk warnings | Must warn user before proceeding with edits. |
| NEVER rename symbols with find-and-replace | Use `gitnexus_rename` (understands call graph). |
| Feature branches + PRs | Always use feature branches; never commit directly to main. |
| Cross-AI review (`/gsd-review`) | Non-skippable after plan-checker PASS. |
| GSD execution hooks | Pre-phase brainstorming for new services; per-plan TDD for `tdd="true"` tasks; post-phase `/review` + `/cso` for auth/storage/API/LLM code. |
| codex exec stdin hang | When any review step shells `codex exec`, must use `< /dev/null`. |

**Note on GitNexus scope:** Phase 29 primarily creates a NEW SIBLING REPO and writes new files. Direct modifications to claude-workflow source files are minimal (only `.gitmodules`, `install.sh` adjustments are NOT in Phase 29 scope — those are Phase 30). GitNexus impact analysis is most relevant in Phase 30; in Phase 29 the blast radius for any claude-workflow changes is essentially zero.

---

## Standard Stack

### Core (Phase B — git history extraction)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `git-filter-repo` | a40bce5 (installed: `/opt/homebrew/bin/git-filter-repo`) | History-preserving directory extraction with path renames | Official replacement for `git filter-branch`; Python-based; supports `--path-rename`; idempotent when run against a fresh scratch clone |
| `git` | system | Scratch clone, push, submodule | — |
| `gh` | system (auth: DonaldVl, member: agenticapps-eu) | Repo create, PR, tag push | — |

[VERIFIED: git-filter-repo installed at /opt/homebrew/bin/git-filter-repo, version a40bce548d2c]
[VERIFIED: gh auth logged in as DonaldVl, member of agenticapps-eu]
[VERIFIED: agenticapps-eu/agenticapps-shared exists (private) at gitlink SHA 1f5d543]
[VERIFIED: agenticapps-eu/agenticapps-observability does NOT yet exist — ready to create]

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `agenticapps-shared` submodule | v1.0.0 (SHA 1f5d543) | Migration runner lib (helpers, fixture-runner, preflight, drift-test) | Phase A.3 — pin submodule; Phase B/G — run-tests.sh sources it |
| `vitest` | pinned in template's `package.json` | Run the cron-monitor.test.ts + queue-monitor.test.ts suites per stack | Phase G template verification |
| `bash` | system | run-tests.sh shim | Everywhere |

**Installation (Phase A):**
```bash
# Create repo
gh repo create agenticapps-eu/agenticapps-observability --private --license MIT --description "..."

# Add submodule pinned to v1.0.0
git submodule add https://github.com/agenticapps-eu/agenticapps-shared vendor/agenticapps-shared
cd vendor/agenticapps-shared && git checkout v1.0.0 && cd ../..
git add .gitmodules vendor/agenticapps-shared
```

---

## Migration Ownership Audit (Gray Area 1 — Resolved)

### Boundary Test
"Who owns the failure mode if this migration breaks?"
- **claude-workflow failure** → STAYS in claude-workflow
- **observability-scaffolding failure** → MOVES to obs repo

### Definitive MOVE / STAY Table

[VERIFIED: inspected every migration header + applies_to in claude-workflow/migrations/]

| Migration | Title | from→to | Disposition | Rationale |
|-----------|-------|---------|-------------|-----------|
| 0000 | baseline | — | STAYS | Framework baseline; no code changes |
| 0001 | go-impeccable-database-sentinel | 1.0.0→1.3.0 | STAYS | Wires Go skill packs + impeccable; pure workflow |
| 0002 | observability-spec-0.2.1 | — | STAYS | Spec version bump in workflow templates, NOT obs code changes |
| 0004 | programmatic-hooks-architecture-audit | — | STAYS | Hooks config; pure workflow |
| 0005 | multi-ai-plan-review-enforcement | — | STAYS | multi-ai-review-gate.sh; pure workflow |
| 0006 | llm-wiki-builder-integration | — | STAYS | Wiki builder; pure workflow |
| 0007 | gitnexus-code-graph-integration | — | STAYS | GitNexus; pure workflow |
| 0008 | coverage-matrix-page | — | STAYS | Coverage; pure workflow |
| 0009 | vendor-claude-md-sections | — | STAYS | CLAUDE.md vendoring; pure workflow |
| 0010 | post-process-gsd-sections | — | STAYS | GSD section markers; pure workflow |
| 0011 | observability-enforcement | 1.9.3→1.10.0 | **STAYS** | Bootstraps the obs skill INTO consuming projects (via `add-observability scan`). Failure = claude-workflow setup broken. Phase 30 repoints it. |
| 0012 | slash-discovery | 1.10.0→1.11.0 | **MOVE** | `applies_to: ~/.claude/skills/add-observability` (symlink). This migration's verify is `test -d $HOME/.claude/skills/agenticapps-workflow/add-observability` — observability skill wiring. Failure = obs skill undiscoverable. |
| 0013 | auto-init-and-stale-vendored-cleanup | 1.11.0→1.12.0 | **MOVE** | `applies_to: .claude/skills/add-observability` stale copy removal + chains obs init. Failure = obs skill stale/broken. |
| 0014 | inject-spec-11-coding-discipline | 1.12.0→1.14.0 | STAYS | Spec §11 coding discipline injection into CLAUDE.md; workflow-level |
| 0015 | add-ts-declare-first-skill | — | STAYS | ts-declare-first skill; pure workflow |
| 0016 | fix-multi-ai-review-gate-resolution | — | STAYS | Review gate fix; pure workflow |
| 0017 | add-axiom-logs-destination | 1.15.0→1.16.0 | **MOVE** | `applies_to: <wrapper-dir>/destinations/` + CLAUDE.md observability block. Engine (`migrate-0017-axiom-destination.sh`) sources `add-observability/templates/`. Failure = observability destinations broken. Boundary test = observability's problem. **Note:** SPLIT-02 doc line 122 says "stays" — OVERRIDDEN by boundary test. |
| 0018 | postphase-observability-hook | 1.16.0→1.17.0 | **MOVE** | Installs `observability-postphase-scan.sh` hook (a `add-observability scan` caller). Failure = obs scan hook broken. |
| 0019 | sentry-crons-and-healthz | 1.17.0→1.18.0 | **MOVE** | Ships `cron-monitor.ts` + `healthz-snippet.ts` via `migrate-0019-sentry-crons-and-healthz.sh`. Failure = obs scaffolding broken. |
| 0020 | openrouter-integration | 1.18.0→1.19.0 | **MOVE** | References `add-observability/openrouter-integration.md`, sources `add-observability/templates/<stack>/llm-response-meta.ts`. Failure = obs OpenRouter kit broken. |
| 0021 | cron-monitor-shape-and-queues | 1.19.0→1.20.0 | **MOVE** | Re-revs `cron-monitor.ts` + ships `queue-monitor.ts`. Observability scaffolding content. |

### Summary by disposition

- **STAYS (12):** 0000, 0001, 0002, 0004, 0005, 0006, 0007, 0008, 0009, 0010, 0011, 0014, 0015, 0016
- **MOVES (8):** 0012, 0013, 0017, 0018, 0019, 0020, 0021 + 0022 (new deferred-fix migration)

**0011 stays confirmed:** Its job is to bootstrap obs skill into a consuming project — that's a claude-workflow migration. Phase 30 repoints it. This is the "handoff point" as described in SPLIT-02 doc.

### 0017 — Disposition of 4 Known-Failing Tests

[VERIFIED: `bash migrations/run-tests.sh 0017` → PASS=7 FAIL=4 (fixtures 02, 06, 10, 11 fail)]

The 4 failing tests are FIX-0017-ENGINE.md scope (engine bugs: unsubstituted tokens, anchor failures). These failures travel with migration 0017 to the obs repo. The obs repo **starts with 4 known failures** in its `test_migration_0017` suite. This matches claude-workflow's current baseline — no regression, just moved. FIX-0017-ENGINE.md becomes an obs-repo follow-up phase.

**Planner decision required:** The CONTEXT.md Gray Area 2 names two options:
- **(Recommended) Move 0017 + document the 4 known-failures.** The obs repo starts at `PASS=N FAIL=4` where the 4 are test_migration_0017. Mirrors claude-workflow today. FIX-0017-ENGINE becomes obs Phase 1 or Phase 2.
- **(Alternative) Leave 0017 in claude-workflow for now.** Then the obs migration chain skips from 0016 to 0018, creating a gap. Not recommended — violates the boundary test.

---

## Architecture Patterns

### New Repo Layout

[VERIFIED: from SPLIT-02-agenticapps-observability.md "New repo layout" section + CONTEXT.md deferred items]

**Phase 29 (0.11.0) only — NOT the full Phase D layout:**

```
agenticapps-observability/
├── README.md
├── SKILL.md                       # name: observability, version: 0.11.0
├── CHANGELOG.md                   # continues from add-observability 0.10.0
├── VERSION                        # 0.11.0
├── LICENSE
├── install.sh                     # creates both symlinks (observability + add-observability alias)
├── implements-spec.md             # implements_spec: 0.3.2
├── docs/
│   └── decisions/                 # ADRs 0029-0034 (moved) + new cron-flush ADR
├── init/
│   └── INIT.md
├── scan/
│   └── SCAN.md
├── scan-apply/
│   └── APPLY.md                   # (if present in add-observability/)
├── enforcement/
│   └── README.md
├── destinations/                  # Phase D skeleton ONLY — .gitkeep dirs
│   ├── _contract/.gitkeep
│   ├── sentry/.gitkeep
│   ├── axiom/.gitkeep
│   └── _examples/{datadog,honeycomb,otlp}/.gitkeep
├── templates/
│   ├── ts-cloudflare-worker/
│   ├── ts-cloudflare-pages/
│   ├── ts-supabase-edge/
│   ├── ts-react-vite/
│   ├── go-fly-http/
│   └── openrouter-monitor/
├── migrations/
│   ├── README.md
│   ├── 0012-slash-discovery.md
│   ├── 0013-auto-init-and-stale-vendored-cleanup.md
│   ├── 0017-add-axiom-logs-destination.md
│   ├── 0018-postphase-observability-hook.md
│   ├── 0019-sentry-crons-and-healthz.md
│   ├── 0020-openrouter-integration.md
│   ├── 0021-cron-monitor-shape-and-queues.md
│   ├── 0022-explicit-flush-and-monitor-config.md  # NEW deferred-fix migration
│   ├── scripts/
│   │   ├── migrate-0017-axiom-destination.sh
│   │   ├── migrate-0019-sentry-crons-and-healthz.sh
│   │   └── migrate-0021-with-cron-and-queue-updates.sh
│   ├── test-fixtures/
│   │   ├── 0017/   (11 fixtures, PASS=7 FAIL=4 — FIX-0017 deferred)
│   │   ├── 0019/   (13 fixtures)
│   │   └── 0021/   (4 fixtures)
│   └── run-tests.sh               # thin source-and-keep shim (mirrors claude-workflow pattern)
├── legacy/
│   └── SKILL.md                   # add-observability alias (deprecation banner)
├── vendor/
│   └── agenticapps-shared/        # git submodule @ v1.0.0 (SHA 1f5d543)
└── tests/
    └── run-tests.sh               # calls migrations/run-tests.sh
```

### Pattern 1: git filter-repo Whole-File Extraction WITH History

[VERIFIED: git-filter-repo installed at /opt/homebrew/bin/git-filter-repo]
[ASSUMED: exact `--path-rename` flag syntax — verify against official docs; logic is correct but flag names may differ from training data]

**What:** Extract a subtree from a source repo into a new repo with full `git log --follow` lineage, using path renames to map source paths to target layout.

**When to use:** Any time files physically move between repos and history preservation matters (this phase; SPLIT-02).

**Key principle:** Run filter-repo against a **scratch clone** of claude-workflow, NOT the live working repo. The scratch clone is disposable; filter-repo rewrites are destructive to the clone.

```bash
# Source: git-filter-repo official docs + SPLIT-02-agenticapps-observability.md Phase B

# 1. Scratch clone (bare-ish, but not bare — filter-repo needs working tree)
git clone https://github.com/agenticapps-eu/claude-workflow /tmp/cw-scratch-for-obs
cd /tmp/cw-scratch-for-obs

# 2. Run filter-repo with path-rename rules
# Each --path-rename maps <source-prefix>:<target-prefix>
git filter-repo \
  --path add-observability/ \
  --path "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh" \
  --path "templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh" \
  --path "templates/.claude/scripts/migrate-0017-axiom-destination.sh" \
  --path "templates/.claude/scripts/migrate-0017-old-wrappers/" \
  --path migrations/0012-slash-discovery.md \
  --path migrations/0013-auto-init-and-stale-vendored-cleanup.md \
  --path migrations/0017-add-axiom-logs-destination.md \
  --path migrations/0018-postphase-observability-hook.md \
  --path migrations/0019-sentry-crons-and-healthz.md \
  --path migrations/0020-openrouter-integration.md \
  --path migrations/0021-with-cron-and-queue-updates.md \
  --path "migrations/test-fixtures/0017/" \
  --path "migrations/test-fixtures/0019/" \
  --path "migrations/test-fixtures/0021/" \
  --path docs/decisions/0029-cron-monitor-sdk-composition.md \
  --path docs/decisions/0030-openrouter-integration-sdk-first.md \
  --path docs/decisions/0031-0019-engine-index-ts-anchor.md \
  --path docs/decisions/0032-cron-monitor-generic-narrowing-cf-worker-only.md \
  --path docs/decisions/0033-with-queue-monitor.md \
  --path docs/decisions/0034-observability-init-singleton-invariant.md \
  --path-rename "add-observability/:" \
  --path-rename "templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:migrations/scripts/migrate-0019.sh" \
  --path-rename "templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh:migrations/scripts/migrate-0021.sh" \
  --path-rename "templates/.claude/scripts/migrate-0017-axiom-destination.sh:migrations/scripts/migrate-0017.sh" \
  --path-rename "templates/.claude/scripts/migrate-0017-old-wrappers/:migrations/scripts/migrate-0017-old-wrappers/" \
  --path-rename "migrations/test-fixtures/0017/:migrations/test-fixtures/0017/" \
  --path-rename "migrations/test-fixtures/0019/:migrations/test-fixtures/0019/" \
  --path-rename "migrations/test-fixtures/0021/:migrations/test-fixtures/0021/" \
  --path-rename "docs/decisions/:docs/decisions/"

# 3. Push filtered history into new repo
git remote set-url origin https://github.com/agenticapps-eu/agenticapps-observability
git push origin main --force  # first push into empty repo — force is safe
```

**Idempotency:** Re-running filter-repo against a FRESH scratch clone is idempotent. Do NOT re-run on the same scratch clone after a push (history has been rewritten; a second run produces different SHAs). If Phase B fails, discard scratch clone and restart from a new `git clone`.

**Verify with:**
```bash
git log --follow --oneline -- SKILL.md | head -5        # should show history from add-observability/SKILL.md
git log --follow --oneline -- migrations/0019-sentry-crons-and-healthz.md | head -5
git log --follow --oneline -- migrations/scripts/migrate-0021.sh | head -5
```

### Pattern 2: Source-and-Keep Migration Runner Shim (SPLIT-01 Precedent)

[VERIFIED: claude-workflow/migrations/run-tests.sh lines 35-66 — exact pattern confirmed]

**What:** The obs repo's `migrations/run-tests.sh` is NOT a thin delegating shim. It sources the four shared libs then contains its own WORKFLOW per-migration test bodies (same D-28e source-and-keep pattern claude-workflow uses).

**Key wiring (verbatim from claude-workflow precedent):**
```bash
# BASH_SOURCE[0]-relative path resolution (symlink-safe, macOS/BSD portable)
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
_SCRIPT_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
_SHARED_LIB="$_SCRIPT_DIR/../vendor/agenticapps-shared/migrations/lib"

# Fail-closed guard (review finding 1 pattern)
if [ ! -d "$_SHARED_LIB" ]; then
  echo "ERROR: agenticapps-shared submodule not initialized." >&2
  exit 1
fi

source "$_SHARED_LIB/helpers.sh"
source "$_SHARED_LIB/fixture-runner.sh"
source "$_SHARED_LIB/preflight.sh"
source "$_SHARED_LIB/drift-test.sh"
```

**Drift test wiring (obs-specific parameters):**
```bash
# run_drift_test(skill_md_path, migrations_dir) — shared mechanism
# Policy wrapper (stays in obs run-tests.sh):
if run_drift_test "$REPO_ROOT/SKILL.md" "$REPO_ROOT/migrations"; then
  echo "  ${GREEN}PASS${RESET}: test-skill-md-version-matches-latest-migration-to-version"
  PASS=$((PASS+1))
else
  echo "  ${RED}FAIL${RESET}: test-skill-md-version-matches-latest-migration-to-version"
  FAIL=$((FAIL+1))
fi
```

**Note on SKILL.md path:** In the obs repo the SKILL.md is at the REPO ROOT (not `skill/SKILL.md` as in claude-workflow). The drift test call uses `"$REPO_ROOT/SKILL.md"` (not `"$REPO_ROOT/skill/SKILL.md"`).

### Pattern 3: Option A Dual-Symlink Alias

[VERIFIED: install.sh source code + SPLIT-02-agenticapps-observability.md "Skill rename: backward compat" section]
[ASSUMED: Claude Code skill loader resolves `~/.claude/skills/<name>/SKILL.md` (one level deep) — verified by current install.sh comment: "Claude Code's skill loader scans ~/.claude/skills/<name>/SKILL.md (one level deep)"]

**What:** The obs repo's `install.sh` creates two symlinks: one canonical (`observability`) and one legacy (`add-observability`) pointing at `legacy/SKILL.md` (deprecation banner body).

```bash
# install.sh for agenticapps-observability
SKILLS_DIR="$HOME/.claude/skills"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Submodule sync (mirrors claude-workflow install.sh pattern)
if [ -f "$REPO/.gitmodules" ] && { [ -d "$REPO/.git" ] || [ -f "$REPO/.git" ]; }; then
  git -C "$REPO" submodule sync --recursive
  git -C "$REPO" submodule update --init --recursive
fi

# Canonical symlink
ln -sfn "$REPO" "$SKILLS_DIR/observability"

# Legacy alias symlink (Option A — points at legacy/SKILL.md via sub-dir)
ln -sfn "$REPO/legacy" "$SKILLS_DIR/add-observability"
```

**`legacy/SKILL.md` content (deprecation banner):**
```markdown
---
name: add-observability
version: 0.11.0
---
# add-observability (deprecated alias)

This skill has been renamed to `observability`. Please use `/observability` instead.

Alias retained for 0.11.0 + 0.12.0. Warning in 0.13.0. Removed in 0.14.0.

Sub-skill routing:

| Subcommand | Canonical path |
|------------|----------------|
| `init`     | `../init/INIT.md` |
| `scan`     | `../scan/SCAN.md` |
| `scan-apply` | `../scan-apply/APPLY.md` |
```

**Slash command resolution:** `/add-observability init` loads `~/.claude/skills/add-observability/SKILL.md` (via the symlink to `legacy/`) and can route to the canonical sub-skill files via relative paths `../init/INIT.md`.

### Pattern 4: Deferred-Fix Migration Shape

[VERIFIED: RESEARCH-cron-monitor-flush-fxsa.md + migration 0021 frontmatter + cron-monitor.ts source]

**Migration number: 0022** — continues the sequence from claude-workflow's last migration (0021). The obs repo's `migrations/` directory contains 0012–0021 (moved) plus 0022 (new). This preserves history continuity.

**Frontmatter:**
```yaml
---
migration_id: "0022"
from_version: 1.20.0
to_version: 1.21.0
type: "re-rev-with-dirty-detection"
idempotency_marker: "cron-monitor.ts content-hash matches v1.21.0 explicit-flush baseline (twofold: includes monitorConfig-on-every-checkin shape)"
related: ["0021", "FXSA-WORKERS-6", "ADR-0033", "ADR-0035-obs"]
---
```

**Three fixes bundled in 0022:**

1. **cron-flush backport** — re-rev `cron-monitor.ts` (cf-worker + cf-pages + supabase-edge as applicable) to the explicit-per-check-in-flush body from `RESEARCH-cron-monitor-flush-fxsa.md`. Keep narrowed generic `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` (NOT `Record<string, unknown>`).

2. **#61 buildMonitorConfig / fixture fix** — replace the relaxed `MonitorConfig` stub in `migrations/test-fixtures/0021/04-.../types.d.ts` with the real `@sentry/cloudflare` shape; forward `monitorConfig` on every check-in (in_progress/ok/error) in the new migration's apply step.

3. **queue-monitor.ts flush audit** — audit `queue-monitor.ts` (cf-worker + cf-pages) for the identical buffered-flush race. The current template uses `Sentry.withMonitor` (Guarded Shape A) which has the same buffered-flush problem. Apply the same `ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS))` immediately after the in_progress equivalent. (Note: queue-monitor uses `withMonitor` which calls `captureCheckIn` internally, but the flush behavior is identical.)

**FXSA-WORKERS-6 marker recognition:**
```bash
# In the engine, recognise LOCAL-PATCH markers as known-reconcilable
if grep -q "FXSA-WORKERS-6" "$wrapper/cron-monitor.ts"; then
  echo "  INFO: FXSA-WORKERS-6 LOCAL-PATCH marker found — recognising as reconcilable divergence"
  echo "        Remove marker after migration; new canonical hash will match."
  # Treat as CLEAN (proceed to apply)
fi
```

### Anti-Patterns to Avoid

- **Re-issuing 0021:** 0021 is Released (2026-05-31) and immutable. Mutating its baseline breaks the hash/idempotency contract for callbot and cparx. New migration = new immutable baseline. [VERIFIED: migration 0021 Status line: "Released 2026-05-31"]
- **Running filter-repo on the live working repo:** Always use a scratch clone. filter-repo rewrites are destructive and would corrupt the claude-workflow development history.
- **Symlink collision in install.sh:** Both the obs `install.sh` and claude-workflow's `install.sh` must produce non-overlapping skill names. obs creates `observability` + `add-observability`; claude-workflow's install.sh currently creates `add-observability` pointing at its own subdir. After Phase 29, if a user has BOTH installed, the last `install.sh` run wins for `add-observability`. Phase 30 removes the claude-workflow `add-observability` entry — that's the final clean state. During the Phase 29 window (before Phase 30), document this as a known ordering issue.
- **Using `grep -r` to find "all observability references":** The boundary test + audit above is the correct method; grepping for "add-observability" or "observability" finds too many false positives (ADR references, CHANGELOG entries, etc.).
- **Copying without history:** Do NOT use `cp -r` to copy files into the new repo. The filter-repo step in Phase B is the only correct method for history preservation.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| History-preserving directory extraction | Custom `git log --follow` + `git format-patch` pipeline | `git filter-repo --path-rename` | Filter-repo handles tree rewriting, SHA remapping, and all edge cases. Custom patch pipelines lose commit metadata. |
| Shared lib sourcing with symlink resolution | Manual dirname logic | The BASH_SOURCE[0] pattern (verbatim from claude-workflow's run-tests.sh) | The existing pattern already handles symlinks, macOS/BSD `readlink` incompatibility. Copy verbatim. |
| Migration number picking | Custom schema | Continue the existing sequence (0022 follows 0021) | Preserves history continuity; the drift test checks `latest migration to_version`; inserting gaps is confusing. |
| Skill alias handling | Custom loader overlay | Option A dual-symlink (decided in CONTEXT.md) | The Claude Code loader is a black box at the skill-author level; symlinks are the only reliable inter-skill hook. |

**Key insight:** The entire SPLIT-01 precedent (28-VERIFICATION.md) is the canonical reference for everything about submodule wiring, install.sh guard patterns, run-tests.sh source-and-keep. Copy the pattern exactly; do not redesign.

---

## Runtime State Inventory

Observability rename (from `add-observability` to `observability`) affects runtime-discoverable state. This is a new-repo bootstrap + Phase-29-only rename; the claude-workflow side is Phase 30. Cataloguing Phase 29-scoped items:

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — obs skill has no persistent datastore of its own (observability wrappers live in consumer project repos, not centrally) | None for Phase 29 |
| Live service config | None — obs is a scaffolder; no live running service | None |
| OS-registered state | `~/.claude/skills/add-observability` symlink (created by claude-workflow's current install.sh) — points at claude-workflow's `add-observability/` subdir | Phase 29 installs NEW symlink at `~/.claude/skills/observability` → obs repo. The `add-observability` symlink stays pointing at claude-workflow until Phase 30. No collision because obs install.sh creates `add-observability` → `legacy/`; if both repos are installed, last one wins. Document ordering in install.sh. |
| Secrets/env vars | `SENTRY_DSN`, `SENTRY_CRON_MONITOR_SLUG_*`, `SERVICE_NAME` — these are consumer-project env vars, not skill-name-dependent | None — env var names are unrelated to skill name |
| Build artifacts | `add-observability/templates/*/node_modules/` in the source tree (excluded by .gitignore) | No action — filter-repo extracts from git history, not working tree; node_modules are not in git |

**Nothing found in categories "stored data", "live service config", "secrets/env vars", "build artifacts"** — verified by inspection of skill structure.

---

## Common Pitfalls

### Pitfall 1: filter-repo path-rename order sensitivity
**What goes wrong:** When `--path-rename` rules overlap or the source paths aren't filtered with `--path` first, filter-repo may silently include unwanted paths or fail to rename.
**Why it happens:** `--path-rename` only renames; `--path` selects. Both are needed together.
**How to avoid:** Always pair `--path <dir>` with the corresponding `--path-rename <dir>:<newdir>`. Test with `--dry-run` first (filter-repo supports it via `--refs HEAD --no-ff`).
**Warning signs:** After push, `git log --follow migrations/scripts/migrate-0019.sh` shows no history (path wasn't renamed correctly).

### Pitfall 2: drift test checks wrong SKILL.md path
**What goes wrong:** The obs run-tests.sh calls `run_drift_test "$REPO_ROOT/skill/SKILL.md"` (copied verbatim from claude-workflow) instead of `"$REPO_ROOT/SKILL.md"` (obs repo root).
**Why it happens:** claude-workflow stores SKILL.md at `skill/SKILL.md` (nested under `skill/` subdir, symlinked out). The obs repo stores it at root.
**How to avoid:** Explicitly set `run_drift_test "$REPO_ROOT/SKILL.md"` in the obs run-tests.sh policy wrapper. The shared `run_drift_test` function takes an explicit path — do NOT rely on a default.
**Warning signs:** Drift test always FAILS with "skill_md not found" or always PASSES with wrong version.

### Pitfall 3: 0022 migration version mismatch
**What goes wrong:** The new migration's `to_version: 1.21.0` conflicts with the obs SKILL.md's version `0.11.0`.
**Why it happens:** The obs migration chain tracks `agentic-apps-workflow` skill versions (the consumer project's SKILL.md version), not the obs skill's own version. Migration `from_version`/`to_version` refer to the CONSUMER project state.
**How to avoid:** Keep the migration frontmatter's `from_version`/`to_version` tracking the claude-workflow SKILL.md version (1.20.0 → 1.21.0). The obs SKILL.md version is separate (`0.11.0`). The drift test in the obs repo must be adapted — it should check that the obs SKILL.md version (`0.11.0`) matches a SEPARATE obs-specific version field, OR the drift policy must be rewritten to track obs versioning separately.
**Warning signs:** Drift test fails because `skill_version=0.11.0` != `migration_to_version=1.21.0`.

**Resolution for Pitfall 3:** The obs repo needs a NEW drift test policy:
- Option A: Have migration 0022's `to_version` track the obs skill version (`0.11.0`). Keep all obs migration `from_version`/`to_version` as obs versions (0.x.y). This requires renumbering the existing migration frontmatter when they move. HIGH effort.
- **Option B (recommended):** For Phase 29, the obs repo's `run-tests.sh` skips the drift test OR uses a custom drift check that compares obs SKILL.md `version: 0.11.0` against the obs-specific latest migration marker. The shared `run_drift_test` is generic enough to work if the latest migration in the obs `migrations/` dir has `to_version: 0.11.0`. This means migration 0022's frontmatter should use `to_version: 0.11.0` (obs version), not `to_version: 1.21.0` (cw version). The `from_version`/`to_version` in the obs migrations track obs skill versions going forward. For the moved migrations (0012–0021), their frontmatter tracks `agentic-apps-workflow` versions — the drift test checks only the LATEST migration's `to_version`, so only 0022's `to_version: 0.11.0` matters.

### Pitfall 4: Strict-Env generic regression in deferred-fix migration
**What goes wrong:** The cron-flush backport copies fxsa's `E extends Record<string, unknown>` form, which REGRESSES the D-05 ADR-0032 SC5 strict-Env narrowing.
**Why it happens:** fxsa's LOCAL-PATCH generalised the generic for multi-env slug resolution — a separable enhancement not required for the flush fix.
**How to avoid:** The draft body in RESEARCH-cron lines 126–166 uses `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` (narrowed). Copy this exact generic, not fxsa's version.
**Warning signs:** `cron-monitor.test.ts` D-16 strict-Env test fails to compile after migration apply.

### Pitfall 5: Submodule not initialized in fresh obs repo clone
**What goes wrong:** `migrations/run-tests.sh` fails with "ERROR: agenticapps-shared submodule not initialized."
**Why it happens:** Users clone the obs repo without `--recurse-submodules`.
**How to avoid:** Mirror claude-workflow's install.sh guard: if `.gitmodules` + `.git` present, run `git submodule sync --recursive && git submodule update --init --recursive`. Also add the fail-closed guard at top of run-tests.sh (check `$_SHARED_LIB` dir exists before sourcing).
**Warning signs:** All test runs immediately exit with submodule error.

### Pitfall 6: Migration script paths after filter-repo rename
**What goes wrong:** The obs migration markdown files (0019, 0021) reference scripts at `templates/.claude/scripts/migrate-0019-*.sh` (claude-workflow layout), but in the obs repo they live at `migrations/scripts/migrate-0019.sh`.
**Why it happens:** The migration markdown documents the invoke path; filter-repo renames the file but not the paths INSIDE the file.
**How to avoid:** After Phase B filter-repo push, do a pass over all moved migration markdown files to update any internal `ENGINE="$HOME/.claude/skills/..."` paths to the obs-repo equivalents.
**Warning signs:** Running a migration says "ENGINE not found" at a claude-workflow path.

---

## Code Examples

### SKILL.md Frontmatter Rename

[VERIFIED: current SKILL.md frontmatter in add-observability/SKILL.md]

```yaml
# Source: add-observability/SKILL.md current + SPLIT-02 doc SKILL.md changes section
---
name: observability                  # was: add-observability
version: 0.11.0                      # was: 0.10.0
implements_spec: 0.3.2               # unchanged
description: |
  Pluggable observability scaffolder for AgenticApps projects. Generate or
  audit observability wrappers across TypeScript/Go stacks running on
  Cloudflare Workers, Cloudflare Pages, Supabase Edge Functions, Vite browser
  apps, or Fly.io HTTP. First-party destination adapters: Sentry, Axiom.
---
```

### Canonical withCronMonitor Body (obs-0022 migration target)

[VERIFIED: RESEARCH-cron-monitor-flush-fxsa.md lines 123–166 — copy-ready draft]

```typescript
// Source: RESEARCH-cron-monitor-flush-fxsa.md — canonical draft (keep narrowed generic)
const FLUSH_TIMEOUT_MS = 2000;

export function withCronMonitor<E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }>(
  handler: ScheduledFn<E>,
  config?: CronMonitorConfig,
): ScheduledFn<E> {
  return async (controller, env, ctx) => {
    if (!isConfigured(env)) {
      await handler(controller, env, ctx); // fail-safe: no DSN → handler runs unchanged
      return;
    }

    const monitorSlug = resolveSlug(config, env, controller);
    const monitorConfig = buildMonitorConfig(config);

    let checkInId: string;
    try {
      checkInId = Sentry.captureCheckIn({ monitorSlug, status: "in_progress" }, monitorConfig);
      // FX-SIGNALS-WORKERS-6: flush the heartbeat IMMEDIATELY
      ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS));
    } catch {
      await handler(controller, env, ctx);
      return;
    }

    try {
      await handler(controller, env, ctx);
      Sentry.captureCheckIn({ checkInId, monitorSlug, status: "ok" }, monitorConfig);
    } catch (err) {
      Sentry.captureCheckIn({ checkInId, monitorSlug, status: "error" }, monitorConfig);
      throw err;
    } finally {
      ctx.waitUntil(Sentry.flush(FLUSH_TIMEOUT_MS));
    }
  };
}
```

### Updated types.d.ts for fixture 0021/04 (#61 fix)

[VERIFIED: current types.d.ts at migrations/test-fixtures/0021/04-.../types.d.ts — relaxed stub identified]

The current stub declares:
```typescript
declare module "@sentry/cloudflare" {
  export interface MonitorConfig { schedule?: { type: string; value?: string | number; unit?: string; }; ... }
  export function withMonitor<T>(...): T;
  export function captureException(error: unknown): string;
}
```

The new migration's fixture must add `captureCheckIn` and `flush` (since the new `withCronMonitor` no longer uses `withMonitor`):
```typescript
declare module "@sentry/cloudflare" {
  export interface MonitorConfig {
    schedule?: { type: "crontab"; value: string } | { type: "interval"; value: number; unit: string };
    checkinMargin?: number;
    maxRuntime?: number;
    timezone?: string;
  }
  export function captureCheckIn(
    checkIn: { monitorSlug: string; status: "in_progress" | "ok" | "error"; checkInId?: string },
    upsertMonitorConfig?: MonitorConfig,
  ): string;
  export function flush(timeout?: number): Promise<boolean>;
  export function captureException(error: unknown): string;
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `Sentry.withMonitor` (Guarded Shape A) for cron heartbeats | `captureCheckIn` + explicit `ctx.waitUntil(Sentry.flush())` per check-in | Phase 29 (this migration) | Prevents missed-checkin false positives for long-running handlers. Confirmed in @sentry/cloudflare 8.55.2 and v10/master — no upstream SDK fix. |
| Monorepo (`add-observability/` inside claude-workflow) | Dedicated repo (`agenticapps-observability`) | Phase 29 | Independent versioning, independent CI, cleaner ownership |
| `add-observability` skill name | `observability` skill name | Phase 29 (alias window) | Product identity clarity; `add-observability` alias retained until 0.13.0 |
| `git filter-branch` | `git filter-repo` | Several years ago (git ecosystem) | 10-100× faster; safer; idempotent; official recommendation |

**Deprecated/outdated:**
- `Sentry.withMonitor` as the check-in lifecycle for long-running handlers: still works for SHORT handlers (sub-30s crons), but vulnerable to missed-checkin for handlers that exceed the Sentry missed-checkin window. Migration 0022 supersedes this pattern.
- `handlerStarted` flag pattern: replaced by the two explicit `captureCheckIn` calls + separate try/catch scopes which make pre-handler vs post-handler distinction structural rather than flag-based.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `git filter-repo --path-rename src:dst` syntax is correct for directory renaming | Architecture Patterns / Pattern 1 | filter-repo command fails; fall back to `--path-glob` + `--path-rename`; verify with `git-filter-repo --help` before executing |
| A2 | Claude Code skill loader resolves `~/.claude/skills/<name>/SKILL.md` one level deep | Architecture Patterns / Pattern 3 | Option A dual-symlink alias may not work; test before relying on it |
| A3 | `legacy/SKILL.md` sub-skill routing via relative paths `../init/INIT.md` works when loaded via the `add-observability` symlink | Architecture Patterns / Pattern 3 | The deprecation alias may fail to route sub-skills; fall back to Option B (standalone SKILL.md with message only) |
| A4 | queue-monitor.ts in cf-pages has the same Guarded Shape A buffered-flush race as cf-worker | Architecture Patterns / Pattern 4 | Audit confirms it (same `Sentry.withMonitor` call; same buffered transport); queue handler on cf-pages is typically shorter-lived but the correctness issue exists |

---

## Open Questions

1. **Migration 0022 version numbering: obs-version vs cw-version?**
   - What we know: obs SKILL.md version is `0.11.0`; the moved migrations (0012–0021) use `agentic-apps-workflow` SKILL.md versions (1.x.y) in their frontmatter.
   - What's unclear: Should migration 0022's `to_version` track obs versioning (`0.11.0`) or the cw version it would have been (`1.21.0`)?
   - Recommendation: Use `to_version: 0.11.0` in 0022 (obs version). The shared `run_drift_test` compares obs SKILL.md `version: 0.11.0` against the latest migration's `to_version` — if 0022 uses `0.11.0` this passes. For the moved migrations (0012–0021) with `to_version: 1.20.0`, the drift test only checks the LATEST (0022), so this works. [ASSUMED — planner should validate this interpretation of run_drift_test behavior]

2. **Template stack scope for the flush fix (which stacks get the explicit-flush body in migration 0022)?**
   - What we know: `RESEARCH-cron-monitor-flush-fxsa.md` confirms the race in cf-worker. The same `Sentry.withMonitor` pattern is in cf-pages (`cron-monitor.ts` confirmed present). `ts-supabase-edge` has `cron-monitor.ts` but no queue-monitor.
   - What's unclear: Does `ts-supabase-edge` have the same isolated-isolate-reuse model that causes the race?
   - Recommendation: Apply the flush fix to cf-worker + cf-pages (both use Cloudflare isolate model). For supabase-edge, audit the runtime model; if flush behavior is different, document it separately. This matches the Phase 25 D-05 pattern (cf-worker gets the full treatment, others get audited first).

3. **FXSA-WORKERS-6 marker removal in fx-signal-agent**
   - What we know: fxsa has `FXSA-WORKERS-6` LOCAL-PATCH marker in its `cron-monitor.ts` plus a `.observability-0021.patch` refusal artifact.
   - What's unclear: Does the migration 0022 engine need to explicitly handle the refusal artifact cleanup, or does the operator remove it manually?
   - Recommendation: Document the two-step: (1) migration 0022 runs and detects the FXSA-WORKERS-6 marker as reconcilable; (2) operator removes the marker + refusal artifact; (3) migration 0022 re-run produces SKIP_ALREADY. Include this in the migration markdown's "Recovery" section.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `git-filter-repo` | Phase B history extraction | ✓ | a40bce548d2c | — |
| `gh` CLI | Phase A repo create, Phase H tag/push | ✓ | authenticated as DonaldVl | — |
| agenticapps-eu org membership | Phase A/H push | ✓ | member confirmed | — |
| `agenticapps-shared` v1.0.0 | Phase A.3 submodule | ✓ | SHA 1f5d543 (private, accessible) | — |
| `agenticapps-observability` repo | Phase A create | ✓ (does not yet exist — ready to create) | — | — |
| `vitest` (per-stack) | Phase G template test verification | Installed in each stack's `node_modules/` (claude-workflow source) | pinned per template | Must `npm install` in obs repo templates after Phase B |
| `bash` ≥ 3.2 | run-tests.sh shim | ✓ | system (macOS) | — |
| `python3` + `pyyaml` | preflight audit in run-tests.sh | ✓ (macOS system python3; pyyaml likely available) | — | Non-strict mode degrades gracefully |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:**
- `python3/pyyaml` for preflight audit: if absent, non-strict mode skips audit gracefully. Do not enable `--strict-preflight` in Phase G until confirmed available.

---

## Validation Architecture

> Nyquist validation is ENABLED (key absent from config.json = treated as enabled).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash (migrations/run-tests.sh) + vitest (per-stack template tests) |
| Config file | migrations/run-tests.sh (new obs repo — Wave 0 gap) |
| Quick run command | `bash migrations/run-tests.sh 0019` or `bash migrations/run-tests.sh 0021` |
| Full suite command | `bash migrations/run-tests.sh` |

### Phase Deliverables → Verification Map

| Deliverable | Verification | Automated Command | Exists? |
|-------------|-------------|-------------------|---------|
| New repo created + submodule | `gh repo view` + `git submodule status` | `gh repo view agenticapps-eu/agenticapps-observability --json url,visibility && git submodule status` | ❌ Wave 0 (repo doesn't exist yet) |
| History preserved — SKILL.md | `git log --follow` on moved files | `git log --follow --oneline -- SKILL.md \| head -5` | ❌ Wave 0 |
| History preserved — migration scripts | `git log --follow` on migrate-0019.sh | `git log --follow --oneline -- migrations/scripts/migrate-0019.sh \| head -3` | ❌ Wave 0 |
| 0019 fixture suite GREEN (13 fixtures) | run-tests.sh filter | `bash migrations/run-tests.sh 0019` → PASS=13 | ❌ Wave 0 |
| 0021 fixture suite GREEN (4 fixtures) | run-tests.sh filter | `bash migrations/run-tests.sh 0021` → PASS=4 | ❌ Wave 0 |
| 0022 fixture suite GREEN (new) | run-tests.sh filter | `bash migrations/run-tests.sh 0022` → GREEN | ❌ Wave 0 |
| Drift test PASSES | run-tests.sh | `bash migrations/run-tests.sh` → drift PASS | ❌ Wave 0 |
| SKILL.md name = observability | grep | `grep "^name: observability" SKILL.md` | ❌ Wave 0 |
| SKILL.md version = 0.11.0 | grep | `grep "^version: 0.11.0" SKILL.md` | ❌ Wave 0 |
| `/observability *` resolves | symlink check | `test -L ~/.claude/skills/observability && test -f ~/.claude/skills/observability/SKILL.md` | ❌ Wave 0 |
| `/add-observability *` resolves | symlink check | `test -L ~/.claude/skills/add-observability && test -f ~/.claude/skills/add-observability/SKILL.md` | ❌ Wave 0 |
| Strict-Env generic preserved (SC5) | vitest typecheck | `cd templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts` | ❌ Wave 0 |
| Immediate-flush regression test (cron-flush) | vitest | `cd templates/ts-cloudflare-worker && npx vitest run cron-monitor.test.ts` (new test case) | ❌ Wave 0 |
| cf-workflow claude-workflow baseline UNCHANGED | run-tests.sh in claude-workflow | `bash migrations/run-tests.sh` → PASS=186 FAIL=4 | ✅ (claude-workflow baseline confirmed) |

### Wave 0 Gaps (new obs repo infrastructure)

- [ ] `migrations/run-tests.sh` — obs shim (source-and-keep, obs-specific SKILL.md path)
- [ ] `migrations/0022-explicit-flush-and-monitor-config.md` — new migration doc
- [ ] `migrations/test-fixtures/0022/` — fixture directories for new migration
- [ ] `legacy/SKILL.md` — deprecation alias SKILL.md
- [ ] `install.sh` — dual-symlink install script
- [ ] `vitest` available per-stack: `cd templates/ts-cloudflare-worker && npm install`

### Sampling Rate

- **Per task commit:** `bash migrations/run-tests.sh <migration_id>` (filter to current migration under test)
- **Per wave merge:** `bash migrations/run-tests.sh` (full suite)
- **Phase gate:** Full suite green + `/observability *` + `/add-observability *` both resolve + `git log --follow` verified on 3+ moved files before `/gsd-verify-work`

---

## Security Domain

> security_enforcement: not explicitly set in config.json = ENABLED.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | n/a (no auth layer in a scaffolder skill) |
| V3 Session Management | No | n/a |
| V4 Access Control | No (repo is private) | GitHub org access control |
| V5 Input Validation | Yes (migration scripts) | Shell parameter quoting; heredoc for untrusted content |
| V6 Cryptography | No | n/a |

### Known Threat Patterns for bash migration scripts

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal in fixture dirs | Tampering | Use `$REPO_ROOT`-anchored paths; never eval user-supplied paths |
| Sandbox escape (scripts writing to real $HOME) | Elevation | Grep install script for hardcoded /Users/... paths (codex F1 pattern from claude-workflow run-tests.sh 0006) |
| Command injection via file content | Tampering | Quote all shell variables; never `eval` migration markdown content |
| Accidental `--force` push to main | Elevation | Phase H is user-gated (`autonomous: false`); use `git push origin main` not `--force` after the initial repo creation push |

### Specific to this phase: install.sh symlink clobbering

The obs `install.sh` may clobber an existing real directory at `~/.claude/skills/add-observability` or `~/.claude/skills/observability` if a user has installed a different version there. Mirror claude-workflow's clobber check:
```bash
if [ -e "$link" ] && [ ! -L "$link" ]; then
  echo "  ✗ $link exists and is NOT a symlink — refusing to clobber."
  FAILED=$((FAILED + 1))
  continue
fi
```
[VERIFIED: install.sh lines 88-95 implement this check]

---

## Sources

### Primary (HIGH confidence)
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/.planning/phases/29-split-02-agenticapps-observability/29-CONTEXT.md` — locked decisions, scope, cross-repo constraints
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/SPLIT-02-agenticapps-observability.md` — full A-H execution plan, exact commands, layout
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/RESEARCH-cron-monitor-flush-fxsa.md` — SDK internals proof, canonical withCronMonitor draft body, test impact analysis
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/.planning/phases/28-split-01-agenticapps-shared/28-VERIFICATION.md` — SPLIT-01 precedent, all 9 observable truths verified
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/migrations/run-tests.sh` lines 1-136 — exact source-and-keep + BASH_SOURCE pattern [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/install.sh` — symlink + submodule wiring pattern [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/.gitmodules` — submodule URL + path [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/vendor/agenticapps-shared/migrations/lib/drift-test.sh` — `run_drift_test(skill_md, migrations_dir)` API [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/vendor/agenticapps-shared/migrations/lib/fixture-runner.sh` — `extract_to` API [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/vendor/agenticapps-shared/migrations/lib/preflight.sh` — `run_preflight_verify_paths` API [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/add-observability/SKILL.md` — current frontmatter + dispatch table [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/add-observability/templates/ts-cloudflare-worker/cron-monitor.ts` — current Guarded Shape A body [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/add-observability/templates/ts-cloudflare-worker/cron-monitor.test.ts` — 22-test suite structure [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/add-observability/templates/ts-cloudflare-worker/queue-monitor.ts` — Guarded Shape A queue wrapper [VERIFIED]
- `/Users/donald/Sourcecode/agenticapps/claude-workflow/migrations/test-fixtures/0021/04-callbot-shape-strict-env-typecheck/types.d.ts` — relaxed MonitorConfig stub (#61) [VERIFIED]
- All migration headers 0011–0021 — ownership classification [VERIFIED by inspection]
- `bash migrations/run-tests.sh 0017` — 4 known failing tests confirmed (fixtures 02, 06, 10, 11) [VERIFIED live run]

### Secondary (MEDIUM confidence)
- `gh api orgs/agenticapps-eu/members/<user>` — org membership confirmed [VERIFIED live]
- `gh repo view agenticapps-eu/agenticapps-shared` — shared repo exists, private [VERIFIED live]
- `gh repo view agenticapps-eu/agenticapps-observability` — does NOT exist [VERIFIED live]
- `git-filter-repo` at `/opt/homebrew/bin/git-filter-repo` version a40bce548d2c [VERIFIED live]

### Tertiary (LOW confidence)
- A1: `--path-rename` exact syntax [ASSUMED — verify with `git-filter-repo --help`]
- A2/A3: Claude Code skill loader one-level-deep resolution + relative-path routing from alias [ASSUMED from install.sh comment]

---

## Metadata

**Confidence breakdown:**
- Migration ownership audit: HIGH — verified all migration headers
- Standard stack (filter-repo, gh, submodule): HIGH — verified installed
- Architecture patterns (source-and-keep, dual-symlink): HIGH — verified from SPLIT-01 precedent + current install.sh
- Deferred-fix migration shape: HIGH — canonical draft in RESEARCH-cron; test suite structure verified in cron-monitor.test.ts
- filter-repo exact flag syntax: MEDIUM (confirmed installed; flag names assumed from training data)
- Skill loader resolution: MEDIUM (confirmed by install.sh comment; not directly tested)

**Research date:** 2026-06-02
**Valid until:** 2026-07-02 (stable tooling; 30 days reasonable)
