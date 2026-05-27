# ADR-0027: GSD post-phase observability hook (advisory)

**Status**: Accepted  **Date**: 2026-05-27  **Issue**: #50

## Context

While backfilling observability coverage in `cparx`, the question came up of
where "auto-check agent-written code for §10 gaps" enforcement should live. The
`add-observability` skill already supports a delta scan
(`scan --since-commit <ref>` → `.observability/delta.json`), but nothing runs it
automatically after a phase. Every AgenticApps repo has the same gap.

`templates/.claude/hooks/` + a migration is exactly how `database-sentinel.sh`
and `multi-ai-review-gate.sh` reach every repo, and the GSD workflow already runs
`/review` (+ `/cso`, `/qa`) post-phase. A post-phase observability delta scan is
the same shape and the natural home for "did this phase introduce new gaps?".

Migration 0011 deliberately shipped local-only enforcement (baseline +
`scan --since-commit` pre-PR command) and deferred the §10.9.3 CI gate and
§10.9.4 pre-commit hook pending a deterministic Node scanner port that is still
unshipped (scaffolder 1.16.0; skill `implements_spec: 0.3.2`). This ADR closes
the one piece that belongs upstream now — the post-phase agent gate — without
relitigating those deferrals.

## Decision

Ship `templates/.claude/hooks/observability-postphase-scan.sh` and wire it into
the **GSD post-phase chain** via a new migration **0018** (1.16.0 → 1.17.0).

**Wiring: the declarative post_phase chain, not a Claude Code `Stop` hook.**
The post-phase gates (`spec_review`, `code_quality_review`, `security`, `qa`)
live in `config-hooks.json` → `hooks.post_phase` (installed into projects as
`.planning/config.json`) and are agent-driven — the workflow skill instructs the
agent to run them once at phase completion. `observability_scan` joins them
there. It is deliberately **not** registered as a Claude Code `Stop` hook in
`.claude/settings.json`: a `Stop` hook fires on every agent turn-end, so running
an LLM-driven scan there would be high-cost and risk recursion (a scan spawning
turns that re-trigger the hook). The post-phase chain runs it exactly once per
phase — the frequency the advisory model assumes.

**Advisory, never blocking.** The script always `exit 0`. The scan is LLM-driven
today, so a hard gate would add per-phase cost + nondeterminism. It can graduate
to blocking once the deterministic scanner lands. Mirrors how
`architecture-audit-check.sh` nags rather than blocks.

**Behavior:**
- Silent no-op (exit 0) outside a GSD project (no `.planning/`).
- **Explicit** no-op (one line, exit 0) when `.observability/baseline.json` is
  absent — the project hasn't adopted §10.9 enforcement, so there's nothing to
  delta against.
- Resolves the phase-base commit (optional `.planning/current-phase/phase-base`
  override, else `git merge-base HEAD origin/<default-branch>`).
- Runs `claude -p "/add-observability scan --since-commit <base>"` headlessly;
  if `claude` is not on PATH, prints the command and exits 0.
- Reads `.observability/delta.json`; if `counts.high_confidence_gaps > 0`, warns
  and points at `scan-apply --confidence high`.
- Fail-open throughout (`set +e` + `trap 'exit 0' EXIT`).

## Alternatives Rejected

- **Register as a `Stop` settings.json hook.** Rejected: fires every turn-end,
  not once per phase — wrong frequency for an LLM scan, and recursion-prone.
- **Make it blocking (hard gate on `high_confidence_gaps > 0`).** Rejected per
  #50: the scan is LLM-driven and nondeterministic today; blocking would add
  per-phase cost and flakiness. Advisory now; blocking once the deterministic
  scanner exists.
- **Bundle the §10.9.3 CI gate / §10.9.4 pre-commit hook.** Out of scope per #50
  — both remain deferred pending the Node scanner port.
- **Fix per-project in `cparx`.** Rejected: wiring it into one repo benefits no
  other and would diverge on the next migration. The hook surface is the upstream
  propagation mechanism.

## Consequences

- Every AgenticApps repo that applies 0018 gets the post-phase scan gate; it is a
  no-op until the repo adopts enforcement (`baseline.json`), so it is safe to
  propagate broadly.
- Workflow `1.16.0 → 1.17.0`. Note: this 1.17.0 is the post-phase hook, **not**
  the long-deferred Node scanner port (also informally called "1.17.0 follow-up"
  in earlier handoffs); those are independent.
- The hook is advisory; a phase can still merge with unaddressed gaps. That is the
  intended strength until the deterministic scanner can back a blocking gate.
- `architecture-audit-check.sh` is the precedent for an advisory, fail-open,
  always-`exit 0` hook in this repo.
