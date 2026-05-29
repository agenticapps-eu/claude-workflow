# Phase 22 — Security Review

**Reviewer:** /cso security
**Date:** 2026-05-29
**Branch:** `feat/sentry-crons-healthz-v1.18.0`
**Commits reviewed:** 29 (`main..HEAD`)

---

## Executive summary

Phase 22 introduces three threat surfaces — the `withCronMonitor` Sentry
heartbeat wrappers (4 stacks), the copy-only `healthz-snippet.{ts,go}`
templates (4 stacks), and the bash apply engine for migration 0019. All
three were authored with security-aware patterns already in place:
no DSN is ever logged, every SDK boundary call is try/swallow-wrapped,
the migration engine canonicalizes paths via `pwd -P` and reuses 0017's
hardened content-hash gate, and the operator runbook (`Part 4`) ships
explicit info-disclosure mitigations.

The only threats with non-trivial residual risk are documented info-
disclosure trade-offs that are **intentional for local-dev** and
**documented for production hardening** (S3 healthz topology leak, S4
probe-timing oracle, S10 unrate-limited probes). None block PR.

Two MEDIUM-severity findings are recommendations rather than defects:
adding probe timeouts (S4) and a SIGTERM trap in the migration engine
(S6). One LOW-severity recommendation: tightening the SENTRY_DEBUG
operational guidance (S9).

**No HIGH-severity findings. Verdict: PASS WITH HARDENING.**

---

## Threat model

### S1 — Sentry DSN handling

**Threat:** A wrapper that logged the DSN (even at debug level) would
leak the ingest credential into stdout/stderr/log-aggregation pipelines
where it could be exfiltrated. Sentry DSNs are project-scoped write
credentials.

**Mitigation in code:**
- `add-observability/templates/ts-cloudflare-worker/cron-monitor.ts:46-48`
  (`isConfigured` reads `env.SENTRY_DSN` but only tests `length > 0`).
- `add-observability/templates/ts-cloudflare-pages/cron-monitor.ts:46-48`
  (same shape).
- `add-observability/templates/ts-supabase-edge/cron-monitor.ts:95-98`
  (`isConfigured` calls `denoEnv("SENTRY_DSN")`, tests length only).
- `add-observability/templates/go-fly-http/cron_monitor.go:130-132`
  (`cronIsConfigured` reads `os.Getenv("SENTRY_DSN")`, tests `!= ""`).
- `debugLog` / `debugLogFn` functions never receive the DSN value — they
  receive a literal message + the SDK Error object only
  (`cron-monitor.ts:107-112` worker, `cron_monitor.go:118-124` go).

DSN never appears in any `console.error` / `fmt.Fprintf` argument list,
including under `SENTRY_DEBUG=1`. Verified by grepping each wrapper for
`SENTRY_DSN` — every occurrence is a read-and-test, never a print.

**Residual risk:** LOW (none — DSN is read-only and never reaches an
output sink).

**Recommendation:** None.

---

### S2 — Env-var injection on slug resolution

