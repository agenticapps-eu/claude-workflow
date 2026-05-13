# Phase 10 — GitNexus code-graph integration

**Migration:** 0007-gitnexus-code-graph-integration
**Version bump:** 1.9.2 → 1.9.3
**Date opened:** 2026-05-13
**Predecessor:** Migration 0006 (LLM wiki builder, 1.9.1 → 1.9.2)
**Decision record:** ADR 0020 — GitNexus code-knowledge graph integration
**Goal:** Install GitNexus globally + wire it as an MCP server in Claude Code so cross-repo code-structure questions are answerable via MCP tool calls instead of multi-hour grep chases. Ship the family-indexing helper script for user-initiated indexing. Bumps scaffolder 1.9.2 → 1.9.3.

---

## Background

Migration 0006 added the per-family **doc/decision** wiki (what we decided, why). It does NOT cover **code structure** — "what calls what across these 30 services," "what breaks if I rename this function," "what's the call chain from API gateway to brand-voice-service." Agents still re-derive code structure every session via grep/find/file-reads. For polyrepo systems like neuroflash (32 repos), the cost compounds: one cross-repo impact question can take dozens of tool calls and tens of thousands of tokens.

ADR 0020 records the decision to adopt **GitNexus** (npm: `gitnexus`) as the code-knowledge layer. The plugin provides a multi-repo MCP server (single `~/.gitnexus/registry.json` serves all indexed repos), 16 MCP tools (impact analysis, symbol view, call-chain trace), 7 per-repo agent skills, and PostToolUse hooks for stale-index detection. License is PolyForm Noncommercial — fine for "use to help develop a commercial product," not fine for "embed the runtime in a shipped product."

---

## Scope reduction vs the carry-over draft (KEY DECISION)

