# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [1.9.0] — Unreleased

### Added

- **Post-processor for inlined GSD section markers** — new POSIX bash 3.2+ script `templates/.claude/hooks/normalize-claude-md.sh` walks CLAUDE.md and rewrites every `<!-- GSD:{slug}-start source:{label} -->...<!-- GSD:{slug}-end -->` block into a 3-line self-closing reference (`<!-- GSD:{slug} source:{label} /-->` + `## {Heading}` + `See [`{path}`](./{path}) — auto-synced.`). Resolves `source:` labels to actual `.planning/`-rooted file paths. Idempotent. Source-existence-safe (preserves blocks with missing sources). Special-cases the `workflow` block (removed entirely once 0009's `.claude/claude-md/workflow.md` exists) and the `profile` block (no `source:` attr; emits `/gsd-profile-user` placeholder). Collapses 2+ consecutive blanks to 1 (mirrors gsd-tools' own normalization).
- **PostToolUse hook registration** — `templates/claude-settings.json` gains "Hook 6 — Normalize CLAUDE.md after Edit/Write (migration 0010)" matching `Edit|Write|MultiEdit`. Defends against future `gsd-tools generate-claude-md` invocations that would re-inflate the marker blocks.
- **Migration `0010-post-process-gsd-sections.md`** — promotes 1.8.0 → 1.9.0 by vendoring the post-processor into consumer projects, registering the PostToolUse hook in `.claude/settings.json` (jq-based insert with hand-edit fallback), and one-shot normalizing existing CLAUDE.md with user-confirmed diff preview. 4 steps; each ships with idempotency check + rollback.
- **ADR 0022** — Post-process GSD section markers via downstream hook (not upstream patch). Documents the source-identification finding (`gsd-tools generate-claude-md` from `~/.claude/get-shit-done/`, owned by upstream `pi-agentic-apps-workflow` family), the post-processor-vs-upstream-patch trade-off, the 0009/0010 boundary (disjoint marker shapes — no regex overlap), and the `--auto` recommendation for users running `gsd-tools` directly.
- **Hand-built test fixtures for migration 0010** — `migrations/test-fixtures/0010/` with 5 pair-shaped scenarios (`fresh` no-op, `inlined-7-sections` full normalization, `inlined-source-missing` safety preservation, `with-0009-vendored` 0009 coexistence, `cparx-shape` ≤200L line-count target). Unlike 0009's fixtures (idempotency-check-only), 0010's harness actually runs the script and diffs against expected goldens.
- **`test_migration_0010()` stanza** added to `migrations/run-tests.sh` — 7 assertions covering all 5 fixtures plus idempotency double-run and missing-input exit code. Diverges from 0001/0009's SKIP-on-missing pattern: 0010 FAILs the harness when the script is absent, because the script IS the migration's artifact under test.

### Notes

- **cparx-shape fixture** (~339L representative input) normalizes to 147L — well under the ≤200L target.
- **Real cparx (647L)** end-to-end projection: 647 → 0009 → ~496L → 0010 → ~270L. The remaining ~70L gap to the user's stated ~165L target is non-GSD content (gstack skill table, anti-patterns list, repo-structure ASCII diagram, project-specific notes — ~232L of non-marker content). Closing the gap requires a follow-up phase trimming non-GSD content; out of scope for 0010.
- **Upstream patch recommended as follow-up** — ADR 0022 captures the rationale for shipping the downstream post-processor first while leaving a TODO for an upstream PR to `pi-agentic-apps-workflow` adding a `--reference-mode` flag to `gsd-tools generate-claude-md`. After upstream lands, 0010's post-processor becomes defense-in-depth.

## [1.8.0] — Unreleased

### Added

- **Vendored CLAUDE.md workflow block** — `templates/.claude/claude-md/workflow.md` is the new canonical location for the Superpowers/GSD/gstack hooks, commitment ritual, rationalization table, and 13 Red Flags. Each consumer project gets `<repo>/.claude/claude-md/workflow.md` vendored on first install (via patched migration 0000) or on upgrade (via migration 0009). CLAUDE.md links to that path with a 5-line reference block instead of inlining ~150 lines. Self-contained — repo never references the meta-repo at runtime.
- **ADR 0021** — Vendor the workflow block as a per-repo file instead of inlining it into CLAUDE.md. Documents the inline → vendor pivot, alternatives rejected (symlink, runtime fetch, `@import`), and why the meta-repo is never referenced at runtime. Captures the "patch 0000 in-place" decision that lets fresh installs go straight to vendored state.
- **Migration `0009-vendor-claude-md-sections.md`** — promotes 1.7.0 → 1.8.0 by vendoring the workflow block, adding a reference to CLAUDE.md, and detecting + (with user confirmation) extracting any pre-existing inlined block. Three-way pick on customised inlined blocks: replace-with-canonical / preserve-as-vendored / skip. Five steps; each ships with idempotency check + rollback.
- **Hand-built test fixtures for migration 0009** — `migrations/test-fixtures/0009/` with five scenarios (fresh, inlined-pristine, inlined-customised, after-vendored, after-idempotent). 29 assertions cover every step's idempotency check across every scenario. Distinct from migration 0001's git-ref-extracted fixtures because 0009's "pre-existing inlined block" state isn't in claude-workflow's own history.

