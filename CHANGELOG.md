# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.0] — 2026-05-03

### Added

- **Programmatic hooks layer (5 hooks)** — deterministic enforcement at
  the tool-call boundary. Complements (does not replace) the conceptual
  CLAUDE.md prose layer. Closes the "prose degrades on compaction"
  failure mode that Sah and Damle's articles identify.
  - **Hook 1 — Database Sentinel** (`PreToolUse: Bash|Edit|Write`) —
    blocks `DROP/TRUNCATE TABLE`, `DELETE FROM` without `WHERE`, edits
    to `.env*`, edits to `migrations/*` without phase approval.
  - **Hook 2 — Design Shotgun Pre-Flight Gate** (`PreToolUse:
    Edit|Write`) — blocks design-surface edits without
    `.planning/current-phase/design-shotgun-passed` sentinel.
  - **Hook 3 — Phase Sentinel** (`Stop`, prompt-type, Haiku 4.5) —
    compares `.planning/current-phase/checklist.md` against the
    conversation; blocks `Stop` if items remain unchecked.
  - **Hook 4 — Skill Router Audit Log** (`PostToolUse` + `SessionStart`) —
    JSONL log of every skill invocation to
    `.planning/skill-observations/skill-router-{date}.jsonl`; warm
    context on each new session via tail-20.
  - **Hook 5 — Commitment Re-Injector** (`SessionStart matcher: compact`,
    GLOBAL) — re-injects `head -50 CLAUDE.md` + current-phase
    `COMMITMENT.md` after compaction. cwd-aware: no-ops on non-AgenticApps
    projects.
  - 43 bats tests across 4 hook test files; all green. `bin/check-hooks.sh`
    validates installation.
- **Architecture audit scheduling** — two complementary mechanisms with
  shared snooze contract:
  - **In-session SessionStart hook** (`templates/.claude/hooks/architecture-audit-check.sh`)
    nags when last audit > 7 days. Honors
    `.planning/audits/.snooze-until-{YYYY-MM-DD}` markers.
  - **Out-of-session weekly cron** (`bin/agenticapps-architecture-cron.sh`)
    Mondays 09:00 local. Reads `~/.agenticapps/dashboard/registry.json`
    `tags: ["active"]` (heuristic fallback for empty registry). Files
    Linear issues with reminder, falls back to log file.
  - Two installers: `bin/install-architecture-cron.sh` (macOS LaunchAgent)
    and `bin/install-systemd-architecture-cron.sh` (Linux systemd-user).
  - Plist + systemd unit templates with `{SCAFFOLDER_BIN}` / `{HOME}`
    placeholders that installers `sed`-substitute.
- **Mattpocock skills installed** — `mattpocock-improve-architecture` +
  `mattpocock-grill-with-docs` cloned from upstream into
  `~/.claude/skills/`. Closes the cross-PR architectural drift gap.
- **`templates/gsd-patches/`** — mirror of the rogs.me-style canonical
  patch storage at `~/.config/gsd-patches/`. Cross-machine
  reproducibility: clone scaffolder → copy → `bin/sync` to apply patches
  to the live `~/.claude/get-shit-done/` install.
