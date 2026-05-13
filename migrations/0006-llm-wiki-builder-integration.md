---
id: 0006
slug: llm-wiki-builder-integration
title: Integrate LLM wiki compiler (Karpathy pattern) per family
from_version: 1.9.1
to_version: 1.9.2
applies_to:
  - .claude/plugins/llm-wiki-compiler (symlink into ~/.claude/plugins/)
  - <family>/.wiki-compiler.json (per family, in projects organized by family)
  - <family>/.knowledge/{raw,wiki}/
requires:
  - plugin: ussumant/llm-wiki-compiler v2.1.0+ (vendored at agenticapps/wiki-builder/)
    install: "test -d ~/Sourcecode/agenticapps/wiki-builder/plugin || git clone --depth=1 https://github.com/ussumant/llm-wiki-compiler.git ~/Sourcecode/agenticapps/wiki-builder"
    verify: "test -f ~/Sourcecode/agenticapps/wiki-builder/plugin/.claude-plugin/plugin.json"
optional_for:
  - projects not organized into family directories (use plugin directly with project-local .wiki-compiler.json)
---

# Migration 0006 — LLM wiki compiler integration

Brings projects from workflow v1.9.1 to v1.9.2 by installing the LLM wiki compiler plugin and configuring per-family wikis. Implements Andrej Karpathy's LLM Knowledge Base pattern. See ADR 0019 (to be written alongside this migration) for design rationale.

## Summary

The vendored `ussumant/llm-wiki-compiler` v2.1.0 plugin compiles each family's source documents (ADRs, READMEs, GSD planning artifacts, schemas, design docs) into a topic-based Obsidian-compatible wiki at `<family>/.knowledge/wiki/`. Configuration per family lives at `<family>/.wiki-compiler.json`. The plugin provides 12 slash commands including incremental compile, lint, query, search, and a canvas-based knowledge-graph visualization.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.9.1" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.9.1"; exit 1; }

test -d ~/Sourcecode/agenticapps/wiki-builder/plugin \
  || { echo "ERROR: wiki-builder plugin not vendored. Clone from https://github.com/ussumant/llm-wiki-compiler.git into ~/Sourcecode/agenticapps/wiki-builder"; exit 1; }
```

## Apply

### Step 1 — symlink the plugin into ~/.claude/plugins/

```bash
mkdir -p ~/.claude/plugins
ln -sfn ~/Sourcecode/agenticapps/wiki-builder/plugin ~/.claude/plugins/llm-wiki-compiler
```

### Step 2 — create per-family configs (if not already present)

For each family directory (agenticapps, factiv, neuroflash, plus any added later), create `.wiki-compiler.json` pointing at relevant source directories. See `agenticapps/.wiki-compiler.json` for a reference layout.

Minimum schema:

```json
{
  "version": 2,
  "name": "<family> Knowledge",
  "mode": "knowledge",
  "sources": [{"path": "<repo>/<dir>", "description": "<why>"}],
  "output": ".knowledge/wiki/"
}
```

### Step 3 — initialize wiki output directory and seed

```bash
for fam in agenticapps factiv neuroflash; do
  mkdir -p ~/Sourcecode/$fam/.knowledge/{raw,wiki}
done
```

(Already created by migration 0005 if you applied that first — this step is a no-op in that case.)

### Step 4 — first-time compile (per family)

In Claude Code, `cd ~/Sourcecode/<family>` and run `/wiki-compile`. The first compile scans sources, classifies topics, and writes article files to `.knowledge/wiki/topics/`. Subsequent runs are incremental.

### Step 5 — bump skill version

```bash
sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.2/' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Verify

```bash
# Plugin installed
test -f ~/.claude/plugins/llm-wiki-compiler/.claude-plugin/plugin.json || exit 1

# At least one family has a config
ls ~/Sourcecode/*/.wiki-compiler.json | wc -l | xargs test 1 -le

# Version bumped
grep -q '^version: 1.9.2$' .claude/skills/agentic-apps-workflow/SKILL.md || exit 1

echo "Migration 0006 applied successfully."
```

## Rollback

```bash
rm -f ~/.claude/plugins/llm-wiki-compiler
# Family configs are left in place (cheap to keep, easy to recreate)
sed -i.bak 's/^version: 1\.9\.2$/version: 1.9.1/' .claude/skills/agentic-apps-workflow/SKILL.md
```

Rollback does NOT remove `.knowledge/wiki/` content — those are user-generated artifacts. Delete them manually if desired.

## Notes

- The plugin is vendored at `agenticapps/wiki-builder/` (sibling repo to claude-workflow). Refresh by re-pulling the upstream: `cd ~/Sourcecode/agenticapps/wiki-builder && git pull` (the vendored `.git` is preserved).
- Per-family `.knowledge/sources.yaml.legacy` files (created by migration 0005) document the original design intent. They are not read by the compiler — the compiler reads `.wiki-compiler.json`. The `.legacy` files are kept as human-readable design references.
- Compile output is gitignored via the `.gitignore` in each family's `.knowledge/` directory (migration 0005). The wiki is regenerable.
- Each family's CLAUDE.md (updated by migration 0005/0006) now documents the slash commands available after install.
