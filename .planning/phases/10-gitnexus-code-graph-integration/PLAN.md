# Phase 10 — PLAN

**Migration:** 0007-gitnexus-code-graph-integration
**Version bump:** 1.9.2 → 1.9.3
**Plan written via:** `superpowers:writing-plans`
**Inputs:** CONTEXT.md, RESEARCH.md, ADR 0020.

Setup-only migration (per CONTEXT scope reduction): installs the wiring (MCP server + helper script) but does NOT run per-repo `gitnexus analyze`. User opts into indexing on-demand via the helper script.

## Plan change log

| Date | Change | Driver |
|---|---|---|
| 2026-05-13 | Initial draft | Phase scope |
| 2026-05-13 | **Amended after multi-AI plan review (10-REVIEWS.md)** — codex REQUEST-CHANGES with 3 BLOCKs + 3 FLAGs, gemini APPROVE-WITH-FLAGS. Locked changes: (B1) MCP command uses `gitnexus mcp` directly (not `npx -y gitnexus@... mcp`) so verify-only is actually load-bearing. (B2) Idempotency validates entry SHAPE (`command=gitnexus`, `args[0]=mcp`), not just presence — malformed entry warns + exits 4. (B3) Behavioral fixtures added (13: MCP startup smoke, 14: helper family dispatch, 15: helper default-set dispatch). (F1) Fresh-user no-claude.json fixture (16). (F2) Info-disclosure threat row added. (F3) Pre-flight contract tightened: node ≥ 18 + jq + gitnexus; no network check. Fixture (17) for no-jq. (gemini F1) Version-mismatch warn-but-proceed (fixture 18). Fixture count: 12 → 18. | codex BLOCKs B1-B3 + FLAGs F1-F3, gemini F1 |

---

## Task graph

```
T1 (fixtures-RED) ──┐
                    ├──> T3 (harness-stanza) ──> T4 (harness-GREEN)
T2 (install + rollback + helper scripts) ────┘                │
                                                              ▼
                                                  T5 (live sandbox apply + rollback)
                                                              │
                                                              ▼
                                T6 (CHANGELOG + SKILL + README + migration body cleanup)
                                                              │
                                                              ▼
                                                      T7 (VERIFICATION.md)
```

---

## Tasks

### T1 — Author test fixtures for 0007 (`tdd="true"`)

**Files under `migrations/test-fixtures/0007/`:**
- `01-no-node/{setup.sh,expected-exit,expected-stderr.txt}` — pre-flight fails because `node` is absent
- `02-old-node/{setup.sh,expected-exit,expected-stderr.txt}` — node < 18
- `03-no-gitnexus/{setup.sh,expected-exit,expected-stderr.txt}` — gitnexus not on PATH; pre-flight emits install command
- `04-fresh-apply/{setup.sh,expected-exit,verify.sh}` — clean apply: MCP entry written, version bumped
- `05-idempotent-reapply/{setup.sh,expected-exit,verify.sh}` — second apply is no-op
- `06-existing-mcp-entry/{setup.sh,expected-exit,verify.sh}` — pre-existing user `gitnexus` MCP entry preserved (NOT overwritten)
- `07-rollback/{setup.sh,expected-exit,verify.sh}` — apply then rollback: MCP entry removed, version reverted, npm install untouched, `~/.gitnexus/` registry preserved
- `08-helper-script-no-args/{setup.sh,expected-exit,expected-stderr.txt}` — `index-family-repos.sh` with no args prints usage + license warning
- `09-helper-script-help-flag/{setup.sh,expected-exit,expected-stderr.txt}` — `--help` does the same
- `10-claude-mcp-cli-missing/{setup.sh,expected-exit,verify.sh}` — `claude` CLI absent, fallback jq path writes MCP entry
- `11-claude-json-malformed/{setup.sh,expected-exit,expected-stderr.txt}` — `~/.claude.json` exists but isn't valid JSON; migration aborts with clear error
- `12-version-pin-respected/{setup.sh,expected-exit,verify.sh}` — `GITNEXUS_VERSION=2.4.0` env var written into MCP command verbatim

**Each fixture:**
- `setup.sh` — materialize the pre-apply state in a sandboxed `$HOME=$TMP/home`. Stubs `node`, `npm`, and `gitnexus` as bash scripts in a `$TMP/bin` and prepends to PATH.
- `verify.sh` (optional) — post-apply assertions.
- `expected-exit` + `expected-stderr.txt` — standard contract.

**Acceptance:**
- 12 scenarios written.
- Each setup.sh sandboxes node/npm/gitnexus as bash stubs (no real `npm install` runs in tests).
- Commit: `test(RED): phase 10 — 12 fixtures for migration 0007 GitNexus integration`.

### T2 — Author install/rollback/helper scripts

**Files written:**
- `templates/.claude/scripts/install-gitnexus.sh` — pre-flight (node ≥ 18, gitnexus present, jq present) + MCP wire (CLI-first, jq fallback, idempotent) + version bump. Per Phase 09 CSO H1 lesson: explicit if/then/else on `sed`, no `&&`-chain swallow.
- `templates/.claude/scripts/rollback-gitnexus.sh` — remove MCP entry (CLI-first, jq fallback) + revert version. Preserve data.
- `templates/.claude/scripts/index-family-repos.sh` — helper. Supports `--family <name>`, `--all`, `--default-set`, `--help`. Default = print usage. Includes license warning.

**Acceptance:**
- All 3 scripts `bash -n` clean.
- Install script bash 3.2-compatible (no `$EPOCHREALTIME`, no `${var,,}` lowercase, no `[[ ]]` outside `[ ]`-safe constructs).
- Helper script's default-no-args behavior matches fixtures 08 and 09.
- Commit: `feat(GREEN): phase 10 — install/rollback/helper scripts for migration 0007`.