### Changed

- **Migration `0000-baseline.md` Step 4 patched in-place** — previously `cat`-ed `templates/claude-md-sections.md` directly into CLAUDE.md (the root cause of cparx 646L and fx-signal-agent 372L). Now writes `.claude/claude-md/workflow.md` from the vendored template + appends a 5-line `## Workflow` reference section to CLAUDE.md. Legitimate in-place patch because 0000's pre-flight already refuses re-execution against existing installs. Note in the patched step documents the rationale.
- **`templates/claude-md-sections.md` H1 rewritten** — was `# CLAUDE.md Sections — paste into your project's CLAUDE.md`, which is the literal smoking-gun line found in fx-signal-agent's CLAUDE.md proving the file was pasted verbatim. New H1 (`# DEPRECATED — vendored as .claude/claude-md/workflow.md since v1.8.0`) carries a "do not paste" banner and explains migration 0009's detection logic. The file is retained for migration 0009's grep-detection of pre-existing pastes in older repos.
- **`setup/SKILL.md`** — post-setup summary now lists `.claude/claude-md/workflow.md` as a created file. Migration history table updated with 0002, 0004–0007, and 0009 entries (was stale at 0001). Notes the v1.8.0 vendor-mode pivot.
- **`update/SKILL.md` Step 5** — adds a "divergence variant" of the per-step Apply prompt: when a vendored file's local copy byte-differs from the canonical scaffolder source, present a 3-way pick (Replace / Keep / Vendor-local). Default to Keep (diverging is usually intentional). Failure modes table extended with vendored-file divergence and inlined-block extraction-ambiguous outcomes.
- **`migrations/README.md`** — added a Migration index table near the top showing the current chain and the v1.8.0 vendor-mode property of 0000.
- **`skill/SKILL.md`** frontmatter version bumped 1.7.0 → 1.8.0.
- **`migrations/run-tests.sh`** — added `test_migration_0009()` stanza (29 assertions). Existing `test_migration_0001()` kept as-is; its 8 pre-existing FAILs (caused by `git merge-base` resolving to a post-0001-merge commit) are unrelated to this phase and tracked separately.

### Notes

- **fx-signal-agent** drops from 372 lines to ~201 after applying migration 0009 (the inlined block extraction is the single largest reduction).
- **cparx** drops from 646 lines to ~496 after migration 0009. Getting it ≤200L requires migration 0010 (GSD compiler reference-mode for auto-managed PROJECT/STACK/CONVENTIONS/ARCHITECTURE sections), queued as a separate phase. ADR 0021 records why 0010 is not bundled into this release.
- Existing 1.7.0 projects pick up the fix via `/update-agenticapps-workflow`; the migration runtime walks them through the inlined-block extraction prompt with diff preview.

## [1.7.0] — Unreleased

### Added

- **GitNexus code-knowledge graph integration** — vendor + reference to abhigyanpatwari/GitNexus (npm package `gitnexus`). Multi-repo MCP server backed by `~/.gitnexus/registry.json`. 16 MCP tools (impact analysis, 360-degree symbol view, call-chain trace, etc.), 7 per-repo skills, PreToolUse and PostToolUse hooks for graph-enriched grep/read and post-commit stale detection. Auto-generates a `gitnexus:start/end` block into each indexed repo's CLAUDE.md/AGENTS.md.
- **ADR 0020** — GitNexus code-graph integration. Documents why GitNexus over Graphify (multi-repo registry wins for our 50-repo polyrepo), the PolyForm Noncommercial 1.0 license trade-off (internal development use is fine, commercial embedding requires akonlabs.com license), and the relationship to migrations 0005–0008.
- **Migration `0007-gitnexus-code-graph-integration.md`** — promotes 1.6.0 → 1.7.0 by installing gitnexus globally, running `gitnexus setup` for MCP wiring, indexing active family repos via `gitnexus analyze`. Pre-flight requires node ≥ 18. Per-family scoped via the helper script `~/Sourcecode/gitnexus-index-all.sh`.
- **Helper script** `~/Sourcecode/gitnexus-index-all.sh` — iterates through `agenticapps/`, `factiv/`, `neuroflash/` and runs `gitnexus analyze` per repo. Supports `--family <name>`, `--all`, and a curated "active development" default. Skips `personal/`, `shared/`, `archive/`.

