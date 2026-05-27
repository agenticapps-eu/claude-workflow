/**
 * Axiom role-dispatch + browser-no-token tests (ts-react-vite / browser).
 *
 * Phase 21 (P2.4 + review #8). Mirrors the cf-worker axiom.test.ts shape,
 * adapted to the browser runtime:
 *
 *   - Env is read from `import.meta.env`. Tests inject config via the
 *     TEST-ONLY `_resetForTest(env)` seam (which also carries `__fetch`), so
 *     the destination registry is exercised without stubbing import.meta.env.
 *   - BROWSER HARD RULE (review #8): the Axiom adapter NEVER ships an ingest
 *     token. It is `isConfigured()` ONLY when `VITE_AXIOM_PROXY_URL` is set,
 *     and POSTs to that same-origin proxy with NO Authorization header. A
 *     dedicated test statically asserts the adapter source reads neither
 *     `VITE_AXIOM_TOKEN` nor `VITE_AXIOM_DATASET`, and that without a proxy URL
 *     the adapter is console-only (logEvent no-ops to console).
 *   - Fire-and-forget prefers `navigator.sendBeacon`; falls back to a detached
 *     fetch. Both never-throw + rate-limited warn.
 *
 * Test runner: vitest (jsdom environment).
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Resolve this test's own directory robustly under vitest (jsdom does not give
// import.meta.url a file: scheme; import.meta.dirname is the reliable seam).
const TEST_DIR =
  typeof import.meta.dirname === "string"
    ? import.meta.dirname
    : dirname(fileURLToPath(import.meta.url));

// Mock @sentry/react so we can assert the ERRORS role reaches Sentry and so
// ErrorBoundary's import resolves under jsdom.
vi.mock("@sentry/react", () => ({
  init: vi.fn(),
  captureException: vi.fn(() => "evt-id"),
  withScope: vi.fn((cb: (s: unknown) => void) => {
    cb({ setTag() {}, setContext() {}, setLevel() {} });
  }),
  addBreadcrumb: vi.fn(),
  ErrorBoundary: () => null,
}));

import * as Sentry from "@sentry/react";
import { _resetForTest, init, logEvent, captureError, startSpan, type InitEnv } from "./index";

// ─── Fakes ──────────────────────────────────────────────────────────────────

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

const SENTRY_DSN = "https://key@org.ingest.sentry.io/123";
const PROXY_URL = "/api/axiom-proxy"; // same-origin proxy; token injected server-side

function envWith(extra: Partial<Record<string, unknown>>): InitEnv {
  return { ...extra } as InitEnv;
}

const captureSpy = Sentry.captureException as unknown as ReturnType<typeof vi.fn>;
let warnSpy: ReturnType<typeof vi.spyOn>;
let logSpy: ReturnType<typeof vi.spyOn>;
let errorSpy: ReturnType<typeof vi.spyOn>;
let beaconSpy: ReturnType<typeof vi.fn> | undefined;

beforeEach(() => {
  vi.mocked(Sentry.captureException).mockClear();
  vi.mocked(Sentry.withScope).mockClear();
  vi.mocked(Sentry.addBreadcrumb).mockClear();
  logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
  // Default: no sendBeacon → adapter falls back to fetch. Individual tests opt
  // into a beacon spy.
  beaconSpy = undefined;
  // @ts-expect-error jsdom navigator is writable in tests
  if (typeof navigator !== "undefined") delete (navigator as { sendBeacon?: unknown }).sendBeacon;
});

afterEach(() => {
  logSpy.mockRestore();
  errorSpy.mockRestore();
  warnSpy.mockRestore();
});

function flushAsync(): Promise<void> {
  return new Promise((r) => setTimeout(r, 10));
}

// ─── Browser HARD RULE: no token in client code (review #8) ──────────────────

describe("browser no-token rule", () => {
  it("the Axiom adapter source reads NO VITE_AXIOM_TOKEN / VITE_AXIOM_DATASET", () => {
    const src = readFileSync(join(TEST_DIR, "destinations", "axiom.ts"), "utf8");
    // Ignore the doc-comment that explicitly NAMES these as forbidden by
    // checking only for real env reads (env.AXIOM_TOKEN / e.AXIOM_DATASET style)
    // and the VITE_ token names outside comments.
    const code = src
      .split("\n")
      .filter((l) => !l.trim().startsWith("*") && !l.trim().startsWith("//"))
      .join("\n");
    expect(code).not.toContain("VITE_AXIOM_TOKEN");
    expect(code).not.toContain("VITE_AXIOM_DATASET");
    expect(code).not.toContain("AXIOM_TOKEN");
    expect(code).not.toContain("AXIOM_DATASET");
    // It MUST read the proxy URL instead.
    expect(code).toContain("AXIOM_PROXY_URL");
    // And MUST NOT set an Authorization header (proxy injects the token).
    expect(code.toLowerCase()).not.toContain("authorization");
  });

  it("no VITE_AXIOM_PROXY_URL → adapter is console-only (logEvent no-ops to console, no POST)", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        // No AXIOM_PROXY_URL → axiom adapter unconfigured → forRole('logs')=null.
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(fake.calls).toHaveLength(0);
    // Console mirror still fires.
    expect(logSpy).toHaveBeenCalled();
  });
});

// ─── Role dispatch ────────────────────────────────────────────────────────────

describe("role dispatch — logs→axiom(proxy), errors→sentry", () => {
  it("case 1: errors=sentry,logs=axiom → logEvent POSTs to proxy (no auth header); captureError → Sentry", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        SENTRY_DSN,
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=sentry,logs=axiom",
        __fetch: fake.fn,
      }));
    init();

    logEvent({ event: "user_login", severity: "info", attrs: { id: 7 } });
    await flushAsync();

    const posts = fake.calls.filter((c) => c.url === PROXY_URL);
    expect(posts).toHaveLength(1);
    expect(posts[0].init?.method).toBe("POST");
    const headers = new Headers(posts[0].init?.headers as HeadersInit);
    // CRITICAL: no Authorization header — the proxy injects the token.
    expect(headers.get("authorization")).toBeNull();
    expect(headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(posts[0].init?.body as string);
    expect(Array.isArray(body)).toBe(true);
    expect(body[0].event).toBe("user_login");

    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await flushAsync();
    expect(captureSpy).toHaveBeenCalledTimes(1);
  });

  it("case 2: errors=sentry,logs=none → logEvent no POST; captureError → Sentry", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        SENTRY_DSN,
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=sentry,logs=none",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "noop_log", severity: "info" });
    await flushAsync();
    expect(fake.calls.filter((c) => c.url === PROXY_URL)).toHaveLength(0);
    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await flushAsync();
    expect(captureSpy).toHaveBeenCalledTimes(1);
  });

  it("case 3: errors=none,logs=axiom → logEvent POSTs to proxy; captureError no-ops (no throw, no Sentry)", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "user_login", severity: "info" });
    await flushAsync();
    expect(fake.calls.filter((c) => c.url === PROXY_URL)).toHaveLength(1);
    expect(() =>
      captureError(new Error("boom"), { event: "explode", severity: "error" }),
    ).not.toThrow();
    expect(captureSpy).not.toHaveBeenCalled();
  });

  it("case 4: errors=none,logs=none → both no-op; no POST, no Sentry", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=none",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    captureError(new Error("boom"), { event: "y", severity: "error" });
    await flushAsync();
    expect(fake.calls.filter((c) => c.url === PROXY_URL)).toHaveLength(0);
    expect(captureSpy).not.toHaveBeenCalled();
  });
});

// ─── sendBeacon preference ────────────────────────────────────────────────────

describe("sendBeacon fire-and-forget", () => {
  it("prefers navigator.sendBeacon when available (no fetch fallback)", async () => {
    const fake = makeFakeFetch("ok");
    beaconSpy = vi.fn(() => true);
    // @ts-expect-error stub sendBeacon on jsdom navigator
    navigator.sendBeacon = beaconSpy;
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(beaconSpy).toHaveBeenCalledTimes(1);
    expect(beaconSpy.mock.calls[0][0]).toBe(PROXY_URL);
    // fetch not used when beacon succeeds.
    expect(fake.calls).toHaveLength(0);
  });

  it("falls back to fetch when sendBeacon returns false", async () => {
    const fake = makeFakeFetch("ok");
    beaconSpy = vi.fn(() => false);
    // @ts-expect-error stub sendBeacon on jsdom navigator
    navigator.sendBeacon = beaconSpy;
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(beaconSpy).toHaveBeenCalledTimes(1);
    expect(fake.calls.filter((c) => c.url === PROXY_URL)).toHaveLength(1);
  });
});

// ─── never-throw egress ───────────────────────────────────────────────────────

describe("never-throw egress (fetch fallback)", () => {
  it("fake fetch REJECTS → logEvent does not throw, one rate-limited warn", async () => {
    const fake = makeFakeFetch("reject");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    expect(() => {
      logEvent({ event: "a", severity: "info" });
      logEvent({ event: "b", severity: "info" });
      logEvent({ event: "c", severity: "info" });
    }).not.toThrow();
    await flushAsync();
    const axiomWarns = warnSpy.mock.calls.filter((c) => String(c[0]).includes("axiom"));
    expect(axiomWarns.length).toBe(1);
  });

  it("fake fetch returns non-2xx (500) → no throw, warn", async () => {
    const fake = makeFakeFetch("error500");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    expect(() => logEvent({ event: "a", severity: "info" })).not.toThrow();
    await flushAsync();
    const axiomWarns = warnSpy.mock.calls.filter((c) => String(c[0]).includes("axiom"));
    expect(axiomWarns.length).toBe(1);
  });
});

// ─── BROWSER HARD RULE: same-origin proxy only (issue #49 — gap #3) ──────────

describe("cross-origin proxy URL is rejected", () => {
  it("absolute cross-origin URL → adapter unconfigured, no POST", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: "https://evil.example.com/ingest",
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(fake.calls.filter((c) => c.url.includes("evil.example.com"))).toHaveLength(0);
    expect(fake.calls).toHaveLength(0);
  });

  it("protocol-relative //host URL → rejected, no POST", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: "//evil.example.com/ingest",
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(fake.calls).toHaveLength(0);
  });

  it("same-origin relative path is still accepted (POSTs)", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    expect(fake.calls.filter((c) => c.url === PROXY_URL)).toHaveLength(1);
  });
});

// ─── startSpan regression ───────────────────────────────────────────────────

describe("startSpan regression", () => {
  it("valid span + idempotent end under SENTRY_DSN unset", () => {
    _resetForTest(envWith({}));
    init();
    const span = startSpan("work", { k: "v" });
    expect(span.traceId).toMatch(/^[0-9a-f]{32}$/);
    expect(span.spanId).toMatch(/^[0-9a-f]{16}$/);
    span.end();
    expect(() => span.end()).not.toThrow();
  });

  it("valid span + idempotent end under errors=none,logs=axiom", async () => {
    const fake = makeFakeFetch("ok");
    _resetForTest(envWith({
        AXIOM_PROXY_URL: PROXY_URL,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }));
    init();
    const span = startSpan("work", { k: "v" });
    expect(span.traceId).toMatch(/^[0-9a-f]{32}$/);
    expect(() => {
      span.end();
      span.end();
    }).not.toThrow();
    await flushAsync();
  });
});
