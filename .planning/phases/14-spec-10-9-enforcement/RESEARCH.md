# Phase 14 — RESEARCH — Design alternatives for §10.9 enforcement layer

> Per `superpowers:brainstorming` discipline, every non-obvious decision lists ≥ 2 alternatives, the trade-offs, and a recommended choice with rationale. Decisions made in CONTEXT.md (slot 0011, version 1.10.0, scope cut) are not re-litigated here.

## D1 — Machine-readable summary format for delta scan (§10.9.1 MUST)

**The obligation**: "alongside the human-readable scan report, a machine-readable summary of the delta's high-confidence-gap count" — so the CI gate can compare without parsing markdown.

| Option | Pros | Cons |
|---|---|---|
| **A. Baseline file is the summary.** `baseline.json` is rewritten on every scan (full and delta) and is what CI diffs. | Single artefact serves §10.9.1 + §10.9.2. No new file. Spec already mandates baseline; piggybacking is zero-cost. | A delta scan against, say, only test files would zero the baseline counts because no source files are walked. **Wrong**: deltas must not silently overwrite the full-scan baseline. |
| **B. Separate `.observability/delta.json` for delta runs.** Full scan writes baseline.json; delta scan writes delta.json with `since_commit` + per-file-walked + counts. CI diffs delta.json's counts against baseline.json. | Conceptually clean. Baseline never accidentally regresses from a partial walk. | Two artefacts. Risk of drift between them (e.g. CI reads stale delta.json). |
| **C. Delta scan writes neither; emits machine-readable summary to STDOUT as JSON the CI captures.** | Stateless. No file to commit/gitignore. | Mismatch with §10.9.2 "MUST update the baseline whenever scan-apply successfully modifies code" — that's a file-on-disk obligation that already exists. Adding a STDOUT-only second channel for §10.9.1 is more surface area, not less. |
| **D. Delta scan writes `.observability/delta-<sha>.json` (per-PR-commit, gitignored).** | CI reads exactly what the scan emitted; baseline never touched on delta runs. | One throwaway file per PR commit. Names accumulate. Needs gitignore entry. |

**Recommendation**: **B**. The "delta scans must not silently overwrite the full-scan baseline" hazard from option A is real and concretely catchable — a developer running `scan --since-commit foo` should not lose their baseline. Two files is cheap; the schemas are similar (delta.json has the extra `since_commit` + file list and lacks `module_roots`). CI diffs `counts.high_confidence_gaps` between the two. **Update**: re-reading §10.9.1 — *"alongside the human-readable scan report"* and the §10.9.2 mandate is *"update the baseline whenever scan-apply successfully modifies code"* + *"manual override (scan --update-baseline) that recomputes the baseline without applying"*. The spec actually distinguishes: regular `scan` runs do NOT have to rewrite the baseline. Only `--update-baseline` does. That makes option **A as written in the hand-off prompt incorrect** — hand-off says "Phase 7: write baseline if full scan OR `--update-baseline`". The spec only requires baseline write on `--update-baseline` (manual) and after successful `scan-apply` (automatic). **Final**: delta scans write `.observability/delta.json` (option B); full `scan` runs read but don't rewrite baseline; only `scan --update-baseline` and `scan-apply` success rewrite baseline. This corrects a spec-vs-handoff divergence — flag in PLAN.md.

## D2 — CI gate threshold: fail on increase in high only, or include medium?

**The obligation**: §10.9.3 says "Compares the delta scan's high-confidence-gap count against the baseline. Fails the PR if the count increases." High-only is explicit; medium is unspecified.

| Option | Pros | Cons |
|---|---|---|
| **A. Fail on high only.** Spec-direct. Medium is a count surfaced in baseline but not gated. | Zero false positives. Medium findings are by definition heuristic (probable business event by name) — gating on them produces noise. | Misses cases where a PR genuinely doubles the medium-count of probable un-instrumented business events. |
| **B. Fail on high; warn on medium.** Two-tier — PR fails on high, comment notes medium delta. | Surface info without hard-fail noise. | Comment becomes routine; reviewers may train themselves to ignore it. |
| **C. Configurable threshold via baseline.json field.** `gate.thresholds.high: strict`, `gate.thresholds.medium: warn`. | Future-proof. | Adds schema surface for a feature nobody has asked for. Premature flexibility. |

**Recommendation**: **A** at v1.10.0; revisit in v1.11.0 if real projects ask for B. Matches the hand-off's recommendation. Predictable + zero false positives is the right default when introducing the gate.

