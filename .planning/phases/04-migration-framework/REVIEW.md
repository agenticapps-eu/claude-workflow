# Phase 4 Review — Migration Framework + 0000 + 0001

## Stage 1 — Spec compliance review (`gstack:/review`-equivalent)

**Reviewer:** primary agent (self), against handoff prompt Phase 4 (Steps A–H) + Q6 design recommendations
**Diff scope:** `setup/SKILL.md` (-87/+200), `skill/SKILL.md` (+1 frontmatter line), 7 new files (3 migration files, 1 test runner, 1 test README, update/SKILL.md, ADR-0013)
**Method:** spec coverage audit + TDD round-trip + adversarial read

### Spec coverage vs handoff prompt Phase 4

| Step | Spec | Status |
|---|---|---|
| A: Design framework in /gsd-discuss-phase 4 | Lock format, version storage, migration discovery, dry-run, setup refactor | ✅ Locked via Q6 (defaults applied: version in skill frontmatter, sequential IDs, idempotency mandatory, per-step rollback, dry-run yes, refactor setup) |
| B: Migration file format | Frontmatter + ordered steps + idempotency + rollback | ✅ Format spec written to `migrations/README.md` |
| C: `update/SKILL.md` (TDD) | 6-step pattern + flags + failure modes | ✅ Skill written; TDD applied via test fixture round-trip; 20/20 tests pass |
| D: Refactor `setup/SKILL.md` | Apply migrations from baseline; eliminate divergent code paths | ✅ `setup/SKILL.md` rewritten as migration applier; delegates to same per-migration logic as `update` |
| E: `migrations/0000-baseline.md` | Codify current 1.2.0 setup behavior | ✅ 6 steps matching the README setup behavior, with optional Step 5 (global CLAUDE.md) gated by install scope |
| F: `migrations/0001-go-impeccable-database-sentinel.md` | Encode Phases 1+2+3 patches | ✅ 10 steps with verbatim patch text, idempotency anchors, per-step rollback |
| G: Update README | "Updating an existing project" section | **Deferred to Phase 5** per the handoff prompt's Phase 5 Step B (README update happens with the version bump) |
| H: ADR | Document framework design | ✅ `docs/decisions/0013-migration-framework.md` |

### TDD round-trip evidence

The test fixture harness (`migrations/run-tests.sh`) caught two real defects in migration 0001 on first run:

| Defect | Found by | Fixed in |
|---|---|---|
| Step 3 idempotency anchor included backticks (` ``database-sentinel:audit`` `) that don't appear adjacent to "if Supabase /…" in the actual file → check would never match a correctly-applied state | Test runner first run | Migration 0001 Step 3 anchor changed to backtick-free phrase "if Supabase / Postgres / MongoDB touched" |
| Step 5 jq path traversal threw exit 4 on baseline (null path), not 1 → noisy and inconsistent with the "any non-zero = not applied" convention | Test runner first run | Migration 0001 Step 5 check rewritten to use `// []` defaulting + `any()` predicate; test runner refactored to use semantic `applied` / `not-applied` assertions |

After both fixes: 20/20 PASS.

### Spec deviations (transparent)

