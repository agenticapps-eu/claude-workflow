/**
 * queue-monitor.test.ts — withQueueMonitor contract suite (ts-cloudflare-worker).
 *
 * Tests the Sentry Crons heartbeat wrapper contract for Cloudflare Queue
 * consumer handlers, mirroring withCronMonitor's Phase 22 + Phase 23 design:
 *   D-07 — new wrapper export (ADR-0033; cf-worker + cf-pages only per codex H-6)
 *   D-08 — Guarded Shape A semantics (ADR-0029 inheritance) + codex M-6 sync-throw
 *   D-09 — 3-source slug resolution; auto-derive uses batch.queue
 *   D-10 — silent + docs multi-queue policy (tightened canonical-phrase regex)
 *   D-17 — behavioural-parity tests (mirrors cron-monitor.test.ts; narrowed to cf-worker + cf-pages)
 *
 * Sentry SDK is mocked at the module boundary — same pattern as cron-monitor.test.ts.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { withQueueMonitor } from "./queue-monitor";

const withMonitor = vi.fn();
vi.mock("@sentry/cloudflare", () => ({
  withMonitor: (...args: unknown[]) => withMonitor(...args),
}));

const fakeBatch = {
  queue: "kompendium-events",
  messages: [],
  retryAll: vi.fn(),
  ackAll: vi.fn(),
} as unknown as MessageBatch<unknown>;
const fakeCtx = { waitUntil: vi.fn(), passThroughOnException: vi.fn() } as unknown as ExecutionContext;
const fakeEnv = { SENTRY_DSN: "https://stub@sentry.io/1" } as { SENTRY_DSN: string };

beforeEach(() => {
  withMonitor.mockReset();
  withMonitor.mockImplementation(async (_slug: unknown, cb: () => unknown) => cb());
});

describe("withQueueMonitor — Guarded Shape A (ADR-0029 / D-08)", () => {
  it("calls Sentry.withMonitor with resolved slug and monitorConfig on happy path", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler, {
      monitorSlug: "callbot:queue:kompendium-events",
      schedule: { type: "interval", value: 5, unit: "minute" },
      maxRuntimeSeconds: 60,
    });
    await wrapped(fakeBatch, fakeEnv, fakeCtx);

    expect(withMonitor).toHaveBeenCalledOnce();
    expect(withMonitor).toHaveBeenCalledWith(
      "callbot:queue:kompendium-events",
      expect.any(Function),
      { schedule: { type: "interval", value: 5, unit: "minute" }, maxRuntime: 60 },
    );
    expect(handler).toHaveBeenCalledOnce();
  });

  it("ASYNC handler rejection propagates (post-callback path)", async () => {
    const boom = new Error("handler exploded async");
    const handler = vi.fn(async () => { throw boom; });
    const wrapped = withQueueMonitor(handler, { monitorSlug: "x" });
    await expect(wrapped(fakeBatch, fakeEnv, fakeCtx)).rejects.toBe(boom);
    expect(handler).toHaveBeenCalledOnce();
  });

  // ── Codex M-6 NEW: synchronous-throw post-callback test ────────────────
  it("Guarded Shape A: handler sets handlerStarted=true and throws SYNCHRONOUSLY → wrapper re-throws (post-callback path)", async () => {
    // The Guarded Shape A pattern (handlerStarted flag inside the withMonitor
    // callback) must correctly route a SYNCHRONOUS throw — not just an async
    // rejection — as a post-callback error. Mock withMonitor to invoke the
    // callback synchronously so any sync throw inside the callback bubbles
    // straight through the try/catch with handlerStarted already true.
    withMonitor.mockImplementation((_slug: unknown, cb: () => unknown) => cb());
    const syncErr = new Error("sync handler failure");
    const handler = vi.fn(((_b: unknown, _e: unknown, _c: unknown): void => {
      throw syncErr;
    }) as unknown as (b: MessageBatch<unknown>, e: typeof fakeEnv, c: ExecutionContext) => Promise<void>);
    const wrapped = withQueueMonitor(handler, { monitorSlug: "x" });
    await expect(wrapped(fakeBatch, fakeEnv, fakeCtx)).rejects.toBe(syncErr);
    expect(handler).toHaveBeenCalledOnce();
  });

  it("no-ops cleanly when SENTRY_DSN is unset (R02 fail-safe preserved)", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler, { monitorSlug: "x" });
    await wrapped(fakeBatch, {} as { SENTRY_DSN?: string }, fakeCtx);
    expect(handler).toHaveBeenCalledOnce();
    expect(withMonitor).not.toHaveBeenCalled();
  });

  it("D-08 guard: withMonitor throws BEFORE callback runs → handler runs unmonitored", async () => {
    const handler = vi.fn(async () => {});
    withMonitor.mockRejectedValue(new Error("Sentry transport failure"));
    const wrapped = withQueueMonitor(handler, { monitorSlug: "x" });
    await wrapped(fakeBatch, fakeEnv, fakeCtx);
    expect(handler).toHaveBeenCalledOnce();
  });

  it("D-08 guard: withMonitor throws AFTER callback ran → error propagates", async () => {
    const handler = vi.fn(async () => {});
    withMonitor.mockImplementation(async (_slug: unknown, cb: () => unknown) => {
      await cb();
      throw new Error("post-callback transport failure");
    });
    const wrapped = withQueueMonitor(handler, { monitorSlug: "x" });
    await expect(wrapped(fakeBatch, fakeEnv, fakeCtx)).rejects.toThrow("post-callback transport failure");
    expect(handler).toHaveBeenCalledOnce();
  });
});

describe("withQueueMonitor — slug resolution (D-09)", () => {
  it("explicit config.monitorSlug wins over env and auto", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler, { monitorSlug: "explicit-wins" });
    await wrapped(fakeBatch, {
      SENTRY_DSN: "https://stub@sentry.io/1",
      SENTRY_CRON_MONITOR_SLUG_QUEUE: "env-loses",
      SERVICE_NAME: "auto-loses",
    } as { SENTRY_DSN: string; SENTRY_CRON_MONITOR_SLUG_QUEUE: string; SERVICE_NAME: string }, fakeCtx);
    expect(withMonitor).toHaveBeenCalledWith("explicit-wins", expect.any(Function), undefined);
  });

  it("falls back to SENTRY_CRON_MONITOR_SLUG_QUEUE env when explicit absent", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler);
    await wrapped(fakeBatch, {
      SENTRY_DSN: "https://stub@sentry.io/1",
      SENTRY_CRON_MONITOR_SLUG_QUEUE: "env-wins",
      SERVICE_NAME: "auto-loses",
    } as { SENTRY_DSN: string; SENTRY_CRON_MONITOR_SLUG_QUEUE: string; SERVICE_NAME: string }, fakeCtx);
    expect(withMonitor).toHaveBeenCalledWith("env-wins", expect.any(Function), undefined);
  });

  it("falls back to auto-derived ${SERVICE_NAME}:queue:${batch.queue} when neither set", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler);
    await wrapped(fakeBatch, {
      SENTRY_DSN: "https://stub@sentry.io/1",
      SERVICE_NAME: "callbot",
    } as { SENTRY_DSN: string; SERVICE_NAME: string }, fakeCtx);
    expect(withMonitor).toHaveBeenCalledWith("callbot:queue:kompendium-events", expect.any(Function), undefined);
  });

  it("auto-derive defaults SERVICE_NAME to 'service' when unset", async () => {
    const handler = vi.fn(async () => {});
    const wrapped = withQueueMonitor(handler);
    await wrapped(fakeBatch, { SENTRY_DSN: "https://stub@sentry.io/1" } as { SENTRY_DSN: string }, fakeCtx);
    expect(withMonitor).toHaveBeenCalledWith("service:queue:kompendium-events", expect.any(Function), undefined);
  });
});

describe("withQueueMonitor — multi-queue documentation (D-10)", () => {
  it("queue-monitor.ts contains canonical-phrase doc-comment requiring explicit monitorSlug for multi-queue handlers", () => {
    // D-10 silent + docs policy: handlers dispatching by batch.queue MUST set monitorSlug explicitly.
    // Enforced via tightened canonical-phrase doc-comment regex — does NOT match organic
    // `batch.queue` mentions (which would silently pass without actual D-10 enforcement).
    const src = readFileSync(new URL("./queue-monitor.ts", import.meta.url), "utf8");
    expect(src).toMatch(/multi-queue.*MUST.*monitorSlug|MUST set monitorSlug explicitly|MUST pass explicit.*monitorSlug/i);
  });
});
