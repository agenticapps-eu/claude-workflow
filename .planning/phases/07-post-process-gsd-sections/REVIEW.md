# Phase 07 — REVIEW.md

## Stage 1 — Spec compliance (pr-review-toolkit:code-reviewer agent)

Scope: `git diff feat/vendor-claude-md-sections-0009..HEAD` (3 commits: RED
tests, GREEN script, packaging). Excludes unstaged changes in
`templates/config-hooks.json` and `docs/ENFORCEMENT-PLAN.md` (those are
ADR-0018 work, not phase 07).

### Method

1. Cross-checked every PLAN.md Step + CONTEXT.md Decision (A–G) against the diff.
2. Re-ran `bash migrations/run-tests.sh 0010` and the full harness — confirmed
   counts independently rather than trusting VERIFICATION.md.
3. Re-ran the end-to-end cparx simulation from VERIFICATION.md "End-to-end
   measurement" — confirmed 647 → 521 → 278 numerically.
4. Cross-checked ADR 0022's code-location citations against
   `/Users/donald/.claude/get-shit-done/bin/lib/profile-output.cjs`.
5. Verified rollback / idempotency-check correlation in the migration markdown
   against 0009's pattern.

### Verification of VERIFICATION.md claims

| Claim | Re-verified? | Notes |
|---|---|---|
| `bash migrations/run-tests.sh 0010` → 7 PASS | YES (re-ran) | Output matches VERIFICATION.md line 130–141 byte-for-byte. |
| Full harness → 57 PASS / 8 FAIL | YES (re-ran) | The 8 FAILs are all in `test_migration_0001` (`Step 1`–`Step 10` "needs apply on v1.2.0" checks). Pre-existing per session-handoff. Not introduced by 0010. |
| cparx end-to-end: 647 → 521 → 278 | YES (re-ran) | Reproduced exactly. `wc -l` output: 647 → sed-delete 154–285 + appended 6-line ref → 521 → script → 278. |
| `cparx-shape` fixture at 147L (≤ 200L) | YES (re-ran) | Fixture input 339L; script output 147L. |
| Bash 3.2 compatibility | YES (re-ran) | `/bin/bash --version` reports 3.2.57 on this macOS; harness PASSes under `/bin/bash`. |
| Hook 6 in `templates/claude-settings.json` parses cleanly | YES (visual + harness) | jq-shaped object, valid JSON. |
| ADR 0022 cites `buildSection` line 236 | YES | Matches `profile-output.cjs:236`. |
| ADR 0022 cites `extractSectionContent` line 226 | YES | Matches line 226. |
| ADR 0022 cites `hasMarkers` line 978 | YES | Matches line 978. |
| ADR 0022 cites `detectManualEdit` lines 257–262 + 980–991 | YES | Definition at 257; normalize logic at 260; auto-branch at 981–990. |
| ADR 0022 cites `--auto` at `cmdGenerateClaudeMd()` line 981 | PARTIAL | `cmdGenerateClaudeMd` is at line **911**, not 932. Line 981 is the `if (options.auto)` check inside that function. The 932 reference in CONTEXT.md/PLAN.md is `bin/gsd-tools.cjs` line 932 (the subcommand router), which is correct. ADR text reads as expected after careful parsing. |
| ADR 0022 cites `updateSection` "line 252" (overwrite-unconditional) | MINOR INACCURACY | Line 252 is inside `updateSection` (the `'replaced'` branch return). The call site that "runs regardless" is line 992 (and 995 for the append branch); the function definition is line 244. NIT-level. |
| ADR 0022 cites `updateSection` "appended" branch line 254 | YES | Line 254 is exactly `return { content: ..., action: 'appended' }`. |
| 0009 / 0010 boundary table | YES | All four shapes are correctly attributed. Verified by inspection of 0009's outputs (no `<!-- GSD: -->` markers) and 0010's regex `^<!--[[:space:]]*GSD:([a-z]+)-start` (cannot match plain markdown). |

