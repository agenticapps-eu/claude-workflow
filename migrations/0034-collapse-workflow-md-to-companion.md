---
id: 0034
slug: collapse-workflow-md-to-companion
title: Collapse the vendored workflow reference to a companion that defers to the SKILL (v3.1.0 -> 3.2.0)
from_version: 3.1.0
to_version: 3.2.0
applies_to:
  - .claude/claude-md/workflow.md                       # re-vendored: ~190-line duplicate -> ~85-line companion (Step 1)
  - .claude/skills/agentic-apps-workflow/SKILL.md       # re-copied from the snapshot; 3.1.0 -> 3.2.0 (Step 2)
---

# Migration 0034 — Collapse the workflow reference to a companion (v3.1.0 → 3.2.0)

**The problem `0033` fixed, and the one it left.** `0033` retargeted
`.claude/claude-md/workflow.md` from the retired GSD engine onto the OpenSpec
lifecycle. What it shipped was ~190 lines that restate the trigger skill's
commitment ritual, lifecycle table, gate-to-skill map, rationalization table and
red flags. Correct, and duplicated.

Two copies of one rule set is the failure `0033` exists to repair. The guard it
added, `test_workflow_md_red_flags_match_canonical`, is a **pin holding two
copies in sync** — which is a workaround for having two copies at all. The
duplication is not hypothetical harm either: the §04 divergence that `0033`
closed took five migrations to notice *because* the second copy could drift
silently.

**What 0034 does.** The vendored file becomes a short **companion**: it orients
(three disciplines, the lifecycle stages, what the §18 gate enforces, where the
gstack tooling fits) and then defers. The commitment ritual template, the
rationalization table and the red flags live in the SKILL and are **not**
restated. The file opens with an explicit contract:

```
> **Authoritative source:** the enforcement skill
> [`.claude/skills/agentic-apps-workflow/SKILL.md`](../skills/agentic-apps-workflow/SKILL.md).
> This file is a short companion — it orients, then defers. It never duplicates
> the SKILL's lifecycle rules, gate map, rationalization table, or red flags
> (spec §11: one source, no drift).
```

**Where the shape came from.** Not invented here. `agents-task-viewer` reached
it independently, by hand, before `0033` shipped — a 67-line companion under
exactly that rule. When the `0033` rollout swept the fleet it *replaced* that
file with the 190-line duplicate, which is what surfaced the question. The
answer was that the downstream repo had it right and the scaffolder had it
wrong. This migration adopts the downstream shape upstream.

**Why the file is not simply deleted.** `CLAUDE.md` is always in the context
window; a skill is loaded only when its trigger fires. A short always-on
orientation document earns its place — the ~190-line restatement did not.
Deleting the file outright would additionally change
`.claude/hooks/normalize-claude-md.sh` behaviour (it keys off the file's
existence to collapse a `<!-- GSD:workflow -->` marker block, live in two repos
today) and break `0000`/`0009`'s post-checks. That remains a separate change,
if it is ever wanted.

**Supported upgrade floor:** `3.1.0 → 3.2.0`. Projects below 3.1.0 replay the
chain through `0033` first.

## Anchor tolerance (edits to released migrations)

`0000`'s post-check and `0009`'s Step 2 idempotency check both anchored on the
literal `Superpowers Integration Hooks (MANDATORY` heading as their "vendored
content is sane / current" sentinel. The companion has no hooks section, so that
heading is gone and both checks would report a healthy install as broken.

Both are made **shape-tolerant** rather than repointed — they now accept either
the legacy heading **or** `^> \*\*Authoritative source:`. Keeping both
alternatives matters: a chain replaying from an old install passes through the
pre-3.2.0 shape before reaching this migration, and a check that recognised only
the new sentinel would fail on the way through. This is the same
address-tolerance treatment `0001`'s Steps 4–6 and `0027`'s section matchers
received when `0032` changed the config shape under them.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (3.1.0), or 3.2.0 for re-apply.
grep -qE '^version: 3\.(1|2)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 3.1.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 3.1.0 -> 3.2.0."
  exit 3
}

