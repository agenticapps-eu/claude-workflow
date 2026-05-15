// agenticapps:observability:start
import { withObservability, withObservabilityScheduled } from "./lib/observability";
// agenticapps:observability:end

interface Env {
  DEPLOY_ENV: string;
}

// agenticapps:observability:start
export default {
  fetch: withObservability(async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
    return new Response("ok", { status: 200 });
  }),
  scheduled: withObservabilityScheduled(async (event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> => {
    console.log(`cron fired: ${event.cron}`);
  }),
} satisfies ExportedHandler<Env>;
// agenticapps:observability:end