### Plan → diff mapping (Steps 1–5)

| PLAN Step | CONTEXT Decision | Artifact in diff | Verdict |
|---|---|---|---|
| Step 1 — add post-processor script | Decision B + C | `templates/.claude/hooks/normalize-claude-md.sh` (216L, executable, sentinel header line 2) | DELIVERED |
| Step 2 — vendor into consumer projects | Decision C | Migration 0010 Step 1: `cp ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh .claude/hooks/normalize-claude-md.sh`; chmod +x; rollback `rm -f` | DELIVERED |
| Step 3 — register hook in `claude-settings.json` | Decision C | Migration 0010 Step 2 (jq insert with hand-edit fallback) **AND** scaffolder-level edit to `templates/claude-settings.json` adding "Hook 6" PostToolUse block | DELIVERED |
| Step 4 — one-shot normalize existing CLAUDE.md | Decision D | Migration 0010 Step 3 with diff preview + A/B/C user prompt | DELIVERED |
| Step 5 — bump scaffolder version | (packaging) | `skill/SKILL.md` 1.8.0 → 1.9.0 (scaffolder side); migration's Step 4 bumps consumer's `.claude/skills/agentic-apps-workflow/SKILL.md` | DELIVERED |

### Decision A–G compliance

| Decision | Spec | Diff delivers | Verdict |
|---|---|---|---|
| A — source identification | upstream `gsd-tools` traced to `profile-output.cjs:236`, owned by `pi-agentic-apps-workflow` family | ADR 0022 Context section captures all findings with line numbers | DELIVERED |
| B — post-processor design | self-closing form + heading + reference link; source-existence safety; idempotent; scope-guard regex; special-case workflow + profile | Script `resolve_source_path()` lines 40–53 (mapping table); `build_replacement()` lines 74–124 (workflow/profile special cases at 80–99; mapping path at 102–123); regex anchor at line 146; `collapse_blank_runs` at 196–200 | DELIVERED |
| C — install point | `templates/.claude/hooks/normalize-claude-md.sh` + PostToolUse hook on `Edit\|Write\|MultiEdit` | Script at the spec'd path; Hook 6 in `templates/claude-settings.json:42-51` | DELIVERED |
| D — one-shot + ongoing | both | Migration Step 3 (one-shot with diff preview); Hook 6 (ongoing) | DELIVERED |
| E — interaction with 0009 | 0010 regex cannot match 0009's output (plain markdown, no `<!-- GSD: -->`) | Fixture `with-0009-vendored` exercises this; harness asserts diff against expected; PASS | DELIVERED |
| F — coverage matrix | target ≤200L on cparx; estimate ~250L | Empirical: 278L on real cparx; 147L on `cparx-shape` fixture. **Target missed by 78L on real cparx.** | PARTIAL — see Findings F-1 below |
| G — verification fixtures | 5 fixtures: `fresh`, `inlined-7-sections`, `inlined-source-missing`, `after-normalized` (idempotency), `cparx-shape` | Diff ships 5 fixture dirs: `fresh`, `inlined-7-sections`, `inlined-source-missing`, `with-0009-vendored` (substitutes for `after-normalized`), `cparx-shape`. Idempotency is tested as a separate scenario (re-running `inlined-7-sections`), not a standalone fixture dir. | DELIVERED with naming variation — see Finding NIT-2 |

### Findings

#### BLOCK

(none)

#### FLAG