## D3 — Standalone Node scanner port for CI

**The obligation**: §10.9.3 CI workflow ships, but Claude Code's CI installation story is not fully supported in 2026-05. Until it is, the reference workflow at `ci/observability.yml` cannot run on a generic GHA runner.

| Option | Pros | Cons |
|---|---|---|
| **A. Defer Node port to v1.11.0.** Ship the GHA template at v1.10.0; document the limitation; users with self-hosted runners can run it today, others run delta-scan locally pre-PR. | Aligns with §10.9.3 ("each host SHIPS a reference workflow") without forcing a parallel implementation. Keeps v1.10.0 scope bounded. | The shipped workflow at v1.10.0 doesn't run for most users until v1.11.0. |
| **B. Build the Node port in this phase.** Pack a `tools/observability-scanner/` Node CLI that re-implements the scan procedure in JavaScript. | CI works out of the box at v1.10.0. | Forks the scanner: two implementations, two test suites, drift over time. Spec procedure → Node procedure translation is non-trivial because the scan currently uses Claude tool calls (Read, Grep, Glob). A pure-Node implementation needs to re-implement those against ripgrep + fs. Estimate: 3-5 days. |
| **C. Run the scanner in a Docker image with Claude Code preinstalled.** CI step builds/pulls the image and runs the scan inside. | No port needed. | Needs an Anthropic API key in CI secrets. Cost per PR. Latency. Image must be maintained. |

**Recommendation**: **A** — defer Node port to v1.11.0. The hand-off recommends this and matches the spec's "each host SHIPS a reference workflow" phrasing — shipping a workflow that documents its dependency on Claude-Code-in-CI satisfies the SHOULD; the gap is in Claude Code's CI story, not in this skill. Track as issue: open one as part of Phase 14 close.

## D4 — Baseline file location and gitignore policy

**The obligation**: §10.9.2 says "committed alongside `policy.md` so its values track the project's history." That implies *not* gitignored.

| Option | Pros | Cons |
|---|---|---|
| **A. Commit baseline.json.** Per spec. CI on `push` to main updates the baseline; PR CI reads `git show base.sha:.observability/baseline.json` to diff against. | Baseline lives with the code. Audit trail = git history of baseline.json. | Merge conflicts on baseline.json are mechanical (counts) but routine — they happen on every PR after another lands. |
| **B. Gitignore baseline.json; store it in CI artifacts or a remote S3-like.** | No merge conflicts. | Breaks the §10.9.2 "committed alongside policy.md" expectation. Adds remote storage as a dependency. |
| **C. Commit baseline.json but stamp it `auto-generated; merge with --strategy=ours`**. | Spec-conformant. Conflicts resolved automatically. | Requires `.gitattributes` setup. Users unfamiliar with merge strategies may be surprised. |

**Recommendation**: **A** at v1.10.0. Conflicts will be mostly mechanical (count fields). If real usage shows it's painful, the v1.11.0 follow-up is C, not B. Note in `ci/README.md` that mid-PR rebases against main may require baseline regeneration via `scan --update-baseline` and re-commit.

## D5 — `module_roots` ordering stability

The baseline JSON's `module_roots` array isn't naturally ordered. If `scan` re-scans and emits module roots in a different order, the diff (and any tooling diffing baselines) flags churn that isn't real.

