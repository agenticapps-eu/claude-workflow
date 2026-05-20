# Session Handoff — 2026-05-20 (template-fidelity v0.4.0 shipped; scaffolder steady at v1.12.0)

## Status snapshot

Five claude-workflow PRs landed across the last three working sessions
(2026-05-16, 2026-05-18, 2026-05-20). State on `main @ 1404fe6`:

- **scaffolder** `skill/SKILL.md`: **v1.12.0**
- **`add-observability/SKILL.md`**: **v0.4.0**, `implements_spec: 0.3.2`
- migration suite (`bash migrations/run-tests.sh --strict-preflight`): **PASS=136 FAIL=0**
- Phase 15 smoke: **9/9**

### Recent merges (newest first)

- **PR #41** (`1404fe6`, 2026-05-20) — `add-observability` v0.3.3 → v0.4.0:
  Sentry v8 `withSentry` adoption in `ts-cloudflare-worker` (closes #40
  Bug 1), `ScheduledEvent` → `ScheduledController` rename (closes #40
  Bug 2), native `Contexts["trace"]` in `go-fly-http` `CaptureError`
  (closes #39), Phase 15 smoke version-pin drift from PR #37 fixed in
  lockstep. No scaffolder bump — template-only.
- **PR #37** (`a7e7668`, 2026-05-18) — `implements_spec` bumped 0.3.0 →
  0.3.2 on both `skill/SKILL.md` and `add-observability/SKILL.md`
  (depends on workflow-core PR #7). Declarative-only.
- **PR #36** (`9011366`, 2026-05-18) — `go-fly-http` template gains
  explicit `Flush(timeout)` primitive — drains emission-goroutine
  WaitGroup before calling `sentry.Flush`. Closes a short-lived-process
  race where wrapper-routed events lost in cparx CLI smoke runs.
  `add-observability` v0.3.2 → v0.3.3.
- **PR #35** (`2459f3c`, 2026-05-16) — Migration 0013 +
  scaffolder 1.11.0 → 1.12.0 (auto-init + stale-vendored cleanup).
- **PR #34** (`6f35aad`, 2026-05-16) — `add-observability` v0.3.1 →
  v0.3.2 (REDACTED_KEYS expansion + ts-react-vite re-export fix).

### Open PRs

- **PR #38** (this branch, `docs/post-0013-handoff-snapshot`) — was the
  handoff snapshot from 2026-05-18; rebased onto current main and
  refreshed in this session to capture today's state.

### Recently closed issues

- **#39** closed by PR #41 — go-fly-http native trace context.
- **#40** closed by PR #41 — both bugs (Sentry.init removal, ScheduledEvent typo).

## Next session: start here

### 1. Sync local global scaffolder install

```bash
cd ~/.claude/skills/agenticapps-workflow && git pull --ff-only
grep '^version:' skill/SKILL.md           # expect: version: 1.12.0
grep '^version:' add-observability/SKILL.md   # expect: version: 0.4.0
```

### 2. Resume downstream adoptions (carried forward)

Both cparx and fx-signal-agent need to land their v1.12.0 + v0.4.0
adoption. As of 2026-05-20 both are on feature branches but neither
has merged.

- **cparx** is on `chore/observability-adoption-v1.12.0`. cparx witnessed
  Issue #39 (PR #48 in cparx, the Sentry-test endpoint at #50). With v0.4.0
  shipped, the `CaptureError` path now writes native trace context — re-pull
  the global scaffolder, re-materialise the Go wrapper into cparx (or apply
  the v0.4.0 template diff manually), and verify `trace:<hex>` Discover
  search hits.
- **fx-signal-agent** is at workflow v1.9.3 with stale v0.2.1 vendored
  skill (see #40 — that's where the worker bugs were discovered). Same
  full-manual flow as cparx today: stash WIP, branch, remove stale
  vendored skill, run init, /update, scan --update-baseline, scan-apply
  --confidence high. With v0.4.0, the worker init produces a wrapper that
  type-checks against `@sentry/cloudflare` v8 OUT OF THE BOX — no manual
  Sentry.init replacement, no manual ScheduledController patch.

### 3. ts-supabase-edge verification (deferred from PR #41)

PR #41's CHANGELOG explicitly notes: `ts-supabase-edge` ships its own
`index.ts` using `@sentry/deno` v8, which still exports `Sentry.init`
(different runtime model from the Cloudflare SDK). Neither PR #41 fix
applies. When the next Supabase Edge adopter lands, verify the
materialised wrapper actually type-checks + runs against current
`@sentry/deno` v8; if it doesn't, open a follow-up issue with the same
shape as #40.

## Plausible future work (no urgency)

- **`test_init_fixtures()` harness** — Phase 15 F4. The init fixture pairs
  in `migrations/test-fixtures/init-<stack>/` are still reference-only;
  no harness materialises `before/` through init and diffs against
  `expected-after/`. PR #41's `ts-cloudflare-worker` fixture edits were
  hand-applied for that reason. A v1.13.0 candidate phase.
- **`policy:` multi-stack support** — cparx-style dual-stack repos ship
  only the primary stack's policy path in CLAUDE.md (per spec §10.8
  scalar `policy:`). Multi-stack `policies: [...]` array form needs a
  spec amendment + parser change.
- **F3 from the original cparx adoption report** — go-fly-http
  multi-binary entry detection (post-candidate-selection HTTP-shape
  verification). Low severity, no migration.

## Open questions (carried forward)

- **`enforcement.ci:` field** still omitted by default. v1.10.0 Option-4
  local-first stance held through v1.12.0. Opt-in CI workflow remains
  copy-paste from `add-observability/enforcement/observability.yml.example`.
- **CI workflow wiring for `--strict-preflight`** — flag exists; no GHA
  workflow uses it yet. Could land in a future test-infrastructure
  phase if you want to gate merges on verify-path rot.
- **Residual #32 formal §1-§8 conformance audit doc** — still open.
- Helper-script license consent for `index-family-repos.sh --all`,
  canonical install command for `/gsd-review` — carried.
