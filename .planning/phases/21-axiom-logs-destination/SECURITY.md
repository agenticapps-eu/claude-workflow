# Phase 21 — Security Audit (CSO post-phase gate)

**Verdict: PASS-WITH-FINDINGS** — no HIGH/CRITICAL issues. Two LOW findings (advisory documentation hardening). The phase upholds every hard constraint: no ingest token is ever logged, written with a value, embedded in a build artifact, or placed in CLAUDE.md; redaction runs once before every egress path; the browser ships no token; `resolveConfig` is fail-closed; the migration is atomic on refuse and uses no `eval`/exec and no new runtime dependency.

Scope: full phase diff `main..HEAD` on `feat/axiom-logs-destination-v1.16.0` — the 5-stack `destinations/{registry,sentry,axiom}.{ts,go}` adapters, the wrappers' redact-before-dispatch logic, INIT.md, env-additions/policy docs, and migration 0017 (`templates/.claude/scripts/migrate-0017-axiom-destination.sh` + markdown + fixtures). This is scaffolder code shipped into downstream user projects, so findings are assessed for blast radius.

---

## Findings by severity

### CRITICAL
None.

### HIGH
None.

### MEDIUM
None.

### LOW

#### L1 — Refuse-path `.observability-0017.patch` may persist user wrapper diff (incl. hand-pasted secrets) on disk, ungitignored
- **File:** `templates/.claude/scripts/migrate-0017-axiom-destination.sh:349-356`; documented in `migrations/0017-add-axiom-logs-destination.md:114,193`
- **Description:** When a hand-modified wrapper is detected, the migration auto-generates `<module-root>/.observability-0017.patch` — a `diff -u` of the user's wrapper vs the known baseline. If a user has (against policy) pasted a literal secret into their wrapper, that secret is captured into the patch file. The patch is **local only** (never transmitted — confirmed: no network egress in the script), so the residual risk is limited to the file lingering in the working tree or being accidentally committed. The migration neither cleans it up nor adds it to `.gitignore`.
- **Recommendation (advisory, do not block):** Have the migration append `.observability-0017.patch` to the project `.gitignore` when it writes one, or print a one-line reminder to delete the patch after recovery. Residual risk is low because (a) the file is local, (b) the dominant secret-handling story (env stubs, no creds in wrappers) is otherwise clean, and (c) wrappers are not supposed to contain secrets in the first place.

