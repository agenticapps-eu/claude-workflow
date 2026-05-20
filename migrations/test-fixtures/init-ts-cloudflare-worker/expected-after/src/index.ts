// agenticapps:observability:start
import { withSentry } from "@sentry/cloudflare";
import { withObservability, withObservabilityScheduled } from "./lib/observability";
// agenticapps:observability:end

interface Env {
  DEPLOY_ENV: string;
}

// agenticapps:observability:start
export default withSentry(
  (env) => ({
    dsn: env.SENTRY_DSN,
    environment: env.DEPLOY_ENV,
    release: env.SERVICE_NAME,
    tracesSampleRate: 0.1,
    sendDefaultPii: false,
  }),
  {
    fetch: withObservability(async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
      return new Response("ok", { status: 200 });
    }),
    scheduled: withObservabilityScheduled(async (controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> => {
      console.log(`cron fired: ${controller.cron}`);
    }),
  } satisfies ExportedHandler<Env>,
);
// agenticapps:observability:end
