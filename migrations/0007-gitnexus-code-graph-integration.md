---
id: 0007
slug: gitnexus-code-graph-integration
title: GitNexus code-knowledge graph integration (MCP-native, setup-only)
from_version: 1.9.2
to_version: 1.9.3
applies_to:
  - ~/.claude.json (MCP server entry for gitnexus)
  - templates/.claude/scripts/install-gitnexus.sh (apply script)
  - templates/.claude/scripts/rollback-gitnexus.sh (rollback script)
  - templates/.claude/scripts/index-family-repos.sh (user-initiated helper)
requires:
  - tool: node (>= 18)
    install: "command -v node >/dev/null 2>&1 || { echo 'Install Node ≥ 18'; exit 1; }"
    verify: "node -p 'parseInt(process.versions.node) >= 18 ? 0 : 1' | grep -q 0"
  - tool: gitnexus (npm package, PolyForm Noncommercial 1.0)
    install: "command -v gitnexus >/dev/null 2>&1 || { echo 'npm install -g gitnexus'; exit 1; }"
    verify: "command -v gitnexus >/dev/null"
  - tool: jq
    install: "command -v jq >/dev/null 2>&1 || { echo 'brew install jq (or apt install jq)'; exit 1; }"
    verify: "command -v jq >/dev/null"
optional_for:
  - non-developer machines (CI, build agents) — they typically don't have gitnexus and the migration is fail-fast there
license_note: |
  GitNexus is PolyForm Noncommercial 1.0. Permitted: personal use, internal
  tooling, developing commercial products that don't embed the runtime. NOT
  permitted: redistributing GitNexus as part of a commercial product or
  hosting it as a service for third parties. See ADR 0020 for the full
  analysis. Running `npm install -g gitnexus` constitutes acceptance.
---

# Migration 0007 — GitNexus code-knowledge graph integration

Brings projects from workflow v1.9.2 to v1.9.3 by registering GitNexus as a Claude Code MCP server and shipping a user-initiated helper script for per-repo indexing. **Setup-only** — the migration does NOT invoke `gitnexus analyze` on any repo. ADR 0020 records the design.

## Summary

Migration 0006 (the LLM wiki) added per-family **doc/decision** knowledge. This migration adds **code-structure** knowledge via GitNexus — an MCP server that pre-computes a multi-repo code graph and exposes 16 tools (impact analysis, symbol view, call-chain trace) for cross-repo questions.

This migration's scope is intentionally narrow:

1. **MCP wiring** — registers `~/.claude.json`'s `mcpServers.gitnexus` entry. Command is `gitnexus mcp` (the verified global binary; not `npx`).
2. **Helper script** — ships `templates/.claude/scripts/index-family-repos.sh` for the user to invoke per-repo `gitnexus analyze` on-demand.
3. **Version bump** — `SKILL.md` 1.9.2 → 1.9.3.

