/**
 * openrouter-monitor observability wrapper — D-02a Wave 0 RED baseline.
 *
 * This test file is the byte-symmetric counterpart of
 * add-observability/templates/ts-cloudflare-worker/lib-observability.test.ts
 * for the openrouter-monitor mirror (ADR-0033 D-21 byte-symmetry contract).
 *
 * Wave 0 (Plan 26-01): only the D-02a `describe("init() repeated-init
 * determinism (D-02a)")` block exists. The rest of the cf-worker test
 * suite (traceparent roundtrip, fail-safe no-throw, span lifecycle, …)
 * is intentionally NOT mirrored here — full test parity is a separate
 * future task. The Wave 0 commitment is that the D-02a block text is
 * byte-symmetric with cf-worker's D-02a block (codex MED-1 evidence
 * target + T4 mitigation).
 *
 * Test runner: vitest. Driven by openrouter-monitor's tracked
 * package-lock.json (the env-stable canonical RED-capture target per
 * codex MED-1 — every other stack's harness is env-blocked behind a
 * fresh `npm install`).
 */

import { describe, it, expect } from "vitest";

// ────────────────────────────────────────────────────────────────────
// D-02a: init() repeated-init determinism contract (Phase 26 / ADR-0034).
// Wave 0 RED stub — flips GREEN once Plan 02 / Wave 2 lands the real
// assertion (which observes singletons via the existing logEvent →
// console.log envelope chain; NO buildSentryOptions dependency per
// codex MED-4 review — DEF-3 proof is independent of DEF-1's helper).
//
// Contract (per ADR-0034, post-codex-HIGH-1 correction):
//   cf-worker/cf-pages/openrouter: last-call-wins (no initialized guard).
//   Calling init() twice mutates singletons on each call. After init(env_b)
//   following init(env_a), the singletons reflect env_b. This is
//   deterministic (output = f(inputs)) but NOT idempotent (state changes).
// See docs/decisions/0034-observability-init-singleton-invariant.md.
// ────────────────────────────────────────────────────────────────────
describe("init() repeated-init determinism (D-02a)", () => {
  it("init() called twice within isolate yields deterministic singleton state", () => {
    // RED stub: real assertion lands in Plan 02 / Wave 2. The Plan 02 GREEN
    // implementation uses a console.log spy + logEvent to observe
    // `serviceName` and `deployEnv` singletons via the JSON envelope chain.
    // See docs/decisions/0034-observability-init-singleton-invariant.md.
    expect.fail("D-02a stub — Wave 0 RED baseline; flips GREEN when Plan 02 lands the logEvent-envelope assertion");
  });
});
