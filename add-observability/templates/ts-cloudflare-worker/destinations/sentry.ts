/**
 * Sentry destination adapter — AgenticApps spec §10.8.
 *
 * Phase 21 (P2.1). Lift-and-shift of the wrapper's inline `@sentry/cloudflare`
 * calls into a named `Destination` so the wrapper dispatches by ROLE rather
 * than knowing about any SDK. Behaviour is identical to the prior inline path:
 *
 *   - init             records whether a DSN is present (the `withSentry` wrap
 *                      at the entry-file site populates the hub; this adapter
 *                      only gates its own `Sentry.*` calls on the same signal)
 *                      plus the service/env used for scope tags, and the
 *                      waitUntil binding for fire-and-forget emission.
 *   - emit(envelope)   addBreadcrumb so the next captureException carries
 *                      context (skipped for debug severity, matching the old
 *                      wrapper's `severity !== "debug"` gate).
 *   - captureException withScope(setTag service/env/trace) + captureException.
 *
 * `@sentry/cloudflare` v8 removed `Sentry.init`; the canonical setup point is
 * `withSentry(optionsFactory, handler)` at the entry file. This adapter does
 * NOT call init — it mirrors the DSN-present signal so its capture/breadcrumb
 * calls are no-ops when Sentry is not wired.
 */

import * as Sentry from "@sentry/cloudflare";
import type { Envelope, Severity } from "../index";
import type { Destination, ExecutionContext, Role } from "./registry";

// Source of truth for supported roles lives in registry.ts; re-declared as the
// adapter's own `supportedRoles` value via the factory wiring there. Kept as a
// local literal here so the adapter is self-describing, matching the contract.
const SENTRY_ROLES: ReadonlyArray<Role> = ["errors", "logs"];

// Reserved attr keys the wrapper injects on the dispatched envelope so the
// adapter can reconstruct Sentry scope tags without importing the wrapper's
// AsyncLocalStorage. See lib-observability.ts `emit`/`dispatchEnvelope`.
const ATTR_SERVICE = "__service";
const ATTR_ENV = "__env";
const ATTR_TRACE_ID = "__trace_id";
const ATTR_SPAN_ID = "__span_id";

function sentryLevel(s: Severity): Sentry.SeverityLevel {
  return s === "warn" ? "warning" : (s as Sentry.SeverityLevel);
}

function attrString(attrs: Record<string, unknown> | undefined, key: string): string | undefined {
  const v = attrs?.[key];
  return typeof v === "string" ? v : undefined;
}

/**
 * Strip the wrapper-injected reserved keys from an attrs object so neither the
 * breadcrumb nor the capture context leaks them back into Sentry payloads.
 */
function publicAttrs(attrs: Record<string, unknown> | undefined): Record<string, unknown> {
  if (!attrs) return {};
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(attrs)) {
    if (k === ATTR_SERVICE || k === ATTR_ENV || k === ATTR_TRACE_ID || k === ATTR_SPAN_ID) continue;
    out[k] = v;
  }
  return out;
}

export function createSentryAdapter(): Destination {
  let dsnPresent = false;
  let waitUntilFn: ((p: Promise<unknown>) => void) | null = null;

  // observability MUST NOT throw into app code; mirror the wrapper's old
  // `safeFireAndForget` so Sentry SDK errors stay swallowed.
  const safeFireAndForget = (fn: () => void): void => {
    try {
      const p = Promise.resolve().then(fn).catch(() => {
        /* observability MUST NOT throw */
      });
      if (waitUntilFn) waitUntilFn(p);
    } catch {
      /* swallow */
    }
  };

  return {
    name: "sentry",
    supportedRoles: SENTRY_ROLES,

    isConfigured(env): boolean {
      return Boolean((env as Record<string, unknown>).SENTRY_DSN);
    },

    init(env, ctx?: ExecutionContext): void {
      dsnPresent = Boolean((env as Record<string, unknown>).SENTRY_DSN);
      try {
        waitUntilFn = ctx ? (p) => ctx.waitUntil(p) : null;
      } catch {
        waitUntilFn = null;
      }
    },

    emit(envelope: Envelope): void {
      // Breadcrumb so the next captureException carries this context. Matches
      // the old wrapper gate: only when a DSN is present and severity!=debug.
      const severity: Severity = envelope.severity ?? "info";
      if (!dsnPresent || severity === "debug") return;
      safeFireAndForget(() => {
        Sentry.addBreadcrumb({
          category: envelope.event,
          level: sentryLevel(severity),
          data: publicAttrs(envelope.attrs) as { [k: string]: unknown },
        });
      });
    },

    captureException(err: unknown, envelope: Envelope): void {
      // Identical to the prior inline path: only real Errors, only with a DSN.
      if (!dsnPresent || !(err instanceof Error)) return;
      const service = attrString(envelope.attrs, ATTR_SERVICE);
      const env = attrString(envelope.attrs, ATTR_ENV);
      const traceId = attrString(envelope.attrs, ATTR_TRACE_ID);
      const spanId = attrString(envelope.attrs, ATTR_SPAN_ID);
      safeFireAndForget(() => {
        Sentry.withScope((scope) => {
          scope.setTag("event", envelope.event);
          if (service) scope.setTag("service", service);
          if (env) scope.setTag("env", env);
          if (traceId) scope.setTag("trace_id", traceId);
          if (spanId) scope.setTag("span_id", spanId);
          const attrs = publicAttrs(envelope.attrs);
          if (Object.keys(attrs).length > 0) scope.setContext("attrs", attrs);
          Sentry.captureException(err);
        });
      });
    },
  };
}

// Reserved-key names exported so the wrapper injects exactly these. Keeping the
// constants in one module avoids drift between producer (wrapper) and consumer
// (this adapter).
export const SENTRY_RESERVED_ATTRS = {
  service: ATTR_SERVICE,
  env: ATTR_ENV,
  traceId: ATTR_TRACE_ID,
  spanId: ATTR_SPAN_ID,
} as const;
