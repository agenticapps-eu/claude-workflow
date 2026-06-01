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
import { init, logEvent } from "./index";

// ────────────────────────────────────────────────────────────────────
// D-02a: init() repeated-init determinism contract (Phase 26 / ADR-0034).
// Wave 2 GREEN — observes singletons via the existing logEvent →
// console.log envelope chain; NO buildSentryOptions dependency per
// codex MED-4 review (DEF-3 proof is independent of DEF-1's helper).
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
    const mockCtx = { waitUntil: () => {}, passThroughOnException: () => {} } as unknown as ExecutionContext;
    const captured: string[] = [];
    const origLog = console.log;
    console.log = (line: string) => { captured.push(line); };
    try {
      // First init — singletons take env-a values.
      init({ SENTRY_DSN: "dsn-a", DEPLOY_ENV: "env-a", SERVICE_NAME: "svc-a" }, mockCtx);
      logEvent({ event: "probe-a", severity: "info" });

      // Second init — cf-worker/openrouter contract = last-call-wins (NO initialized guard).
      init({ SENTRY_DSN: "dsn-b", DEPLOY_ENV: "env-b", SERVICE_NAME: "svc-b" }, mockCtx);
      logEvent({ event: "probe-b", severity: "info" });
    } finally {
      console.log = origLog;
    }

    expect(captured.length).toBe(2);
    const env_a = JSON.parse(captured[0]);
    const env_b = JSON.parse(captured[1]);

    // env_a envelope reflects first init's values.
    expect(env_a.service).toBe("svc-a");
    expect(env_a.env).toBe("env-a");

    // env_b envelope reflects second init's values (last-call-wins mutation).
    expect(env_b.service).toBe("svc-b");
    expect(env_b.env).toBe("env-b");
  });
});
