// agenticapps:observability:start
import { withObservability } from "../_shared/observability/middleware.ts";
// agenticapps:observability:end

const handler = async (req: Request): Promise<Response> => {
  const url = new URL(req.url);
  return new Response(JSON.stringify({ ok: true, path: url.pathname }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};

// agenticapps:observability:start
Deno.serve(withObservability(handler));
// agenticapps:observability:end
