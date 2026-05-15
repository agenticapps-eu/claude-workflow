# Phase 14 — PLAN — Implement spec §10.9 enforcement layer (v1.10.0)

**Revision**: v2 (post-review). v1 returned BLOCK from codex on Q1 (spec conformance) and REQUEST-CHANGES from gemini + Claude on Q4 (CI security). See `14-REVIEWS.md` for the 21-item revision list this PLAN incorporates.

**Phase goal**: ship the `add-observability` skill at version `0.3.0` (`implements_spec: 0.3.0`) with delta scan, baseline file, CI workflow template; ship migration 0011 promoting projects 1.9.3 → 1.10.0; preserve all 61 v0.2.1 contract tests green.

**Scaffolder bump**: `skill/SKILL.md` 1.9.3 → 1.10.0.

---

## Key invariants codified after review

These are spec-derived requirements that bind every task's implementation:

1. **`delta.json` is always emitted whenever `--since-commit` is set** — even on empty deltas. The machine-readable summary obligation in §10.9.1 is unconditional.
2. **`scanned_commit` is always a 40-char SHA** (`git rev-parse HEAD`). No "working-tree" placeholder.
3. **`policy_hash` is always `sha256:<hex>`**. No null. Projects without `policy.md` cannot run `scan --update-baseline` or migration 0011 — they're directed to run `add-observability init` first.
4. **Baseline writes only on `--update-baseline` or `scan-apply` success** — never on a plain `scan` or a delta scan. (Spec §10.9.2 line 219.)
5. **CI gate fail rule**: `B = base baseline.json's counts.high_confidence_gaps`; `D = delta.json's counts.high_confidence_gaps`. Fail if `D > 0`. Document this as "the count of high-confidence gaps would increase from B to B+D if this PR landed; we fail on any net new high gap". If base baseline.json is missing/empty, log "enforcement disabled — no baseline on base branch" and pass the gate.
6. **GitHub Actions SHA-pinned**, no floating tags. Every `${{ }}` interpolation inside `run:` is lifted to a step-level `env:` first. Trigger is `pull_request` (NEVER `pull_request_target`).
7. **CI workflow file is scaffolder-owned** — migration always overwrites it (with `.bak` for user customisations). Documented in `ci/README.md`.
8. **Migration 0011 aborts pre-flight** if `observability:` block missing from CLAUDE.md, or if `policy.md` missing, or if `claude` CLI missing. No silent skips; clear remediation message.

---

## Task breakdown (atomic — one commit per task)

### Phase 1 — Delta scan (§10.9.1)

#### T1 — `scan/SCAN.md` accepts `--since-commit <ref>`
**Touches**: `add-observability/scan/SCAN.md`
**Change**:
- Add an "Inputs" entry: `--since-commit <ref>` (optional, default `none`).
- Insert new "Phase 0.5 — Resolve scope" between Phase 1 and Phase 2:
  - If `--since-commit <ref>` is set: compute `git diff --name-only <ref>...HEAD` (triple-dot — files changed in HEAD relative to merge-base, which is what "what does this PR add" means semantically; see "Important rules" addition below).
  - Resolve `<ref>` → 40-char SHA via `git rev-parse --verify <ref>^{commit}`. Error early if the ref doesn't resolve.
  - Set `scope = delta`; record `since_commit = <resolved-sha>` and `head_commit = git rev-parse HEAD`.
  - The file-scope set is the diff result (possibly empty). Pass forward to Phase 3.
  - **Do NOT early-exit on empty scope.** Empty deltas still emit `delta.json` (Phase 8) and a markdown report banner. The early exit is just "no files in scope → no findings to walk", which Phase 3 handles naturally by iterating zero files.
- Update Phase 3 (Walk) bullet 3: "For each file in scope (full scan = all matching files; delta = files from Phase 0.5 intersected with stack patterns)".
- Update Phase 5 (Compose) to set frontmatter `scope: delta | full` and (delta only) `since_commit:`, `head_commit:`, `files_walked:` fields.
- Add to "Important rules":
  - "Delta-scan reports MUST NOT silently overwrite the baseline file. Baseline write happens only on `--update-baseline` (Phase 7) or `scan-apply` success."
  - "Delta scope uses `git diff --name-only <ref>...HEAD` (triple-dot). This is merge-base relative — the set of files changed by the PR's commits, ignoring changes on the base branch since the merge-base. Use case: CI gate that asks 'does THIS PR introduce gaps'."
  - "Empty deltas still emit `delta.json` with zero counts. The machine-readable summary is unconditional."

**Idempotency / verification**:
- `grep -nE "Phase 0.5 — Resolve scope" add-observability/scan/SCAN.md` returns one match.
- `grep -q "Empty deltas still emit" add-observability/scan/SCAN.md`.

**Commit**: `feat(add-observability): scan accepts --since-commit, walks delta scope`

---

#### T2 — `scan/report-template.md` adds delta frontmatter + banner
**Touches**: `add-observability/scan/report-template.md`
**Change**:
- Add a frontmatter block at the very top of the rendered report (above `# Observability scan report`):
  ```
  ---
  scope: {{SCOPE}}                  # full | delta
  since_commit: {{SINCE_COMMIT}}    # 40-char SHA; only present when scope=delta
  head_commit: {{HEAD_COMMIT}}      # 40-char SHA; only present when scope=delta
  scanned_at: {{DATE_ISO}}
  ---
  ```
