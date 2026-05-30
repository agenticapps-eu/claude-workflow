/**
 * check-credit.test.ts — openrouter-monitor handler contract suite.
 *
 * Phase 24 / ADR-0030. 13 fixtures per CONTEXT D-15 covering:
 *   (1)  under WARNING                       → pulse only
 *   (2)  at WARNING exactly (0.85)           → pulse + credit_low warn
 *   (3)  between WARNING and CRITICAL (0.90) → pulse + credit_low warn
 *   (4)  at CRITICAL exactly (0.95)          → pulse + BudgetCriticalError
 *   (5)  401                                 → HealthcheckFailedError(401, http)
 *   (6)  500                                 → HealthcheckFailedError(500, http)
 *   (7)  429                                 → HealthcheckFailedError(429, http)
 *   (8)  network throw                       → HealthcheckFailedError(0, network)
 *   (9)  malformed JSON                      → HealthcheckFailedError(-1, parse)
 *   (10) limit: null (unlimited)             → pulse only, ratio = 0
 *   (11) inverted thresholds                 → misconfig warn + fallback
 *   (12) invalid env vars                    → fallback to default 0.85
 *   (13) 200 OK + missing body.data           → HealthcheckFailedError(-1, parse)
 *
 * Mocks `./observability` (the bundled wrapper). The composition chain
 * (withSentry/withObservabilityScheduled/withCronMonitor) is wired in
 * src/index.ts and contract-tested in Phase 22/23's existing suites — we
 * don't re-validate it here.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  checkCredit,
  OpenRouterBudgetCriticalError,
  OpenRouterHealthcheckFailedError,
} from "./check-credit";

// Mock the bundled wrapper. checkCredit imports logEvent + captureError
// from "./observability" — vitest swaps the module here so we can assert
// exact call shapes.
vi.mock("./observability", () => ({
  logEvent: vi.fn(),
  captureError: vi.fn(),
}));
import { logEvent, captureError } from "./observability";

// Mirrors check-credit.ts's Env interface (kept local so the test file is
// self-contained — Env isn't exported from check-credit). Must extend
// Record<string, unknown> to match check-credit's parameter type, which
// extends it to satisfy the ScheduledFn<E> constraint in cron-monitor.ts.
interface Env extends Record<string, unknown> {
  OPENROUTER_API_KEY: string;
  OPENROUTER_WARNING_RATIO?: string;
  OPENROUTER_CRITICAL_RATIO?: string;
}

function makeEnv(overrides: Partial<Env> = {}): Env {
  return { OPENROUTER_API_KEY: "sk-or-v1-test", ...overrides };
}

// ScheduledController + ExecutionContext aren't used by checkCredit (it
// only reads env + does fetch); cast as never to satisfy the signature.
const noController = {} as never;
const noCtx = {} as never;

function mockFetchOk(body: unknown): void {
  globalThis.fetch = vi.fn().mockResolvedValue(
    new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } }),
  ) as never;
}

function mockFetchStatus(status: number): void {
  globalThis.fetch = vi.fn().mockResolvedValue(new Response("", { status })) as never;
}

function mockFetchThrow(err: Error): void {
  globalThis.fetch = vi.fn().mockRejectedValue(err) as never;
}

function mockFetchBadJson(): void {
  globalThis.fetch = vi.fn().mockResolvedValue(new Response("not json at all")) as never;
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("checkCredit", () => {
  it("(1) under WARNING — pulse only", async () => {
    mockFetchOk({ data: { usage: 10, limit: 100 } });
    await checkCredit(noController, makeEnv(), noCtx);
    expect(logEvent).toHaveBeenCalledTimes(1);
    expect(logEvent).toHaveBeenCalledWith(
      expect.objectContaining({ event: "openrouter.credit_pulse", severity: "info" }),
    );
    expect(captureError).not.toHaveBeenCalled();
  });

  it("(2) at WARNING exactly (0.85) — pulse + credit_low warn", async () => {
    mockFetchOk({ data: { usage: 85, limit: 100 } });
    await checkCredit(noController, makeEnv(), noCtx);
    expect(logEvent).toHaveBeenCalledTimes(2);
    expect(logEvent).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ event: "openrouter.credit_pulse" }),
    );
    expect(logEvent).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ event: "openrouter.credit_low", severity: "warn" }),
    );
    expect(captureError).not.toHaveBeenCalled();
  });

  it("(3) between WARNING and CRITICAL (0.90) — pulse + credit_low warn", async () => {
    mockFetchOk({ data: { usage: 90, limit: 100 } });
    await checkCredit(noController, makeEnv(), noCtx);
    expect(logEvent).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ event: "openrouter.credit_low", severity: "warn" }),
    );
    expect(captureError).not.toHaveBeenCalled();
  });

  it("(4) at CRITICAL exactly (0.95) — pulse + BudgetCriticalError", async () => {
    mockFetchOk({ data: { usage: 95, limit: 100 } });
    await checkCredit(noController, makeEnv(), noCtx);
    expect(logEvent).toHaveBeenCalledTimes(1); // pulse only — critical is captureError not logEvent
    expect(logEvent).toHaveBeenCalledWith(expect.objectContaining({ event: "openrouter.credit_pulse" }));
    expect(captureError).toHaveBeenCalledTimes(1);
    expect(captureError).toHaveBeenCalledWith(
      expect.any(OpenRouterBudgetCriticalError),
      expect.objectContaining({ event: "openrouter.credit_critical" }),
    );
  });

  it("(5) 401 — HealthcheckFailedError(401, http)", async () => {
    mockFetchStatus(401);
    await checkCredit(noController, makeEnv(), noCtx);
    expect(captureError).toHaveBeenCalledTimes(1);
    const [err] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(err).toBeInstanceOf(OpenRouterHealthcheckFailedError);
    expect((err as OpenRouterHealthcheckFailedError).status).toBe(401);
    expect((err as OpenRouterHealthcheckFailedError).cause_kind).toBe("http");
    expect(logEvent).not.toHaveBeenCalled();
  });

  it("(6) 500 — HealthcheckFailedError(500, http)", async () => {
    mockFetchStatus(500);
    await checkCredit(noController, makeEnv(), noCtx);
    const [err] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
    expect((err as OpenRouterHealthcheckFailedError).status).toBe(500);
  });

  it("(7) 429 — HealthcheckFailedError(429, http)", async () => {
    mockFetchStatus(429);
    await checkCredit(noController, makeEnv(), noCtx);
    const [err] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
    expect((err as OpenRouterHealthcheckFailedError).status).toBe(429);
  });

  it("(8) network throw — HealthcheckFailedError(0, network)", async () => {
    mockFetchThrow(new TypeError("network error"));
    await checkCredit(noController, makeEnv(), noCtx);
    const [err, envelope] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(err).toBeInstanceOf(OpenRouterHealthcheckFailedError);
    expect((err as OpenRouterHealthcheckFailedError).status).toBe(0);
    expect((err as OpenRouterHealthcheckFailedError).cause_kind).toBe("network");
    expect((envelope as { attrs: { cause: string } }).attrs.cause).toBe("network");
  });

  it("(9) malformed JSON — HealthcheckFailedError(-1, parse)", async () => {
    mockFetchBadJson();
    await checkCredit(noController, makeEnv(), noCtx);
    const [err] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
    expect((err as OpenRouterHealthcheckFailedError).status).toBe(-1);
    expect((err as OpenRouterHealthcheckFailedError).cause_kind).toBe("parse");
  });

  it("(10) limit:null (unlimited key) — pulse only, ratio = 0", async () => {
    mockFetchOk({ data: { usage: 99999, limit: null } });
    await checkCredit(noController, makeEnv(), noCtx);
    expect(logEvent).toHaveBeenCalledTimes(1);
    const envelope = (logEvent as ReturnType<typeof vi.fn>).mock.calls[0][0];
    expect(envelope).toMatchObject({
      event: "openrouter.credit_pulse",
      attrs: { used: 99999, limit: 0, used_ratio: 0 },
    });
    expect(captureError).not.toHaveBeenCalled();
  });

  it("(11) inverted thresholds (warn=0.95, crit=0.85) — misconfig warn + fallback", async () => {
    mockFetchOk({ data: { usage: 90, limit: 100 } });
    await checkCredit(
      noController,
      makeEnv({ OPENROUTER_WARNING_RATIO: "0.95", OPENROUTER_CRITICAL_RATIO: "0.85" }),
      noCtx,
    );
    // First emission: misconfig warning (before the API call).
    expect(logEvent).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ event: "openrouter.misconfigured_thresholds", severity: "warn" }),
    );
    // After fallback to defaults (warn=0.85, crit=0.95), 0.90 used_ratio triggers credit_low.
    expect(logEvent).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ event: "openrouter.credit_pulse" }),
    );
    expect(logEvent).toHaveBeenNthCalledWith(
      3,
      expect.objectContaining({ event: "openrouter.credit_low", severity: "warn" }),
    );
  });

  it("(12) invalid env vars (NaN/negative/zero/>1/trailing-garbage/empty) — fallback to default 0.85", async () => {
    // "0" must fallback (would otherwise spam credit_low on every pulse since
    // any non-negative used_ratio satisfies `>= 0`).
    // "0.85extra" must fallback (parseFloat would silently accept 0.85; Number
    // correctly rejects trailing garbage).
    for (const bad of ["not-a-number", "-1", "0", "1.5", "0.85extra", ""]) {
      vi.clearAllMocks();
      mockFetchOk({ data: { usage: 85, limit: 100 } });
      await checkCredit(noController, makeEnv({ OPENROUTER_WARNING_RATIO: bad }), noCtx);
      // Default 0.85 kicks in → 85/100 = 0.85 → credit_low warn fires.
      expect(logEvent).toHaveBeenCalledWith(
        expect.objectContaining({ event: "openrouter.credit_low", severity: "warn" }),
      );
    }
  });

  it("(13) 200 OK + missing data — HealthcheckFailedError(-1, parse) NOT a false-healthy pulse", async () => {
    // Three malformed-200 shapes that the optional-chain would have silently
    // converted to used=0/limit=0/ratio=0 (a clean Axiom pulse) before the
    // contract guard was added. Each must now surface as a parse-class error.
    for (const malformed of [{}, { error: "key revoked" }, { data: null }]) {
      vi.clearAllMocks();
      mockFetchOk(malformed);
      await checkCredit(noController, makeEnv(), noCtx);
      expect(logEvent).not.toHaveBeenCalled(); // no false-healthy pulse
      expect(captureError).toHaveBeenCalledTimes(1);
      const [err] = (captureError as ReturnType<typeof vi.fn>).mock.calls[0];
      expect(err).toBeInstanceOf(OpenRouterHealthcheckFailedError);
      expect((err as OpenRouterHealthcheckFailedError).status).toBe(-1);
      expect((err as OpenRouterHealthcheckFailedError).cause_kind).toBe("parse");
    }
  });
});
