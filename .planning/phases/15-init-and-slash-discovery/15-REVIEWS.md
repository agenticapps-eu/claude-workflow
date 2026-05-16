# Phase 15 — REVIEWS — Pre-execution peer review of PLAN.md

**Date**: 2026-05-15
**Reviewers**: 3 (codex-cli 0.130.0, gemini 0.28.2, Claude Opus 4.7 phase author)
**Subject**: `.planning/phases/15-init-and-slash-discovery/PLAN.md` v1 (initial draft, commit `6d8cce7`)
**Verdict aggregate**: **BLOCK** — codex returned BLOCK on Q1+Q2+Q3+Q4+Q8 (five questions). Gemini and Claude returned REQUEST-CHANGES. Codex's reading is authoritative on Q4 (per-stack rewrite shapes) because codex actually read each stack's template source files and surfaced concrete contradictions between PLAN.md and the shipped templates. PLAN.md must be revised before T1 starts.

Raw reviewer outputs live in `.codex-review.md`, `.gemini-review.md`, `.claude-review.md` (gitignored — not committed). The `.review-prompt.md` is also gitignored per Phase 14's pattern. This file is the consolidated, committed record.

---

## Reviewer roster

| Reviewer | Tool | Mode | Result |
|---|---|---|---|
| Codex GPT-5 | `codex exec --skip-git-repo-check` | full tool access, full workspace + spec dir read, ran Q8 mechanical script + read every per-stack template source file | **BLOCK** (Q1, Q2, Q3, Q4, Q8) |
| Gemini Code Reviewer v1.0 | `gemini --allowed-tools "read_file,list_directory,search_file_content,glob"` | read-only, workspace-only — could not execute the Q8 shell script (no `run_shell_command`); inferred Q8 manually | REQUEST-CHANGES (Q6 BLOCK on risk-register completeness) |
| Claude Opus 4.7 (phase author) | self-review, structured | full workspace + spec; ran Q8 mechanical script before review | REQUEST-CHANGES (consent-3 trap + drift) |

The 3-reviewer floor declared by migration 0005 pre-flight is met (2 CLIs available + 1 host Claude). No reviewer was a sub-agent of another; codex and gemini were invoked as independent OS processes.

**New for Phase 15**: Q8 (structural existence check) codifies the lesson from Phase 14's miss — the question that all three Phase 14 reviewers failed to ask. Q8 produced the expected MISSING `add-observability/init/INIT.md` (correctly tagged "create" in T4), but **codex's Q8 also flagged 6 PLAN.md Touches paths that were silently new without explicit `(create)` / `(new)` annotation**. That's a stricter reading of the structural rule and the right one to adopt going forward.

---

## Consolidated findings (by question)

### Q1 — Spec conformance: **BLOCK** (codex), FLAG (gemini, Claude)

Four spec-conformance gaps. Codex's findings (1) and (2) supersede Claude's softer "T8 needs explicit fetch-propagation statement" because codex read the template's expected shape verbatim:

1. **ts-react-vite rewrite shape is fabricated.** PLAN T8 wraps the root in `<ObservabilityProvider><ErrorBoundary><App /></ErrorBoundary></ObservabilityProvider>`. **Neither `ObservabilityProvider` nor `ErrorBoundary` (named that way) exists in the template.** Per `add-observability/templates/ts-react-vite/env-additions.md:55-73`, the canonical shape is:

   ```tsx
   import { init, ObservabilityErrorBoundary } from "./lib/observability"
   init()
   createRoot(...).render(<StrictMode><ObservabilityErrorBoundary><App /></ObservabilityErrorBoundary></StrictMode>)
   ```

   `init()` MUST be called before `createRoot(...).render(...)` because `init()` installs the global `fetch` interceptor (verified: `lib-observability.ts:131` — `window.fetch = instrumentedFetch(originalFetch)`). PLAN T8 omits `init()` entirely. **Without `init()`, §10.7 obligation (2) "wire trace-propagation middleware" is NOT satisfied for the Vite stack.** Note: Gemini's Q1 PASS on T8 was based on inferring fetch propagation from `meta.yaml` + `CONTEXT.md`; codex's reading of the actual template invalidates Gemini's PASS.