**FLAG-1** | `templates/.claude/hooks/normalize-claude-md.sh:107-118` + `migrations/test-fixtures/0010/inlined-source-missing/CLAUDE.md:7` + `PLAN.md:21` | **Source-existence safety guard at lines 115–118 is untested.** The threat-model row "Script deletes content when source file is missing" claims coverage via `inlined-source-missing.md`. But that fixture uses `source:NONEXISTENT.md`, which has no entry in `resolve_source_path()`'s case statement — so it hits the **unmapped-label** branch at line 107–109 (empty `link_path` → `return 1` → preserve), not the **mapped-label-but-file-missing** branch at line 115–118 (which has a distinct stderr warning at line 116 that never fires). Both branches preserve, so the user-visible behavior is the same, but the safety guard the threat model points at is never exercised. Fix: add a fixture or assertion that uses e.g. `source:PROJECT.md` without staging `.planning/PROJECT.md`, and assert the stderr warning text. Alternative: rename the fixture to `inlined-source-unmapped` and add a separate `inlined-source-mapped-but-missing` fixture.

**FLAG-2** | `.planning/phases/07-post-process-gsd-sections/PLAN.md:149-157` (T2–T10 estimated commits) + actual git log | **Plan promised ~24 commits via TDD pairs; delivered 3.** PLAN.md Task breakdown lists 15 tasks expected to produce ~24 commits (mostly RED→GREEN pairs). The actual phase shipped as 3 commits: one RED (fixtures + harness), one GREEN (script), one packaging (migration + ADR + version). The single GREEN commit collapsed T3–T10. This isn't a correctness defect (the harness PASSes, all decisions are delivered), but the TDD discipline the plan committed to was not honored at the commit granularity. Reasonable trade-off to ship faster; should be acknowledged in VERIFICATION.md "Process notes" or similar. Not a BLOCK because the plan explicitly framed commit count as "estimated" (line 164), and the spec's behavior contracts are fully covered by the harness.

**FLAG-3** | `.planning/phases/07-post-process-gsd-sections/VERIFICATION.md:21` + AC-4 | **AC-4 claims "7 assertions (fewer than estimated; the 5 fixtures double up)"; PLAN.md AC-4 specified "~15 assertions".** This is a process gap, not a correctness gap — the 7 assertions do cover every Decision-B rule and every fixture in CONTEXT.md Decision G. But the AC-4 row "MET" should clarify that the assertion count was reduced from the original ~15 estimate, not just state "MET" with parenthetical. Suggest: rewrite AC-4 evidence to say "Reduced from ~15 estimated to 7 actual; each fixture is exercised by ≥1 assertion and all Decision-B rules are covered. See test_migration_0010() lines 410–533." or similar.

**FLAG-4** | `migrations/0010-post-process-gsd-sections.md:194-196` (Step 3 rollback) | **Step 3 rollback says "Restore CLAUDE.md from the working-tree snapshot taken at Step 3 entry" but doesn't specify how the runtime takes that snapshot.** 0009's Step 4 has the same hand-wavy "the migration runtime has not committed yet" wording (line 198 of `0009-vendor-claude-md-sections.md`), so 0010 is consistent — but neither migration is precise about the snapshot mechanism. For a project that runs `update-agenticapps-workflow` and gets a Step 3 abort partway through, the rollback path is non-mechanical. Suggest: either add a concrete `cp CLAUDE.md /tmp/0010-step3-snapshot.md` directive in the apply block, or explicitly cross-reference the migration-runtime contract that owns snapshot management.

**FLAG-5** | `.planning/phases/07-post-process-gsd-sections/VERIFICATION.md:24` (AC-7) + user prompt | **AC-7 missed by 78L on real cparx (278 vs target ≤200).** Empirically verified: re-ran the procedure and reproduced 278L. The gap is non-GSD content (gstack skill table, anti-patterns, repo-structure diagram, project notes — ~232L combined per VERIFICATION.md lines 99–104). This is shippable because (a) 0010 still delivers the largest single delta in the chain (47% reduction from post-0009 baseline; 57% from original 647L), (b) the remaining gap is content the user authored as project-canonical (not mechanical migration territory), and (c) the cparx-shape fixture lands at 147L proving the script can hit ≤200L when the input has only marker-block content. **Partial-credit shippable**, BUT the user's original prompt set the expectation of "646L → 0009 → ~496L → 0010 → ~165L" (auto green). Actual 278L is between the post-0009 baseline (521L) and the stretch target (~165L) — closer to the stretch goal than the baseline. CHANGELOG and ADR 0022 already capture this gap correctly. The trade-off: shipping a 47% reduction now vs blocking for follow-up Phase 08 (vendor gstack skill list) + Phase 09 (collapse repo-structure diagram) to chase the additional ~50–60L. **Recommendation: ship 0010 as PARTIAL on the coverage matrix; do not block.**