- Add a "delta banner" rendered immediately under the H1 when `scope: delta`:
  ```
  > **Delta scan** — {{FILE_COUNT}} file(s) changed since `{{SINCE_COMMIT_SHORT}}`.
  > Findings below are the delta only. Run `scan --update-baseline` for the full baseline.
  >
  > Files walked:
  > {{FILE_LIST_FENCED}}
  ```
  - When `FILE_COUNT` is 0: the banner reads `> **Delta scan** — 0 files changed since {{SINCE_COMMIT_SHORT}}. No findings to report.` (no file list block).
- Update "Section content rules" with `{{SCOPE}}`, `{{SINCE_COMMIT}}`, `{{HEAD_COMMIT}}`, `{{FILE_COUNT}}`, `{{FILE_LIST_FENCED}}` token semantics.

**Idempotency / verification**:
- `grep -q '^scope:' add-observability/scan/report-template.md`
- `grep -q 'Delta scan' add-observability/scan/report-template.md`

**Commit**: `feat(add-observability): scan report frontmatter + delta banner`

---

### Phase 2 — Baseline file (§10.9.2)

#### T3 — `scan/baseline-template.json` (new file)
**Touches**: `add-observability/scan/baseline-template.json` (create)
**Change**: shape matches spec §10.9.2 lines 184-217 exactly. `module_roots` sorted by `(stack, path)` per RESEARCH D5. `high_confidence_gaps_by_checklist` is a top-level sibling of `counts` (matching spec lines 192-205, NOT nested inside counts as the hand-off prompt erroneously showed).

```json
{
  "spec_version": "0.3.0",
  "scanned_at": "{{DATE_ISO}}",
  "scanned_commit": "{{COMMIT_SHA}}",
  "module_roots": [
    { "stack": "{{STACK_ID}}", "path": "{{PATH}}" }
  ],
  "counts": {
    "conformant": {{N_CONFORMANT}},
    "high_confidence_gaps": {{N_HIGH}},
    "medium_confidence_findings": {{N_MEDIUM}},
    "low_confidence_findings": {{N_LOW}}
  },
  "high_confidence_gaps_by_checklist": {
    "C1": {{N_C1}},
    "C2": {{N_C2}},
    "C3": {{N_C3}},
    "C4": {{N_C4}}
  },
  "policy_hash": "sha256:{{POLICY_HASH_HEX}}"
}
```