### Changed

- `skill/SKILL.md` frontmatter version bumped 1.6.0 → 1.7.0.

### Notes

- Three-layer knowledge architecture is now in place: wiki (decision/doc knowledge, migration 0006), GitNexus (code-structure knowledge, this migration), multi-AI plan review (workflow contract, migration 0005). Migration 0008 (dashboard coverage matrix) is queued as the visibility layer over all three.

## [1.6.0] — Unreleased

### Added

- **LLM wiki compiler integration** — vendored `ussumant/llm-wiki-compiler` v2.1.0 plugin into `agenticapps/wiki-builder/`. Implements Andrej Karpathy's LLM Knowledge Base pattern: per-family `.wiki-compiler.json` declares source directories; `/wiki-compile` produces a topic-based Obsidian-compatible wiki at `<family>/.knowledge/wiki/`. 12 slash commands available after install: `wiki-init`, `wiki-compile`, `wiki-lint`, `wiki-query`, `wiki-search`, `wiki-visualize`, `wiki-capture`, `wiki-ingest`, `wiki-migrate`, `wiki-upgrade`, `wiki-global-init`, `fetch-bookmarks`. Plugin supports both Claude Code and Codex via dual `.claude-plugin/` and `.codex-plugin/` manifests.
- **ADR 0019** — LLM wiki compiler integration. Documents why this plugin over alternatives (nvk/llm-wiki, rvk7895/llm-knowledge-bases, Pinecone Nexus, GraphRAG/LightRAG/HippoRAG), why per-family rather than per-repo, why vendor instead of npm-install, and why `.wiki-compiler.json` superseded the sources.yaml manifest design from migration 0005.
- **Migration `0006-llm-wiki-builder-integration.md`** — promotes 1.5.1 → 1.6.0 by symlinking the plugin into `~/.claude/plugins/`, validating per-family configs exist, and bumping skill version. Idempotent. Pre-flight verifies the vendored plugin is present.
- **Per-family `.wiki-compiler.json`** created for agenticapps, factiv, neuroflash. Source directories listed per family. `topic_hints` and `article_sections` customized per domain.

### Changed

- `skill/SKILL.md` frontmatter version bumped 1.5.1 → 1.6.0.
- Per-family CLAUDE.md (in `~/Sourcecode/<family>/`, not in claude-workflow) updated with `/wiki-*` slash command reference block.
- `.knowledge/sources.yaml` files from migration 0005 renamed to `sources.yaml.legacy` — kept as design-intent reference, not read by the compiler. Active config is `.wiki-compiler.json` at family root.

## [1.5.1] — Unreleased

### Added

- **Hook 6 — Multi-AI Plan Review Gate** (`.claude/hooks/multi-ai-review-gate.sh`, PreToolUse: `Edit|Write`). Blocks code-touching edits during a phase if `*-PLAN.md` files exist but `*-REVIEWS.md` does not. Closes the drift pattern observed in cparx phases 04.9 → 05 where `/gsd-review` was silently skipped for 8 consecutive phases. Override surfaces: `GSD_SKIP_REVIEWS=1` env var (session-scoped, no on-disk trace) or `touch .planning/current-phase/multi-ai-review-skipped` (phase-scoped, committed sentinel for audit).
- **ADR 0018** — Multi-AI plan review enforcement. Documents the failure mode (eight cparx phases without REVIEWS.md), the three coordinated remedies (hook + contract entry + conceptual layer update), and the override surface.
- **Migration `0005-multi-ai-plan-review-enforcement.md`** — promotes projects from 1.5.0 to 1.5.1 by installing hook 6, wiring `.claude/settings.json`, bumping skill version. Idempotent. Pre-flight checks that `/gsd-review` is installed and that ≥2 reviewer CLIs are available on the host.

### Changed

- `docs/ENFORCEMENT-PLAN.md` — Phase planning gates table now includes a `/gsd-review` row with `{padded_phase}-REVIEWS.md` as required evidence.
- `templates/config-hooks.json` — new `pre_execute_gates.multi_ai_plan_review` entry between per_plan and post_phase, citing ADR 0018.
- `skill/SKILL.md` — 13 Red Flags → 14 Red Flags (new entry at position 8: "`/gsd-review` skipped — no `{phase}-REVIEWS.md` artifact"). Rationalization table gains a new row anticipating the "just one model is fine" excuse. Verification check (post-phase grep) extended to confirm REVIEWS.md presence in addition to REVIEW.md Stage 2.
- `skill/SKILL.md` frontmatter version bumped 1.5.0 → 1.5.1.

