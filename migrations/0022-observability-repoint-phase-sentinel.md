---
id: 0022
slug: observability-repoint-phase-sentinel
title: Repoint observability to agenticapps-observability; replace Phase Sentinel hook (v1.20.0 -> 2.0.0)
from_version: 1.20.0
to_version: 2.0.0
applies_to:
  - CLAUDE.md                                          # observability: block cross-reference repoint (add-observability -> observability)
  - .claude/settings.json                             # Hook 3 Stop block replacement (Haiku prompt -> type:command)
  - .claude/hooks/phase-sentinel.sh                    # new deterministic hook script (GH #58)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 1.20.0 -> 2.0.0
requires:
  - skill: observability
    install: |
      git clone https://github.com/agenticapps-eu/agenticapps-observability \
        ~/.claude/skills/agenticapps-observability && \
      bash ~/.claude/skills/agenticapps-observability/install.sh
    verify: "test -f ~/.claude/skills/observability/SKILL.md && grep -q '^name: observability' ~/.claude/skills/observability/SKILL.md"
---

# Migration 0022 — Repoint observability + Phase Sentinel hook (v1.20.0 -> 2.0.0)

This is the breaking cleanup migration for `claude-workflow 2.0.0` (SPLIT-03).
It supersedes migration `0011`'s observability install step **without mutating
0011** (immutability contract — 0011 stays byte-identical). 0022 chains off the
current chain endpoint (`from_version: 1.20.0`), NOT off 0011.

It folds three deliverables into a single `to_version: 2.0.0` migration:

1. **Repoint** the observability install from the in-repo `add-observability`
   skill to the now-separately-installed `observability` skill
   (`agenticapps-eu/agenticapps-observability`). The skill is a **separate
   install** — this migration verifies its presence and aborts with an
   actionable pointer if absent; it does **not** auto-install (D-03).