The original draft of 0007 (carried in PR #12) had a Step 3 that ran `gitnexus analyze` on every family repo automatically — 30-90 minutes of LLM-driven indexing on every migration apply. **This phase scopes that out.**

| Aspect | Original draft | Phase 10 scope |
|---|---|---|
| `npm install -g gitnexus` | Step 1 of apply | Pre-flight verify; install only if absent |
| `gitnexus setup` (MCP register) | Step 2 of apply | Step 2 of apply |
| Per-repo `gitnexus analyze` | Step 3 of apply (mass-index) | **OUT OF SCOPE** — user runs on-demand |
| Helper script for indexing | Referenced but undefined | **Ships** as `templates/.claude/scripts/index-family-repos.sh` |
| Version bump | Step 4 | Step 3 |

**Rationale:**
- A migration that takes 30-90 min on apply is not a migration, it's an integration session. The migration framework's `idempotency-check + retry` model breaks down on long-running ops.
- `gitnexus analyze` makes LLM calls (semantic extraction). Running it implicitly during apply is a surprise spend.
- Per-repo indexing is naturally user-initiated: the user knows which repos they're actively working on.
- The helper script makes it one command (`bash ~/.claude/scripts/index-family-repos.sh --family factiv`) to opt-in.
- License-wise (PolyForm Noncommercial), `gitnexus analyze` on factiv/neuroflash repos is the "internal-use for developing commercial products" path. Making it user-initiated is more transparent than implicit-on-migration-apply.

---

## Scope (must-have for this phase)

1. **Pre-flight checks** — node ≥ 18, npm, internet reachable, and (if `gitnexus` is already installed) it's a version we recognize. If `gitnexus` is NOT installed, surface a clear `npm install -g gitnexus` command in the error; don't auto-install.
2. **Step 1 (install) — DESIGN DECISION:** verify-or-install? See RESEARCH §1. Tentative: **verify-only**, fail-with-clear-install-command if absent.
3. **Step 2 (MCP wire)** — `claude mcp add gitnexus -- npx -y gitnexus@latest mcp` via `claude` CLI, OR direct json edit of `~/.claude.json` if the CLI is unavailable. Idempotent (check existing entry before adding).
4. **Step 3 (helper script ships)** — `templates/.claude/scripts/index-family-repos.sh` accepts `--family <name>` / `--all` / default (curated active set). Does NOT run during migration apply.
5. **Step 4 (version bump)** — `SKILL.md` 1.9.2 → 1.9.3.
6. **Rollback** — remove MCP entry, revert version. Does NOT npm-uninstall (user may have other uses). Does NOT remove `~/.gitnexus/` registry (preserve-data semantics, matching Phase 09 RESEARCH §3).
7. **Test harness** — `test_migration_0007()` with fixtures covering: pre-flight fails on missing node, pre-flight fails on missing gitnexus, fresh apply, idempotent re-apply, rollback, existing MCP entry preserved on re-apply, helper script syntax-checks under bash 3.2+.
8. **CHANGELOG [1.9.3]** + SKILL.md bump + migrations/README index row promotion (from draft → shipping).
9. **Phase artifacts** — CONTEXT, RESEARCH, PLAN, 10-REVIEWS (multi-AI), REVIEW (Stage 1 + Stage 2), SECURITY (CSO), VERIFICATION.

## Won't-do (explicit scope cuts)

- **Per-repo `gitnexus analyze` invocation during migration apply.** Moved to user-initiated helper script.
- **Per-repo skills/hooks/CLAUDE.md block install.** `gitnexus analyze` does this — not our migration's responsibility. We only install the global pieces.
- **Auto-uninstall on rollback.** `npm uninstall -g gitnexus` would remove a tool the user might still use directly. Rollback removes only OUR additions (MCP entry, version bump).
- **License-acceptance gate.** ADR 0020 documents the license; the migration assumes the user has read it. No interactive prompt (migrations are non-interactive).
- **Graphify fallback** (mentioned in ADR 0020 as 0007b). Out of scope.
- **Reindex scheduling** (cron/launchd). Future follow-up.

## Open questions (resolve before PLAN.md)

| # | Question | Tentative answer |
|---|---|---|
| Q1 | Verify-only vs install-during-apply for gitnexus? | **Verify-only**. Migrations shouldn't network-fetch arbitrary npm packages. User runs `npm install -g gitnexus` themselves (clear error + command). |
| Q2 | MCP entry via `claude mcp add` CLI or direct `~/.claude.json` edit? | Try CLI first (`claude mcp add gitnexus -- npx -y gitnexus@latest mcp`), fall back to jq edit of `~/.claude.json`. CLI is more future-proof but may not be available everywhere. |
| Q3 | Helper script default scope: `--all`, `--default`, or none? | Default = print usage if no flag. Force user to choose `--family <name>` or `--all`. No surprise mass-indexing. |
| Q4 | What if `~/.gitnexus/` has data from a previous install? | Preserve unconditionally. The registry is user state, not migration state. |
| Q5 | License acceptance — written log or just trust? | Document in migration Notes + ADR 0020. No on-disk acceptance log; if the user runs the migration, they're consenting to the documented license terms. |

## Decisions resolved (locked)

- **Setup-only migration** (Scope reduction): the migration installs the wiring, not the index. Index is user-initiated.
- **Verify-only on gitnexus**: don't auto-install. Print the install command in the error.
- **Helper script ships in `templates/.claude/scripts/`**: idempotent, user-runnable, scoped (--family/--all/--default-set).
- **Rollback preserves `~/.gitnexus/` and the npm install**: user data + system state untouched.
- **MCP wiring via `claude mcp add` with jq-edit fallback**: future-proof + works without the CLI.
- **No license-acceptance prompt**: documented in ADR 0020 + migration Notes; user assumed-aware.

## Dependencies

**Upstream (already shipped):**
- Migration 0000 — SKILL.md with version field.
- Migration 0006 (just shipped) — scaffolder at 1.9.2.
- node ≥ 18 + npm on host.

**External:**
- `gitnexus` npm package (must be available via `npm install -g gitnexus`).
- Network for the user's `npm install -g`.

**Downstream (this phase enables):**
- User opts into per-repo indexing via the helper script.
- Migration 0008 (queued — dashboard coverage matrix) gets a new dimension to display.
- PR #12 (carry-over) reduces to zero rows after this lands; can be closed.

---

## Acceptance criteria

- **AC-1** — Migration body is setup-only (no `gitnexus analyze` in apply). Helper script ships separately.
- **AC-2** — Migration applies cleanly from 1.9.2 baseline; idempotent re-apply; rollback removes MCP entry + reverts version.
- **AC-3** — Pre-flight emits clear error + install command if `gitnexus` is absent. Refuses to apply if node < 18.
- **AC-4** — `migrations/run-tests.sh test_migration_0007` covers: missing-node fail, missing-gitnexus fail, fresh apply, idempotent re-apply, rollback, MCP-entry-already-present preserve.
- **AC-5** — Helper script `index-family-repos.sh` syntax-checks under bash 3.2; supports `--family <name>`, `--all`, `--default-set`. Default behavior prints usage.
- **AC-6** — MCP wire step is idempotent: detects existing `gitnexus` MCP entry and short-circuits.
- **AC-7** — `skill/SKILL.md` 1.9.3; `CHANGELOG.md [1.9.3]` section.
- **AC-8** — `10-REVIEWS.md` produced by ≥2 reviewer CLIs (multi-AI dogfood).
- **AC-9** — Stage 1 + Stage 2 + CSO reviews complete; no unresolved BLOCKs.
- **AC-10** — License caveat surfaced in migration Notes + ADR + CHANGELOG.

---

## Threat model preview (full in PLAN.md)

Smaller than Phase 09's surface because gitnexus is verify-only:

| Threat | Surface | Mitigation |
|---|---|---|
| Supply chain via `npm install -g gitnexus` | User runs npm globally; could fetch compromised package | Documentation — pin to a vetted version in `requires:`. Recommend lockfile or registry-mirror for security-sensitive setups. |
| MCP server registers arbitrary command | Step 2 writes `claude mcp add gitnexus -- npx -y gitnexus@latest mcp`. Future runs of npx could fetch a different package version. | Pin via `@<version>` in the MCP command. Document explicit version in migration body. |
| Existing MCP entry overwritten | Step 2 could clobber a user's customised `gitnexus` MCP entry | Idempotency check: detect existing entry; skip if present. |
| Mass per-repo modification | NOT a threat in this phase (per-repo indexing is user-initiated). Documented as a known surface for the helper script. | Helper script never runs without explicit flag. Logs what it touches. |
| License non-compliance | User unaware of PolyForm Noncommercial implications for commercial product distribution | Migration Notes + ADR 0020 + CHANGELOG explicit callout. |
| `~/.claude.json` corruption | jq-fallback path could mangle the file on partial-write | Atomic write via `.tmp` + `mv` (same pattern as 0005 Step 2). |
