---
phase: 21
reviewers: [gemini, codex]
reviewed_at: 2026-05-26
plans_reviewed: [PLAN.md]
self_skipped: claude (running inside Claude Code CLI)
---

# Cross-AI Plan Review — Phase 21 (Axiom logs destination)

Two independent external reviewers (gemini, codex). `claude` skipped for
independence (this session is Claude Code). Codex's first run deadlocked on stdin
and was re-invoked with stdin closed — see session notes.

## Gemini Review

### Summary
Exceptionally strong, comprehensive, convention-grounded plan. Phased TDD + explicit
verification gates give high confidence of meeting G1–G7 while honoring the §10.1
byte-identical interface guarantee.

### Strengths
- Rigorous TDD (RED→GREEN) minimizes regressions.
- Proactive debt reduction: cf-pages harness backfill (D3/G4).
- Robust migration strategy: hash-based hand-modified detection + idempotency.
- Clear P0–P6 phasing with strong per-phase + cross-phase verification gates.
- Security-aware: browser token-exfil risk identified, proxy mitigation specified.

### Concerns
- **(MEDIUM) Migration refusal UX.** "Refuse + emit manual-splice guidance + exit
  non-zero" is safe but the guidance is undefined; a poor experience could deter
  adoption of this and future migrations.
- **(LOW) Silent ingest failures.** Fire-and-forget drops logs silently on network
  / API / bad-token errors — complicates debugging.
- **(LOW) Scaffolder logic testability.** P2/P5 test generated code + migration, but
  not the new `init` generator logic (P4.2). A generator bug could break
  `add-observability init` for new projects.

### Suggestions
- Migration refusal: auto-generate a `.patch` of the user's changes vs baseline →
  stash → migrate clean → re-apply patch.
- Degraded-mode feedback: wrap egress in try/catch, emit one rate-limited
  `console.warn` on failure (keeps fire-and-forget contract).
- Add an `init` fixture: run `init --destinations`, assert only correct files
  scaffolded with correct baked config.

### Risk Assessment: **LOW**
Exemplary, meticulous, risks proactively addressed; concerns are DX, not
fundamental flaws.

---

## Codex Review

### Summary
Well-scoped, strongly grounded, capable of delivering G1, G3, G4, G6, G7. Strongest:
explicit non-goals, per-phase gates, migration fixture matrix. Main weaknesses are in
**enforcement, not architecture**: G2's byte-identical guarantee is not actually
proven by the proposed checks; G5 hand-modified detection is too narrow (only hashes
entry files); the role-map override path needs fail-closed validation to make
"captureError never goes to Axiom" truly robust.

### Strengths
- Tight alignment to spec + locked decisions (D1–D6) reduces ambiguity.
- Strong scope control via non-goals (no batching / Axiom errors / new destinations).
- Clean registry/adapter abstraction; stable public surface in principle.
- cf-pages harness closes a real pre-existing coverage gap.
- Credible migration fixture matrix (fresh / already-applied / refuse / partial /
  no-CLAUDE.md).
- Browser exfil risk identified; proxy-only Vite default correct.
- Strong verification culture (TDD, per-phase gates, green-suite expectations).

### Concerns
- **[HIGH] G2 not actually enforceable.** "Existing tests unchanged" + grep don't
  prove a byte-identical public interface — they miss export-shape drift, type/decl
  drift, symbol ordering, subtle signature changes. G2 is refuse-to-merge, so this
  is the biggest gap.
- **[HIGH] `OBS_DESTINATIONS` override under-specified for invalid input.** No
  fail-closed behavior for malformed strings, unknown destinations, duplicate keys,
  unsupported mappings like `errors=axiom`, case/whitespace, partial configs.
  Without strict validation, "captureError never reaches Axiom" depends on
  implementation luck.
- **[HIGH] Migration consent too narrow.** P5.1 hashes only `index.{ts,go}`, but the
  migration also rewrites `CLAUDE.md`, env rows, possibly stack files — hand-modified
  adjacent files can be overwritten undetected.
- **[MEDIUM] Partial migration + non-zero exit is operationally risky.** A command
  that "failed" still mutated the repo. Needs a transactional model or explicit
  `--allow-partial` opt-in.
- **[MEDIUM] Fire-and-forget failure paths under-tested.** No coverage for fetch
  rejection, non-2xx ingest, `waitUntil` absent/throwing, `sendBeacon` false, Go
  flush race/error — the cases most likely to break "never throw into app code."
- **[MEDIUM] `startSpan` dependency context changes.** Moving Sentry init behind the
  registry can drift span behavior under `errors=none` / `logs=axiom` / `SENTRY_DSN`
  unset; no dedicated regression coverage.
- **[MEDIUM] Phase ordering slightly backward.** Generator contract (P4) lands after
  adapter rollout (P2) → rework risk if the generator contract changes mid-stream.
- **[LOW] Browser config story mixed.** Generated stubs/tests should make the Vite
  no-token exception explicit to prevent accidental leakage.
- **[LOW] Version metadata confusion.** `add-observability` `implements_spec: 0.3.2`
  while materializing 0.4.0 destination metadata looks inconsistent unless explained.

