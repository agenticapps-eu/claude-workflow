# ADR-0026: add-observability template correctness patch (issue #49)

**Status**: Accepted  **Date**: 2026-05-27  **Issue**: #49

## Context

CodeRabbit's review of `agenticapps-eu/callbot#40` (the migration-0017 landing
PR) surfaced 8 comments mapping to 5 distinct correctness gaps. All 5 live in
the `add-observability` v1.16.0 wrapper **templates**, not in callbot-specific
code, so every downstream that adopts the template inherits them:

1. **Major** — `redactObject` is top-level-only; nested secrets
   (`attrs.request.headers.authorization`, arrays of objects) leak.
2. **Major** — `captureError` passes caller `severity` straight to `emit`; a
   caller-supplied `severity: "debug"` is sample-rate-gated and the exception is
   silently dropped.
3. **Major** — the browser Axiom adapter's `isConfigured()` accepts ANY
   non-empty `AXIOM_PROXY_URL`, contradicting its own "same-origin only" rule —
   a misconfigured `VITE_AXIOM_PROXY_URL` could POST envelopes cross-origin.
4. **Minor** — `parseTraceparent` gates shape but not semantics; all-zero
   trace-id/parent-id pass and downstreams (Sentry/Tempo/Honeycomb) reject them.
5. **Minor** — the browser `_resetForTest` clears only 3 of N module vars,
   leaving `spanStack`/`serviceName`/`deployEnv` and an instrumented
   `window.fetch` to leak across test suites.

## Decision

Ship as `add-observability` **v0.5.1** — a patch release. The wrapper's public
interface (exported function signatures per spec §10.1) stays byte-identical, so
**no migration is required**: downstreams re-materialise the wrapper and the new
template wins.

**Scope: all four TS stacks for the shared gaps.** Gaps #1, #2, #4 live in
*identical* code in `ts-cloudflare-worker`, `ts-cloudflare-pages`,
`ts-supabase-edge`, and `ts-react-vite`. Gaps #3 and #5 are browser-only and
apply to `ts-react-vite` alone (the browser Axiom adapter + browser module
state). The `go-fly-http` stack has a separate implementation and is out of
scope (no equivalent gaps reported).

Implementation choices:

- **#1** — `redactValue(key, value)` checks the key first (existing behaviour),
  then recurses via `redactDeep`: arrays mapped element-wise, plain objects
  re-redacted, `null` and non-plain objects (e.g. `Date`) preserved as-is. New
  objects/arrays are constructed — input is never mutated.
- **#2** — coerce severity before `emit`:
  `severity === "fatal" ? "fatal" : "error"`. `captureError` can never be
  sampled out.
- **#3** — `isConfigured`/`init` resolve the proxy URL through a same-origin
  guard: empty → reject; single-leading-slash relative path (but **not** a
  protocol-relative `//host`) → accept; otherwise parse against `location.href`
  and accept only when `origin === location.origin`; parse failure → reject
  (fail-closed).
- **#4** — keep the regex as the fast structural gate, then an inline
  `validateTraceparent` rejecting version ≠ `00`, all-zero trace-id, and
  all-zero parent-id. No new `zod` dependency (per the issue).
- **#5** — `_resetForTest` additionally clears `spanStack`, restores
  `window.fetch` from the stored `originalFetch`, and resets `serviceName` /
  `deployEnv` to their documented defaults (`SERVICE_DEFAULT` / `"dev"`) rather
  than `null`, since both are typed `string`.

## Alternatives Rejected

- **Fix only worker + react-vite (the literal issue scope / callbot's stacks).**
  Rejected: pages and supabase-edge carry byte-identical buggy code for #1/#2/#4.
  Leaving them shipped would diverge the stacks and let a future pages/supabase
  downstream inherit the gap — exactly the divergence the "fix upstream" rationale
  in #49 exists to prevent.
- **Fix in callbot directly.** Rejected per #49: customising the wrapper away
  from baseline makes the migration engine refuse the next migration until the
  customisation is reverted (the dance #47 + PR #46 went through).
- **Cut a new migration.** Rejected: the public interface is unchanged, so a
  migration would be a no-op transform. Re-materialisation suffices.
- **Add `zod` for traceparent validation.** Rejected per #49: a runtime dep for
  one validation is disproportionate; an inline helper covers the invariants.

## Consequences

- Downstreams already on v1.16.0 re-run the materialisation flow to pick up the
  patch; no `/update-agenticapps-workflow` migration step.
- Redaction is now recursive — marginally more work per emit, bounded by attr
  depth; acceptable for an observability hot path that already JSON-stringifies.
- `captureError` is guaranteed visible regardless of caller severity, matching
  its documented contract.
- The browser Axiom adapter is fail-closed against cross-origin egress.
- Template test suites gain regression coverage for all five gaps; the migration
  init fixtures are structural stubs and are unaffected by these internal edits.
