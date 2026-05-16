const handler = async (req: Request): Promise<Response> => {
  const url = new URL(req.url);
  return new Response(JSON.stringify({ ok: true, path: url.pathname }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};

Deno.serve(handler);
