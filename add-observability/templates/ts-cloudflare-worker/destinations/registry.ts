/**
 * Destination registry — AgenticApps spec §10.8 multi-destination materialisation.
 *
 * Phase 21 (P1). A role-based registry lets the wrapper route each
 * observability ROLE (errors / logs / analytics) to a named destination
 * adapter (sentry / axiom) without the wrapper knowing about any specific
 * SDK. The wrapper builds the registry once in `init` and dispatches
 * `logEvent` → forRole("logs").emit and `captureError` → forRole("errors").
 * captureException.
 *
 * SAFETY (review #5, codex HIGH): `resolveConfig` is FAIL-CLOSED. A hostile
 * or malformed OBS_DESTINATIONS override can only ever NARROW toward the
 * baked default — errors can NEVER be routed to the logs-only Axiom adapter.
 *
 * P1 ships lightweight stub adapters keyed by name so the registry contract
 * is testable now. P2 replaces the factory function bodies without touching
 * `resolveConfig`, `buildRegistry`, the `Destination` interface, or
 * `ADAPTER_SUPPORTED_ROLES`.
 */

import type { Envelope, InitEnv } from "../index";

// ExecutionContext is the Cloudflare Workers runtime type. Defined here
// compatibly (rather than imported) so the registry compiles standalone in
// the materialize-and-test harness, which has no @cloudflare/workers-types.
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
// Hardcoded here for P1; the generator rewrites this constant from the
// resolved --destinations role map. errors→sentry, logs→axiom, analytics→none.
const DESTINATIONS_CONFIG: DestinationsConfig = {
  errors: "sentry",
  logs: "axiom",
  analytics: "none",
};

const ROLES: ReadonlyArray<Role> = ["errors", "logs", "analytics"];
const DEST_NAMES: ReadonlyArray<DestName> = ["sentry", "axiom", "none"];

// ─── Supported roles (single source of truth) ───────────────────────────────
// Declared here — NOT inside factory functions — so the fail-closed resolver
// can read roles without constructing an adapter (P2 factories will do real
// SDK setup). Adapter factories reference this same constant so there is
// exactly one place to update when roles change.
const ADAPTER_SUPPORTED_ROLES: Record<"sentry" | "axiom", ReadonlyArray<Role>> = {
  sentry: ["errors", "logs"],
  // NOTE: NO "errors" for axiom — logs/analytics sink only. This is what
  // makes resolveConfig reject `errors=axiom`.
  axiom: ["logs", "analytics"],
};

// ─── Adapter factories (keyed by name) ──────────────────────────────────────
// P1 uses minimal stubs so the registry is testable. The supportedRoles
// reference ADAPTER_SUPPORTED_ROLES as the authoritative declaration the
// fail-closed resolver validates against: sentry⇒errors+logs,
// axiom⇒logs+analytics (NO errors). P2 swaps the factory bodies for real
// SDK adapters; the keys + ADAPTER_SUPPORTED_ROLES stay.

function createSentryAdapter(): Destination {
  return {
    name: "sentry",
    supportedRoles: ADAPTER_SUPPORTED_ROLES.sentry,
    isConfigured(env: InitEnv): boolean {
      return Boolean((env as Record<string, unknown>).SENTRY_DSN);
    },
    init(_env: InitEnv, _ctx?: ExecutionContext): void {
      /* P2: Sentry init (withSentry populates the hub at the entry site) */
    },
    emit(_envelope: Envelope): void {
      /* P2: Sentry breadcrumb / log */
    },
    captureException(_err: unknown, _envelope: Envelope): void {
      /* P2: Sentry.captureException with scoped context */
    },
  };
}

function createAxiomAdapter(): Destination {
  return {
    name: "axiom",
    supportedRoles: ADAPTER_SUPPORTED_ROLES.axiom,
    isConfigured(env: InitEnv): boolean {
      const e = env as Record<string, unknown>;
      return Boolean(e.AXIOM_TOKEN) && Boolean(e.AXIOM_DATASET);
    },
    init(_env: InitEnv, _ctx?: ExecutionContext): void {
      /* P2: cache token + dataset + ingest URL */
    },
    emit(_envelope: Envelope): void {
      /* P2: POST envelope to the Axiom ingest endpoint (fire-and-forget) */
    },
    captureException(_err: unknown, _envelope: Envelope): void {
      /* Axiom never captures errors — no-op by contract */
    },
  };
}

const ADAPTER_FACTORIES: Record<"sentry" | "axiom", () => Destination> = {
  sentry: createSentryAdapter,
  axiom: createAxiomAdapter,
};

// supportedRoles lookup used by the fail-closed resolver — reads from the
// module-level constant; no adapter instantiation required.
function supportedRolesFor(name: "sentry" | "axiom"): ReadonlyArray<Role> {
  return ADAPTER_SUPPORTED_ROLES[name];
}

// ─── buildRegistry ───────────────────────────────────────────────────────────

/**
 * Construct each named adapter referenced by `config` exactly once, call
 * `init()` on those that report `isConfigured(env)`, and map each role to its
 * named adapter (skipping "none"). `forRole(role)` returns the adapter ONLY
 * when it is configured — otherwise null (so an unconfigured destination
 * degrades to a no-op rather than a throw).
 */
export function buildRegistry(
  config: DestinationsConfig,
  env: InitEnv,
  ctx?: ExecutionContext,
): Registry {
  // Construct each distinct named adapter once; track only those that are
  // configured+initialised so all() never returns uninitialised adapters.
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

  // Map each role to its (configured) named adapter.
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
 * override is BOTH well-formed AND legal. The resolver is fail-closed:
 *
 *  - A dest is only accepted for a role if that adapter declares the role in
 *    its supportedRoles (sentry⇒errors+logs, axiom⇒logs+analytics). So
 *    `errors=axiom` is REJECTED, keeping the baked sentry default + warns.
 *  - Unknown role / unknown dest token → ignore + warn per rejected pair.
 *  - "none" is always a legal dest for any role (disables that role).
 *  - Malformed pair (no `=`, empty value) → ignore. Duplicate keys → last
 *    valid wins. Tokens are trimmed + lowercased before matching.
 *
 * Net guarantee: a malformed/hostile OBS_DESTINATIONS can only ever narrow
 * toward the safe baked default; errors can NEVER resolve to axiom.
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
    // "none" is always legal. A named adapter is only legal for the role if it
    // declares that role — this is the SAFETY gate that rejects errors=axiom.
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