2. **Replace the Phase Sentinel Stop hook** (GH #58, D-07): the Haiku
   `prompt`-type Hook 3 is swapped for a deterministic 28-line shell gate
   `phase-sentinel.sh` (exit 0 allow / exit 2 block).
3. **Bump** the installed workflow version to `2.0.0` (D-04).

**Supported upgrade floor:** the supported upgrade path is `1.21.0 -> 2.0.0`
(the Phase 27 SPLIT-00 stable baseline that all live downstreams are parked at).
0022 chains from the current endpoint `1.20.0 -> 2.0.0`; pre-baseline
(`< 1.21.0`) full-chain replay is out of support scope (documented in
`docs/UPGRADING.md`). The one-line `requires.verify` obs-identity check
(`name: observability`) is the compatibility gate; a numeric version floor is
optional and not required for the 0-1 live consumers today.

## Pre-flight (hard aborts on failure)

```bash
# Supported upgrade floor: 1.21.0 -> 2.0.0 (Phase 27 SPLIT-00 baseline). Pre-baseline replay unsupported.

# 1. The 'observability' skill must be installed as a SEPARATE install.
#    No auto-install (D-03) — abort with an actionable pointer if absent.
test -f "$HOME/.claude/skills/observability/SKILL.md" || {
  echo "ABORT: The 'observability' skill is not installed."
  echo "Install agenticapps-observability separately:"
  echo ""
  echo "  git clone https://github.com/agenticapps-eu/agenticapps-observability \\"
  echo "    ~/.claude/skills/agenticapps-observability"
  echo "  bash ~/.claude/skills/agenticapps-observability/install.sh"
  echo ""
  echo "Then re-run /update-agenticapps-workflow."
  exit 3
}

# 2. Workflow SKILL.md is at the supported baseline (1.20.0/1.21.0), or 2.0.0 for re-apply.
grep -qE '^version: (1\.(20|21)\.0|2\.0\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 1.20.0/1.21.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 1.21.0 -> 2.0.0 (pre-baseline replay unsupported)."
  exit 3
}
```

Each abort exit-3 includes the remediation step. The migration is **not**
silently skipped — pre-flight failures must be resolved before it can apply.

## Steps

### Step 1 — Repoint observability requires in the project's CLAUDE.md

**Idempotency check (positive — repointed name PRESENT):**
```bash
grep -q 'skill: observability' CLAUDE.md
```
(Returns 0 if the project's observability metadata/Skills line already names
`observability` rather than `add-observability` — the repoint is done.)

**Pre-condition:**
```bash
grep -q '^observability:' CLAUDE.md
```
(The project has an `observability:` metadata block to repoint.)

**Apply:** in the observability metadata block / Skills line ONLY, rewrite the
skill name `add-observability` to `observability`. Do NOT rewrite historical
prose, links, or examples elsewhere in CLAUDE.md — only the forward-looking
skill reference inside the `observability:` block / Skills entry.

```bash
# Repoint the skill name in the observability metadata block / Skills line only.
# Anchor the substitution to the 'skill:' (or 'Skills:') reference, not free prose.
sed -i.0022.bak -E 's/(skill: )add-observability/\1observability/' CLAUDE.md
rm -f CLAUDE.md.0022.bak
```

**Rollback:** revert the repointed line:
```bash
sed -i.0022.bak -E 's/(skill: )observability/\1add-observability/' CLAUDE.md
rm -f CLAUDE.md.0022.bak
```

### Step 2 — Install the deterministic Phase Sentinel hook (GH #58 / D-07)

**Idempotency check (positive — hook PRESENT + executable):**
```bash
test -x .claude/hooks/phase-sentinel.sh && grep -q 'set -euo pipefail' .claude/hooks/phase-sentinel.sh
```

**Pre-condition:** `test -d .claude/hooks` (or create it).

**Apply:** write the verbatim `phase-sentinel.sh` body (byte-identical to the
template shipped in `templates/.claude/hooks/phase-sentinel.sh`) into
`.claude/hooks/phase-sentinel.sh`, then `chmod +x`:

```bash
mkdir -p .claude/hooks
cat > .claude/hooks/phase-sentinel.sh <<'EOF_PHASE_SENTINEL'
#!/usr/bin/env bash
# phase-sentinel.sh — deterministic Stop hook.
# Allows stop unless .planning/current-phase/checklist.md exists AND
# contains unchecked `- [ ]` items.

set -euo pipefail

checklist="${CLAUDE_PROJECT_DIR:-$PWD}/.planning/current-phase/checklist.md"

[ -f "$checklist" ] || exit 0

unchecked=$(grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" || true)
[ "${unchecked:-0}" -eq 0 ] && exit 0

echo "Phase Sentinel: $unchecked unchecked item(s) remain in $checklist:" >&2
# `|| true`: under `set -euo pipefail`, `head -5` closing the pipe early (>5 items)
# kills grep with SIGPIPE, making the pipeline non-zero and exiting before `exit 2`.
# Swallowing the status guarantees the block contract (exit 2) always holds.
grep -E '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' "$checklist" | head -5 >&2 || true
exit 2
EOF_PHASE_SENTINEL
chmod +x .claude/hooks/phase-sentinel.sh
```

**Rollback:** `rm -f .claude/hooks/phase-sentinel.sh`

### Step 3 — Swap the Stop hook in .claude/settings.json (GH #58 / D-07)

**Idempotency check (positive — the deterministic command hook is PRESENT):**
```bash
jq -e '.. | objects | select(.type? == "command" and (.command? // "" | test("phase-sentinel.sh")))' .claude/settings.json >/dev/null
```
(Asserts the correct `type:command` phase-sentinel hook EXISTS — not merely that
the old prompt text is gone.)

**Pre-condition:** `test -f .claude/settings.json`

**Apply:** reconstruct the `.hooks.Stop` array with `jq` — drop the entry whose
inner hook has `type == "prompt"` AND whose `prompt` contains the
`current-phase/checklist.md` substring (Pitfall 5: a narrow selector so we never
delete an unrelated hook), then append the deterministic command entry. Exact
filter:

```bash
jq '
  .hooks.Stop = (
    [ .hooks.Stop[]
      | select(
          ( [ .hooks[]?
              | select(.type? == "prompt"
                       and ((.prompt? // "") | test("current-phase/checklist.md"))) ]
            | length ) == 0
        )
    ]
    + [ {
          "_hook": "Hook 3 — Phase Sentinel (deterministic shell)",
          "hooks": [
            {
              "type": "command",
              "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/phase-sentinel.sh",
              "timeout": 5000
            }
          ]
        } ]
  )
' .claude/settings.json > .claude/settings.json.0022.tmp \
  && mv .claude/settings.json.0022.tmp .claude/settings.json
```

**Rollback:** restore the prior Stop array from git:
```bash
git checkout -- .claude/settings.json
```

### Step 4 — Bump installed workflow version to 2.0.0

The version line lives in the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per migration 0011 `applies_to`
+ `install.sh:42` skill-name `agentic-apps-workflow`). This is NOT the
non-hyphenated dev-scaffolder clone path; targeting that form would silently
no-op the bump.

