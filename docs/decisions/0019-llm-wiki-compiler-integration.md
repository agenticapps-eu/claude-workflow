# ADR 0019 — LLM wiki compiler integration

**Status:** Accepted
**Date:** 2026-05-12 (rev 2026-05-13)
**Supersedes:** —
**Superseded by:** —
**Related:** Migration 0006 (wiki-builder integration, self-contained)

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

## Why .wiki-compiler.json

The plugin's native config format. Directory paths + classification at compile time via the LLM rather than by manifest pre-declaration. Migration 0006 writes a default config per family if absent; user customisation is preserved on re-apply.

Why not a glob-typed manifest (the alternative considered): glob-typed manifests would be over-engineering for a compiler that does its own classification well. The LLM-driven classification surfaces concepts and cross-cutting topics the manifest typing would have hidden.

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

## Self-containment (rev 2026-05-13)

Migration 0006 is self-contained: it owns the host symlink, the per-family directory scaffolding, the default `.wiki-compiler.json`, AND the family-level `CLAUDE.md` section update. Earlier drafts of this ADR assumed a separate prior migration (an old draft of 0005) handled the directory scaffolding. The shipped migration 0005 is multi-AI plan review enforcement, unrelated — so 0006 folds the scaffolding step in. Rollback is preserve-data: removes only the host symlink and version bump.

## Threat model

Recorded in migration 0006's PLAN.md `Threat model (STRIDE)` table. Summary:

- **Symlink overwrites a real file** at `~/.claude/plugins/llm-wiki-compiler` → mitigated by ABORT-on-exists-as-regular-file in the install script (codex B2 lock).
- **Wrong-target symlink overwrite** → ABORT (do not silently repoint a forked install).
- **Cross-family `.wiki-compiler.json` leak** via misconfigured `sources[*].path` → low risk: migration writes only the default config; user customization is user-territory. T5b post-apply smoke test catches malformed globs.
- **Family CLAUDE.md collision** via duplicate `## Knowledge wiki` heading → idempotency check.
- **Plugin supply-chain compromise** via upstream `ussumant/llm-wiki-compiler` → vendored-clone trust assumption; future hardening: pin to a release tag + SHA-256 (deferred follow-up).
- **Vendored plugin contains session hooks** that run in every Claude session after symlink → known trade-off; users who don't want host-level hooks skip migration 0006 entirely (it's in `optional_for`).
- **Rollback leaves orphan files** → by design (preserve-data); clean-uninstall commands documented.

## Open follow-ups

- GitNexus integration (migration 0007) — code-structure graph complementing the doc wiki.
- Dashboard coverage matrix (migration 0008) — show per-repo wiki freshness and GitNexus index status.
- Pin vendored plugin to a release tag + SHA-256 (same approach as Phase 08 CSO M2 deferred item).
