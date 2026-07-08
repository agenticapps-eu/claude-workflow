# Design — GitNexus background reindex hook (migration 0026, v2.3.0 → 2.4.0)

**Date:** 2026-07-08
**Status:** Approved (brainstorming) — pending implementation plan
**Migration:** 0026-gitnexus-background-reindex

## Problem

GitNexus keeps its knowledge graph fresh via a **staleness nudge**: after a git
mutation, gitnexus's own global hook (`~/.claude/hooks/gitnexus/gitnexus-hook.cjs`,
registered in the user's global `~/.claude/settings.json`) compares `HEAD`
against the last-indexed commit and, if they differ, prints
"GitNexus index is stale — run `npx gitnexus analyze`". It never reindexes
itself. This is unreliable: the agent must notice and act on the nudge, and it
often defers or ignores it, so the index drifts. (It also literally suggests
`npx gitnexus analyze`, which pulls registry-latest — a storage-format the local
readers can't open; see the 2026-07-08 FTS root-cause session.)

We want **reindex, not nudge**: the index should self-heal on a commit without
the agent doing anything.

## Ownership constraint (why this shape)

Investigation established two distinct hook layers:

- **Global** `~/.claude/settings.json` → gitnexus's **nudge** hook. Installed by
  `gitnexus setup`; claude-workflow does not ship, register, or manage it.
  `install-gitnexus.sh` only writes the MCP entry in `$HOME/.claude.json` — it
  never touches `settings.json` or any hook.
- **Per-project** `.claude/settings.json` → claude-workflow's **enforcement**
  hooks (PreToolUse/PostToolUse/Stop/SessionStart), shipped in
  `setup/snapshot/claude-settings.json` and installed per-repo.

Therefore claude-workflow cannot (and should not) edit gitnexus's global nudge.
It **can** own a new **per-project PostToolUse reindex hook**. The two coexist:
after a commit our hook fires a background reindex → `lastCommit` catches up to
`HEAD` → gitnexus's nudge sees them equal on the next call and **self-silences**.

Rejected alternatives:
- **Upstream to gitnexus** — correct long-term home, but an external dependency
  (and the currently-buggy component); slow, outside our repos.
- **Global installer hook** via `install-gitnexus.sh` — one install per machine,
  but expands the installer past its MCP-only boundary and is not a per-repo
  rollout (which is what the operator asked for).

Known tradeoff: the *first* commit after a stale interval may still show
gitnexus's nudge once, before the background reindex finishes; it goes quiet
after. Killing even that first nudge would require modifying gitnexus's global
hook (out of scope).

## Architecture

A new claude-workflow-owned, per-project PostToolUse hook that runs a detached,
incremental `gitnexus analyze` on a git HEAD change. Nothing global is modified.

### Components

1. **Engine** — `setup/snapshot/hooks/gitnexus-reindex.cjs` (+ mirror in
   `templates/.claude/hooks/gitnexus-reindex.cjs`), executable `.cjs`
   (`#!/usr/bin/env node` shebang + chmod +x, matching how existing hooks are
   invoked directly). Ported from the validated
   `~/.gitnexus-hooks/reindex-on-change.cjs`. Behaviour:
   - Resolve repo root: prefer `$CLAUDE_PROJECT_DIR`, else
     `git rev-parse --show-toplevel`.
   - No `.gitnexus/` dir → **no-op** (safe to ship to non-indexed repos).
   - Compare `git rev-parse HEAD` to `.gitnexus/meta.json` → `lastCommit`;
     equal → no-op.
   - Concurrency guard: `.gitnexus/.reindex.lock` via `O_EXCL`; a lock older
     than 10 min is stale and reclaimed.
   - Spawn **detached** `sh -c 'gitnexus analyze >/dev/null 2>&1; rm -f <lock>'`
     with `GITNEXUS_INVOCATION=gitnexus` (pin the writer to the local build so
     it never writes a storage version the readers can't open), `stdio:ignore`,
     `unref()`. Returns in milliseconds.
   - **Fail-open**: any error → `exit 0`. Kill switch:
     `GITNEXUS_AUTOREINDEX_DISABLED=1`.

2. **Wiring** — `setup/snapshot/claude-settings.json` gains one PostToolUse
   entry:
   ```json
   {
     "_hook": "Hook — GitNexus background reindex (migration 0026)",
     "matcher": "Bash",
     "hooks": [
       { "type": "command",
         "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
         "timeout": 5000 }
     ]
   }
   ```
   `matcher: "Bash"` only — HEAD changes only via git, which runs through Bash;
   avoids firing on every Edit/Read.

3. **Migration** — `migrations/0026-gitnexus-background-reindex.md`, idempotent:
   - Copy `gitnexus-reindex.cjs` into `.claude/hooks/` (chmod +x) — skip if
     byte-identical.
   - Insert the PostToolUse entry into `.claude/settings.json` only if no entry
     with that `_hook`/command exists (preserve user edits verbatim).
   - Bump installed skill version 2.3.0 → 2.4.0.
   - Supported floor 2.3.0 → 2.4.0; lower versions replay through 0025 first.

### Data flow

```
Bash commit → HEAD moves
  → PostToolUse(Bash) fires gitnexus-reindex.cjs
    → HEAD != lastCommit → take lock → spawn detached `gitnexus analyze` → return (ms)
      → [background] analyze finishes → meta.lastCommit = HEAD → lock removed
  → next Bash call: gitnexus global nudge sees HEAD == lastCommit → silent
```

## Error handling

- Fail-open everywhere; a freshness hook must never break the host.
- No `.gitnexus/` → no-op (non-indexed repos unaffected).
- Lock prevents two `analyze` runs racing on one SQLite DB (the corruption /
  storage-skew failure mode).
- Detached + `unref` → never blocks the tool loop; 5s hook timeout never hit.

## Testing

`migrations/test-fixtures/0026/`:
- `01-fresh-insert` — hook file copied + PostToolUse entry added.
- `02-idempotent-reapply` — re-running makes no further change.
- `03-preserve-existing-posttooluse` — existing PostToolUse entries untouched.
- `04-engine-present-executable` — shipped `.cjs` exists and is chmod +x.
- (engine unit behaviour) — HEAD-equal → no spawn; no `.gitnexus/` → no-op;
  kill-switch honored.

Wire into `run-tests.sh` (+ dispatcher entry) and add a `check-snapshot-parity.sh`
section asserting the hook entry + engine are in the seed. `build-snapshot.sh
--check` must stay green.

## Docs

- **ADR-0039** — per-project reindex hook coexisting with gitnexus's global
  nudge; alternatives rejected (upstream, global installer).
- CHANGELOG `[2.4.0]`, MANIFEST rows, standards checklist line.

## Rollout (after merge)

1. Fast-forward the local scaffolder clone `~/.claude/skills/agenticapps-workflow`.
2. `/update-agenticapps-workflow` per repo → applies migration 0026 (per-project
   hook). Repos without gitnexus no-op harmlessly.

## Out of scope

- Modifying gitnexus's global nudge hook (not owned by claude-workflow).
- Fixing the upstream gitnexus FTS storage-version bug (handled separately by
  pinning to 1.6.4).
- Bringing codex/opencode reindex hooks under claude-workflow management (those
  live in host-specific config; the shared engine already covers them locally).
