interface Env {
  DEPLOY_ENV: string;
}

export default {
  fetch: async (request: Request, env: Env, ctx: ExecutionContext): Promise<Response> => {
    return new Response("ok", { status: 200 });
  },
  scheduled: async (event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> => {
    console.log(`cron fired: ${event.cron}`);
  },
} satisfies ExportedHandler<Env>;
