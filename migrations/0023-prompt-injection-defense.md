---
id: 0023
slug: prompt-injection-defense
title: Wire §14 prompt-injection defense via injection-guard (v2.0.0 -> 2.1.0)
from_version: 2.0.0
to_version: 2.1.0
applies_to:
  - CLAUDE.md                                          # injection_guard: metadata block (written by /injection-guard init, consent gate 3)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.0.0 -> 2.1.0
  # §14 enforcement assets are scaffolded by /injection-guard init, NOT by this
  # migration (it delegates — see Step 1). For awareness, init may materialise:
  #   - the trust-classification static enforcement (TS ESLint rule / Go analyzer)
  #   - the fenceUntrusted + output-canary helpers
  #   - the untrusted-input registry doc
  #   - the attack-matrix §14 regression test
requires:
  - skill: injection-guard
    install: |
      git clone https://github.com/agenticapps-eu/agenticapps-observability \
        ~/.claude/skills/agenticapps-observability && \
      bash ~/.claude/skills/agenticapps-observability/install.sh
    verify: "test -f ~/.claude/skills/injection-guard/SKILL.md && grep -q '^name: injection-guard' ~/.claude/skills/injection-guard/SKILL.md"
---

# Migration 0023 — Prompt-injection defense via injection-guard (v2.0.0 -> 2.1.0)

This is the first additive feature migration on the post-SPLIT **2.x axis**
(`claude-workflow 2.1.0`). It propagates AgenticApps core spec **§14
(prompt-injection defense)** to every project on the fleet.

The §14 generator lives in **agenticapps-observability** as the
`injection-guard` skill (folded in there, superseding the earlier
claude-workflow brief — see ADR-0016 and obs `v0.13.0`). This migration does
**not** carry §14 assets itself. It does exactly three things:

1. **Pre-flight gate:** verify the `injection-guard` skill is installed (a
   sibling of `observability`, materialised by the obs `install.sh` symlink).
   No auto-install (mirrors 0022's D-03 contract) — abort with an actionable
   pointer if absent.
2. **Delegate the §14 scaffold** to the consent-gated `/injection-guard init`.
   The skill owns stack detection, applicability warnings, and its own three
   consent gates (assets → entry rewrite → metadata block). This migration must
   NOT inline a `cp` of templates (the skill is the generator) and must NOT call
   the obs `migrate-0023.sh` (its pre-flight requires the obs **1.21.0** consumer
   axis and would refuse on a claude-workflow 2.0.0 project — a different axis).
3. **Bump** the installed workflow version to `2.1.0`.

**Why a real 2.x migration (not a 1.x tombstone):** the update engine applies a
migration only when `installed >= from_version AND installed < to_version`.
After SPLIT-03's `0022-repoint`, every live project's installed
`agentic-apps-workflow` SKILL.md is at **2.0.0**. A `1.21 -> 1.22` tombstone is
`< 2.0.0` for all of them → silently skipped → never propagates. Only a
`from 2.0.0 -> to 2.1.0` migration reaches the fleet via
`/update-agenticapps-workflow`.

**Supported upgrade floor:** `2.0.0 -> 2.1.0`. Projects below 2.0.0 must first
replay the chain through 0022 (which lands them at 2.0.0) before 0023 matches.

## Pre-flight (hard aborts on failure)

```bash
# 1. The 'injection-guard' skill must be installed (sibling of 'observability',
#    created by agenticapps-observability/install.sh). No auto-install — abort
#    with an actionable pointer if absent.
test -f "$HOME/.claude/skills/injection-guard/SKILL.md" || {
  echo "ABORT: The 'injection-guard' skill is not installed."
  echo "It ships with agenticapps-observability (>= v0.13.0). Install/refresh it:"
  echo ""
  echo "  git clone https://github.com/agenticapps-eu/agenticapps-observability \\"
  echo "    ~/.claude/skills/agenticapps-observability"
  echo "  bash ~/.claude/skills/agenticapps-observability/install.sh"
  echo ""
  echo "(If obs is already cloned, just re-run its install.sh — it creates the"
  echo " ~/.claude/skills/injection-guard symlink.)"
  echo ""
  echo "Then re-run /update-agenticapps-workflow."
  exit 3
}

# 2. Workflow SKILL.md is at the supported floor (2.0.0), or 2.1.0 for re-apply.
grep -qE '^version: 2\.(0|1)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.0.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.0.0 -> 2.1.0."
  exit 3
}
```

Each abort exit-3 includes the remediation step. The migration is **not**
silently skipped — pre-flight failures must be resolved before it can apply.

## Steps

### Step 1 — Delegate the §14 scaffold to consent-gated `/injection-guard init`

**Idempotency check (positive — injection_guard metadata block PRESENT):**
```bash
grep -q '^injection_guard:' CLAUDE.md
```
(Returns 0 if `/injection-guard init` has already written its `injection_guard:`
metadata block — consent gate 3 — meaning the §14 scaffold is in place. Re-runs
skip Step 1.)

**Pre-condition:** the injection-guard skill is reachable (pre-flight #1 already
guaranteed this):
```bash
test -f "$HOME/.claude/skills/injection-guard/SKILL.md"
```

**Apply:** run the consent-gated init subcommand and let the skill drive:

```
/injection-guard init
```

The skill detects the project's stack(s), surfaces an `applicability_warning`
for stacks with no LLM prompt-building path, and materialises the §14 assets
behind its own three consent gates (assets → entry-file rewrite → `injection_guard:`
metadata block in CLAUDE.md). Do **not** substitute an inline `cp` of templates,
and do **not** invoke the obs `migrate-0023.sh` (wrong version axis — see header).

If the user declines at the skill's consent gates (e.g. a project with no LLM
path), no `injection_guard:` block is written and this step is a no-op — that is
an allowed outcome. The version bump (Step 2) still runs; the scaffold can be
adopted later by re-running `/injection-guard init`.

