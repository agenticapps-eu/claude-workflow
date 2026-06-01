// Vanilla Hono middleware co-anchor — NO instrumentation markers in this file.
// The engine's existing co-anchor filter accepts (a) sibling middleware.ts
// exists and (b) path is not /dist/ — both pass for this pair. Only the new
// content-marker check (D-06, Plan 03) will reject the pair, by inspecting
// index.ts (NOT this file) for the wrapper-identifier regex.
import type { Context, MiddlewareHandler } from "hono";

export const auth: MiddlewareHandler = async (_c: Context, next) => {
  await next();
};
