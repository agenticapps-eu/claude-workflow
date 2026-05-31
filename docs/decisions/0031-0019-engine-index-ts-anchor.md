# 0031 — 0019 engine accepts index.ts as canonical anchor

**Status**: Accepted  **Date**: 2026-05-31  **Phase**: 25-fix-0019-engine-and-cron-wrappers

## Context

Migration 0019's apply engine (`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`) discovered wrapper roots by looking for `lib-observability.ts` (cf-worker, cf-pages) or `observability.go` (go-fly-http) or `index.ts` scoped to `*/_shared/observability/` (supabase-edge). But `add-observability/templates/ts-cloudflare-worker/meta.yaml:target.wrapper_path` is `src/lib/observability/index.ts`, NOT `lib-observability.ts`. The template SOURCE file is named `lib-observability.ts`; the materialised TARGET file is `index.ts`. Same for cf-pages: `functions/_lib/observability/index.ts`. The engine never matched real materialised projects — only the test fixtures, which hand-seeded the SOURCE filename.

Issue #56 surfaced this when callbot (v1.16.0 → v1.19.0) attempted to apply migration 0019 and the engine reported "no wrappers found" with exit 0 — the engine considered the migration a no-op because `lib-observability.ts` did not exist in the project.

The existing 7 fixtures hand-seed `lib-observability.ts` (test-only divergence from production reality), which is why the bug shipped green. No real materialised project ever had `lib-observability.ts`; that filename exists only in the template source tree and in the test fixture sandbox.

## Decision

Engine accepts `index.ts` AND `lib-observability.ts` as anchor filenames for `ts-cloudflare-worker` and `ts-cloudflare-pages` stacks. `index.ts` is the canonical materialised filename (per `meta.yaml:target.wrapper_path`); `lib-observability.ts` continues to work as a legacy alias for fixture compatibility.

The `middleware.ts` (cf-worker) / `_middleware.ts` (cf-pages) co-anchor requirement remains — guards against unintended `index.ts` matches in unrelated directories (barrel files, utility modules, etc.).

Implementation: extend `find` candidate collection in `migrate-0019-sentry-crons-and-healthz.sh:224-226` to include `-name index.ts`, add classify branches at `:317-331` so cf-worker matches `(index.ts OR lib-observability.ts) + middleware.ts` and cf-pages matches `(index.ts OR lib-observability.ts) + _middleware.ts`, and add a `resolve_anchor_files()` helper that picks the actually-present anchor at fingerprint time.

**Codex M-2 follow-up:** a pre-classify dist-path negative filter ALSO drops `index.ts` candidates whose path matches `*/dist/*`, `*/build/*`, or `*/out/*` regardless of co-anchor presence. Typed compiled output can ship both `index.ts` + `middleware.ts` adjacent in these directories (e.g., esbuild/wrangler bundler output for monorepos with multiple Worker entries). Those are not legitimate wrappers. The filter is applied before classification, not after — so `classify_stack()` never sees `dist/`-shaped candidates, and `SKIP_UNSUPPORTED` noise is avoided.

The engine's content-hash canonicaliser is unchanged: both filenames hash to the same canonical fingerprint because they carry the same content.

## Alternatives Rejected

| Alternative | Reason Rejected |
|-------------|-----------------|
| **Rename template source files** (`lib-observability.ts` → `index.ts` in templates/) | Would break existing 7 fixtures that seed `lib-observability.ts` and require coordinated changes across template source, test fixtures, and potentially scaffolder code. Renaming introduces more surface change than the two-alias approach. The source/target naming split is also documentable: source file has a descriptive name; target follows the project's module convention. |
| **REFUSE on `index.ts`** (emit error + require manual rename) | Hostile to legitimate projects. Every project scaffolded since v1.16.0 uses `index.ts` as the materialised name (per `meta.yaml`). An engine that REFUSEs on the canonical production shape is broken-by-design. |
| **Hybrid alias-with-warning** (accept `index.ts` but log a deprecation warning to STDERR) | Noise with no benefit. `lib-observability.ts` is a fixture-only legacy artifact — there is nothing to deprecate from the consumer's perspective. A warning would confuse operators whose projects are correctly structured. |

## Consequences

- Engine now recognises any project scaffolded since v1.16.0 (canonical materialised path `src/lib/observability/index.ts`, `functions/_lib/observability/index.ts`). Pre-engine-fix workarounds (hand-applied 0019, manual recovery) no longer needed.
- Test fixtures gain coverage for `index.ts`-anchored wrappers (fixtures 08, 09) AND the dist-shaped negative case (fixture 12). Existing `lib-observability.ts`-seeded fixtures (01–07) continue to pass — both filenames classify as the same stack.
- The dist-path negative filter (codex M-2) adds defence-in-depth: `dist/` / `build/` / `out/` directories are excluded even when both `index.ts` + `middleware.ts` are present (typed compiled output that happens to share filenames). Fixtures 11 (stray index.ts, no co-anchor) and 12 (dist/server/ with both anchors) RED-lock the filter requirements.
- No spec change for consumers — the engine change is transparent. Existing `lib-observability.ts` projects and new `index.ts` projects are both valid inputs.
- Extends ADR-0028.
