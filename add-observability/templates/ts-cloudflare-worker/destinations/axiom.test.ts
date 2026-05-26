/**
 * Role-dispatch + failure-path tests for the real Sentry + Axiom adapters.
 *
 * Phase 21 (P2.4). These drive the wrapper's PUBLIC entry points
 * (`init` → `logEvent` / `captureError` / `startSpan`) and assert that the
 * configured destination registry routes each role to the correct named
 * adapter — LOGS → Axiom (one POST to the ingest URL with bearer auth and a
 * `[envelope]` body), ERRORS → Sentry (scoped captureException) — without the
 * wrapper knowing about any SDK.
 *
 * Fake-fetch injection pattern (documented for P2 replication to the other
 * stacks): the Axiom adapter resolves its HTTP egress from `env.__fetch ??
 * globalThis.fetch` at `init` time and caches it. Tests therefore inject a
 * spy by passing `__fetch` on the InitEnv handed to `init(env, ctx)`. No
 * global monkey-patching, no module-level seam — the seam is the env, which is
 * already the adapter's only configuration source.
 *
 * Sentry is exercised through the real `@sentry/cloudflare` module; tests spy
 * on `Sentry.captureException` to assert the ERRORS role reached Sentry. The
 * wrapper only invokes Sentry when a DSN is configured (`SENTRY_DSN` set), so
 * the env carries one in the dispatch cases.
 *
 * Test runner: vitest (matches the wrapper + registry contract suites).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mock @sentry/cloudflare so we can assert the ERRORS role reaches Sentry.
// ESM namespaces are not spy-able (vi.spyOn fails on the module), so the whole
// module is mocked with vi.fn()s the test inspects.
vi.mock("@sentry/cloudflare", () => ({
  captureException: vi.fn(() => "evt-id"),
  withScope: vi.fn((cb: (s: unknown) => void) => {
    cb({ setTag() {}, setContext() {}, setLevel() {} });
  }),
  addBreadcrumb: vi.fn(),
}));

import * as Sentry from "@sentry/cloudflare";
import {
  init,
  logEvent,
  captureError,
  startSpan,
  type InitEnv,
} from "../index";
import type { ExecutionContext } from "./registry";

// ─── Fakes ──────────────────────────────────────────────────────────────────

interface FetchCall {
  url: string;
  init: RequestInit | undefined;
}

/**
 * Build a fake fetch that records every call and resolves to a 2xx Response by
 * default. `mode` controls the failure path: "ok" (200), "error500" (non-2xx),
 * or "reject" (the promise rejects).
 */
function makeFakeFetch(mode: "ok" | "error500" | "reject" = "ok") {
  const calls: FetchCall[] = [];
  const fn = vi.fn(
    (input: RequestInfo | URL, requestInit?: RequestInit): Promise<Response> => {
      calls.push({ url: String(input), init: requestInit });
      if (mode === "reject") return Promise.reject(new Error("network down"));
      const status = mode === "error500" ? 500 : 200;
      return Promise.resolve(
        new Response("{}", { status, headers: { "content-type": "application/json" } }),
      );
    },
  );
  return { fn, calls };
}

/** A waitUntil-capable ExecutionContext that awaits the registered promises. */
function makeCtx(): { ctx: ExecutionContext; settled: () => Promise<void> } {
  const pending: Promise<unknown>[] = [];
  const ctx: ExecutionContext = {
    waitUntil(p: Promise<unknown>): void {
      pending.push(p.catch(() => {}));
    },
    passThroughOnException(): void {},
  };
  return { ctx, settled: async () => { await Promise.all(pending); } };
}

const SENTRY_DSN = "https://key@org.ingest.sentry.io/123";
const AXIOM_TOKEN = "xaat-test";
const AXIOM_DATASET = "test-ds";
const DEFAULT_INGEST = `https://api.axiom.co/v1/datasets/${AXIOM_DATASET}/ingest`;

function envWith(extra: Partial<Record<string, unknown>>): InitEnv {
  return { ...extra } as InitEnv;
}

// ─── Setup ────────────────────────────────────────────────────────────────

const captureSpy = Sentry.captureException as unknown as ReturnType<typeof vi.fn>;
let warnSpy: ReturnType<typeof vi.spyOn>;
let logSpy: ReturnType<typeof vi.spyOn>;
let errorSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  vi.mocked(Sentry.captureException).mockClear();
  vi.mocked(Sentry.withScope).mockClear();
  vi.mocked(Sentry.addBreadcrumb).mockClear();
  // Silence the console mirror + rate-limited warns; assert via the spy.
  logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  logSpy.mockRestore();
  errorSpy.mockRestore();
  warnSpy.mockRestore();
});

// ─── Role-dispatch (4 cases) ────────────────────────────────────────────────

