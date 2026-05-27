/**
 * Contract tests for the destination registry + fail-closed config resolution.
 *
 * Phase 21 (P1.1). These tests verify the role-based registry that lets the
 * wrapper route LOGS to Axiom and ERRORS to Sentry without changing the
 * wrapper's public interface. The critical safety property is that a hostile
 * or malformed OBS_DESTINATIONS override can only ever narrow toward the safe
 * baked default — errors can NEVER resolve to the logs-only Axiom adapter.
 *
 * Test runner: vitest (matches the wrapper contract suite).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  buildRegistry,
  resolveConfig,
  type DestinationsConfig,
  type InitEnv,
} from "./registry";

// A minimal InitEnv with both Sentry + Axiom configured so adapters report
// isConfigured()===true and forRole returns them.
function configuredEnv(extra: Partial<InitEnv> = {}): InitEnv {
  return {
    SENTRY_DSN: "https://key@org.ingest.sentry.io/123",
    AXIOM_TOKEN: "xaat-test",
    AXIOM_DATASET: "test-ds",
    ...extra,
  } as InitEnv;
}

describe("buildRegistry — role → adapter mapping", () => {
  it("default config maps logs→axiom and errors→sentry", () => {
    const config: DestinationsConfig = { errors: "sentry", logs: "axiom", analytics: "none" };
    const reg = buildRegistry(config, configuredEnv());
    expect(reg.forRole("logs")?.name).toBe("axiom");
    expect(reg.forRole("errors")?.name).toBe("sentry");
  });

  it("analytics:none → forRole('analytics') is null", () => {
    const config: DestinationsConfig = { errors: "sentry", logs: "axiom", analytics: "none" };
    const reg = buildRegistry(config, configuredEnv());
    expect(reg.forRole("analytics")).toBeNull();
  });

  it("errors:none baked → forRole('errors') is null", () => {
    const config: DestinationsConfig = { errors: "none", logs: "axiom", analytics: "none" };
    const reg = buildRegistry(config, configuredEnv());
    expect(reg.forRole("errors")).toBeNull();
    // logs still resolves
    expect(reg.forRole("logs")?.name).toBe("axiom");
  });

  it("forRole returns null when the named adapter is not configured", () => {
    const config: DestinationsConfig = { errors: "sentry", logs: "axiom", analytics: "none" };
    // Axiom env unset → axiom adapter not configured → logs role yields null.
    const reg = buildRegistry(config, configuredEnv({ AXIOM_TOKEN: undefined, AXIOM_DATASET: undefined }));
    expect(reg.forRole("logs")).toBeNull();
    expect(reg.forRole("errors")?.name).toBe("sentry");
  });

  it("all() returns the constructed adapters", () => {
    const config: DestinationsConfig = { errors: "sentry", logs: "axiom", analytics: "none" };
    const reg = buildRegistry(config, configuredEnv());
    const names = reg.all().map((d) => d.name).sort();
    expect(names).toContain("sentry");
    expect(names).toContain("axiom");
  });

  it("all() returns only configured adapters — axiom unconfigured is excluded", () => {
    // errors=sentry (configured via SENTRY_DSN), logs=axiom but AXIOM_TOKEN/AXIOM_DATASET unset.
    // all() must return only [sentry]; forRole("logs") must be null.
    const config: DestinationsConfig = { errors: "sentry", logs: "axiom", analytics: "none" };
    const env = configuredEnv({ AXIOM_TOKEN: undefined, AXIOM_DATASET: undefined });
    const reg = buildRegistry(config, env);
    const all = reg.all();
    expect(all).toHaveLength(1);
    expect(all[0].name).toBe("sentry");
    expect(reg.forRole("logs")).toBeNull();
  });
});

describe("resolveConfig — fail-closed override resolution", () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
  });
  afterEach(() => {
    warnSpy.mockRestore();
  });

  it("no override → baked default {errors:sentry, logs:axiom, analytics:none}", () => {
    const cfg = resolveConfig(configuredEnv());
    expect(cfg).toEqual({ errors: "sentry", logs: "axiom", analytics: "none" });
  });

  it("SAFETY: OBS_DESTINATIONS='errors=axiom' is REJECTED — errors stays sentry, NOT axiom", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "errors=axiom" } as Partial<InitEnv>));
    expect(cfg.errors).toBe("sentry");
    expect(cfg.errors).not.toBe("axiom");
  });

  it("unknown dest token 'errors=bogus' → errors stays default sentry", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "errors=bogus" } as Partial<InitEnv>));
    expect(cfg.errors).toBe("sentry");
  });

  it("malformed pair with no '=' ('errorssentry') → ignored, defaults hold", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "errorssentry" } as Partial<InitEnv>));
    expect(cfg).toEqual({ errors: "sentry", logs: "axiom", analytics: "none" });
  });

  it("duplicate keys 'logs=axiom,logs=none' → last valid wins (logs=none)", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "logs=axiom,logs=none" } as Partial<InitEnv>));
    expect(cfg.logs).toBe("none");
  });

  it("valid override 'logs=none' applies", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "logs=none" } as Partial<InitEnv>));
    expect(cfg.logs).toBe("none");
    expect(cfg.errors).toBe("sentry");
  });

  it("trims + lowercases tokens before matching", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: " LOGS = NONE " } as Partial<InitEnv>));
    expect(cfg.logs).toBe("none");
  });

  it("unknown role token is ignored", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "bogusrole=sentry" } as Partial<InitEnv>));
    expect(cfg).toEqual({ errors: "sentry", logs: "axiom", analytics: "none" });
  });

  it("empty value 'logs=' is ignored", () => {
    const cfg = resolveConfig(configuredEnv({ OBS_DESTINATIONS: "logs=" } as Partial<InitEnv>));
    expect(cfg.logs).toBe("axiom");
  });
});
