---
id: 0011
slug: observability-enforcement
title: Spec §10.9 — delta scan, baseline file, CI workflow (v0.3.0 enforcement layer)
from_version: 1.9.3
to_version: 1.10.0
applies_to:
  - .observability/baseline.json                  # initial baseline (created by Step 1)
  - CLAUDE.md                                     # observability metadata bump (0.2.1→0.3.0) + enforcement sub-block + Skills line
  - .claude/skills/agentic-apps-workflow/SKILL.md # version bump 1.9.3→1.10.0
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
---

# Migration 0011 — Spec §10.9 observability enforcement (local-first)

Brings projects from workflow v1.9.3 to v1.10.0 by installing the
**local enforcement layer** for AgenticApps spec §10 (observability):

1. Authors the initial `.observability/baseline.json` by invoking
   `claude /add-observability scan --update-baseline`.
2. Bumps the project's `observability:` metadata block:
   - `spec_version: 0.2.1` → `0.3.0`
   - Adds the new `enforcement:` sub-block (§10.8 OPTIONAL — declares
     the project's enforcement posture: baseline path + pre-commit
     toggle. The `ci:` field is omitted in v1.10.0 — see Notes.).
3. Adds a one-line cross-reference to the per-PR enforcement command
   in CLAUDE.md so contributors see how to validate locally before
   opening a PR.
4. Bumps the workflow scaffolder version to `1.10.0`.

**Not installed by this migration (v1.10.0)**: the CI workflow file at
`.github/workflows/observability.yml`. The skill ships a reference
GHA workflow at `add-observability/enforcement/observability.yml.example`
as an opt-in for projects with self-hosted runners or v1.11.0+
Node-scanner-port adopters. See `add-observability/enforcement/README.md`
for the rationale (Claude Code's CI installation isn't first-class on
hosted runners as of 2026-05).

ADR record: see `claude-workflow/.planning/phases/14-spec-10-9-enforcement/`
for the design discussion and multi-AI plan review.

## Pre-flight (hard aborts on failure)

```bash
# 1. Project HAS run /add-observability init (so observability: metadata block exists)
grep -q '^observability:' CLAUDE.md || {
  echo "ABORT: CLAUDE.md has no observability: metadata block."
  echo "Run 'claude /add-observability init' first to scaffold observability,"
  echo "then re-run /update-agenticapps-workflow."
  echo ""
  echo "(NOTE: projects on workflow v1.11.0+ get this handled automatically"
  echo " by migration 0013's Step 2 — upgrade via /update-agenticapps-workflow"
  echo " when you reach v1.12.0+. This abort path is the v1.9.3 → v1.10.0"
  echo " transition only.)"
  exit 3
}

# 2. policy.md exists at the metadata-declared (or default) path
POLICY_PATH=$(awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md | tr -d '"')
POLICY_PATH=${POLICY_PATH:-lib/observability/policy.md}
test -f "$POLICY_PATH" || {
  echo "ABORT: policy.md not found at $POLICY_PATH."
  echo "Re-run 'claude /add-observability init' to scaffold the wrapper + policy."
  exit 3
}

# 3. Workflow SKILL.md is at 1.9.3 (or 1.10.0 for re-apply)
grep -qE '^version: 1\.(9\.3|10\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  echo "ABORT: workflow scaffolder version is not 1.9.3."
  echo "Apply prior migrations first via /update-agenticapps-workflow."
  exit 3
}

# 4. Required tools available (also declared in frontmatter)
command -v claude >/dev/null || { echo "ABORT: claude CLI required"; exit 3; }
command -v jq >/dev/null     || { echo "ABORT: jq required"; exit 3; }
```

Each abort exit-3 includes the remediation step. Migration is **not**
silently skipped — pre-flight failures must be resolved before the
migration can apply.

## Steps

### Step 1 — Author initial baseline via scan

**Idempotency check:**
```bash
test -f .observability/baseline.json && \
  jq -e '.spec_version == "0.3.0"' .observability/baseline.json >/dev/null 2>&1
```
(returns 0 if a v0.3.0 baseline already exists; skip the scan)