describe("role dispatch — logs→axiom, errors→sentry", () => {
  it("case 1: errors=sentry,logs=axiom → logEvent POSTs to Axiom; captureError → Sentry; Axiom gets no error", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        SENTRY_DSN,
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=sentry,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    logEvent({ event: "user_login", severity: "info", attrs: { id: 7 } });
    await settled();

    // Exactly one POST to the Axiom ingest URL with bearer auth + [envelope].
    const posts = fake.calls.filter((c) => c.url === DEFAULT_INGEST);
    expect(posts).toHaveLength(1);
    const post = posts[0];
    expect(post.init?.method).toBe("POST");
    const headers = new Headers(post.init?.headers as HeadersInit);
    expect(headers.get("authorization")).toBe(`Bearer ${AXIOM_TOKEN}`);
    expect(headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(post.init?.body as string);
    expect(Array.isArray(body)).toBe(true);
    expect(body).toHaveLength(1);
    expect(body[0].event).toBe("user_login");

    // captureError reaches Sentry (capture is fire-and-forget via waitUntil).
    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await settled();
    expect(captureSpy).toHaveBeenCalledTimes(1);
  });

  it("case 2: errors=sentry,logs=none → logEvent no POST; captureError → Sentry", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        SENTRY_DSN,
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=sentry,logs=none",
        __fetch: fake.fn,
      }),
      ctx,
    );

    logEvent({ event: "noop_log", severity: "info" });
    await settled();
    expect(fake.calls.filter((c) => c.url === DEFAULT_INGEST)).toHaveLength(0);

    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await settled();
    expect(captureSpy).toHaveBeenCalledTimes(1);
  });

  it("case 3: errors=none,logs=axiom → logEvent POSTs to Axiom; captureError no-ops (no throw, no Sentry)", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        // No SENTRY_DSN → wrapper-native Sentry path is off; errors=none anyway.
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    logEvent({ event: "user_login", severity: "info" });
    await settled();
    expect(fake.calls.filter((c) => c.url === DEFAULT_INGEST)).toHaveLength(1);

    expect(() =>
      captureError(new Error("boom"), { event: "explode", severity: "error" }),
    ).not.toThrow();
    expect(captureSpy).not.toHaveBeenCalled();
  });

  it("case 4: errors=none,logs=none → both no-op; no POST, no Sentry", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=none",
        __fetch: fake.fn,
      }),
      ctx,
    );

    logEvent({ event: "x", severity: "info" });
    captureError(new Error("boom"), { event: "y", severity: "error" });
    await settled();

    expect(fake.calls.filter((c) => c.url === DEFAULT_INGEST)).toHaveLength(0);
    expect(captureSpy).not.toHaveBeenCalled();
  });
});

// ─── Ingest URL override ──────────────────────────────────────────────────

describe("AXIOM_INGEST_URL override", () => {
  it("uses the override URL when set", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    const override = "https://proxy.example.com/ingest";
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        AXIOM_INGEST_URL: override,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    logEvent({ event: "x", severity: "info" });
    await settled();

    expect(fake.calls.map((c) => c.url)).toContain(override);
    expect(fake.calls.filter((c) => c.url === DEFAULT_INGEST)).toHaveLength(0);
  });
});

// ─── Failure path — never-throw ─────────────────────────────────────────────

describe("never-throw egress", () => {
  it("fake fetch REJECTS → logEvent does not throw, one rate-limited warn", async () => {
    const fake = makeFakeFetch("reject");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    expect(() => {
      logEvent({ event: "a", severity: "info" });
      logEvent({ event: "b", severity: "info" });
      logEvent({ event: "c", severity: "info" });
    }).not.toThrow();
    await settled();

    // Multiple failures collapse to a single rate-limited warn for the cooldown window.
    const axiomWarns = warnSpy.mock.calls.filter((c) =>
      String(c[0]).includes("axiom"),
    );
    expect(axiomWarns.length).toBe(1);
  });

  it("fake fetch returns non-2xx (500) → no throw, warn", async () => {
    const fake = makeFakeFetch("error500");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    expect(() => logEvent({ event: "a", severity: "info" })).not.toThrow();
    await settled();

    const axiomWarns = warnSpy.mock.calls.filter((c) =>
      String(c[0]).includes("axiom"),
    );
    expect(axiomWarns.length).toBe(1);
  });

  it("no ctx.waitUntil present → still no unhandled rejection", async () => {
    const fake = makeFakeFetch("reject");
    // ctx whose waitUntil throws → wrapper degrades waitUntilFn to null; the
    // Axiom adapter must fall back to void p.catch(warnOnce).
    const ctx = {
      waitUntil() {
        throw new Error("no waitUntil");
      },
      passThroughOnException() {},
    } as unknown as ExecutionContext;

    let unhandled = false;
    const onUnhandled = () => {
      unhandled = true;
    };
    process.on("unhandledRejection", onUnhandled);

    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );

    expect(() => logEvent({ event: "a", severity: "info" })).not.toThrow();
    // Let microtasks + a macrotask flush so any rejection would surface.
    await new Promise((r) => setTimeout(r, 10));
    process.off("unhandledRejection", onUnhandled);
    expect(unhandled).toBe(false);
  });
});

// ─── startSpan regression ───────────────────────────────────────────────────

describe("startSpan regression", () => {
  it("valid span + idempotent end under SENTRY_DSN unset", () => {
    init(envWith({}), makeCtx().ctx);
    const span = startSpan("work", { k: "v" });
    expect(span.traceId).toMatch(/^[0-9a-f]{32}$/);
    expect(span.spanId).toMatch(/^[0-9a-f]{16}$/);
    span.end();
    expect(() => span.end()).not.toThrow();
  });

  it("valid span + idempotent end under errors=none,logs=axiom", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );
    const span = startSpan("work", { k: "v" });
    expect(span.traceId).toMatch(/^[0-9a-f]{32}$/);
    expect(span.spanId).toMatch(/^[0-9a-f]{16}$/);
    expect(() => {
      span.end();
      span.end();
    }).not.toThrow();
    await settled();
  });
});
