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
