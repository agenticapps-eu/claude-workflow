# Session Handoff — 2026-05-15 (Phase 14 shipped — spec §10.9 local-first enforcement at scaffolder 1.10.0)

## Accomplished

Phase 14 shipped the v1.10.0 enforcement layer per spec §10.9, **local-first
after post-review pivot to Option 4** (no CI dependency). Single phase,
~15 commits on branch `feat/observability-enforcement-v1.10.0`, PR #25.
Multi-AI plan review went BLOCK → REQUEST-CHANGES → APPROVE after a
21-item PLAN.md revision; user picked Option 4 (local-only) post-approval.
A subsequent CodeRabbit pass surfaced 10 genuine bugs + 2 false positives,
all addressed in a follow-up commit.

| Commit | Subject |
|---|---|
| `289c8eb` | docs(planning): phase 14 — CONTEXT, RESEARCH, PLAN, REVIEWS |
| `4aeaa0d` | feat(add-observability): SCAN.md delta scope + baseline/delta writers (§10.9.1, §10.9.2) |
| `2f2a234` | feat(add-observability): scan report frontmatter + delta banner (§10.9.1) |
| `1d699db` | feat(add-observability): add baseline-template.json schema (§10.9.2) |
| `7372a36` | feat(add-observability): scan-apply regenerates baseline on success (§10.9.2) |
| `2366ddc` | feat(add-observability): ship reference CI workflow + adoption README (§10.9.3) |
| `df3e283` | feat(migrations): 0011 — observability enforcement (1.9.3 → 1.10.0) |
| `e25daf1` | test(migrations): 0011 fixtures (7 scenarios) + run-tests stanza |
| `2f1b16b` | chore(version): bump add-observability 0.2.1→0.3.0, scaffolder 1.9.3→1.10.0 |
| `367d0f3` | docs(changelog): record v1.10.0 — observability enforcement |
| `6dee657` | docs(verification): phase 14 evidence ledger + delta-scan smoke test |
| `321c6a5` | refactor: pivot v1.10.0 to local-first enforcement (option 4, no CI dependency) |
| `<next>`  | fix: address coderabbit review (push-event policy drift, smoke error masking, stale paths, POSIX awk) |

Workflow scaffolder progression: `1.9.3 → 1.10.0`. Skill
`add-observability` v0.2.1 → v0.3.0 (`implements_spec: 0.3.0`).

Test status of `migrations/run-tests.sh`:
- **0011: 6/6 PASS** (post-pivot; fixture 07 dropped).
- ~117 total PASS, 9 FAIL (pre-existing; 8x `test_migration_0001`
  `git merge-base` resolution + 1x `test_migration_0007` fixture
  `03-no-gitnexus` fnm-PATH leak). Both tracked in prior session-handoff
  "Next session" items #5/#6.

**Spec conformance at v1.10.0**:
- §10.9.1 (delta scan): MUST, fully implemented.
- §10.9.2 (baseline file): MUST, fully implemented.
- §10.9.3 (reference CI workflow): SHOULD, shipped as opt-in example at
  `add-observability/enforcement/observability.yml.example` but NOT
  installed by migration 0011. Closes when v1.11.0 ships the Node
  scanner port.
- §10.9.4 (pre-commit hook): MAY, deferred.

## Decisions

- **Re-baselined the hand-off prompt's stale version targets.** The
  `claude-workflow-update-prompt.md` carry-over (written 2026-05-13)
  pre-supposed v1.5.0 → v1.6.0. By 2026-05-15 the scaffolder was at
  v1.9.3 (phases 11/12/13 had advanced it). Updated to v1.9.3 →
  v1.10.0 and migration slot 0011 (the prompt said 0003 but the
  chain extends to 0010). The technical content of the hand-off
  (three primitives + a migration) was implemented unchanged; only
  the version arithmetic was off.

