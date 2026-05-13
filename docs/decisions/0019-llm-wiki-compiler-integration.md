# ADR 0019 — LLM wiki compiler integration

**Status:** Accepted
**Date:** 2026-05-12
**Supersedes:** —
**Superseded by:** —
**Related:** Migration 0005 (knowledge substrate scaffold), Migration 0006 (wiki-builder integration)

## Context

After the Sourcecode reorganization on 2026-05-11, repositories are organized into client families (`agenticapps/`, `factiv/`, `neuroflash/`, `personal/`, `shared/`). Each family contains many repos, each with its own CLAUDE.md, AGENTS.md, README.md, ADRs, GSD planning artifacts, and schema histories. Across 51 git repos there are 18 CLAUDE.md files, 9 AGENTS.md files, ~50 README.md files, ~8 ADRs in claude-workflow alone, and dozens of `.planning/phases/` directories.

When Claude Code agents enter a repo within a family, they currently re-derive context every session by reading raw source files. This is expensive (tokens), slow (latency), and doesn't compound (every session re-reads what previous sessions already understood).

## Decision

Adopt Andrej Karpathy's LLM Knowledge Base pattern, implemented via the vendored `ussumant/llm-wiki-compiler` plugin (v2.1.0+). Per-family compilation: each family directory has a `.wiki-compiler.json` pointing at the relevant source directories; running `/wiki-compile` from the family root produces a compiled wiki at `<family>/.knowledge/wiki/` that subsequent agent sessions read instead of re-walking raw files.

## Why this plugin

Evaluated alternatives:

- **Build our own compiler from scratch** — high cost, low marginal value. The OSS plugin is mature (v2.1.0, marketplace-ready, Codex-compatible, supports both knowledge and codebase modes).
- **`nvk/llm-wiki`** — multi-agent research orchestration. More heavyweight than needed for our compile-existing-docs use case.
- **`rvk7895/llm-knowledge-bases`** — has explicit lint phase. The `ussumant` plugin also ships lint as a first-class command, with broader checks (stale, orphans, cross-refs, low coverage, contradictions, schema drift).
- **`AgriciDaniel/claude-obsidian`** — Obsidian-tight. The `ussumant` plugin emits Obsidian-compatible output while staying portable; family wikis can be opened in any markdown editor.
- **Pinecone Nexus** — SaaS / BYOC only; doesn't fit our local-first multi-host model.
- **GraphRAG / LightRAG / HippoRAG** — fancier retrieval, but their value is at runtime. The wiki pattern moves work upstream to compile time, which is the more valuable shift for our workflow (see prior conversation thread; ADR-context summary).

## Why per family, not per repo

Each repo's CLAUDE.md is already authoritative for that repo's specifics. The wiki adds value when it can *connect across repos within a family* — "what calls what across these 30 neuroflash services," "how does cparx's role-based registration relate to its phase-by-phase decision history," etc. A per-repo wiki would just duplicate what CLAUDE.md already says. A per-family wiki compiles cross-repo patterns that no single CLAUDE.md can express.

Family-level placement also aligns with the access boundary enforced by the family-level CLAUDE.md (root `~/Sourcecode/CLAUDE.md`: "stay inside the family unless cross-family work is explicitly requested"). Agents reading the wiki are reading material from the same boundary they're already constrained to.

## Why vendor instead of npm-install / clone-on-the-fly

- **Reproducibility** — versioned source-of-truth lives in our tree, immune to upstream removal.
- **Auditability** — we can read every command/skill/hook the plugin ships.
- **Local modification** — if a family needs a tweaked config schema or an additional command, we patch the vendored copy and document the divergence in this ADR.
- **Multi-host portability** — the same vendored copy serves Claude Code AND Codex (the plugin ships both `.claude-plugin/` and `.codex-plugin/` manifests).

The upstream `.git/` is preserved in the vendored copy so we can `git pull` to refresh without recloning.

## Why .wiki-compiler.json instead of sources.yaml

Migration 0005 originally created `<family>/.knowledge/sources.yaml` with glob patterns + per-source type/template metadata. Migration 0006 supersedes those with the plugin's native `.wiki-compiler.json` format (directory paths, classification at compile time via the LLM rather than by manifest pre-declaration). The `sources.yaml` files are renamed `sources.yaml.legacy` and kept as a design-intent reference; the compiler reads only `.wiki-compiler.json`.

This trade is worth it: glob-typed manifests were over-engineering for a compiler that does its own classification well. The LLM-driven classification surfaces concepts and cross-cutting topics the manifest typing would have hidden.

## Consequences

**Positive:**
- Agents stop re-deriving family knowledge every session.
- Cross-repo patterns become first-class: "how do all neuroflash services handle authentication" becomes a wiki page instead of a multi-grep operation.
- Lint phase catches knowledge drift programmatically.
- Knowledge-graph visualization is now available for any family.
- Same toolchain serves Claude Code AND Codex sessions (plugin supports both).

**Negative:**
- One more thing to keep current: `/wiki-compile` must be run after meaningful source changes. Mitigated by lint (detects stale).
- Compile time scales with family size. Neuroflash with 32 repos will be the slowest first-compile.
- The compiled wiki is a derived artifact, not authoritative — bugs in the compile prompt could mis-classify topics. Lint + provenance-citation in each wiki page mitigate this.

## Relationship to migration 0005

Migration 0005 created the `.knowledge/{raw,wiki}/` directory structure and the `.gitignore` and stub `INDEX.md`. Migration 0006 layers the actual compiler on top of that scaffolding. Either can be rolled back independently — rolling back 0006 leaves the empty scaffolding in place, rolling back 0005 removes the directories (but the compiler can recreate them on next compile).

## Open follow-ups

- GitNexus integration (migration 0007) — code-structure graph complementing the doc wiki.
- Dashboard coverage matrix (migration 0008) — show per-repo wiki freshness and GitNexus index status.
