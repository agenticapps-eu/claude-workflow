# ADR-0039: GitNexus background reindex — a per-project hook that coexists with the global nudge

**Status**: Accepted  **Date**: 2026-07-08  **Linear**: —
**Spec**: `docs/superpowers/specs/2026-07-08-gitnexus-background-reindex-design.md`
**Migration**: `0026-gitnexus-background-reindex` (v2.3.0 → 2.4.0)

## Context

GitNexus keeps its knowledge graph fresh via a **staleness nudge**: after a git
mutation, gitnexus's own global hook (registered in the user's global
`~/.claude/settings.json` by `gitnexus setup`) compares `HEAD` against the
last-indexed commit and, if they differ, prints "index is stale — run
`npx gitnexus analyze`". It never reindexes itself, so freshness depends on the
agent noticing and acting on the nudge — which it often defers or ignores, and
the suggested `npx gitnexus analyze` pulls a registry-latest build whose storage
format the local readers can't open (see the 2026-07-08 FTS root-cause session).

Investigation established two distinct hook layers. **Global**
`~/.claude/settings.json` → gitnexus's nudge; installed by `gitnexus setup`,
not shipped or managed by claude-workflow (`install-gitnexus.sh` only writes the
MCP entry in `$HOME/.claude.json`). **Per-project** `.claude/settings.json` →
claude-workflow's enforcement hooks, shipped in `setup/snapshot/claude-settings.json`.
claude-workflow therefore cannot and should not edit gitnexus's global nudge.

## Decision

1. **Reindex, not nudge, via a per-project hook we own.** Ship a new
   PostToolUse `matcher:"Bash"` hook (`.claude/hooks/gitnexus-reindex.cjs`) that,
   on a git HEAD change, spawns a **detached** incremental `gitnexus analyze` and
   returns in milliseconds. The two layers coexist: our hook advances
   `meta.lastCommit` to `HEAD`, so gitnexus's global nudge sees them equal on its
   next call and self-silences.
2. **Fail-open, lock-guarded, writer-pinned.** Any error exits 0 (a freshness
   hook must never break the host). A `.gitnexus/.reindex.lock` (`O_EXCL`, 10-min
   stale TTL) prevents two `analyze` runs racing on one SQLite DB. The child is
   spawned with `GITNEXUS_INVOCATION=gitnexus` so the write path uses the local
   build and never writes a storage version the readers can't open. Kill switch:
   `GITNEXUS_AUTOREINDEX_DISABLED=1`.
3. **Snapshot + migration propagation.** The engine's source of truth is
   `templates/.claude/hooks/gitnexus-reindex.cjs`; `bin/build-snapshot.sh` copies
   it into `setup/snapshot/hooks/` and the drift guard (`check-snapshot-parity.sh`
   §2 + §8) enforces it stays. Migration 0026 installs it into existing repos
   idempotently, copying the engine verbatim from the scaffolder snapshot so a
   migrated install is byte-identical to a fresh one.
4. **No `.gitnexus/` → no-op.** The hook is safe to ship to every repo; repos
   without a gitnexus index no-op at runtime.

## Consequences

- A repo's index self-heals on commit without agent involvement; the global
  nudge goes quiet after the first background reindex completes.
- **Known tradeoff:** the *first* commit after a stale interval may still show
  gitnexus's nudge once, before the background reindex finishes. Killing even
  that first nudge would require modifying gitnexus's global hook (out of scope).
- One more per-project hook to maintain; covered by fixtures under
  `migrations/test-fixtures/0026/` and parity §8.

## Alternatives rejected

- **Upstream to gitnexus.** The correct long-term home, but an external
  dependency (and the currently-buggy component); slow, outside our repos.
- **Global installer hook** via `install-gitnexus.sh`. One install per machine,
  but expands the installer past its MCP-only boundary and is not the per-repo
  rollout the operator asked for.

## Downstream hosts

codex-workflow / opencode-workflow already run the shared engine as host-local
config (`~/.gitnexus-hooks/` + the opencode plugin). Productizing it into their
own snapshots is deferred to those repos; this ADR governs the Claude host.