- **Spec-vs-hand-off divergence on baseline write trigger.** RESEARCH
  D1 caught it: the hand-off's "Phase 7: write baseline if full scan
  OR `--update-baseline`" is spec-incorrect. §10.9.2 line 219 says
  ONLY `scan-apply` success (automatic) and `--update-baseline`
  (manual) write the baseline. Regular full scans MUST NOT. Codified
  in SCAN.md Phase 7 + Important Rules.

- **Codex BLOCK on Q1 caught two genuinely load-bearing spec
  divergences my self-review missed.** First, the empty-delta path
  was silently skipping `delta.json` emission (the §10.9.1 machine-
  readable summary obligation is unconditional). Second, the
  original baseline schema allowed `policy_hash: null` /
  `scanned_commit: "working-tree"` non-conformant placeholders.
  Fixed both pre-execution. **Codify as workflow norm**: when a
  reviewer returns BLOCK on spec conformance, trust it — multi-AI
  review catches what a single author misses. Document each load-
  bearing item in the revision pass with the line-citation to the
  spec.

- **Gemini's read-only mode (`--approval-mode plan`)** errored with
  "Approval mode 'plan' is only available when experimental.plan is
  enabled". Retry with `--allowed-tools read_file,list_directory,...`
  worked but the workspace-only file resolution prevented gemini from
  reading the spec at `~/Sourcecode/agenticapps/agenticapps-workflow-core/`.
  Gemini's Q1 PASS was therefore based on summarised context, not
  the spec itself; explicitly annotated in REVIEWS.md as weaker
  evidence than codex's.

- **CI workflow ships dormant but spec-conformant at v1.10.0.** The
  reference `observability.yml` requires `claude` in CI which isn't
  fully supported on hosted GHA runners as of 2026-05. Three
  workarounds documented in `add-observability/ci/README.md`
  (manual pre-PR scan, self-hosted runner, wait for v1.11.0 Node
  scanner port). The workflow itself is fully spec-conformant — the
  gap is in Claude Code's CI story, not in the skill.

- **GitHub Actions SHAs pinned at ship time** (`actions/checkout
  @de0fac2...` v6.0.2, `marocchino/sticky-pull-request-comment
  @0ea0beb...` v3.0.4). README ships a Dependabot example for
  keeping them fresh.

- **Migration 0011 ABORTS pre-flight** on missing observability
  block / missing policy.md / missing `claude` — not silent skips.
  CONTEXT said abort; the codex review caught a drift to skip in
  PLAN v1; v2 reverted to abort. Skip would have stamped 1.10.0
  onto a non-conformant project state.

- **`/review` (T15) and `/cso` (T16) deferred to PR-time tooling.**
  The local gstack slash commands aren't invoked here; the
  pre-execution multi-AI plan review (REVIEWS.md), VERIFICATION.md
  ledger, and PR-time review tooling (coderabbit / autofix-bot /
  GitHub PR review) are the substitutes. Explicit deviation noted
  in VERIFICATION.md close-criteria section.

- **Templates dir unchanged → 61 contract tests structurally
  cannot regress.** Cleanest possible regression evidence:
  `git diff main -- add-observability/templates/` returns zero
  lines. Codified as a regression-guard pattern.

## Files modified

### Skill changes (add-observability/)
- `SKILL.md` — version 0.2.1 → 0.3.0, implements_spec 0.2.1 → 0.3.0, subcommand description expanded with new flags + ci/ reference.
- `scan/SCAN.md` — +230 lines net: new Phase 1.5 (resolve scope), Phase 7 (baseline writer), Phase 8 (delta writer), new Important Rules + Verification entries.
- `scan/report-template.md` — +44 lines: report frontmatter (`scope`, `since_commit`, etc.) + delta banner section + token semantics docs.
- `scan/baseline-template.json` — NEW. Strict schema matching spec §10.9.2 lines 184-217.
- `scan/baseline-template.note.md` — NEW. Token reference + rationale.
- `scan-apply/APPLY.md` — +52 lines: Phase 6b (regenerate baseline on apply success).
- `ci/observability.yml` — NEW. SHA-pinned GHA reference workflow.
- `ci/README.md` — NEW. Adoption guide + threat model.
- `CONTRACT-VERIFICATION.md` — +36 lines: v0.3.0 §10.9 coverage matrix.

