#!/usr/bin/env node
/* eslint-disable */
// ^ This is a vendored CommonJS (.cjs) Node hook, not application code. It uses
//   require() by necessity and is not part of any project's TypeScript surface.
//   Consuming repos that lint .claude/ would otherwise fail it on rules like
//   @typescript-eslint/no-require-imports; a hook is tooling, so linting is off.
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

// Is the process that wrote this lock still running? The lock file holds the
// writer's PID. `kill(pid, 0)` sends no signal — it just probes liveness:
// throws ESRCH if the process is gone, EPERM if it exists but is another
// user's. An unreadable/blank PID is treated as dead (reclaimable). Used to
// distinguish "the previous reindex crashed" from "the previous reindex is
// legitimately still running past the TTL".
function ownerAlive(lock) {
  let pid;
  try {
    pid = parseInt(fs.readFileSync(lock, 'utf8').trim(), 10);
  } catch {
    return false; // unreadable lock — treat as dead
  }
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true; // process exists
  } catch (e) {
    return e.code === 'EPERM'; // EPERM = alive but not ours; ESRCH = gone
  }
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
    if (Date.now() - st.mtimeMs < LOCK_TTL_MS) return; // fresh lock — a reindex is in flight
    // Lock is older than the TTL. Reclaim it ONLY if its owner is actually
    // gone: a genuine analyze that runs past LOCK_TTL_MS is still holding the
    // DB, and reclaiming it there would spawn a second analyze racing on the
    // same SQLite file — the corruption mode the lock exists to prevent.
    if (ownerAlive(lock)) return;
    fs.unlinkSync(lock); // owner is dead — reclaim the stale lock
  } catch {
    /* no lock present */
  }
  try {
    fs.writeFileSync(lock, String(process.pid), { flag: 'wx' }); // O_EXCL
  } catch {
    return; // lost the create race to a sibling hook
  }

  // Detached incremental reindex. argv-form spawn — NO shell — so the lock
  // path is never interpolated into a command string (a repo path containing
  // a quote, backtick, or $() would otherwise break out of `sh -c`). The lock
  // is cleared on the child's exit, which fires in this parent before it
  // returns; unref() keeps the parent off the critical path regardless.
  // GITNEXUS_INVOCATION pins the write to the local build (storage parity).
  const child = spawn('gitnexus', ['analyze'], {
    cwd: root,
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, GITNEXUS_INVOCATION: 'gitnexus' },
  });
  child.on('exit', () => {
    try {
      fs.unlinkSync(lock);
    } catch {
      /* already gone, or reclaimed by a later run — the TTL is the backstop */
    }
  });
  child.unref();
}

try {
  main();
} catch {
  /* fail-open — a freshness hook must never break the host */
}
process.exit(0);