**Schema invariants** (asserted in T13's verification):
- `scanned_commit` is 40-char hex (no "working-tree", no abbreviated SHA).
- `policy_hash` begins with `"sha256:"` followed by 64 hex chars.
- All numeric `counts.*` and `high_confidence_gaps_by_checklist.*` fields are non-negative integers.

**Idempotency / verification**:
- File exists at the expected path.
- Sibling `.template-note.md` documents tokens.

**Commit**: `feat(add-observability): add baseline-template.json schema (§10.9.2)`

---

#### T4 — `scan/SCAN.md` adds Phase 7 (baseline writer) + Phase 8 (delta writer)
**Touches**: `add-observability/scan/SCAN.md`
**Change**: After Phase 6 (Print summary), insert:

**Phase 7 — Update baseline (only if `--update-baseline` set)**
- Read `add-observability/scan/baseline-template.json`.
- Fill tokens:
  - `DATE_ISO` from system time (RFC 3339 UTC).
  - `COMMIT_SHA`: `git rev-parse HEAD`. If repo has no commits, error out: "Project has no git commits; baseline.json requires a committed state. Commit something first."
  - `MODULE_ROOTS` from Phase 1 detection, sorted by `(stack, path)`.
  - `COUNTS` from Phase 5 aggregation.
  - `HIGH_CONFIDENCE_GAPS_BY_CHECKLIST` from per-checklist tallies.
  - `POLICY_HASH_HEX`: hex sha256 of `<wrapper-dir>/policy.md` (raw bytes). Path resolution: CLAUDE.md's `observability.policy` field if set, else default `lib/observability/policy.md`.
- **Pre-condition for Phase 7**: `policy.md` MUST exist at the resolved path. If not, error out: "policy.md not found at {path}. Run `add-observability init` first to scaffold the wrapper and policy."
- Atomic write: write to `.observability/baseline.json.tmp` (after `mkdir -p .observability/`), then `mv` to `.observability/baseline.json`.
- If `--update-baseline` was NOT set, skip Phase 7 entirely (no baseline write).

**Phase 8 — Write delta artefact (only if `--since-commit` set)**
- Even if Phase 0.5's scope is empty: write `.observability/delta.json` with shape:
  ```json
  {
    "spec_version": "0.3.0",
    "scanned_at": "{{DATE_ISO}}",
    "since_commit": "{{SINCE_COMMIT_SHA}}",
    "head_commit": "{{HEAD_SHA}}",
    "files_walked": ["{{path1}}", "..."],
    "counts": { "conformant": N, "high_confidence_gaps": N, "medium_confidence_findings": N, "low_confidence_findings": N },
    "high_confidence_gaps_by_checklist": { "C1": N, "C2": N, "C3": N, "C4": N }
  }
  ```
- Same atomic write semantics as Phase 7.
- This is the artefact the CI gate diffs against the baseline.

**Phase 9 — Verification before exit**:
- If baseline.json or delta.json was written, `jq -e .spec_version <file>` returns 0.

Also update SCAN.md "Inputs" with `--update-baseline` (optional, default false; full-scan only — incompatible with `--since-commit`).

**Idempotency / verification**:
- `grep -E "Phase 7 — Update baseline|Phase 8 — Write delta" add-observability/scan/SCAN.md` returns two matches.
- `grep -q "even if .* scope is empty" add-observability/scan/SCAN.md` (or equivalent — confirms unconditional delta emit).
- `grep -q "mkdir -p .observability" add-observability/scan/SCAN.md`.

**Commit**: `feat(add-observability): scan emits baseline.json (--update-baseline) + delta.json (--since-commit)`

---

#### T5 — `scan-apply/APPLY.md` regenerates baseline on success
**Touches**: `add-observability/scan-apply/APPLY.md`
**Change**: Extend Phase 6 with sub-phase 6b:

**Phase 6b — Regenerate baseline.json (automatic, on successful apply)**
- If at least one finding had `status: applied`: recompute baseline.json using the same procedure as SCAN.md Phase 7. Counts reflect post-apply state.
- Same schema invariants (40-char `scanned_commit` SHA, `sha256:` `policy_hash`).
- Same pre-conditions (policy.md exists; project has commits).
- If `policy.md` is missing despite `scan-apply` running successfully (shouldn't happen — scan-apply requires a prior scan which itself requires init), log a warning and skip the baseline regen rather than failing the apply.
- Atomic write same as SCAN.md Phase 7.
- The Phase 8 summary mentions: "Baseline updated: high-confidence gaps {{OLD}} → {{NEW}}."

**Idempotency / verification**:
- `grep -q "Phase 6b — Regenerate baseline" add-observability/scan-apply/APPLY.md`

**Commit**: `feat(add-observability): scan-apply regenerates baseline.json on success`

---

### Phase 3 — CI workflow template (§10.9.3)

#### T6 — `ci/observability.yml` (new file) + `ci/README.md` (new file)
**Touches**: `add-observability/ci/observability.yml`, `add-observability/ci/README.md` (both create)

**`observability.yml` requirements** (each becomes a YAML construct):

1. **Triggers**: `pull_request` (any branch) and `push` to `main`. **Comment in YAML**: `# Trigger MUST be pull_request, NEVER pull_request_target. Forks must not see secrets.`

2. **Permissions** (top-level, restricted): `contents: read`. Comment job (separate job) elevates to `pull-requests: write`.

3. **Concurrency**:
   ```yaml
   concurrency:
     group: observability-${{ github.ref }}
     cancel-in-progress: true
   ```

4. **Checkout step**: `actions/checkout@<40-char-sha>  # v4.x.y` with `fetch-depth: 0` so `git diff` against the base SHA works.

5. **Env-var indirection step** (before any `run:` that uses GitHub context):
   ```yaml
   - name: Resolve refs
     env:
       BASE_SHA: ${{ github.event.pull_request.base.sha }}
       HEAD_SHA: ${{ github.event.pull_request.head.sha }}
     run: |
       echo "BASE_SHA=${BASE_SHA}" >> $GITHUB_ENV
       echo "HEAD_SHA=${HEAD_SHA}" >> $GITHUB_ENV
   ```
   All subsequent `run:` steps reference `$BASE_SHA` / `$HEAD_SHA` only.

6. **Detect baseline on base branch** (compute `B`):
   ```yaml
   - name: Read base baseline
     run: |
       if git show ${BASE_SHA}:.observability/baseline.json > /tmp/base-baseline.json 2>/dev/null; then
         B=$(jq -r '.counts.high_confidence_gaps // empty' /tmp/base-baseline.json)
         if [ -z "$B" ]; then
           echo "::warning::baseline.json on base branch is malformed — enforcement disabled for this PR"
           echo "ENFORCEMENT_DISABLED=1" >> $GITHUB_ENV
         else
           echo "BASELINE_HIGH=$B" >> $GITHUB_ENV
         fi
       else
         echo "::warning::No baseline.json on base branch — enforcement disabled for this PR"
         echo "ENFORCEMENT_DISABLED=1" >> $GITHUB_ENV
       fi
   ```

7. **Delta scan step** (PR only): `claude /add-observability scan --since-commit $BASE_SHA`. Documented requirement: Claude Code (or scanner port) available in CI. If absent, document workaround in README.

8. **Full scan step** (push to main only): `claude /add-observability scan --update-baseline`.

9. **Compare against baseline** (PR only):
   ```yaml
   - name: Compare delta vs baseline
     if: github.event_name == 'pull_request' && env.ENFORCEMENT_DISABLED != '1'
     run: |
       D=$(jq -r '.counts.high_confidence_gaps' .observability/delta.json)
       echo "Delta high-confidence gaps: $D"
       echo "Baseline (base branch) high-confidence gaps: $BASELINE_HIGH"
       if [ "$D" -gt "0" ]; then
         echo "::error::PR introduces $D new high-confidence observability gap(s). Project total would increase from $BASELINE_HIGH to $((BASELINE_HIGH + D))."
         echo "GATE_FAILED=1" >> $GITHUB_ENV
         exit 1
       fi
   ```

10. **PR comment** (PR only, on failure):
    ```yaml
    - name: Comment on PR
      if: failure() && github.event_name == 'pull_request'
      uses: marocchino/sticky-pull-request-comment@<40-char-sha>  # v2.9.x
      with:
        header: observability-gate
        message: |
          ## Observability conformance check failed
          This PR adds new high-confidence gaps. See `.scan-report.md` for the file:line list.
          Apply fixes with: `claude /add-observability scan-apply --confidence high`
    ```

11. **Policy-drift warn-only step** (optional, runs always):
    ```yaml
    - name: Policy drift check
      if: env.ENFORCEMENT_DISABLED != '1' && hashFiles('lib/observability/policy.md') != ''
      run: |
        EXPECTED=$(jq -r '.policy_hash' /tmp/base-baseline.json | sed 's/^sha256://')
        ACTUAL=$(shasum -a 256 lib/observability/policy.md | awk '{print $1}')
        if [ "$EXPECTED" != "$ACTUAL" ]; then
          echo "::warning::policy.md hash changed since baseline was last recorded. Run scan --update-baseline."
        fi
    ```

**SHA resolution at implementation time**: resolve current stable tags for `actions/checkout` and `marocchino/sticky-pull-request-comment` via `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` and hardcode the SHAs.

**`ci/README.md` content**:
- v1.10.0 limitation: Claude Code in CI not fully supported. Workarounds: (a) manual local pre-PR scan, (b) self-hosted runner, (c) wait for v1.11.0 Node scanner port.
- Installation: migration 0011 copies this workflow to your project's `.github/workflows/`. Manual install: copy the file directly.
- Opt-out: delete or empty `.observability/baseline.json`; the workflow logs "enforcement disabled" and passes the gate. Per spec §10.9.3, this is the only opt-out path — and it's loud, not silent.
- **Threat model**: a malicious PR from a fork could place prompt-injection content in source files that `claude` reads during the scan step. Mitigations: (a) `pull_request` trigger (no secrets exposed), (b) read-only permissions on the scan job, (c) optional restriction: add `if: github.event.pull_request.head.repo.full_name == github.repository` to skip fork PRs entirely. Document the trade-off.
- **DO NOT change `pull_request` to `pull_request_target`** — that would give attacker code access to secrets. Explicit warning.
- **Baseline merge conflicts**: a PR that rebases against main after another conformance-affecting PR has merged will see a baseline.json conflict. Resolution: regenerate (`claude /add-observability scan --update-baseline`) and commit. Don't merge-resolve the conflicting counts manually.
- **Pinned SHAs**: actions pinned to commit SHAs to prevent supply-chain attacks. Update via dependabot or renovate; sample config in `ci/dependabot-example.yml`.
- **Customisation**: this workflow file is scaffolder-owned. Migration 0011 overwrites it (with `.bak`) on each scaffolder update. To customise: fork the action contents into a sibling workflow under a different filename.

**Idempotency / verification**:
- `python -c 'import yaml; yaml.safe_load(open("add-observability/ci/observability.yml"))'` exits 0.
- `grep -q 'enforcement disabled' add-observability/ci/observability.yml`.
- `grep -q 'fetch-depth: 0' add-observability/ci/observability.yml`.
- `grep -q 'marocchino/sticky-pull-request-comment@[a-f0-9]\{40\}' add-observability/ci/observability.yml`.
- `grep -q 'actions/checkout@[a-f0-9]\{40\}' add-observability/ci/observability.yml`.
- `grep -q 'concurrency:' add-observability/ci/observability.yml`.
- `! grep -q 'pull_request_target' add-observability/ci/observability.yml`.
- `grep -q 'NEVER pull_request_target' add-observability/ci/observability.yml` (the cautionary comment).
- `grep -q 'BASE_SHA' add-observability/ci/observability.yml` (env-var indirection used).

**Commit**: `feat(add-observability): ship reference CI workflow + adoption README (§10.9.3)`

---

### Phase 4 — Migration 0011 + test fixtures

#### T7 — `migrations/0011-observability-enforcement.md`
**Touches**: `migrations/0011-observability-enforcement.md` (create); `migrations/README.md` (update chain table)

Frontmatter:
```yaml
id: 0011
slug: observability-enforcement
title: Spec §10.9 — delta scan, baseline file, CI workflow (v0.3.0 enforcement layer)
from_version: 1.9.3
to_version: 1.10.0
applies_to:
  - .github/workflows/observability.yml          # CI workflow copy (overwritten)
  - .observability/baseline.json                  # initial baseline (created)
  - CLAUDE.md                                     # observability metadata bump + enforcement sub-block + Skills line
  - .claude/skills/agentic-apps-workflow/SKILL.md # version bump
requires:
  - skill: add-observability
    install: "(skill ships in scaffolder repo; no separate install)"
    verify: "test -f ~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md && grep -q '^implements_spec: 0.3.0' ~/.claude/skills/agenticapps-workflow/add-observability/SKILL.md"
  - tool: claude
    install: "Claude Code CLI; install separately (https://claude.ai/code)"
    verify: "command -v claude >/dev/null"
  - tool: jq
    install: "brew install jq (or apt install jq)"
    verify: "command -v jq >/dev/null"
```

**Pre-flight (hard aborts):**

```bash
# 1. Project has observability metadata block (i.e. init has been run)
grep -q '^observability:' CLAUDE.md || {
  echo "ABORT: CLAUDE.md has no observability: metadata block."
  echo "Run 'claude /add-observability init' first to scaffold observability, then re-run this migration."
  exit 3
}

# 2. policy.md exists at the path the metadata declares (or default lib/observability/policy.md)
POLICY_PATH=$(grep -E '^\s*policy:' CLAUDE.md | head -1 | sed 's/.*policy:\s*//' | tr -d '"')
POLICY_PATH=${POLICY_PATH:-lib/observability/policy.md}
test -f "$POLICY_PATH" || {
  echo "ABORT: policy.md not found at $POLICY_PATH."
  echo "Re-run 'claude /add-observability init' to scaffold the wrapper + policy."
  exit 3
}

# 3. SKILL.md is at 1.9.3 (or 1.10.0 for re-apply)
grep -qE '^version: 1\.(9\.3|10\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  echo "ABORT: workflow version is not 1.9.3. Apply prior migrations first."
  exit 3
}
```

**Steps:**

**Step 1: Overwrite `.github/workflows/observability.yml`**
- Idempotency check: `cmp -s ~/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml .github/workflows/observability.yml`
- Pre-condition: `mkdir -p .github/workflows` (always succeeds)
- Apply: if a different `observability.yml` already exists, back it up to `.github/workflows/observability.yml.bak.<timestamp>`. Then `cp` the scaffolder copy in place.
- Rollback: `rm .github/workflows/observability.yml; mv .github/workflows/observability.yml.bak.<latest> .github/workflows/observability.yml 2>/dev/null || true`.
- Rationale: the CI workflow is scaffolder-owned per the spec §10.9.3 reference-workflow contract. The .bak file preserves user customisations for manual reconciliation.

**Step 2: Author initial baseline by invoking the scan skill**
- Idempotency check: `test -f .observability/baseline.json && jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1`
- Pre-condition: pre-flight passed (policy.md exists, etc.)
- Apply: the consuming Claude session reads `~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md` and follows the full procedure with `--update-baseline` set, using the project root as the working directory. End-state: `.observability/baseline.json` exists with `spec_version: 0.3.0` and well-formed counts.
- Rollback: `rm -rf .observability/`

**Step 3: Add `enforcement:` sub-block to `observability:` in CLAUDE.md and bump `spec_version`**
- Idempotency check: `grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md`
- Pre-condition: `grep -q '^observability:' CLAUDE.md` (asserted by pre-flight)
- Apply: in-place edit using anchor lines. Replace:
  ```
  observability:
    spec_version: 0.2.1
  ```
  with:
  ```
  observability:
    spec_version: 0.3.0
  ```
  Then append `enforcement:` sub-block below the existing `observability:` block (anchored at the next top-level key or end of file). Block content:
  ```
    enforcement:
      baseline: .observability/baseline.json
      ci: .github/workflows/observability.yml
      pre_commit: optional
  ```
- Rollback: revert spec_version to 0.2.1; remove the enforcement sub-block.

**Step 4: Document the per-PR enforcement command in the Skills/Observability section of CLAUDE.md**
- Idempotency check: `grep -q 'add-observability scan --since-commit main' CLAUDE.md`
- Pre-condition: a "Skills" or "Observability" reference section exists in CLAUDE.md (else skip with a note)
- Apply: append `Observability enforcement: claude /add-observability scan --since-commit main` to the relevant section.
- Rollback: remove that line.

**Step 5: Bump `.claude/skills/agentic-apps-workflow/SKILL.md` version 1.9.3 → 1.10.0**
- Idempotency check: `grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md`
- Pre-condition: `grep -q '^version: 1.9.3$' .claude/skills/agentic-apps-workflow/SKILL.md`
- Apply: in-place sed (with `.bak`, rm bak)
- Rollback: sed back to 1.9.3

**Post-checks**: each step's idempotency check returns 0 on re-run; `git status` shows the expected file set.

Also update `migrations/README.md` chain table:
```
| `0011` | 1.9.3 → 1.10.0 | Spec §10.9 observability enforcement (delta scan, baseline file, CI workflow) |
```

**Commit**: `feat(migrations): 0011 — observability enforcement (1.9.3 → 1.10.0)`

---

#### T8 — Test fixtures for migration 0011
**Touches**: `migrations/test-fixtures/0011/<fixtures>/`

**Fixtures (7)** — each with `before/`, `expected-after/`, `assert.sh`. Step 2's scan invocation is stubbed by replacing `claude` with a deterministic fixture-supplied script that writes a canned `baseline.json` matching the expected shape.

| # | Scenario | Expected outcome |
|---|---|---|
| 01-fresh-apply | v1.9.3 project, has `observability: spec_version: 0.2.1` block + `lib/observability/policy.md`, no `.github/workflows/observability.yml`, no `.observability/` | All 5 steps apply; workflow file present (matches scaffolder copy); baseline.json created with valid shape; CLAUDE.md has enforcement sub-block and spec_version 0.3.0; version is 1.10.0 |
| 02-idempotent-reapply | After fixture 01, re-run migration | Each step logs "skipped (already applied)"; no changes; exit 0 |
| 03-no-observability-metadata | v1.9.3 project, CLAUDE.md has no `observability:` block | Pre-flight aborts (exit 3) with the "run init first" message; no files created or modified |
| 04-existing-workflow-yml | v1.9.3 project with pre-existing `.github/workflows/observability.yml` (different content) | Step 1 backs up the existing file to `.observability.yml.bak.*` and overwrites with scaffolder copy; rest of migration proceeds; exit 0 |
| 05-baseline-already-present | v1.9.3 project with `.observability/baseline.json` pre-existing at `spec_version: 0.3.0` | Step 2 idempotency passes; no rewrite; rest proceeds |
| 06-rollback | After fixture 01, run rollback procedure | workflow file deleted (or .bak restored); baseline.json deleted; CLAUDE.md observability block reverted; SKILL.md back to 1.9.3 |
| 07-no-claude-cli | v1.9.3 project, project state OK, but `claude` binary absent from PATH (stubbed by clearing PATH for the verify step) | `requires.tool.claude.verify` fails pre-flight; clear error message; no files modified |

Each fixture ships:
- `before/` directory: starting project state.
- `expected-after/` directory: expected post-migration state (only files the migration touches, for diff-clarity).
- `assert.sh`: structural assertions (file presence, key strings, version field). Includes a `jq -e` schema-shape check on baseline.json for fixture 01 and 02.

**Idempotency / verification**:
- `bash migrations/run-tests.sh 0011` exits 0 with green output across all 7 fixtures.

**Commit**: `test(migrations): 0011 fixtures (7 scenarios)`

---

#### T9 — `migrations/run-tests.sh` `test_migration_0011()` stanza
**Touches**: `migrations/run-tests.sh`
**Change**: Add `test_migration_0011()` following the 0006/0007 pattern. Sandbox each fixture via `HOME=$TMP/home`; stub `claude` and `jq` binaries in `$HOME/bin` (PATH-prepended) for behavioural reproducibility. Add the function to the dispatcher's known-tests list.

**Idempotency / verification**:
- `bash migrations/run-tests.sh 0011` runs and reports green.
- `bash migrations/run-tests.sh preflight` (the Phase 13 audit) passes — verify path `~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md` resolves on a real install.

**Commit**: `test(migrations): wire 0011 into run-tests.sh + preflight audit`

---

### Phase 5 — Version bumps + CHANGELOG

#### T10 — Skill version bumps
**Touches**:
- `add-observability/SKILL.md` frontmatter: `version: 0.2.1` → `0.3.0`; `implements_spec: 0.2.1` → `0.3.0`; subcommand description text updated to mention `--since-commit` and `--update-baseline` and the new ci/ subdirectory.
- `skill/SKILL.md` (the scaffolder skill) frontmatter: `version: 1.9.3` → `1.10.0`.
- `add-observability/CONTRACT-VERIFICATION.md` — append a `## v0.3.0 §10.9 enforcement` section that maps each new MUST to the PLAN-task that satisfies it (uses the table from `14-REVIEWS.md` Q7 ledger).

**Idempotency / verification**:
- `grep -q '^version: 0.3.0$' add-observability/SKILL.md`
- `grep -q '^implements_spec: 0.3.0$' add-observability/SKILL.md`
- `grep -q '^version: 1.10.0$' skill/SKILL.md`
- `grep -q '## v0.3.0 §10.9 enforcement' add-observability/CONTRACT-VERIFICATION.md`

**Commit**: `chore(version): bump add-observability 0.2.1→0.3.0, scaffolder 1.9.3→1.10.0`

---

#### T11 — CHANGELOG entry
**Touches**: `CHANGELOG.md`
**Change**: New `[1.10.0] — Unreleased` section ABOVE `[1.9.3]`. Documents:
- New `--since-commit <ref>` and `--update-baseline` flags on the scan subcommand.
- New baseline file format (`.observability/baseline.json`, schema per spec §10.9.2).
- New delta artefact (`.observability/delta.json`), unconditional on `--since-commit`.
- New CI workflow template at `add-observability/ci/observability.yml` + adoption README.
- New migration 0011 (1.9.3 → 1.10.0) with 7-fixture test coverage.
- Spec target bumped: `implements_spec: 0.2.1` → `0.3.0`.
- Known limitation: GHA workflow requires Claude Code in CI (or self-hosted runner) until v1.11.0 ships the Node scanner port.
- Multi-AI review verdict (codex BLOCK → REQUEST-CHANGES → APPROVE; gemini REQUEST-CHANGES → APPROVE): 14-REVIEWS.md.

`[1.9.3]` line stamp is left as-is (the CHANGELOG hygiene PR to mark 1.9.3 as released is out of scope here — flagged for a follow-up).

**Idempotency / verification**:
- `grep -q '^## \[1.10.0\]' CHANGELOG.md`
- `grep -q 'observability enforcement' CHANGELOG.md`

**Commit**: `docs(changelog): record v1.10.0 — observability enforcement`

---

### Phase 6 — Regression check + close

#### T12 — Run all template contract tests
**Touches**: nothing (read-only).
**Change**: Run each stack's tests; record outcomes in VERIFICATION.md.

```bash
cd add-observability/templates/go-fly-http && go test ./...
cd ../ts-cloudflare-worker && npx vitest run
cd ../ts-supabase-edge && deno test
cd ../ts-react-vite && npx vitest run
```

Expected: 61 tests pass per CONTRACT-VERIFICATION.md. Any regression here is a stop-the-line bug.

**Verification**: capture test output to `.planning/phases/14-spec-10-9-enforcement/test-output.txt`.

**No commit**.

---

#### T12.5 — Smoke test: delta scan against this repo
**Touches**: nothing (read-only).
**Change**: Promised in CONTEXT.md. Run the delta scan procedure (as written in SCAN.md v0.3.0) against this repo's `feat/observability-enforcement-v1.10.0` vs `main`. The repo has no AgenticApps stack (no `path_root` manifests under templates/), so the scan should produce a "no AgenticApps stack detected" report — confirming both the stack-detection path and the delta scoping.

If a stack IS unexpectedly detected, this smoke test FAILS the PR — the implementation has a false-positive.

**Output**: capture markdown report + delta.json (well-formed per schema, even if empty) under `.planning/phases/14-spec-10-9-enforcement/smoke/`.

**No commit** — the smoke artefact is committed as part of T14.

---

#### T13 — Migration runner end-to-end
**Touches**: nothing.
**Change**: Run `bash migrations/run-tests.sh` (full suite) and `bash migrations/run-tests.sh preflight` (Phase 13 audit). Capture green status. Also run `jq` schema-shape assertions on a sample fixture 01 baseline.json:

```bash
jq -e '
  .spec_version == "0.3.0" and
  (.scanned_at | test("^[0-9]{4}")) and
  (.scanned_commit | test("^[a-f0-9]{40}$")) and
  (.module_roots | type == "array") and
  (.counts | (.conformant | type == "number") and (.high_confidence_gaps | type == "number")) and
  (.high_confidence_gaps_by_checklist | (.C1 | type == "number")) and
  (.policy_hash | test("^sha256:[a-f0-9]{64}$"))
' migrations/test-fixtures/0011/01-fresh-apply/expected-after/.observability/baseline.json
```

**No commit**.

---

#### T14 — VERIFICATION.md
**Touches**: `.planning/phases/14-spec-10-9-enforcement/VERIFICATION.md` (create).
**Change**: 1:1 must_have → evidence rows, incorporating the 6 additions from REVIEWS.md Q7:

| Must-have | Evidence |
|---|---|
| §10.9.1 `--since-commit` flag accepted | T1 SCAN.md Phase 0.5 |
| §10.9.1 delta scope = files in `git diff --name-only <ref>...HEAD` | T1 SCAN.md text + T12.5 smoke output |
| §10.9.1 confidence/output rules unchanged for delta | T1 SCAN.md Phase 3 unchanged; fixture-based assertion in T8 |
| §10.9.1 machine-readable summary emitted alongside report | T4 Phase 8 + unconditional-on-empty annotation |
| §10.9.2 canonical path `.observability/baseline.json` | T3 template + T4 Phase 7 + fixture 01 assert.sh |
| §10.9.2 schema byte-exact (all required fields present, types match) | T13 `jq -e` schema-shape check on fixture 01 |
| §10.9.2 `scanned_commit` is 40-char SHA | T13 jq regex assertion |
| §10.9.2 `policy_hash` is `sha256:<64-hex>` | T13 jq regex assertion |
| §10.9.2 `module_roots` sorted by (stack, path) | T4 Phase 7 sort directive; fixture 01 assert.sh checks ordering |
| §10.9.2 baseline regen on apply success | T5 APPLY.md Phase 6b |
| §10.9.2 `--update-baseline` manual override | T4 Phase 7 + SCAN.md "Inputs" |
| §10.9.3 reference CI workflow shipped | T6 observability.yml + ci/README.md |
| §10.9.3 (1) delta scan on every PR | T6 step in workflow + grep check |
| §10.9.3 (2) compare delta against baseline from merge-target branch | T6 "Compare delta vs baseline" step + base-baseline read step |
| §10.9.3 (3) fail PR if count increases | T6 logic `if D > 0: exit 1` (equivalent to "post-PR total > baseline") + structural test |
| §10.9.3 (4) surface findings as PR comment | T6 `marocchino/sticky-pull-request-comment` step (SHA-pinned) |
| §10.9.3 no silent opt-out | T6 "enforcement disabled" log + grep evidence |
| §10.8 enforcement sub-block in CLAUDE.md | T7 Step 3 + fixture 01 assert.sh |
| Migration 0011 applies cleanly + aborts gracefully on missing pre-conditions | T8 fixtures 01-07 + T9 run-tests.sh |
| All 61 v0.2.1 contract tests pass | T12 test-output.txt |
| Preflight audit (Phase 13) clean | T13 preflight output |
| GitHub Actions SHA-pinned (no floating tags) | T6 grep for `@[a-f0-9]{40}` |
| No `pull_request_target` trigger | T6 negative grep |
| Smoke: delta scan against this repo produces well-formed delta.json | T12.5 smoke output |

**Commit**: `docs(verification): phase 14 evidence ledger`

---

#### T15 — `gstack /review` post-phase
**Run**: `/review` against the full branch diff (or fall back to structured review pass). Two-stage: Stage 1 spec drift, Stage 2 code quality. REVIEW.md committed.

**Commit**: `docs(review): phase 14 — REVIEW.md`

---

#### T16 — `gstack /cso` post-phase (CI security)
**Run**: `/cso` focused on `ci/observability.yml` permission scoping, action pinning verification, secret exposure, prompt-injection threat surface. SECURITY.md committed.

**Commit**: `docs(security): phase 14 — SECURITY.md`

---

#### T17 — session handoff + PR open
**Touches**: `session-handoff.md` (overwrite previous); open PR.
**Change**: rewrite session-handoff.md per the global CLAUDE.md format. Open PR via `gh pr create` targeting `main` with title `feat: spec §10.9 observability enforcement (v1.10.0)`.

---

## Wave dependency graph (revised)

```
T1 (SCAN.md delta) ─┐
T2 (report template) ┤── (independent; parallel)
                     ▼
T3 (baseline-template.json) ─┐
T4 (SCAN.md baseline+delta writers) ─┤ T4 depends on T3
T5 (APPLY.md regen)           ─┤ T5 depends on T3 + T4
                              ▼
T6 (observability.yml + README) ── depends on T1+T4 (workflow invokes the new flags)
                              ▼
   (review gate ALREADY PASSED — this is v2 PLAN after REVIEWS.md)
                              ▼
T7 (migration 0011 .md)  ─┐
T8 (fixtures)            ─┤  T7→T8→T9 strict sequence
T9 (run-tests stanza)    ─┤
                          ▼
T10 (version bumps)      ─┐
T11 (CHANGELOG)          ─┤
                          ▼
T12 (template tests)     ─┐  Verification + close
T12.5 (smoke test)       ─┤
T13 (migration tests)    ─┤
T14 (VERIFICATION.md)    ─┤
T15 (/review → REVIEW.md)─┤
T16 (/cso → SECURITY.md) ─┤
T17 (handoff + PR)
```

Execution order: T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12, T12.5, T13, T14, T15, T16, T17.

---

## Risk register (revised — adds 4 from REVIEWS Q6)

| Risk | Likelihood | Mitigation |
|---|---|---|
| Template contract tests regress (T12 red) | Low — we touch no template code | Run after every commit; bisect early |
| Migration 0011 fixture 02 fails on Step 2 because stub `claude` is non-deterministic | Med | Stub writes a fixed baseline.json; idempotency check matches on `jq` shape, not raw bytes |
| GHA workflow YAML has a typo only catchable by GHA's parser | Med | T6 verification step: `python -c 'import yaml; yaml.safe_load(open("..."))'` |
| Spec drift between implementation and §10.9 wording | **Closed** — codex's BLOCK on Q1 forced spec-strict interpretation in this revision | n/a |
| Pre-flight audit (Phase 13) flags migration 0011 verify path | Med | Verify path uses `~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md` (canonical per migrations/README.md) |
| **Baseline.json merge conflicts on concurrent PRs** | High (when adopted at scale) | `ci/README.md` documents: rebase against main → run `scan --update-baseline` → re-commit. Don't merge-resolve counts manually. |
| **`claude` CLI absent in target environment** | Med (CI; non-Claude hosts) | Migration 0011 frontmatter `requires.tool.claude` with verify check. Fixture 07 exercises the abort path. |
| **CI environment brittleness (Claude Code in CI not fully supported)** | High at v1.10.0 | Documented in `ci/README.md` with three workarounds; targeted resolution in v1.11.0 Node scanner port |
| **`claude` running on untrusted PR content (prompt injection)** | Med | `pull_request` trigger (no secrets); read-only permissions; documented opt-out via `if: head.repo.full_name == github.repository` in `ci/README.md` |
| **GitHub Actions SHA pin staleness over time** | Low operationally, but pins eventually become CVE-vulnerable | `ci/README.md` includes a dependabot example config that updates SHA pins automatically |

---

## Out-of-scope (deferred)

- **Pre-commit hook template** (§10.9.4 MAY) — defer to v1.11.0.
- **Standalone Node scanner port** — defer to v1.11.0; track as issue at PR close.
- **GitLab / CircleCI workflow templates** — defer to v1.11.0+.
- **Dashboard reads of baseline.json** — separate agenticapps-dashboard change.
- **Retroactive enforcement on fx-signal-agent** — next session-handoff.
- **CHANGELOG stamping `[1.9.3]` as released** — separate hygiene PR.