**Rollback:** the assets are owned by the skill. Revert with
`git checkout -- CLAUDE.md` for the metadata block and remove any §14 files the
init created in the working tree (`git status` lists them); or re-run
`/injection-guard scan` to re-derive state. No claude-workflow-owned file is
mutated by this step.

### Step 2 — Bump installed workflow version to 2.1.0

The version line lives in the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per migration 0011 `applies_to`
+ `install.sh` skill-name `agentic-apps-workflow`). This is NOT the
non-hyphenated dev-scaffolder clone path; targeting that form would silently
no-op the bump.

**Idempotency check (positive — exact hyphenated path + exact version line):**
```bash
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 2.0.0 floor):**
```bash
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0023.bak -E 's/^version: 2\.0\.0$/version: 2.1.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0023.bak
```

**Rollback:**
```bash
sed -i.0023.bak -E 's/^version: 2\.1\.0$/version: 2.0.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0023.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.1.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. If the §14 scaffold was accepted, the injection_guard: block exists in CLAUDE.md.
#    (Conditional — absent when the user declined init on a non-LLM project.)
grep -q '^injection_guard:' CLAUDE.md && echo "§14 scaffold present" \
  || echo "NOTE: injection-guard init not applied (declined / no LLM path) — version still bumped"
```

Post-check 1 is the hard guarantee. Post-check 2 is informational: the
delegated scaffold is consent-gated, so its absence is a valid declined-state,
not a failure.

## Skip cases

- **`from_version` mismatch** (project not at 2.0.0) → migration framework skips
  silently per the standard rule. Projects below 2.0.0 replay 0022 first.
- **`injection-guard` skill absent** → pre-flight ABORTS (exit 3) with the
  obs-install / `install.sh` pointer. NOT a silent skip and NOT an auto-install.
- **User declines `/injection-guard init` consent gates** → Step 1 is a no-op
  (no `injection_guard:` block); Step 2 still bumps the version to 2.1.0.

## Compatibility

- **Additive (minor) bump** to `2.1.0`: no breaking change to existing files.
  Only the version field is mutated by this migration; the §14 assets are owned
  and written by the `injection-guard` skill.
- **Distinct version axes (LOCKED, 29-CONTEXT "Version axes"):** the obs
  *consumer* axis is `1.x`, the obs *product* axis is `0.x`, and the
  claude-workflow axis is `2.x` (post-SPLIT). The obs `migrate-0023.sh` lives on
  the obs 1.x consumer axis (1.21.0 -> 1.22.0) and is irrelevant here — calling
  it on a 2.0.0 cw project would fail its pre-flight floor. This cw 0023 is the
  2.x-axis counterpart and the only shape that propagates to real projects.
- **Drift coupling:** as the highest-numbered migration file, 0023's
  `to_version` (2.1.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  is bumped to 2.1.0 in lockstep.

## References

- Core spec §14: `agenticapps-workflow-core/spec/14-prompt-injection.md` (0.6.0), ADR-0016
- Generator skill: `agenticapps-observability/injection-guard/` (obs `v0.13.0`)
- Obs consumer-axis migration (different axis): obs `migrations/0023` (1.21.0 -> 1.22.0)
- Superseded brief: `ADD-INJECTION-GUARD-MIGRATION.md` (stale; folded into obs)
- Sibling 2.x-axis precedent: `0022-observability-repoint-phase-sentinel.md`
