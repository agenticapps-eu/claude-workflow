# Phase 20 — Research

Two research streams: (a) brainstorming on the scanner evaluation
design — alternatives, threshold choices, fixture selection — and (b)
brainstorming on how to integrate the §11 injection without breaking
claude-workflow's own §12 (Lost-in-the-middle) advisory.

> Stream (a) is the input to Phase 4's pre-declared criteria table.
> Per the hand-off's "decide thresholds *before* running, not after"
> rule, this file is authored before any benchmark is executed.

---

## Stream A — Scanner evaluation design

### A1. Candidate set

Three candidates considered, two carried forward into the benchmark:

| Candidate | Status | Reason |
|-----------|--------|--------|
| `gitleaks` (Zachary Rice) | Baseline | Mature, well-tuned, status-quo recommendation in ADR 0015's Context section. |
| `betterleaks` (Aikido Security) | Challenger | Apache/MIT, gitleaks-compatible config, parallel scan, recursive encoded decoding, BPE entropy filter. ADR 0015's Context names it explicitly. |
| `trufflehog` (Truffle Security) | Rejected pre-benchmark | Different rule grammar, no `.gitleaksignore` compatibility, migration cost not bounded by the 'config-compatible' invariant ADR 0015 leans on. Open follow-up if Phase 4 outcome forces re-evaluation. |

### A2. Fixture choice

The hand-off prompt names two options:

1. **cparx pilot's seeded secrets** (`scan-report-cparx-example.md`,
   referenced in `~/Documents/Claude/Projects/agentic-workflow/pilot-cparx-2026-05-10.md`).
   Preferred if seeded secrets are still present in git history.
   Pro: real-shape fixture with known true positives; documented
   false-positive triage; reflects actual production rule-tuning.
   Con: requires verification that secrets weren't accidentally
   removed in subsequent cparx work.

2. **vercel-labs/deepsec `fixtures/vulnerable-app/`** (read-only
   clone into scratch dir). Fallback if cparx is no longer suitable.
   Pro: maintained as a vulnerability fixture; broadly known shape;
   reproducible by external reviewers.
   Con: not specific to AgenticApps' false-positive surface.

**Decision rule for fixture**: P4 verifies cparx availability first
(check for seeded secrets via gitleaks dry-run against cparx HEAD; if
≥3 known true positives still present, use cparx; else fallback).

### A3. Criteria table (pre-declared, locked before benchmark runs)

The hand-off prompt provides seven criteria. Locking thresholds here
so Phase 4 cannot rationalize:

| # | Criterion | Measurement | Threshold to favor betterleaks |
|---|-----------|-------------|--------------------------------|
| 1 | True-positive recall | Count of seeded secrets detected | ≥ gitleaks count (equal counts → tie on this row) |
| 2 | False-positive count | Count of findings *not* on the seeded list | ≤ gitleaks count |
| 3 | Wall-clock on full history | `time <scanner> detect --log-opts="--all"` | ≤ 0.5× gitleaks (median of 3 runs) |
| 4 | Base64-encoded seeded secret detection | Inject one known secret as base64 into a test file in scratch fixture; rescan | betterleaks detects AND gitleaks does not |
| 5 | Honors existing `.gitleaksignore` | Add ignore line for one known TP; rescan | betterleaks: TP suppressed (matches gitleaks behavior) |
| 6 | Honors `gitleaks:allow` inline | Add `// gitleaks:allow` comment adjacent to a known TP; rescan | betterleaks: TP suppressed |
| 7 | SARIF output equivalence | `--format sarif` on identical finding sets | JSON-comparable rule_id / location for shared findings (allow ID prefix difference) |

### A4. Decision rule (locked before benchmark runs)

Per the hand-off:

- **SWAP** (adopt betterleaks): criteria 1, 2, 5, 6 ALL met
  AND at least one of {3, 4, 7} met.
- **STAY** (keep gitleaks): gitleaks ties or wins on 1 OR 2.
- **REVISIT** (stay; 90-day calendar reminder): anything else.

Note on this PR's Phase 5: claude-workflow has no CI swap target.
"SWAP" outcome in this PR's context translates to "ADR ratified as
adopt-for-future + add opt-in CI fragment recommendation". "STAY"
translates to "ADR ratified as keep-gitleaks-status-quo + no CI
fragment added".

### A5. Artifact storage (locked)

All raw outputs to:

```
/Users/donald/Documents/Claude/Projects/agentic-workflow/scanner-eval-2026-05-20/
├── fixture-meta.md             # which fixture, why, sha
├── gitleaks-version.txt
├── betterleaks-version.txt
├── gitleaks-baseline.json      # SARIF or native JSON
├── betterleaks-baseline.json
├── gitleaks-timing.log         # time output × 3 runs
├── betterleaks-timing.log
├── criterion-1-tp.md           # rows: secret-id, gitleaks-hit?, betterleaks-hit?
├── criterion-2-fp.md
├── criterion-3-timing-summary.md
├── criterion-4-base64.md
├── criterion-5-gitleaksignore.md
├── criterion-6-inline-allow.md
├── criterion-7-sarif-diff.md
└── DECISION.md                 # outcome + which-rule-fired + ADR-0015 wording
```

This path is outside the repo because (a) it may contain real
secret material in error logs and (b) the hand-off names this
path explicitly.

### A6. Threats to validity surfaced up front

- **Single-fixture risk**: one fixture cannot generalise across all
  AgenticApps repos. Mitigation: the ADR explicitly scopes its
  ratification to the fixture used and lists "extending to N
  additional fixtures" as a 90-day follow-up.