**Threat:** Operator-supplied env vars (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>`,
`SERVICE_NAME`) flow into the resolved `monitorSlug` string. If an attacker
controls the deployment env (e.g. compromised CI secrets), could they:
1. inject newlines / control characters into the slug to corrupt log lines
   or terminal escape sequences in the operator's `grep`?
2. interpolate the slug into a shell command or URL un-escaped?

**Mitigation in code:**
- The slug is constructed by **string concatenation only** and passed to
  Sentry's `captureCheckIn({ monitorSlug, status })` as an object-literal
  field (`cron-monitor.ts:151-156` worker; analogous in pages, supabase-edge,
  and go-fly-http via `*sentry.CheckIn{MonitorSlug: slug, ...}`).
- Sentry SDKs serialize check-ins via JSON envelope; control characters
  would be JSON-escaped at the SDK boundary, not interpolated raw.
- The slug NEVER reaches a shell command, URL path, URL query, HTML, or
  log line. `debugLog` is called with a **literal message string** + the
  caught `Error` only — the slug is not in the message string
  (`cron-monitor.ts:158, 168, 176` worker; analogous elsewhere).
- The runbook's grep command (`uptime-setup-runbook.md:56-60`) shells out
  with `grep -rn "withCronMonitor" ... .` — the search literal is hard-
  coded, not the slug; matched lines are surfaced as `grep` output, which
  is the operator's terminal, not a sink that re-executes content.

**Residual risk:** LOW.

- Practical exploitability requires control of the deployment env, at
  which point the attacker already has the DSN and many other secrets.
- A maliciously-crafted slug ending with `\x1b[2J\x1b[H` (terminal clear)
  could in principle appear in `grep` output **inside the Sentry UI** —
  but the Sentry UI sanitizes display; and a terminal-injecting slug
  shows up as a Sentry monitor name, immediately visible.
- No shell/URL interpolation path was found.

**Recommendation:** Defer. A future hardening could add a regex validator
(`/^[A-Za-z0-9_:-]{1,128}$/`) on the resolved slug with a debug-log on
mismatch, but the cost-benefit at this surface is poor.

---

### S3 — Healthz info disclosure (per-check breakdown)

**Threat:** Default healthz response exposes internal dependency names
(`kv`, `serviceBinding`, `db`, `supabase`, `upstream`) and their live
state. An external attacker probing `/healthz` learns:
1. which datastores / downstreams the service depends on;
2. through time-series sampling, which deps are flaky;
3. attack surface for amplification (a flaky upstream is a soft target).

**Mitigation in code:**
- Each `healthz-snippet.{ts,go}` ships with a **WARNING ASCII-banner**
  at the top that explicitly calls out the topology leak and points to
  the runbook for hardening:
  - `ts-cloudflare-worker/healthz-snippet.ts:1-16` (WARNING block,
    item 3 explicitly mentions SECURITY + `?detail=true` opt-in).
  - `ts-cloudflare-pages/healthz-snippet.ts:1-16`.
  - `ts-supabase-edge/healthz-snippet.ts:1-18`.
  - `go-fly-http/healthz_snippet.go:1-14`.
- Runbook Part 4 (`add-observability/uptime-setup-runbook.md:311-446`)
  is a 135-line dedicated SECURITY section with three concrete
  mitigations:
  - Mitigation 1: `?detail=true` gate, full TS code example (line 347).
  - Mitigation 2: `/healthz` (shallow) vs `/readyz` (deep) split per
    CONTEXT N7 (line 400).
  - Mitigation 3: Sentry Uptime Bearer-token auth-gating with key-
    rotation guidance and "don't reuse user session tokens" caveat
    (line 423).

**Residual risk:** LOW — by-design, scoped to local-dev default.
Production hardening is documented in the runbook (R10 binding); the
WARNING block ensures any developer who opens the file sees the caveat.

The default-on per-check return is **deliberate** per CONTEXT D4
(`/healthz` not wrapped, optimised for ops debug clarity) and runbook
Part 4 (info-disclosure trade-off + opt-in gating). This was raised in
the multi-AI plan review (R10 binding) and resolved by the runbook
addition.

**Recommendation:** Defer. Consider in a future minor: shipping the
`?detail=true` gate as the **default** snippet and requiring explicit
opt-OUT for unrestricted output; this inverts the current default in
the operator's favor at the cost of a slightly-more-painful local-dev
experience.

---

### S4 — Healthz timing oracle

**Threat:** Per-probe handlers run sequentially (`await` /
synchronous-in-Go). Response time of `/healthz` therefore leaks the
slowest dep probe's latency. An attacker timing healthz at intervals can:
1. fingerprint which deps are configured (presence of a probe adds
   that probe's RTT to response time);
2. detect dependency-state transitions (DB slow → DB ping spike);
3. correlate with degraded-mode behaviour windows.

**Mitigation in code:**
- **None** — the snippets do not impose a max probe duration.
- `ts-cloudflare-worker/healthz-snippet.ts:81-129` — sequential awaits,
  no `Promise.race` against a timeout, no `AbortSignal`.
- `ts-cloudflare-pages/healthz-snippet.ts:89-135` — same shape.
- `ts-supabase-edge/healthz-snippet.ts:91-131` — same shape.
- `go-fly-http/healthz_snippet.go:88-147` — passes `r.Context()` to
  `PingContext` (so a client-side cancel propagates), but no
  `context.WithTimeout`.
- Runbook Part 2 Step 2 recommends a `timeout: 10 seconds` on the Sentry
  Uptime probe (`uptime-setup-runbook.md:232`), but that bounds the
  **prober's** wait, not the **handler's** per-probe execution.

**Residual risk:** MEDIUM.

- Practical exploitability is moderate: timing oracles against
  `/healthz` are a well-known fingerprinting technique. The probe-name
  set is already disclosed in S3 (so the timing signal is mostly
  redundant), but timing also reveals dep-state transitions that the
  status flag would not.
- Risk is mitigated by Mitigation 3 in Part 4 (auth-gating reduces who
  can probe), but unauthenticated public `/healthz` is the default.

**Recommendation:** SHOULD-FIX in a follow-up phase (not blocking PR).
Two concrete options:
1. Add a per-probe `AbortSignal.timeout(probeTimeoutMs)` (TS) /
   `context.WithTimeout(ctx, probeTimeout)` (Go) with default 2 s.
   Probes that time out are recorded as `false`. Bounds worst-case
   response time + masks dependency-latency signal.
2. Add a top-level `Promise.race` against `Promise.all(probes)` with a
   5 s overall budget.

Document the new pattern in the snippet header WARNING block.

---

### S5 — Migration engine path traversal / write-outside-project

**Threat:** The apply engine takes `--project-dir` and writes new files
into wrapper-directory paths discovered by `find`. If a project tree
contains symlinks pointing outside the project (a malicious
`functions/_lib/observability` → `/etc/`), could the engine be tricked
into writing to a system path?

**Mitigation in code:**
- `templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh:139-141`
  canonicalizes `TEMPLATES_DIR` via `pwd -P` (real-path, follows
  symlinks once).
- Each discovered wrapper directory is canonicalized via `pwd -P` at
  lines 148, 187 — so a symlink directory resolves to its real path
  BEFORE being added to `ROOTS`. Subsequent `cp $cm "$dir_abs/cron-
  monitor.ts"` writes to the canonical target.
- The scaffolder's templates tree is filtered out of the discovery set
  (lines 152-156, 189-193) — running the engine inside the scaffolder
  repo cannot accidentally migrate the SOURCE files.

**Residual risk:** LOW.

- A symlink-directory attack would resolve to its real target (`pwd -P`),
  so writes land at the real path. If the project root itself was
  `cd`'d into a symlink, the engine has already followed it.
- If `$dir/cron-monitor.ts` itself is a pre-existing symlink, the
  idempotency check (`apply_root` → SKIP_ALREADY at line 446-449)
  refuses to write — `cron-monitor.ts` existing means already-migrated.
  But if the symlink points at a non-existent target, `cp` would create
  the target file at the symlink's destination. This is bounded by the
  classification gate (clean-wrapper hash check at line 451 — a
  symlink-to-malicious-target wouldn't pass canonical hash matching of
  the v1.17.0 baseline anchors), but worth flagging.
- `cp` (the engine uses default `cp`, not `cp -P` / `cp --no-deref`) WILL
  follow a destination-side symlink and overwrite the target. So a
  hypothetical attacker-prepared directory with `cron-monitor.ts` as a
  symlink to `/etc/passwd` AND a clean-hashing fingerprint set could
  cause an overwrite of `/etc/passwd` with the wrapper template. Two
  things make this implausible: (1) the attacker must already write
  the symlink AND the clean wrapper bytes into the victim's repo; (2)
  the idempotency check refuses if `cron-monitor.ts` already exists
  (which a symlink would satisfy in some shells but not all — `[ -f ]`
  follows symlinks, so a symlink-to-real-file is treated as
  "already-applied"). The actual write only happens when the
  destination does **not** exist.

**Recommendation:** LOW-priority hardening: replace `cp "$cm" "$dir/cron-
monitor.ts"` with `cp --no-clobber` (refuses to overwrite, even via
symlink) OR `(cd "$dir" && cp "$cm" cron-monitor.ts)` after asserting
`cron-monitor.ts` is not a symlink. The realistic exploit path is too
narrow to be blocking.

---

### S6 — Migration engine partial state on signal / disk-full

**Threat:** The engine uses a 2-pass structure (classify all, then apply
all) to enforce the all-clean gate (R08). But within pass 2, files are
copied root-by-root with no transaction. If the engine is killed
(SIGINT / SIGTERM / OOM / disk-full) between root #2 and root #3 of N,
the operator is left with:
- roots 1-2: migrated (cron-monitor.ts + healthz-snippet.ts present)
- roots 3-N: un-migrated (no new files)
- SKILL.md: either still at 1.17.0 (if `bump_version` didn't run) or
  at 1.18.0 (if it did) — depending on where the signal landed.

**Mitigation in code:**
- `bump_version` (line 91-103) is only called AFTER the apply loop
  completes (line 692-697), so a mid-loop kill leaves SKILL.md at
  1.17.0 → operator's next `migrate-0019` invocation will resume.
- The apply loop is idempotent at the root level: re-running on a
  partially-applied repo classifies the already-done roots as
  SKIP_ALREADY (line 446) and writes only the missing ones.
- No `trap` is registered for SIGTERM / SIGINT.

**Residual risk:** MEDIUM (operational, not security per se).

- Idempotency makes recovery cheap: just re-run.
- But the bash script could grow a `trap 'cleanup' INT TERM EXIT` to log
  "interrupted at root X" for visibility. Today, a kill produces no
  message — the operator sees partial state and has to diff.

**Recommendation:** SHOULD-FIX in a follow-up: add a `trap`
that prints a clear "INTERRUPTED — re-run to resume" line on exit
when MIGRATED < (CLEAN_DIRS count). Non-blocking; cheap addition.

---

### S7 — Migration engine content-hash bypass

**Threat:** The clean-vs-dirty classification relies on
`canonicalize_awk` (style-insensitive normalization) + sha256 against a
known-clean baseline (`is_known_clean_wrapper`, line 409-422). Two
bypass vectors:
1. **Hash collision:** an attacker crafts a hand-modified wrapper that
   canonicalizes to the same sha256 as the v1.17.0 baseline. Practical
   exploitability is essentially zero (sha256 second-preimage is
   computationally infeasible).
2. **Canonicalizer over-strips:** the awk normalizer aggressively masks
   tokens (`SERVICE_NAME`, `DESTINATION`, `REDACTED_KEYS`, env-var
   names, sample rates). If the canonicalizer over-masks a
   security-relevant edit — e.g. an operator added a custom auth
   header to the wrapper, which gets canonicalized away — the
   modified wrapper hashes equal to clean, the engine writes new
   files, and the migration completes "successfully" while the
   operator's modification gets silently rolled into a future drift.

**Mitigation in code:**
- `canonicalize_awk` (line 303-386) is **copy-verbatim from 0017's
  hardened canonicalizer** (per the script's header comment line
  301-302: "Any future refinement should land in 0017 FIRST and be
  back-ported here"). 0017's canonicalizer has shipped through two
  bugfix iterations (commits `27ef638` and `de13aca`) so it is
  battle-tested.
- The canonicalizer masks ONLY the well-known token positions; a
  user-added line (e.g. a custom header injection) would NOT canonicalize
  to baseline and would be flagged DIRTY → engine refuses
  (`emit_refuse_artifacts_for`, line 478-540).
- Migration 0019 is **additive only** — no wrapper files are MODIFIED.
  Only NEW files are written (`cron-monitor.{ts,go}` +
  `healthz-snippet.{ts,go}`). So even if a hand-modification slipped
  through classification, the operator's wrapper bytes are not
  rewritten — only new files appear next to them.

**Residual risk:** LOW.

- Hash-collision attack: cryptographically infeasible.
- Canonicalizer-bug attack: bounded by additive-only semantic of 0019.
  Worst case: operator gets `cron-monitor.ts` + `healthz-snippet.ts`
  alongside their existing custom wrapper; the custom wrapper is not
  touched.

**Recommendation:** None for 0019. (The shared `canonicalize_awk`
function is a known-shared concern; any hardening lands in 0017
first.)

---

### S8 — Sentry checkin spoofing

**Threat:** `captureCheckIn` returns a `checkInId` (TS) or
`*sentry.EventID` (Go). The wrapper passes this returned value into the
follow-up `ok`/`error` checkin. If the SDK returned an attacker-controlled
value, could the wrapper be tricked into a confused state (e.g.
referencing a different monitor's check-in)?

**Mitigation in code:**
- The wrapper passes `checkInId` AND `monitorSlug` on the completion
  call (`cron-monitor.ts:166, 174` worker; `cron_monitor.go:254-258,
  263-267` go) — so even if `checkInId` were spoofed, the slug field
  pins the monitor identity at the Sentry side.
- The SDK is trusted dependency (`@sentry/cloudflare`, `@sentry/deno`,
  `sentry-go`). A compromised SDK is out-of-scope for this review;
  the wrapper does not amplify the threat.
- The Go variant returns `*sentry.EventID` (pointer); the wrapper
  nil-checks (`if checkInID != nil`) before using it (`cron_monitor.go:
  251, 262`). A spoofed-nil return correctly skips the completion call.

**Residual risk:** LOW (theoretical only; depends on SDK trust).

**Recommendation:** None.

---

### S9 — SENTRY_DEBUG operational risk

**Threat:** When `SENTRY_DEBUG=1`, `debugLog` calls `console.error(msg,
err)` (TS) or `fmt.Fprintf(os.Stderr, ...)` (Go) with the caught Error.
Error objects in JS include stack traces containing absolute file paths
of the deployed bundle. In production deployments where `SENTRY_DEBUG=1`
is accidentally set (e.g. left over from a debugging session), stderr
captures bundle paths into the host log stream — a soft info-disclosure.

**Mitigation in code:**
- Default behaviour is **off** — `isDebug` checks for the exact
  string `"1"` (`cron-monitor.ts:51` worker, `cron-monitor.ts:53`
  pages, `cron-monitor.ts:101` supabase-edge, `cron_monitor.go:135`
  go). No partial matches.
- The intended use of `SENTRY_DEBUG` is documented in the wrapper
  source comments as "opt-in" (`cron-monitor.ts:103` worker R04 ref).
- Errors are only logged when the **SDK** boundary throws — i.e. when
  `captureCheckIn` itself crashes. In steady-state production with
  a healthy SDK, debug stays silent even if `SENTRY_DEBUG=1` is set.

**Residual risk:** LOW.

- The leak surface is "SDK boundary crashes only" — a low-frequency
  signal even when the toggle is on.
- The runbook does not currently caveat "avoid SENTRY_DEBUG=1 in
  production"; the source-code comments do.

**Recommendation:** LOW-priority docs hardening: add a one-line caveat
to the runbook's Part 1 ("Don't ship `SENTRY_DEBUG=1` to production —
the swallowed-checkin error path will write SDK stack traces to
stderr.") Not blocking.

---

### S10 — Runbook security guidance completeness

**Threat:** Runbook Part 4 covers info-disclosure (Mitigation 1) and
auth-gating (Mitigation 3) — but does NOT discuss rate-limiting. An
unauthenticated public `/healthz` exposed to the world can be DoS'd by
an attacker firing thousands of probes per second. Each probe drives
the underlying dep probes (DB ping, KV get, upstream HTTP), which can
amplify the attack against the dependencies themselves.

**Mitigation in code:**
- Runbook Part 4 documents Mitigations 1-3 (info-disclosure gate,
  `/readyz` split, Bearer-token auth) but does NOT document rate-
  limiting or per-probe caching.
- Runbook Part 2 Step 2 mentions probe cost: "1-minute probe across 4
  regions = 5,760 requests / day per endpoint" — implicitly framing
  COST but not DoS-amplification.
- No code-side rate-limit guard in any snippet (rate-limiting is a
  platform/edge-side concern — Cloudflare has built-in WAF rules;
  Supabase Edge has rate-limit middleware; Go would need a reverse-
  proxy).

**Residual risk:** LOW-to-MEDIUM (operational).

- The default Sentry Uptime probe cadence is bounded (1–15 min × N
  regions) so legitimate traffic is tiny.
- A motivated attacker probing 10k QPS at an unauthenticated public
  `/healthz` would amplify against deps — a real concern for low-end
  Fly Machines or small Workers.

**Recommendation:** LOW-priority follow-up: add a Mitigation 4 to
runbook Part 4 documenting two patterns:
1. **Cache the response for N seconds.** A 5-second SWR cache makes
   the probe a no-op for excess traffic; dep probes only fire once
   per N seconds regardless of request rate.
2. **Rate-limit at the edge.** Cloudflare Rules / WAF / Supabase
   throttle policies / Fly Tigris — platform-specific recipes.

Non-blocking. If the team prefers to defer, the existing Bearer-token
mitigation (Mitigation 3) provides a strong gate that subsumes most
DoS risk for production deployments.

---

## Findings summary

| Severity | Count | Items |
|----------|-------|-------|
| HIGH     | 0     | — |
| MEDIUM   | 2     | S4 (probe-timing oracle / no probe timeouts), S6 (no SIGTERM trap on apply engine) |
| LOW      | 4     | S2 (slug-injection regex), S5 (cp `--no-clobber` hardening), S9 (SENTRY_DEBUG runbook caveat), S10 (rate-limit + cache mitigations in runbook) |

**Dimensions clean (no finding):** S1 (DSN handling), S3 (intentional;
documented), S7 (canonicalizer bypass — additive-only bounds risk),
S8 (Sentry checkin spoofing).

---

## Verdict

**PASS WITH HARDENING.**

Phase 22 ships no HIGH-severity defects. The MEDIUM findings (S4 probe
timeouts, S6 signal trap) are RECOMMENDED follow-ups, neither of which
blocks the PR:
- S4 is a known info-disclosure trade-off scoped to the public-healthz
  default (mitigation paths documented in runbook Part 4).
- S6 is operational hygiene; the engine is idempotent so partial state
  on signal is recoverable by re-running.

The LOW findings are documentation / defense-in-depth improvements that
can be folded into a future minor (S9 runbook caveat, S10 rate-limit
patterns) or a follow-up hardening phase (S2 slug-regex validator,
S5 `cp --no-clobber`).

**Approved to merge.** Suggested follow-up phase items:
1. Phase 22.1 — Healthz probe-timeout pattern (S4) + runbook Mitigation 4
   for rate-limit / SWR-cache (S10) + SENTRY_DEBUG production caveat (S9).
2. Phase 22.2 (deferred-minor) — Migration-engine signal trap (S6) + slug
   regex validator (S2) + `cp --no-clobber` (S5). Defer to the next
   migration-engine pass; S7's pattern of "land hardening in 0017 first,
   back-port to 0019" applies.

---

## References

- Spec §10.6 — observability wrapper contract.
- Spec §10.7 — migration consent gates.
- CONTEXT.md D4 (`/healthz` not wrapped — noise + privacy framing).
- CONTEXT.md D11 (multi-cron explicit-slug requirement — env-var
  unambiguity).
- PLAN.md R02 / R03 / R04 (fail-safe + opt-in debug surface).
- PLAN.md R06 (fail-closed zero-probes 503).
- PLAN.md R07 (WARNING ASCII-banner in each snippet).
- PLAN.md R08 (all-clean gate — 2-pass atomic apply).
- PLAN.md R10 (runbook Part 4 — security & public exposure).
- Runbook Part 4 (`add-observability/uptime-setup-runbook.md:311-446`).
- ADR-0028 (`docs/decisions/0028-sentry-crons-healthz-conventions.md`)
  — host-discretion trade-off; not a spec mandate.
- Migration engine
  (`templates/.claude/scripts/migrate-0019-sentry-crons-and-healthz.sh`).
- 0017's canonicalizer (parent shape; bugfixes in commits `27ef638`,
  `de13aca`).