### T3 — `test_migration_0007()` stanza in `migrations/run-tests.sh`

**Action:** Add the function. Same sandbox model as `test_migration_0006`: `mktemp -d` per fixture, run setup.sh with `HOME=$TMP/home`, invoke install script, assert exit + stderr + verify.sh.

**Acceptance:**
- Function added.
- Dispatcher updated.

### T4 — Verify GREEN

**Action:** `bash migrations/run-tests.sh 0007` → 12/12 PASS.

### T5 — Live sandbox apply + rollback

**Action:** Build a realistic sandbox (`HOME=$TMP/home`, stub gitnexus binary, baseline SKILL.md at 1.9.2). Run install. Verify MCP entry, version bump. Run rollback. Verify entry removed, version reverted. Capture before/after diffs.

**Acceptance:**
- All three cycles green.
- Diffs recorded in VERIFICATION.md.

### T6 — Wire contract entries + clean migration body

**Files modified:**
- `migrations/0007-gitnexus-code-graph-integration.md` — rewritten to delegate to `templates/.claude/scripts/install-gitnexus.sh` and reflect the scope reduction. Strike the `gitnexus analyze` per-repo step from apply. Reference the helper script for on-demand indexing. Add explicit `**Idempotency check:**` markers. Add jq to `requires:`.
- `docs/decisions/0020-gitnexus-code-graph-integration.md` — minor cleanup: note that mass-indexing is helper-script-only, not migration-driven. Remove "Step 3 — index the active family repos" from the relationship section if it implies migration-driven.
- `CHANGELOG.md` — new `[1.9.3]` section with explicit license callout.
- `skill/SKILL.md` — frontmatter 1.9.2 → 1.9.3.
- `migrations/README.md` — index row promoted from `(draft — PR #12)` annotation.

**Acceptance:**
- Migration body delegates to scripts; no inline `npm install -g` or `gitnexus analyze` commands in the apply section.
- All version refs are 1.9.2/1.9.3.

### T7 — VERIFICATION.md

**Action:** 1:1 evidence per AC-1 through AC-10.

---

## Threat model (STRIDE — smaller than Phase 09)

| Threat | STRIDE | Surface | Mitigation | Evidence |
|---|---|---|---|---|
| Supply chain via npm install -g | **T** | User-driven npm install before migration | Pre-flight verifies version-pin matches expected range (T2 implementation). Documented as user responsibility in migration Notes. | Fixture 03 (no-gitnexus) + Notes. |
| `@latest` in MCP command auto-loads compromised future versions | **T** | If we used `@latest`, MCP server runs whatever's currently published | Pin via `GITNEXUS_VERSION` env var with recorded default. Migration writes the literal pinned `@X.Y.Z` into the MCP command. | Fixture 12 (version-pin-respected). |
| Existing MCP entry overwritten | **I** | Step 2 could clobber a user's customised entry | Idempotency check: detect existing `mcpServers.gitnexus`; preserve unchanged. | Fixture 06. |
| `~/.claude.json` corruption via partial write | **D** | jq fallback path; atomic write essential | `jq ... > .tmp && mv .tmp original` (atomic-on-same-filesystem). Same pattern as 0005 Step 2. | Manual T5 test + fixture 04. |
| Malformed `~/.claude.json` swallows error | **I** | jq read on a broken file returns empty; migration could think the entry is absent and add it again | Pre-flight `jq empty ~/.claude.json` aborts on parse error before any writes. | Fixture 11. |
| License non-compliance (PolyForm Noncommercial) | **R** | User unaware of license for commercial product distribution | Explicit callout in migration Notes + CHANGELOG + ADR 0020. Helper script's usage message repeats the warning. | All four artifacts grep-verifiable. |
| Bash 3.2 incompatibility | **D** | Helper script + install script must run on macOS bash 3.2.57 | `bash -n` syntax check. Avoid `[[` in `$()` substitutions, `${var,,}`, `$EPOCHREALTIME`, `coproc`. | T2 acceptance + fixture run on macOS. |
| Mass per-repo modification (NOT in this phase) | **I** | If we'd kept the carry-over draft's auto-`gitnexus analyze`, every Edit/Read across all family repos would carry implicit modifications | Scope reduction: per-repo state is user-initiated via helper script. Documented in CONTEXT scope reduction section. | Migration body's Apply section has no analyze command. |

---

## Goal-backward verification matrix

Goal: *A user on workflow 1.9.3 has gitnexus MCP server registered in their Claude Code config, can invoke `bash ~/.claude/scripts/index-family-repos.sh --family <X>` to opt into per-repo indexing, and has clear documentation of the PolyForm Noncommercial license terms.*

1. **Goal:** MCP entry written + helper script available + license terms surfaced.
2. **For (1):** Install script writes MCP entry; helper script ships in templates/; migration Notes + CHANGELOG + ADR 0020 carry license callout.
3. **For (2):** T4 fixtures 04, 06, 08, 09 confirm. T5 live sandbox confirms.
4. **Sufficiency:** Idempotent re-apply, rollback works, pre-flight blocks insufficient environments.
5. **For (4):** Fixtures 05, 07, 01, 02, 03 cover those branches.

Goal achieved iff T4 GREEN + T5 live cycles work + grep-verifiable license callout.

---

## Definition of done

- All 7 tasks complete in TaskList.
- 12/12 PASS on `test_migration_0007`.
- CHANGELOG `[1.9.3]` section landed with explicit license callout.
- SKILL.md at 1.9.3.
- REVIEW.md has Stage 1 + Stage 2 sections, both APPROVE.
- SECURITY.md from CSO recorded, no Critical findings.
- VERIFICATION.md 1:1 evidence per AC.
- PR opened, non-draft, targeting main.
