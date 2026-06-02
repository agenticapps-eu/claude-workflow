---
phase: 27
slug: 1-21-0-stable-baseline-split-00-gate-close-wr-01-04-minimum
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-02
---

# Phase 27 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Phase 27 ships the 1.21.0 stable baseline (SPLIT-00 gate; closes WR-01..04). The
work is overwhelmingly test-harness annotations, unit-test coverage, planning
documentation, a CHANGELOG entry, and one production-adjacent rewire (WR-04 routing
the openrouter scaffold entry through the test-locked `buildSentryOptions` helper).
No new network endpoint, auth path, or schema crosses any trust boundary.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| worker env → Sentry SDK init | `buildSentryOptions(env)` shapes the options passed to `withSentry` in the openrouter scaffold entry. The redaction path (`REDACTED_KEYS`) and `sendDefaultPii: false` are the security-relevant invariants on this surface. WR-04 routes the entry THROUGH the already-tested helper rather than a divergent inline object. | Deploy env vars → Sentry options (no PII; auth headers redacted) |
| (no other new boundaries) | Remaining changes are test files, a test-harness shell script, planning docs, and a CHANGELOG edit. No production request path, no untrusted input. | — |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-27-01-01 | Tampering | run-template-tests.sh counter | accept | Test-harness reporting only; firewall-line acceptance check (grep returns exactly 128/130/558/559) guards an over-broad edit. No consumer-facing behavior. | closed |
| T-27-01-02 | n/a | supabase-edge test isolation | accept | Change strengthens test isolation (prevents state bleed). No attack surface; HIGH-3 honored. | closed |
| T-27-02-01 | Information Disclosure | buildSentryOptions(sendDefaultPii) | mitigate | Tests A/B assert `sendDefaultPii === false` in all 3 stacks, pinning the no-PII-to-Sentry contract. Verified: openrouter `src/observability/index.test.ts:45,56`; cf-worker `lib-observability.test.ts:597,608`; cf-pages `lib-observability.test.ts:597,608`. | closed |
| T-27-02-02 | n/a | test correctness | accept | Tests lock the existing helper contract; they do not change the helper. No attack surface. | closed |
| T-27-03-01 | n/a | planning docs | accept | Documentation-only; accuracy verified by grep-checkable acceptance criteria. No attack surface. | closed |
| T-27-04-01 | Tampering | run-tests.sh annotations | accept | Comment-only; acceptance check (`git diff` shows only `+# SHARED`/`+# WORKFLOW`, full suite GREEN) guards an accidental executable-line change. | closed |
| T-27-04-02 | n/a | SPLIT docs | accept | Documentation accuracy. No attack surface. | closed |
| T-27-05-01 | Information Disclosure | Sentry options (sendDefaultPii / redaction) | mitigate | Openrouter entry routed through `buildSentryOptions(env)`, removing the divergent inline object that risked silent PII forwarding. Verified: `src/index.ts:32` (import) + `src/index.ts:47` (`withSentry((env: Env) => buildSentryOptions(env), …)`); no inline `tracesSampleRate:0.1` in entry; `sendDefaultPii:false` lives in env-pure helper `observability/index.ts:173`. | closed |
| T-27-05-02 | Tampering | byte-symmetry pair | mitigate | WR-04 commit `88b609e` touched only `.gitignore` + `src/index.ts`; neither frozen pair file (`openrouter-monitor/src/observability/index.ts`, `ts-cloudflare-worker/lib-observability.ts`) is in the changeset — pair uncoupled. | closed |
| T-27-06-01 | Tampering | version/drift invariant | mitigate | `skill/SKILL.md:3` `version: 1.20.0` (unchanged); migration `0021` `to_version: 1.20.0`; drift test `test-skill-md-version-matches-latest-migration-to-version` → PASS. Prevents an accidental SKILL bump breaking the migration-locked-version invariant (A2). | closed |
| T-27-06-02 | n/a | release tag | accept | `v1.21.0` tag is a deliberate manual release step (deferred to ship time, on `main`). No attack surface. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-27-01 | T-27-01-01 | Test-harness counter reporting; no consumer-facing behavior, no attack surface. | DonaldVl | 2026-06-02 |
| AR-27-02 | T-27-01-02 | Test-isolation strengthening; no new seam or attack surface. | DonaldVl | 2026-06-02 |
| AR-27-03 | T-27-02-02 | Tests lock existing contract; do not alter the helper. No attack surface. | DonaldVl | 2026-06-02 |
| AR-27-04 | T-27-03-01 | Planning-documentation-only edit. No code, no runtime. | DonaldVl | 2026-06-02 |
| AR-27-05 | T-27-04-01 | Comment-only test-script annotations; full suite GREEN, diff is comment-only. | DonaldVl | 2026-06-02 |
| AR-27-06 | T-27-04-02 | SPLIT documentation accuracy. No attack surface. | DonaldVl | 2026-06-02 |
| AR-27-07 | T-27-06-02 | Manual release tag (deferred to ship time on `main`); deliberate step, no attack surface. | DonaldVl | 2026-06-02 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-02 | 11 | 11 | 0 | gsd-security-auditor (sonnet) |

Audit method: State B (run from artifacts). 4 `mitigate`-disposition threats verified
against the implementation with file:line evidence; 7 `accept`-disposition threats
documented as accepted risks above. The migration suite shows 4 pre-existing,
unrelated verify-exit failures (`02-fresh-apply-fxsa-shape`, `06-no-claudemd`,
`10-fresh-apply-worker-env`, `11-prettier-style-clean-applies`) — none touch the
version-drift invariant (PASS) or the byte-symmetry contract; out of scope.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-02
