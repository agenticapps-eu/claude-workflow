# Phase 09 — LLM wiki builder integration

**Migration:** 0006-llm-wiki-builder-integration
**Version bump:** 1.9.1 → 1.9.2
**Date opened:** 2026-05-13
**Predecessor:** Migration 0005 (multi-AI plan review enforcement, 1.9.0 → 1.9.1)
**Decision record:** ADR 0019 — LLM wiki compiler integration
**Goal:** Install the vendored `ussumant/llm-wiki-compiler` plugin globally, scaffold per-family `.knowledge/` directories + `.wiki-compiler.json` configs, so any consumer running `/setup-agenticapps-workflow` or `/update-agenticapps-workflow` from a fresh machine gets the same wiki integration that's already in place locally.

---

## Background

After the Sourcecode reorganization (`~/Sourcecode/{agenticapps,factiv,neuroflash,personal,shared}/`), repositories sit in client families. Each family contains 5-30 repos with their own CLAUDE.md, ADRs, READMEs, and `.planning/` artifacts. Agents entering a repo within a family currently re-derive cross-repo context every session — expensive in tokens, slow, and doesn't compound.

ADR 0019 records the decision to adopt Andrej Karpathy's LLM Knowledge Base pattern via the vendored `ussumant/llm-wiki-compiler` plugin. Per-family compilation: each family directory has a `.wiki-compiler.json` pointing at relevant source directories; `/wiki-compile` from the family root produces a wiki at `<family>/.knowledge/wiki/` that subsequent sessions read instead of re-walking raw files.

**Current local state on this machine:**
- `~/Sourcecode/agenticapps/wiki-builder/` — vendored plugin (cloned 2026-05-12)
- `~/.claude/plugins/llm-wiki-compiler` → symlink into vendored plugin
- `~/Sourcecode/agenticapps/.wiki-compiler.json` — family config
- `~/Sourcecode/agenticapps/.knowledge/{raw,wiki}/` — scaffolded
- `/wiki-compile`, `/wiki-lint`, `/wiki-query`, etc. — slash commands work

The wiki was set up *manually* before the migration framework existed for it. Phase 09 captures that setup as a versioned migration so the same install can be reproduced on a fresh machine or a teammate's environment.

---

## Scope clarification — what changes vs Phase 08

Migration 0005 (just shipped) was **per-project**: a hook script in `.claude/hooks/` and a settings.json entry. Migration 0006 touches **three scope levels** simultaneously:

1. **Host-level** — `~/.claude/plugins/llm-wiki-compiler` symlink (visible to every Claude session on the machine).
2. **Family-level** — `<family>/.wiki-compiler.json` + `<family>/.knowledge/{raw,wiki}/` (visible to every repo in the family).
3. **Per-project** — `.claude/skills/agentic-apps-workflow/SKILL.md` version bump.

The migration framework was designed around per-project state, but precedent exists for host-level operations in migration 0001 (which installs plugins to `~/.claude/plugins/`). Phase 09 follows that precedent.

---

## Scope (must-have for this phase)

1. **Self-contained migration** — fold the `.knowledge/{raw,wiki}/` directory scaffolding (originally drafted as a separate "old 0005" task) directly into migration 0006. No cross-references to non-existent prior migrations. The current 0005 is multi-AI review enforcement, unrelated.

2. **Cleanup stale references** — strike `sources.yaml.legacy` mentions and "Already created by migration 0005" notes from the migration body. Same for ADR 0019.

3. **Pre-flight extension** — verify the vendored plugin exists at `~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json`. If absent, hard-fail with the clone command in the error message (the `requires:` block already does this; just confirm).

4. **Symlink installation** — idempotent. `ln -sfn` handles the symlink-already-exists case. Add an `**Idempotency check:**` marker per the BLOCK-1 lesson from Phase 08.

5. **Per-family config bootstrap** — for each detected family directory (`~/Sourcecode/{agenticapps,factiv,neuroflash}`), if `.wiki-compiler.json` is absent, write a minimal-but-functional config pointing at the canonical source dirs (ADRs, READMEs, CLAUDE.mds, `.planning/`). If the family directory is absent, skip silently (not every machine has all families).

