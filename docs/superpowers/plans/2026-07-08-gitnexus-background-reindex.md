# GitNexus Background Reindex Hook — Implementation Plan (migration 0026, v2.3.0 → 2.4.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a claude-workflow-owned, per-project PostToolUse hook that runs a detached, incremental `gitnexus analyze` after a git commit, so a repo's GitNexus index self-heals instead of nudging the agent.

**Architecture:** A new executable Node engine (`gitnexus-reindex.cjs`) lives in `templates/.claude/hooks/` (source of truth), is copied into `setup/snapshot/hooks/` by `bin/build-snapshot.sh`, and is bound by one `matcher: "Bash"` PostToolUse entry in `templates/claude-settings.json`. Migration 0026 installs both into existing repos idempotently; fresh installs get them from the snapshot. Nothing global is modified — the hook coexists with gitnexus's global nudge, which self-silences once `lastCommit` catches up to `HEAD`.

**Tech Stack:** Node.js (`.cjs`, no deps — `child_process`/`fs`/`path`), `jq` (settings edits), POSIX `sh` (fixtures + build), the existing migration test harness (`migrations/run-tests.sh`) and drift guard (`migrations/check-snapshot-parity.sh`).

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-07-08-gitnexus-background-reindex-design.md`. Every task's requirements implicitly include these.

- **Supported upgrade floor:** `2.3.0 → 2.4.0`. Minor, additive (no breaking change). Projects below 2.3.0 replay the chain through 0025 first.
- **Source of truth is `templates/` + `skill/SKILL.md`.** `setup/snapshot/` is a generated artifact: after any template/skill edit run `bash bin/build-snapshot.sh` and commit the result; `migrations/check-snapshot-parity.sh` + `bin/build-snapshot.sh --check` enforce parity in CI. Never hand-edit `setup/snapshot/` files as the primary edit.
- **Per-project only.** The hook lives in `.claude/hooks/` and is bound in the project's `.claude/settings.json`. Nothing in `~/.claude/` or gitnexus's global nudge is touched.
- **Matcher is `"Bash"` only** — HEAD changes only via git, which runs through Bash; avoids firing on every Edit/Read.
- **`_hook` label (exact):** `Hook — GitNexus background reindex (migration 0026)`.
- **Engine invariants:** `#!/usr/bin/env node` shebang; `chmod +x`; **fail-open** (any error → `process.exit(0)`); kill switch `GITNEXUS_AUTOREINDEX_DISABLED=1`; detached child spawned with `GITNEXUS_INVOCATION=gitnexus` (pins the writer to the local build so `analyze` never writes a storage version the readers can't open); lockfile `.gitnexus/.reindex.lock` created `O_EXCL` (`flag: 'wx'`); a lock older than `LOCK_TTL_MS = 10 * 60 * 1000` is stale and reclaimed.
- **No `.gitnexus/` → no-op** (safe to ship to non-indexed repos; they no-op harmlessly).
- **Command bound (exact):** `$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs`, `"timeout": 5000`.
- **Migration copy source of truth (for existing installs):** the scaffolder clone's snapshot — `$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs` — so a migrated install is byte-identical to a fresh snapshot install. In fixtures, `$REPO_ROOT` stands in for `$SCAFFOLDER`.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `templates/.claude/hooks/gitnexus-reindex.cjs` | Create | The reindex engine (source of truth). Ported from `~/.gitnexus-hooks/reindex-on-change.cjs`, adding `$CLAUDE_PROJECT_DIR`-preferred root resolution. |
| `bin/build-snapshot.sh` | Modify (line ~32) | Copy `templates/.claude/hooks/*.cjs` into the snapshot and `chmod +x` them (currently only `*.sh` are copied). |
| `templates/claude-settings.json` | Modify | Add one `PostToolUse` `matcher:"Bash"` entry binding the engine. |
| `setup/snapshot/hooks/gitnexus-reindex.cjs` | Generated | Fresh-install copy of the engine (produced by build-snapshot). |
| `setup/snapshot/claude-settings.json` | Generated | Fresh-install settings with the new entry (produced by build-snapshot). |
| `migrations/check-snapshot-parity.sh` | Modify | Add `gitnexus-reindex.cjs` to `REQUIRED_HOOK_BINDINGS` (§2) and a new §8 asserting the engine is present + executable + Bash-bound. |
| `migrations/0026-gitnexus-background-reindex.md` | Create | The idempotent upgrade path for existing installs (copy engine → wire settings → bump version). |
| `migrations/test-fixtures/0026/common-setup.sh` | Create | Shared sandbox builder (git repo + project skeleton). |
| `migrations/test-fixtures/0026/01-fresh-insert/` | Create | Replay: engine copied + PostToolUse entry added. |
| `migrations/test-fixtures/0026/02-idempotent-reapply/` | Create | Replay twice → no further change. |
| `migrations/test-fixtures/0026/03-preserve-existing-posttooluse/` | Create | Existing PostToolUse entries survive the insert. |
| `migrations/test-fixtures/0026/04-engine-present-executable/` | Create | Shipped snapshot `.cjs` exists and is `chmod +x`. |
| `migrations/test-fixtures/0026/05-engine-behaviour/` | Create | Drives the `.cjs` directly: kill-switch / no-`.gitnexus` / HEAD-equal → no reindex; HEAD-diff → detached `gitnexus` invoked. |
| `migrations/run-tests.sh` | Modify | Add `test_migration_0026()` + dispatcher entry. |
| `skill/SKILL.md` | Modify | Version bump `2.3.0 → 2.4.0` (frontmatter only — reindex is a hook, not a skill section). |
| `docs/decisions/0039-gitnexus-background-reindex.md` | Create | ADR: per-project reindex hook coexisting with gitnexus's global nudge; rejected alternatives. |
| `CHANGELOG.md` | Modify | `[2.4.0]` entry. |
| `setup/snapshot/MANIFEST.md` | Modify | Note that snapshot `hooks/*` now includes the `.cjs` engine. |

**Task order (each commit is parity-/drift-green):**
1. Engine + its behaviour test (snapshot machinery still ignores `.cjs`, so parity/build-check stay green).
2. Wire settings + teach build-snapshot to copy `.cjs` + regenerate snapshot + parity §8. (Snapshot VERSION still 2.3.0; latest migration still 0025 → drift/§5 green.)
3. Migration 0026 doc + replay fixtures 01–04 + skill version bump 2.4.0 + snapshot rebuild. (Migration `to_version` 2.4.0 and skill 2.4.0 land together → drift/§5 green.)
4. Docs: ADR-0039 + CHANGELOG + MANIFEST.

---

## Task 1: Reindex engine + behaviour test

