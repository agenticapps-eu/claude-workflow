# Phase 15 — CONTEXT — Ship `init/INIT.md` + fix slash-command discovery

**Date**: 2026-05-15
**Branch**: `feat/init-and-slash-discovery-v1.11.0`
**Scaffolder bump**: `1.10.0 → 1.11.0`
**Skill bump**: `add-observability` `0.3.0 → 0.3.1` (patch — still `implements_spec: 0.3.0`; closes a long-standing §10.7 gap)
**Migration slot**: `0012-observability-init-procedure.md`

## Origin

Two issues filed against PR #25 (post-merge):

- **#26** — `add-observability/SKILL.md` (v0.3.0) routes the `init` subcommand to `./init/INIT.md`, but that file **does not exist**. CONTRACT-VERIFICATION.md has openly admitted this gap since v0.2.1: *"Section 10.8 (project metadata) is written by the skill's init subcommand (task #3 follow-up — wiring not yet implemented in the skill itself)."*
- **#22** — Migration 0002 installs `add-observability` per-project at `.claude/skills/add-observability/`, but Claude Code's slash-command discovery walks `~/.claude/skills/*` (global) rather than per-project. So `/add-observability init` is not invocable even after migration 0002 applies.

Together these block every fresh-project upgrade path to v1.10.0:

1. Project on v1.9.3 tries to upgrade via `/update-agenticapps-workflow`.
2. Migration 0011 pre-flight: "Run `/add-observability init` first."
3. User tries `/add-observability init` → not slash-discoverable (#22).
4. Even if invoked manually, the procedure prompt at `init/INIT.md` doesn't exist (#26).
5. Stuck at v1.9.3.

Issue **#24** (parent v0.3.0 adoption checklist) confirms: "Ship an `add-observability` skill satisfying §10.7's five obligations: scaffold per-stack wrappers, wire traceparent middleware…" is **unchecked**.

## Why we shipped over this in Phase 14

The Phase 14 multi-AI review (codex + gemini + Claude self) all read `SKILL.md` and accepted the routing table without verifying the target files existed on disk. None of the three reviewers ran a structural-existence check on manifest-referenced paths. The CONTRACT-VERIFICATION.md "wiring not yet implemented" admission was visible but didn't surface as a blocker because Phase 14's scope was §10.9 enforcement, not §10.7 init.

**Lesson codified for future phases**: every manifest- or routing-table-referenced path must resolve. This becomes a structural pre-execution check in the multi-AI review template (added to `gsd-review` prompt template in this phase).

## What §10.7 actually demands of generators

Spec §10.7 (re-read in context of this phase):

> A conformant generator MUST:
> 1. Scaffold a wrapper module per stack into the target project.
> 2. Wire trace-propagation middleware into the entry-point file.
> 3. Validate existing projects against §10.4 and produce a confidence-ranked report.
> 4. Apply only with consent (no auto-application of changes).
> 5. (Added v0.3.0) Support delta scan + maintain a project baseline file per §10.9.

The skill currently implements (3), (4), and (5). It does NOT implement (1) and (2). INIT.md is the procedure that closes those.

## Current state of the skill

| Artefact | Status | What it does |
|---|---|---|
| `SKILL.md` | exists, **broken** | dispatch table routes `init` → `./init/INIT.md` (missing); `scan` → `./scan/SCAN.md` (works); `scan-apply` → `./scan-apply/APPLY.md` (works) |
| `scan/SCAN.md` | exists | brownfield audit procedure (v0.3.0, includes §10.9.1 delta scan) |
| `scan-apply/APPLY.md` | exists | apply consented findings + regen baseline (v0.3.0, includes §10.9.2 regen) |
| `init/INIT.md` | **MISSING** | greenfield scaffold procedure — what this phase ships |
| `templates/<stack-id>/` | exists for all 5 stacks | per-stack source files: wrapper, middleware (where applicable), env-additions doc, contract tests, meta.yaml |
| `templates/<stack-id>/meta.yaml` | exists for all 5 | declares `detection`, `target` paths, `parameters` (with `derive_from` rules), `entry_file_candidates` |
| `enforcement/observability.yml.example` | exists (v1.10.0) | opt-in §10.9.3 CI workflow |

## What the 5 stacks need for init

Each stack's `meta.yaml` already declares the data INIT.md will orchestrate. Per-stack divergence summary:

| Stack | Has middleware? | Entry-file kind | Target wrapper dir | Notable param |
|---|---|---|---|---|
| `ts-cloudflare-worker` | yes (`middleware.ts`) | `fetch`/`scheduled`/`queue` default export | `src/lib/observability/` | `SERVICE_NAME` from `wrangler.toml [name]` |
| `ts-cloudflare-pages` | inherits worker | `onRequest{,Get,Post,…}` exports | `functions/lib/observability/` (TBC) | inherits |
| `ts-supabase-edge` | yes (Deno-flavored) | `Deno.serve(handler)` | `supabase/functions/_shared/observability/` | Deno-import URLs |
| `ts-react-vite` | **no middleware** — `ErrorBoundary.tsx` instead | `main.tsx` ReactDOM root | `src/lib/observability/` | `VITE_SENTRY_DSN` env var prefix |
| `go-fly-http` | yes (`middleware.go`) | `mux.HandleFunc` / chi router | `internal/observability/` | `PACKAGE_NAME`, `MODULE_PATH` from go.mod |

The init procedure must walk per-stack — there's no one-size-fits-all rewrite shape. INIT.md's structure will be: per-stack section, each with materialise → substitute → wrap entry → write policy → write CLAUDE.md block.

## Slash-discovery options (#22)

The four options from issue #22, with my read on each:

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| **A** — symlink at install | Migration 0002 adds `ln -s "$PWD/.claude/skills/add-observability" "$HOME/.claude/skills/add-observability"` after `cp -r` | Smallest patch; both per-project and global presence preserved | Ties global name to one project at a time. Last-project-installed wins. |
| **B** — global-only install | Migration 0002 writes to `~/.claude/skills/add-observability/` directly; path-root resolution stays project-relative at runtime | Cleanly machine-wide; slash-discovery works everywhere | Per-project install marker becomes purely informational; rollback semantics change |
| **C** — promote scaffolder layout | Move `add-observability/` out of the nested scaffolder skill directory; it becomes a top-level skill that the scaffolder install registers globally | Cleanest architecturally; no cp/symlink at all | Larger refactor; touches setup/SKILL.md, layout docs; affects every consumer's install path |
| **D** — drop the slash claim | Document invocation as "ask Claude to follow `<skill-path>/SKILL.md`" — don't promise a slash command | Zero code change; honest about current state | UX regression; loses the discoverability benefit the spec implies |

Pre-decision in RESEARCH.md but my lean: **C** — promote out of the nested layout. Issue #22 itself notes "the upstream copy that migration 0002 sources from lives nested inside the scaffolder skill directory, so it is also not a top-level entry under `~/.claude/skills/` and would not be discovered there either". Fixing this at the scaffolder-layout level closes both the per-project install and the upstream discovery in one move. Trade-off is real (more touched files) — surface in RESEARCH.

## Migration 0012 outline

| | |
|---|---|
| `from_version` | 1.10.0 |
| `to_version` | 1.11.0 |
| `applies_to` | scaffolder layout change (if option C); slash-discovery wire-up; bump skill 0.3.0 → 0.3.1 |
| Pre-flight | scaffolder at 1.10.0; Claude Code installed; jq |
| Step 1 | Apply slash-discovery fix (per chosen option from RESEARCH) |
| Step 2 | Verify `/add-observability init` is now slash-discoverable |
| Step 3 | Bump `.claude/skills/agentic-apps-workflow/SKILL.md` 1.10.0 → 1.11.0 |

Migration 0012 does NOT install INIT.md — INIT.md ships as part of the scaffolder skill itself (not via project-side migration). The migration's role is to fix discoverability so that an existing v1.10.0 project can invoke `/add-observability init` and reach the now-shipped procedure.

## Out of scope for Phase 15

- **Pre-push hook (§10.9.4 MAY)** — separate phase, lower priority than init.
- **Standalone Node scanner port** — downgraded; only valuable if we ever ship the CI gate, which Option 4 ruled out for now.
- **fx-signal-agent retroactive adoption of 0011** — separate consumption work; blocked on this phase.
- **Per-stack new template additions** — Python, Rust, Java not in scope.
- **policy.md content review** — ship the v0.3.1 default template; substantive policy curation is its own conversation.

## Coverage matrix (what init MUST orchestrate per §10.7 bullet 1+2)

(Updated to match PLAN.md v2 T4's 9-phase INIT.md skeleton; supersedes v1's draft phase numbering.)

| §10.7 obligation | INIT.md section | Source data |
|---|---|---|
| Stack detection | "Phase 1 — Detect stacks" | reuses `scan/SCAN.md` Phase 1 detection rules |
| Target resolution | "Phase 2 — Resolve targets" | meta.yaml + spec §10.7.1 module-root resolution |
| Plan summary (informational; not a gate) | "Phase 3 — Show full plan" | aggregated outputs from Phases 1-2 |
| **Scaffold wrapper module + middleware + policy.md** (consent gate 1 of 3) | "Phase 4 — Materialise wrapper + middleware + policy" | meta.yaml `target.{wrapper_path, middleware_path, policy_path}` + per-stack templates |
| **Edit entry file** (consent gate 2 of 3) | "Phase 5 — Rewrite entry file" | meta.yaml `target.entry_file_candidates` + per-stack wrap shape (T5-T9) |
| **Write CLAUDE.md metadata block** (consent gate 3 of 3) | "Phase 6 — Write `observability:` metadata to CLAUDE.md" | spec §10.8 schema; **scalar `policy:`** (v0.3.1 contract — see PLAN.md T11) |
| Smoke verification | "Phase 7 — Smoke verification" | language-native syntax check per stack |
| Summary + chain hint (D7) | "Phase 8 — Print summary + chain hint" | (stale-scan-report detection) |
| Verification | "Phase 9 — Verification before exit" | structural assertions on materialised files |
| Parameter substitution | cross-cutting (Phase 4) | meta.yaml `parameters.<NAME>.{default,derive_from}` |
| Consent | gates at Phases 4, 5, 6 | hybrid consent per RESEARCH D2 (PLAN v2: gates are `scaffold` / `entry-file` / `CLAUDE.md` — replaces v1's draft `intent / scaffold / entry-file`); spec §10.7 bullet 4. Decline of gate 2 ⇒ skip gate 3 + print rollback hint. Decline of gate 3 ⇒ print warning that future `/update-agenticapps-workflow` will fail until block is added manually. |

## Verification budget

- Each of the 5 stacks ships an init-fixture pair: bare project → run INIT.md procedure → assert end-state matches a checked-in `expected-after/` directory.
- `bash migrations/run-tests.sh 0012` 4+ fixtures: slash-discovery before/after, version bump, rollback.
- All 61 v0.2.1 contract tests stay green (regression-guarded by zero template diff).
- All 6 migration-0011 fixtures stay green.
- Smoke test: cut a fresh empty Node project, run init for `ts-cloudflare-worker`, then run migration 0011 — full v1.9.3 → v1.10.0 → init → v1.11.0 path works end-to-end.

## Open questions for RESEARCH.md / discuss

1. **Slash-discovery option** A vs B vs C (or D as honesty fallback)?
2. **INIT.md procedure shape** — interactive walk (one phase at a time with prompts) vs declarative (single unified diff for the user to accept)?
3. **Multi-stack monorepo** — init walks each detected stack independently (one CLAUDE.md write at the end aggregating all stacks) or one stack per invocation (user re-runs for each)?
4. **policy.md template** — single canonical default, or per-stack defaults (since trivial-errors differ between Go and TS)?
5. **`init --force`** — should re-init be allowed (e.g., to refresh a stale wrapper) or strict-first-run-only?
6. **Entry-file rewrite safety** — what if the user has customised the entry file post-init? Spec §10.7 bullet 4 ("apply only with consent") covers this but the procedure needs a stale-detection step.
