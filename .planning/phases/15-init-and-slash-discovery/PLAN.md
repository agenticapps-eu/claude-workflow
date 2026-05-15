# Phase 15 — PLAN — Ship `init/INIT.md` + slash discovery (option C) — v1.11.0

**Phase goal**: a fresh project can run `/setup-agenticapps-workflow` → `/add-observability init` → `/update-agenticapps-workflow` and land at v1.11.0 with §10.7 obligations (1) wrapper scaffolded and (2) middleware wired actually satisfied. Closes #26 (init missing) and #22 (slash-discovery) together.

**Versions**:
- Scaffolder `skill/SKILL.md`: 1.10.0 → 1.11.0.
- Skill `add-observability/SKILL.md`: 0.3.0 → 0.3.1 (patch; `implements_spec` stays 0.3.0).

**RESEARCH decisions encoded**: D1 = **C** (promote layout, user-confirmed), D2 = hybrid consent, D3 = walk-all + `--stack` override, D4 = per-stack policy.md, D5 = strict first-run, D6 = anchor-comment markers, D7 = chain hint, D8 = both migration 0012 + scaffolder setup-time.

---

## Task breakdown (atomic — one commit per task)

### Phase 1 — Scaffolder layout refactor (slash discovery, option C)

#### T1 — Move `add-observability/` to scaffolder repo root as a peer skill

**Touches**: `add-observability/` → moves up one level out of the implicit "nested under scaffolder skill" semantics; in practice the scaffolder is the whole `claude-workflow` repo so `add-observability/` is already at repo root. The actual fix is in how the scaffolder *install* registers the skill.

Verify the current scaffolder install pattern: `git clone … ~/.claude/skills/agenticapps-workflow`. This puts `add-observability/` at `~/.claude/skills/agenticapps-workflow/add-observability/` — nested. Claude Code's skill discovery walks `~/.claude/skills/*` and finds `agenticapps-workflow/` only; the nested `add-observability/` isn't discovered as a separate skill.

**Fix**: update the scaffolder install instructions (and `setup/SKILL.md` if it owns this) so that after `git clone … ~/.claude/skills/agenticapps-workflow`, a follow-up step symlinks the nested skill to a top-level location:

```bash
ln -sfn ~/.claude/skills/agenticapps-workflow/add-observability \
        ~/.claude/skills/add-observability
```

The symlink lives at the global top-level path Claude Code's discovery sees. The target (the scaffolder's nested copy) is the source of truth — updates via `git pull` in the scaffolder repo propagate automatically through the symlink. No file duplication.

**Files touched**:
- `README.md` (scaffolder root) — install instructions add the symlink step.
- `setup/SKILL.md` — if/where it documents the install layout, mention the symlink.

**Idempotency / verification**:
- `ln -sfn` is itself idempotent.
- `test -L ~/.claude/skills/add-observability && readlink ~/.claude/skills/add-observability | grep -q 'agenticapps-workflow/add-observability'`

**Commit**: `feat(setup): promote add-observability to top-level skill via symlink (closes part of #22)`

---

#### T2 — Backport slash-discovery fix to migration 0002 + add migration 0012

**Touches**: `migrations/0002-observability-spec-0.2.1.md`, `migrations/0012-init-and-slash-discovery.md` (new).

**0002 changes**: Step 1 already does the per-project install. Add a new sub-step that adds the global symlink if not already present:

```bash
# Idempotent: only create if symlink missing OR pointing elsewhere
if [ ! -L "$HOME/.claude/skills/add-observability" ]; then
  ln -sfn "$HOME/.claude/skills/agenticapps-workflow/add-observability" \
          "$HOME/.claude/skills/add-observability"
fi
```

The per-project copy under `.claude/skills/add-observability/` remains as a project-level audit marker but is no longer the discovery path.

**0012 (new migration)**: Backport the slash-discovery fix for projects already at v1.10.0 (i.e., they ran 0002 before this PR landed).

```yaml
id: 0012
slug: init-and-slash-discovery
title: Ship add-observability/init/INIT.md + fix slash-command discovery (closes #22, #26)
from_version: 1.10.0
to_version: 1.11.0
applies_to:
  - ~/.claude/skills/add-observability (symlink — creates if missing)
  - .claude/skills/agentic-apps-workflow/SKILL.md (version bump)
requires:
  - skill: agentic-apps-workflow
    install: "(scaffolder install)"
    verify: "test -d ~/.claude/skills/agenticapps-workflow/add-observability"
```

