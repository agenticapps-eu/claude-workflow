# Phase 26: worker-template hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 26-worker-template-hardening
**Areas discussed:** DEF-1 strategy, DEF-3 singletons, F-2 lockfile policy, Migration shape, Claude's Discretion approval

---

## Gray-area selection

User was presented with 4 candidate areas (DEF-1, DEF-3, F-2, Migration shape) as multiSelect. Selected all 4.

DEF-2, CR-D, CR-E, .gitignore extension, markdown lint, versioning were handled as Claude's Discretion recommendations (D-05..D-10), bulk-approved at the end.

---

## DEF-1: TRACE_SAMPLE_RATE wiring strategy

### Question 1: Wiring mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Helper export from wrapper | Add `observabilitySentryOptions(env)` export to lib-observability.ts; operator wires via `withSentry(env => observabilitySentryOptions(env), withObservability(handler))`. Wrapper owns the contract; TRACE_SAMPLE_RATE stops being dead. Spec-first. | ✓ |
| Drop dead code + document | Remove TRACE_SAMPLE_RATE from cf-worker/cf-pages templates; document in env-additions.md. Honest about today's reality; minimum surface change. | |
| Guidance only (keep constant) | Keep TRACE_SAMPLE_RATE; expand env-additions.md with explicit wiring snippet. Lightest touch but DEF-1 lives on as latent drift risk. | |
| Wire at middleware.ts init() call | Restructure cf-worker's init() to surface options. Brings rate INTO the wrapper but adds plumbing and changes init() contract. | |

**User's choice:** Helper export from wrapper
**Notes:** Spec-first framing won. The reframing context (cf-worker can't call Sentry.init because @sentry/cloudflare v8 removed it; canonical setup is at the operator's entry-file `withSentry`) made the design call explicit.

### Question 2: Scope

| Option | Description | Selected |
|--------|-------------|----------|
| cf-worker + cf-pages + openrouter only | Match codex H-3/H-6 principle: narrow to where bug exists. supabase-edge/react-vite already wire correctly. Don't touch what works. | ✓ |
| Symmetric refactor across all 4 stacks + openrouter | Restructure supabase-edge + react-vite to use the same helper for consistency. More invasive; uniform DX. | |

**User's choice:** Narrow scope (cf-worker + cf-pages + openrouter only)
**Notes:** Mirrors Phase 25's codex-revised narrowing pattern (D-05, D-07). "Don't touch what works."

---

## DEF-3: module-level singleton handling

### Question 1: Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Leave + ADR documenting assumption | Add ADR for the Cloudflare-isolate `no-concurrent-invocations-per-isolate` invariant. Add init() idempotency assertion to lib-observability.test.ts per stack. Cheapest defensible fix. | ✓ |
| AsyncLocalStorage refactor | Move singletons into initStorage ALS; init() wraps handler. Aligns with existing spanStorage pattern. Per-request isolation. More invasive: changes accessor sites + middleware composition. | |
| Per-request closure (explicit parameter) | Wrapper functions take InitContext as explicit arg. Most explicit + most testable. Largest API surface change. | |
| Defer entirely to Phase 27+ | Strip from Phase 26 scope. DEF-3 is latent; no observed bug. | |

**User's choice:** Leave + ADR documenting assumption
**Notes:** Phase 26 is cleanup, not architecture overhaul. Cloudflare guarantee holds today; ADR-0034 + idempotency test make the assumption explicit and testable. AsyncLocalStorage refactor preserved as deferred candidate for Phase 27+.

---

## F-2 + vitest-pin: lockfile policy

### Question 1: Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Pin harness deps to known-good versions | Edit run-template-tests.sh heredocs: pin vitest to `~3.2.4` + @sentry/cloudflare to known-good 8.x.y. Tiny diff. Defends against exact drift class hit Phase 25. | ✓ |
| Stable lockfile harness + npm ci | Create harness-fixtures dir with tracked package.json + package-lock.json per stack. `npm ci` for full determinism. ~3 new lockfiles + refactor. | |
| Pin + commit stack lockfiles too | Option 1 + ship tracked package-lock.json in each generated template. Operators inherit deterministic dep tree. Largest surface; conflicts with "operator owns lockfile" model. | |
| Document only — no harness fix | Add troubleshooting note; pin nothing. Honest but doesn't solve breakage. | |