**Files:**
- Create: `templates/.claude/hooks/gitnexus-reindex.cjs`
- Create: `migrations/test-fixtures/0026/common-setup.sh`
- Create: `migrations/test-fixtures/0026/05-engine-behaviour/setup.sh`
- Create: `migrations/test-fixtures/0026/05-engine-behaviour/verify.sh`
- Create: `migrations/test-fixtures/0026/05-engine-behaviour/expected-exit`
- Modify: `migrations/run-tests.sh` (add `test_migration_0026()` + dispatcher entry)

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - Engine at `templates/.claude/hooks/gitnexus-reindex.cjs`, executable, resolving repo root as `$CLAUDE_PROJECT_DIR` (if an existing directory) else `git rev-parse --show-toplevel` of `cwd`; reading `.gitnexus/meta.json` → `lastCommit`; writing lock `.gitnexus/.reindex.lock`; spawning `sh -c 'gitnexus analyze >/dev/null 2>&1; rm -f "<lock>"'` detached with `GITNEXUS_INVOCATION=gitnexus`; always `process.exit(0)`.
  - `common-setup.sh` contract: sourced with `FIXTURES_ROOT` + `REPO_ROOT` set and `HOME` pointed at a sandbox; honors `SKILL_VERSION` (default `2.3.0`); leaves cwd as a fresh git repo (one commit) with `.claude/skills/agentic-apps-workflow/SKILL.md`, `.claude/settings.json`, and an empty `.claude/hooks/`.
  - `test_migration_0026()` in `run-tests.sh`: loops every `migrations/test-fixtures/0026/[0-9]*-*/` dir, runs `setup.sh` then `verify.sh` under `HOME=<sandbox>`, `REPO_ROOT`, `FIXTURES_ROOT`, and asserts `verify` exit == `expected-exit`.

- [ ] **Step 1: Write the engine `common-setup.sh` (shared sandbox builder)**

Create `migrations/test-fixtures/0026/common-setup.sh`:

```sh
#!/bin/sh
# Sourced by each 0026 fixture's setup.sh. Builds a sandboxed BEFORE state:
# a fresh git repo (one commit — gives HEAD a value) with a project-local
# hyphenated SKILL.md at a controllable version (default 2.3.0 — Step 3's bump
# floor), a baseline .claude/settings.json (existing PostToolUse entries, no
# gitnexus-reindex binding), and an empty .claude/hooks/ (Step 1's copy target).
#
#   SKILL_VERSION=2.4.0 . "$FIXTURES_ROOT/common-setup.sh"   # already-applied state
set -eu

: "${SKILL_VERSION:=2.3.0}"

# A real git repo so the engine and `git rev-parse HEAD` have a HEAD to read.
git init -q
git config user.email fixture@example.com
git config user.name  fixture
git commit --allow-empty -qm "fixture: initial commit"

mkdir -p .claude/skills/agentic-apps-workflow .claude/hooks
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<EOF_PROJ_SKILL
---
name: agentic-apps-workflow
version: ${SKILL_VERSION}
implements_spec: 0.4.0
description: synthetic test fixture for migration 0026
---

## Daily Quick Reference

1. stub
EOF_PROJ_SKILL

# Baseline settings: one pre-existing PostToolUse entry, NO gitnexus-reindex.
cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "PostToolUse": [
      {
        "_hook": "Hook 4a — Skill Router Audit Log",
        "matcher": "mcp__skills__.*|Bash",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/skill-router-log.sh", "timeout": 5000 }
        ]
      }
    ]
  }
}
EOF_SETTINGS
```

- [ ] **Step 2: Write the behaviour fixture `05-engine-behaviour/setup.sh`**

Create `migrations/test-fixtures/0026/05-engine-behaviour/setup.sh`:

```sh
#!/bin/sh
# Fixture 05 — BEFORE: a plain indexed-or-not git repo. verify.sh drives the
# engine directly through each decision branch; setup only needs the repo.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
```

- [ ] **Step 3: Write the behaviour fixture `05-engine-behaviour/verify.sh`**

Create `migrations/test-fixtures/0026/05-engine-behaviour/verify.sh`. This drives the shipped engine at `$REPO_ROOT/templates/.claude/hooks/gitnexus-reindex.cjs` through its synchronous branches. It PATH-injects a `gitnexus` stub that appends to a sentinel, so the detached reindex is observable without a real gitnexus install. `CLAUDE_PROJECT_DIR` is unset so the engine resolves the sandbox via `git rev-parse` (a live Claude session exports `CLAUDE_PROJECT_DIR`, which would otherwise point the engine at the real repo).

```sh
#!/bin/sh
# Verify the engine's synchronous decision branches:
#   kill-switch        → no reindex
#   no .gitnexus/      → no reindex (non-indexed repos unaffected)
#   HEAD == lastCommit → no reindex (already fresh)
#   HEAD != lastCommit → detached `gitnexus` invoked (self-heal)
# Determinism: a PATH `gitnexus` stub appends to $SENTINEL; the negative
# branches return BEFORE spawning, so the sentinel must stay absent.
set -eu
command -v node >/dev/null || { echo "SKIP-DEP: node required"; exit 1; }

ENGINE="$REPO_ROOT/templates/.claude/hooks/gitnexus-reindex.cjs"
test -f "$ENGINE" || { echo "RED: engine missing at $ENGINE"; exit 1; }
test -x "$ENGINE" || { echo "RED: engine not executable"; exit 1; }

# A live session sets CLAUDE_PROJECT_DIR to the real repo — unset it so the
# engine resolves THIS sandbox via git.
unset CLAUDE_PROJECT_DIR

SANDBOX="$(pwd)"
STUBDIR="$SANDBOX/.stub-bin"
SENTINEL="$SANDBOX/.gitnexus-invoked"
LOCK="$SANDBOX/.gitnexus/.reindex.lock"
mkdir -p "$STUBDIR"
# Stub `gitnexus`: record the invocation, exit fast. The engine's child runs
# `gitnexus analyze; rm -f "<lock>"`, so the sentinel appears iff we spawned.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$SENTINEL" > "$STUBDIR/gitnexus"
chmod +x "$STUBDIR/gitnexus"
export PATH="$STUBDIR:$PATH"

run_engine() { node "$ENGINE"; }               # engine always exits 0 (fail-open)
reset()      { rm -f "$SENTINEL" "$LOCK"; }
spawned() {   # poll up to ~3s for the detached child to hit the stub
  i=0; while [ $i -lt 30 ] && [ ! -f "$SENTINEL" ]; do sleep 0.1; i=$((i+1)); done
  [ -f "$SENTINEL" ]
}
not_spawned() { sleep 0.3; [ ! -f "$SENTINEL" ]; }

HEAD="$(git rev-parse HEAD)"

# ── Branch A: kill switch → no reindex (even with a stale index present) ──────
reset; mkdir -p "$SANDBOX/.gitnexus"; printf '{"lastCommit":"deadbeef"}' > "$SANDBOX/.gitnexus/meta.json"
GITNEXUS_AUTOREINDEX_DISABLED=1 run_engine
not_spawned || { echo "FAIL A: kill switch did not suppress reindex"; exit 1; }

# ── Branch B: no .gitnexus/ → no reindex (non-indexed repo) ───────────────────
reset; rm -rf "$SANDBOX/.gitnexus"
run_engine
not_spawned || { echo "FAIL B: reindexed a non-indexed repo"; exit 1; }

# ── Branch C: HEAD == lastCommit → already fresh, no reindex ──────────────────
reset; mkdir -p "$SANDBOX/.gitnexus"; printf '{"lastCommit":"%s"}' "$HEAD" > "$SANDBOX/.gitnexus/meta.json"
run_engine
not_spawned || { echo "FAIL C: reindexed a fresh index"; exit 1; }

# ── Branch D: HEAD != lastCommit → detached reindex fires ─────────────────────
reset; mkdir -p "$SANDBOX/.gitnexus"; printf '{"lastCommit":"deadbeef"}' > "$SANDBOX/.gitnexus/meta.json"
run_engine
spawned || { echo "FAIL D: stale index did not trigger a reindex"; exit 1; }

echo "fixture 05 — engine: kill-switch/no-index/fresh → no-op; stale → detached reindex"
```