### Audit

- cparx `.planning/phases/`: REVIEWS.md present in 6/16 phases; missing in 10/16 including the entire 05-handover. Backfill is optional and out of scope for this migration — the hook gates new edits, not old artifacts.
- fx-signal-agent `.planning/phases/`: REVIEWS.md missing in 1/1 phase (01-tenant-model-in-code). Same backfill posture.

## [1.5.0] — Unreleased

### Fixed

- **`.claude/settings.json` is now installed at baseline.** Migration
  `0000-baseline.md` gains a new Step 6 that bootstraps the file as
  `{}` if missing. Previously, no migration in the chain ever created
  it — `migrations/0004-programmatic-hooks-architecture-audit.md`
  asserted its existence at pre-flight but baseline never installed
  it, so any 1.3.0 project trying to update to 1.4.0 hit a hard fail.
  Migration 0004's pre-flight now also self-heals (creates the file if
  missing) as belt-and-braces for older projects baselined before this
  fix. Reported in
  [agenticapps-eu/claude-workflow#8](https://github.com/agenticapps-eu/claude-workflow/issues/8).

### Added

- **`add-observability` skill** — Claude Code implementation of
  AgenticApps core spec §10 v0.2.1 (observability contract). Three
  subcommands:
  - `init` — greenfield: scaffold the wrapper module + middleware into
    each detected stack.
  - `scan` — brownfield: audit conformance against §10.4 mandatory
    instrumentation points; produce `.scan-report.md` with findings
    classified high / medium / low confidence.
  - `scan-apply` — apply high-confidence gaps with **per-file or
    per-batch consent in chat** (§10.7 fourth bullet). Edit-tool
    content-matching is the safety net; stale findings flagged for
    re-scan rather than fuzzy-merged.
- **Five stack templates** ship with the skill at
  `add-observability/templates/`:
  - `ts-cloudflare-worker` (Workers fetch / scheduled / queue handlers)
  - `ts-cloudflare-pages` (Pages Functions; inherits worker wrapper)
  - `ts-supabase-edge` (Deno; uses `npm:@sentry/deno`)
  - `ts-react-vite` (browser; module-level span stack +
    `ObservabilityErrorBoundary` for React)
  - `go-fly-http` (chi / std net/http; `context.Context` propagation)
- **61 contract tests across 4 runtimes** ship with the templates and
  pass against materialized-from-template wrappers (vitest+jsdom for
  TS, deno test for Deno, go test for Go).
- **Migration `0002-observability-spec-0.2.1.md`** — installs the skill
  on `/update-agenticapps-workflow` for projects on 1.4.x. Steps:
  install skill, bump version, add `/add-observability` reference to
  CLAUDE.md. Non-destructive — does not instrument any source code;
  the user explicitly invokes `init` / `scan-apply` afterward.

### Spec context

- This release implements AgenticApps core spec §10 v0.2.1.
  v0.2.1 patches over v0.2.0:
  - §10.5 — added a note clarifying interaction with framework-level
    recoverer middleware (mount inside Recoverer).
  - §10.7.1 — clarified that target paths resolve against the
    *language module root* (`go.mod`, `package.json`, `Cargo.toml`,
    `supabase/config.toml`), not the repo root. Supports monorepos and
    non-root manifests (e.g. cparx's `backend/go.mod`).
- The spec text itself lives in the (still-pending) `agenticapps-workflow-core` repo;
  this release ships the implementation that satisfies it. The skill's
  `SKILL.md` declares `implements_spec: 0.2.1` for forward-compat
  conformance tracking.

### Pilot

- **cparx pilot (2026-05-10)** validated the templates end-to-end
  against the cparx Go backend. `go build ./...`, `go vet ./...`, and
  the existing test suite all passed after the templates were applied.
  Six gaps surfaced and were resolved in v0.2.1 (G1 module-root
  resolution, G2 transport composition for custom RoundTrippers, G4
  recoverer ordering, G6 contract test fixtures shipping with each
  template). G3 detached-goroutine instrumentation and G5 RequestID
  coexistence deferred to v0.3.0+. Pilot artifacts live in the design
  folder; the cparx adoption itself happens via the project's own
  feature-branch + GSD workflow.

### Changed

- `skill/SKILL.md` frontmatter version bumped 1.4.0 → 1.5.0.

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
