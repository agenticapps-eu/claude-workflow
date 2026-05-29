# Phase 23 — Discussion Log

> **Audit trail only.** Not consumed by researcher / planner / executor.
> The binding decisions live in `CONTEXT.md` §"Resolved decisions" (D-01–D-09).
> This log preserves the alternatives considered for each decision so future
> reviewers can see *what was rejected and why*.

**Date:** 2026-05-29
**Phase:** 23 — observability-followups
**Mode:** express-path discuss (single AskUserQuestion gate on the architectural fork; 8 of 9 OQs locked to pre-discuss recommendations after user approval)
**Discussant:** Claude Opus 4.7 (1M context) — author of pre-discuss CONTEXT
**User authority:** Donald (donald.vlahovic@neuro-flash.com), express-path approval via single multi-option question on 2026-05-29

---

## Why express-path

The pre-discuss CONTEXT.md draft (25 KB before resolution, written across two sessions on 2026-05-29) framed all 9 open questions with concrete recommendations grounded in:

- **Code reads** of the current `withCronMonitor` implementations across `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `go-fly-http`
- **Context7 lookups** against `@getsentry/sentry-javascript@develop` (confirming `withMonitor<T>(slug, callback, monitorConfig?): T` exists at `packages/core/src/exports.ts`) and `getsentry/sentry-go` (confirming no `WithMonitor` helper exists — only `CaptureCheckIn`)
- **Phase 22 contract review** (REVIEW.md, SECURITY.md, CONTEXT.md decision tables) to identify which existing contracts (D6, R02, R04, D11, D12) each refactor shape would preserve or regress
- **User memory** at `~/.claude/projects/-Users-donald-Sourcecode-agenticapps-claude-workflow/memory/prefers-judgment-over-asking.md` — user prefers recommend-and-proceed over multi-round AskUserQuestion ceremony

The user invoked Phase 23 with the explicit instruction *"do phase 23, but withCronMonitor refactoring baked in"* (2026-05-29 session). The phrase *"refactoring baked in"* (not "fold the refactor consideration in" or "add the refactor as a discussion item") was interpreted as a directive to land the refactor, with the only open architectural decision being its shape (A/B/C/D/F).

Eight of the nine OQs have clear-cut recommendations with no controversial trade-off (version bump is mechanically determined by OQ-8; batch-vs-split is overwhelmingly batch; timeout default + parser + test location + flag mechanics + Go SDK posture all have one defensible choice each). Only OQ-8 (refactor shape) presents a real architectural fork: Shape A trades R02/R04 SDK-error swallow for upstream alignment + `withIsolationScope`; Shape F preserves all Phase 22 contracts but loses the strategic value of the refactor.

A single AskUserQuestion was issued with three options (Lock all + Shape A / Lock 8 + swap OQ-8 to Shape F / Open full discuss flow), code-previewed for Shape A and Shape F so the user could compare the actual `cron-monitor.ts` diff shapes side-by-side. The user selected **"Lock all 9 with recommendations (Shape A)"** — confirming both the express-path framing and the Shape A refactor.

---

## Per-question record

### OQ-1 — Version bump shape

| Option | Description | Selected |
|---|---|---|
| (a) No bump anywhere | Engine fix + test + doc + template tweak — none individually user-facing | |
| (b) `add-observability 0.6.0 → 0.6.1` patch | Honours F2 template-shape change only | |
| (c) `add-observability 0.6.0 → 0.7.0` minor | F5's `withIsolationScope` addition + R02/R04 SDK-error propagation shift = observable downstream behaviour → honest minor; F2 hitches along | ✓ |
| (d) `claude-workflow 1.18.0 → 1.18.1` patch | If F1/F3/F4 are reclassified as user-visible | |

**Resolution: D-01 — option (c).** Mechanically forced by OQ-8 = Shape A. `claude-workflow` stays at `1.18.0` per the *versioning-tracks-migrations* memory invariant (engine fix + tests + doc only). No new migration — same N2 reasoning as Phase 22.

**Notes:** Pre-discuss CONTEXT originally recommended (b) before F5 was added; revised to (c) when F5 was baked in. The revision is documented at `CONTEXT.md` §"Version bump (locked per D-01)".

---

### OQ-2 — Batch vs split

| Option | Description | Selected |
|---|---|---|
| Batch all five (F1–F5) into Phase 23 | TD1: per-item planning ceremony cost dwarfs implementation; F5 sequences naturally after F2 | ✓ |
| Split per Phase 22 SECURITY.md (22.1 + 22.2 sequence) | Honour the original split proposal | |

**Resolution: D-02 — batch.**

**Notes:** F5's addition strengthens the batch case rather than weakening it — F5 and F2 both touch `add-observability` templates and ship in the same minor bump.

---

### OQ-3 — Healthz default probe timeout

| Option | Description | Selected |
|---|---|---|
| 1 second | More conservative; risk of false-degraded on slow but legitimate upstreams | |
| 2 seconds (default, caller-configurable) | TD2; matches SECURITY.md S4 recommendation; Sentry Uptime probes typically time out at 5–10s, leaves margin | ✓ |
| 3 seconds | More slack for slow upstreams; closer to Sentry's outer timeout | |
| Caller-required, no default | Forces explicit decision per probe; higher friction at install time | |

**Resolution: D-03 — 2 seconds, caller-configurable (TS `DEFAULT_HEALTHZ_PROBE_TIMEOUT_MS = 2000`, Go `defaultHealthzProbeTimeout = 2 * time.Second`).**

---

### OQ-4 — `yq` dependency posture for F4 frontmatter parsing

| Option | Description | Selected |
|---|---|---|
| Adopt `yq` | Robust YAML parsing; new tool dep (not currently used anywhere in repo) | |
| Minimal bash YAML parser inline | `skill/SKILL.md` frontmatter is fixed-shape — `grep ^version:` + `awk` is sufficient | ✓ |

**Resolution: D-04 — minimal parser.** No new tool dependency. If a future phase needs richer YAML parsing (e.g., multi-field cross-reference checks), that's the trigger to revisit `yq` adoption.

---

### OQ-5 — F3 SIGTERM test mechanics

| Option | Description | Selected |
|---|---|---|
| (a) Inject a "pause here" hook the test releases | Cleanest but requires test-only code path in engine | |
| (b) Add `--pause-between-passes <signal-file>` engine flag | Test-only flag, no production code path, deterministic | ✓ |
| (c) Race with a short sleep | Accept ~5% flake | |

**Resolution: D-05 — option (b).**

---

### OQ-6 — F4 drift test location

| Option | Description | Selected |
|---|---|---|
| `migrations/run-tests.sh` | Test guards a migration-side invariant (every migration's `to_version` must equal shipped SKILL.md version) | ✓ |
| New `tests/skill-drift.sh` | Assertion is about `skill/` not migrations — could justify standalone test file | |

**Resolution: D-06 — `migrations/run-tests.sh`.** Naming inside the script: `test-skill-md-version-matches-latest-migration-to-version`.

---

### OQ-7 — Atomic-refuse `--allow-partial` flag for migration engine

| Option | Description | Selected |
|---|---|---|
| (a) Status quo (R09): patches everywhere on refuse | Fast manual recovery; surprise git diff on clean roots | |
| (b) Add `--allow-partial` flag; default to zero-side-effect refuse | Restores "truly atomic refusal" as default; preserves R09 recovery aid as opt-in | ✓ |
| (c) Always zero-side-effect refuse on clean roots; emit patches only for the dirty root | Cleanest but loses cross-root splice aid even when operator would want it | |

**Resolution: D-07 — option (b).**

**Notes:** Migrating 0019 to (b) requires fixture 06's `verify.sh` assertion shape to flip. Migration 0017 audit precedes the change to align both engines' refuse semantics. CodeRabbit's PR #53 R09-on-clean-roots observation (rejected as false-positive at the time pending this OQ) is now actioned via D-07.

---

### OQ-8 — F5 refactor shape *(the only genuine architectural fork)*

| Option | Description | Selected |
|---|---|---|
| (A) Compose `Sentry.withMonitor` underneath outer wrapper | Preserves D6 slug + R02 fail-safe + D12 monitorConfig; trades R02/R04 SDK-error swallow for upstream alignment + `withIsolationScope` + duration accuracy | ✓ |
| (B) Drop-in replacement | Smallest LOC. Drops R02 fail-safe, R04 swallow, R02 fail-safe; adds `withIsolationScope` by default | |
| (C) Deprecate + parallel export (`withCronMonitor` + `withCronMonitorV2`) | +50 LOC per file; zero risk for in-flight fxsa/callbot adoption; sunsets in future major | |
| (D) Compose with explicit SDK-throw firewall (stack inspection) | Restores R02/R04 at significant complexity cost | |
| (F) No refactor — port only `duration` tracking | +8 LOC per file; all Phase 22 contracts preserved; loses strategic upstream-alignment value | |

**Resolution: D-08 — Shape A.** User confirmed via AskUserQuestion on 2026-05-29 with side-by-side code previews for Shape A and Shape F.

**Documented regression:** R02/R04 SDK-error swallow drops — `Sentry.withMonitor` re-throws SDK errors during `captureCheckIn` instead of silently swallowing them. The Phase 23 PR body and `add-observability/CHANGELOG.md 0.7.0` entry MUST call this out as a breaking-ish change for downstream consumers (fxsa, callbot).

**Documented addition:** `withIsolationScope` wrapping added — each cron run gets its own Sentry scope. Non-breaking; arguably correctness improvement (error context no longer leaks between cron invocations).

**Trade-off rationale:** User invoked the refactor with the phrasing *"withCronMonitor refactoring baked in"*. This was interpreted as a directive for a genuine refactor (Shape A) rather than a cosmetic touch-up (Shape F). Shape A delivers strategic value: upstream alignment with the Sentry SDK's primary cron API + automatic duration accuracy + scope isolation, at the cost of one documented regression that downstream consumers handle by upgrading their existing outer-wrapper error capture (which they already have via `withObservabilityScheduled`).

---

### OQ-9 — Go SDK gap follow-up

| Option | Description | Selected |
|---|---|---|
| (a) Document the gap in `cron_monitor.go` package doc | G8; no upstream action | ✓ |
| (b) Open GH issue against `getsentry/sentry-go` proposing the helper | Nice-to-have; doesn't protect any downstream contract | |
| (c) Send PR to `sentry-go` implementing `WithMonitor` | Highest upstream value; significant scope expansion for this phase | |

**Resolution: D-09 — option (a).** Captured as deferred idea for future phase if user wants upstream contribution.

---

## Claude's Discretion

Within D-08 Shape A:
- Precise placement of the `try` block around `Sentry.withMonitor` (whether the outer error path needs adjustment now that SDK errors propagate)
- Exact JSDoc wording for the documented regression in each `cron-monitor.ts`
- Test-file naming for the behavioural-parity case (`cron-monitor.test.ts` extension vs new `cron-monitor.parity.test.ts`)

Within D-07:
- Bash flag-vs-env-var precedence order — recommendation: flag wins over env var, both must explicitly opt in to enable patches-on-refuse

---

## Deferred Ideas

Captured during Phase 23 scoping but explicitly out of scope (also recorded in `CONTEXT.md` §"Deferred Ideas"):

- Open a `getsentry/sentry-go` issue or PR proposing a `WithMonitor` helper (D-09 (b) or (c))
- Retrofit `Sentry.withMonitor` adoption into Go via an AgenticApps shim
- Add GitHub Actions CI (`migrations/run-tests.sh` + `add-observability/templates/run-template-tests.sh all` on PR) — Phase 24 candidate
- Multi-cron env-key support (Phase 22 D11 deferral)
- Per-cron `monitorConfig` overrides for `schedule` / `maxRuntimeSeconds` (Phase 22 D12 deferral)
- Client-side timeout enforcement on `withCronMonitor` (Phase 22 D12 deferral)
- Refactor Go `WithCronMonitor` (N6 — no `sentry-go` `WithMonitor` to compose against)

---

*Phase: 23-observability-followups*
*Discussion logged: 2026-05-29*