#### L2 — Same-origin proxy example in react-vite env-additions has no body-size cap or auth (open log-relay shape)
- **File:** `add-observability/templates/ts-react-vite/env-additions.md:128-171`
- **Description:** The documented `/api/log` Hono/Express proxy forwards the client-supplied body verbatim to Axiom using the server-held `AXIOM_TOKEN`. As written it accepts unbounded, unauthenticated POSTs from any origin reaching the route, which is an abuse/cost-amplification vector (an attacker who can hit `/api/log` can drive Axiom ingest on the operator's token). This is **example documentation** the user copies and adapts, not shipped runtime code, and the design correctly keeps the token server-side (the actual security goal — no client token — is met).
- **Recommendation (advisory):** Add a one-line note to the proxy example recommending a body-size limit, same-origin/CSRF check, and basic rate-limiting on the proxy route. Not a blocker — the token-exfil hard rule is satisfied.

---

## Threat model — threats considered & cleared

1. **Secret handling (AXIOM_TOKEN / SENTRY_DSN) — CLEARED.**
   - The token is never logged: the rate-limited failure warn is the static string `"axiom: log delivery failing (N suppressed)"` — no token, no `Authorization` header (`destinations/axiom.ts:48`, `go-fly-http/destinations.go:428-430`). No `console.*`/`log.Printf`/`fmt.*` site references token/bearer/dsn (full grep, none).
   - The migration writes only env **stubs** with empty values: `printf 'AXIOM_TOKEN=\nAXIOM_DATASET=\n'` (`migrate-0017-axiom-destination.sh:413`) and a doc-table row showing the `xaat-...` placeholder — never a real secret.
   - CLAUDE.md `observability:` block written by both INIT and the migration contains only the role MAP + `spec_version` + policy/baseline paths (`migrate-0017-axiom-destination.sh:427-432,439-443,456`) — no credentials.
   - The token is held only in adapter closure state (`token` var), read from env at `init`, never serialized.

2. **Third-party data egress to api.axiom.co — CLEARED.**
   - Redaction is applied **once, centrally, before dispatch on every path.** The wrapper's internal `emit()` builds the enriched envelope from `redactObject(attrs)` (`lib-observability.ts:291,313-323`); both `logEvent` and `captureError` only ever hand adapters this already-redacted envelope (`:247-255,265-273`). The Axiom adapter receives no raw attrs. The Go path is equivalent: `axiomAdapter.Emit` calls `redactObject(env.Attrs)` before marshaling (`destinations.go:465`).
   - The `captureError → logs` path cannot leak un-redacted data: `captureError` routes only to `forRole("errors").captureException`; Axiom's `captureException` is a contractual no-op (`axiom.ts:126-128`, `destinations.go:499`). Spans route their end-event only to `forRole("errors")`, never the logs sink (`lib-observability.ts:230-233`).
   - Reserved keys `__service/__env/__trace_id/__span_id` (`SENTRY_RESERVED_ATTRS`, `sentry.ts:138-143`) carry only service name, deploy env, and W3C trace/span IDs — non-PII correlation metadata.
   - `AXIOM_INGEST_URL` override is operator-set env, not attacker-controlled; SSRF risk is the operator's own choice of egress host. Acceptable.

3. **Browser token exfiltration (ts-react-vite) — CLEARED (hard rule upheld).**
   - The browser Axiom adapter reads only `AXIOM_PROXY_URL` (mapped from `VITE_AXIOM_PROXY_URL`), never `VITE_AXIOM_TOKEN`/`VITE_AXIOM_DATASET` (`ts-react-vite/destinations/axiom.ts:64-82`; wrapper mapping `lib-observability.ts:156`). It POSTs to the same-origin proxy with **no** `Authorization` header (`:90,110-115`).
   - The static no-token test (`ts-react-vite/axiom.test.ts:110-128`) asserts the adapter source contains no `VITE_AXIOM_TOKEN`/`AXIOM_TOKEN`/`AXIOM_DATASET` and no `authorization`, and that absence of a proxy URL → console-only. No way for a token to enter the client bundle.

4. **OBS_DESTINATIONS injection / fail-closed — CLEARED.**
   - `resolveConfig` starts from the baked default and only applies overrides that are well-formed AND legal against `ADAPTER_SUPPORTED_ROLES` (`registry.ts:183-227`). `errors=axiom` is rejected because Axiom declares no `errors` role (`:76-81,216-221`). Unknown role/dest, malformed pairs, and empty values are dropped with a warn; net effect can only narrow toward the safe default. Go parser mirrors this (`destinations.go:148-186`). A hostile value can never route errors to the logs-only adapter.

5. **Migration 0017 (rewrites user repos) — CLEARED.**
   - (a) No path traversal: discovery uses `find` over the project tree filtered to canonical wrapper paths; all `cp`/`mkdir`/`diff`/`rm` operands are quoted (`:390-399`). `rm` is used only on `mktemp` temp files (`:276`), never `rm -rf` on user content. Rollback `rm -rf destinations/` lives in the markdown as operator guidance, not in the auto-run engine.
   - (b) The `.observability-0017.patch` residual is the only secret-adjacent artifact → see **L1** (LOW, local-only).
   - (c) No attacker-controllable execution: no `eval`, no `source`/`.` of project files (grep clean); the only dynamic awk is the static `canonicalize_awk` heredoc, fed the user's wrapper as data, not code. Go side has no `os/exec`.
   - (d) Writes-nothing-on-refuse holds from a security angle: the all-clean gate classifies all roots before any write and exits 2 with zero writes in default mode (`:320-376`); fail-closed — an unrecognised wrapper shape canonicalizes to a non-matching hash and is treated as hand-modified (refuse), never silently overwritten.

6. **Supply chain — CLEARED.** No new runtime dependency. Adapters use native `fetch`/`navigator.sendBeacon` (TS) and stdlib `net/http` (Go). No `@axiomhq`/`axiom-*` SDK import anywhere (grep clean). react-vite still depends only on the pre-existing `@sentry/react`.

7. **Injection in the engine bash — CLEARED.** `set -uo pipefail`; all variable expansions in `cp`/`diff`/`mkdir`/`grep`/`sha256_of` are double-quoted; no `eval`; jq is invoked with `--arg` (no shell interpolation of the hashes file). Paths originate from the operator's own checkout (`find` output), not an external untrusted source.

---

## Notes
- This is a logs-shipping feature plus a repo-rewriting migration, not an auth system; findings are scoped accordingly. The two LOW items are documentation/cleanup hardening, not exploitable defects in shipped runtime code.
- No code was modified during this audit.