**User's choice:** Pin harness deps to known-good versions
**Notes:** Tight surface (~6 lines across 3 stack heredocs). Re-bump deliberately. Doesn't conflict with operator-owns-lockfile model.

---

## Migration shape: 0022 or template-only?

### Question 1: Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Template-only — no Migration 0022 | Phase 26 = template edits + engine fixes + harness pin + ADRs + tests. Rationale: DEF-1 needs operator wiring; DEF-2 policy.md is operator-owned; DEF-3 is doc+test. No migration forces these. add-observability 0.9.0 → 0.10.0 minor; claude-workflow patch or no bump. | ✓ |
| Ship Migration 0022 (re-rev shape) | Mirror 0021's dirty-detection re-rev. 0022 ships updated lib-observability.ts + monitors. Refuses on hand-modified files. Existing projects adopt via npx migrate. add-observability 0.9.0 → 0.10.0; claude-workflow 1.20.0 → 1.21.0. | |
| Template-only + migration spec (no engine) | Hybrid: ship 0022 spec doc describing the changes operators should make, but NO engine script. Documents for visibility / audit trail. add-observability 0.9.0 → 0.10.0; claude-workflow 1.20.0 → 1.21.0. | |

**User's choice:** Template-only — no Migration 0022
**Notes:** Locked. Versioning falls out: add-observability 0.10.0 minor, claude-workflow 1.20.1 patch (per D-10 / D-10a in CONTEXT.md). D-04a (optional spec-only 0022.md) preserved as Claude's Discretion for the planner.

---

## Claude's Discretion (bulk approval)

User was presented with the locked decisions (D-01..D-04) plus 6 recommended Claude's Discretion items (D-05..D-10):

| ID | Item | Recommendation |
|---|---|---|
| D-05 | DEF-2 REDACTED_KEYS expansion | `[password, token, api_key, authorization, bearer, cookie, x-api-key, secret]` |
| D-06 | CR-D content-marker firewall | grep -qiE marker filter on index.ts content |
| D-07 | CR-E TS1038 + verify.sh exit-0 | Canonical `interface Console + declare var console` pattern; remove exit-0 fallback |
| D-08 | .gitignore extension | Copy openrouter shape to cf-worker + cf-pages; adapt for supabase-edge runtime |
| D-09 | Markdown lint findings | Skip (historical artifacts) |
| D-10 | Versioning | add-observability 0.9.0 → 0.10.0 minor; claude-workflow 1.20.0 → 1.20.1 patch |

### Question: Lock all 6 or discuss specific items?

| Option | Description | Selected |
|--------|-------------|----------|
| Lock all 6 — write CONTEXT.md | All 10 decisions stand. Proceed to write CONTEXT.md + DISCUSSION-LOG.md, commit, hand off to /gsd-plan-phase 26. | ✓ |
| Discuss D-05 (REDACTED_KEYS expansion) | Open up narrower vs broader redacted-keys set. | |
| Discuss D-10 (versioning) | Reconsider claude-workflow patch-vs-minor call. | |
| Discuss D-09 (markdown lint cleanup) | Reconsider skipping the 10 markdown-lint residuals. | |

**User's choice:** Lock all 6
**Notes:** No follow-up discussion. All recommendations stand as written.

---

## Deferred Ideas (captured during discussion)

- **AsyncLocalStorage refactor of singletons** (Phase 27+ candidate) — Option B from DEF-3 discussion preserved on file.
- **Per-request closure (explicit parameter) refactor** (Phase 27+ candidate) — Option C from DEF-3 discussion.
- **Symmetric DEF-1 refactor for supabase-edge + react-vite** — only if future phase needs uniform DX across all stacks.
- **Migration 0022 with engine script** — only if a future regression demands forcing fixes onto already-migrated projects (security-critical class).
- **Markdown lint cleanup batch** (Phase 27+ candidate) — fold into a `markdownlint --fix` pass if project ever standardises on markdown linting as a CI gate.
- **Full retroactive ROADMAP/STATE/PROJECT bootstrap** (carry-forward) — should land before Phase 27.
- **FIX-0017-ENGINE.md working-dir prompt** — separate scope.
- **gstack 1.48 → 1.52 upgrade** (operational, not code-phase).
- **Untracked session noise triage** (cleanup pass).

---

*Audit complete. All decisions captured in 26-CONTEXT.md.*