#### NIT

**NIT-1** | `docs/decisions/0022-post-process-gsd-section-markers.md:45` and `:176` | "overwritten unconditionally via `updateSection()` at line 252" — line 252 is inside `updateSection` (the `'replaced'` branch return statement). The function definition is at line 244; the call site that runs unconditionally without `--auto` is line 992. Cleaner: cite "line 992 (the unconditional call from `cmdGenerateClaudeMd`)" or "line 244 (the function definition)". Doesn't affect any decision; reader can still find the right code.

**NIT-2** | `.planning/phases/07-post-process-gsd-sections/CONTEXT.md:262-264` + `migrations/test-fixtures/0010/` | Decision G enumerated 5 fixtures including `after-normalized.md`. The diff ships `with-0009-vendored` instead, and tests idempotency by re-running the script against `inlined-7-sections` output (run-tests.sh:506–519). This is functionally equivalent — idempotency is verified — but the fixture-name divergence from the spec is worth a quick CONTEXT.md or VERIFICATION.md note. Suggest: amend Decision G's fixture list, or document in VERIFICATION.md that "`after-normalized` was implemented as an inline second-pass on `inlined-7-sections` rather than a standalone fixture".

**NIT-3** | `templates/.claude/hooks/normalize-claude-md.sh:1-22` (header) | Header comment doesn't mention that the script atomically rewrites only when output differs (lines 212–214). This is a documented behavior that matters for the PostToolUse loop-avoidance threat-model row. One-line addition: "Atomically rewrites the input only when output differs (avoids re-triggering PostToolUse on the script's own write)."

**NIT-4** | `migrations/0010-post-process-gsd-sections.md:131` | Step 2's jq-less fallback `echo "ERROR: jq not available; agent-driven edit required" >&2; exit 1` aborts the bash apply block. PLAN.md Step 3 described "both paths documented in the migration", which is true at the prose level but the executable apply block only implements one path. Acceptable as-is (migrations are markdown contracts read by the agent runtime), but a comment clarifying "Agent-driven hand-edit fallback is documented above; the executable path requires jq" would tighten this.

### Stage-1 verdict

**APPROVE-WITH-FLAGS**

The spec is honored. Every Step in PLAN.md and every Decision (A–G) in
CONTEXT.md has a corresponding, behaviorally-correct artifact in the diff.
The harness PASSes 7/7 for migration 0010 with no regressions in 0009 (the
8 0001 FAILs are pre-existing, documented, unrelated to this phase).
VERIFICATION.md's numerical claims are honest — re-running the procedure
reproduces 647 → 521 → 278 byte-for-byte and the harness output matches
exactly. The ADR's code-location citations are accurate (one minor line-
reference imprecision noted as NIT-1).

The AC-7 line-count miss (278L vs ≤200L target) is shippable as PARTIAL
because the remaining gap is non-GSD content explicitly out-of-scope for
0010, the chain still delivers a 57%-from-original reduction, and CHANGELOG
+ ADR-0022 + VERIFICATION.md all document the gap with empirical math and
a follow-up path. Recommend landing 0010 with FLAG-1 (untested
existence-guard branch) addressed before merge, and FLAG-2 through FLAG-5
acknowledged in CHANGELOG or VERIFICATION.md without blocking the ship.
