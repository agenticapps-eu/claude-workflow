# Phase 10 — RESEARCH

**Migration:** 0007-gitnexus-code-graph-integration
**Inputs:** CONTEXT.md, ADR 0020, drafted migration body (carry-over PR #12, scope-reduced).

Each section answers one CONTEXT.md open question with ≥2 alternatives.

---

## Section 1 — Verify-only vs install-during-apply (CONTEXT Q1)

**Question:** Does the migration's apply step install gitnexus, or only verify it's installed?

### Alternative 1A — Verify-only, fail-with-install-command if absent (chosen)

```bash
if ! command -v gitnexus >/dev/null 2>&1; then
  echo "ERROR: gitnexus not installed. Run: npm install -g gitnexus" >&2
  exit 1
fi
```

**Pros:**
- Migration is bounded and deterministic. No network operation in the apply step.
- User explicitly consents to the install (and its PolyForm Noncommercial license terms) by running `npm install -g gitnexus` themselves.
- Sandbox-friendly: harness can mock gitnexus as a bash stub.
- No "migration silently took 90 seconds to download a package" surprise.

**Cons:**
- Two-step user UX: install gitnexus first, then run the migration. Documented in the error message.

### Alternative 1B — Install-during-apply (`npm install -g gitnexus`) (rejected)

**Why rejected:**
- Network-dependent migrations are fragile in CI/sandbox contexts.
- Implicit license acceptance — user runs `/update-agenticapps-workflow` and ends up with PolyForm Noncommercial software installed without explicit confirmation.
- Migration framework's idempotency-check + retry pattern doesn't compose cleanly with long network fetches.
- Adds a real "what if npm registry is down" failure mode to the migration runtime.

### Alternative 1C — Bundle gitnexus binary in the workflow repo (rejected)

**Why rejected:**
- License + size: PolyForm Noncommercial says we can't redistribute, and bundling 10MB+ of node_modules into a scaffolder repo is hostile.

**Decision:** **1A** (verify-only).

---

## Section 2 — MCP wire path (CONTEXT Q2)

**Question:** How does the migration register gitnexus as a Claude Code MCP server?

### Alternative 2A — Try `claude mcp add` CLI, fall back to jq edit (chosen)

```bash
if command -v claude >/dev/null 2>&1; then
  # CLI path (preferred — future-proof to schema changes)
  claude mcp add gitnexus -- npx -y "gitnexus@${GITNEXUS_VERSION:-latest}" mcp 2>/dev/null || true
fi
# Verify via direct jq read regardless of which path landed it
jq -e '.mcpServers.gitnexus // .mcp_servers.gitnexus // empty' ~/.claude.json >/dev/null 2>&1 || \
  # Fallback: direct jq edit
  jq '.mcpServers.gitnexus = {"command":"npx","args":["-y","gitnexus@latest","mcp"]}' \
    ~/.claude.json > ~/.claude.json.tmp && mv ~/.claude.json.tmp ~/.claude.json
```

**Pros:**
- Uses the supported public CLI when available.
- Falls back gracefully on hosts where `claude` CLI isn't on PATH (CI, agent sandboxes, custom installs).
- Verification via jq lets us detect whether the entry exists regardless of which write path landed it.

**Cons:**
- The fallback jq edit assumes a specific schema (`.mcpServers.gitnexus`). If Claude Code changes that, the fallback path breaks. Documented as a known risk.

### Alternative 2B — Always jq-edit, never use CLI (rejected)

**Why rejected:** schema fragility. The CLI absorbs schema changes; direct edits don't. Best to prefer the CLI when available.

### Alternative 2C — Always use CLI, fail if absent (rejected)

**Why rejected:** `claude mcp add` is a Claude Code-specific CLI surface. Codex/Cursor/Windsurf consumers running this same migration have no `claude` command. We'd block them needlessly.

**Decision:** **2A** (CLI-first, jq fallback).

---

## Section 3 — Helper script default behavior (CONTEXT Q3)

**Question:** What does `index-family-repos.sh` do when run without flags?

### Alternative 3A — Print usage; require explicit flag (chosen)

```bash
usage() {
  cat <<EOF
Usage: index-family-repos.sh [--family <name> | --all | --default-set | --help]

  --family <name>   Index repos under ~/Sourcecode/<name>/ (e.g. factiv)
  --all             Index agenticapps + factiv + neuroflash families
  --default-set     Index the curated 'active development' subset
  --help            This message

WARNING: Indexing makes LLM calls (PolyForm Noncommercial license — see ADR 0020).
         A 50k-LOC repo takes 1-3 minutes; --all is 30-90 minutes total.
EOF
}
[ $# -eq 0 ] && { usage; exit 0; }
```

**Pros:**
- No accidental mass-indexing. User must consciously choose scope.
- License + runtime cost surface in the usage message itself.

**Cons:**
- Slightly more friction for the common case. Acceptable.

### Alternative 3B — Default to `--default-set` (curated subset) (rejected)

**Why rejected:** "Default-set" is opinionated. The right curated set depends on what the user is actively working on this week. Better to force them to pick.

### Alternative 3C — Default to `--all` (rejected)

**Why rejected:** Mass-indexing on a no-args invocation is the surprise case CONTEXT explicitly wants to avoid.

**Decision:** **3A** (print usage, require flag).

---

## Section 4 — Rollback scope (CONTEXT Q4 / RESEARCH §3 from Phase 09)

**Question:** What does rollback remove vs preserve?

### Alternative 4A — Remove MCP entry + revert version; preserve everything else (chosen)

```bash
# Remove MCP entry (via claude mcp CLI, with jq fallback)
claude mcp remove gitnexus 2>/dev/null || \
  jq 'del(.mcpServers.gitnexus)' ~/.claude.json > ~/.claude.json.tmp && \
  mv ~/.claude.json.tmp ~/.claude.json

# Revert SKILL.md version
# (explicit if/then/else per Phase 09 CSO H1 lesson)

# DO NOT: npm uninstall, rm -rf ~/.gitnexus, touch per-repo state
```

**Pros:**
- Matches Phase 09's preserve-data semantics.
- User's `~/.gitnexus/` indexed graphs survive (re-applying picks back up).
- Doesn't `npm uninstall` a tool the user may use directly.
- Symmetric with Phase 09 rollback.

**Cons:**
- A user wanting clean uninstall needs to manually `npm uninstall -g gitnexus && rm -rf ~/.gitnexus`. Documented.

### Alternative 4B — Aggressive: npm uninstall + clear ~/.gitnexus (rejected)

**Why rejected:** Same as Phase 09 — destructive rollback creates fear-of-rollback. Many users may have used gitnexus before the migration; uninstalling it on rollback is hostile.

**Decision:** **4A** (preserve-data rollback).

---

## Section 5 — MCP version pin

**Question:** Does the migration pin gitnexus to a specific version in the MCP command, or use `@latest`?

### Alternative 5A — Pin to a recorded version, with env override (chosen)

```bash
GITNEXUS_VERSION="${GITNEXUS_VERSION:-2.4.0}"
# ... use "gitnexus@${GITNEXUS_VERSION}" in the MCP command
```

**Pros:**
- Reproducible: same migration ran today vs in 6 months produces same MCP config.
- Supply-chain hardening: a compromised upstream version published next month doesn't auto-propagate to running sessions.
- Env override lets users opt into newer versions.

**Cons:**
- We need to record a specific version. Bumping the migration when gitnexus releases is a small ongoing cost.
- The version we pin must actually be published. If we ship the migration with `2.4.0` and that version isn't on npm, the MCP server fails on first invocation.

### Alternative 5B — Use `@latest`, document as known risk (rejected)

**Why rejected:** Supply-chain attack vector. A future malicious gitnexus version would auto-load on every session. Pinning is the security-conscious default.

**Decision:** **5A** (pin to recorded version with env override). For initial ship: TBD on the exact version (whatever's current at PR open time, default `latest` as fallback only if no published version found during pre-flight).

---

## Section 6 — Pre-flight network check?

**Question:** Should pre-flight verify network reachability for `npm install -g`?

### Alternative 6A — No network check; let `npm install` fail loud (chosen)

User runs `npm install -g gitnexus` outside the migration. If they have no network, npm will tell them clearly. The migration doesn't need to add a layered "is npm reachable" check.

**Decision:** **6A** (no network check; this is a verify-only migration).

---

## Summary

| # | Decision | Outcome |
|---|---|---|
| 1 | Install policy | Verify-only; fail with clear install command |
| 2 | MCP wire | CLI-first with jq-edit fallback |
| 3 | Helper script default | Print usage, require flag |
| 4 | Rollback scope | Preserve data; remove only MCP entry + version |
| 5 | MCP version pin | Pinned with env override |
| 6 | Network pre-flight | None — npm surfaces errors well enough |