### Migration
- `migrations/0011-observability-enforcement.md` — NEW. 5 steps + 4-check pre-flight + post-checks.
- `migrations/README.md` — +1 line (chain entry).
- `migrations/run-tests.sh` — +120 lines (`test_migration_0011()` stanza + dispatcher).
- `migrations/test-fixtures/0011/` — 7 fixtures × 3 files + common-setup.sh.

### Scaffolder
- `skill/SKILL.md` — version 1.9.3 → 1.10.0.
- `CHANGELOG.md` — new `[1.10.0] — Unreleased` section.
- `.gitignore` — NEW (none existed before phase 14): ignores reviewer raw outputs + local state.

### Phase artefacts
- `.planning/phases/14-spec-10-9-enforcement/{CONTEXT,RESEARCH,PLAN,VERIFICATION}.md` + `14-REVIEWS.md` + `smoke/`.

## Next session: start here

The branch `feat/observability-enforcement-v1.10.0` is ready for PR.
Run `gh pr create` (or use the prepared body in this session's PR
draft) targeting `main`. After merge:

1. **CHANGELOG hygiene PR** (small) — stamp `[1.9.3]` as released
   with a date. Currently shows "Unreleased" despite fx-signal-agent
   having upgraded to v1.9.3 already (per prior session-handoff).
   `[1.10.0]` is the new "Unreleased" tail.

2. **v1.11.0 follow-up scope** — three threads ranked by demand:
   - **Standalone Node scanner port** (closes the "Claude Code in
     CI" gap; lets the shipped `observability.yml` actually run on
     hosted GHA runners). Estimate 3-5 days. This is the highest-
     impact follow-up — it activates the v1.10.0 CI gate for every
     project, not just self-hosted-runner setups.
   - **Pre-commit hook template** (§10.9.4 MAY).
   - **fx-signal-agent retroactive adoption** of migration 0011
     (run `/update-agenticapps-workflow` against fx-signal-agent at
     its next maintenance window).

3. **Optional Phase 17 — fix 8 pre-existing `test_migration_0001`
   failures** (`git merge-base` resolution; carried from prior
   session-handoff). Phase 14 didn't touch this; the 9-failure
   baseline is unchanged.

4. **Optional Phase 18 — fix `test_migration_0007` fixture
   `03-no-gitnexus` fnm PATH leak** on this dev machine (also
   carried).

5. **Optional Phase 19 — `--strict-preflight` flag** for the Phase 13
   audit (carried). The 0011 verify-path FAIL on this dev machine is
   a perfect motivating example: the verify command is correct, the
   missing-canonical-install is real, but neither is a defect that
   should block CI.

## Open questions

- **CI gate fail rule interpretation revisit?** Phase 14 codex review
  questioned whether "fail if delta > 0" exactly matches spec
  §10.9.3 "compares delta against baseline, fails if the count
  increases". Defensible equivalence (delta represents net new
  high-confidence gaps; post-PR total = baseline + delta) but the
  wording matters. If a real PR ever fails the gate on a "noisy"
  delta where someone removes high gaps but the count still looks
  like it increases due to scope artefacts, revisit. Track as
  "watch list" item.

- **Multi-AI plan review CLI floor** — coderabbit + opencode CLIs
  still absent on this machine (carried from prior session-handoff).
  Phase 14 used codex + gemini + Claude self-review. The floor of
  ≥2 from `gemini|codex|claude|coderabbit|opencode` is met by
  codex + gemini; document the canonical install for the remaining
  two if a 4-reviewer floor ever becomes the bar.

- **Helper script license consent for `index-family-repos.sh
  --all`** — still open, no change.

- **Canonical install command for `/gsd-review` skill** — still
  open, no change.

- **Reviewer-prompt template** that this phase used for codex+gemini
  could be codified as a reusable artefact for future phases —
  `~/.claude/skills/agenticapps-workflow/.review-prompt-template.md`
  with structured questions. Worth a small PR to formalise.