| Deviation | Reason |
|---|---|
| Phase 4 Step G (README update) deferred to Phase 5 | The handoff prompt itself moves the README update into Phase 5 Step B (alongside the version bump). Following the prompt's actual phasing rather than re-scoping. |
| `0000-baseline.md` Step 1 reads from `~/.claude/skills/agenticapps-workflow/skill/SKILL.md` (the scaffolder's source) but the scaffolder skill name in this repo is `agenticapps-workflow` — there's a known path drift bug (other parts of the repo say `agentic-apps-workflow`). | Out of scope for this phase. Migration 0000 follows the README's documented install path (which uses `agenticapps-workflow`); the path-drift bug is a separate concern and would be its own future migration. |

### Findings

| ID | Severity | Confidence | File:Line | Finding | Action |
|---|---|---|---|---|---|
| S1-1 | INFORMATIONAL | 9/10 | Multiple files | Path drift between `agenticapps-workflow` (in README, setup/SKILL.md, migration 0000) and `agentic-apps-workflow` (in workflow-config.md, claude-md-sections.md, project install paths). Pre-existing in the repo; this phase did not introduce or fix it. | **NO ACTION** — out of scope for Phase 4. Could ship as a follow-up cleanup migration. |
| S1-2 | INFORMATIONAL | 8/10 | `migrations/0000-baseline.md` Step 5 | Step 5 (global CLAUDE.md append) is conditional on install scope but the migration file format doesn't have a "conditional step" mechanism — the conditional logic lives in setup/SKILL.md Step 5 (skip if `$SCOPE = per-project`). | **NO ACTION** — the `optional_for` frontmatter field exists for the analogous "Go-only" case. For 0000's install-scope case, the conditional is invocation-context (driven by Step 2 in setup), not file-content (which is what `optional_for` was designed for). Documenting this distinction in `migrations/README.md` is a future polish. |
| S1-3 | INFORMATIONAL | 7/10 | `migrations/0001-…md` Step 9 | Copies `~/.claude/skills/agenticapps-workflow/templates/adr-db-security-acceptance.md` into the project. This file only exists in the scaffolder AFTER Phase 3 ships. If a project tries to apply 0001 against a scaffolder that doesn't have the template (e.g. a partial pull), Step 9 will fail. | **NO ACTION** — `requires` block doesn't currently express "scaffolder-side file dependencies". The pre-flight check (`test -f $TEMPLATE_PATH`) catches this at runtime. Future enhancement: add scaffolder-version check to migration frontmatter. |

### Stage 1 verdict

**STATUS: clean.** All Phase 4 deliverables ship matching the handoff prompt spec. TDD round-trip caught and fixed two real defects. JSON valid (no JSON files modified this phase). Spec deviations (G deferred to Phase 5; path drift left as-is) documented transparently.

---

## Stage 2 — Independent code-quality review

**Reviewer:** Stage-2 reviewer agent (`pr-review-toolkit:code-reviewer` role; independent from primary)
**Diff scope:** `setup/SKILL.md` (rewritten, 222 lines), `skill/SKILL.md` (+1 frontmatter line), 7 new files (`migrations/{README,0000-baseline,0001-…}.md`, `migrations/test-fixtures/README.md`, `migrations/run-tests.sh`, `update/SKILL.md`, `docs/decisions/0013-migration-framework.md`)
**Method:** ran `migrations/run-tests.sh` (20/20 PASS confirmed); spot-verified Steps 1, 7 apply blocks against HEAD verbatim; verified `awk` frontmatter parser against actual `skill/SKILL.md` shape; replayed `sort -V` semver bound logic for 1.2.0/1.3.0/1.10.0 boundary cases; checked idempotency anchors against `git show 7dafa63:templates/...`.

### Coverage summary

- Steps A–H: A/B/C/D/E/F/H all delivered. G (README) explicitly deferred to Phase 5 by the source prompt — not spec drift.
- Test harness: 20/20 PASS verified locally. Semantic `applied` / `not-applied` assertions correctly map to "check exit 0 = patch present, skip" contract.
- `update/SKILL.md` Step 1 awk parser (`f==1 && /^version:/ {print $2; exit}`) correctly extracts `1.2.0` from the actual `skill/SKILL.md` frontmatter shape.
- `update/SKILL.md` Step 2 `sort -V` chain correctly bounds the pending range; verified 1.2.0/1.3.0/1.5.0 boundary cases by hand.
- `setup/SKILL.md` rewrite preserves all v1.2.0 behavior: workflow-config substitution (now in 0000 Step 2), hooks JSON copy (0000 Step 3), CLAUDE.md append (0000 Step 4), install-scope choice (Step 2 + 0000 Step 5 conditional), external tooling warnings (Step 1 lines 65–68 — `claude` / GSD / gstack / superpowers).
- ADR-0013 six rejections genuinely distinct.

### Findings

<finding>
<severity>medium</severity>
<category>correctness / robustness</category>
<location>migrations/0001-go-impeccable-database-sentinel.md, Step 9 (line 202–207)</location>
<evidence-quote>**Pre-condition:** the source template exists at `~/.claude/skills/agenticapps-workflow/templates/adr-db-security-acceptance.md`</evidence-quote>
<issue>Step 9 hard-codes the scaffolder install path as `agenticapps-workflow` (no hyphen). The project-side install convention (and the synthetic fixture in `run-tests.sh` line 58) uses `agentic-apps-workflow` (hyphen). If a user installs the scaffolder repo under the hyphenated name (which several other paths in the repo suggest is also valid), Step 9's pre-condition will fail at apply time. The test harness does not exercise apply, so this is invisible to `run-tests.sh`. Stage 1 noted the path drift as out-of-scope; this finding flags that 0001 Step 9 in particular has a runtime-fail risk.</issue>
<suggested_fix>Either (a) document the canonical scaffolder install path in `migrations/README.md` § "Where the workflow scaffolder lives" so all migrations reference one source-of-truth, or (b) make Step 9 try both paths (`for p in ~/.claude/skills/agenticapps-workflow ~/.claude/skills/agentic-apps-workflow; do …`).</suggested_fix>
</finding>

<finding>
<severity>low</severity>
<category>specification clarity</category>
<location>migrations/0001-…md, Steps 5 + 6 (lines 118–158)</location>
<evidence-quote>**Apply:** add a `sub_gates` array to the existing `security` entry: ```json "sub_gates": [ { … } ] ```</evidence-quote>
<issue>Steps 5 and 6 show only the new JSON fragment, not the merged result. The agent must understand "this is a child of `.hooks.post_phase.security`" or "siblings of `.hooks.finishing.branch_close`" from prose alone. For an agent-interpreted apply step (no executable patch), this is fragile — a different agent run could put the array at the wrong nesting level. The idempotency check would still pass on a re-run after a wrong-nesting apply because it tolerates `// []`.</issue>
<suggested_fix>Add a concrete `jq` apply command alongside the JSON literal, e.g. `jq '.hooks.post_phase.security.sub_gates = [{…}]' .planning/config.json > .tmp && mv .tmp .planning/config.json`. This both shows the intended nesting and gives a deterministic apply mechanism.</suggested_fix>
</finding>

<finding>
<severity>low</severity>
<category>idempotency anchor weakness</category>
<location>migrations/0001-…md, Step 8 (line 182)</location>
<evidence-quote>**Idempotency check:** `grep -q "database-sentinel:audit" CLAUDE.md`</evidence-quote>
<issue>Anchor is the bare skill name. If a future migration or user edit mentions `database-sentinel:audit` anywhere in `CLAUDE.md` (a comment, a different hook expansion, a TOC entry), Step 8 will spuriously skip even when the Hook 8 paragraph isn't present. Stronger anchor: a phrase from the new content unique to Hook 8, e.g. `grep -q "produces exact SQL DDL fixes" CLAUDE.md`.</issue>
<suggested_fix>Change anchor to a unique phrase from the inserted paragraph, e.g. `grep -q "Additionally,\*\* when the phase touches Supabase" CLAUDE.md` or `grep -q "produces exact SQL DDL fixes" CLAUDE.md`.</suggested_fix>
</finding>

<finding>
<severity>low</severity>
<category>test harness portability</category>
<location>migrations/run-tests.sh line 117</location>
<evidence-quote>local before_ref="$(git merge-base HEAD main 2>/dev/null || git rev-parse main)"</evidence-quote>
<issue>Uses local `main` ref. If the developer's local `main` is stale (no `git fetch` since the feature branch was created), the merge-base could resolve to a different commit than expected. After this branch lands and `main` advances past `7dafa63`, the harness still works because the merge-base of HEAD (squash-merged) and the new main is the merge-commit itself — but on a fork or stale clone, behavior may surprise.</issue>
<suggested_fix>Either pin to `origin/main` (`git merge-base HEAD origin/main`) or document the expectation in `test-fixtures/README.md` that callers should `git fetch` first.</suggested_fix>
</finding>

<finding>
<severity>info</severity>
<category>ADR completeness</category>
<location>docs/decisions/0013-migration-framework.md, "Alternatives Rejected" (lines 90–117)</location>
<evidence-quote>(six alternatives listed — re-run setup, CHANGELOG, git apply, semver-only, GSD reuse, defer)</evidence-quote>
<issue>One reasonable alternative is missing: a **single idempotent agent-driven setup skill** that reads the current state and converges to the latest version (no migration files; the skill's logic handles all version transitions). This is what the v1.2.0 setup essentially was, plus convergence logic. It was implicitly rejected when adopting "migration files," but explicitly naming + rejecting it would close the alternatives space. Not a blocker.</issue>
<suggested_fix>Add a 7th rejection: "Single idempotent setup skill with convergence logic — rejected because every new feature would balloon the skill's branching logic; migrations make each delta self-contained and individually testable."</suggested_fix>
</finding>

### Stage 2 verdict

**STATUS: clean with minor findings.** All Phase 4 deliverables ship as specified. The test harness genuinely validates the idempotency contract (caught 2 real bugs in TDD RED stage; both fixed and verified). Apply blocks for Steps 1 and 7 match HEAD verbatim. The awk frontmatter parser and `sort -V` semver logic in `update/SKILL.md` are correct. Findings are quality polish (anchor strength, apply-block determinism, ADR exhaustiveness) — none block phase merge.

### Resolution (post-Stage-2 fixes applied)

All 5 findings addressed before commit:

- **S2-medium (Step 9 path drift):** Added a "Where the workflow scaffolder lives" subsection to `migrations/README.md` documenting that the canonical scaffolder install path is `~/.claude/skills/agenticapps-workflow/` (no internal hyphen) and the project-side install uses `agentic-apps-workflow` (with hyphen). The two paths are intentionally different — one for the scaffolder repo, one for each project's local skill copy. Step 9 follows the canonical scaffolder path; non-canonical installs are out of scope (future enhancement: `--scaffolder PATH` override).
- **S2-low (Steps 5+6 jq apply):** Added concrete `jq` apply commands alongside the JSON literal blocks in both Step 5 (sub_gates) and Step 6 (finishing entries). The agent can now use either the literal or the deterministic jq form; the jq form fixes the nesting unambiguously.
- **S2-low (Step 8 anchor weakness):** Changed Step 8 idempotency check from `grep -q "database-sentinel:audit" CLAUDE.md` (too broad — would match any mention) to `grep -q "produces exact SQL DDL fixes" CLAUDE.md` (a unique phrase from the inserted Hook 8 paragraph). Test runner updated to use the same anchor; 20/20 PASS confirmed.
- **S2-low (run-tests.sh stale main):** Added `git fetch --quiet origin main` before computing `merge-base`, with fallback chain `origin/main → main → rev-parse main`. Stale clones are now self-healing.
- **S2-info (ADR alternative):** Added 7th rejected alternative ("Single idempotent setup skill with convergence logic") to ADR-0013, naming the v1.2.0-shape that the migration framework explicitly chose against, and explaining why migrations beat the god-object branching alternative.

**Verification re-run after fixes:** `./migrations/run-tests.sh` → 20/20 PASS. Step 8 anchor change validated by both the before-state (anchor absent → "needs apply") and after-state (anchor present → "skip") behaving correctly.

**FINAL STATUS: Stage 1 ✅, Stage 2 ✅ (after 5-fix resolution). Phase 4 ready to commit.**