Steps:
- **Step 1 — Install global symlink**: `ln -sfn ~/.claude/skills/agenticapps-workflow/add-observability ~/.claude/skills/add-observability`. Idempotency: `readlink` returns the expected target.
- **Step 2 — Verify slash-discoverability**: `test -f ~/.claude/skills/add-observability/SKILL.md && grep -q '^name: add-observability' ~/.claude/skills/add-observability/SKILL.md` — confirms Claude Code's discovery will find it.
- **Step 3 — Bump scaffolder version**: `sed -i.bak 's/^version: 1.10.0$/version: 1.11.0/'`.

Update `migrations/README.md` chain table.

**Idempotency / verification**:
- Re-running 0012 reports "skipped (already applied)" on all three steps.
- New fixture coverage under `migrations/test-fixtures/0012/`.

**Commit**: `feat(migrations): 0002 + 0012 — slash-discovery via global symlink (option C, closes #22)`

---

#### T3 — Test fixtures for migration 0012

**Touches**: `migrations/test-fixtures/0012/` + `migrations/run-tests.sh` `test_migration_0012()` stanza.

5 fixtures (state-comparison pattern matching 0011):

| # | Scenario | Expected |
|---|---|---|
| 01-fresh-apply | v1.10.0 project, no `~/.claude/skills/add-observability` symlink | Steps 1-3 apply; symlink present; version 1.11.0 |
| 02-idempotent-reapply | After fixture 01, re-run | All 3 step idempotency checks return 0 |
| 03-symlink-already-exists | `~/.claude/skills/add-observability` already symlinked correctly | Step 1 idempotent; rest proceeds |
| 04-symlink-wrong-target | `~/.claude/skills/add-observability` exists pointing elsewhere | Step 1 errors with exit 4 ("applied with warning"); user must resolve manually |
| 05-rollback | After fixture 01, run rollback procedure | Symlink removed; version reverted |

**Commit**: `test(migrations): 0012 fixtures (5 scenarios)`

---

### Phase 2 — Author `init/INIT.md` skeleton

#### T4 — `add-observability/init/INIT.md` skeleton with 9 phases

**Touches**: `add-observability/init/INIT.md` (create).

Skeleton structure (each phase fleshed out per-stack in subsequent tasks T5-T9):

```
# `init` subcommand procedure

## Inputs
- Project root (CWD)
- --stack <id> (optional, default: walk all detected stacks)
- --force (optional, v0.4.0+; rejected at v0.3.1)

## Outputs
- Wrapper module(s) materialised at meta.yaml `target.wrapper_path`
- Middleware materialised (where applicable per stack)
- policy.md materialised per-stack
- Entry file(s) rewritten with observability wrap + anchor comments
- `observability:` metadata block written to CLAUDE.md

## Procedure

### Phase 1 — Detect stacks
(Identical to scan/SCAN.md Phase 1; reuse the same detection rules.)

### Phase 2 — Resolve targets
For each detected stack: read meta.yaml, resolve target.* paths against
the module root (NOT project root, per spec §10.7.1), resolve parameters
per derive_from rules.

### Phase 3 — Confirm intent (consent block 1 of 3)
Present the user with a summary: "About to scaffold observability for
<N> stack(s): <list>. New files: <list>. Edits to existing files:
<entry-file>, CLAUDE.md. Continue? [y/n/per-stack]"

### Phase 4 — Materialise wrapper + middleware + policy (consent block 2 of 3)
For each stack: copy template files to target paths, performing token
substitution. Anchor wrapper insertions with
`// agenticapps:observability:start` / `:end` (Go variant `//`; TS `//`;
Python `#`).
Consent: "Apply these N new files? [y/n]"

### Phase 5 — Rewrite entry file (consent block 3 of 3)
For each stack with `entry_file_candidates`, scan the project for the
first matching candidate. Diff-and-confirm before rewriting.
(Detailed per-stack rewrite shapes in tasks T5-T9.)

### Phase 6 — Write `observability:` metadata to CLAUDE.md
Per spec §10.8. Multi-stack projects get one block listing all stacks.
Anchor with `<!-- agenticapps:observability:start -->` / `:end`.

### Phase 7 — Smoke verification
For each materialised stack: run a language-native syntax check
(`tsc --noEmit` / `go build` / `deno check`). If failures, report but
do not auto-fix — user reviews and applies.

### Phase 8 — Print summary + chain hint
Summary: "Init complete. <N> stacks scaffolded: <list>." Chain hint:
"If you previously ran `add-observability scan`, the report is stale;
re-run scan."

