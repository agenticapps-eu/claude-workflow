/**
 * Full contract harness for the cf-pages observability wrapper (D3).
 *
 * Phase 21 (P2.3). ts-cloudflare-pages historically shipped ZERO contract
 * tests — its wrapper inherits the byte-identical cf-worker module. This file
 * closes that zero-coverage gap with the same 15 baseline contract tests the
 * cf-worker suite pins (trace roundtrip, fail-safe no-throw, span lifecycle,
 * active-context propagation, console mirror), PLUS the Axiom role-dispatch +
 * never-throw failure-path + startSpan-regression tests mirrored from
 * cf-worker's axiom.test.ts.
 *
 * Cloudflare Pages Functions run on the Workers runtime: `env` arg +
 * `ctx.waitUntil` fire-and-forget + `@sentry/cloudflare`. The wrapper module
 * and its destination adapters are therefore identical in shape to cf-worker.
 *
 * Fake-fetch injection: the Axiom adapter resolves its HTTP egress from
 * `env.__fetch ?? globalThis.fetch` at `init` time. Tests inject a spy by
 * passing `__fetch` on the InitEnv handed to `init(env, ctx)` — no global
 * monkey-patching.
 *
 * Test runner: vitest.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mock @sentry/cloudflare so we can assert the ERRORS role reaches Sentry.
vi.mock("@sentry/cloudflare", () => ({
  captureException: vi.fn(() => "evt-id"),
  withScope: vi.fn((cb: (s: unknown) => void) => {
    cb({ setTag() {}, setContext() {}, setLevel() {} });
  }),
  addBreadcrumb: vi.fn(),
}));

import * as Sentry from "@sentry/cloudflare";
import {
  parseTraceparent,
  newRootContext,
  formatTraceparent,
  startSpan,
  logEvent,
  captureError,
  runWithContext,
  getActiveContext,
  init,
  type InitEnv,
} from "./index";
import type { ExecutionContext } from "./destinations/registry";

// ─── §10.3 traceparent roundtrip (contract) ─────────────────────────────────

describe("§10.3 traceparent", () => {
  it("roundtrips: format → parse → identical trace_id and parent_id", () => {
    const root = newRootContext();
    const header = formatTraceparent(root);
    const parsed = parseTraceparent(header);
    expect(parsed).not.toBeNull();
    expect(parsed!.traceId).toBe(root.traceId);
    expect(parsed!.parentSpanId).toBe(root.spanId);
  });

  it("rejects malformed inputs", () => {
    for (const header of [
      "",
      "not-a-traceparent",
      "00-tooshort-tooshort-01",
      "00-XYZ-not-hex-01",
    ]) {
      expect(parseTraceparent(header), `expected reject for ${header}`).toBeNull();
    }
  });

  it("accepts the canonical W3C example", () => {
    const header = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";
    const tc = parseTraceparent(header);
    expect(tc).not.toBeNull();
    expect(tc!.traceId).toBe("4bf92f3577b34da6a3ce929d0e0e4736");
    expect(tc!.parentSpanId).toBe("00f067aa0ba902b7");
    expect(tc!.spanId).toHaveLength(16);
    expect(tc!.spanId).not.toBe(tc!.parentSpanId);
  });
});

// ─── §10.5 fail-safe (contract) ──────────────────────────────────────────────

describe("§10.5 fail-safe", () => {
  it("logEvent does not throw without init", () => {
    expect(() => logEvent({ event: "test", severity: "info" })).not.toThrow();
  });

  it("captureError does not throw with a real Error", () => {
    expect(() =>
      captureError(new Error("boom"), { event: "test_capture", severity: "error" }),
    ).not.toThrow();
  });

  it("captureError does not throw with a non-Error value", () => {
    expect(() => captureError("string error", { event: "test" })).not.toThrow();
    expect(() => captureError({ weird: "object" }, { event: "test" })).not.toThrow();
    expect(() => captureError(undefined, { event: "test" })).not.toThrow();
  });
});

// ─── §10.1 span lifecycle (contract) ─────────────────────────────────────────

describe("§10.1 startSpan", () => {
  it("returns a span with traceId and spanId", () => {
    const span = startSpan("test", { k: "v" });
    expect(span.traceId).toMatch(/^[0-9a-f]{32}$/);
    expect(span.spanId).toMatch(/^[0-9a-f]{16}$/);
    span.end();
  });

  it("end() is idempotent", () => {
    const span = startSpan("test");
    span.end();
    expect(() => span.end()).not.toThrow();
  });

  it("setStatus + end emits without throwing", () => {
    const span = startSpan("test");
    span.setStatus("error");
    expect(() => span.end()).not.toThrow();
  });

  it("setAttribute on a span doesn't throw", () => {
    const span = startSpan("test");
    expect(() => span.setAttribute("k", "v")).not.toThrow();
    expect(() => span.setAttribute("password", "leaked")).not.toThrow(); // redacted internally
    span.end();
  });
});

// ─── §10.3 runWithContext / getActiveContext (contract) ──────────────────────

describe("§10.3 active-context propagation", () => {
  it("getActiveContext returns null outside runWithContext", () => {
    expect(getActiveContext()).toBeNull();
  });

  it("getActiveContext returns the bound context inside runWithContext", () => {
    const root = newRootContext();
    runWithContext(root, "test", () => {
      const active = getActiveContext();
      expect(active).not.toBeNull();
      expect(active!.traceId).toBe(root.traceId);
      expect(active!.spanId).toBe(root.spanId);
    });
  });

  it("nested runWithContext scopes correctly", () => {
    const outer = newRootContext();
    const inner = newRootContext();
    runWithContext(outer, "outer", () => {
      expect(getActiveContext()!.traceId).toBe(outer.traceId);
      runWithContext(inner, "inner", () => {
        expect(getActiveContext()!.traceId).toBe(inner.traceId);
      });
      expect(getActiveContext()!.traceId).toBe(outer.traceId);
    });
  });
});

// ─── §10.5 console mirror smoke test (contract) ──────────────────────────────

describe("§10.5 stdout mirror", () => {
  it("error severity writes to console.error", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    logEvent({ event: "test_error", severity: "error" });
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });

  it("info severity writes to console.log", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    logEvent({ event: "test_info", severity: "info" });
    expect(spy).toHaveBeenCalled();
    spy.mockRestore();
  });
});

// ─── §10.6 redaction (contract) ──────────────────────────────────────────────

describe("§10.6 redaction", () => {
  it("scrubs default-policy keys from logEvent attrs in the console mirror", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    logEvent({
      event: "redact_check",
      severity: "info",
      attrs: { password: "hunter2", api_key: "xyz", keep: "ok" },
    });
    expect(spy).toHaveBeenCalled();
    const line = String(spy.mock.calls[spy.mock.calls.length - 1][0]);
    expect(line).not.toContain("hunter2");
    expect(line).not.toContain("xyz");
    expect(line).toContain("[redacted]");
    expect(line).toContain("ok");
    spy.mockRestore();
  });
});

// ─── Axiom role-dispatch + failure paths (mirror cf-worker axiom.test.ts) ────

interface FetchCall {
  url: string;
  init: RequestInit | undefined;
}

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

const captureSpy = Sentry.captureException as unknown as ReturnType<typeof vi.fn>;
let warnSpy: ReturnType<typeof vi.spyOn>;
let logSpy: ReturnType<typeof vi.spyOn>;
let errorSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  vi.mocked(Sentry.captureException).mockClear();
  vi.mocked(Sentry.withScope).mockClear();
  vi.mocked(Sentry.addBreadcrumb).mockClear();
  logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
});

afterEach(() => {
  logSpy.mockRestore();
  errorSpy.mockRestore();
  warnSpy.mockRestore();
});

describe("role dispatch — logs→axiom, errors→sentry", () => {
  it("case 1: errors=sentry,logs=axiom → logEvent POSTs to Axiom; captureError → Sentry", async () => {
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

    const axiomWarns = warnSpy.mock.calls.filter((c) => String(c[0]).includes("axiom"));
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

    const axiomWarns = warnSpy.mock.calls.filter((c) => String(c[0]).includes("axiom"));
    expect(axiomWarns.length).toBe(1);
  });

  it("no ctx.waitUntil present → still no unhandled rejection", async () => {
    const fake = makeFakeFetch("reject");
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
    await new Promise((r) => setTimeout(r, 10));
    process.off("unhandledRejection", onUnhandled);
    expect(unhandled).toBe(false);
  });

  it("isConfigured false (no AXIOM_TOKEN) → logEvent no POST, no throw", async () => {
    const fake = makeFakeFetch("ok");
    const { ctx, settled } = makeCtx();
    init(
      envWith({
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
      ctx,
    );
    expect(() => logEvent({ event: "a", severity: "info" })).not.toThrow();
    await settled();
    expect(fake.calls).toHaveLength(0);
  });
});

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

// ─── §10.6 redaction depth (issue #49 — gap #1) ─────────────────────────────

describe("§10.6 redaction recurses into nested objects and arrays", () => {
  it("scrubs secrets nested under non-secret keys and inside arrays of objects", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    logEvent({
      event: "request",
      severity: "info",
      attrs: {
        request: { headers: { secret: "leak-me", "x-ok": "fine" } },
        items: [{ password: "p1" }, { ok: "yes" }],
      },
    });
    const logged = JSON.parse(spy.mock.calls.at(-1)![0] as string);
    expect(logged.attrs.request.headers.secret).toBe("[redacted]");
    expect(logged.attrs.request.headers["x-ok"]).toBe("fine");
    expect(logged.attrs.items[0].password).toBe("[redacted]");
    expect(logged.attrs.items[1].ok).toBe("yes");
    spy.mockRestore();
  });
});

// ─── §10.4 captureError visibility (issue #49 — gap #2) ─────────────────────

describe("§10.4 captureError is never sampled out", () => {
  it("coerces a caller-supplied low severity so the exception still emits", () => {
    const rnd = vi.spyOn(Math, "random").mockReturnValue(0.999999);
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    captureError(new Error("boom"), { event: "explode", severity: "debug" });
    expect(errSpy).toHaveBeenCalled();
    errSpy.mockRestore();
    rnd.mockRestore();
  });
});

// ─── §10.3 traceparent semantics (issue #49 — gap #4) ───────────────────────

describe("§10.3 traceparent semantic validation", () => {
  it("rejects all-zero ids and non-00 version", () => {
    for (const header of [
      "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
      "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ]) {
      expect(parseTraceparent(header), `expected reject for ${header}`).toBeNull();
    }
  });
});
