# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [1.11.0] — Unreleased

### Fixed

- **`test_migration_0007` hermetic sandbox** (phase 18) — `run_0007_fixture` invoked the install + verify scripts with `PATH="$fake_home/bin:$PATH"`, so a host-installed `gitnexus` (e.g., from `fnm`-managed node at `$HOME/.local/state/fnm_multishells/.../bin/gitnexus`) shadowed the missing-stub case in the `03-no-gitnexus` fixture. The install script's `command -v gitnexus` resolved to the host binary, the script exited 0, and the test logged the last remaining carry-over failure since v1.9.3. Replaced the leaky invocation with `env -i HOME=… PATH="$fake_home/bin:/usr/bin:/bin" bash …`: the host PATH and any host `GITNEXUS_*` / `WIKI_SKILL_MD` env vars no longer cross the sandbox boundary. Full migration suite now reports **PASS=131 FAIL=0** — clean baseline. Phase 15 smoke regression-guard tightened from `PASS≥130 FAIL≤1` to `PASS≥131 FAIL=0` (no known-fail allowlist needed) and the parser now treats a missing `FAIL: 0` line from `run-tests.sh` as zero. Test-only change; no scaffolder semantics moved.
- **`test_migration_0001` baseline-anchor regression** (phase 17) — the test extracted its "before" fixture from `git merge-base HEAD origin/main`, which resolves to HEAD itself when running on `main` post-merge. Both fixtures then carried the post-0001 template state and all 8 "needs apply on v1.2.0" assertions failed (8 of the 9 known carry-over failures since v1.3.0). The fix anchors `before_ref` to the parent of the commit that first introduced migration 0001's `## Backend language routing` marker in `templates/workflow-config.md` — a self-locating lookup that resolves to the v1.2.0 baseline (`7dafa63`) regardless of branch. The legacy merge-base chain is retained as a fallback for stripped clones or feature branches that haven't merged 0001 yet. Full migration suite now reports **PASS=130 FAIL=1** (only Phase 18's `03-no-gitnexus` carry-over remains). Phase 15 smoke regression-guard thresholds tightened in lockstep from `PASS≥122 FAIL≤9` to `PASS≥130 FAIL≤1`. Test-only change; no scaffolder semantics moved.

### Added

- **`--strict-preflight` flag for `migrations/run-tests.sh`** (phase 19) — rolls the Phase 13 preflight-correctness audit's `FAIL` count into the global `FAIL` count when set, so CI environments with parity to author dev environments can gate merges on verify-path rot (the issue-#18 bug class). Also accepts `STRICT_PREFLIGHT=1` as an env-var alias for CI-runner ergonomics. Default (loose) mode is unchanged: audit failures still print but don't affect exit code, so dev machines with partial host dependencies aren't false-positive failed. In strict mode the audit's mode-aware header reads `Preflight-correctness audit (strict — failures gate exit)` and the disclaimer reports `(counted in suite totals — strict mode: N FAIL rolled into global FAIL.)`. PyYAML-missing is also strict-aware: loose mode skips with a `~` warning, strict mode emits `✗ python3 with PyYAML not available — audit cannot run (strict)` and increments `FAIL` by 1. New `--help` flag prints the usage block; unknown flags exit 2 (distinct from FAIL → exit 1 so CI can distinguish user error from test failure). Phase 15 smoke runs without the flag and remains unaffected. `migrations/README.md` gains a "Preflight-correctness audit" section documenting both modes.
- **`add-observability/init/INIT.md` shipped** (phase 15) — closes #26 + spec §10.7 obligations (1) wrapper scaffold and (2) middleware/trace-propagation wiring. Nine-phase init flow with three consent gates (consent-1 plan, consent-2 entry-rewrite, consent-3 CLAUDE.md metadata), idempotent re-detection via anchor comments, and per-stack subsections for all five supported stacks (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `ts-react-vite`, `go-fly-http`). Decline paths preserve partial work + print rollback hints instead of half-applying.
- **Slash-discovery via global `~/.claude/skills/` symlink** — closes #22 on both code paths: fresh install via `install.sh` LINKS row (Step T1) and existing installs via migration 0012 Step 4 (1.10.0 → 1.11.0 upgrade path). After either path, `claude /add-observability …` resolves directly without prefixing the project skill directory.
- **Migration `0012-slash-discovery.md`** — promotes 1.10.0 → 1.11.0 in one step: idempotently symlinks `~/.claude/skills/add-observability` to the scaffolder's `add-observability/` directory + bumps `skill/SKILL.md` version. Refuses to overwrite a hand-curated real directory at the target path; warns and aborts if the symlink already points elsewhere.
- **Migration 0012 test fixtures** — `migrations/test-fixtures/0012/` with 5 sandboxed scenarios (fresh apply, idempotent re-apply, wrong-target abort, real-directory abort, version-bump idempotency). `test_migration_0012()` stanza added to `migrations/run-tests.sh`. **5/5 pass.**
- **Per-stack init fixtures** — `migrations/test-fixtures/init-<stack>/` × 6 (7 fixture pairs total: 1 worker + 1 pages + 1 supabase + 1 vite + 3 go for chi/gorilla/std priority detection). Each pair has `before/` + `expected-after/` capturing the canonical wrapper scaffold, middleware wiring, entry-file rewrite, `policy.md` materialisation, and CLAUDE.md observability metadata block. Reference-only at v1.11.0 (no automated harness function yet) — load-bearing as the structural reference for INIT.md's per-stack subsections.
- **Per-stack `policy.md.template` files** — `add-observability/templates/<stack>/policy.md.template` × 5. Anchorless template body; init wraps with `<!-- BEGIN observability policy -->` / `<!-- END observability policy -->` and substitutes `{{SERVICE_NAME}}` at materialisation. Byte-equivalence verified: each of the 7 fixture `policy.md` files = template body + anchor wrap + service-name substitution.
- **`add-observability/init/metadata-template.md`** — canonical §10.8 metadata schema reference (NEW, 413 lines). Documents the observability CLAUDE.md block shape, the three pre-existing-state paths (add / update-via-anchor / conflict-via-unanchored-grep), `enforcement.ci:` as an optional manual field (omitted by default per §10.8 line 160 + Option-4 stance), and the post-write 0011-parser self-check (`awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}'`) that init runs to prove the block is parseable. The parser invocation is byte-identical across metadata-template, INIT Phase 6 (block writer), and INIT Phase 9 (post-write self-check) to lock the contract.
- **`add-observability/SKILL.md` bumped 0.3.0 → 0.3.1** — `implements_spec: 0.3.0` unchanged (spec semantics didn't move; only the implementation surface grew). Init row description expanded to name all 9 phases + 3 consent gates + 5 stacks. New **Routing-table structural invariant** section codifies the Q8 mechanical check (every manifest- or routing-table-referenced path MUST resolve OR be explicitly annotated `(create)` / `(new)`) as a permanent contract on the skill, not just a phase-15 review heuristic.

### Notes

- **Closes 1.10.0's init-blocker**: migration 0011's hard pre-flight aborted with "run init first" when observability metadata or `policy.md` was missing. At v1.10.0 there was no init to run — the abort was correct but the path forward was empty. v1.11.0 ships init, so the v1.10.0 → v1.11.0 chain (or the fresh-install path) now has a fully-walkable end-to-end story for new projects.
- **`enforcement.ci:` omitted by default**: per spec §10.8 line 160 + the Option-4 local-first stance carried forward from v1.10.0. Init's metadata writer ships the field neither set nor referenced; teams wiring CI gates add it manually. The metadata-template documents the field for users who go that path.
- **`policy:` is scalar (single string), not array, at v0.3.1**: PLAN T11's explicit decision, locked by migration 0011's POLICY_PATH parser which expects a single-token value at `^[[:space:]]*policy:`. Multi-stack `policy:` unification is deferred to a future spec amendment + matching parser change. T15's regression row runs `bash migrations/run-tests.sh 0011` post-T1-T13 as the explicit guard against scalar-policy regression.
- **CLAUDE.md add/update/conflict paths**: Phase 6 of init distinguishes three pre-existing-state cases via anchor comments + `^observability:` grep. Anchored block ⇒ update in place. No block ⇒ append fresh. Unanchored observability block (hand-curated) ⇒ refuse to auto-overwrite — print manual-merge hint + treat as consent-gate-3 decline. The conflict branch protects user-tuned metadata from silent destruction.
- **Phase 15 multi-AI review**: BLOCK by codex on PLAN.md v1 (REQUEST-CHANGES by gemini + Claude); 20-item revision list applied to produce PLAN v2 (see `.planning/phases/15-init-and-slash-discovery/15-REVIEWS.md`). Codex caught the Q1 routing-table integrity gap (manifest referenced `./init/INIT.md` which didn't exist at PLAN v1 time) — the lesson was codified as the Q8 mechanical check and embedded in the skill itself per T12.
- **Q8 regex bugfix**: PLAN v1's Q8 script used `[a-z/-]+\.md` (lowercase-only) and missed `./init/INIT.md` because of the uppercase `INIT`. PLAN v2's corrected case-insensitive form `grep -oiE '\./[a-zA-Z/_-]+\.md'` is now the canonical reference encoded in `add-observability/SKILL.md`'s structural-invariant section so future phases inherit the fix instead of rediscovering it.
- **T6-T9 bundled commit**: the four per-stack init subsections + their fixtures landed as a single commit (`047b963`) rather than the per-task atomic pattern T1-T5 / T10-T12 followed. Rationale: shared Phase 5 contract, per-stack subsection headers + named fixture dirs preserve traceability without ~470-line edit-revert ping-pong. Flagged as a one-off precedent; future phases default back to atomic-per-task unless the PLAN explicitly bundles.
- **Out of scope, deferred to future versions**: init harness function in `run-tests.sh` exercising the 7 init fixture pairs (currently reference-only); standalone Node scanner port (carry-over from 1.10.0 deferred list); pre-commit hook template (§10.9.4 MAY); GitLab / CircleCI workflows; retroactive enforcement on fx-signal-agent.

## [1.10.0] — Unreleased

### Added

- **Spec §10.9 observability enforcement — local-first** (phase 14) — the `add-observability` skill bumps to `0.3.0` / `implements_spec: 0.3.0`. v1.10.0 ships the two §10.9 MUSTs (delta scan, baseline file) fully implemented + a §10.9.3 reference CI workflow as opt-in example. Migration 0011 installs only the local-enforcement layer; CI is left as a manual opt-in for advanced setups.
- **`scan --since-commit <ref>` flag** (§10.9.1) — limits the walk to files in `git diff --name-only <ref>...HEAD` (triple-dot, merge-base relative). Resolves `<ref>` to a 40-char SHA via `git rev-parse --verify`. Empty deltas still emit `.observability/delta.json` with zero counts — the machine-readable summary obligation is unconditional. Mutually exclusive with `--update-baseline`.
- **`scan --update-baseline` flag** (§10.9.2) — full-scan-only; atomically writes `.observability/baseline.json` to the spec-mandated canonical path with strict schema: `scanned_commit` always 40-char hex, `policy_hash` always `sha256:<64-hex>`, `module_roots` sorted by `(stack, path)`. Aborts if `policy.md` missing or repo has no commits.
- **`.observability/delta.json`** (§10.9.1) — per-PR machine-readable summary. Emitted unconditionally whenever `--since-commit` is set. Same `counts` + `high_confidence_gaps_by_checklist` shape as baseline, plus `since_commit` / `head_commit` / `files_walked` fields.
- **`.observability/baseline.json`** (§10.9.2) — canonical conformance state. Written only by `scan --update-baseline` (manual) and `scan-apply` success (automatic). Regular `scan` runs read but never rewrite the baseline (per spec §10.9.2 line 219).
- **`scan-apply/APPLY.md` Phase 6b** (§10.9.2) — regenerates `baseline.json` automatically after a successful apply. Skipped when zero findings were applied.
- **`add-observability/enforcement/README.md`** — local-first enforcement guide. Documents the canonical pre-PR command (`claude /add-observability scan --since-commit main`), how to interpret `delta.counts.high_confidence_gaps`, when to refresh baseline, suggested team norms (PR checklist line, pre-push muscle memory alias, monthly full-scan audit). Also documents the opt-in CI workflow path, threat model (pull_request vs pull_request_target trap), and baseline merge-conflict resolution.
- **Reference CI workflow `add-observability/enforcement/observability.yml.example`** (§10.9.3, opt-in only) — fully-spec-conformant GitHub Actions workflow with SHA-pinned actions (`actions/checkout@de0fac2…` v6.0.2, `marocchino/sticky-pull-request-comment@0ea0beb…` v3.0.4), env-var indirection for every `${{ }}` interpolation inside `run:` blocks, top-level `permissions: contents: read`, concurrency block, `pull_request` trigger (NEVER `pull_request_target`). NOT installed by migration 0011 in v1.10.0 — copied manually by projects with self-hosted GHA runners or post-v1.11.0 Node-scanner adopters.
- **Report frontmatter for scan reports** — `.scan-report.md` now declares `scope: full | delta` at the top, plus `since_commit` / `head_commit` / `scanned_at` for delta scans. Includes a delta banner under the H1 listing files walked (or "0 files changed" on empty deltas).
- **Migration `0011-observability-enforcement.md`** — promotes 1.9.3 → 1.10.0 in **4 steps** (local-only): (1) authors initial `.observability/baseline.json` via `claude /add-observability scan --update-baseline`, (2) bumps `observability.spec_version` 0.2.1 → 0.3.0 and adds the new `enforcement:` sub-block (`baseline:` + `pre_commit: optional` — **no `ci:` field**) to CLAUDE.md, (3) appends a per-PR enforcement section to CLAUDE.md documenting both the canonical command and how to interpret `delta.counts.high_confidence_gaps`, (4) bumps `.claude/skills/agentic-apps-workflow/SKILL.md` version. Hard pre-flight aborts on three preconditions (no observability metadata → "run init first"; no policy.md → "run init first"; no `claude` CLI → "install separately") rather than silent skips. Migration does NOT install the CI workflow.
- **`migrations/test-fixtures/0011/` with 6 sandboxed scenarios** — 01-fresh-apply (before-state idempotency for all 4 steps), 02-idempotent-reapply (after-state idempotency + jq schema-strictness check on baseline.json + assertion that NO CI workflow was installed), 03-no-observability-metadata (pre-flight 1 abort), 04-no-policy-md (pre-flight 2 abort), 05-baseline-already-present (Step 1 idempotency catches pre-existing v0.3.0 baseline), 06-no-claude-cli (`requires.tool.claude.verify` abort). `test_migration_0011()` stanza added to `run-tests.sh`. **6/6 pass.**
- **CONTRACT-VERIFICATION.md** gains a v0.3.0 §10.9 coverage matrix mapping each obligation to its load-bearing artefact and verification evidence.

### Notes

- **Local-first enforcement choice**: v1.10.0 ships §10.9.1 + §10.9.2 (the MUSTs) and treats §10.9.3 (the SHOULD) as opt-in. Rationale: Claude Code's CI installation isn't first-class on hosted GitHub runners as of 2026-05; running an LLM-driven scan in CI on every PR has cost, latency, determinism, and prompt-injection trade-offs that aren't worth it for most teams. The example workflow is shipped so adoption is one-`cp` away when the trade-offs change (v1.11.0 Node scanner port closes the install/cost/determinism gaps).
- **Phase 14 multi-AI review**: BLOCK (codex Q1 on three spec-conformance gaps) → REQUEST-CHANGES (gemini + Claude on CI security) → APPROVE after 21-item PLAN.md v2 revision. See `.planning/phases/14-spec-10-9-enforcement/14-REVIEWS.md`. Codex's BLOCK caught two genuinely load-bearing issues: empty-delta path was silently skipping `delta.json` emission, and the original baseline schema allowed `policy_hash: null` / `scanned_commit: "working-tree"` non-conformant placeholders. Both fixed in v1.10.0.
- **Post-review pivot to Option 4 (local-only)**: after the multi-AI review approved a "ship the CI workflow as the primary enforcement mechanism" PLAN, a course-correction pivoted to local-first. The shipped workflow file was renamed `observability.yml.example` and migration 0011 dropped its install step. The §10.9.3 spec obligation is SHOULD not MUST; shipping an example is defensible conformance at "example-only" level.
- **Out of scope, deferred**: pre-commit hook template (§10.9.4 MAY), standalone Node scanner port (closes the CI-feasibility gap), GitLab / CircleCI workflows, retroactive enforcement on fx-signal-agent, dashboard `baseline.json` rendering. Each tracked as a v1.11.0 follow-up.
- **Backward compatibility**: projects that do NOT run migration 0011 keep working at v1.9.3 — no breaking changes in scan/init/scan-apply behaviour at v0.3.0.
- **Init-blocker (resolved in v1.11.0)**: migration 0011's hard pre-flight aborted with "run init first" when observability metadata or `policy.md` was missing, but `add-observability/init/` was not yet shipped at v1.10.0. Projects starting at v1.9.3 with no prior observability state had no walkable path forward at v1.10.0 alone. **Resolved in v1.11.0** by shipping `add-observability/init/INIT.md` + per-stack templates; the v1.10.0 pre-flight messages now point at a real init command (see `[1.11.0]` above).

## [1.9.3] — Unreleased

### Added

- **GitNexus code-graph MCP integration (setup-only)** — new install script `templates/.claude/scripts/install-gitnexus.sh` registers the `gitnexus` MCP server in `~/.claude.json` and bumps the workflow scaffolder. Migration does NOT install gitnexus itself (verify-only — user runs `npm install -g gitnexus`) and does NOT invoke `gitnexus analyze` on any repo (helper script for that). Pre-flight: jq + node ≥ 18 + global gitnexus + valid `~/.claude.json` (or bootstraps if absent). Idempotency validates entry SHAPE (`command=gitnexus`, `args[0]=mcp`) — a malformed pre-existing entry warns + exits 4 (applied-with-warnings) per codex review BLOCK-2.
- **Companion rollback script** `templates/.claude/scripts/rollback-gitnexus.sh` — preserve-data: removes only MCP entry + version bump. Leaves `~/.gitnexus/`, the npm install, and per-repo skills/hooks/CLAUDE.md blocks untouched.
- **Helper script for user-initiated per-repo indexing** — `templates/.claude/scripts/index-family-repos.sh` supports `--family <name>`, `--all`, `--default-set`, `--help`. Default no-args behavior prints usage + explicit warnings about LLM calls (repository content sent to configured LLM provider) and PolyForm Noncommercial license terms. Curated `--default-set` covers 7 active-development repos.
- **Migration `0007-gitnexus-code-graph-integration.md`** — promotes 1.9.2 → 1.9.3 by running the install script. Setup-only scope: no `gitnexus analyze` runs during apply. ADR 0020 records the design rationale (multi-repo registry, MCP-native, license analysis).
- **Hand-built test fixtures for migration 0007** — `migrations/test-fixtures/0007/` with 16 sandboxed scenarios covering: old-node pre-flight, missing-gitnexus pre-flight, fresh apply, idempotent re-apply, existing canonical entry preserved, rollback preserves data, helper script usage / --help, claude CLI absence (no dependency), malformed `~/.claude.json` aborts, canonical entry shape, behavioral MCP startup smoke (codex B3), helper family/default-set dispatch (codex B3), no-claude-json bootstrap (codex F1), version-pin mismatch warn-but-proceed (gemini F1).
- **`test_migration_0007()` stanza** in `migrations/run-tests.sh` — 16 fixtures, each sandboxed via `HOME=$TMP/home` with stubbed `node`/`npm`/`gitnexus` binaries in `$HOME/bin` (PATH-prepended). Behavioral fixtures use a recording stub that logs invocation args to `$HOME/.gn-record` so the harness can assert what was called.

### License

**GitNexus is PolyForm Noncommercial 1.0.** Using GitNexus to help develop a commercial product (factiv, neuroflash) is the permitted "internal use" path. Embedding the GitNexus runtime in a shipped commercial product, or hosting it as a service for third parties, requires an enterprise license from akonlabs.com. See ADR 0020 for the full analysis. Running `npm install -g gitnexus` constitutes license acceptance.

### Notes

- **Phase 10 dogfood**: PLAN.md ran through codex + gemini before T1. Codex returned REQUEST-CHANGES (3 BLOCKs + 3 FLAGs) — all addressed in PLAN.md amendments. B1: MCP command uses `gitnexus mcp` (global binary), not `npx -y gitnexus@... mcp` — makes verify-only actually load-bearing. B2: idempotency validates entry shape, not just presence. B3: behavioral fixtures added (MCP startup smoke, helper dispatch). Plus codex F1 (no-claude-json case), F2 (info-disclosure threat row in plan), F3 (preconditions drift fixed), and gemini F1 (version-pin mismatch warn-but-proceed).
- **Scope reduction**: original draft of migration 0007 (in carry-over PR #12) ran `npm install -g gitnexus` + `gitnexus setup` + per-repo `gitnexus analyze` (30-90 min of LLM work) during apply. Phase 10 strips that to setup-only. Per-repo indexing becomes user-initiated.
- **Fixture count**: 16 (originally 18 — dropped 01-no-node and 17-no-jq because the harness can't sandbox missing-binary-on-host scenarios cleanly; those pre-flight checks are simple `command -v` lines verified by inspection).

## [1.9.2] — Unreleased

### Added

- **LLM wiki compiler integration** — new install script `templates/.claude/scripts/install-wiki-compiler.sh` (POSIX bash, sandbox-friendly via `$HOME`) symlinks the vendored `ussumant/llm-wiki-compiler` plugin into `~/.claude/plugins/`, scaffolds per-family `.knowledge/{raw,wiki}/` dirs + default `.wiki-compiler.json` configs, and appends a `## Knowledge wiki` section to each family's `CLAUDE.md`. Companion rollback script `templates/.claude/scripts/rollback-wiki-compiler.sh` preserves family data (removes only the host symlink + version bump).
- **Migration `0006-llm-wiki-builder-integration.md`** — promotes 1.9.1 → 1.9.2 by running the install script. Pre-flight verifies the vendored plugin exists at `~/Sourcecode/agenticapps/wiki-builder/plugin/` and SKILL.md is at 1.9.1. ABORT-on-wrong-target-symlink policy (won't silently repoint a forked install). Skip-when-CLAUDE.md-absent policy (won't create user files from scratch). Family heuristic: directory under `~/Sourcecode/` containing at least one immediate child git repo, excluding `personal|shared|archive`.
- **ADR 0019** — LLM wiki compiler integration. Records Andrej Karpathy's LLM Knowledge Base pattern, the per-family vs per-repo decision, why vendor instead of npm-install, the `.wiki-compiler.json` schema choice, and the threat model (symlink overwrites, supply-chain trust, plugin session hooks, preserve-data rollback).
- **Hand-built test fixtures for migration 0006** — `migrations/test-fixtures/0006/` with 15 sandboxed scenarios covering every decision branch: plugin-missing pre-flight, fresh install, idempotent re-apply, rollback, zero-families, existing-config-preserved, real-file collision (ABORT), correct-symlink idempotency, CLAUDE.md update idempotency, wrong-target symlink (ABORT, codex B2), missing-family-CLAUDE.md (skip-with-note, codex B3), non-family directory skipped via child-`.git` heuristic (codex F2), missing-plugins-parent (mkdir -p, codex F4), `.knowledge` exists as file (ABORT exit 3, codex F4), malformed existing config (preserve+warn, codex F4).
- **`test_migration_0006()` stanza** added to `migrations/run-tests.sh` — 15 fixtures, each sandboxed via `HOME=$TMP/home`. Strict line-presence stderr matching. Codex F1 sandbox-escape guard rejects any install script containing hardcoded real-home paths.

### Notes

- **Phase 09 dogfood**: PLAN.md ran through codex + gemini before T1. Codex returned REQUEST-CHANGES (3 BLOCKs + 4 FLAGs) — all addressed in PLAN.md amendments before execution. B1 (goal-vs-verify gap) → new T5b smoke test verifies plugin manifest parses, declares canonical commands, family configs parse, source globs resolve. B2 (wrong-target symlink) → ABORT policy locked. B3 (missing family CLAUDE.md) → skip-with-warning. Fixture count grew 9 → 15.
- **Scope reach**: migration 0006 touches three scope levels — host (`~/.claude/plugins/` symlink), family (`<family>/`-rooted scaffolding), per-project (SKILL.md version). This is intentional and follows the precedent of migration 0001 (global plugin installs).
- **Self-contained**: earlier draft of this migration assumed an old draft of 0005 had scaffolded `.knowledge/{raw,wiki}/` first. The shipped 0005 (multi-AI review enforcement) is unrelated; migration 0006 now owns the entire scaffolding chain.

## [1.9.1] — Unreleased

### Added

- **Multi-AI plan review enforcement gate** — new POSIX bash 3.2+ script `templates/.claude/hooks/multi-ai-review-gate.sh` (hook 6 in the programmatic-hooks taxonomy from ADR 0015). Fires as PreToolUse on `Edit|Write|MultiEdit`. Reads the active phase via `.planning/current-phase` symlink, looks for `*-PLAN.md` and `*-REVIEWS.md` with `find -maxdepth 2`, blocks (exit 2) when PLAN.md is present but REVIEWS.md is missing. Sub-100ms latency (measured: avg 22-48ms across all 11 fixture scenarios). Override surfaces are `GSD_SKIP_REVIEWS=1` (session-scoped escape) and `touch .planning/current-phase/multi-ai-review-skipped` (phase-scoped, committed audit trail). Edits to planning artifacts (`*PLAN.md`, `*REVIEWS.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `*CONTEXT.md`, `*RESEARCH.md`) bypass the gate to avoid chicken-and-egg deadlock.
- **Migration `0005-multi-ai-plan-review-enforcement.md`** — promotes 1.9.0 → 1.9.1 by installing hook 6, wiring it into `.claude/settings.json` PreToolUse hooks array (jq-based insert with idempotency guard), bumping `skill/SKILL.md` to `version: 1.9.1`, and recording the gate in `docs/workflow/ENFORCEMENT-PLAN.md` if vendored. Pre-flight checks for `/gsd-review` slash command installation and ≥2 reviewer CLIs from `gemini|codex|claude|coderabbit|opencode`. Three steps; each ships with idempotency check + rollback.
- **ADR 0018** — Multi-AI plan review enforcement. Documents the drift pattern observed in `factiv/cparx/.planning/phases/` (eight consecutive phases 04.9 → 05-handover produced PLAN.md but no REVIEWS.md), the choice to promote `/gsd-review` from optional gsd-patch slash command to enforced contract gate, the dual-override-surface design (env var + sentinel), and the trust-boundary at "REVIEWS.md exists" (not at reviewer-content quality).
- **Hand-built test fixtures for migration 0005** — `migrations/test-fixtures/0005/` with 11 pair-shaped scenarios covering every decision branch: no-active-phase, no-plans, plan-no-reviews (the canonical block), plan-with-reviews, stub-reviews (≤5 lines), env-override, sentinel-override, planning-artifact-edit, hostile-filename-edit (proves shell-injection inertness), non-Edit-tool, and MultiEdit-tool (proves matcher closure).
- **`test_migration_0005()` stanza** added to `migrations/run-tests.sh` — 11 assertions, strict line-presence stderr matching, mktemp-per-fixture isolation. FAIL-not-SKIP if the hook script is missing (the script IS the migration's artifact under test). Fixture 09 additionally asserts `/tmp/HOSTILE_MARKER` survives the run as evidence that `$(rm -rf …)` in `tool_input.file_path` is never command-substituted.
- **Contract entry** — `templates/config-hooks.json` gains a `pre_execute_gates.multi_ai_plan_review` block; `docs/ENFORCEMENT-PLAN.md` gains a row in the planning-gates table that references the gate's evidence requirement (`{padded_phase}-REVIEWS.md` exists and is non-stub).

### Notes

- **Phase 08 dogfood**: the gate was exercised on its own creation phase. Multi-AI plan review (`08-REVIEWS.md`) produced by **codex + gemini** — codex returned REQUEST-CHANGES with 4 BLOCKs and 3 FLAGs, all addressed in PLAN.md amendments before T1 execution (MultiEdit added to matcher per B3, fixture 09 redesigned to actually exercise the parsing branch per B4, T6b added for live apply/rollback verification per B1, T-dogfood added for self-test per B2).
- **Subtractive TDD pattern**: hook script was drafted in the PR #12 carry-over and cherry-picked into phase 08. The RED→GREEN sequence proves the hook (existing) matches the fixture decision matrix (new). Same pattern as migration 0010.
- **Bash 3.2 compatibility**: hook script + harness target macOS bash 3.2.57 explicitly. Empty-array expansion guarded with `${env_args[@]+"${env_args[@]}"}`. Latency benchmark uses python3 brackets around N=100 batches to amortize timing overhead.

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
- **Migration `0009-vendor-claude-md-sections.md`** — promotes 1.6.0 → 1.8.0 (re-anchored in Phase 11; the runner matches on `from_version` only, so the 1.6 → 1.8 jump skipping 1.7 is supported) by vendoring the workflow block, adding a reference to CLAUDE.md, and detecting + (with user confirmation) extracting any pre-existing inlined block. Three-way pick on customised inlined blocks: replace-with-canonical / preserve-as-vendored / skip. Five steps; each ships with idempotency check + rollback.
- **Hand-built test fixtures for migration 0009** — `migrations/test-fixtures/0009/` with five scenarios (fresh, inlined-pristine, inlined-customised, after-vendored, after-idempotent). 29 assertions cover every step's idempotency check across every scenario. Distinct from migration 0001's git-ref-extracted fixtures because 0009's "pre-existing inlined block" state isn't in claude-workflow's own history.

### Changed

- **Migration `0000-baseline.md` Step 4 patched in-place** — previously `cat`-ed `templates/claude-md-sections.md` directly into CLAUDE.md (the root cause of cparx 646L and fx-signal-agent 372L). Now writes `.claude/claude-md/workflow.md` from the vendored template + appends a 5-line `## Workflow` reference section to CLAUDE.md. Legitimate in-place patch because 0000's pre-flight already refuses re-execution against existing installs. Note in the patched step documents the rationale.
- **`templates/claude-md-sections.md` H1 rewritten** — was `# CLAUDE.md Sections — paste into your project's CLAUDE.md`, which is the literal smoking-gun line found in fx-signal-agent's CLAUDE.md proving the file was pasted verbatim. New H1 (`# DEPRECATED — vendored as .claude/claude-md/workflow.md since v1.8.0`) carries a "do not paste" banner and explains migration 0009's detection logic. The file is retained for migration 0009's grep-detection of pre-existing pastes in older repos.
- **`setup/SKILL.md`** — post-setup summary now lists `.claude/claude-md/workflow.md` as a created file. Migration history table updated with 0002, 0004–0007, and 0009 entries (was stale at 0001). Notes the v1.8.0 vendor-mode pivot.
- **`update/SKILL.md` Step 5** — adds a "divergence variant" of the per-step Apply prompt: when a vendored file's local copy byte-differs from the canonical scaffolder source, present a 3-way pick (Replace / Keep / Vendor-local). Default to Keep (diverging is usually intentional). Failure modes table extended with vendored-file divergence and inlined-block extraction-ambiguous outcomes.
- **`migrations/README.md`** — added a Migration index table near the top showing the current chain and the v1.8.0 vendor-mode property of 0000.
- **`skill/SKILL.md`** frontmatter version bumped 1.6.0 → 1.8.0 (re-anchored in Phase 11; the prior frontmatter `1.7.0 → 1.8.0` was retired alongside the [1.5.1]/[1.6.0]/[1.7.0] slots).
- **`migrations/run-tests.sh`** — added `test_migration_0009()` stanza (29 assertions). Existing `test_migration_0001()` kept as-is; its 8 pre-existing FAILs (caused by `git merge-base` resolving to a post-0001-merge commit) are unrelated to this phase and tracked separately.

### Notes

- **fx-signal-agent** drops from 372 lines to ~201 after applying migration 0009 (the inlined block extraction is the single largest reduction).
- **cparx** drops from 646 lines to ~496 after migration 0009. Getting it ≤200L requires migration 0010 (GSD compiler reference-mode for auto-managed PROJECT/STACK/CONVENTIONS/ARCHITECTURE sections), queued as a separate phase. ADR 0021 records why 0010 is not bundled into this release.
- Existing 1.6.0 projects pick up the fix via `/update-agenticapps-workflow`; the migration runtime walks them through the inlined-block extraction prompt with diff preview.

## [1.7.0] — Skipped (no migration)

This version slot is intentionally skipped by the migration chain. Migration
0009 promotes `1.6.0 → 1.8.0` directly — the runner matches on
`from_version` only, so `to_version` need not be `from_version + 0.1`. See
`migrations/README.md` "Application order" note 3.

The previous draft of this entry described the GitNexus code-graph
integration that was once planned to ship as migration 0007 at
`1.6.0 → 1.7.0`. After Phase 10's scope reduction and Phase 11's chain
rebase, GitNexus actually shipped via migration 0007 at `1.9.2 → 1.9.3`.
See **[1.9.3]** for the content that landed.

## [1.6.0] — Unreleased

### Added

- **Coverage Matrix Page** — agenticapps-dashboard ships a new `/coverage`
  route, a cross-family knowledge-layer freshness dashboard. Workflow-repo
  surface only; no consumer-project state changes. ADR 0023.
- **Migration `0008-coverage-matrix-page.md`** — promotes `1.5.0 → 1.6.0`.
  Re-anchored in Phase 11 from a previously-planned `1.7.0 → 1.8.0` slot;
  the prior chain had a gap at `1.5 → 1.7` and a `0008/0009` collision at
  `1.7 → 1.8`. Re-anchoring closed both without touching shipped
  migrations 0010 / 0005 / 0006 / 0007.

### Notes

- The previous draft of this entry described the LLM wiki compiler
  integration that was once planned to ship as migration 0006 at
  `1.5.1 → 1.6.0`. After Phase 11's chain rebase, the wiki compiler
  actually shipped via migration 0006 at `1.9.1 → 1.9.2`. See **[1.9.2]**
  for the content that landed.

## [1.5.1] — Skipped (no migration)

This version slot is intentionally skipped by the migration chain. After
Phase 11's chain rebase, migration `0008` promotes `1.5.0 → 1.6.0`
directly, so no migration claims `1.5.1` as its `to_version`.

The previous draft of this entry described the multi-AI plan review
enforcement gate that was once planned to ship as migration 0005 at
`1.5.0 → 1.5.1`. After the rebase, the gate actually shipped via
migration 0005 at `1.9.0 → 1.9.1`. See **[1.9.1]** for the content that
landed.

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