- **Version-drift risk**: betterleaks moves fast; today's evaluation
  may not hold in 6 months. Mitigation: ADR records exact versions
  benchmarked; ratification carries an implicit 12-month half-life.
- **Author-bias risk**: betterleaks is by ex-gitleaks maintainers,
  so betterleaks may favor gitleaks-shape findings. Mitigation:
  criterion 4 (base64 encoded) specifically probes the
  capability-superset claim that motivates the swap; this is a
  feature betterleaks claims and gitleaks does not.
- **Benchmark gaming**: I author the criteria before benchmarking,
  so post-hoc threshold-tuning is structurally prevented. Locked.

---

## Stream B — §11 injection without breaking §12's placement advisory

### B1. The tension

§12's advisory: "Long prose paragraphs critical to runtime behavior
should appear early in their containing file ... because models
systematically underweight content buried in the middle of long
contexts." It explicitly names §11 placement: "The §11 canonical
block lives near the top of CLAUDE.md / AGENTS.md / equivalent — not
appended below long appendices."

claude-workflow's host has TWO CLAUDE.md instances to think about:

1. **The host repo's own root `CLAUDE.md`** (if it exists). Phase 0
   should grep — TODO before P1.
2. **The scaffolded project-template CLAUDE.md** that init / update
   stamp into newly-set-up downstream projects.

For (2), the template already has structure — the question is *where*
inside the template the §11 block goes.

### B2. Anchor design

Migration 0014 needs a stable anchor for idempotent re-application.
Candidates considered:

| Anchor design | Pro | Con | Decision |
|---------------|-----|-----|----------|
| `## Coding Discipline (spec §11)` heading | Stable, descriptive, includes spec citation | Heading text might collide with existing host headings | **Chosen** — section name is unique enough to be collision-free |
| HTML-comment fence `<!-- BEGIN: spec-11 -->` / `<!-- END: spec-11 -->` | Maximally machine-detectable; safe against heading drift | Less human-discoverable; not idiomatic for the existing CLAUDE.md style | Rejected — §11 itself uses prose anchors, not fence comments |
| Hash-of-content marker | Tamper-detectable | Brittle across spec revisions; defeats the purpose of "update spec → re-inject" | Rejected |

**Combined approach (final)**: heading anchor + provenance HTML
comment ON THE LINE INSIDE the section. The HTML comment carries
the spec source version for drift-detection:

```markdown
## Coding Discipline (spec §11)
<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->

[verbatim block from spec/11-coding-discipline.md lines 26–102]
```

Detection logic in 0014:
- If `## Coding Discipline (spec §11)` heading is absent → insert.
- If heading present + HTML-comment version matches current spec
  version → no-op.
- If heading present + HTML-comment version is older → replace
  section content (preserving anchor + comment with new version).
- If heading present + no HTML-comment → STAGE: refuse with
  "manual conflict — section exists but is not under spec-11
  management". User resolves.

### B3. Placement within the file (per §12 advisory)

Insertion point in newly-init'd project CLAUDE.md: **immediately
after the project preamble (project name + 1-2 sentence purpose
statement), before any GSD / workflow scaffolding sections**. This
honors §12's "near the top" guidance.

For the host's own CLAUDE.md (if present), same rule — insert near
the top, after preamble.

For an EXISTING downstream project CLAUDE.md being updated:
**preserve user content above the insertion point; only the §11
section moves**. Migration 0014 does not reflow surrounding text.

### B4. Verbatim verification

§11's conformance requirement is byte-identical reproduction. The
migration's apply step must:

1. Extract bytes from `spec/11-coding-discipline.md` between
   `## Canonical block` heading and the next `## ` heading. (The
   §11 file uses `````` quad-backtick fence around the block, so the
   apply step extracts inside-fence content.)
2. Inject without modification — no whitespace normalisation, no
   line-ending coercion (preserve LF if source is LF).
3. Verification gate after apply: `diff <(extract from spec)
   <(extract from injected CLAUDE.md)` produces empty output.

This `diff` command is the evidence row for G1.

### B5. Source-of-truth path resolution

The migration needs to find `spec/11-coding-discipline.md` from
wherever it runs (host repo, downstream project, scaffolder install).
Options:

- **Read from globally-installed scaffolder bundle** —
  `$HOME/.claude/skills/agenticapps-workflow/...` — but the
  scaffolder bundle ships claude-workflow, not workflow-core's spec.
- **Vendor the §11 block into claude-workflow** — store a copy at a
  known path inside claude-workflow's scaffolder bundle, with a
  version stamp matching workflow-core's release.
- **Fetch from a known location** — network fetch, brittle.

**Chosen**: vendor. Add `spec-blocks/11-coding-discipline.txt` (or
similar — final path decided in P1) inside the scaffolder bundle.
Migration 0014 reads from there. Updates flow: when workflow-core
ships a new spec version, claude-workflow re-vendors the block and
ships a new migration (or, more likely, updates the vendored block
in place at the next minor version bump). Drift detection in
migration 0014 references the vendored block's version stamp.

---

## What this research enables

- P1 can proceed with anchor design B2, placement rule B3,
  verbatim-verification B4, and vendoring approach B5 locked.
- P4 can proceed with criteria A3 and decision rule A4 locked
  before any scanner runs.

## What's still open

- Path resolution for vendored §11 block (B5) — exact path under
  the scaffolder bundle. P1 picks this; precedent suggests
  `skill/spec-blocks/11.md` or `spec-mirrors/11-coding-discipline.md`.
- ts-declare-first skill's chosen host path (CONTEXT.md OQ2).
- Scaffolded-project CLAUDE.md path (CONTEXT.md OQ1).
- Fixture choice for scanner benchmark (A2 — verified at P4 start).
