# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

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