- [ ] **Step 4: Write `05-engine-behaviour/expected-exit`**

Create `migrations/test-fixtures/0026/05-engine-behaviour/expected-exit` containing exactly:

```
0
```

- [ ] **Step 5: Add `test_migration_0026()` + dispatcher entry to `run-tests.sh`**

Insert the function immediately after `test_migration_0025()` ends (after line 1563, the closing `}`). It mirrors `test_migration_0025` but has **no hard migration-file guard** (the fixtures are self-contained replays; the guard would fail in Task 1 before the 0026 doc exists):

````markdown
Insert after the blank lines that follow `test_migration_0025()`:
````

```bash
# ─────────────────────────────────────────────────────────────────────────────
# test_migration_0026 — GitNexus background reindex hook (2.3.0 -> 2.4.0)
# WORKFLOW — verify body specific to migration 0026 content; stays in claude-workflow.
# Same fixture-replay shape as 0025: each fixture's setup.sh builds a sandboxed
# before state, verify.sh replays the migration's deterministic Step 1/2/3 shell
# (copy engine from $REPO_ROOT/setup/snapshot/hooks, wire the PostToolUse Bash
# entry, bump version) or drives the engine directly (05-engine-behaviour), and
# asserts idempotency + surgical insert; expected-exit asserts the rc.
# ─────────────────────────────────────────────────────────────────────────────
test_migration_0026() {
  echo ""
  echo "${YELLOW}━━━ Migration 0026 — GitNexus background reindex ━━━${RESET}"

  local fixtures="$REPO_ROOT/migrations/test-fixtures/0026"

  if [ ! -d "$fixtures" ]; then
    echo "  ${RED}SKIP${RESET}: fixtures directory missing"
    SKIP=$((SKIP+1))
    return
  fi

  run_0026_fixture() {
    local fixname="$1"
    local fixdir="$fixtures/$fixname"
    local tmp; tmp="$(mktemp -d -t "migration-0026-${fixname}-XXXXXX")"
    local fake_home="$tmp/home"
    mkdir -p "$fake_home"

    if [ -x "$fixdir/setup.sh" ]; then
      (
        cd "$tmp" && \
        HOME="$fake_home" REPO_ROOT="$REPO_ROOT" FIXTURES_ROOT="$fixtures" \
          "$fixdir/setup.sh" >/dev/null 2>&1
      ) || {
        echo "  ${RED}✗${RESET} $fixname — setup.sh failed"
        FAIL=$((FAIL+1))
        rm -rf "$tmp"
        return
      }
    fi

    local verify_out verify_exit
    verify_out=$(
      cd "$tmp" && \
      HOME="$fake_home" REPO_ROOT="$REPO_ROOT" \
        bash "$fixdir/verify.sh" 2>&1
    )
    verify_exit=$?

    local expected_exit
    expected_exit=$(tr -d '\n' < "$fixdir/expected-exit")
    if [ "$verify_exit" != "$expected_exit" ]; then
      echo "  ${RED}✗${RESET} $fixname — verify exit $verify_exit, expected $expected_exit"
      echo "      verify output:"
      printf '%s\n' "$verify_out" | sed 's/^/        /' | head -12
      FAIL=$((FAIL+1))
      rm -rf "$tmp"
      return
    fi

    echo "  ${GREEN}✓${RESET} $fixname"
    PASS=$((PASS+1))
    rm -rf "$tmp"
  }

  for fix in "$fixtures"/[0-9]*-*/; do
    local name
    name="$(basename "${fix%/}")"
    run_0026_fixture "$name"
  done
}
```

Then register it in the dispatcher. After the `0025` block (lines 1989–1991):

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "0025" ]; then
  test_migration_0025
fi
```

add:

```bash
if [ -z "$FILTER" ] || [ "$FILTER" = "0026" ]; then
  test_migration_0026
fi
```

- [ ] **Step 6: Run the behaviour test to verify it FAILS (RED)**

Run: `bash migrations/run-tests.sh 0026`
Expected: `✗ 05-engine-behaviour` — verify exits 1 with `RED: engine missing at .../templates/.claude/hooks/gitnexus-reindex.cjs` (the engine does not exist yet).

- [ ] **Step 7: Write the engine `templates/.claude/hooks/gitnexus-reindex.cjs`**

Create the file (exact content):

```javascript
#!/usr/bin/env node
/**
 * gitnexus reindex-on-change — background, non-blocking per-project index refresh.
 *
 * A claude-workflow-owned PostToolUse(Bash) hook. On a git HEAD change (i.e.
 * after a commit) it spawns a DETACHED incremental `gitnexus analyze` and
 * returns immediately, so the agent's tool loop never blocks and the index
 * self-heals within seconds — no "index is stale, run analyze" nudge that the
 * agent may ignore. Coexists with gitnexus's global nudge, which self-silences
 * once meta.lastCommit catches up to HEAD.
 *
 * Why this shape:
 *  - Reindex, not nudge — freshness stops depending on the agent remembering.
 *  - Incremental + detached — analyze reuses .gitnexus/parse-cache, so a
 *    HEAD-delta reindex is cheap; detaching keeps it off the critical path
 *    (the 5s hook budget is never touched).
 *  - Lockfile guard — two commits in quick succession must not launch two
 *    analyze processes racing on the same SQLite DB (the corruption /
 *    storage-skew failure mode). O_EXCL create; a lock older than LOCK_TTL_MS
 *    is treated as stale and broken.
 *  - GITNEXUS_INVOCATION=gitnexus — pin the WRITER to the same local build the
 *    readers (MCP servers, search hooks) use, so analyze never writes a storage
 *    version the readers can't open.
 *  - Fail-open — any error exits 0. A freshness hook must never break the host.
 *
 * Kill switch: export GITNEXUS_AUTOREINDEX_DISABLED=1
 */
'use strict';

const { execFileSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const LOCK_TTL_MS = 10 * 60 * 1000; // a reindex older than this is presumed dead

function git(args, cwd) {
  return execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  }).trim();
}

// Prefer the host-provided project dir; fall back to the git toplevel of cwd.
function resolveRoot() {
  const fromEnv = process.env.CLAUDE_PROJECT_DIR;
  if (fromEnv) {
    try {
      if (fs.statSync(fromEnv).isDirectory()) return fromEnv;
    } catch {
      /* not a usable dir — fall through to git */
    }
  }
  try {
    return git(['rev-parse', '--show-toplevel'], process.cwd());
  } catch {
    return null; // not a git repo
  }
}

