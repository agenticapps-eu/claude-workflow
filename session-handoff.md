# Session Handoff — 2026-07-06 (spec §15 knowledge capture → PR #78, v2.3.0)

## Accomplished
- **Implemented core spec §15 (knowledge capture) in the reference host → PR #78** on branch `feat/knowledge-capture` (commit `f556f63`, base main). Prerequisite (core spec v0.7.0 + core ADR-0017) was already merged in `agenticapps-workflow-core`.
- **Skill wiring:** `skill/SKILL.md` (+ snapshot copy) gained `## Knowledge Capture — Ritual Tail (spec §15)` — final step of the three rituals (session handoff / plan completion / phase completion); destination read from `.planning/config.json → knowledge_capture` at trigger time; graceful skip (block absent, `enabled:false`, vault folder missing → one info line, never mkdir); 1–5 transferable learnings with write-nothing-if-nothing-qualifies; embedded first-write skeleton; append-only Log + curated Key Learnings; vault-safety rules. Version → **2.3.0**.
- **Config seeding:** `templates/config-hooks.json` seeds the block with a literal `<repo-name>` placeholder; `setup/SKILL.md` Step 4d resolves it via `basename $(git rev-parse --show-toplevel)` at install time; Step 5 post-checks resolution.
- **Migration 0025** (2.2.0 → 2.3.0): inserts the block only if missing (user opt-outs/custom notes preserved verbatim; creates config if absent) and appends the section by **extracting it from the scaffolder's `skill/SKILL.md`** (single source of truth — no heredoc duplicate). 4 fixtures (insert-and-wire, preserve-existing-block, idempotent-reapply, create-config-when-absent) + `test_migration_0025` + dispatcher entry in `run-tests.sh`.
- **Drift guard:** `check-snapshot-parity.sh` §7 (snapshot SKILL carries section + all three triggers + config-routed destination; §6 style) and §3 extension (block shape; placeholder must remain in the SEED). Snapshot rebuilt via `build-snapshot.sh`.
- **Docs:** ADR-0038 (references core ADR-0017; records that `implements_spec` stays 0.4.0 pending a full conformance audit), standards checklist line, `templates/obsidian-learnings-note.md`, CHANGELOG `[2.3.0]`, MANIFEST rows.
- **Green:** `run-tests.sh` **160 PASS / 0 FAIL** (incl. 0025 fixtures + version coupling at 2.3.0); `check-snapshot-parity.sh` PASS; `build-snapshot.sh --check` OK; `gitnexus detect_changes` low risk, 0 affected flows.
- **First live §15 exercise:** created `~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/claude-workflow.md` from the skeleton with 4 learnings (log entry `2026-07-06 — handoff`, Key Learnings seeded).

## Decisions
- **Migration appends by extraction, not heredoc.** Step 2 pulls the section from the scaffolder clone's `skill/SKILL.md` (awk heading→EOF), so migrated installs are byte-identical to fresh snapshot installs; pre-flight aborts on a stale clone. Rejected: 0024-style self-contained duplicate (drifts on every skill edit).
- **Placeholder stays literal in the seed.** Parity §3 asserts `<repo-name>` is still unresolved in `setup/snapshot/planning-config.json`; setup Step 5 asserts it is resolved in the installed project. Two-sided guard.
- **`implements_spec` NOT bumped to 0.7.0** — it tracks the last full conformance audit; §§ from 0.5.0/0.6.0 are unaudited in this host. Recorded in ADR-0038.
- **Skill step, not a hook** — the selectivity bar and Key-Learnings curation are LLM judgment calls; §15 non-requirements explicitly permit skill-step wiring.

## Files modified (27, +963/−6) — see PR #78
New: `migrations/0025-knowledge-capture.md`, `migrations/test-fixtures/0025/*` (common-setup + 4 fixtures), `templates/obsidian-learnings-note.md`, `docs/decisions/0038-knowledge-capture.md`. Modified: `skill/SKILL.md`, `setup/SKILL.md`, `templates/config-hooks.json`, `migrations/run-tests.sh`, `migrations/check-snapshot-parity.sh`, `setup/snapshot/{agentic-apps-workflow-SKILL.md,planning-config.json,VERSION,MANIFEST.md}`, `docs/standards/gsd-binding-and-planning.md`, `CHANGELOG.md`.

## Next session: start here
**PR #78 is MERGED to main** (merge commit `31298ad`; CI `migrations-and-snapshot` passed) and the scaffolder clone at `~/.claude/skills/agenticapps-workflow` is already fast-forwarded to 2.3.0 (see [[local-scaffolder-clone]]) — migration 0025's extraction pre-flight is satisfied fleet-wide. Start directly with Prompt 3 of the rollout: mirror §15 in `codex-workflow` (and later `opencode-workflow`) per ADR-0038's downstream note — config seed + three trigger points + graceful skip, host tag `(codex)`/`(opencode)` in log headings.

## Open questions / loose ends
- **claude-workflow's own `.planning/config.json` does not carry the `knowledge_capture` block** — this session wrote the vault note per the task prompt, not via config. If the scaffolder repo itself should be opted in, add the block (note: `.../claude-workflow.md`) in a follow-up.
- **GitNexus FTS v41/v40 build skew persists** (see [[gitnexus-fts-version-skew]]); index also reports stale (last indexed `574eed4`). MCP `detect_changes` works; re-run `node .gitnexus/run.cjs analyze` after merge if needed.
- Non-blocking: CHANGELOG still has no `[2.1.0]` entry (0023 skipped it); optional backfill.
