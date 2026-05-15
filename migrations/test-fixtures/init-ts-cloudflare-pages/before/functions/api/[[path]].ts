interface Env {
  DEPLOY_ENV: string;
}

export const onRequest: PagesFunction<Env> = async (context) => {
  return new Response("ok", { status: 200 });
};

export const onRequestPost: PagesFunction<Env> = async (context) => {
  const body = await context.request.text();
  return new Response(`echo: ${body}`, { status: 200 });
};