2. **ts-cloudflare-pages rewrite shape is wrong.** PLAN T6 wraps every `onRequest*` export individually with `withObservability`. But the shipped template's wiring path is `functions/_middleware.ts` — Pages' built-in middleware mount point that wraps all `onRequest*` exports automatically. Per-export wrapping is a duplicate, semantically incorrect path. **Fix**: T6 must materialise `functions/_middleware.ts` (already in `add-observability/templates/ts-cloudflare-pages/_middleware.ts`) and NOT rewrite individual route files.

3. **ts-supabase-edge import path + signature gap.**
   - `withObservability` lives in `../_shared/observability/middleware.ts`, NOT `index.ts` (the latter is the wrapper itself).
   - PLAN T7 ignores the `Deno.serve(options, handler)` 2-arg signature.
   - **Fix**: T7 procedure must (a) import from `middleware.ts`, (b) handle both `Deno.serve(handler)` and `Deno.serve(options, handler)` shapes.

4. **ts-cloudflare-worker scope too narrow.** T5 only covers `export default { fetch: handler }`. The declared stack covers `fetch`, `scheduled`, and `queue` handlers (per `CONTEXT.md:63` + `templates/ts-cloudflare-worker/middleware.ts:70-99`). **Fix**: T5 procedure wraps all three handler types in the default export object.

5. **§10.7 obligation (4) "apply only with consent" — consent design drift creates false-conformance.** RESEARCH D2 specified 3 consent blocks as `scaffold` / `entry file` / `CLAUDE.md`. PLAN T4 INIT.md skeleton ships `intent` / `scaffold` / `entry file` — **CLAUDE.md is written WITHOUT its own consent gate**. Worse: if the user declines the entry-rewrite consent, the project STILL gets a `CLAUDE.md observability:` block claiming conformance the wrapper hasn't established. **Fix**: replace PLAN's "intent" consent with the RESEARCH-mandated CLAUDE.md consent. The 3 blocks become `scaffold (new files)` / `rewrite entry` / `write CLAUDE.md observability block`. Decline of any of (2) or (3) MUST roll back consents (1) and (2) before exit, OR fall through with explicit warning that the project is in a partial state — no false-metadata write path.

