---
id: 0031
slug: reindex-skip-agents-md
title: Re-sync the reindex engine with --skip-agents-md (v2.8.0 -> 2.9.0)
from_version: 2.8.0
to_version: 2.9.0
applies_to:
  - .claude/hooks/gitnexus-reindex.cjs                 # re-copy the engine from the scaffolder snapshot (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md      # version bump 2.8.0 -> 2.9.0 (Step 2)
---

# Migration 0031 — Re-sync the reindex engine with `--skip-agents-md` (v2.8.0 -> 2.9.0)

**The bug.** `gitnexus analyze` rewrites the `<!-- gitnexus:start -->`…
`<!-- gitnexus:end -->` section of `AGENTS.md` / `CLAUDE.md` as a side effect
of indexing. Migration 0026 shipped a per-project hook
(`.claude/hooks/gitnexus-reindex.cjs`) that spawns `gitnexus analyze`
DETACHED after every commit. So a project that deliberately removes or edits
that section has the change silently reverted on its next commit — by our own
tooling. `gitnexus analyze --skip-agents-md` ("Skip updating the gitnexus
section in AGENTS.md and CLAUDE.md") is the documented fix, and it is now the
flag the vendored engine passes.

**What 0031 does, precisely.** It re-syncs `.claude/hooks/gitnexus-reindex.cjs`
against the scaffolder's snapshot — the same byte-copy idiom migration 0026
used to install it in the first place, RE-RUN rather than sed-patching the
flag in. A re-copy picks up this fix and any other engine change since 0026,
and byte-equality with the vendored source is a cleaner invariant to maintain
than "contains a flag". Projects that never ran 0026 have no engine to
re-sync and are left untouched — installing one for the first time is 0026's
job, not this migration's.

**Supported upgrade floor:** `2.8.0 -> 2.9.0`. Projects below 2.8.0 replay the
chain through 0030 first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (2.8.0), or 2.9.0 for re-apply.
grep -qE '^version: 2\.(8|9)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 2.8.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 2.8.0 -> 2.9.0."
  exit 3
}

# 2. The scaffolder's snapshot carries the engine Step 1 re-syncs against
#    (guards against running 0031 from a stale scaffolder clone that predates
#    the --skip-agents-md fix, which would re-sync projects onto the SAME
#    stale bytes they already have).
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
test -f "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0031."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}
```

## Steps

### Step 1 — Re-sync the reindex engine

The engine is **re-copied from the scaffolder's snapshot** (single source of
truth), the same idiom migration 0026 used to install it, so a re-synced
install is byte-identical to a fresh snapshot install and the code cannot
drift. This is deliberately NOT a sed patch for the `--skip-agents-md` flag:
a re-copy picks up this fix and any other engine change since 0026 in one
step, and "byte-identical to the vendored source" is a cleaner invariant to
verify than "contains this one flag".

The check below returns 0 (skip — nothing to do) in BOTH of the following
cases, and returns non-zero only when there is real work to do:

- **No engine installed at all.** `.claude/hooks/gitnexus-reindex.cjs` does
  not exist — migration 0026 was never applied here, so there is nothing to
  re-sync. Installing an engine into a project that never had one is 0026's
  job, not 0031's; this migration must never do it. (This repo,
  `claude-workflow`, is itself in this state.)
- **The engine already matches the vendored source byte-for-byte.**

**Idempotency check:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ ! -f .claude/hooks/gitnexus-reindex.cjs ]; then
  # 0026 was never applied here; nothing to re-sync. Treat as already
  # satisfied rather than as an error — this is the expected steady state
  # for any project that never opted into the reindex hook.
  true
else
  cmp -s "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" \
         .claude/hooks/gitnexus-reindex.cjs
fi
```

Only reached when the engine exists AND differs from the vendored source —
the idempotency check above already ruled out "absent" and "identical".

