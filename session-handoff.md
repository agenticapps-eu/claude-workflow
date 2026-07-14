# Session Handoff — 2026-07-14 (Spec 0.9.0 conformance shipped — 3 PRs open)

## Status: all work built, reviewed, /cso'd, verified GREEN. 3 PRs open, awaiting merge.
Started from "check the core repo spec, did we implement all?" → full conformance audit → 7 fixes across 2 repos → shipped.

## PRs open (merge order matters)
1. **agenticapps-workflow-core#19** — `fix/spec-0.9.0-conformance` @ 9e19eb7. Spec 0.9.0: §08 amended for snapshot-install (end-state equivalence + CI guard normative), §09 gate count 15→16, ADR-0018 supersedes ADR-0013, claude-workflow ledger row → 0.9.0/full. Independent — can merge anytime.
2. **claude-workflow#82** — `feat/gitnexus-background-reindex` @ cdf6f68 (2.4.0, migration 0026). Pre-existing PR; this session pushed the /cso fix (cdf6f68). **Merge FIRST** of the two claude-workflow PRs.
3. **claude-workflow#84** — `feat/spec-0.8.0-conformance` @ efc7b4c (2.5.0, migration 0027, implements_spec 0.9.0). **STACKED on #82** (base = the gitnexus branch, not main). After #82 merges: retarget #84 to main (`gh pr edit 84 --base main`), it should apply cleanly.

## Accomplished
- **Audit** (5 parallel agents): claim was incoherent (SKILL said 0.4.0, shipped 0.7.0 features, ledger said 0.3.0, no Spec deltas). 3 real defects + 1 knowing §08 violation.
- **claude-workflow (5 tasks, subagent-driven, 2-stage reviews):** §11 now ships on the snapshot/setup path (was replay-only → fresh installs silently lost it); design-critique trigger de-inverted (fresh + existing via 0027); check-hooks.sh derives its set from settings.json + verifies event bindings; single §09 bindings table; implements_spec 0.4.0→0.9.0 + Spec deltas; §04 red flags reordered (canonical 13 at 1-13, host flag at 14) per core 0.8.0.
- **agenticapps-workflow-core:** §08 amendment, §09 count, ADR-0018, ledger row.
- **/cso on the gitnexus hook:** MEDIUM shell-injection (`sh -c` interpolated repo path) → argv-form spawn; + PID-liveness lock reclaim. Fixed on #82's branch.
- Removed dead hook `observability-postphase-scan.sh` (shipped but registered nowhere; tombstoned by 0018).

## Decisions
- **Claim 0.9.0/full, not 0.7.0/partial** — core released 0.8.0 mid-session; amending §08 upstream (rather than carrying a permanent delta) was right because opencode-workflow was independently non-conformant under old §08 too (convergent pattern, not a claude-workflow exception).
- **gitnexus lands first** — further along (only /cso remained); conformance branch stacked on it, migration 0026→0027, 2.4.0→2.5.0.
- **§11 duplication with migration 0014 accepted** — 0014 is immutable, so some duplication is unavoidable; no shared-injector refactor.

## Next session: start here
Watch the 3 PRs. Merge order: #19 (anytime) → #82 → then retarget #84 to main and merge. **AFTER #84 merges:** fast-forward `~/.claude/skills/agenticapps-workflow` (the local scaffolder clone), then `/update-agenticapps-workflow` per downstream repo to pick up 2.5.0 / migration 0027. Also: propagate the §15/§04/§08 changes to codex-workflow + opencode-workflow (their own idiom) per the ADR-0037 pattern.

## Open questions / deferred (in .superpowers/sdd/progress.md)
- **Divergent §04 copy** in `templates/.claude/claude-md/workflow.md` (reworded heading + 4 reworded flags) — disclosed as a delta, not a §09 item-1 break (canonical block IS verbatim in skill/SKILL.md). Needs its own migration to reconcile — changes every scaffolded project's payload.
- **drift-report.sh (core)** has 3 defects: greps a literal "13 Red Flags" heading (false DRIFT on legit appends), substring-matches reworded flags, AND greps gitignored scratch (caused a false PASS this session). Tracked, not fixed.
- **§13 implicit GSD trigger** still unwired (documented delta; SHOULD-level; own phase).
- Minor: setup awk END-branch diverges from 0014 (unreachable branch, byte-identity claim overstated there); §11 mirror guarded vs templates/ not the core spec.