# 2. The scaffolder clone carries the payload this migration re-vendors.
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
for f in claude-md-workflow.md agentic-apps-workflow-SKILL.md; do
  test -f "$SCAFFOLDER/setup/snapshot/$f" || {
    echo "ABORT: scaffolder clone at $SCAFFOLDER is missing setup/snapshot/$f."
    echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
    exit 3
  }
done

# 3. That payload is actually the COMPANION. Re-vendoring from a clone that
#    predates 0034 would copy the 190-line duplicate back over itself and report
#    success — the same stale-clone failure 0031 and 0033 guard against.
grep -q '^> \*\*Authoritative source:' "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0034 — its vendored"
  echo "       workflow reference is still the full duplicate, not the companion."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}
```

## Steps

> **Both steps are vendored-file replacements**, so the update runtime presents
> the 3-way divergence pick from `update/SKILL.md` on a local copy that differs.
>
> **Read the divergence carefully on this one.** The `0033` rollout has already
> demonstrated the failure mode in both directions: its prompt defaults to
> **Keep**, which was wrong for five repos carrying merely *stale* copies, and
> the operator's blanket **Replace** was wrong for the one repo carrying a
> deliberate rewrite. Divergence that is *age* wants Replace; divergence that is
> *intent* wants Keep. The prompt cannot tell them apart — you must. If the
> local copy already defers to the SKILL and carries no duplicated rule blocks,
> it is intent: keep it, or take **C** to make it the project's canonical.

### Step 1 — Re-vendor `.claude/claude-md/workflow.md` as the companion

Byte-copied from the scaffolder's snapshot: the `0031` Step 1 / `0032` Step 6 /
`0033` Step 1 idiom. As in `0033`, the check returns 0 (skip) both when no
vendored file exists — installing one is `0000`/`0009`'s job — and when the file
already matches byte-for-byte.

**Idempotency check:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ ! -f .claude/claude-md/workflow.md ]; then
  # Nothing vendored here; treat as already satisfied rather than as an error.
  true
else
  cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" \
         .claude/claude-md/workflow.md
fi
```

**Pre-condition:** none — a project without the file no-ops.

**Apply:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ -f .claude/claude-md/workflow.md ]; then
  install -m 0644 "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" \
    .claude/claude-md/workflow.md
else
  echo "SKIP: no .claude/claude-md/workflow.md here. 0034 re-vendors an existing"
  echo "      copy; installing a first one is 0000/0009's job, not this one's."
fi
```

**Rollback:**

```bash
git checkout -- .claude/claude-md/workflow.md 2>/dev/null || {
  echo "ROLLBACK: .claude/claude-md/workflow.md is not tracked — pre-migration"
  echo "          bytes are not recoverable. Re-run /update-agenticapps-workflow"
  echo "          to restore the canonical copy."
}
```

### Step 2 — Re-copy the trigger skill (3.1.0 → 3.2.0)

The snapshot copy carries `version: 3.2.0`. The SKILL's own content is unchanged
by this migration — it was already the authoritative copy; `0034` only stops a
second document from restating it.

**Idempotency check:**

```bash
grep -q '^version: 3.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:** none — prose + frontmatter replacement.

**Apply:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
install -m 0644 "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
  .claude/skills/agentic-apps-workflow/SKILL.md
```

**Rollback:**

```bash
git checkout -- .claude/skills/agentic-apps-workflow/SKILL.md
```

## Post-checks

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow

# 1. The vendored file is the companion, byte-identical to the scaffolder's copy.
if [ -f .claude/claude-md/workflow.md ]; then
  cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md
  grep -q '^> \*\*Authoritative source:' .claude/claude-md/workflow.md
fi

# 2. It no longer DUPLICATES the SKILL's rule blocks. This is the whole point of
#    the migration, so it is asserted rather than assumed.
if [ -f .claude/claude-md/workflow.md ]; then
  ! grep -qE '^#{2,4} [0-9]+ Red Flags' .claude/claude-md/workflow.md
  ! grep -q '^## Workflow commitment$'  .claude/claude-md/workflow.md
  ! grep -q 'If you think\.\.\.'        .claude/claude-md/workflow.md
fi

# 3. The SKILL still carries them — deferring to a document that lost the
#    content would be worse than duplicating it.
grep -q '^## 14 Red Flags — STOP → DELETE → RESTART$' .claude/skills/agentic-apps-workflow/SKILL.md
grep -q 'If you think\.\.\.' .claude/skills/agentic-apps-workflow/SKILL.md

# 4. 0033's guarantee is not regressed: still no GSD references.
for f in .claude/claude-md/workflow.md .claude/workflow-config.md; do
  if [ -f "$f" ]; then
    ! grep -qiE '/gsd-|GSD state|gsd-execute-phase' "$f"
  fi
done

# 5. CLAUDE.md still points at the file (0034 never touches CLAUDE.md).
if [ -f .claude/claude-md/workflow.md ]; then
  grep -q "claude-md/workflow.md" CLAUDE.md
fi

# 6. Version bumped; spec claim unchanged.
grep -q '^version: 3.2.0$' .claude/skills/agentic-apps-workflow/SKILL.md
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```

