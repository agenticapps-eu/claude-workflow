---
id: 0006
slug: llm-wiki-builder-integration
title: Integrate LLM wiki compiler (Karpathy pattern) per family
from_version: 1.9.1
to_version: 1.9.2
applies_to:
  - .claude/plugins/llm-wiki-compiler (symlink into ~/.claude/plugins/)
  - <family>/.wiki-compiler.json (per family, generated if absent)
  - <family>/.knowledge/{raw,wiki}/ (per family)
  - <family>/CLAUDE.md (## Knowledge wiki section appended if file exists)
  - templates/.claude/scripts/install-wiki-compiler.sh (the apply script)
  - templates/.claude/scripts/rollback-wiki-compiler.sh (the rollback script)
requires:
  - plugin: ussumant/llm-wiki-compiler v2.1.0+ (vendored at ~/Sourcecode/agenticapps/wiki-builder/)
    install: "test -d ~/Sourcecode/agenticapps/wiki-builder/plugin || git clone --depth=1 https://github.com/ussumant/llm-wiki-compiler.git ~/Sourcecode/agenticapps/wiki-builder"
    verify: "test -f ~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json"
  - tool: jq
    install: "command -v jq >/dev/null 2>&1 || { echo 'jq is required for migration 0006. Install: brew install jq (macOS) / apt install jq (Linux)'; exit 1; }"
    verify: "command -v jq >/dev/null"
optional_for:
  - machines without a `~/Sourcecode/` layout (the family-detection step finds 0 families and the install is a host-only symlink)
---

# Migration 0006 — LLM wiki compiler integration

Brings projects from workflow v1.9.1 to v1.9.2 by installing the vendored `ussumant/llm-wiki-compiler` plugin globally and scaffolding per-family wiki infrastructure. Implements Andrej Karpathy's LLM Knowledge Base pattern. See ADR 0019 for design rationale.

## Summary

The migration installs at three scope levels:

1. **Host-level** — symlinks `~/.claude/plugins/llm-wiki-compiler` to the vendored plugin source. Makes `/wiki-compile`, `/wiki-lint`, `/wiki-query`, `/wiki-search` discoverable across all Claude Code sessions on the host.
2. **Family-level** — for each detected family directory under `~/Sourcecode/` (heuristic: must contain child git repos, NOT in skip-list `personal|shared|archive|.*`), scaffolds `.knowledge/{raw,wiki}/` dirs, a `.gitignore`, a default `.wiki-compiler.json` config (preserving any user-customized config), and appends a `## Knowledge wiki` section to the family's `CLAUDE.md` (only if the file exists — does NOT create one from scratch).
3. **Per-project** — bumps `.claude/skills/agentic-apps-workflow/SKILL.md` version field to 1.9.2.

All steps are idempotent. Rollback is preserve-data: removes the host symlink and reverts the version, leaves family-level state untouched. See `templates/.claude/scripts/install-wiki-compiler.sh` for the executable apply body and `rollback-wiki-compiler.sh` for the rollback body — both shipped from this PR.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.9.1" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.9.1"; exit 1; }

test -d ~/Sourcecode/agenticapps/wiki-builder/plugin \
  || { echo "ERROR: wiki-builder plugin not vendored. Clone from https://github.com/ussumant/llm-wiki-compiler.git into ~/Sourcecode/agenticapps/wiki-builder"; exit 1; }

test -f ~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json \
  || { echo "ERROR: vendored plugin missing manifest at ~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json"; exit 1; }
