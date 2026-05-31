// Local ambient declarations for the migrated-wrapper typecheck (codex H-2).
// Avoids the @cloudflare/workers-types dependency. Shapes mirror the relevant
// surface only — enough for withCronMonitor + withQueueMonitor to compile.

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
}

export {};
