/**
 * Axiom role-dispatch + never-throw failure-path tests (Supabase Edge / Deno).
 *
 * Phase 21 (P2.4). Mirrors the cf-worker axiom.test.ts shape, adapted to the
 * Deno runtime: env comes from `Deno.env.get(...)` (the wrapper's `init`
 * accepts an optional InitEnv override so tests can inject `__fetch` +
 * `OBS_DESTINATIONS` without mutating the real Deno.env), and fire-and-forget
 * egress uses `EdgeRuntime.waitUntil(p)` when present (guarded) — else a
 * detached `void p.catch(...)`.
 *
 * Sentry (`npm:@sentry/deno`) is exercised through the real module without a
 * DSN, so the ERRORS-role assertions here verify that `captureError` does not
 * throw and never reaches the Axiom logs sink (Axiom's captureException is a
 * no-op by contract). Sentry's own emission path is covered by the contract
 * suite's fail-safe tests.
 *
 * Run with: deno test -A --no-check axiom.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  init,
  logEvent,
  captureError,
  startSpan,
  type InitEnv,
} from "./index.ts";

interface FetchCall {
  url: string;
  init: RequestInit | undefined;
}

function makeFakeFetch(mode: "ok" | "error500" | "reject" = "ok") {
  const calls: FetchCall[] = [];
  const fn = (input: string | URL | Request, requestInit?: RequestInit): Promise<Response> => {
    calls.push({ url: String(input), init: requestInit });
    if (mode === "reject") return Promise.reject(new Error("network down"));
    const status = mode === "error500" ? 500 : 200;
    return Promise.resolve(
      new Response("{}", { status, headers: { "content-type": "application/json" } }),
    );
  };
  return { fn, calls };
}

const SENTRY_DSN = "https://key@org.ingest.sentry.io/123";
const AXIOM_TOKEN = "xaat-test";
const AXIOM_DATASET = "test-ds";
const DEFAULT_INGEST = `https://api.axiom.co/v1/datasets/${AXIOM_DATASET}/ingest`;

function envWith(extra: Partial<Record<string, unknown>>): InitEnv {
  return { ...extra } as InitEnv;
}

// Let the EdgeRuntime.waitUntil-or-detached promise settle. The adapter does
// not expose a settle hook (no ctx), so we yield a couple of macrotasks.
function flushAsync(): Promise<void> {
  return new Promise((r) => setTimeout(r, 10));
}

// Silence the console mirror + rate-limited warns; collect axiom warns.
function withSilencedConsole(): { axiomWarns: () => number; restore: () => void } {
  const origLog = console.log;
  const origError = console.error;
  const origWarn = console.warn;
  let warns = 0;
  console.log = () => {};
  console.error = () => {};
  console.warn = (...args: unknown[]) => {
    if (String(args[0]).includes("axiom")) warns += 1;
  };
  return {
    axiomWarns: () => warns,
    restore: () => {
      console.log = origLog;
      console.error = origError;
      console.warn = origWarn;
    },
  };
}

// ─── Role dispatch (4 cases) ─────────────────────────────────────────────────

Deno.test({
  name: "case 1: errors=sentry,logs=axiom → logEvent POSTs to Axiom; captureError no-throw, no Axiom error",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        SENTRY_DSN,
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=sentry,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "user_login", severity: "info", attrs: { id: 7 } });
    await flushAsync();

    const posts = fake.calls.filter((c) => c.url === DEFAULT_INGEST);
    assertEquals(posts.length, 1);
    assertEquals(posts[0].init?.method, "POST");
    const headers = new Headers(posts[0].init?.headers as HeadersInit);
    assertEquals(headers.get("authorization"), `Bearer ${AXIOM_TOKEN}`);
    assert((headers.get("content-type") ?? "").includes("application/json"));
    const body = JSON.parse(posts[0].init?.body as string);
    assert(Array.isArray(body));
    assertEquals(body.length, 1);
    assertEquals(body[0].event, "user_login");

    // captureError reaches the errors role (Sentry), never Axiom — no extra POST.
    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 1);
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "case 2: errors=sentry,logs=none → logEvent no POST; captureError no-throw",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        SENTRY_DSN,
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=sentry,logs=none",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "noop_log", severity: "info" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 0);
    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 0);
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "case 3: errors=none,logs=axiom → logEvent POSTs to Axiom; captureError no-ops cleanly",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "user_login", severity: "info" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 1);
    // captureError must not throw and must not reach Axiom.
    captureError(new Error("boom"), { event: "explode", severity: "error" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 1);
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "case 4: errors=none,logs=none → both no-op; no POST",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=none",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "x", severity: "info" });
    captureError(new Error("boom"), { event: "y", severity: "error" });
    await flushAsync();
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 0);
  } finally {
    c.restore();
  }
}});

// ─── Ingest URL override ─────────────────────────────────────────────────────

Deno.test({
  name: "AXIOM_INGEST_URL override is used when set",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  const override = "https://api.eu.axiom.co/v1/datasets/test-ds/ingest";
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        AXIOM_INGEST_URL: override,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "x", severity: "info" });
    await flushAsync();
    assert(fake.calls.map((c) => c.url).includes(override));
    assertEquals(fake.calls.filter((c) => c.url === DEFAULT_INGEST).length, 0);
  } finally {
    c.restore();
  }
}});

// ─── Never-throw egress ──────────────────────────────────────────────────────

Deno.test({
  name: "fake fetch REJECTS → logEvent does not throw, one rate-limited warn",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("reject");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "a", severity: "info" });
    logEvent({ event: "b", severity: "info" });
    logEvent({ event: "c", severity: "info" });
    await flushAsync();
    assertEquals(c.axiomWarns(), 1);
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "fake fetch returns non-2xx (500) → no throw, one warn",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("error500");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "a", severity: "info" });
    await flushAsync();
    assertEquals(c.axiomWarns(), 1);
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "isConfigured false (no AXIOM_TOKEN) → logEvent no POST, no throw",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    logEvent({ event: "a", severity: "info" });
    await flushAsync();
    assertEquals(fake.calls.length, 0);
  } finally {
    c.restore();
  }
}});

// ─── startSpan regression ────────────────────────────────────────────────────

Deno.test({
  name: "startSpan: valid span + idempotent end under SENTRY_DSN unset",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: () => {
  const c = withSilencedConsole();
  try {
    init(envWith({}));
    const span = startSpan("work", { k: "v" });
    assert(/^[0-9a-f]{32}$/.test(span.traceId));
    assert(/^[0-9a-f]{16}$/.test(span.spanId));
    span.end();
    span.end(); // idempotent — no throw
  } finally {
    c.restore();
  }
}});

Deno.test({
  name: "startSpan: valid span + idempotent end under errors=none,logs=axiom",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
  const fake = makeFakeFetch("ok");
  const c = withSilencedConsole();
  try {
    init(
      envWith({
        AXIOM_TOKEN,
        AXIOM_DATASET,
        OBS_DESTINATIONS: "errors=none,logs=axiom",
        __fetch: fake.fn,
      }),
    );
    const span = startSpan("work", { k: "v" });
    assert(/^[0-9a-f]{32}$/.test(span.traceId));
    assert(/^[0-9a-f]{16}$/.test(span.spanId));
    span.end();
    span.end();
    await flushAsync();
  } finally {
    c.restore();
  }
}});