**Idempotency check (positive — exact hyphenated path + exact version line):**
```bash
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 1.20/1.21 baseline):**
```bash
grep -qE '^version: 1\.(20|21)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0022.bak -E 's/^version: 1\.(20|21)\.0$/version: 2.0.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0022.bak
```

**Rollback:**
```bash
sed -i.0022.bak -E 's/^version: 2\.0\.0$/version: 1.20.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0022.bak
```

## Post-checks (all POSITIVE)

```bash
# 1. Repoint applied: observability skill named (not add-observability)
grep -q 'skill: observability' CLAUDE.md

# 2. Deterministic hook installed + executable
test -x .claude/hooks/phase-sentinel.sh
grep -q 'set -euo pipefail' .claude/hooks/phase-sentinel.sh

# 3. Stop block carries the type:command phase-sentinel hook (positive jq select) + valid JSON
jq -e '.. | objects | select(.type? == "command" and (.command? // "" | test("phase-sentinel.sh")))' .claude/settings.json >/dev/null
jq . .claude/settings.json >/dev/null

# 4. Version bumped to 2.0.0 at the canonical hyphenated path
grep -q '^version: 2.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

All four post-checks return 0 on a successful apply. Each is also the idempotency
check for its matching step — re-applying finds them all green and reports
"skipped (already applied)".

## Skip cases

- **`from_version` mismatch** (project not at 1.20.0) → migration framework
  skips silently per the standard rule.
- **`observability` skill absent** → pre-flight ABORTS (exit 3) with the
  separate-install pointer. NOT a silent skip and NOT an auto-install (D-03) —
  the user must install agenticapps-observability and re-run.
- **`observability:` metadata block absent in CLAUDE.md** → Step 1's
  pre-condition fails; the repoint step is skipped (nothing to repoint), the
  hook/version steps still run.

## Compatibility

- **Supersedes 0011's install step** without mutating 0011 (immutability
  contract). 0011 stays byte-identical; the obs repo's `add-observability`
  dual-symlink alias keeps 0011's old-name runtime verify resolving.
- **Breaking (major) bump** to `2.0.0`: the observability skill is now a
  separate install. Projects that do not install it cannot complete this
  migration (fails closed at pre-flight).
- **Downstream at 1.20.0/1.21.0:** replays the chain → hits only 0022 → applies
  → installed version becomes `2.0.0`.

## References

- Phase plan: `.planning/phases/30-split-03-claude-workflow-2-0-0-follow-up/`
- Superseded install step: `0011-observability-enforcement.md` (NOT mutated)
- Sibling repo install contract: `agenticapps-observability/install.sh`
  (canonical symlink `~/.claude/skills/observability` + `add-observability` alias)
- GH issue #58: deterministic Phase Sentinel hook
- Downstream upgrade story: `docs/UPGRADING.md` (1.21.0 -> 2.0.0)