- **GSD bug fix** — `~/.claude/get-shit-done/workflows/review.md:169`
  patched to strip `2>/dev/null` from the `opencode run` invocation
  (rogs.me's Bug 1). Bug 2 (`--no-input` flag) not present in this
  install. Bug 3 (sequential reviewers) skipped to respect upstream's
  explicit "(not parallel — avoid rate limits)" comment.
- **`migrations/0004-programmatic-hooks-architecture-audit.md`** —
  applies hooks + settings merge + version bump to v1.3.0 projects via
  `/update-agenticapps-workflow`.
- **4 new ADRs:** 0014 (GSD bug fixes), 0015 (programmatic hooks layer),
  0016 (mattpocock architecture audit), 0017 (audit scheduling).

### Changed

- **`templates/claude-settings.json`** — added entries for Hooks 1–4 +
  architecture-audit-check (5 entries total). Hook 5 is global,
  not project-scoped.
- **`docs/ENFORCEMENT-PLAN.md`** — new "Two-layer enforcement:
  programmatic + conceptual" section between Finishing gates and the
  Commitment ritual. Documents the split rule, lists all 6 hooks,
  points at `bin/check-hooks.sh`.
- **`skill/SKILL.md`** version bumped 1.3.0 → 1.4.0.

### Migration path for existing projects (v1.3.0 → v1.4.0)

```bash
# 1. Pull the latest scaffolder + re-run install.sh (in case new skill
#    subdirs were added; v1.4.0 didn't add any but the discipline holds)
cd ~/.claude/skills/agenticapps-workflow && git pull && ./install.sh && cd -

# 2. Install mattpocock skills (required by 0004 pre-flight)
git clone https://github.com/mattpocock/skills /tmp/mattpocock-skills
mkdir -p ~/.claude/skills/mattpocock-improve-architecture ~/.claude/skills/mattpocock-grill-with-docs
cp -r /tmp/mattpocock-skills/skills/engineering/improve-codebase-architecture/. ~/.claude/skills/mattpocock-improve-architecture/
cp -r /tmp/mattpocock-skills/skills/engineering/grill-with-docs/. ~/.claude/skills/mattpocock-grill-with-docs/

# 3. Preview, then apply
cd <your-project>
claude "/update-agenticapps-workflow --dry-run"
claude "/update-agenticapps-workflow"

# 4. Install Hook 5 (Commitment Re-Injector) GLOBALLY (one-time per machine)
cp ~/.claude/skills/agenticapps-workflow/templates/global-hooks/commitment-reinject.sh \
   ~/.claude/hooks/commitment-reinject.sh 2>/dev/null \
  || echo "TODO: Hook 5 will live at templates/global-hooks/ once setup-skill installs it; for now copy from your local Claude Code session that ran P2A"
chmod +x ~/.claude/hooks/commitment-reinject.sh
# Then add SessionStart matcher: compact entry to ~/.claude/settings.json

# 5. Install the weekly cron (optional but recommended)
~/.claude/skills/agenticapps-workflow/bin/install-architecture-cron.sh   # macOS
# OR
~/.claude/skills/agenticapps-workflow/bin/install-systemd-architecture-cron.sh   # Linux
```

### Removed

Nothing. v1.4.0 is purely additive.

## [1.3.0] — 2026-05-03

### Added

- **Backend language routing for Go** — phases that touch `*.go` files
  auto-trigger `samber:cc-skills-golang` (40+ Go skills with measured eval
  data) and `netresearch:go-development-skill` (production resilience
  patterns: retry/backoff/graceful-shutdown/observability). Per-project
  install — non-Go repos don't pay the context cost. See README
  § "Per-language skill packs."
- **`impeccable:critique` as pre-phase design gate** — runs after
  `gstack:/design-shotgun`, scores each variant against ~24 AI-slop
  anti-patterns, eliminates sub-bar variants before the user picks. Score
  recorded in UI-SPEC.md.
- **`impeccable:audit` as finishing gate** — runs against deployed
  frontend before branch close. Red findings BLOCK close.
- **`database-sentinel:audit` as security sub-gate** — fires under existing
  `gstack:/cso` when the phase touches Supabase / Postgres / MongoDB.
  Output: `DB-AUDIT.md`. Critical / High findings BLOCK branch close
  unless accepted via the new `templates/adr-db-security-acceptance.md`
  ADR template.
- **`database-sentinel:audit` (full-surface) as pre-launch finishing gate**
  — runs before any AgenticApps client app goes live. Zero Critical / zero
  High required to clear.
- **Versioned migration framework** — `migrations/` directory holds
  numbered migration files (`NNNN-slug.md`) with frontmatter, idempotency
  checks, pre-conditions, apply blocks, and per-step rollback. Each
  migration brings projects from one version to the next non-destructively.
- **`update-agenticapps-workflow` skill** — applies pending migrations to
  an installed project. Detect installed version → find pending → show
  plan → pre-flight (skill installs) → apply each step (idempotency /
  diff / confirm / apply / commit) → summary. Supports `--dry-run`,
  `--migration N`, `--from V` flags.
- **`setup-agenticapps-workflow` skill REWRITTEN** — now applies all
  migrations from `0000-baseline.md` forward. Eliminates the previous
  "setup and any future update would maintain divergent shapes" code-path
  bug. Setup and update share one runtime.
- **`migrations/0000-baseline.md`** — codifies the v1.2.0 starting state
  as a 6-step migration (skill copy, workflow-config substitution, hooks
  config, CLAUDE.md append, optional global CLAUDE.md, version bump).
- **`migrations/0001-go-impeccable-database-sentinel.md`** — codifies
  this release's deltas as a 10-step migration with deterministic `jq`
  apply commands for JSON inserts.
- **`migrations/run-tests.sh`** — TDD test harness using git refs as
  fixtures. Verifies every migration step's idempotency check behaves
  correctly against before-state and after-state. 20/20 PASS for 0001.
- **`docs/decisions/0010..0013`** — four new ADRs documenting the Go
  routing, impeccable, database-sentinel, and migration framework
  decisions with their rejected alternatives.
- **`templates/adr-db-security-acceptance.md`** — standalone ADR template
  for accepting Critical/High `database-sentinel` findings (time-boxed,
  compensating control required, single owner).
- **`skill/SKILL.md` frontmatter `version: 1.3.0`** — installed version
  is now recorded explicitly. `update-agenticapps-workflow` reads this
  field to determine pending migrations.
- **`install.sh`** — bootstraps Claude Code's skill discovery by
  symlinking `skill/`, `setup/`, `update/` subdirectories out to their
  canonical `~/.claude/skills/<name>/` paths. Idempotent. Required after
  initial clone AND after every `git pull` that adds new skill subdirs.
  Fixes a long-standing bug where `/setup-agenticapps-workflow` and the
  new `/update-agenticapps-workflow` weren't actually registered as
  slash commands (the loader scans one level deep; this repo nests
  skills two levels deep for logical grouping). README install steps
  now invoke `install.sh` automatically.

### Changed

- **Pre-Phase Hook 1** in `templates/claude-md-sections.md` — expanded to
  require `impeccable:critique` against each `/design-shotgun` variant
  before the user picks.
- **Post-Phase Hook 8** in `templates/claude-md-sections.md` — expanded to
  require `database-sentinel:audit` when the phase touches supported
  databases. BLOCK on Critical / High unresolved findings.
- **`templates/workflow-config.md`** — added "Backend language routing"
  section; widened `cso` Post-Phase row to name database-sentinel +
  Supabase/Postgres/MongoDB scope + BLOCK semantics.
- **`templates/config-hooks.json`** — added `pre_phase.design_critique`,
  `post_phase.security.sub_gates[]` (with database-sentinel),
  `finishing.impeccable_audit`, `finishing.db_pre_launch_audit`. Schema
  now uses `sub_gates` arrays (new pattern; documented in ENFORCEMENT-PLAN.md).
- **`docs/ENFORCEMENT-PLAN.md`** — new "Language-specific code-quality
  gates" subsection (extension of post-phase Stage 2); new post-phase
  database-sentinel row; new pre-phase impeccable critique row.

### Migration path for existing projects

Projects on v1.2.0 upgrade to v1.3.0 by:

```bash
# Pull the latest scaffolder AND re-run install.sh (idempotent — required
# because v1.3.0 introduces a new update/ skill subdir that needs symlinking)
cd ~/.claude/skills/agenticapps-workflow && git pull && ./install.sh && cd -

# Preview, then apply
cd <your-project>
claude "/update-agenticapps-workflow --dry-run"
claude "/update-agenticapps-workflow"
```

Migration `0001-go-impeccable-database-sentinel.md` handles all 10 deltas
from this release. Pre-flight will prompt to install impeccable +
database-sentinel skills if missing.

### Removed

Nothing. This release is purely additive. All v1.2.0 hooks continue to
fire as before.

## [1.2.0] — Pre-this-release baseline

The starting state codified by `migrations/0000-baseline.md`. Pre-1.3.0
projects have no `version` field in their installed
`.claude/skills/agentic-apps-workflow/SKILL.md`; the `update` skill
prompts for `--from 1.2.0` if it can't auto-detect.