### Phase 9 — Verification before exit
Confirm wrapper files exist, parameters substituted (no
unfilled `{{...}}` tokens), entry file's anchor comments parse, CLAUDE.md
metadata block present.

## Important rules
- Never run if wrapper directory already exists (v0.3.1 strict).
- Anchor comments are load-bearing — never edit by hand outside the
  anchored block; that's an init-rewrite-only zone.
- Parameter substitution uses `{{NAME}}` tokens; missing values default
  per meta.yaml or error if no default.

## Verification before exiting
- All target.* files exist with no unfilled tokens.
- Entry file's anchor block parses.
- CLAUDE.md observability block validates against §10.8 schema.
```

**Idempotency / verification**:
- `grep -E '### Phase [1-9]' add-observability/init/INIT.md` returns 9 matches.

**Commit**: `feat(add-observability): init/INIT.md skeleton (9 phases)`

---

### Phase 3 — Per-stack init procedure sections

T5-T9 each flesh out ONE stack's Phase 5 (entry-file rewrite) — the shape that meta.yaml only sketches. Each task is one stack: rewrite shape pre/post, anchor placement, parameter substitution details, edge cases. Each stack also gets a test fixture pair.

#### T5 — `ts-cloudflare-worker` init procedure + fixture
**Touches**: INIT.md "Phase 5 — `ts-cloudflare-worker`" subsection; `migrations/test-fixtures/init-ts-cloudflare-worker/{before,expected-after}/`.
- Rewrite shape: `export default { fetch: handler }` → `export default { fetch: withObservability(handler) }` (with anchor comments before/after).
- `withObservability` is provided by the scaffolded `lib/observability/index.ts`.
- Edge: handler defined inline vs imported (procedure handles both via diff-preview).
- Fixture: minimal Worker project with `wrangler.toml` + `src/index.ts` exporting a handler; init scaffolds; expected-after shows the wrapper + middleware + rewritten entry + policy.md + CLAUDE.md block.

**Commit**: `feat(add-observability): init for ts-cloudflare-worker + fixture`

---

#### T6 — `ts-cloudflare-pages` init procedure + fixture
**Touches**: INIT.md subsection; fixture pair.
- Rewrite shape: `export function onRequestGet(ctx) { … }` → wrap each `onRequest*` export with `withObservability`.
- Edge: multiple `onRequest*` exports per file; init rewrites all.
- Fixture: `functions/api/[[path]].ts` with multiple handlers.

**Commit**: `feat(add-observability): init for ts-cloudflare-pages + fixture`

---

#### T7 — `ts-supabase-edge` init procedure + fixture
**Touches**: INIT.md subsection; fixture pair.
- Rewrite shape: `Deno.serve(handler)` → `Deno.serve(withObservability(handler))`.
- Edge: Deno-specific imports for wrapper (`import { withObservability } from "../_shared/observability/index.ts"`).
- Fixture: `supabase/functions/myfunc/index.ts`.

**Commit**: `feat(add-observability): init for ts-supabase-edge + fixture`

---

#### T8 — `ts-react-vite` init procedure + fixture
**Touches**: INIT.md subsection; fixture pair.
- No handler concept. Init wraps the ReactDOM root + installs `ErrorBoundary` at the top of the component tree.
- Rewrite shape: `ReactDOM.createRoot(rootEl).render(<App />)` → `ReactDOM.createRoot(rootEl).render(<ObservabilityProvider><ErrorBoundary><App /></ErrorBoundary></ObservabilityProvider>)`.
- Init must add 2 imports + wrap the render call. Anchor comments around imports + around the JSX.
- Fixture: `src/main.tsx`.

**Commit**: `feat(add-observability): init for ts-react-vite + fixture`

---

#### T9 — `go-fly-http` init procedure + fixture
**Touches**: INIT.md subsection; fixture pair.
- Rewrite shape: for `mux.HandleFunc("/path", handler)`, no rewrite at registration — middleware applies via `mux := observability.Middleware(http.HandlerFunc(...))` at server boot. So the rewrite is at the entry point where `http.ListenAndServe` is called.
- Edge: chi router uses `r.Use(observability.Middleware)` instead.
- Init detects pattern (chi vs net/http vs gorilla/mux) and picks the right wrap shape.
- Fixture: `cmd/api/main.go` with std net/http.

**Commit**: `feat(add-observability): init for go-fly-http + fixture`

---

### Phase 4 — Default policy.md templates + observability metadata block

#### T10 — Per-stack `policy.md` template files
**Touches**: `add-observability/templates/<stack>/policy.md.template` (new for each of 5 stacks).

Each template has 3 sections:
- `## Trivial errors` pre-populated per language (Go: `pgx.ErrNoRows`, `sql.ErrNoRows`, `context.Canceled`, `context.DeadlineExceeded`; TS: HTTP 4xx-returning errors, validation errors).
- `## Redacted attributes` defaults to `password|token|api_key|card_number|cvv`.
- `## Project event names` empty placeholder section with a `<!-- add domain events here -->` comment.

