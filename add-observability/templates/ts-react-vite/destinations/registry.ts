/**
 * Destination registry — AgenticApps spec §10.8 multi-destination materialisation.
 *
 * Phase 21 (P1, ts-react-vite / browser). A role-based registry lets the
 * wrapper route each observability ROLE (errors / logs / analytics) to a named
 * destination adapter (sentry / axiom) without the wrapper knowing about any
 * specific SDK. The wrapper builds the registry once in `init` and dispatches
 * `logEvent` → forRole("logs").emit and `captureError` → forRole("errors").
 * captureException.
 *
 * SAFETY: `resolveConfig` is FAIL-CLOSED. A hostile or malformed
 * OBS_DESTINATIONS override can only ever NARROW toward the baked default —
 * errors can NEVER be routed to the logs-only Axiom adapter.
 *
 * BROWSER NOTES: there is no Cloudflare `ExecutionContext`. The registry keeps
 * the `init(env, ctx?)` shape for cross-stack portability, but ctx is always
 * undefined here. Env is assembled by the wrapper from `import.meta.env`
 * (VITE_-prefixed vars only) plus an optional test override. CRITICAL: the
 * Axiom adapter NEVER reads an ingest token in the browser — see axiom.ts.
 */

import type { Envelope, InitEnv } from "../index";
import { createSentryAdapter } from "./sentry";
import { createAxiomAdapter } from "./axiom";

// Cloudflare-compatible shape, kept for cross-stack registry portability.
// Unused at runtime in the browser (ctx is always undefined here).
export interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// ─── Public types ──────────────────────────────────────────────────────────

export type Role = "errors" | "logs" | "analytics";
export type DestName = "sentry" | "axiom" | "none";

export interface Destination {
  name: "sentry" | "axiom";
  supportedRoles: ReadonlyArray<Role>;
  isConfigured(env: InitEnv): boolean;
  init(env: InitEnv, ctx?: ExecutionContext): void;
  emit(envelope: Envelope): void;
  captureException(err: unknown, envelope: Envelope): void;
  flush?(timeoutMs: number): Promise<boolean>;
}

export interface DestinationsConfig {
  errors: DestName;
  logs: DestName;
  analytics: DestName;
}

export interface Registry {
  forRole(role: Role): Destination | null;
  all(): Destination[];
}

// ─── Baked default (substituted at init-time by the generator in P4) ────────
const DESTINATIONS_CONFIG: DestinationsConfig = {
  errors: "sentry",
  logs: "axiom",
  analytics: "none",
};

const ROLES: ReadonlyArray<Role> = ["errors", "logs", "analytics"];
const DEST_NAMES: ReadonlyArray<DestName> = ["sentry", "axiom", "none"];

// ─── Supported roles (single source of truth) ───────────────────────────────
const ADAPTER_SUPPORTED_ROLES: Record<"sentry" | "axiom", ReadonlyArray<Role>> = {
  sentry: ["errors", "logs"],
  // NOTE: NO "errors" for axiom — logs/analytics sink only. This is what
  // makes resolveConfig reject `errors=axiom`.
  axiom: ["logs", "analytics"],
};

// ─── Adapter factories (keyed by name) ──────────────────────────────────────
const ADAPTER_FACTORIES: Record<"sentry" | "axiom", () => Destination> = {
  sentry: createSentryAdapter,
  axiom: createAxiomAdapter,
};

function supportedRolesFor(name: "sentry" | "axiom"): ReadonlyArray<Role> {
  return ADAPTER_SUPPORTED_ROLES[name];
}

// ─── buildRegistry ───────────────────────────────────────────────────────────

export function buildRegistry(
  config: DestinationsConfig,
  env: InitEnv,
  ctx?: ExecutionContext,
): Registry {
  const adapters = new Map<"sentry" | "axiom", Destination>();
  const configuredAdapters = new Map<"sentry" | "axiom", Destination>();

  const ensureAdapter = (name: "sentry" | "axiom"): Destination => {
    let a = adapters.get(name);
    if (!a) {
      a = ADAPTER_FACTORIES[name]();
      adapters.set(name, a);
      if (a.isConfigured(env)) {
        a.init(env, ctx);
        configuredAdapters.set(name, a);
      }
    }
    return a;
  };

  const roleMap = new Map<Role, Destination | null>();
  for (const role of ROLES) {
    const dest = config[role];
    if (dest === "none") {
      roleMap.set(role, null);
      continue;
    }
    const adapter = ensureAdapter(dest);
    roleMap.set(role, configuredAdapters.has(dest) ? adapter : null);
  }

  return {
    forRole(role: Role): Destination | null {
      return roleMap.get(role) ?? null;
    },
    all(): Destination[] {
      return Array.from(configuredAdapters.values());
    },
  };
}

// ─── resolveConfig (FAIL-CLOSED) ─────────────────────────────────────────────

function isRole(token: string): token is Role {
  return (ROLES as ReadonlyArray<string>).includes(token);
}

function isDestName(token: string): token is DestName {
  return (DEST_NAMES as ReadonlyArray<string>).includes(token);
}

/**
 * Resolve the effective {errors, logs, analytics} → destination map.
 *
 * Starts from the baked DESTINATIONS_CONFIG and applies the OBS_DESTINATIONS
 * env override (format `errors=sentry,logs=axiom`) ON TOP — but only where the
 * override is BOTH well-formed AND legal. Net guarantee: a malformed/hostile
 * OBS_DESTINATIONS can only ever narrow toward the safe baked default; errors
 * can NEVER resolve to axiom.
 */
export function resolveConfig(env: InitEnv): DestinationsConfig {
  const resolved: DestinationsConfig = { ...DESTINATIONS_CONFIG };

  const raw = (env as Record<string, unknown>).OBS_DESTINATIONS;
  if (typeof raw !== "string" || raw.trim() === "") return resolved;

  const warnPair = (msg: string): void => {
    console.warn(`obs: OBS_DESTINATIONS ${msg}; falling back to baked default for this key`);
  };

  for (const pair of raw.split(",")) {
    const eq = pair.indexOf("=");
    if (eq === -1) {
      warnPair(`ignored malformed pair "${pair.trim()}"`);
      continue;
    }
    const roleToken = pair.slice(0, eq).trim().toLowerCase();
    const destToken = pair.slice(eq + 1).trim().toLowerCase();

    if (roleToken === "" || destToken === "") {
      warnPair(`ignored empty key/value in "${pair.trim()}"`);
      continue;
    }
    if (!isRole(roleToken)) {
      warnPair(`ignored unknown role "${roleToken}"`);
      continue;
    }
    if (!isDestName(destToken)) {
      warnPair(`ignored unknown destination "${destToken}"`);
      continue;
    }
    if (destToken !== "none") {
      const roles = supportedRolesFor(destToken);
      if (!roles.includes(roleToken)) {
        warnPair(`rejected unsupported mapping "${roleToken}=${destToken}" (adapter does not serve that role)`);
        continue;
      }
    }
    resolved[roleToken] = destToken;
  }

  return resolved;
}
