// Vanilla Hono Worker — NO instrumentation markers anywhere in this file.
// Fixture 13 (Phase 26 D-06a): asserts the engine's content-marker firewall
// (Plan 03 / Wave 3) skips index.ts files that lack any wrapper-identifier
// substring. KEEP THIS FILE FREE OF the strings the engine regex matches on;
// any of those strings would defeat the negative-case purpose.
import { Hono } from "hono";

const app = new Hono();
app.get("/", (c) => c.text("Hello World"));
app.get("/api/items", (c) => c.json({ items: [] }));

export default app;