What this migration does NOT do:
- Install gitnexus (verify-only pre-flight — user runs `npm install -g gitnexus`).
- Run `gitnexus analyze` on any repo (helper script's job, user-initiated).
- Touch per-repo `.claude/skills/gitnexus-*/`, `.claude/hooks/gitnexus-hook.js`, or `CLAUDE.md` blocks (those are written by `gitnexus analyze`, not by us).

## Pre-flight

The install script verifies:
- `jq` available.
- `SKILL.md` version is `1.9.2` (or `1.9.3` for re-apply).
- `node` available + major version ≥ 18.
- `gitnexus` available as a global binary.
- Version-pin check (`GITNEXUS_VERSION` env, default `2.4.0`): warn-but-proceed on mismatch.
- `~/.claude.json` (if it exists) parses as valid JSON. If absent, the script bootstraps it.

## Apply

```bash
bash templates/.claude/scripts/install-gitnexus.sh
```

Or for consumer projects pulling from the published scaffolder:

```bash
bash ~/.claude/skills/agenticapps-workflow/templates/install-gitnexus.sh
```

**Idempotency check** (entire apply is a no-op when):
- `~/.claude.json` already has `.mcpServers.gitnexus.command == "gitnexus"` AND `.args[0] == "mcp"`.
- `SKILL.md` already at 1.9.3.

The script returns exit 4 if a pre-existing `mcpServers.gitnexus` entry has unexpected shape — applied successfully but the user should validate their MCP config manually.

## Verify

```bash
# MCP entry registered with canonical shape
jq -e '.mcpServers.gitnexus.command == "gitnexus"' ~/.claude.json
jq -e '.mcpServers.gitnexus.args == ["mcp"]' ~/.claude.json

# Version bumped
grep -q '^version: 1.9.3$' .claude/skills/agentic-apps-workflow/SKILL.md

# Helper script available
test -x ~/.claude/scripts/index-family-repos.sh || \
  test -x ./templates/.claude/scripts/index-family-repos.sh

# Smoke: MCP command can start (stub-verifiable; in production gitnexus mcp is a long-running server)
gitnexus --version
```

## Per-repo indexing (user-initiated, after migration)

```bash
bash ~/.claude/scripts/index-family-repos.sh --family factiv      # one family
bash ~/.claude/scripts/index-family-repos.sh --default-set        # curated subset (~10-20 min)
bash ~/.claude/scripts/index-family-repos.sh --all                # everything (~30-90 min)
bash ~/.claude/scripts/index-family-repos.sh --help               # usage + warnings
```

Each `gitnexus analyze <repo>` call:
- Builds the repo's code graph (Tree-sitter + LLM semantic extraction).
- Registers the repo in `~/.gitnexus/registry.json`.
- Installs 7 GitNexus skills + 1 PreToolUse/PostToolUse hook + a `<!-- gitnexus:start -->...<!-- gitnexus:end -->` block in `<repo>/CLAUDE.md` (or `AGENTS.md`).
- ~1-3 minutes per 50k-LOC repo.

The helper's default-no-args invocation prints usage + explicit warnings about LLM calls (repository content sent to the configured LLM provider) and PolyForm Noncommercial license.

## Rollback

```bash
bash templates/.claude/scripts/rollback-gitnexus.sh
```

Removes the MCP entry and reverts the version bump. **Preserves**: `~/.gitnexus/` registry, the global `gitnexus` npm install, per-repo skills/hooks/CLAUDE.md blocks. For a clean uninstall:

```bash
npm uninstall -g gitnexus
rm -rf ~/.gitnexus/
for repo in $(jq -r '.repos[]?.path // empty' ~/.gitnexus/registry.json 2>/dev/null); do
  rm -rf "$repo/.claude/skills/gitnexus-"* "$repo/.claude/hooks/gitnexus-hook.js"
  sed -i.bak '/<!-- gitnexus:start -->/,/<!-- gitnexus:end -->/d' "$repo/CLAUDE.md" 2>/dev/null
  rm -f "$repo/CLAUDE.md.bak"
done
```

## Notes

- **License (PolyForm Noncommercial)** — by running `npm install -g gitnexus`, the user accepts the license terms. This migration's pre-flight verifies the install exists; the migration itself doesn't trigger the install (so doesn't trigger implicit license acceptance). The helper script repeats the license warning in its usage block. Commercial product distribution embedding GitNexus is NOT covered — see ADR 0020 and akonlabs.com if relevant.
- **Information disclosure** — `gitnexus analyze` sends repository content to the LLM provider configured in gitnexus's settings. Users should verify that's acceptable for their codebase before invoking the helper.
- **Multi-repo registry** — one `gitnexus mcp` server reads `~/.gitnexus/registry.json` and serves all indexed repos. Cross-repo queries work without per-repo MCP servers.
- **Reindex** — manual via `gitnexus analyze <repo>` from repo root, or full-family via the helper. GitNexus's own PostToolUse hook (installed per-repo by `gitnexus analyze`) detects stale indexes after commits.
- **Wrong-shape MCP entry** — if `~/.claude.json` already has a `gitnexus` MCP entry that doesn't match `{"command":"gitnexus","args":["mcp"]}`, the migration preserves it but exits 4 to flag the discrepancy. User should validate manually.
