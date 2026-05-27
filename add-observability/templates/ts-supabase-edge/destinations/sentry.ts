/**
 * Sentry destination adapter — AgenticApps spec §10.8 (supabase-edge / Deno).
 *
 * Phase 21 (P2.1). Lift-and-shift of the wrapper's inline `@sentry/deno` calls
 * into a named `Destination` so the wrapper dispatches by ROLE rather than
 * knowing about any SDK. Behaviour is identical to the prior inline path:
 *
 *   - init             calls `Sentry.init({ dsn, ... })` when a DSN is present
 *                      (Deno SDK keeps the classic `Sentry.init` setup point,
 *                      unlike `@sentry/cloudflare` v8's `withSentry`), and
 *                      records the service/env used for scope tags.
 *   - emit(envelope)   addBreadcrumb so the next captureException carries
 *                      context (skipped for debug severity).
 *   - captureException withScope(setTag service/env/trace) + captureException.
 *   - flush(timeoutMs) drains Sentry's buffer before isolate teardown (Edge
 *                      Functions have no waitUntil for errors; the middleware
 *                      awaits this).
 */

import * as Sentry from "npm:@sentry/deno@^8.0.0";
import type { Envelope, Severity } from "../index.ts";
import type { Destination, ExecutionContext, Role } from "./registry.ts";

const SENTRY_ROLES: ReadonlyArray<Role> = ["errors", "logs"];

const TRACE_SAMPLE_RATE = {{TRACE_SAMPLE_RATE}};

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

  // observability MUST NOT throw into app code.
  const safeFireAndForget = (fn: () => void): void => {
    try {
      Promise.resolve().then(fn).catch(() => {
        /* observability MUST NOT throw */
      });
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

    init(env, _ctx?: ExecutionContext): void {
      const e = env as Record<string, unknown>;
      const dsn = typeof e.SENTRY_DSN === "string" ? e.SENTRY_DSN : "";
      dsnPresent = Boolean(dsn);
      const deployEnv = typeof e.DEPLOY_ENV === "string" ? e.DEPLOY_ENV : "dev";
      const service = typeof e.SERVICE_NAME === "string" ? e.SERVICE_NAME : undefined;
      if (dsnPresent) {
        try {
          Sentry.init({
            dsn,
            environment: deployEnv,
            release: service,
            tracesSampleRate: TRACE_SAMPLE_RATE,
            sendDefaultPii: false,
          });
        } catch {
          /* observability MUST NOT throw */
        }
      }
    },

    emit(envelope: Envelope): void {
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

    async flush(timeoutMs: number): Promise<boolean> {
      if (!dsnPresent) return true;
      try {
        return await Sentry.flush(timeoutMs);
      } catch {
        return false;
      }
    },
  };
}

// Reserved-key names exported so the wrapper injects exactly these.
export const SENTRY_RESERVED_ATTRS = {
  service: ATTR_SERVICE,
  env: ATTR_ENV,
  traceId: ATTR_TRACE_ID,
  spanId: ATTR_SPAN_ID,
} as const;