### Suggestions
- Add explicit public-API verification per stack: declaration snapshot / exported-
  symbol manifest diff / materialized-wrapper byte diff vs 1.15.0.
- Make `OBS_DESTINATIONS` parsing strict + fail-closed: unknown→warn+ignore;
  unsupported mapping (`errors=axiom`)→reject role, fall to none/baked default;
  partial→merge only validated keys; test malformed + unsupported combos.
- Expand hand-modified detection to every file the migration rewrites, or gate writes
  behind anchored managed regions + per-file hash/marker checks.
- Decide partial-migration semantics explicitly: preflight "all roots clean" pass
  before any writes; require `--allow-partial` otherwise.
- Add egress failure-path tests on every runtime; assertion = "observability path
  never throws into app code."
- Add `startSpan` regression tests under `SENTRY_DSN` unset and `errors=none,logs=axiom`
  (esp. cf-worker, go-fly-http).
- Pull P4 metadata/init earlier, or freeze the generator substitution format before
  duplicating adapters across 5 stacks.
- Make the Vite exception concrete in generated output: no `VITE_AXIOM_TOKEN` /
  `VITE_AXIOM_DATASET`; dedicated test that browser templates emit only proxy config.

### Risk Assessment: **MEDIUM**
Design sound, plan disciplined, very likely implementable without architectural
churn. Not LOW because the two hardest guarantees — public-interface byte identity
and safe consent-driven migration — are not yet enforced as strongly as the spec
requires. Tightening API verification, override validation, and migration mutation
boundaries moves it toward LOW.

---

## Consensus Summary

**Overall: MEDIUM risk.** Architecture and scope are endorsed by both reviewers; the
work needed is in **enforcement strength**, not redesign. Gemini rated LOW, codex
MEDIUM — the divergence is justified: codex found concrete enforcement holes (G2
verification, override validation, migration mutation boundary) that gemini's
higher-level pass missed. We adopt MEDIUM and incorporate the fixes before execution.

### Agreed Strengths (both reviewers)
- Tight alignment to spec + locked decisions (D1–D6).
- Strong scope control via explicit non-goals.
- Clean registry/adapter abstraction; stable public surface in principle.
- cf-pages harness closes a real pre-existing coverage gap (D3/G4).
- Browser token-exfil risk correctly identified; proxy-only Vite default correct.
- Strong TDD + per-phase + cross-phase verification culture.

### Agreed Concerns (raised by both — highest priority to fix)
1. **Migration consent / refusal path** — gemini (refusal UX, MEDIUM) + codex
   (hash covers only `index.*`, HIGH). Fix: expand hand-modified detection to every
   rewritten file (incl. CLAUDE.md, env rows) via anchored managed regions +
   per-file hash; auto-generate a `.patch` for the refuse path so users can
   stash→migrate→re-apply.
2. **Fire-and-forget failure handling** — gemini (silent failures, LOW) + codex
   (failure paths untested, MEDIUM). Fix: try/catch around all egress with a single
   rate-limited `console.warn`; add failure-path tests (fetch reject, non-2xx,
   `waitUntil` absent/throw, `sendBeacon` false, Go flush timeout) asserting the obs
   path never throws into app code.
3. **`init`/generator contract untested + ordering** — gemini (init logic untested,
   LOW) + codex (freeze generator format before P2, MEDIUM). Fix: freeze the P4
   generator substitution format before duplicating adapters across 5 stacks; add an
   `init --destinations` fixture asserting only role-referenced adapters are
   scaffolded with correct baked config.

### Codex-only — HIGH severity, adopt anyway (distinct blind spots)
4. **G2 byte-identity is asserted but not actually verified.** Add a real public-API
   check: exported-symbol manifest / declaration snapshot / materialized-wrapper byte
   diff vs 1.15.0 for the unchanged surface. Grep + "tests unchanged" is insufficient
   for a refuse-to-merge guarantee.
5. **`OBS_DESTINATIONS` must be fail-closed.** This is a SAFETY issue: an
   `errors=axiom` override would violate the never-Axiom-errors hard constraint.
   Reject unsupported role→dest mappings, warn+ignore unknowns, merge only validated
   keys; test malformed + unsupported combos.

### Codex-only — MEDIUM/LOW, fold in
6. `startSpan` regression coverage under `SENTRY_DSN` unset / `errors=none`.
7. Partial-migration transactional semantics (`--allow-partial` or all-clean
   preflight).
8. Make the Vite no-token exception concrete in generated output + a test.
9. Explain the `add-observability implements_spec: 0.3.2` vs 0.4.0-metadata
   distinction somewhere user-facing.

### Divergent Views
- **Risk rating:** gemini LOW vs codex MEDIUM. Resolved to MEDIUM (codex's
  enforcement findings are concrete and well-justified).
- **Migration refusal:** gemini frames it as a DX problem (improve guidance); codex
  frames it as a correctness/consent gap (detection scope too narrow). Both true —
  the fix addresses both: broaden detection AND improve the refuse-path UX.
