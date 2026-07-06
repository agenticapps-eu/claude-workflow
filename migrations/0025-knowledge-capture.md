---
id: 0025
slug: knowledge-capture
title: Knowledge capture into the Obsidian vault — spec §15 (v2.2.0 -> 2.3.0)
from_version: 2.2.0
to_version: 2.3.0
applies_to:
  - .planning/config.json                              # insert knowledge_capture block if missing
  - .claude/skills/agentic-apps-workflow/SKILL.md      # append §15 ritual-tail section; version bump 2.2.0 -> 2.3.0
---

# Migration 0025 — Knowledge capture (v2.2.0 -> 2.3.0)

Implements core spec **§15 (knowledge capture)** for existing installs.
Transferable learnings currently die where they were made: the per-repo
`session-handoff.md` is overwritten by the next session, and ADRs/CHANGELOGs
capture repo-scoped facts by design. §15 routes 1–5 distilled, transferable
learnings to **one Obsidian note per repo**
(`~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/<repo-name>.md`)
at three ritual boundaries: session handoff, plan completion, phase completion.
See core ADR-0017 and this repo's ADR-0038.

Two changes reach existing installs:

1. `.planning/config.json` gains the `knowledge_capture` block (destination is
   **config-routed, never hardcoded** — repos stay self-contained; machines
   without the vault skip silently at trigger time).
2. The installed workflow skill gains the `## Knowledge Capture — Ritual Tail
   (spec §15)` section that wires the three trigger points.

Fresh installs get both from the snapshot (`setup/snapshot/planning-config.json`
+ `setup/snapshot/agentic-apps-workflow-SKILL.md`, laid down by `setup/SKILL.md`
Step 4a/4d); the drift guard (`migrations/check-snapshot-parity.sh` §3/§7) fails
if either ever drops out of the seed.

**Supported upgrade floor:** `2.2.0 -> 2.3.0`. Projects below 2.2.0 replay the
chain through 0024 first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (2.2.0), or 2.3.0 for re-apply.
grep -qE '^version: 2\.(2|3)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.2.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.2.0 -> 2.3.0."
  exit 3
}

# 2. jq is required (Step 1 edits JSON structurally, never with sed).
command -v jq >/dev/null || { echo "ABORT: jq required for migration 0025."; exit 3; }

# 3. The scaffolder's skill carries the section Step 2 extracts (guards against
#    running 0025 from a stale scaffolder clone).
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
grep -q '^## Knowledge Capture — Ritual Tail' "$SCAFFOLDER/skill/SKILL.md" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0025."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}
```

## Steps

### Step 1 — Insert the `knowledge_capture` block into `.planning/config.json`

Insert only if **missing** — a project that already carries the block (custom
`note`, `enabled: false`, …) is user-configured state and is preserved
verbatim. `<repo-name>` is written out literally at configuration time (spec
§15.2): resolve it NOW to the repo directory name; hosts never substitute
placeholders at runtime. The leading `~` stays literal in the config — the
skill expands it against `$HOME` at trigger time.

**Idempotency check (positive — block already present):**
```bash
jq -e 'has("knowledge_capture")' .planning/config.json >/dev/null 2>&1
```

**Apply (only when the block is absent; creates the file if the project has
no `.planning/config.json` at all):**
```bash
REPO_NAME="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
mkdir -p .planning
[ -f .planning/config.json ] || printf '{}\n' > .planning/config.json
jq --arg note "~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/${REPO_NAME}.md" \
  'if has("knowledge_capture") then . else . + {knowledge_capture: {enabled: true, note: $note}} end' \
  .planning/config.json > .planning/config.json.tmp \
  && mv .planning/config.json.tmp .planning/config.json