function main() {
  if (process.env.GITNEXUS_AUTOREINDEX_DISABLED === '1') return;

  const root = resolveRoot();
  if (!root) return;

  const gnDir = path.join(root, '.gitnexus');
  if (!fs.existsSync(gnDir)) return; // this repo isn't indexed by gitnexus

  // HEAD now vs. the commit gitnexus last indexed (meta.json → lastCommit).
  let head;
  try {
    head = git(['rev-parse', 'HEAD'], root);
  } catch {
    return; // detached/empty repo — nothing meaningful to compare
  }

  let indexed = null;
  try {
    const meta = JSON.parse(fs.readFileSync(path.join(gnDir, 'meta.json'), 'utf8'));
    indexed = meta.lastCommit || null;
  } catch {
    /* unreadable meta → fall through and reindex */
  }
  if (indexed && indexed === head) return; // index is already fresh

  // Concurrency guard: one reindex per repo at a time.
  const lock = path.join(gnDir, '.reindex.lock');
  try {
    const st = fs.statSync(lock);
    if (Date.now() - st.mtimeMs < LOCK_TTL_MS) return; // a reindex is in flight
    fs.unlinkSync(lock); // stale lock — previous run died; reclaim it
  } catch {
    /* no lock present */
  }
  try {
    fs.writeFileSync(lock, String(process.pid), { flag: 'wx' }); // O_EXCL
  } catch {
    return; // lost the create race to a sibling hook
  }

  // Detached incremental reindex; the child clears its own lock on exit.
  // GITNEXUS_INVOCATION pins the write to the local build (storage parity).
  const child = spawn(
    'sh',
    ['-c', `gitnexus analyze >/dev/null 2>&1; rm -f "${lock}"`],
    {
      cwd: root,
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, GITNEXUS_INVOCATION: 'gitnexus' },
    },
  );
  child.unref();
}

try {
  main();
} catch {
  /* fail-open — a freshness hook must never break the host */
}
process.exit(0);
```

- [ ] **Step 8: Make the engine executable**

Run: `chmod +x templates/.claude/hooks/gitnexus-reindex.cjs`

- [ ] **Step 9: Run the behaviour test to verify it PASSES (GREEN)**

Run: `bash migrations/run-tests.sh 0026`
Expected: `✓ 05-engine-behaviour` and the run's summary shows 0 failures for the 0026 filter.

- [ ] **Step 10: Run the FULL migration suite to confirm no regression**

Run: `bash migrations/run-tests.sh`
Expected: PASS summary, 0 failures. (The new `.cjs` is invisible to `bin/build-snapshot.sh --check` at this point because build-snapshot still copies only `*.sh`, so parity/drift are unaffected.)

- [ ] **Step 11: Commit**

```bash
git add templates/.claude/hooks/gitnexus-reindex.cjs \
        migrations/test-fixtures/0026/common-setup.sh \
        migrations/test-fixtures/0026/05-engine-behaviour \
        migrations/run-tests.sh
