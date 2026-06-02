# Phase 28 — Cross-AI Plan Reviews (SPLIT-01)

> Generated 2026-06-02 via `/gsd-review 28`. Reviewers: gemini (done), codex (done after
> fixing the stdin-hang — see memory `codex-exec-stdin-hang`). claude skipped (running inside it).
> Consume with `/gsd-plan-phase 28 --reviews`.

## Reviewer verdicts

| Reviewer | CLI | Overall risk | Verdict |
|----------|-----|--------------|---------|
| gemini | `gemini -p` | **LOW** | No high-severity concerns; plans sound. 1 LOW (PR-body placeholder). |
| codex | `codex exec --skip-git-repo-check` | **HIGH** | Architecture/sequencing right, but release-rigor + correctness gaps. 4 HIGH + 3 MEDIUM. |

Same-LLM `gsd-plan-checker` PASSED — codex caught structural blind-spots it missed. Treat codex's
HIGH items as required pre-execution fixes.

## Consolidated action items (the replanner MUST address each)

### A1 — [HIGH] `setup_fixture` is not truly shareable → demote to a claude-workflow wrapper
**Source:** codex (set-as-whole + 28-01). **Target:** 28-01, 28-03.
`setup_fixture` (run-tests.sh:109-123) hardcodes workflow template paths AND a workflow-only
`1.3.0` ADR special-case (run-tests.sh:112). Parameterizing only `skill_name` (the current plan)
leaves hidden consumer coupling — `agenticapps-observability` can't reuse it, violating SC5.
**Resolution (RECOMMENDED — Option B, codex's second suggestion):** share only the truly-generic
primitive `extract_to` in agenticapps-shared. KEEP `setup_fixture` as a thin **claude-workflow
wrapper** in run-tests.sh that calls shared `extract_to` and layers the workflow-specific template
paths + the 1.3.0 special-case on top. Update ADR-0035's SHARED set: `setup_fixture` moves to
WORKFLOW (wrapper), `extract_to` stays SHARED. (Rejected Option A "fully parameterize fixture
source paths now" — over-engineers paths this phase doesn't need and guesses observability's shape.)

### A2 — [HIGH] Don't tag v1.0.0 until the fragile shared surfaces are proven
**Source:** codex (28-02). **Target:** 28-02.
The standalone suite only exercises `assert_check` + drift. Before cutting v1.0.0 it MUST also
prove, in a temp git repo against real refs: `extract_to` (real ref extraction) and (if A1 keeps
any shared fixture logic) the fixture primitive; plus synthetic `run_preflight_verify_paths` tests
for BOTH strict and non-strict modes. Block the tag task on these passing.

### A3 — [HIGH] install.sh must advance the submodule on existing clones, not just first init
**Source:** codex (28-03). **Target:** 28-03.
Current proposal runs the init only when `vendor/agenticapps-shared/VERSION` is missing → after a
`git pull` an existing clone never advances to the new gitlink SHA (breaks install.sh's idempotent
rerun contract, install.sh:10). **Resolution:** when `.gitmodules` exists, ALWAYS run
`git submodule sync --recursive && git submodule update --init --recursive` (idempotent), or
compare the current gitlink SHA and update on mismatch.

### A4 — [MEDIUM] The pin contract is a gitlink SHA, not a tag
**Source:** codex (set-as-whole, 28-02, 28-03). **Target:** 28-02, 28-03.
The superproject persists a gitlink **commit SHA**, not the tag. **Resolution:** 28-02 records the
exact release commit SHA (e.g. in its SUMMARY/CHANGELOG) as the canonical pin artifact; treat
`v1.0.0` as provenance only. 28-03's acceptance criterion verifies the superproject **gitlink SHA
== 28-02's recorded SHA** (e.g. `git -C . ls-tree HEAD vendor/agenticapps-shared`), NOT
`git describe --tags --exact-match HEAD` (which is environment-local and fails on a legit fresh
clone when submodule tags weren't fetched).

### A5 — [MEDIUM] Preflight must be `set -u`-safe
**Source:** codex (28-01). **Target:** 28-01.
`run_preflight_verify_paths` implicitly assumes the caller pre-initialized `STRICT_PREFLIGHT`
(run-tests.sh:46). Under a shared caller with `set -u` this explodes. **Resolution:** read
`${STRICT_PREFLIGHT:-0}` internally in the shared function.

### A6 — [MEDIUM] SC-6 GSD-regression proof is too weak
**Source:** codex (28-03). **Target:** 28-03 (and ROADMAP SC-6 wording).
`gsd-tools.cjs --help` does not prove `/gsd-progress`, `/gsd-stats`, `/gsd-help` are unchanged.
**Resolution:** capture those three command outputs before the refactor, diff after; or narrow SC-6
to the specific invariant actually being protected.

### A7 — [LOW] PR body placeholder
**Source:** gemini (28-03). **Target:** 28-03.
Give `gh pr create` a concrete body template (links to SPLIT-00/01, ADR-0035, the new repo, the
release SHA) rather than `<body>`.

## Full reviewer outputs

### Gemini (risk: LOW)
Comprehensive, high-quality plans. Validated: 186/4 hard gate, Wave1-tag-before-Wave2-pin ordering,
mechanism/policy drift split, `BASH_SOURCE` sourcing, fresh-clone/install.sh handling. Only concern
LOW: the `gh pr create` body is a placeholder (A7). No suggested changes to 28-01/28-02.

### Codex (risk: HIGH)
Set-as-whole: "carve, release shared, then consume" sequence is right; understands 186/4, trap
ordering, drift split. Misses are release rigor: tagging v1.0.0 before the fragile surfaces are
proven (A2), and treating the submodule as if the tag is what persists (A4). Per-plan: 28-01
MEDIUM-HIGH (A1 setup_fixture coupling, A5 STRICT_PREFLIGHT); 28-02 HIGH (A2 shallow suite, A4 SHA
artifact); 28-03 MEDIUM-HIGH (A3 install existing-clone, A4 gitlink semantics, A6 weak SC-6 proof).
Strengths confirmed: source-and-keep shape, 186/4 as hard gate, return-code-only drift runner,
BASH_SOURCE sourcing, trap-after-source.