**Apply:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
cp "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
chmod +x .claude/hooks/gitnexus-reindex.cjs
```

Step 1 has no forward inverse. It overwrites a stale engine with the vendored
one; the pre-migration bytes are not preserved anywhere, and restoring them
would re-introduce the exact defect this migration exists to fix — a hook
that unconditionally rewrites AGENTS.md/CLAUDE.md on every commit. This is
safe by construction because Step 1 is byte-idempotent: if Step 2 fails, the
project holds a re-synced engine and a 2.8.0 stamp, 0031 stays pending, and a
re-run is a no-op for Step 1 plus a retry for Step 2. `migrations/README.md`
sanctions this — "partial-state recovery may be more useful than full
revert" and rollback may be "manual". Rollback is therefore an honest
report, not an action: it never removes or rewrites the engine file, and it
never exits the calling shell (an `exit` from an eval'd Rollback block would
terminate the caller, not just this block).

**Rollback:**

```bash
if [ -f .claude/hooks/gitnexus-reindex.cjs ]; then
  echo "ROLLBACK: Step 1 has no inverse — .claude/hooks/gitnexus-reindex.cjs"
  echo "          is left synced to the vendored engine (which runs"
  echo "          'gitnexus analyze --skip-agents-md'). Restoring the"
  echo "          pre-sync bytes would reintroduce the defect this"
  echo "          migration exists to fix."
else
  echo "ROLLBACK: no .claude/hooks/gitnexus-reindex.cjs present — nothing to do."
fi
```

### Step 2 — Bump the installed scaffolder version 2.8.0 -> 2.9.0

**Idempotency check:**

```bash
grep -q '^version: 2\.9\.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -qE '^version: 2\.(8\.0|9\.0)$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

```bash
sed -i.0031.bak 's/^version: 2\.8\.0$/version: 2.9.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0031.bak
```

**Rollback:**

```bash
sed -i.0031.bak 's/^version: 2\.9\.0$/version: 2.8.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md \
  && rm -f .claude/skills/agentic-apps-workflow/SKILL.md.0031.bak
```

## Post-checks

```bash
# 1. Version bumped to 2.9.0 at the canonical hyphenated path (ALWAYS true on success)
grep -q '^version: 2.9.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 2. If the engine is present at all, it is byte-identical to the vendored
#    source (a project that never had one still has none — that is correct,
#    not a failure of this check).
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ -f .claude/hooks/gitnexus-reindex.cjs ]; then
  cmp -s "$SCAFFOLDER/setup/snapshot/hooks/gitnexus-reindex.cjs" .claude/hooks/gitnexus-reindex.cjs
  test -x .claude/hooks/gitnexus-reindex.cjs
fi
```

## Skip cases

- **`from_version` mismatch** (project not at 2.8.0) → migration framework
  skips silently per the standard rule. Projects below 2.8.0 replay 0030
  first.
- **No engine installed** (0026 never applied) → Step 1 is a no-op; 0031
  never installs an engine into a project that never had one.
- **Engine already re-synced** (byte-identical to the vendored source) →
  Step 1 is a no-op.

## Compatibility

- **Additive (minor) bump** to `2.9.0`: no breaking change. Step 1 overwrites
  one file only when it exists and differs; nothing is added or removed for a
  project that never opted into 0026's reindex hook.
- **`implements_spec` stays `0.9.0`, unchanged** — no spec moved. This
  migration fixes an engine-level defect in claude-workflow's own tooling; it
  is not a spec-conformance change.
- **Drift coupling:** as the highest-numbered migration file, 0031's
  `to_version` (2.9.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  and `setup/snapshot/VERSION` are bumped to `2.9.0` in the release that ships
  this migration (tracked separately from migration authoring).

## Downstream

Verified affected today: `agenticapps-dashboard`, `callbot`, `cparx`,
`fx-signal-agent` — all four carry the pre-`--skip-agents-md` engine copied in
by migration 0026 and need this re-sync.

## References

- Source fix: `templates/.claude/hooks/gitnexus-reindex.cjs`,
  `setup/snapshot/hooks/gitnexus-reindex.cjs`
- Precedent for the byte-copy idiom: `0026-gitnexus-background-reindex.md` Step 1
- Precedent for the honest reporting-no-op rollback:
  `0030-resync-spec-11-mirror-bytes.md` Step 1 Rollback