git commit -m "feat(gitnexus): add per-project background reindex engine + behaviour test"
```

---

## Task 2: Wire the hook into templates + snapshot + parity guard

**Files:**
- Modify: `bin/build-snapshot.sh` (after line 32 — the `*.sh` hook copy)
- Modify: `templates/claude-settings.json` (add the PostToolUse Bash entry)
- Modify: `migrations/check-snapshot-parity.sh` (§2 `REQUIRED_HOOK_BINDINGS` + new §8)
- Generated (commit the regenerated output): `setup/snapshot/hooks/gitnexus-reindex.cjs`, `setup/snapshot/claude-settings.json`

**Interfaces:**
- Consumes: the engine from Task 1 (`templates/.claude/hooks/gitnexus-reindex.cjs`).
- Produces: a snapshot that contains the engine (`setup/snapshot/hooks/gitnexus-reindex.cjs`, executable) and a settings file binding it (`setup/snapshot/claude-settings.json` PostToolUse `matcher:"Bash"` → `gitnexus-reindex.cjs`); a parity guard that fails if either drops out.

- [ ] **Step 1: Teach `bin/build-snapshot.sh` to copy `.cjs` hooks**

In `bin/build-snapshot.sh`, find line 32:

```bash
cp "$ROOT"/templates/.claude/hooks/*.sh                "$OUT/hooks/"
```

Add immediately after it:

```bash
cp "$ROOT"/templates/.claude/hooks/*.cjs               "$OUT/hooks/" 2>/dev/null || true
chmod +x "$OUT"/hooks/*.cjs 2>/dev/null || true
```

(The `|| true` keeps the build robust if no `.cjs` hooks exist; the `chmod` guarantees the snapshot copy is executable so parity §8's `-x` check passes.)

- [ ] **Step 2: Add the PostToolUse Bash entry to `templates/claude-settings.json`**

Read `templates/claude-settings.json` and locate the `PostToolUse` array (it contains "Hook 4a — Skill Router Audit Log" and "Hook 6 — Normalize CLAUDE.md"). Append this object as the **last** element of the `PostToolUse` array (add a comma after the current last entry's closing `}`):

```json
{
  "_hook": "Hook — GitNexus background reindex (migration 0026)",
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
      "timeout": 5000
    }
  ]
}
```

- [ ] **Step 3: Verify the template is still valid JSON**

Run: `jq -e '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command' templates/claude-settings.json`
Expected: prints `"$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs"` (and does not error — proves valid JSON + entry present).

- [ ] **Step 4: Regenerate the snapshot**

Run: `bash bin/build-snapshot.sh`
Expected: prints `snapshot rebuilt at version 2.3.0` (version unchanged this task).

- [ ] **Step 5: Verify the snapshot now carries the engine + binding**

Run:
```bash
test -x setup/snapshot/hooks/gitnexus-reindex.cjs && echo "ENGINE-OK"
jq -e '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command | test("gitnexus-reindex")' setup/snapshot/claude-settings.json && echo "BOUND-OK"
```
Expected: `ENGINE-OK` then `true` then `BOUND-OK`.

- [ ] **Step 6: Confirm the snapshot is in parity with the just-regenerated build**

Run: `bash bin/build-snapshot.sh --check`
Expected: exits 0 (no diff between committed snapshot and a fresh rebuild).

- [ ] **Step 7: Add the `.cjs` binding to parity §2 and write parity §8 (RED first)**

In `migrations/check-snapshot-parity.sh`, extend `REQUIRED_HOOK_BINDINGS` (around line 50) to include the engine:

```bash
REQUIRED_HOOK_BINDINGS=(
  phase-sentinel.sh
  multi-ai-review-gate.sh
  normalize-claude-md.sh
  gitnexus-reindex.cjs
)
```

Then, immediately before the final `echo` / `if [ "$fail" -ne 0 ]` block (currently around line 176–177), add §8:

```bash
# ── 8. gitnexus background reindex (migration 0026): engine + Bash binding ────
# The snapshot MUST ship the reindex engine (executable, node shebang) and bind
# it on a PostToolUse Bash matcher. §4's referential-integrity loop is .sh-only,
# so the .cjs engine needs its own end-state invariant here.
GNH="$SNAP/hooks/gitnexus-reindex.cjs"
if [ -f "$GNH" ]; then
  ok "gitnexus reindex engine present in snapshot"
  [ -x "$GNH" ] && ok "gitnexus reindex engine is executable" \
                || bad "gitnexus reindex engine not executable"
  head -1 "$GNH" | grep -q '^#!/usr/bin/env node' \
    && ok "gitnexus reindex engine has a node shebang" \
    || bad "gitnexus reindex engine missing '#!/usr/bin/env node' shebang"
else
  bad "missing hooks/gitnexus-reindex.cjs (migration 0026 engine)"
fi
if [ "$have_jq" = 1 ]; then
  jq -e '.hooks.PostToolUse[]? | select(.matcher=="Bash")
         | .hooks[]?.command? | select(test("gitnexus-reindex"))' "$SET" >/dev/null 2>&1 \
    && ok "settings binds gitnexus-reindex.cjs on a Bash PostToolUse matcher" \
    || bad "settings.json does not bind gitnexus-reindex.cjs on a Bash PostToolUse matcher"
fi
```

- [ ] **Step 8: Run the parity guard to verify it PASSES (GREEN)**

Run: `bash migrations/check-snapshot-parity.sh`
Expected: ends with `PASS`; the output includes `✓ settings binds gitnexus-reindex.cjs`, `✓ gitnexus reindex engine present in snapshot`, `✓ gitnexus reindex engine is executable`, and `✓ settings binds gitnexus-reindex.cjs on a Bash PostToolUse matcher`.

- [ ] **Step 9: Prove §8 actually guards (temporary RED check)**

Run:
```bash
mv setup/snapshot/hooks/gitnexus-reindex.cjs /tmp/gnh.bak
bash migrations/check-snapshot-parity.sh; echo "rc=$?"
mv /tmp/gnh.bak setup/snapshot/hooks/gitnexus-reindex.cjs
```
Expected: the middle run prints `FAIL` and `rc=1` (proves §8 is not a false-green); the final `mv` restores the engine.

- [ ] **Step 10: Run the full migration suite**

Run: `bash migrations/run-tests.sh`
Expected: PASS, 0 failures (snapshot VERSION is still 2.3.0 and the latest migration is still 0025, so the drift test and parity §5 remain green).

- [ ] **Step 11: Commit**

```bash
git add bin/build-snapshot.sh templates/claude-settings.json \
        migrations/check-snapshot-parity.sh \
        setup/snapshot/hooks/gitnexus-reindex.cjs \
        setup/snapshot/claude-settings.json
git commit -m "feat(gitnexus): wire reindex hook into snapshot + parity guard"
```

---

## Task 3: Migration 0026 doc + replay fixtures + version bump

**Files:**
- Create: `migrations/0026-gitnexus-background-reindex.md`
- Create: `migrations/test-fixtures/0026/01-fresh-insert/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0026/02-idempotent-reapply/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0026/03-preserve-existing-posttooluse/{setup.sh,verify.sh,expected-exit}`
- Create: `migrations/test-fixtures/0026/04-engine-present-executable/{setup.sh,verify.sh,expected-exit}`
- Modify: `skill/SKILL.md` (version `2.3.0 → 2.4.0`)
- Generated (commit): `setup/snapshot/VERSION` (→ `2.4.0`) and any other snapshot files build-snapshot restamps

**Interfaces:**
- Consumes: engine + snapshot binding (Tasks 1–2); the snapshot copy source `$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs`.
- Produces: `migrations/0026-gitnexus-background-reindex.md` with `from_version: 2.3.0`, `to_version: 2.4.0`; deterministic Step 1 (copy engine, skip if byte-identical, chmod +x) / Step 2 (jq-guarded PostToolUse Bash insert) / Step 3 (version bump). `skill/SKILL.md` at `version: 2.4.0`.

- [ ] **Step 1: Write the migration doc `migrations/0026-gitnexus-background-reindex.md`**

Create the file (exact content):

````markdown
---
id: 0026
slug: gitnexus-background-reindex
title: GitNexus background reindex hook — reindex, not nudge (v2.3.0 -> 2.4.0)
from_version: 2.3.0
to_version: 2.4.0
applies_to:
  - .claude/hooks/gitnexus-reindex.cjs                 # copy the engine from the scaffolder snapshot
  - .claude/settings.json                              # add one PostToolUse matcher:"Bash" entry
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.3.0 -> 2.4.0
---

# Migration 0026 — GitNexus background reindex (v2.3.0 -> 2.4.0)

Ships a **claude-workflow-owned, per-project** PostToolUse hook that runs a
detached, incremental `gitnexus analyze` after a git commit, so the repo's
GitNexus index self-heals instead of relying on the agent to act on gitnexus's
global staleness *nudge*. The two coexist: after a commit our hook fires a
background reindex → `meta.lastCommit` catches up to `HEAD` → gitnexus's global
nudge sees them equal on its next call and self-silences. Nothing global is
modified. See ADR-0039.

Two things reach existing installs:

1. `.claude/hooks/gitnexus-reindex.cjs` — the engine (copied verbatim from the
   scaffolder's snapshot, so a migrated install is byte-identical to a fresh
   snapshot install), chmod +x.
2. `.claude/settings.json` gains one `PostToolUse` `matcher:"Bash"` entry
   binding the engine.

Fresh installs get both from the snapshot (`setup/snapshot/hooks/gitnexus-reindex.cjs`
+ the `PostToolUse` entry in `setup/snapshot/claude-settings.json`, laid down by
`setup/SKILL.md` Step 4c); the drift guard (`migrations/check-snapshot-parity.sh`
§2 + §8) fails if the engine or its binding ever drops out of the seed.

**Supported upgrade floor:** `2.3.0 -> 2.4.0`. Projects below 2.3.0 replay the
chain through 0025 first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (2.3.0), or 2.4.0 for re-apply.
grep -qE '^version: 2\.(3|4)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.3.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.3.0 -> 2.4.0."
  exit 3
}

# 2. jq is required (Step 2 edits JSON structurally, never with sed).
command -v jq >/dev/null || { echo "ABORT: jq required for migration 0026."; exit 3; }

# 3. The scaffolder's snapshot carries the engine Step 1 copies (guards against
#    running 0026 from a stale scaffolder clone).
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
test -f "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0026."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}

# 4. .claude/settings.json exists and is valid JSON (baselined by 0000).
test -f .claude/settings.json || { echo "ABORT: .claude/settings.json missing — was 0000-baseline applied?"; exit 3; }
jq empty .claude/settings.json 2>/dev/null || { echo "ABORT: .claude/settings.json is not valid JSON."; exit 3; }
```

## Steps

### Step 1 — Copy the reindex engine into `.claude/hooks/`

The engine is **copied from the scaffolder's snapshot** (single source of
truth) rather than duplicated here, so a migrated install is byte-identical to
a fresh snapshot install and the code cannot drift.

**Idempotency check (positive — engine already installed and identical):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
cmp -s "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" \
       .claude/hooks/gitnexus-reindex.cjs 2>/dev/null
```

**Apply (only when absent or differing; preserves a user-customized hook —
`cmp` above already returned non-zero, so we overwrite only a stale/missing copy):**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
mkdir -p .claude/hooks
cp "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
```

**Rollback:** `rm -f .claude/hooks/gitnexus-reindex.cjs`

### Step 2 — Wire the PostToolUse Bash entry into `.claude/settings.json`

Insert only if **no** entry already binds `gitnexus-reindex`; an existing
binding (including a user-edited one) is preserved verbatim. The insert is
append-only and structural (`jq`), so all other hooks survive.

**Idempotency check (positive — already wired):**
```bash
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))' \
  .claude/settings.json >/dev/null 2>&1
```

**Apply (guarded merge, append-only-if-absent):**
```bash
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

The `any(...)` guard makes re-running a no-op — it can never duplicate the entry.

**Rollback:**
```bash
jq '.hooks.PostToolUse |= map(select(.hooks[]?.command? | strings | test("gitnexus-reindex") | not))' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

### Step 3 — Bump installed workflow version to 2.4.0

The version line lives at the CANONICAL project-local hyphenated path
`.claude/skills/agentic-apps-workflow/SKILL.md` (per 0011 `applies_to` +
`install.sh` skill-name). NOT the non-hyphenated dev-scaffolder clone path.

**Idempotency check (positive):**
```bash
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition (at supported 2.3.0 floor):**
```bash
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**
```bash
sed -i.0026.bak -E 's/^version: 2\.3\.0$/version: 2.4.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
```

**Rollback:**
```bash
sed -i.0026.bak -E 's/^version: 2\.4\.0$/version: 2.3.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.4.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. Engine installed + executable
test -x .claude/hooks/gitnexus-reindex.cjs

# 3. Exactly one gitnexus-reindex PostToolUse entry, matcher is Bash
COUNT=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$COUNT" = "1" ]
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .matcher == "Bash"' .claude/settings.json >/dev/null
```

All four post-checks are hard guarantees.

**This migration never runs `gitnexus analyze`.** It only installs the hook; the
first reindex happens at the next commit, and only in a repo that already has a
`.gitnexus/` directory (the engine no-ops everywhere else — CI, containers,
non-indexed repos).

## Skip cases

- **`from_version` mismatch** (project not at 2.3.0) → migration framework skips
  silently per the standard rule. Projects below 2.3.0 replay 0025 first.
- **Engine already installed and identical** → Step 1 is a no-op (`cmp` match).
- **Entry already wired** (any shape, including a user-edited command) → Step 2
  is a no-op; user configuration is never overwritten.
- **Repo without gitnexus** → the hook installs but no-ops at runtime (no
  `.gitnexus/` directory), so the migration is harmless everywhere.

## Compatibility

- **Additive (minor) bump** to `2.4.0`: no breaking change. Step 1 adds a file;
  Step 2 appends one hook entry (structural `jq`, whole-file rewrite preserves
  all other hooks); nothing existing is modified or removed.
- **Kill switch stays local:** `export GITNEXUS_AUTOREINDEX_DISABLED=1` disables
  the reindex per shell without re-running any migration; removing the settings
  entry (Step 2 rollback) disables it per repo.
- **Drift coupling:** as the highest-numbered migration file, 0026's
  `to_version` (2.4.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  is bumped to 2.4.0 in lockstep, and `check-snapshot-parity.sh` §5 requires the
  snapshot VERSION to equal it.

## Downstream hosts

`codex-workflow` and `opencode-workflow` already carry the shared reindex engine
as host-local config (`~/.gitnexus-hooks/` + the opencode plugin). Productizing
it into their own snapshots (their idiom for per-project hooks) is tracked in
ADR-0039; this migration is the Claude-host productization only.

## References

- Spec: `docs/superpowers/specs/2026-07-08-gitnexus-background-reindex-design.md`
- ADR: `docs/decisions/0039-gitnexus-background-reindex.md`
- Ported from the validated engine `~/.gitnexus-hooks/reindex-on-change.cjs`
- Fresh-install path: `setup/snapshot/hooks/gitnexus-reindex.cjs` +
  `setup/snapshot/claude-settings.json`, `setup/SKILL.md` Step 4c
- Drift invariants: `migrations/check-snapshot-parity.sh` §2 + §8
- Sibling copy+wire precedent: `0005-multi-ai-plan-review-enforcement.md`
- Sibling 2.x-axis precedent: `0025-knowledge-capture.md`
````

- [ ] **Step 2: Write fixture `01-fresh-insert/setup.sh`**

```sh
#!/bin/sh
# Fixture 01 — BEFORE: project at v2.3.0, baseline settings with one PostToolUse
# entry and NO gitnexus-reindex binding, empty .claude/hooks/. The typical fleet
# state 0026 upgrades.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
```

- [ ] **Step 3: Write fixture `01-fresh-insert/verify.sh`**

```sh
#!/bin/sh
# Replays 0026 Step 1 + Step 2 + Step 3 exactly (engine copied from the snapshot
# — $REPO_ROOT stands in for the scaffolder clone — PostToolUse Bash entry wired,
# version bumped) and asserts a surgical insert: the pre-existing PostToolUse
# entry survives and exactly one gitnexus-reindex entry is added.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

ENGINE_SRC="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
test -f "$ENGINE_SRC" || { echo "PRE: snapshot engine missing at $ENGINE_SRC"; exit 1; }

# Pre-conditions:
grep -q '^version: 2.3.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.3.0 before apply"; exit 1; }
jq -e '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length == 0' \
  .claude/settings.json >/dev/null || { echo "PRE: unexpected gitnexus-reindex entry before apply"; exit 1; }
test -e .claude/hooks/gitnexus-reindex.cjs && { echo "PRE: engine present before apply"; exit 1; }

# ── Step 1 (apply) — copy engine from the scaffolder snapshot ────────────────
mkdir -p .claude/hooks
cp "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
test -x .claude/hooks/gitnexus-reindex.cjs || { echo "STEP 1 failed: engine not executable"; exit 1; }
cmp -s "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs \
  || { echo "STEP 1 failed: installed engine differs from snapshot source"; exit 1; }

# ── Step 2 (apply) — wire the PostToolUse Bash entry ────────────────────────
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Exactly one gitnexus-reindex entry, matcher Bash, correct command + timeout
COUNT=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$COUNT" = "1" ] || { echo "STEP 2 failed: expected 1 entry, got $COUNT"; exit 1; }
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .matcher == "Bash"' \
  .claude/settings.json >/dev/null || { echo "STEP 2 failed: matcher != Bash"; exit 1; }
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex")) | .hooks[0].timeout == 5000' \
  .claude/settings.json >/dev/null || { echo "STEP 2 failed: timeout != 5000"; exit 1; }
# Surgical: the pre-existing skill-router entry survives
jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("skill-router-log"))' \
  .claude/settings.json >/dev/null || { echo "STEP 2 not surgical: pre-existing entry dropped"; exit 1; }

# ── Step 3 (apply) — version bump ────────────────────────────────────────────
sed -i.0026.bak -E 's/^version: 2\.3\.0$/version: 2.4.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0026.bak
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "STEP 3 failed: version not bumped to 2.4.0"; exit 1; }

echo "fixture 01 — engine copied (identical), Bash entry wired (surgical), version 2.3.0 -> 2.4.0"
```

- [ ] **Step 4: Write fixture `01-fresh-insert/expected-exit`** containing exactly `0`.

- [ ] **Step 5: Write fixture `02-idempotent-reapply/setup.sh`**

The BEFORE state is the ALREADY-APPLIED end state (version 2.4.0, engine present, entry wired); re-running the migration's Step 1/2/3 must change nothing.

```sh
#!/bin/sh
# Fixture 02 — BEFORE: 0026 already applied. Re-running must be a no-op.
set -eu
SKILL_VERSION=2.4.0 . "$FIXTURES_ROOT/common-setup.sh"

# Install the engine + entry so the fixture starts in the applied state.
cp "$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
jq '.hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs",
        "timeout": 5000
      }]
    }])' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

- [ ] **Step 6: Write fixture `02-idempotent-reapply/verify.sh`**

```sh
#!/bin/sh
# Re-running each step's guarded apply against the applied state is a no-op:
# the engine cmp-matches (Step 1 skipped), the any() guard short-circuits
# (Step 2 no new entry), and the version is already 2.4.0 (Step 3 skipped).
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

ENGINE_SRC="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
before_count=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$before_count" = "1" ] || { echo "PRE: expected exactly 1 entry in applied state, got $before_count"; exit 1; }

# Step 1 idempotency: engine already identical → cmp match → skip
cmp -s "$ENGINE_SRC" .claude/hooks/gitnexus-reindex.cjs \
  || { echo "PRE: applied-state engine differs from snapshot"; exit 1; }

# Step 2 re-apply (guarded) — must NOT add a second entry
jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"Bash","hooks":[{"type":"command","command":"x"}]}])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
after_count=$(jq '[.hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test("gitnexus-reindex"))] | length' .claude/settings.json)
[ "$after_count" = "1" ] || { echo "IDEMPOTENCY failed: entry count $before_count -> $after_count"; exit 1; }

# Step 3 idempotency: version already 2.4.0
grep -q '^version: 2.4.0$' .claude/skills/agentic-apps-workflow/SKILL.md \
  || { echo "PRE: expected version 2.4.0 in applied state"; exit 1; }

echo "fixture 02 — re-apply is a no-op (engine identical, single entry preserved, version steady)"
```

- [ ] **Step 7: Write fixture `02-idempotent-reapply/expected-exit`** containing exactly `0`.

- [ ] **Step 8: Write fixture `03-preserve-existing-posttooluse/setup.sh`**

```sh
#!/bin/sh
# Fixture 03 — BEFORE: a project whose settings already carry TWO custom
# PostToolUse entries (and none is gitnexus-reindex). The insert must leave both.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

cat > .claude/settings.json <<'EOF_SETTINGS'
{
  "hooks": {
    "PostToolUse": [
      {
        "_hook": "Hook 4a — Skill Router Audit Log",
        "matcher": "mcp__skills__.*|Bash",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/skill-router-log.sh", "timeout": 5000 }
        ]
      },
      {
        "_hook": "Hook 6 — Normalize CLAUDE.md",
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/normalize-claude-md.sh \"$CLAUDE_PROJECT_DIR/CLAUDE.md\"", "timeout": 5000 }
        ]
      }
    ]
  }
}
EOF_SETTINGS
```

- [ ] **Step 9: Write fixture `03-preserve-existing-posttooluse/verify.sh`**

```sh
#!/bin/sh
# The Step 2 insert appends the gitnexus-reindex entry and leaves BOTH existing
# PostToolUse entries (skill-router-log, normalize-claude-md) intact.
set -eu
command -v jq >/dev/null || { echo "SKIP-DEP: jq required"; exit 1; }

before=$(jq '.hooks.PostToolUse | length' .claude/settings.json)
[ "$before" = "2" ] || { echo "PRE: expected 2 existing entries, got $before"; exit 1; }

jq 'if (.hooks.PostToolUse // []) | any(.hooks[]?.command? | strings | test("gitnexus-reindex"))
    then .
    else .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
      "_hook": "Hook — GitNexus background reindex (migration 0026)",
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs", "timeout": 5000 }]
    }])
    end' .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

after=$(jq '.hooks.PostToolUse | length' .claude/settings.json)
[ "$after" = "3" ] || { echo "FAIL: expected 3 entries after insert, got $after"; exit 1; }
for cmd in skill-router-log normalize-claude-md gitnexus-reindex; do
  jq -e ".hooks.PostToolUse[]? | select(.hooks[]?.command? | strings | test(\"$cmd\"))" \
    .claude/settings.json >/dev/null || { echo "FAIL: entry '$cmd' missing after insert"; exit 1; }
done

echo "fixture 03 — insert preserved both existing PostToolUse entries (2 -> 3)"
```

- [ ] **Step 10: Write fixture `03-preserve-existing-posttooluse/expected-exit`** containing exactly `0`.

- [ ] **Step 11: Write fixture `04-engine-present-executable/setup.sh`**

```sh
#!/bin/sh
# Fixture 04 — no project state needed; asserts the SHIPPED snapshot engine.
set -eu
. "$FIXTURES_ROOT/common-setup.sh"
```

- [ ] **Step 12: Write fixture `04-engine-present-executable/verify.sh`**

```sh
#!/bin/sh
# The engine ships in BOTH the snapshot (fresh-install source) and templates
# (build source), is executable, and carries the node shebang.
set -eu
SNAP="$REPO_ROOT/setup/snapshot/hooks/gitnexus-reindex.cjs"
TPL="$REPO_ROOT/templates/.claude/hooks/gitnexus-reindex.cjs"

test -f "$SNAP" || { echo "FAIL: snapshot engine missing at $SNAP"; exit 1; }
test -x "$SNAP" || { echo "FAIL: snapshot engine not executable"; exit 1; }
test -f "$TPL"  || { echo "FAIL: template engine missing at $TPL"; exit 1; }
test -x "$TPL"  || { echo "FAIL: template engine not executable"; exit 1; }
head -1 "$SNAP" | grep -q '^#!/usr/bin/env node' || { echo "FAIL: snapshot engine missing node shebang"; exit 1; }
cmp -s "$SNAP" "$TPL" || { echo "FAIL: snapshot engine differs from template source"; exit 1; }

echo "fixture 04 — engine present + executable + node shebang in snapshot and templates (identical)"
```

- [ ] **Step 13: Write fixture `04-engine-present-executable/expected-exit`** containing exactly `0`.

- [ ] **Step 14: Run the 0026 fixtures to verify replay + engine-present PASS (GREEN)**

Run: `bash migrations/run-tests.sh 0026`
Expected: `✓ 01-fresh-insert`, `✓ 02-idempotent-reapply`, `✓ 03-preserve-existing-posttooluse`, `✓ 04-engine-present-executable`, `✓ 05-engine-behaviour` — 0 failures.

- [ ] **Step 15: Bump `skill/SKILL.md` to 2.4.0 and rebuild the snapshot**

Confirm the current line then bump:
```bash
grep -n '^version: 2.3.0$' skill/SKILL.md
sed -i.bak -E 's/^version: 2\.3\.0$/version: 2.4.0/' skill/SKILL.md && rm -f skill/SKILL.md.bak
grep -q '^version: 2.4.0$' skill/SKILL.md && echo "SKILL-BUMPED"
bash bin/build-snapshot.sh
```
Expected: `SKILL-BUMPED` then `snapshot rebuilt at version 2.4.0`.

- [ ] **Step 16: Run the FULL suite + parity to verify version coupling is GREEN**

Run:
```bash
bash migrations/run-tests.sh
bash migrations/check-snapshot-parity.sh
bash bin/build-snapshot.sh --check
```
Expected: full suite PASS with 0 failures (the drift test now sees `skill/SKILL.md` 2.4.0 == latest migration 0026 `to_version` 2.4.0); parity prints `PASS` (§5: snapshot VERSION 2.4.0 == latest `to_version`); `--check` exits 0.

- [ ] **Step 17: Commit**

```bash
git add migrations/0026-gitnexus-background-reindex.md \
        migrations/test-fixtures/0026 \
        skill/SKILL.md setup/snapshot/
git commit -m "feat(gitnexus): migration 0026 — background reindex hook (2.3.0 -> 2.4.0)"
```

---

## Task 4: Docs — ADR-0039 + CHANGELOG + MANIFEST

**Files:**
- Create: `docs/decisions/0039-gitnexus-background-reindex.md`
- Modify: `CHANGELOG.md` (new `[2.4.0]` section at top)
- Modify: `setup/snapshot/MANIFEST.md` (note the `.cjs` engine)

**Interfaces:**
- Consumes: everything from Tasks 1–3 (final names/paths/versions).
- Produces: documentation only — no code behavior.

- [ ] **Step 1: Write `docs/decisions/0039-gitnexus-background-reindex.md`**

```markdown
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
```

- [ ] **Step 2: Add the `[2.4.0]` section to `CHANGELOG.md`**

Insert immediately after the intro paragraph (before the `## [2.3.0]` heading):

```markdown
## [2.4.0] — GitNexus background reindex hook (reindex, not nudge)

Ships a claude-workflow-owned, **per-project** PostToolUse `matcher:"Bash"` hook
that runs a detached, incremental `gitnexus analyze` after a git commit, so a
repo's GitNexus index self-heals instead of relying on the agent to act on
gitnexus's global staleness *nudge*. The two coexist — our hook advances
`meta.lastCommit` to `HEAD`, so the global nudge self-silences on its next call.
Nothing global is modified. See ADR-0039.

### Added

- **`templates/.claude/hooks/gitnexus-reindex.cjs`** → `setup/snapshot/hooks/`
  → `.claude/hooks/gitnexus-reindex.cjs` — the reindex engine (ported from the
  validated `~/.gitnexus-hooks/reindex-on-change.cjs`, adding `$CLAUDE_PROJECT_DIR`-
  preferred root resolution). Fail-open (any error exits 0), lock-guarded
  (`.gitnexus/.reindex.lock`, `O_EXCL`, 10-min stale TTL), writer-pinned
  (`GITNEXUS_INVOCATION=gitnexus`), kill switch `GITNEXUS_AUTOREINDEX_DISABLED=1`,
  and a no-op in repos without a `.gitnexus/` directory.
- **PostToolUse `matcher:"Bash"` entry** in `templates/claude-settings.json`
  (→ snapshot) binding the engine with a 5s timeout.
- **`migrations/0026-gitnexus-background-reindex.md`** (2.3.0 → 2.4.0) — copies
  the engine from the scaffolder snapshot (idempotent — skips if byte-identical),
  wires the PostToolUse Bash entry if absent (guarded — never duplicates or
  overwrites a user edit), and bumps the installed version. Fixtures under
  `migrations/test-fixtures/0026/` (fresh-insert, idempotent-reapply,
  preserve-existing-posttooluse, engine-present-executable, engine-behaviour).
- **`docs/decisions/0039-gitnexus-background-reindex.md`** — the per-project-vs-global
  ownership decision and rejected alternatives (upstream, global installer).

### Changed

- **`bin/build-snapshot.sh`** now copies `templates/.claude/hooks/*.cjs` into the
  snapshot (and `chmod +x`), not just `*.sh`.
- **`migrations/check-snapshot-parity.sh`** — `gitnexus-reindex.cjs` added to the
  required hook bindings (§2) and a new §8 asserts the engine is present,
  executable, has a node shebang, and is bound on a PostToolUse Bash matcher.
```

- [ ] **Step 3: Note the `.cjs` engine in `setup/snapshot/MANIFEST.md`**

In the "Contents → install target" table, change the `hooks/*` row's "Source of truth" cell to record that `.cjs` hooks are now included:

Find:
```markdown
| `hooks/*` | `.claude/hooks/*` | `templates/.claude/hooks/*` |
```
Replace with:
```markdown
| `hooks/*` | `.claude/hooks/*` | `templates/.claude/hooks/*` (`.sh` + `.cjs`; includes the gitnexus-reindex engine — parity §8) |
```

- [ ] **Step 4: Verify docs cross-references resolve**

Run:
```bash
test -f docs/decisions/0039-gitnexus-background-reindex.md && echo "ADR-OK"
grep -q '^## \[2.4.0\]' CHANGELOG.md && echo "CHANGELOG-OK"
grep -q 'gitnexus-reindex engine' setup/snapshot/MANIFEST.md && echo "MANIFEST-OK"
```
Expected: `ADR-OK`, `CHANGELOG-OK`, `MANIFEST-OK`.

- [ ] **Step 5: Final full verification (belt-and-suspenders before commit)**

Run:
```bash
bash migrations/run-tests.sh
bash migrations/check-snapshot-parity.sh
bash bin/build-snapshot.sh --check
```
Expected: full suite PASS (0 failures); parity `PASS`; `--check` exits 0.

- [ ] **Step 6: Commit**

```bash
git add docs/decisions/0039-gitnexus-background-reindex.md \
        CHANGELOG.md setup/snapshot/MANIFEST.md
git commit -m "docs: ADR-0039 + CHANGELOG 2.4.0 + MANIFEST for gitnexus background reindex"
```

---

## Post-implementation (outside this plan)

Per the spec's Rollout and the workflow commitment, after the plan is executed:

1. **verification-before-completion** — re-run `migrations/run-tests.sh`,
   `migrations/check-snapshot-parity.sh`, and `bin/build-snapshot.sh --check`;
   confirm all green with captured output.
2. **`/review` + two-stage requesting-code-review** (same-LLM review then
   `/gsd-review` cross-AI — the latter is non-skippable).
3. **`/cso`** — the hook spawns a subprocess (detached `sh -c`), so a security
   pass is warranted.
4. **finishing-a-development-branch** — PR `feat/gitnexus-background-reindex` → main.
5. **After merge:** fast-forward `~/.claude/skills/agenticapps-workflow`
   (`git pull --ff-only origin main`), then `/update-agenticapps-workflow` per
   repo to apply migration 0026 (repos without gitnexus no-op harmlessly).

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- Problem / "reindex not nudge" → Task 1 engine + Task 3 migration.
- Ownership constraint (per-project only, no global edit) → Global Constraints + Task 2 (per-project settings) + ADR-0039 (Task 4).
- Architecture §Components 1 (engine) → Task 1. Component 2 (wiring) → Task 2 (templates) + Task 3 (migration Step 2). Component 3 (migration) → Task 3.
- Engine behaviours (root resolution, no-`.gitnexus` no-op, HEAD compare, lock/`O_EXCL`/TTL, detached spawn + `GITNEXUS_INVOCATION`, fail-open, kill switch) → Task 1 engine code + fixture 05.
- Data flow / error handling → engine code (Task 1) + ADR (Task 4).
- Testing §fixtures 01–04 + engine unit → Task 3 fixtures 01–04 + Task 1 fixture 05; `run-tests.sh` dispatcher → Task 1 Step 5; `check-snapshot-parity.sh` section → Task 2 §8; `build-snapshot.sh --check` stays green → verified in Tasks 2/3/4.
- Docs: ADR-0039, CHANGELOG `[2.4.0]`, MANIFEST → Task 4. (The spec's "standards checklist line" has no corresponding file in this repo — no `STANDARDS`/checklist doc exists — so it is intentionally not a step; the MANIFEST + CHANGELOG + parity §8 are the durable records.)
- Rollout / out-of-scope → Post-implementation section + ADR downstream-hosts note.

**2. Placeholder scan** — no `TBD`/`TODO`/"add error handling"/"similar to Task N"; every code and JSON block is complete and literal.

**3. Type/name consistency** — the engine filename `gitnexus-reindex.cjs`, the `_hook` label `Hook — GitNexus background reindex (migration 0026)`, the command `$CLAUDE_PROJECT_DIR/.claude/hooks/gitnexus-reindex.cjs`, timeout `5000`, matcher `Bash`, versions `2.3.0 → 2.4.0`, lock `.gitnexus/.reindex.lock`, env vars `GITNEXUS_INVOCATION` / `GITNEXUS_AUTOREINDEX_DISABLED`, and the copy source `setup/snapshot/hooks/gitnexus-reindex.cjs` are used identically across the engine, the settings entry, the migration doc, the fixtures, the parity §8, and the docs.
