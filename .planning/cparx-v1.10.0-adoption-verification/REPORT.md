# cparx v1.10.0+v1.11.0 adoption verification

**Date**: 2026-05-16
**Scaffolder version under test**: v1.11.0 (HEAD `763d041` on main)
**Skill version under test**: `add-observability` v0.3.1 (global), v0.3.2 in-flight (claude-workflow branch `chore/redacted-keys-default-v0.3.2`)
**Target repo**: `agenticapps-eu/cparx` @ `chore/observability-adoption-v1.10.0`
**Verifier**: Claude Opus 4.7 (1M context), driven by user request "REDACTED_KEYS and 1.10.0 adoption verification but with cparx"

---

## Outcome

**PASS** with **3 findings** (1 user-side blocker resolved, 1 template
bug discovered, 1 soft gap in detection logic).

7 atomic commits on cparx's `chore/observability-adoption-v1.10.0`
branch take it from workflow `v1.9.3 / no observability` to `v1.11.0
/ spec §10 conformant`. Backend (chi) and frontend (Vite) both
compile clean post-adoption.

```text
5c29da44 chore: migrate AgenticApps workflow 1.10.0 → 1.11.0 (migration 0012)
022c6680 chore: migrate AgenticApps workflow 1.9.3 → 1.10.0 (migration 0011 Steps 2-4)
cfc15d74 feat(observability): migration 0011 Step 1 — author .observability/baseline.json
571aea90 feat(observability): init Phase 6 — observability metadata block in CLAUDE.md
79df9e6b feat(observability): init Phase 5 — wire entry files + Sentry SDK deps (dual stack)
f0caa3d1 feat(observability): init Phase 4 — scaffold wrapper + middleware + policy (dual stack)
d6a6ccc2 chore: remove stale vendored add-observability skill (v0.2.1)
```

---

## Findings

### F1 — User-side blocker: stale vendored skill (RESOLVED on cparx)

**Severity**: HIGH (would block adoption silently with a confusing error)
**Affects**: Any project that installed `add-observability` at v0.2.x via
the pre-slash-discovery vendoring pattern.

cparx had `.claude/skills/add-observability/SKILL.md @ v0.2.1` —
project-local, vendored at workflow setup time (pre-§10.9, pre-init).
Claude Code resolves project-local skills before user-global ones, so
`claude /add-observability init` would route through the v0.2.1 skill
which has no `init` subcommand at all, producing "unknown subcommand"
without ever reaching the global v0.3.1 skill.

**Fix on cparx**: deleted the entire `.claude/skills/add-observability/`
tree in commit `d6a6ccc2`. Subsequent `/add-observability …` calls
resolve to the global skill via the slash-discovery symlink installed
by migration 0012.

**Upstream implication**: any other AgenticApps project that vendored
add-observability (likely candidates: fx-signal-agent, factiv-website,
others) will hit the same blocker. Worth adding to migration 0011's
or 0012's pre-flight a check that fails fast if a stale project-local
vendored copy is present, with a clear "remove .claude/skills/add-observability/"
remediation message.

Recommended migration: a new `0013-stale-vendored-cleanup.md` that
detects `.claude/skills/add-observability/` and aborts with a clear
remediation step. Or fold into 0011's pre-flight (less invasive but
mixes concerns).

### F2 — Template bug: ts-react-vite missing re-export

**Severity**: MEDIUM (breaks Phase 5 entry rewrite on a stack that's
documented to support it)
**Affects**: Every ts-react-vite adopter at v0.3.1.

`templates/ts-react-vite/lib-observability.ts` does NOT include the
line:

```typescript
export { ObservabilityErrorBoundary } from "./ErrorBoundary";
```

But INIT.md Phase 5 detail (line 632-634) requires it:

> `src/lib/observability/index.ts` — re-exports `init`, `captureError`,
> `startSpan`, `logEvent`, and the `ObservabilityErrorBoundary` React
> component.

And INIT.md Phase 5's main.tsx rewrite shape (line 723) imports both:

```typescript
import { init, ObservabilityErrorBoundary } from "./lib/observability"
```

Without the re-export line in the template, the materialized
`src/lib/observability/index.ts` exports `init` but NOT
`ObservabilityErrorBoundary`, and `main.tsx` fails type-check:

```text
Module './lib/observability' has no exported member 'ObservabilityErrorBoundary'
```

**Fix on cparx**: manually added the re-export line in commit
`79df9e6b` after spotting the diagnostic.

**Upstream fix**: add the line to
`add-observability/templates/ts-react-vite/lib-observability.ts`
between the JSDoc header and the rest of the module body. Shipped as
**v0.3.2** of the skill (this PR) — patch release since it's a bug
fix that breaks a documented integration path. No migration needed;
the fix only affects future `init` runs.

The init fixture at
`migrations/test-fixtures/init-ts-react-vite/expected-after/src/lib/observability/index.ts`
already shows the correct shape on line 22 — so the fixture documented
the contract but the template never matched it. Suggests an
unautomated drift between fixture and template. Phase 15's
"per-stack init fixtures (reference-only at v1.11.0; no automated
harness yet)" — this finding is concrete evidence for why that
harness matters.

### F3 — Soft gap: go-fly-http multi-binary entry detection

