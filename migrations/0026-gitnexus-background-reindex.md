---
id: 0026
slug: gitnexus-background-reindex
title: GitNexus background reindex hook — reindex, not nudge (v2.3.0 -> 2.4.0)
from_version: 2.3.0
to_version: 2.4.0
applies_to:
  - .claude/hooks/gitnexus-reindex.cjs                 # copy the engine from the scaffolder snapshot
  - .claude/settings.json                              # add one PostToolUse matcher:"Bash" entry
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.3.0 -> 2.4.0
---

# Migration 0026 — GitNexus background reindex (v2.3.0 -> 2.4.0)

Ships a **claude-workflow-owned, per-project** PostToolUse hook that runs a
detached, incremental `gitnexus analyze` after a git commit, so the repo's
GitNexus index self-heals instead of relying on the agent to act on gitnexus's
global staleness *nudge*. The two coexist: after a commit our hook fires a
background reindex → `meta.lastCommit` catches up to `HEAD` → gitnexus's global
nudge sees them equal on its next call and self-silences. Nothing global is
modified. See ADR-0039.

Two things reach existing installs:

1. `.claude/hooks/gitnexus-reindex.cjs` — the engine (copied verbatim from the
   scaffolder's snapshot, so a migrated install is byte-identical to a fresh
   snapshot install), chmod +x.
2. `.claude/settings.json` gains one `PostToolUse` `matcher:"Bash"` entry
   binding the engine.

Fresh installs get both from the snapshot (`setup/snapshot/hooks/gitnexus-reindex.cjs`
+ the `PostToolUse` entry in `setup/snapshot/claude-settings.json`, laid down by
`setup/SKILL.md` Step 4c); the drift guard (`migrations/check-snapshot-parity.sh`
§2 + §8) fails if the engine or its binding ever drops out of the seed.

**Supported upgrade floor:** `2.3.0 -> 2.4.0`. Projects below 2.3.0 replay the
chain through 0025 first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (2.3.0), or 2.4.0 for re-apply.
grep -qE '^version: 2\.(3|4)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.3.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.3.0 -> 2.4.0."
  exit 3
}

# 2. jq is required (Step 2 edits JSON structurally, never with sed).
command -v jq >/dev/null || { echo "ABORT: jq required for migration 0026."; exit 3; }

# 3. The scaffolder's snapshot carries the engine Step 1 copies (guards against
#    running 0026 from a stale scaffolder clone).
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
test -f "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0026."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}

# 4. .claude/settings.json exists and is valid JSON (baselined by 0000).
test -f .claude/settings.json || { echo "ABORT: .claude/settings.json missing — was 0000-baseline applied?"; exit 3; }
jq empty .claude/settings.json 2>/dev/null || { echo "ABORT: .claude/settings.json is not valid JSON."; exit 3; }
```

## Steps

### Step 1 — Copy the reindex engine into `.claude/hooks/`

The engine is **copied from the scaffolder's snapshot** (single source of
truth) rather than duplicated here, so a migrated install is byte-identical to
a fresh snapshot install and the code cannot drift.

**Idempotency check (positive — engine already installed and identical):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
cmp -s "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" \
       .claude/hooks/gitnexus-reindex.cjs 2>/dev/null
```

**Apply (only when absent or differing; preserves a user-customized hook —
`cmp` above already returned non-zero, so we overwrite only a stale/missing copy):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
mkdir -p .claude/hooks
cp "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
```

**Rollback:** `rm -f .claude/hooks/gitnexus-reindex.cjs`

### Step 2 — Wire the PostToolUse Bash entry into `.claude/settings.json`

Insert only if **no** entry already binds `gitnexus-reindex`; an existing
binding (including a user-edited one) is preserved verbatim. The insert is
append-only and structural (`jq`), so all other hooks survive.

**Idempotency check (positive — already wired):**
```bash
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))' \
  .claude/settings.json >/dev/null 2>&1
```

**Apply (guarded merge, append-only-if-absent):**
```bash
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

The `any(...)` guard makes re-running a no-op — it can never duplicate the entry.

**Rollback:**
```bash
jq '.hooks.PostToolUse |= map(select(.hooks[]?.command? | strings | test("gitnexus-reindex") | not))' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

### Step 3 — Bump installed workflow version to 2.4.0

The version line lives at the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per 0011 `applies_to` +
`install.sh` skill-name). NOT the non-hyphenated dev-scaffolder clone path.

**Idempotency check (positive):**
```bash
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 2.3.0 floor):**
```bash
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0026.bak -E 's/^version: 2\.3\.0$/version: 2.4.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
```

**Rollback:**
```bash
sed -i.0026.bak -E 's/^version: 2\.4\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.4.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. Engine installed + executable
test -x .claude/hooks/gitnexus-reindex.cjs

# 3. Exactly one gitnexus-reindex PostToolUse entry, matcher is Bash
COUNT=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$COUNT" = "1" ]
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .matcher == "Bash"' .claude/settings.json >/dev/null
```

All four post-checks are hard guarantees.

**This migration never runs `gitnexus analyze`.** It only installs the hook; the
first reindex happens at the next commit, and only in a repo that already has a
`.gitnexus/` directory (the engine no-ops everywhere else — CI, containers,
non-indexed repos).

## Skip cases

- **`from_version` mismatch** (project not at 2.3.0) → migration framework skips
  silently per the standard rule. Projects below 2.3.0 replay 0025 first.
- **Engine already installed and identical** → Step 1 is a no-op (`cmp` match).
- **Entry already wired** (any shape, including a user-edited command) → Step 2
  is a no-op; user configuration is never overwritten.
- **Repo without gitnexus** → the hook installs but no-ops at runtime (no
  `.gitnexus/` directory), so the migration is harmless everywhere.

## Compatibility

- **Additive (minor) bump** to `2.4.0`: no breaking change. Step 1 adds a file;
  Step 2 appends one hook entry (structural `jq`, whole-file rewrite preserves
  all other hooks); nothing existing is modified or removed.
- **Kill switch stays local:** `export GITNEXUS_AUTOREINDEX_DISABLED=1` disables
  the reindex per shell without re-running any migration; removing the settings
  entry (Step 2 rollback) disables it per repo.
- **Drift coupling:** as the highest-numbered migration file, 0026's
  `to_version` (2.4.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  is bumped to 2.4.0 in lockstep, and `check-snapshot-parity.sh` §5 requires the
  snapshot VERSION to equal it.

## Downstream hosts

`codex-workflow` and `opencode-workflow` already carry the shared reindex engine
as host-local config (`~/.gitnexus-hooks/` + the opencode plugin). Productizing
it into their own snapshots (their idiom for per-project hooks) is tracked in
ADR-0039; this migration is the Claude-host productization only.

## References

- Spec: `docs/superpowers/specs/2026-07-08-gitnexus-background-reindex-design.md`
- ADR: `docs/decisions/0039-gitnexus-background-reindex.md`
- Ported from the validated engine `~/.gitnexus-hooks/reindex-on-change.cjs`
- Fresh-install path: `setup/snapshot/hooks/gitnexus-reindex.cjs` +
  `setup/snapshot/claude-settings.json`, `setup/SKILL.md` Step 4c
- Drift invariants: `migrations/check-snapshot-parity.sh` §2 + §8
- Sibling copy+wire precedent: `0005-multi-ai-plan-review-enforcement.md`
- Sibling 2.x-axis precedent: `0025-knowledge-capture.md`