**Commit**: `feat(add-observability): per-stack policy.md templates`

---

#### T11 — `observability:` metadata block writer per spec §10.8

**Touches**: INIT.md Phase 6 + `add-observability/init/metadata-template.md` (new — the YAML block schema).

The block:

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: <wrapper-dir>/policy.md   # per-stack path; array if multi-stack
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

Multi-stack projects get `policy:` as an array of paths.

**Commit**: `feat(add-observability): observability metadata block writer (§10.8)`

---

### Phase 5 — Skill SKILL.md + version bumps

#### T12 — Bump skill `0.3.0 → 0.3.1` and document init in the description
**Touches**: `add-observability/SKILL.md`.

- Frontmatter: `version: 0.3.1`.
- Description: expand the `init` subcommand row to reference the now-shipped procedure and the 9-phase flow.
- Routing table verification check: add a structural note that `./init/INIT.md` MUST exist on disk (closes #26).

**Commit**: `chore(version): add-observability 0.3.0 → 0.3.1 (init shipped)`

---

#### T13 — Bump scaffolder `1.10.0 → 1.11.0` + CHANGELOG entry
**Touches**: `skill/SKILL.md`, `CHANGELOG.md`.

CHANGELOG `[1.11.0] — Unreleased` section above `[1.10.0]`:
- `add-observability/init/INIT.md` shipped — closes #26 + §10.7 obligations (1) and (2).
- Slash-discovery via global symlink (closes #22).
- Migration 0012 (1.10.0 → 1.11.0).
- 5-stack init fixtures.
- Updates CHANGELOG `[1.10.0]` to mark the init-blocker as resolved (cross-reference to v1.11.0).

**Commit**: `docs(changelog): record v1.11.0 — init shipped + slash discovery`

---

### Phase 6 — Multi-AI review (pre-execution gate)

**Required before any of T1-T13 starts.** Same pattern as Phase 14 — invoke codex + gemini for independent review of PLAN.md, plus a Claude self-review. **New structural check**: every manifest- or routing-table-referenced path MUST resolve. This is the codification of the lesson from Phase 14's miss.

Specifically the reviewer prompt adds:

> Q8 — Structural existence check: for every file path referenced in `add-observability/SKILL.md`, `meta.yaml`, or migration manifests, does the target file exist on disk? Run `grep -E "'\.?/?init/INIT\.md|'\.?/?scan/SCAN\.md|'\.?/?scan-apply/APPLY\.md'" <referencing-file> | while read ref; do test -f <resolved-path> || echo MISSING <path>; done`. If any path is MISSING, that's a BLOCK.

Generate `15-REVIEWS.md` from the 3 reviews; address required revisions before T1.

---

### Phase 7 — Verification + close

#### T14 — End-to-end smoke test
**Touches**: nothing in skill; produces `.planning/phases/15-init-and-slash-discovery/smoke/output.txt`.

Cut a fresh empty Node project (sandboxed via `mktemp -d`):
1. Apply scaffolder install + symlink (Phase 1 / T1+T2 changes).
2. Run `claude /add-observability init` against a minimal Worker fixture.
3. Run `claude /add-observability scan` — confirms post-init scan shows zero high-confidence gaps (the wrapper is just-shipped, no instrumentation gaps yet).
4. Run migration 0011 (`/update-agenticapps-workflow`).
5. Assert project is at v1.10.0 with valid baseline.json (the v1.10.0 path now works end-to-end since init is shipped).
6. Run migration 0012.
7. Assert project at v1.11.0.

If any step fails, that's a stop-the-line bug. Capture full output.

**Commit**: `test(smoke): end-to-end v1.9.3 → v1.10.0 → v1.11.0 via init + 0011 + 0012`

---

#### T15 — VERIFICATION.md
**Touches**: `.planning/phases/15-init-and-slash-discovery/VERIFICATION.md`.

1:1 must-have → evidence ledger covering:
- §10.7 obligation (1) wrapper scaffold — for each of 5 stacks.
- §10.7 obligation (2) middleware wired — for each stack that has middleware.
- §10.7 obligation (4) apply with consent — 3 consent blocks present.
- §10.8 metadata block written — fixture assertion.
- Anchor comments idempotent re-detection — fixture 02 of T5-T9.
- Slash discovery — symlink present after migration 0012 fixture 01.
- Migration 0012 — 5/5 fixtures green.
- Smoke test — end-to-end path green.
- Phase 14 regression: all 0011 + earlier fixtures still green; 61 contract tests still green.

**Commit**: `docs(verification): phase 15 evidence ledger`

---

#### T16 — `/review` + `/cso` post-phase

`/review` against the branch diff. `/cso` focused on:
- The default `REDACTED_KEYS` list — is it sufficient for sensitive data?
- The anchor-comment pattern — can attacker-contributed code inject anchor comments to bypass detection?
- Symlink-based discovery — symlink-following CVEs are a real pattern; should we check for symlink-target tampering?

**Commits**: `docs(review): phase 15 — REVIEW.md` + `docs(security): phase 15 — SECURITY.md`.

---

#### T17 — Session handoff + PR

Open PR `feat: ship init procedure + slash discovery (v1.11.0)` against main. Reference #22, #26, #24 in the description.

---

## Wave dependency graph

```
T1 (layout refactor) ─┐
T2 (migrations 0002 + 0012) ─┤  Phase 1 — slash discovery
T3 (0012 fixtures)            ─┘
                              ▼
T4 (INIT.md skeleton) ── must be done before any of T5-T9
                              ▼
T5 (ts-cloudflare-worker) ─┐
T6 (ts-cloudflare-pages)   ─┤  Phase 3 — per-stack init (can be parallelized but
T7 (ts-supabase-edge)      ─┤  sequential per the migration-fixture lesson —
T8 (ts-react-vite)         ─┤  one stack's fixture-stub bug shouldn't block 4
T9 (go-fly-http)           ─┘  others)
                              ▼
T10 (policy.md templates) ─┐
T11 (metadata writer)     ─┤  Phase 4 — supporting artefacts
                          ▼
T12 (skill version bump) ─┐
T13 (scaffolder + CHANGELOG) ─┤  Phase 5 — versions
                              ▼
   ━━━ Multi-AI review gate (Phase 6) ━━━ [REQUIRED before T1 if strict; 
                                          recommended NOW since structure is
                                          settled and reviewers can spot the 
                                          per-stack wrap shapes before code]
                              ▼
T14 (smoke) ─┐
T15 (VERIFICATION) ─┤  Phase 7 — verify + close
T16 (review + cso) ─┤
T17 (handoff + PR)
```

Concrete execution order: T1, T2, T3, T4, multi-AI review, T5-T9 (parallel-ish), T10, T11, T12, T13, T14, T15, T16, T17.

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Symlink fix breaks existing fresh installs of the scaffolder | Low | T1 backwards-compatible: existing installs without the symlink work as today (degraded — no slash-discovery); migration 0012 forward-fixes |
| Per-stack entry-file rewrite is wrong for one stack | Med | T5-T9 each ship a fixture exercising the rewrite shape; if a fixture fails, that stack's procedure is wrong |
| Anchor-comment pattern subverted by code formatters | Med | `// agenticapps:observability:start` is a comment; gofmt/prettier preserve it. Test in each stack's fixture. |
| Multi-stack monorepo CLAUDE.md write order non-deterministic | Med | Lexicographic sort on stack_id; same as baseline.json sort in Phase 14 |
| Smoke test in T14 fails on a fixture project that doesn't exist | High at start, Low after T5-T9 | Smoke uses one of T5-T9's fixtures as its starting state. |
| Multi-AI review surfaces a different INIT.md shape | Med | Same pattern as Phase 14: incorporate into PLAN v2 before T1 starts |
| Symlink-target tampering CVE class | Low | T16 `/cso` review covers this. The symlink target is inside the scaffolder repo's git-managed tree; attacker would need filesystem write access to alter it. |

---

## Out of scope (deferred to v1.12.0+)

- **`init --force` re-init** — D5 decision; defer to a future version.
- **Pre-commit hook template** (§10.9.4 MAY) — same deferral as Phase 14.
- **Standalone Node scanner port** — downgraded after Option 4 pivot.
- **fx-signal-agent retroactive adoption** — separate consumption work; should follow phase 15 to validate the v1.9.3 → v1.11.0 path.
- **Python / Rust / Java stacks** — new templates are their own phases.
- **`init` interactive multi-stack pickers** (D3 "C" option) — current PLAN ships walk-all + `--stack <id>` override.
