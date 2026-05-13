# ADR 0020 — GitNexus code-knowledge graph integration

**Status:** Accepted
**Date:** 2026-05-12
**Related:** Migration 0007 (this), Migration 0006 (LLM wiki for docs/decisions), ADR 0019 (wiki integration rationale)

## Context

Migration 0006 installed an LLM wiki for compiling *doc and decision knowledge* per family (ADRs, READMEs, planning artifacts, design docs). It does not address *code-structure knowledge* — "what calls what across these 33 neuroflash services," "what breaks if I change this function's signature," "what's the call chain from the API gateway to the brand-voice-service."

Agents currently re-derive code structure every session by running grep, find, and file-reads. For polyrepo systems like neuroflash (32 repos), the cost compounds: a single cross-repo impact question can take dozens of tool calls and tens of thousands of tokens before the agent has enough context to answer reliably.

## Decision

Adopt GitNexus (abhigyanpatwari/GitNexus, npm: `gitnexus`) as the code-knowledge layer, installed globally and indexed per repo. The plugin provides:

- **Multi-repo registry** — a single MCP server reads `~/.gitnexus/registry.json` and serves every indexed repo. Cross-repo queries are first-class. This is the killer feature for our 50-repo polyrepo layout.
- **16 MCP tools** — impact analysis, 360-degree symbol view, call-chain trace, process-grouped search, multi-file rename, change-detection.
- **7 agent skills** — exploring, debugging, impact-analysis, refactoring, pr-review, cli, guide — installed per-repo.
- **PreToolUse + PostToolUse hooks** — enrich `Grep`/`Read` with graph context, detect stale index after commits.
- **Auto-generated `gitnexus:start/end` block** in each repo's CLAUDE.md/AGENTS.md — gives the agent canonical MCP tool documentation without manual edits.

## Why GitNexus over Graphify

In an earlier research pass I recommended Graphify as the primary code-graph solution. After deeper investigation:

| Criterion | GitNexus | Graphify |
|---|---|---|
| Multi-repo support | Native via `~/.gitnexus/registry.json` | Per-project; no cross-repo |
| MCP support | First-class | Skill-format only |
| Hooks for staleness | Built-in (PostToolUse on commits) | Not advertised |
| Hosts supported | Claude Code, Codex, Cursor, Windsurf, OpenCode | Claude Code, Codex, OpenCode, Cursor, Gemini CLI, Aider, Hermes, Pi, Antigravity |
| Token reduction (benchmark) | Not separately benchmarked; same architectural pattern | ~70× on 50k-LOC (documented) |
| License | PolyForm Noncommercial 1.0 | MIT |

For *our* situation — 50 repos across 3 client families with cross-repo impact analysis as the main pain point — GitNexus's multi-repo registry wins. Graphify's broader host support and permissive license are real advantages, but the multi-repo gap is unworkable for polyrepo at our scale.

Graphify remains a viable fallback if/when we add `pi` as a third host and GitNexus's pi support proves weaker than Claude/Codex. Migration 0007b can add Graphify as a per-host overlay if needed.

## Why index per family, not all 50 at once

`gitnexus analyze` on a single 50k-LOC repo takes 1–3 minutes. For all 49 repos that's 50–150 minutes of one-time indexing. The helper script lets you scope:

- `--family <name>` — index just one family (e.g. start with factiv, 3 repos, ~10 min)
- `--all` — index all of agenticapps/factiv/neuroflash (~80–100 min)
- Default — index a curated "active development" subset (claude-workflow + cparx + fx-signal-agent + neuroapi + neuroflash_api + mcp-server + frontend-nextjs)

Personal/, shared/, archive/ are not indexed by default. Reindex any repo at any time with `gitnexus analyze` from its root.

## License consequences (PolyForm Noncommercial)

This is the friction point. PolyForm Noncommercial 1.0 permits:

- Personal use
- Internal use within an organization for the organization's own purposes
- Development of commercial products *using* the tool

It does NOT permit:

- Distributing or sublicensing the GitNexus runtime as part of a commercial product
- Commercial hosting of GitNexus for third parties

For factiv (commercial product) and neuroflash (commercial product), using GitNexus to *help develop* the products is the permitted "internal use" case. Embedding GitNexus into a shipped product, or running GitNexus as part of a hosted service offered to customers, would require an enterprise license from [akonlabs.com](https://akonlabs.com).

The current use case (agents reading the graph during development) is comfortably inside the OSS license. If at any point we want to embed graph-aware code intelligence in factiv's or neuroflash's customer-facing product, that's the moment to talk to akonlabs.

## Relationship to migrations 0005, 0006, 0008

- **Migration 0005** added the multi-AI plan review enforcement (workflow contract).
- **Migration 0006** added the per-family LLM wiki (doc/decision knowledge).
- **Migration 0007** (this) adds the per-repo + cross-repo code graph (code-structure knowledge).
- **Migration 0008** (queued) will surface coverage of both 0006 and 0007 in the agenticapps-dashboard so we can see per-repo which artifacts exist and how fresh they are.

The three knowledge layers are complementary, not competing. The wiki tells the agent *why*; GitNexus tells it *what calls what*; the review gate ensures plans are stress-tested before any of it gets edited.

## Consequences

**Positive:**

- Cross-repo impact analysis becomes a single MCP tool call instead of a multi-hour grep chase.
- The agent stops re-walking codebases every session.
- Stale-index detection means we cannot drift silently the way the multi-AI review did.
- Same registry serves Claude Code AND Codex AND any other MCP-capable agent.

**Negative:**

- ~80–100 minutes of one-time indexing for all active families. Mitigated by scoping (start with factiv, expand).
- Disk: `~/.gitnexus/` holds the indexed graphs. For 49 repos this is typically <500MB; not a concern.
- Another tool to keep current. Mitigated by GitNexus's own PostToolUse staleness detection.
- License attention required if we ever ship GitNexus-derived intelligence in a customer product.

## Open follow-ups

- Migration 0007b — Graphify as pi-host fallback (only if pi's MCP support proves insufficient).
- Migration 0008 — dashboard coverage matrix (this+wiki+CLAUDE.md per repo).
- Periodic reindex schedule — currently relies on the PostToolUse hook + manual `gitnexus analyze` after large refactors. Consider a launchd/cron job for weekly full-family reindex if drift becomes a problem.
