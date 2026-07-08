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
