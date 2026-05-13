---
id: 0007
slug: gitnexus-code-graph-integration
title: GitNexus code-knowledge graph integration (MCP-native)
from_version: 1.6.0
to_version: 1.7.0
applies_to:
  - ~/.gitnexus/registry.json (global, multi-repo)
  - ~/.claude.json (MCP server entry for gitnexus)
  - <each indexed repo>/.claude/skills/gitnexus-*/ (7 skills per repo)
  - <each indexed repo>/.claude/hooks/gitnexus-hook.js
  - <each indexed repo>/CLAUDE.md or AGENTS.md (gitnexus:start/end block)
requires:
  - tool: gitnexus (npm package)
    install: "npm install -g gitnexus"
    verify: "command -v gitnexus >/dev/null"
  - node: ">= 18"
  - platform: macOS or Linux (Windows has a different invocation)
optional_for:
  - repos that are not actively edited (archived, frozen, personal one-off websites)
license_note: |
  GitNexus OSS is PolyForm Noncommercial 1.0. Individual-developer use and
  internal tooling within a company are typically covered. For commercial
  product distribution that *embeds* the GitNexus runtime, an enterprise
  license from akonlabs.com is required. Using GitNexus to help develop a
  commercial product (factiv/neuroflash) is not the same as embedding it.
  Consult the license text + akonlabs if in doubt. See ADR 0020.
---

# Migration 0007 — GitNexus code-knowledge graph integration

Brings projects from workflow v1.6.0 to v1.7.0 by installing GitNexus globally, wiring it as an MCP server in Claude Code, and indexing the active family repos. Provides cross-repo code-structure awareness (impact analysis, call chains, dependency graph, symbol resolution) as a complement to the doc/decision wiki from migration 0006. See ADR 0020 for rationale.

## Summary

After migration 0006 (LLM wiki for compounding decision/doc knowledge), agents still re-derive *code structure* every session via grep / find / file-reads. GitNexus pre-computes the structural graph once, exposes 16 MCP tools (impact analysis, 360-degree symbol view, call-chain trace, etc.), and serves multiple indexed repos from a single MCP server backed by `~/.gitnexus/registry.json`. Independent measurements report ~70× token reduction on large codebases. Multi-repo polyrepo support is native — exactly the shape this Sourcecode reorganization is designed for.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.6.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.6.0"; exit 1; }

command -v node >/dev/null || { echo "ERROR: node not found. Install Node >= 18."; exit 1; }
command -v npm  >/dev/null || { echo "ERROR: npm not found."; exit 1; }
node -e 'process.exit(parseInt(process.versions.node) >= 18 ? 0 : 1)' || { echo "ERROR: node version too old, need >= 18."; exit 1; }
```

## Apply

### Step 1 — install gitnexus globally

```bash
npm install -g gitnexus
gitnexus --version
```

### Step 2 — run gitnexus setup (writes MCP config for Claude Code + Codex + Cursor)

```bash
gitnexus setup
```

This auto-detects installed editors and writes an MCP server entry to each. For Claude Code specifically the equivalent direct command is:

```bash
claude mcp add gitnexus -- npx -y gitnexus@latest mcp
```

### Step 3 — index the active family repos

Run the helper script generated alongside this migration:

```bash
bash ~/Sourcecode/gitnexus-index-all.sh
```

The script iterates through `agenticapps/`, `factiv/`, and `neuroflash/` (skipping `personal/`, `shared/`, `archive/`) and runs `gitnexus analyze` per repo. Each analyze call:

- Builds the repo's knowledge graph (Tree-sitter static analysis + LLM semantic extraction for richer relationships)
- Registers the repo in `~/.gitnexus/registry.json`
- Installs the 7 GitNexus skills (`gitnexus-cli`, `-debugging`, `-exploring`, `-guide`, `-impact-analysis`, `-pr-review`, `-refactoring`) into `<repo>/.claude/skills/`
- Installs `<repo>/.claude/hooks/gitnexus-hook.js` (PreToolUse + PostToolUse)
- Injects a `<!-- gitnexus:start --> … <!-- gitnexus:end -->` block into `<repo>/CLAUDE.md` (or `AGENTS.md`) with MCP tool documentation

For a 50k-LOC repo this typically takes 1–3 minutes. The script logs results per repo; on failure it continues with the next repo and reports a summary at the end.

### Step 4 — bump skill version

```bash
sed -i.bak 's/^version: 1\.6\.0$/version: 1.7.0/' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Verify

```bash
# gitnexus installed
command -v gitnexus

# MCP server registered with Claude Code
grep -q gitnexus ~/.claude.json || claude mcp list | grep -q gitnexus

# Registry has at least one indexed repo
test -f ~/.gitnexus/registry.json
jq '.repos | length' ~/.gitnexus/registry.json

# Pick one indexed repo and confirm per-repo install
test -d ~/Sourcecode/factiv/cparx/.claude/skills/gitnexus-exploring
test -f ~/Sourcecode/factiv/cparx/.claude/hooks/gitnexus-hook.js
grep -q "gitnexus:start" ~/Sourcecode/factiv/cparx/CLAUDE.md

# Version bumped
grep -q '^version: 1.7.0$' .claude/skills/agentic-apps-workflow/SKILL.md

echo "Migration 0007 applied successfully."
```

## Rollback

```bash
# Per-repo cleanup (be selective — only do the repos you want to detach)
for repo in <list-of-repos>; do
  rm -rf "$repo/.claude/skills/gitnexus-"*
  rm -f  "$repo/.claude/hooks/gitnexus-hook.js"
  # Remove the gitnexus:start/end block from CLAUDE.md or AGENTS.md (use sed or manual edit)
  sed -i.bak '/<!-- gitnexus:start -->/,/<!-- gitnexus:end -->/d' "$repo/CLAUDE.md" 2>/dev/null || true
done

# Remove MCP server entry
claude mcp remove gitnexus 2>/dev/null || true

# Optionally uninstall globally
# npm uninstall -g gitnexus

# Optionally clear registry
# rm -rf ~/.gitnexus

# Revert version
sed -i.bak 's/^version: 1\.7\.0$/version: 1.6.0/' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Notes

- **Multi-repo registry.** A single `gitnexus mcp` server reads `~/.gitnexus/registry.json` and serves *all* indexed repos. There is no per-repo MCP server — agents in any repo can ask cross-repo questions.
- **Reindex after structural commits.** GitNexus's PostToolUse hook detects when a commit changed code structure and prompts the agent to reindex. Manual reindex: `cd <repo> && gitnexus analyze`.
- **Coexistence with the wiki (0006).** GitNexus answers "what calls what." The wiki answers "why did we decide this." Use both. Migration 0008 (dashboard) will surface coverage of both per-repo.
- **License.** See `license_note` in the frontmatter and ADR 0020. PolyForm Noncommercial. Individual / internal-tooling use is generally fine; commercial *embedding* requires an enterprise license.