**Severity**: LOW (didn't bite cparx, but would bite a similar layout)
**Affects**: Go monorepos with multiple `cmd/<name>/main.go` binaries
where the HTTP server isn't the first entry candidate matched.

cparx has 4 cmd binaries:
- `cmd/api/` — chi HTTP server (the one to wrap)
- `cmd/llm-check/` — CLI utility
- `cmd/process-pending-docs/` — CLI utility
- `cmd/seed-mock-docs/` — CLI utility

INIT.md's `entry_file_candidates` for go-fly-http:

```yaml
entry_file_candidates:
  - cmd/server/main.go
  - cmd/api/main.go
  - main.go
  - internal/server/server.go
```

cparx matches at position 2 (`cmd/api/main.go`) — correct. But a repo
where the first candidate `cmd/server/main.go` exists AND is a non-HTTP
CLI would have init try to wrap a non-server `main()`, producing
either a no-op (if no ListenAndServe / NewRouter found, the wrap site
detection would fail) or worse, accidentally wrap a non-HTTP cmd.

**Mitigation that would have helped**: after candidate selection,
verify the candidate file imports an HTTP-server-shaped package
(`net/http` AND `ListenAndServe`, OR chi/gorilla router constructor)
before proceeding. Treat non-HTTP candidates as auto-skipped, fall
through to the next candidate.

Not load-bearing for v1.11.0 ship; flag for a v0.3.4 or v0.4.0
refinement. The current behavior is "best-effort first-match" which
is fine for single-binary Go services (the common case).

### Migration mechanics (positive findings)

**0011 Step 2 is correctly idempotent when init lands before
migration 0011** — this is the v1.11.0 ordering pattern (init shipped
at v1.11.0, migration 0011 at v1.10.0). When a v1.9.3 project adopts
v1.11.0 in one go, init runs first and writes the v0.3.0 metadata
block with the enforcement sub-block (including
`spec_version: 0.3.0`). Migration 0011 Step 2's idempotency check
correctly identifies "already at v0.3.0, skip" and Step 3 still
applies (adding the enforcement section to CLAUDE.md). No conflict.

**0012's symlink pre-flight is correctly defensive** — it refuses to
clobber a real directory at `~/.claude/skills/add-observability` and
refuses to redirect a symlink pointing elsewhere. The dev-box state
where the symlink was missing (this verifier's setup) was caught and
remediated as a pre-step before adoption began.

**Both migrations are CLAUDE.md-friendly** — they edit a known
section, use anchored insertions or whole-file sed for version
bumps, and the post-checks confirm idempotency. cparx's existing
CLAUDE.md structure (gstack workflow + handover sections) survived
unmodified.

---

## What the user did

The user requested adoption verification on cparx specifically because
they're actively working on fx-signal-agent and wanted a safer target.
Per the global CLAUDE.md "feature branches + PRs to main" rule, all
work landed on a feature branch with no push and no PR. The user can:

1. Push the branch and open a PR for cparx review.
2. Keep the branch local indefinitely until needed.
3. Cherry-pick specific commits (e.g., the 4-commit "scaffold only"
   subset) without taking the full migration chain.

cparx pre-adoption dirty state (`codebase-analysis-docs/CODEBASE_KNOWLEDGE.md`
modification + `workflows.png` untracked) was stashed under
`pre-observability-adoption: snapshot of unrelated WIP` and is
preserved.

---

## Upstream action items (claude-workflow)

| # | Finding | Action | Target version |
|---|---------|--------|----------------|
| F1 | Stale vendored skill blocker | Detection in pre-flight + remediation message, OR a `0013-stale-vendored-cleanup.md` migration | scaffolder v1.12.0 |
| F2 | ts-react-vite missing re-export | Add `export { ObservabilityErrorBoundary } from "./ErrorBoundary";` to template | `add-observability` v0.3.2 (this PR) |
| F3 | Multi-binary Go entry-file detection | Post-candidate-selection HTTP-shape verification | `add-observability` v0.3.4 or v0.4.0 |

### Suggested test additions

The 7 init fixture pairs are still reference-only at v1.11.0 (no
harness exercises them — see Phase 15 VERIFICATION F4). F2 is direct
evidence for why that harness should exist: the template + fixture
divergence sat there for 6+ months silently. A
`test_init_fixtures()` function in `migrations/run-tests.sh` that
materializes each fixture's `before/` through init (substituting
parameters) and diffs against `expected-after/` would catch F2-class
drift automatically.

This is a logical follow-up phase for v1.12.0 of the scaffolder.

---

## How to reproduce / extend

The branch is reusable as a reference adoption. To replay against
fx-signal-agent (the originally-listed target):

1. Confirm fx-signal-agent's vendored skill state:
   ```bash
   ls ~/Sourcecode/agenticapps/fx-signal-agent/.claude/skills/add-observability/
   ```
   If present, remove it (F1 remediation) before running init.

2. Re-execute Phase 4-6 + migrations 0011 + 0012 following the
   commit-message pattern from this branch. The same dual-stack
   verification approach applies (fx-signal-agent has Go + Vite).

3. F2 is fixed in v0.3.2 (this PR). Ensure the consuming Claude Code
   session resolves the global skill at v0.3.2+ — no manual patch needed.

The 14-gap fresh-init baseline.json on cparx is hand-authored
(commit `cfc15d74`); fx-signal-agent should run
`claude /add-observability scan --update-baseline` to author its own
authoritative baseline before opening a PR.

---

## Sign-off

Adoption path verified end-to-end on a real (post-handover) repo.
Migration framework is sound. Two skill-side fixes (F2, F3) and one
migration-side enhancement (F1) recommended; none of them block
v1.11.0 ship.

— Claude Opus 4.7, 2026-05-16