| Option | Pros | Cons |
|---|---|---|
| **A. Sort `module_roots` alphabetically by `path`.** Deterministic order. | Trivial. Eliminates spurious diffs. | Loses any "primary stack first" semantic if SCAN's detection ever cared (it doesn't today). |
| **B. Preserve detection order.** Whatever order SCAN walks templates/* in. | No code change. | Order depends on filesystem semantics; not reliable. |
| **C. Two-key sort: `stack` then `path`.** Same outcome as A in current data, more stable if multiple modules share a stack. | Slightly more deterministic for monorepos with N>1 of the same stack. | Marginal. |

**Recommendation**: **C** — sort by `(stack, path)`. Costs nothing, future-proofs monorepos. Codify in SCAN.md Phase 7.

## D6 — `policy_hash` computation method

Spec §10.9.2: `"policy_hash": "sha256:<hash of policy.md>"`. Two readings.

| Option | Pros | Cons |
|---|---|---|
| **A. Hash the raw bytes of `<wrapper-dir>/policy.md`.** Single file. | Trivially computed in any host (POSIX `shasum -a 256`). Stable across line-ending normalization if policy.md ships LF-only. | Doesn't account for trailing whitespace or trailing newlines — a no-op edit that re-saves the file changes the hash. |
| **B. Hash the content after normalising trailing whitespace + final newline.** | More resilient to no-op edits. | One more processing step. Host-dependent normalisation = drift risk. |
| **C. Hash the parsed-out "Trivial errors" section only.** | Only the load-bearing content of policy.md affects the hash. Tested. | Requires parsing the markdown; brittle if policy.md structure changes. |

**Recommendation**: **A** — sha256 of raw bytes. Simplest, host-portable, the spec gives no guidance on normalisation. If a no-op edit triggers a CI warning, that's not a real problem — re-running scan resolves it.

## D7 — How to authenticate the initial baseline in migration 0011

The migration must produce the project's *first* baseline. Two paths.

| Option | Pros | Cons |
|---|---|---|
| **A. Migration invokes `claude /add-observability scan --update-baseline` directly.** | One command. End-to-end automated. | The migration is a markdown file consumed by another agent; it can't itself invoke claude. The Apply block would say "run this" and the consuming agent invokes the skill. Works in setup/update skill context, may not work in CI. |
| **B. Migration ships a static placeholder baseline (zeros) and a follow-up step prompts the user to run `scan --update-baseline` manually.** | Migration is purely declarative — no embedded sub-skill invocation. CI gate works immediately (any new gap fails the build, since baseline is zeros — strict). | "Strict from day 1" may flag legacy code as PR regression when the dev just hasn't run init. Surprising. |
| **C. Migration runs the scan procedure inline (as text) and the consuming agent (Claude Code applying the migration) follows it.** | Same as A but explicit about the chain. | Same constraint; only works in agent-driven setup/update flows. |

**Recommendation**: **A** — the migration's Apply block instructs the consuming Claude session to invoke the skill's `scan --update-baseline` after the file-copy steps. This matches how migration 0002 wires the init step, and matches how setup/update skills already work. Document the failure mode (project without conforming stack) in the migration's Skip cases.

## D8 — Migration sequence and chain protocol

The chain extends from 0007 (1.9.2 → 1.9.3). Two slot choices.

| Option | Pros | Cons |
|---|---|---|
| **A. New migration at slot 0011, 1.9.3 → 1.10.0.** Next free sequential ID. | Conforms to "pick the next free sequential ID" guidance in README. Continues the chain. | None — it's the documented protocol. |
| **B. Backfill slot 0003 for spec coverage symmetry (0002 = spec 0.2.1, 0003 = spec 0.3.0).** | Tells a clean story by ID. | IDs are sequential not thematic per README §"Application order" — "IDs and versions can be out of sync". Breaks the convention to reuse a historical gap. |

**Recommendation**: **A**. Slot 0011, `1.9.3 → 1.10.0`. Codifies the protocol.

## D9 — Open questions to surface during PLAN.md and at PR time

1. **No-stack project handling**: a project that runs the migration without having previously run `init` has no `lib/observability/policy.md`. `policy_hash` is undefined. **Resolution**: baseline.json's `policy_hash` field becomes `null` (not `"sha256:0"`); CI workflow tolerates null and skips the policy-drift check; document in baseline schema notes. **Defer to PLAN.md Task implementation.**

2. **fx-signal-agent dogfood**: the hand-off explicitly defers retroactive enforcement application to fx-signal-agent ("not in scope"). After v1.10.0 merges, fx-signal-agent's next maintenance window adopts the migration. **Defer to next session-handoff.**

3. **Dashboard read of baseline.json**: the agenticapps-dashboard already exists (per family CLAUDE.md). Reading baseline.json to render a project's conformance posture is a dashboard-side change. **Out of scope for this phase**; tracked as follow-up.

## Decision log summary

| Decision | Recommendation |
|---|---|
| D1 — machine-readable summary format | **B** + spec-correctness pass: delta writes `.observability/delta.json`; baseline regen ONLY on `--update-baseline` or successful `scan-apply` |
| D2 — CI gate threshold | **A** — high only at v1.10.0 |
| D3 — Node scanner port | **A** — defer to v1.11.0 |
| D4 — baseline gitignore | **A** — commit per spec |
| D5 — module_roots ordering | **C** — sort by `(stack, path)` |
| D6 — policy_hash method | **A** — raw bytes sha256 |
| D7 — initial baseline in migration | **A** — migration Apply block instructs skill invocation |
| D8 — migration slot | **A** — slot 0011, 1.9.3 → 1.10.0 |
| D9 — open questions | three follow-ups deferred to PLAN.md / next session / out-of-scope |