6. **Wiki output dir scaffolding** — `<family>/.knowledge/{raw,wiki}/` plus a `.gitignore` that ignores the compiled wiki (it's a derived artifact).

7. **CLAUDE.md family-level update** — ensure the family's `CLAUDE.md` documents the available slash commands (`/wiki-compile`, `/wiki-lint`, etc.). Use a `<!-- GSD:wiki-start --> ... <!-- GSD:wiki-end -->` block so migration 0010's post-processor can normalize it consistently with the other GSD section markers. Or — since 0010 only normalizes 7 canonical slugs and `wiki` isn't one — skip the marker and just append a `## Knowledge wiki` section with rollback awareness.

8. **Version bump** — `skill/SKILL.md` 1.9.1 → 1.9.2, CHANGELOG `[1.9.2] — Unreleased`.

9. **Test harness** — `test_migration_0006()` stanza in `run-tests.sh` with fixtures covering: plugin-missing pre-flight fail, fresh install on a clean tmp dir, idempotent re-apply, rollback removes symlink (preserves data), family-detection (1, 2, 3 families present), CLAUDE.md update is idempotent.

10. **Phase artifacts** — CONTEXT, RESEARCH, PLAN, 09-REVIEWS (multi-AI dogfood), REVIEW (Stage 1 + Stage 2), SECURITY (CSO), VERIFICATION.

## Won't-do (explicit scope cuts)

- **Compile the wiki for any family in this phase.** That's an `/wiki-compile` invocation — content production, not migration scaffolding. Documented in the Verify step as a post-apply manual action.
- **Modify the vendored plugin itself.** `~/Sourcecode/agenticapps/wiki-builder/plugin/` is read-only from this migration's perspective. If patches are needed, they happen in a separate phase.
- **Migrate `.knowledge/raw/` content.** Users can drop notes there manually; the migration doesn't pre-populate it.
- **Touch host-level `~/.claude/CLAUDE.md`.** That's user-personal config. Migration 0006 only manages family- and project-level state.
- **Bundle GitNexus integration (migration 0007).** That's Phase 10. Each integration ships as its own GSD phase.

## Open questions (resolve before PLAN.md)

| # | Question | Tentative answer |
|---|---|---|
| Q1 | Detect families dynamically (scan `~/Sourcecode/`) or use a hardcoded allowlist? | Detect via `ls -d ~/Sourcecode/*/` and skip non-directories + `personal`/`shared`/`archive`. Hardcoding tomorrow's families is fragile. |
| Q2 | What goes in the minimal `.wiki-compiler.json`? | Match the working `agenticapps/.wiki-compiler.json` shape (version 2, mode "knowledge", sources list with ADRs + READMEs + CLAUDE.mds + `.planning/`). |
| Q3 | Should rollback delete the vendored `wiki-builder/`? | No — it's a sibling repo, possibly with user changes. Rollback only removes the symlink and reverts the version bump. |
| Q4 | Family CLAUDE.md update — append, or wrapped in a GSD-marker block? | Append a `## Knowledge wiki` section + 5-line content block. No GSD marker (the 7 canonical slugs in 0010 don't include `wiki`). Idempotency check: `grep -q '## Knowledge wiki'`. |
| Q5 | What about families that already have a `.wiki-compiler.json` with custom config? | Idempotency-check on file presence (any content) — leave intact. Custom configs win. |

## Decisions resolved (locked, do not relitigate)

- **Self-contained 0006** (Scope #1, #2). No cross-references to a "0005 scaffold step" — that draft assumption is gone. The directory creation, symlink, family configs, and CLAUDE.md update all live in this migration.
- **Per-family `.wiki-compiler.json`** (ADR 0019). Per-repo configs would duplicate CLAUDE.md content. Per-family is the right granularity.
- **Vendored plugin via `~/Sourcecode/agenticapps/wiki-builder/`** (ADR 0019). Symlink into `~/.claude/plugins/` keeps the install discoverable by Claude Code without duplicating bytes.
- **Idempotency: every step has an `**Idempotency check:**` marker** (Phase 08 Stage 2 BLOCK-1 lesson). Re-apply must be a true no-op.
- **Rollback preserves user data** — `.knowledge/` directories and family configs stay in place; only the host symlink and the version bump revert. Phase 08 taught us that destructive rollback creates fear-of-rollback; preservation rollback is friendlier.
- **No PreToolUse hook involved.** This migration installs at apply-time and has zero runtime cost on Edit/Write/MultiEdit. Latency budgets don't apply.

## Dependencies

**Upstream (already shipped):**
- Migration 0000 — `.claude/skills/agentic-apps-workflow/SKILL.md` exists with version field.
- Migration 0005 (just shipped) — scaffolder at 1.9.1.
- Vendored plugin at `~/Sourcecode/agenticapps/wiki-builder/` — pre-flight enforces. If absent, the user must clone first per the `requires:` block.

**External:**
- `ussumant/llm-wiki-compiler` v2.1.0+ at `~/Sourcecode/agenticapps/wiki-builder/plugin/`. Not bundled with the workflow repo; lives as a sibling clone.

**Downstream (this phase enables):**
- Future Phase 10 (migration 0007 — GitNexus code-graph integration) chains 1.9.2 → 1.9.3.
- Carry-over PR #12 loses its 0006 row; only 0007 remains there.

---

## Acceptance criteria (goal-backward inputs for VERIFICATION.md)

- **AC-1** — Migration 0006 body is self-contained: zero references to a non-existent prior migration scaffolding `.knowledge/`. ADR 0019 similarly cleaned.
- **AC-2** — Migration applies cleanly from a 1.9.1-baseline tmp sandbox; idempotent re-apply is a no-op; rollback removes the symlink and reverts version without touching family data.
- **AC-3** — Apply does NOT execute the plugin's code (no `npm install`, no `node`-script invocation). It only creates a symlink + config files + dirs. Compile time is on-demand via `/wiki-compile`.
- **AC-4** — `migrations/run-tests.sh test_migration_0006` covers: plugin-missing pre-flight fail, fresh install, idempotent re-apply, rollback, family-detection (0/1/3 families present), CLAUDE.md update idempotency.
- **AC-5** — Pre-flight surfaces a clear error message + clone command if `~/Sourcecode/agenticapps/wiki-builder/plugin/` is missing.
- **AC-6** — `templates/config-hooks.json` documents the wiki install (informational only — no hook fires for this migration).
- **AC-7** — `skill/SKILL.md` `version: 1.9.2`; `CHANGELOG.md [1.9.2] — Unreleased` section with `### Added` block.
- **AC-8** — `09-REVIEWS.md` produced by multi-AI plan review (codex + gemini). Floor of 2 reviewers met.
- **AC-9** — Stage 1 + Stage 2 + CSO post-execution reviews complete. No BLOCK findings unresolved.
- **AC-10** — Phase 08's gate (`multi-ai-review-gate.sh`) fires on this phase's directory before `09-REVIEWS.md` exists. The dogfood property is preserved: the gate gates its own next phase, structurally.

---

## Threat model preview (full in PLAN.md)

Much smaller than Phase 08's surface — this migration runs at install time only, not on every Edit/Write.

| Threat | Surface | Mitigation |
|---|---|---|
| **Symlink overwrites an existing real file** | `ln -sfn ~/Sourcecode/agenticapps/wiki-builder/plugin ~/.claude/plugins/llm-wiki-compiler` — the `-f` would delete a pre-existing regular file at that path. | Idempotency check: pre-flight + per-step asserts `~/.claude/plugins/llm-wiki-compiler` is either absent or already-a-symlink-to-the-right-target before `ln`. If it's a real file or a wrong-target symlink, abort with error. |
| **Cross-family data exposure** | `.wiki-compiler.json` per family points at family-local paths. Misconfigured paths could leak across families. | The migration writes only the default config (glob paths rooted under the family directory). T5b post-apply smoke test catches malformed globs at install time via `jq empty` + `compgen -G` resolution checks. No path validation at write time — user customization is user territory. (codex F3 lock: PLAN and CONTEXT align on this.) |
| **CLAUDE.md edit by migration could collide with user content** | Migration appends a `## Knowledge wiki` block to family CLAUDE.md. If user has a section by that name, the migration would duplicate or clobber it. | Idempotency check: `grep -q '## Knowledge wiki'`. If present, skip. If user has a *differently-named* section about the wiki, no collision. |
| **Plugin upstream compromise** | Vendored copy lives at `~/Sourcecode/agenticapps/wiki-builder/plugin/`. If a developer runs `git pull` upstream and pulls compromised code, the symlinked plugin runs in their sessions. | Out of scope for this migration. Document the supply-chain trust assumption in the ADR. |
| **Rollback leaves stale state** | Rollback removes symlink but not the `.wiki-compiler.json` files. If a user reapplies with a different config, they'd merge the user's customisation rather than start fresh. | Document as intentional in the migration Notes. Rollback preserves user data by design. |

No PreToolUse latency budget — this migration doesn't install runtime hooks.
