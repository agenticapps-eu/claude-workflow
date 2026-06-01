// Local ambient declarations for the migrated-wrapper typecheck (codex H-2).
// Avoids the @cloudflare/workers-types and @sentry/cloudflare dependencies.
// Shapes mirror the relevant surface only — enough for withCronMonitor +
// withQueueMonitor to compile without a full project install.

// Ambient module for @sentry/cloudflare — provides withMonitor signature
// used by cron-monitor.ts and queue-monitor.ts.
declare module "@sentry/cloudflare" {
  export interface MonitorConfig {
    schedule?: {
      type: string;
      value?: string | number;
      unit?: string;
    };
    checkinMargin?: number;
    maxRuntime?: number;
    timezone?: string;
  }
  export function withMonitor<T>(
    monitorSlug: string,
    callback: () => T,
    upsertMonitorConfig?: MonitorConfig,
  ): T;
  export function captureException(error: unknown): string;
}

declare global {
  // Sentry Crons handler param shape (minimal).
  interface ScheduledController {
    readonly cron: string;
    readonly scheduledTime: number;
  }

  // Cloudflare Workers execution context (minimal).
  interface ExecutionContext {
    waitUntil(promise: Promise<unknown>): void;
    passThroughOnException(): void;
  }

  // Cloudflare Queue MessageBatch (minimal).
  interface Message<Body = unknown> {
    readonly id: string;
    readonly timestamp: Date;
    readonly body: Body;
    readonly attempts: number;
    ack(): void;
    retry(): void;
  }

  interface MessageBatch<Body = unknown> {
    readonly queue: string;
    readonly messages: readonly Message<Body>[];
    retryAll(): void;
    ackAll(): void;
  }

  // console — provided by ES2015+ lib but not included in strict ES2022-only
  // (workers runtimes provide console; declare minimal surface for typecheck).
  // Canonical pattern: `interface Console` + `declare var console: Console`
  // (Phase 26 D-07a / CR-E — `declare const` inside `declare global` is TS1038).
  interface Console {
    log(...args: unknown[]): void;
    warn(...args: unknown[]): void;
    error(...args: unknown[]): void;
  }
  declare var console: Console;
}

export {};