- Drift test green: SKILL.md `version` (3.2.0) == latest migration `to_version` (3.2.0)
- Snapshot parity green: rebuilt via `bash bin/build-snapshot.sh`

## Skip cases

- **`from_version` mismatch** (project not at 3.1.0) → framework skips silently.
  Projects below 3.1.0 replay `0033` first.
- **No `.claude/claude-md/workflow.md`** → Step 1 is a no-op. `0034` never
  installs one. `agenticapps-dashboard` is in this state permanently, by choice.
- **Already collapsed** (file matches the scaffolder) → both idempotency checks
  are positive; the migration no-ops.
- **Local copy is already a companion of the project's own authorship** (e.g.
  `agents-task-viewer`) → divergence prompt. **B (Keep)** or **C (vendor local
  as canonical)** are both defensible; Replace is not obviously wrong here
  either, since the shapes now agree in kind. Read the diff.

## Compatibility

- **Additive (minor) bump** to `3.2.0`. No enforcement surface moves: no hook,
  setting, config key, gate or command changes. One vendored document shrinks.
- **`implements_spec` stays `1.0.0`.** §09 item 1 binds the canonical §04 block
  to the host's instruction file (`skill/SKILL.md`), which is untouched.
  Removing the *duplicate* strengthens the claim rather than weakening it —
  there is now exactly one copy in the payload, so there is nothing to drift.
- **`0033`'s `test_workflow_md_red_flags_match_canonical` is inverted, not
  deleted.** With no second copy there is nothing to pin, but silently dropping
  the check would let a revert reintroduce the duplicate unnoticed. It now
  asserts the SKILL still carries the canonical block **and** that the template
  and snapshot do **not** carry a duplicate — the same
  assert-the-absence treatment `check-snapshot-parity.sh` §10 gave GitNexus.
- **Released migrations edited in place:** `0000`'s post-check and `0009`'s
  Step 2 idempotency check gain shape tolerance (see above). Both remain true
  for pre-3.2.0 shapes, so no replay path changes behaviour.
- **Snapshot parity (ADR-0036):** snapshot rebuilt from the 3.2.0 end state.

## Downstream

Every repo that just took `0033` takes this one too — the rollout state as of
this migration is in `0033`'s `## Downstream` table. Two notes specific to
`0034`:

- **`agents-task-viewer` is the origin of this shape**, not a straggler. Its
  local companion predates the upstream one and differs in wording. Either
  answer on the divergence prompt is defensible; the repo is not "behind".
- **`agenticapps-dashboard` has no `workflow.md`** and Step 1 no-ops there. It
  gets only the version bump, which is correct — it opted out of the file
  entirely and this migration does not re-litigate that.

## References

- The duplication this removes: `0033` +
  [ADR-0045](../docs/decisions/0045-revendor-openspec-instruction-payload.md)
  ("Open question this raised — should `workflow.md` exist at all?")
- Decision: [ADR-0046](../docs/decisions/0046-workflow-md-as-companion.md)
- Shape precedent: `agents-task-viewer`'s hand-authored companion
- Byte-copy idiom: `0031` Step 1, `0032` Step 6, `0033` Step 1
- Assert-the-absence precedent: `migrations/check-snapshot-parity.sh` §10
