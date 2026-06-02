# Phase 27: 1.21.0 stable baseline (SPLIT-00 gate) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 27-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 27 - 1.21.0 stable baseline (SPLIT-00 gate)
**Areas discussed:** WR-04 direction, split-prep depth, milestone sequencing, PROJECT.md depth, bundling
**Mode:** `--auto` transcription of an approved brainstorm (no live Q&A — decisions pre-locked 2026-06-02)

---

## WR-04 — openrouter entry point

| Option | Description | Selected |
|--------|-------------|----------|
| Use the helper | Rewrite `src/index.ts` to `withSentry(env => buildSentryOptions(env), …)`; wires TRACE_SAMPLE_RATE in the worked example | ✓ |
| Tighten docs only | Leave inline `tracesSampleRate: 0.1`; just clarify docs | |

**User's choice:** Use the helper.
**Notes:** Matches openrouter's own `env-additions.md`; makes the worked example consistent with cf-worker/cf-pages and with DEF-1's intent. Entry file is not the byte-symmetry pair, so symmetry unaffected — re-verify with `diff -q` regardless.

## Split-prep decoupling depth

| Option | Description | Selected |
|--------|-------------|----------|
| Audit + annotate only | Mark gsd-tools exports `// SHARED`/`// WORKFLOW` + boundary ADR; zero code movement | ✓ |
| Fold extraction into 1.21.0 | Actually split bin/gsd-tools.cjs now | |
| Defer entirely to SPLIT-01 | Do nothing in 1.21.0 | |

**User's choice:** Audit + annotate only.
**Notes:** 1.21.0's job is to be a stable 7-day cooling-off baseline; any behavior change to gsd-tools resets the clock. Annotation + ADR makes SPLIT-01 Phase C mechanical without risk. SPLIT-01 explicitly anticipates this as "what 1.21.0 should have done."

## Milestone sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Archive after 1.21.0 ships | Phase 27 closes current milestone; archive + new "repo-split" milestone post-merge | ✓ |
| Archive first, then Phase 27 | Open new milestone before doing the phase work | |

**User's choice:** Archive after ship.
**Notes:** Phase 27 is the final phase of the current milestone; SPLIT-01/02 become phases of a fresh "repo-split" milestone opened after merge.

## PROJECT.md depth

| Option | Description | Selected |
|--------|-------------|----------|
| Minimum-viable, forward-looking | Product identity + impending split; link phase history, don't reconstruct it | ✓ |
| Full Phases 01-26 retro | Archaeological phase-by-phase reconstruction | |

**User's choice:** Minimum-viable.
**Notes:** Phase histories already live in `.planning/phases/` + git; deep retro of a soon-to-split monorepo is wasted work.

## Bundling fork

| Option | Description | Selected |
|--------|-------------|----------|
| Bundle WR-01..04 + workflow-meta in 1.21.0 | Single release covering obs fixes + PROJECT/STATE/ROADMAP | ✓ |
| Pure split-prep; push WR fixes to obs repo post-split | Smaller 1.21.0; WR lands in future home | |

**User's choice:** Bundle now.
**Notes:** WR items are already scoped/tested-shaped and SPLIT-00 lists them as 1.21.0 scope. Flagged as the one genuine fork; user approved bundling.

## Claude's Discretion

- Exact WR-01 bash idiom; PROJECT.md prose/ordering; ADR number; WR-03 openrouter test file vs block placement.

## Deferred Ideas

- gsd-tools extraction → SPLIT-01 Phase C; milestone archive → post-merge; `{{ENV_VAR_RELEASE}}` design; FIX-0017-ENGINE; session-noise triage; full 01-24 retro (superseded by minimum-viable PROJECT.md).