**Pre-condition:** pre-flight passed — `policy.md` exists, project has
at least one git commit (asserted by pre-flight check #2 and via `git
rev-parse HEAD` succeeding).

**Apply:** the consuming agent (Claude Code session running
`/update-agenticapps-workflow`) follows the scan procedure in
`~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md`
with `--update-baseline`, using the project root as the working
directory. Step 1 establishes the conformance baseline locally; later
PRs validate against it via `claude /add-observability scan
--since-commit main` (per `add-observability/enforcement/README.md`).

Concretely:

```
Read ~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md
Execute Phases 1, 1.5 (full-scan branch), 2, 3, 4, 5, 6, 7.
Skip Phase 8 (no --since-commit).
End-state assertion: .observability/baseline.json exists with
  jq -e '.spec_version == "0.3.0"' returning 0.
```

The scan is non-destructive (per its own contract, it modifies no
source files). It creates `.observability/baseline.json` and
optionally rewrites `.scan-report.md`.

**Rollback:**
```bash
rm -rf .observability/
```

### Step 2 — Bump observability metadata in CLAUDE.md

**Idempotency check:**
```bash
grep -q '^  enforcement:' CLAUDE.md && grep -q '^  spec_version: 0.3.0' CLAUDE.md
```

**Pre-condition:** `grep -q '^observability:' CLAUDE.md` (asserted by
pre-flight check #1).

**Apply:**

Bump the spec_version line:
```bash
# In CLAUDE.md, within the observability: block, replace:
#   spec_version: 0.2.1
# with:
#   spec_version: 0.3.0
```

Then append the `enforcement:` sub-block beneath the existing
`observability:` block contents (typically directly after the `policy:`
line). The exact insertion uses an anchor: find the last non-blank
indented line in the `observability:` block, append the sub-block
below it.

Content to insert:
```yaml
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

Indentation is 2-space (matching spec §10.8 example lines 158-162).

**Note on the missing `ci:` field**: v1.10.0 ships local-only
enforcement (the reference CI workflow is opt-in, not installed by
this migration). Per spec §10.8 the `enforcement:` sub-block is
OPTIONAL and each declared field MUST be satisfied — by omitting
`ci:` we declare that this project does NOT claim §10.9.3 CI gating.
To opt in later: copy
`~/.claude/skills/agenticapps-workflow/add-observability/enforcement/observability.yml.example`
to `.github/workflows/observability.yml`, then add the line
`    ci: .github/workflows/observability.yml` to the enforcement
block. See `add-observability/enforcement/README.md`.

**Rollback:**
- Revert `spec_version: 0.3.0` → `spec_version: 0.2.1`.
- Remove the `enforcement:` sub-block (anchor: the four lines starting
  with `  enforcement:`).

### Step 3 — Document per-PR enforcement command in CLAUDE.md

**Idempotency check:**
```bash
grep -q '^### Observability enforcement (local)' CLAUDE.md && \
  grep -q 'add-observability scan --since-commit main' CLAUDE.md
```

**Pre-condition:** CLAUDE.md exists.

**Apply:** append the following block to the relevant section of
CLAUDE.md (Skills section if present, else under the observability
metadata block). v1.10.0 ships local-only enforcement, so this is
THE load-bearing developer touchpoint — the snippet documents both
the command and how to interpret its output.

```markdown
### Observability enforcement (local)

Before opening a PR, run:

```bash
claude /add-observability scan --since-commit main
```

Check `.observability/delta.json` — if `counts.high_confidence_gaps > 0`,
the PR introduces new high-confidence observability gaps. Fix with
`claude /add-observability scan-apply --confidence high` (per-file
consent) before pushing.

See `add-observability/enforcement/README.md` for the full local-first
workflow + the opt-in CI workflow example.
```

**Rollback:** remove the appended block (anchored by its `###
Observability enforcement (local)` header).

### Step 4 — Bump workflow scaffolder version

**Idempotency check:**
```bash
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**
```bash
grep -q '^version: 1.9.3$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.bak 's/^version: 1\.9\.3$/version: 1.10.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

**Rollback:**
```bash
sed -i.bak 's/^version: 1\.10\.0$/version: 1.9.3/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

## Post-checks

```bash
# 1. Baseline exists with correct shape
jq -e '
  .spec_version == "0.3.0" and
  (.scanned_commit | test("^[a-f0-9]{40}$")) and
  (.policy_hash    | test("^sha256:[a-f0-9]{64}$"))
' .observability/baseline.json

# 2. CLAUDE.md observability block bumped + enforcement sub-block present
grep -q '^  spec_version: 0.3.0' CLAUDE.md
grep -q '^  enforcement:' CLAUDE.md
grep -q '^    baseline: .observability/baseline.json' CLAUDE.md

# 3. Per-PR enforcement section + command reference present
grep -q '^### Observability enforcement (local)' CLAUDE.md
grep -q 'add-observability scan --since-commit main' CLAUDE.md

# 4. Workflow scaffolder version bumped
grep -q '^version: 1.10.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

All 4 post-checks return 0 on a successful apply. Each is also the
idempotency check for the matching step — re-applying the migration
finds them all green and reports "skipped (already applied)".

**Not checked by post-checks**: presence of the CI workflow at
`.github/workflows/observability.yml`. The migration does NOT install
it (v1.10.0 ships local-only enforcement); projects opting in to the
CI gate copy the example workflow manually per
`add-observability/enforcement/README.md`.

## Skip cases

- **`from_version` mismatch** (project is not at 1.9.3) → migration
  framework skips silently per the standard rule.
- **`observability:` metadata block absent** → pre-flight ABORTS (exit
  3) with the "run init first" message. NOT a silent skip — the user
  must take action.
- **`policy.md` absent** → pre-flight ABORTS with the "run init first"
  message.
- **`claude` or `jq` not in PATH** → pre-flight ABORTS via
  `requires.tool.<name>.verify` with the "install separately" message.

## Compatibility

- **Spec target**: this migration installs spec §10.9 (v0.3.0
  enforcement layer). Future patches within v0.3.x are clarification-
  only and ship without a new migration. Spec v0.4.0+ ships a new
  migration.

- **Backward compatibility with v1.9.3 projects**: projects that do
  NOT run this migration keep working at v1.9.3 — there's no breaking
  change in scan/init/scan-apply behaviour at v0.3.0. They simply
  don't have the enforcement layer.

- **CI environment**: the shipped `observability.yml` requires
  `claude` to be installable in the CI runner. As of v1.10.0, this
  works on self-hosted runners but not on hosted GHA runners
  out-of-the-box. The workflow ships dormant on hosted runners and
  fires when the v1.11.0 Node scanner port lands. See
  `add-observability/enforcement/README.md` "v1.10.0 status" for workarounds.

## References

- Spec §10.9: `agenticapps-workflow-core/spec/10-observability.md` (sections
  10.9.1 / 10.9.2 / 10.9.3 / 10.9.4)
- Reference workflow: `add-observability/enforcement/observability.yml.example` (opt-in)
- Adoption guide: `add-observability/enforcement/README.md`
- Phase plan: `.planning/phases/14-spec-10-9-enforcement/`
- ADR-0013 (migration framework): `claude-workflow/docs/decisions/0013-migration-framework.md`
- Prior observability migration: `0002-observability-spec-0.2.1.md` (1.4.0 → 1.5.0)