```

**Rollback:** `git checkout -- .planning/config.json` (the file is committed
project state). If Step 1 created the file, `rm .planning/config.json`.

### Step 2 — Append the ritual-tail section to the installed skill

The section is **extracted from the scaffolder's `skill/SKILL.md`** (single
source of truth) rather than duplicated here, so a migrated install is
byte-identical to a fresh snapshot install and the text cannot drift.

**Idempotency check (positive — section already present):**
```bash
grep -q '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
{
  printf '\n'
  awk '/^## Knowledge Capture — Ritual Tail/{f=1} f' "$SCAFFOLDER/skill/SKILL.md"
} >> .claude/skills/agentic-apps-workflow/SKILL.md
```

(The section is the last one in `skill/SKILL.md`, so `awk` from the heading to
EOF captures exactly it. Pre-flight check 3 guarantees the heading exists.)

**Rollback:** delete from the heading to EOF:
```bash
sed -i.0025.bak '/^## Knowledge Capture — Ritual Tail/,$d' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
```

### Step 3 — Bump installed workflow version to 2.3.0

The version line lives at the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per 0011 `applies_to` +
`install.sh` skill-name). NOT the non-hyphenated dev-scaffolder clone path.

**Idempotency check (positive):**
```bash
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 2.2.0 floor):**
```bash
grep -q '^version: 2.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0025.bak -E 's/^version: 2\.2\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
```

**Rollback:**
```bash
sed -i.0025.bak -E 's/^version: 2\.3\.0$/version: 2.2.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0025.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.3.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. knowledge_capture block present, enabled is boolean, no unresolved placeholder
jq -e '.knowledge_capture.enabled | type == "boolean"' .planning/config.json >/dev/null
! grep -qF '<repo-name>' .planning/config.json

# 3. Ritual-tail section present exactly once
[ "$(grep -c '^## Knowledge Capture — Ritual Tail' .claude/skills/agentic-apps-workflow/SKILL.md)" = "1" ]
```

All three post-checks are hard guarantees.

**This migration never touches the vault.** It only teaches the project where
the note lives; the first write happens at the next ritual boundary, and only
on a machine where the vault folder exists (graceful skip everywhere else —
CI, containers, other workstations).

## Skip cases

- **`from_version` mismatch** (project not at 2.2.0) → migration framework
  skips silently per the standard rule. Projects below 2.2.0 replay 0024 first.
- **Block already present** (any shape, including `enabled: false` or a custom
  `note`) → Step 1 is a no-op; user configuration is never overwritten.
- **No `.planning/config.json`** → Step 1 creates it containing only the
  `knowledge_capture` block (GSD adds its own sections at its own init).

## Compatibility

- **Additive (minor) bump** to `2.3.0`: no breaking change. Step 1 only adds a
  key (structural `jq` edit, whole-file rewrite preserves all other sections);
  Step 2 only appends a section; nothing existing is modified or removed.
- **Opt-out stays local:** setting `enabled: false` (or deleting the block)
  disables capture for the repo without re-running any migration; a missing
  vault folder disables it per machine with a single info line.
- **Drift coupling:** as the highest-numbered migration file, 0025's
  `to_version` (2.3.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  is bumped to 2.3.0 in lockstep, and `check-snapshot-parity.sh` §5 requires
  the snapshot VERSION to equal it.

## Downstream hosts

`codex-workflow` and `opencode-workflow` must mirror §15 in their own idiom:
seed the `knowledge_capture` block (their config template), wire the three
trigger points into their ritual instructions, and honor the graceful skip.
Their log-entry host tag is their own (`(codex)` / `(opencode)`). Tracked in
ADR-0038.

## References

- Spec: `agenticapps-workflow-core/spec/15-knowledge-capture.md` (v0.7.0)
- Core ADR: `agenticapps-workflow-core/adrs/0017-knowledge-capture-obsidian.md`
- ADR: `docs/decisions/0038-knowledge-capture.md`
- Vault-side schema (authoritative for writes):
  `~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/CLAUDE.md`
- First-write skeleton: `templates/obsidian-learnings-note.md`
- Fresh-install path: `setup/snapshot/planning-config.json` +
  `setup/snapshot/agentic-apps-workflow-SKILL.md`, `setup/SKILL.md` Step 4d
- Drift invariants: `migrations/check-snapshot-parity.sh` §3 + §7
- Sibling 2.x-axis precedent: `0024-commit-planning-phases.md`