6. **§10.8 metadata `policy:` is scalar in the spec AND in the upgrade-path parser.** PLAN T11 invents an array shape for multi-stack. Spec §10.8 line 157 shows `policy: lib/observability/policy.md` (scalar). **Migration 0011 line 63 parses with `awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}'` — array would break this hard.** **Fix**: For multi-stack, ship ONE policy path (use the first/primary stack's path) and document that multi-stack policy unification is deferred to a spec amendment. Do NOT introduce a v0.3.1 schema divergence that breaks 0011's pre-flight.

### Q2 — Slash-discovery option C: **BLOCK** (codex), PASS (gemini), FLAG (Claude)

Codex (correctly) escalates this to BLOCK on a finding all three reviewers should have caught:

1. **T1 is option A relabelled, not option C.** RESEARCH D1's option C: "Move `add-observability/` out of the nested scaffolder-skill directory → sibling skill → migration 0002 discovery no-op." T1: keeps the nested layout and adds a top-level symlink (the literal definition of option A). The PLAN preamble says "D1 = C (promote layout, user-confirmed)" — drift between label and implementation. **Fix**: re-label "D1 = A executed at scaffolder-install layer (true C deferred to v1.12.0+)".

2. **Fresh-install delivery is broken.** The real registration path is `install.sh:22-28`'s `LINKS` array. T1 lists "Files touched: README.md, setup/SKILL.md" — neither is the actual install entry point. Verified: `install.sh` has a `LINKS` array (`"skill agentic-apps-workflow"`, `"setup setup-agenticapps-workflow"`, `"update update-agenticapps-workflow"`) with NO row for `add-observability`. **Fix**: T1 MUST add a row `"add-observability add-observability"` to the `LINKS` array in `install.sh`. Without this, fresh installs remain undiscoverable, the symlink is never created, and migration 0012 has no idempotent prior-state to detect.

3. **install.sh's "refuse to clobber non-symlink" branch** (`install.sh:61-75`) is also a risk path that PLAN T1 doesn't address: if `~/.claude/skills/add-observability/` already exists as a real directory from a prior project-side migration 0002 (cp-copy install), install.sh will REFUSE to clobber it — fresh install fails. **Fix**: 0012's pre-flight must detect this case and either preserve-rename it (`.bak`) before T1's symlink runs, or document a manual remediation step.

Symlink mechanism itself: PASS — `git pull` works, existing v1.10.0 installs without the symlink keep working.

### Q3 — Migration 0012 design: **BLOCK** (codex), FLAG (gemini, Claude)

1. **D8 "both" is not delivered.** RESEARCH D8 chose "migration 0012 + setup-time fix". 0012 is concrete (T2); setup-time fix lives in T1 but T1 doesn't touch `install.sh` (Q2 #2 above). **Fix**: same as Q2 #2 — add to `install.sh` LINKS.

2. **Fixture 04 ("symlink-wrong-target" exit 4 with warning) is the wrong outcome.** Two reviewers (codex + gemini) flagged this; Claude's self-review accepted it. **Majority resolution**: for a scaffolder-owned registration path, the right outcomes are (a) overwrite OR (b) hard abort before version bump. "Applied with warning" leaves discovery broken (the migration claims success while discovery is silently wrong). **Fix**: change fixture 04 to **hard abort** with exit 1 and a clear "Manual intervention: existing symlink at ~/.claude/skills/add-observability points to $OTHER. Remove or move it before re-running 0012." message. NO version bump on this path.

3. **0012 title overstates scope.** PLAN T2 frontmatter title: `Ship add-observability/init/INIT.md + fix slash-command discovery (closes #22, #26)`. CONTEXT.md:96 says 0012 does NOT ship INIT.md — INIT.md ships via the scaffolder skill repo at v1.11.0. **Fix**: rename 0012 title to `Slash-command discovery wire-up (closes #22)`. Issue #26 is closed by the scaffolder skill bump itself (T12 + T4 ship INIT.md as part of the skill, not via migration). Add a comment at top of 0012 manifest body: "Note: INIT.md is delivered via the scaffolder skill repo at v1.11.0. This migration's role is discovery wire-up only."

4. **`requires: tool: claude`** — confirmed not needed (PASS). 0012 is file-ops only.

### Q4 — Per-stack rewrite shapes: **BLOCK** (codex), FLAG (gemini, Claude)

Codex BLOCKs based on direct reads of the shipped templates. All 5 stacks have shape problems (see Q1 #1-4 above for details). Summary:

| Stack | PLAN T# shape | Actual template shape | Verdict |
|---|---|---|---|
| ts-cloudflare-worker (T5) | only `fetch` wrap | `fetch` + `scheduled` + `queue` | NEEDS-FIX |
| ts-cloudflare-pages (T6) | per-export `onRequest*` wrap | `_middleware.ts` mount point | NEEDS-REWRITE |
| ts-supabase-edge (T7) | `index.ts` import + 1-arg only | `middleware.ts` import + 2-arg signature | NEEDS-FIX |
| ts-react-vite (T8) | `ObservabilityProvider` (fabricated) | `init()` + `ObservabilityErrorBoundary` | NEEDS-REWRITE |
| go-fly-http (T9) | "auto-detects" (unspecified) | std `net/http` + chi + gorilla concrete shapes | NEEDS-DETAIL |

**Fix scope**: T5-T9 each get rewritten to match the canonical shape documented in each stack's `env-additions.md` + `meta.yaml`. Codex's pointers (file:line) in `.codex-review.md` are the authoritative reference.

### Q5 — PLAN/RESEARCH/CONTEXT drift: **FLAG** (codex, Claude), PASS (gemini)

Six distinct drifts to resolve:

1. **D1 label** (Q2 #1): "C" → "A at scaffolder-install layer".
2. **D2 consent set** (Q1 #5): `intent / scaffold / entry-file` → `scaffold / entry-file / CLAUDE.md` (RESEARCH-mandated).
3. **0012 title** (Q3 #3): drop INIT.md from the title.
4. **CONTEXT Coverage matrix vs PLAN T4 phase numbering**: CONTEXT lists "Phase 4 — Materialise wrapper / Phase 5 — Wire middleware / Phase 6 — Edit entry / Phase 7 — Write policy / Phase 8 — Write metadata". PLAN T4 INIT.md skeleton merges these into 9 phases with different boundaries. **Fix**: update CONTEXT.md Coverage matrix to match PLAN T4's phase numbering (PLAN is more recent + structurally cleaner — anchor PLAN, update CONTEXT).
5. **T15 references "fixture 02 of T5-T9"** (`PLAN.md:361`) but T5-T9 define only one fixture pair each. **Fix**: either add a second fixture per stack ("02-idempotent re-apply", "02-stale-scan-report variant for D7 hint") OR drop the "fixture 02" reference and inline the assertions into the single fixture pair.
6. **All D1-D8 reflected in PLAN**: D1 (labelling drift but implementation present), D2 (consent drift), D3✓, D4✓, D5✓ (T4 "Important rules"), D6✓ (anchor comments throughout), D7 (chain hint in T4 Phase 8 — needs T15 evidence row, see Q7), D8 (broken via install.sh gap).

### Q6 — Risk register completeness: **BLOCK** (gemini), FLAG (codex, Claude)

Add these risks to PLAN.md's Risk Register. Each maps 1:1 to a finding above:

| Risk | Likelihood | Mitigation |
|---|---|---|
| `install.sh` LINKS array not updated → fresh installs undiscoverable | **High** if T1 leaves install.sh untouched | T1 MUST add `"add-observability add-observability"` row to LINKS (Q2 #2) |
| `~/.claude/skills/add-observability` exists as a real directory (from prior 0002 cp-install) → install.sh refuses to clobber → fresh-install fails | Med (any project that ran 0002 between v0.2.1 and v1.10.0 has this state) | 0012 pre-flight detects directory; either preserves as `.bak` or aborts with manual-remediation message (Q2 #3) |
| Consent decline of entry-rewrite → CLAUDE.md gets false `observability:` block | High (any user who reviews diffs cautiously) | Move CLAUDE.md write to its own consent gate; on decline, do NOT write metadata block (Q1 #5) |
| `policy:` array breaks migration 0011 POLICY_PATH parser | High in multi-stack adopt | Ship scalar `policy:` for v0.3.1 (use primary stack's path); defer multi-stack unification to spec amendment (Q1 #6) |
| BSD vs GNU `readlink -f` portability in run-tests.sh | Low | Lint for `readlink -f`; replace with portable form (Claude self-review) |
| Prettier `--prose-wrap=always` could re-wrap anchor comment text | Low-Med | Verify in T5-T9 fixtures with a Prettier config that has prose-wrap on (Claude self-review) |
| 6th stack (e.g. python-fastapi) extension friction | Low (future) | Document the extension procedure in INIT.md "Important rules" (Claude self-review) |
| `applies_to:` cross-tree path (`~/.claude/skills/...`) novel for migrations framework | Med | Confirm framework accepts paths outside project tree; comment in 0012 manifest (Claude self-review) |

### Q7 — Verification gaps: **FLAG** (codex, gemini, Claude)

Add these evidence rows to T15:

| Must-have | Evidence row |
|---|---|
| §10.7 (4) consent decline path tested | Fixture: synthetic INIT.md run where user declines consent at each of the 3 gates; assert post-state for each (no wrapper / no entry rewrite / no CLAUDE.md block) |
| §10.7 (2) Vite trace propagation wired via `init()` | T8 fixture asserts `init()` call appears at top of `main.tsx` AND `lib-observability.ts` is present AND its `window.fetch =` interceptor activates (structural grep) |
| §10.8 metadata block byte-shape | `jq -e` or YAML parse on the post-init CLAUDE.md observability block extracted via anchored markers; assert `.observability.policy` is scalar |
| Migration 0011 POLICY_PATH parser unchanged | Run `bash migrations/run-tests.sh 0011` after T1-T13; all 6 fixtures still green |
| All 61 v0.2.1 contract tests still green | ✓ already in PLAN T15 |
| D7 chain hint fires when stale `.scan-report.md` exists | Fixture variant `02-stale-scan-report` in one of T5-T9; assert chain hint emitted on stdout |
| install.sh LINKS row honored by fresh install | T14 smoke test step 1 runs `./install.sh` against a clean `~/.claude/skills/` and asserts `~/.claude/skills/add-observability` is a symlink to scaffolder path |

### Q8 — Structural existence check: **BLOCK** (codex), PASS (gemini, Claude)

Mechanical script output (Claude ran):

```
=== Q8.1 SKILL.md routing-table existence ===
  OK       ./enforcement/README.md
  MISSING  ./init/INIT.md          (PLAN T4 marks "create" — expected)
  OK       ./scan-apply/APPLY.md
  OK       ./scan/SCAN.md

=== Q8.2 meta.yaml template source files (per-stack) ===
  ts-cloudflare-worker: OK  (env-additions.md, lib-observability.{test.,}ts, meta.yaml, middleware.ts)
  ts-cloudflare-pages:  OK  (_middleware.ts, env-additions.md, meta.yaml)
  ts-supabase-edge:     OK  (env-additions.md, index.{test.,}ts, meta.yaml, middleware.ts)
  ts-react-vite:        OK  (ErrorBoundary.tsx, env-additions.md, lib-observability.{test.,}ts, meta.yaml)
  go-fly-http:          OK  (env-additions.md, meta.yaml, middleware.go, observability.{,_test.}go)

=== Q8.3 migration manifests ===
  OK       migrations/0002-observability-spec-0.2.1.md (applies_to: all)
  OK       migrations/0011-observability-enforcement.md (applies_to: 3 paths)
```

**Single MISSING is `./init/INIT.md` — explicitly tagged `(create)` in T4. That alone is not a blocker.**

**Codex's stricter Q8 catch (the real BLOCK)**: 6 PLAN.md `**Touches**:` paths reference NEW filesystem locations without explicit `(create)` / `(new)` annotation:

- `migrations/test-fixtures/0012/` (PLAN.md:94)
- `migrations/test-fixtures/init-ts-cloudflare-worker/` (PLAN.md:204)
- T6-T9 analogous fixture paths (PLAN.md:215, 225, 235, 246)
- `.planning/phases/15-init-and-slash-discovery/smoke/output.txt` (PLAN.md:336 — has "produces" wording but not the canonical `(new)`)
- `.planning/phases/15-init-and-slash-discovery/VERIFICATION.md` (PLAN.md:354)

**Fix**: every PLAN.md Touches path that is NEW must be explicitly annotated `(create)` or `(new)`. This is the structural rule Q8 enforces — same lesson Phase 14 missed for init/INIT.md, generalized to all manifest-or-PLAN-referenced paths.

**Lesson codified for future phases**: Q8 must be run mechanically by every reviewer; the script in `.review-prompt.md` is the canonical form (and has a bugfix needed — the regex was lowercase-only; codex caught this). The fixed regex `[a-zA-Z/_-]+\.md` is what produced Claude's PASS-with-MISSING-INIT result above.

---

## Required PLAN.md revisions before T1 may start

A single PLAN.md revision pass incorporating the following items. Each maps 1:1 to a finding above so the revision is auditable.

### BLOCK-class (must resolve before T1)

1. **T1** — add `"add-observability add-observability"` row to `install.sh:22-28` LINKS array. State this explicitly in T1's "Files touched". (Q2 #2)
2. **T1** — re-label as "option A at scaffolder-install layer (true C deferred)". (Q2 #1)
3. **T1** — add pre-flight check for `~/.claude/skills/add-observability` existing as a real directory (from prior 0002 cp-install); document remediation. (Q2 #3)
4. **T2 / T3** — change fixture 04 from "exit 4 with warning" to **hard abort exit 1** with manual-remediation message. NO version bump on this path. (Q3 #2)
5. **T2** — rename migration 0012 title to `Slash-command discovery wire-up (closes #22)`. Add manifest-body comment: "INIT.md ships via scaffolder skill at v1.11.0, not this migration." (Q3 #3)
6. **T4 INIT.md skeleton** — replace the 3 consent blocks with RESEARCH-mandated set: `scaffold (new files)` / `rewrite entry-file` / `write CLAUDE.md observability block`. On decline of (2) or (3), MUST roll back (1) and prior accepted gates, OR fall through with explicit no-false-metadata behaviour. (Q1 #5)
7. **T5** — extend Worker procedure to wrap `fetch`, `scheduled`, AND `queue` handlers (per CONTEXT and template middleware.ts:70-99). (Q1 #4 / Q4)
8. **T6** — REWRITE: drop per-export `onRequest*` wrapping; materialise `functions/_middleware.ts` from template. (Q1 #2 / Q4)
9. **T7** — fix import path to `../_shared/observability/middleware.ts`; handle both `Deno.serve(handler)` and `Deno.serve(options, handler)` shapes. (Q1 #3 / Q4)
10. **T8** — REWRITE: shape is `import { init, ObservabilityErrorBoundary }` + `init()` call before render + `<ObservabilityErrorBoundary>` wrap. No `ObservabilityProvider` (it doesn't exist). (Q1 #1 / Q4)
11. **T9** — codify the chi vs net/http vs gorilla/mux detection rule explicitly; add a concrete fixture per detected pattern (not just std net/http). (Q4)
12. **T11** — multi-stack `policy:` ships as scalar (primary-stack path); document multi-stack unification deferred to spec amendment. (Q1 #6)
13. **Every PLAN Touches path that is NEW** — annotate `(create)` or `(new)` explicitly. Apply to T3, T5-T9 fixture paths, T14 smoke output, T15 VERIFICATION.md. (Q8)

### FLAG-class (resolve in same revision pass)

14. **CONTEXT.md Coverage matrix** — update phase-numbering to match PLAN T4 INIT.md skeleton's 9 phases. (Q5 #4)
15. **PLAN T15** — drop "fixture 02 of T5-T9" reference OR add 2nd fixture per stack. (Q5 #5)
16. **PLAN T15** — add 7 evidence rows from Q7 table.
17. **PLAN Risk Register** — add 8 risks from Q6 table.
18. **PLAN T1 + T2** — lint for `readlink -f` in run-tests.sh + migrations; replace with portable form if found.
19. **PLAN T15** — explicit row for `bash migrations/run-tests.sh 0011` post-T1-T13 (regression guard for the POLICY_PATH parser change risk).
20. **Q8 script in `.review-prompt.md`** — fix regex to `[a-zA-Z/_-]+\.md` (case-insensitive). Codify in `gsd-review` template going forward.

This is the full list. After applying these, the PLAN is multi-AI approved.

---

## Disagreements between reviewers (for audit trail)

| Question | Codex | Gemini | Claude | Resolution |
|---|---|---|---|---|
| Q1 (T8 trace propagation) | BLOCK ("ObservabilityProvider fabricated") | PASS (inferred from meta.yaml) | FLAG (asked for explicit statement) | **Codex wins** — codex read `env-additions.md:55-73` showing the canonical `init() + ObservabilityErrorBoundary` shape; Gemini's inference was wrong because the template has different identifier names than PLAN T8 invented. |
| Q2 | BLOCK | PASS | FLAG | **Codex wins** — codex found `install.sh` is the actual install entry point; neither Gemini nor Claude checked there. |
| Q3 (fixture 04 outcome) | BLOCK (hard abort) | BLOCK (hard abort) | PASS (exit-4-warning acceptable) | **Majority wins** — hard abort. Claude's "user-owned path" rationale was right in principle but the migration framework's deterministic-success model precludes "applied with warning" as a stamp-successful-and-bump-version outcome. |
| Q5 (drift severity) | FLAG | PASS (no material drift) | FLAG | **Codex + Claude win** — Gemini missed the D1 label vs implementation drift and the D2 consent-set drift; both are material. |
| Q8 (PLAN Touches annotations) | BLOCK (6 paths un-annotated) | PASS | PASS | **Codex wins** — codex applied the stricter reading "exist OR explicitly say create"; Claude and Gemini both missed the un-annotated fixture paths. This is the stricter rule going forward. |

---

## Verdict timeline

- 2026-05-15 ~12:11 — PLAN.md v1 drafted (commit `6d8cce7`).
- 2026-05-15 ~12:20 — Phase 14 session-handoff committed (`2fecb34`); review work begins next session.
- 2026-05-15 12:27 — `.review-prompt.md` authored with Q1-Q8 (Q8 = new structural existence check codifying Phase 14's lesson).
- 2026-05-15 12:27 — codex + gemini launched in parallel; Claude self-review authored in parallel.
- 2026-05-15 12:29 — gemini completed (REQUEST-CHANGES; Q6 BLOCK on risks).
- 2026-05-15 12:33 — codex completed (**BLOCK** — Q1, Q2, Q3, Q4, Q8).
- 2026-05-15 — Claude verified codex's authoritative claims (`install.sh` LINKS, Vite `init()` shape, migration 0011 scalar parser); all hold.
- 2026-05-15 — 15-REVIEWS.md drafted (this file).
- (pending) — PLAN.md v2 revision pass (20 items above).
- (pending) — re-run Q8 mechanical script as PLAN.md v2 smoke check.
- (pending) — T1 begins (after revision pass).
