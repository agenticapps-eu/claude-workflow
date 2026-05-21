---
id: 0024
slug: secret-scanner-choice
title: Secret-scanner choice — STAY on gitleaks (ratifies workflow-core ADR-0015)
status: Accepted
date: 2026-05-21
supersedes: []
related: [0014]
---

# ADR 0024: Secret-scanner choice — STAY on gitleaks

## Status

Accepted. Mirrors the outcome that ratifies the upstream
`agenticapps-workflow-core` ADR-0015 (Status: Proposed → Accepted in
the cross-repo PR opened from Phase 20 P4.6).

## Context

Phase 20 (spec 0.4.0 absorption) carried an obligation to ratify
workflow-core ADR-0015, which had shipped at spec v0.4.0 as a
Proposed placeholder with a TBD Decision block. ADR-0015 expects a
benchmark-driven ratification: keep `gitleaks` (status quo) or swap
to `betterleaks` (Apache/MIT, advertised as a strict capability
superset with config-compatible migration).

This ADR records claude-workflow's local outcome from that benchmark
and provides a stable in-repo link for downstream tooling that
expects per-project provenance for the chosen scanner.

The benchmark methodology (criteria, decision rule, fixture
strategy) was authored before any scan ran — see
`.planning/phases/20-spec-0.4.0-absorption/RESEARCH.md` §§A1–A6.
All seven criteria + their pass/fail thresholds + the SWAP/STAY/REVISIT
decision rule were locked pre-benchmark to prevent post-hoc tuning.

## Decision

**STAY on gitleaks** as claude-workflow's recommended secret-scanner.

Rule that fired: RESEARCH.md A4 STAY clause — *"gitleaks ties or
wins on criterion 1 OR criterion 2"*. Triggered by TIES on both
criterion 1 (TP recall) and criterion 2 (FP count).

### Benchmark scorecard

| # | Criterion | gitleaks 8.30.1 | betterleaks 1.3.0 | Threshold to swap | Met? |
|---|-----------|------------------|---------------------|--------------------|------|
| 1 | TP recall on documented seeded secrets | 1 of 5  | 1 of 5  | `≥ gitleaks (equal → tie)` | TIE → STAY |
| 2 | FP count (in-scope)                    | 0       | 0       | `≤ gitleaks`              | TIE → STAY |
| 3 | Wall-clock median (3 runs)             | 0.53s   | 0.40s   | `≤ 0.5× gitleaks`         | NOT MET (0.75×) |
| 4 | Base64-encoded secret detection        | **YES** | **NO**  | `betterleaks detects AND gitleaks doesn't` | NOT MET — INVERTED |
| 5 | Honors `.gitleaksignore`               | yes     | yes     | `TP suppressed`           | MET |
| 6 | Honors `gitleaks:allow` inline         | yes     | yes     | `TP suppressed`           | MET |
| 7 | SARIF output equivalence               | identical | identical | `JSON-comparable rule_id/location` | MET |

Fixture: `vercel-labs/deepsec/fixtures/vulnerable-app/` at commit
`74549bbd8bef45d16c4efd5bbe8ba2c8076cab83` (44 KB, 5 documented seeded
secrets in `src/config.ts`). cparx was the A2-preferred fixture but
had no documented seeded-secret catalogue, so the benchmark fell back
to A2's named alternative — recorded in
`<host-local>/scanner-eval-2026-05-20/fixture-meta.md` (off-repo by
design — see RESEARCH.md §A5).

The most informative non-deciding signal: **criterion 4 inverted vs
RESEARCH.md A1's prediction.** A1 named "recursive encoded decoding"
as a betterleaks differentiator. In practice, gitleaks 8.30.1
decodes inline base64 to find an embedded AWS-shape access key by
default; betterleaks 1.3.0 does not surface the same encoding with
default flags, `--max-decode-depth 10`, or any of five tried
`--experiments` values. This is a credibility-positive secondary
signal for keeping the incumbent.

## Alternatives Rejected

- **SWAP to betterleaks.** Rejected — locked SWAP precondition
  required strict wins on criteria 1+2 AND at least one of {3,4,7}.
  Ties on 1+2 plus the inversion on 4 mean the SWAP threshold isn't
  reachable from this fixture's evidence.
- **REVISIT with a 90-day reminder.** Rejected — REVISIT is the
  residual case for when STAY also doesn't fire. STAY fires here, so
  REVISIT doesn't apply. A 12-month re-evaluation reminder DOES carry
  forward (see Consequences).
- **Add an opt-in betterleaks CI fragment anyway.** Rejected for the
  1.14.0 PR — Phase 20 P5 disposition follows DECISION.md: skip the
  SWAP arm, which means no new `add-observability/enforcement/secret-scan.yml.example`
  file. Downstream projects that wish to evaluate betterleaks locally
  may still do so; this ADR does not foreclose that.
- **Carry a wrapper layer that routes to either scanner.** Rejected
  in workflow-core ADR-0015 up-front; not revisited here.

## Consequences

**Positive:**

- claude-workflow's recommended CI gate is unchanged. No migration
  cost for the zero projects currently shipping a gitleaks-invoking
  template through this scaffolder (Phase 0 grep count = 0; verified
  again at P6).
- Cross-repo ADR-0015 reaches Accepted status; spec v0.4.0
  ratification is closed.
- The benchmark methodology itself becomes a reusable artifact for
  the 12-month re-evaluation and for other scanner candidates that
  may emerge.

**Negative:**

- gitleaks's base64 detection is a defensible behavior here, but it
  is not documented as a guarantee — a future gitleaks release could
  regress it. A guarantee would require either a different fixture
  strategy or a contract test embedded in this repo.
- The locked-threshold methodology is conservative by design. A 25%
  speedup (criterion 3) and one structural advantage (parallel git
  walk, claimed in workflow-core ADR-0015's Context) are not enough
  to push SWAP under this rule — by intent, but with the trade-off
  that incremental improvements don't accumulate toward a switch
  decision.

**Follow-ups:**

- 12-month re-evaluation reminder (calendar 2027-05-21): re-run the
  same 7-criterion benchmark on the then-current betterleaks
  release. Re-evaluate sooner if betterleaks ships an obvious
  inline-decoder opt-in or a published 2× speedup claim on a
  representative corpus.
- Extend the fixture set: A6 named "single-fixture risk" as a known
  threat to validity. A future re-evaluation should add at least one
  larger Go-or-TS repo (likely candidate: cparx itself with a
  hand-curated TP catalogue authored ahead of time).

## References

- Cross-repo: `agenticapps-workflow-core/adrs/0015-secret-scanner.md` —
  the upstream ADR this local ADR ratifies. Cross-repo PR captured in
  Phase 20 P4.6 commit message.
- Benchmark artifacts: `<host-local>/scanner-eval-2026-05-20/`
  (tool-versions, fixture-meta, criterion-1..7, DECISION). Intentionally
  off-repo — see RESEARCH.md §A5 for the rationale (error logs may
  contain real secret material).
- `.planning/phases/20-spec-0.4.0-absorption/RESEARCH.md` §§A1–A6 —
  pre-benchmark methodology lock.
- `.planning/phases/20-spec-0.4.0-absorption/PLAN.md` §P4 — the plan
  this ADR executes.
- gitleaks: https://github.com/gitleaks/gitleaks (v8.30.1)
- betterleaks: https://github.com/betterleaks/betterleaks (v1.3.0;
  correct upstream URL — RESEARCH.md A1's `aikidosec/betterleaks`
  was stale and 404s today).
- RFC 2119 (terminology in workflow-core ADR-0015).
