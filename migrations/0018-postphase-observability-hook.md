---
id: 0018
slug: postphase-observability-hook
title: GSD post-phase observability scan hook (advisory)
from_version: 1.16.0
to_version: 1.17.0
applies_to:
  - .claude/hooks/observability-postphase-scan.sh
  - .planning/config.json
optional_for:
  - projects without GSD (no .planning/ directory)
---

# Migration 0018 — GSD post-phase observability scan hook (advisory)

Brings projects from AgenticApps workflow v1.16.0 to v1.17.0 by installing the
advisory `observability-postphase-scan.sh` hook and wiring it into the GSD
post-phase chain (`.planning/config.json` → `hooks.post_phase.observability_scan`),
alongside the `spec_review` / `code_quality_review` / `security` / `qa` gates.

The hook delta-scans the phase diff with `add-observability scan --since-commit`
and WARNS (never blocks) when the phase introduced new high-confidence §10 gaps.
It is **advisory** (always `exit 0`) and a **no-op** until the project adopts
§10.9 enforcement (`.observability/baseline.json`). See ADR-0027.

This closes the one piece of §10.9 enforcement that belongs upstream as a
post-phase agent gate. It does NOT add the §10.9.3 CI gate or §10.9.4 pre-commit
hook — both remain deferred pending the deterministic Node scanner port.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.16.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.16.0"; exit 1; }

# GSD project — config.json is the installed copy of config-hooks.json (baseline 0000).
test -f .planning/config.json || { echo "ERROR: .planning/config.json missing — is this a GSD project? (optional_for non-GSD repos)"; exit 1; }
jq empty .planning/config.json || { echo "ERROR: .planning/config.json does not parse as JSON"; exit 1; }

# Scaffolder source present.
test -x ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/observability-postphase-scan.sh \
  || { echo "ERROR: scaffolder hook template missing/non-executable"; exit 1; }
```

## Steps

### Step 1 — Install the hook script into `.claude/hooks/`

**Idempotency check:** `test -x .claude/hooks/observability-postphase-scan.sh && grep -q 'observability-postphase-scan' .claude/hooks/observability-postphase-scan.sh`

**Pre-condition:** `.claude/` exists; scaffolder template present.

**Apply:**
```bash
mkdir -p .claude/hooks
cp ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/observability-postphase-scan.sh \
   .claude/hooks/observability-postphase-scan.sh
chmod +x .claude/hooks/observability-postphase-scan.sh
```

**Rollback:** `rm -f .claude/hooks/observability-postphase-scan.sh`

### Step 2 — Wire it into the GSD post-phase chain

Add the `observability_scan` declarative gate to `.planning/config.json` under
`hooks.post_phase`, pulling the entry verbatim from the scaffolder template so it
stays in lockstep.

**Idempotency check:** `jq -e '.hooks.post_phase.observability_scan' .planning/config.json >/dev/null 2>&1`

**Pre-condition:** `.planning/config.json` parses; scaffolder template present.

**Apply (deterministic via jq):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
ENTRY=$(jq '.hooks.post_phase.observability_scan' "$SCAFFOLDER/templates/config-hooks.json")
jq --argjson entry "$ENTRY" '
  .hooks //= {} |
  .hooks.post_phase //= {} |
  .hooks.post_phase.observability_scan = $entry
' .planning/config.json > .planning/config.json.tmp && mv .planning/config.json.tmp .planning/config.json
```

Setting a single key is idempotent by construction; the check above short-circuits
re-application.

**Rollback:**
```bash
jq 'del(.hooks.post_phase.observability_scan)' .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json
```

### Step 3 — Bump installed version field

**Idempotency check:** `grep -q '^version: 1.17.0' .claude/skills/agentic-apps-workflow/SKILL.md`

**Pre-condition:** `.claude/skills/agentic-apps-workflow/SKILL.md` exists with `version: 1.16.0`.

**Apply:** Edit the file frontmatter to change `version: 1.16.0` → `version: 1.17.0`.

**Rollback:** Edit `version: 1.17.0` → `version: 1.16.0`.

## Post-checks

```bash
# Hook present + executable
test -x .claude/hooks/observability-postphase-scan.sh

# Wired into the post-phase chain
jq -e '.hooks.post_phase.observability_scan.enabled == true' .planning/config.json >/dev/null
jq -e '.hooks.post_phase.observability_scan.blocking == false' .planning/config.json >/dev/null
jq -e '.hooks.post_phase.observability_scan.programmatic_hook == ".claude/hooks/observability-postphase-scan.sh"' .planning/config.json >/dev/null

# Advisory contract: the hook NEVER exits non-zero, even without a baseline.
( cd "$(mktemp -d)" && mkdir .planning && bash "$OLDPWD/.claude/hooks/observability-postphase-scan.sh" ); test $? -eq 0

# Version bumped
grep -q '^version: 1.17.0' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Notes

- **Advisory, not blocking** — the scan is LLM-driven (`add-observability` is at
  `implements_spec: 0.3.2`); a hard gate would add per-phase cost + nondeterminism.
  Promote to blocking only once the deterministic scanner ships (ADR-0027).
- **No-op without a baseline** — a project that hasn't run `/add-observability`
  has no `.observability/baseline.json` to delta against; the hook prints one
  explicit line and exits 0.
- **Idempotent** — all three steps are guarded; re-applying is a no-op.
- This `1.17.0` is the post-phase hook, independent of the long-deferred Node
  scanner port sometimes also called a "1.17.0 follow-up".