```

## Apply

The migration delegates to the vendored install script. All policy decisions (symlink ABORT-on-wrong-target per codex B2, skip-when-CLAUDE.md-missing per codex B3, child-`.git` family heuristic per codex F2) live in the script.

**Idempotency check:** entire apply is a no-op when `grep -q '^version: 1.9.2$' .claude/skills/agentic-apps-workflow/SKILL.md` matches.

```bash
bash templates/.claude/scripts/install-wiki-compiler.sh
```

Or, for consumer projects pulling from the published scaffolder:

```bash
bash ~/.claude/skills/agenticapps-workflow/templates/install-wiki-compiler.sh
```

### What the script does, in order:

1. **Pre-flight** — re-verifies SKILL.md version + vendored plugin manifest (defense-in-depth with the pre-flight block above).
2. **Step 1 — host symlink** — `~/.claude/plugins/llm-wiki-compiler` → vendored plugin. ABORTs if the path exists as a real file (refuses to clobber) or as a wrong-target symlink (refuses to repoint silently).
3. **Step 2 — family detection** — scans `~/Sourcecode/*/` for directories containing child git repos. Skips `personal|shared|archive|.*`.
4. **Step 3 — per-family dirs** — `<family>/.knowledge/{raw,wiki}/` + `.gitignore`. ABORTs if `.knowledge` exists as a regular file.
5. **Step 4 — per-family configs** — `<family>/.wiki-compiler.json` if absent. Preserves any existing file (even if malformed — emits warning).
6. **Step 5 — per-family CLAUDE.md** — appends `## Knowledge wiki` section if the heading isn't already present. Skips with a `note:` if the file doesn't exist.
7. **Step 6 — version bump** — `SKILL.md` 1.9.1 → 1.9.2.

## Verify

```bash
# Plugin discoverable
test -L ~/.claude/plugins/llm-wiki-compiler || exit 1
test -f ~/.claude/plugins/llm-wiki-compiler/.claude-plugin/plugin.json || exit 1
jq empty ~/.claude/plugins/llm-wiki-compiler/.claude-plugin/plugin.json || exit 1

# At least one family scaffolded (skip if no families on this host)
FAMILY_COUNT=$(ls ~/Sourcecode/*/.wiki-compiler.json 2>/dev/null | wc -l | tr -d ' ')
echo "Families with .wiki-compiler.json: $FAMILY_COUNT"

# Each family config parses (Stage 2 FLAG-A fix: handle no-match + preserved-malformed cases)
shopt -s nullglob 2>/dev/null || true
for c in ~/Sourcecode/*/.wiki-compiler.json; do
  if [ -f "$c" ] && ! jq empty "$c" 2>/dev/null; then
    echo "warn: $c does not parse (likely preserved-malformed from a prior install; user must fix)" >&2
  fi
done
shopt -u nullglob 2>/dev/null || true

# Version bumped
grep -q '^version: 1.9.2$' .claude/skills/agentic-apps-workflow/SKILL.md || exit 1

# Smoke test — at least one source-glob in agenticapps config resolves (sanity check for sources schema)
if [ -f ~/Sourcecode/agenticapps/.wiki-compiler.json ]; then
  FIRST_GLOB=$(jq -r '.sources[0].path // empty' ~/Sourcecode/agenticapps/.wiki-compiler.json)
  test -n "$FIRST_GLOB" || { echo "ERROR: agenticapps config has no sources"; exit 1; }
fi

echo "Migration 0006 verified."
```

## Rollback

```bash
bash templates/.claude/scripts/rollback-wiki-compiler.sh
```

Removes the host symlink and reverts the version bump. Preserves all family-level data (`.knowledge/`, configs, CLAUDE.md sections). For a clean uninstall:

```bash
rm -rf ~/Sourcecode/*/.knowledge/
rm     ~/Sourcecode/*/.wiki-compiler.json 2>/dev/null
# Manually strip the `## Knowledge wiki` section from each family's CLAUDE.md.
```

## Notes

- The plugin is vendored at `~/Sourcecode/agenticapps/wiki-builder/` (sibling repo to claude-workflow). Refresh by re-pulling the upstream: `cd ~/Sourcecode/agenticapps/wiki-builder && git pull` (the vendored `.git` is preserved). Supply-chain trust assumption is recorded in ADR 0019.
- Compile output (`<family>/.knowledge/wiki/`) is gitignored via the `.gitignore` written by Step 3. The wiki is regenerable via `/wiki-compile`.
- The plugin ships its own session hooks under `wiki-builder/plugin/hooks/`. Once the symlink is in place, those hooks fire in every Claude session on the host. This is documented as a known trade-off in ADR 0019.
- A user wanting *no* host-level install can skip migration 0006 (it's listed in `optional_for` for machines without `~/Sourcecode/`). The other migrations don't depend on it.
- **Wrong-target symlink** — if a user already has `~/.claude/plugins/llm-wiki-compiler` pointing somewhere else (e.g. a personal fork), the migration ABORTS rather than silently repointing. To switch, run rollback first: `rm -f ~/.claude/plugins/llm-wiki-compiler`, then re-apply. This policy (codex B2 from `09-REVIEWS.md`) protects manual installs.
