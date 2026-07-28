---
id: 0033
slug: revendor-openspec-instruction-payload
title: Re-vendor the runtime instruction payload onto the OpenSpec lifecycle (v3.0.0 -> 3.1.0)
from_version: 3.0.0
to_version: 3.1.0
applies_to:
  - .claude/claude-md/workflow.md                       # re-vendored byte-for-byte from the scaffolder (Step 1)
  - .claude/workflow-config.md                          # hooks SECTION re-vendored; placeholders preserved (Step 2)
  - .claude/skills/agentic-apps-workflow/SKILL.md       # re-copied from the snapshot; 3.0.0 -> 3.1.0 (Step 3)
---

# Migration 0033 — Re-vendor the runtime instruction payload (v3.0.0 → 3.1.0)

**The defect.** Migration `0032` retargeted the *trigger skill*
(`.claude/skills/agentic-apps-workflow/SKILL.md`) onto the OpenSpec lifecycle
but left two vendored documents pointing at the retired GSD phase engine:

- `.claude/claude-md/workflow.md` — 12 GSD references, 0 OpenSpec. It told
  agents to "Check GSD state", declared pre-phase hooks "before
  `/gsd-execute-phase`", pointed at `.planning/config.json` → `hooks` (a tree
  `0032` Step 5 deleted), and carried a whole `## GSD Workflow Enforcement`
  section ending "Do not make direct repo edits outside a GSD workflow unless
  the user explicitly asks to bypass it."
- `.claude/workflow-config.md` — 4 GSD references, 0 OpenSpec: the hooks are
  described as enforcing "the Superpowers + GSD + gstack workflow", read from
  `.planning/config.json` → `hooks`, with an execution-order diagram rooted at
  `/gsd-execute-phase {N}`.

`workflow.md` is the file `CLAUDE.md` links to, so **it is what an agent reads
at runtime**. A project could pass all fifteen of `0032`'s post-checks, report
`version: 3.0.0` / `implements_spec: 1.0.0`, and still be instructed to route
its work through `/gsd-execute-phase`. That is not stale prose — it is the
instruction surface contradicting the enforcement surface, and the §18 gate
blocking edits the vendored document told the agent to make.

**What 0033 does, precisely.** It re-vendors both documents from the scaffolder
— the same byte-copy idiom `0031` Step 1 and `0032` Step 6 use — plus the
trigger skill, which carries the version stamp and drops a now-obsolete §04
disclosure (see *§04 reconciliation* below).

**One deliberate deviation from a pure byte-copy.**
`.claude/workflow-config.md` is **not** copied wholesale. Setup substitutes
every `{{PLACEHOLDER}}` in it with this project's name, repo, client, budget and
tech stack; a byte-copy would restore `{{PROJECT_NAME}}` and friends and destroy
the project's own configuration. Step 2 therefore replaces exactly one section —
`## Superpowers Integration Hooks` — and leaves everything else, including any
section the project added, untouched. `workflow.md` carries no placeholders and
*is* copied byte-for-byte.

**§04 reconciliation.** The vendored `workflow.md` carried its own 13-flag list
under a reworded heading, with flags 1, 6, 12 and 13 reworded relative to the
canonical §04 block. `skill/SKILL.md`'s `## Spec deltas` section disclosed that
divergence rather than fixing it. The re-vendored `workflow.md` now carries the
canonical block byte-for-byte — heading and all fourteen flags — so §09 item 1
holds by construction in both copies and the disclosure bullet is deleted rather
than carried forward. `migrations/run-tests.sh` asserts the byte-identity
(`test_workflow_md_red_flags_match_canonical`), so the two cannot drift apart
again silently.

**What 0033 deliberately does NOT do:**

1. **It does not delete `.claude/claude-md/workflow.md`.** One consuming repo
   has already removed it and that is a legitimate end state, but
   `.claude/hooks/normalize-claude-md.sh` keys off the file's *existence* to
   collapse a `<!-- GSD:workflow -->` marker block. Removing the file changes
   that hook's behaviour in every repo still carrying those markers. If the file
   should go away, that is its own migration with the hook change alongside it.
2. **It does not install either file into a project that lacks it.** Both steps
   no-op when the target is absent — installing is `0000`/`0009`'s job, not a
   re-vendor's.
3. **It does not touch `.planning/`, `openspec/`, `settings.json`, or any
   hook.** No enforcement surface moves; only the documents that describe it.

**Supported upgrade floor:** `3.0.0 → 3.1.0`. Projects below 3.0.0 replay the
chain through `0032` first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (3.0.0), or 3.1.0 for re-apply.
grep -qE '^version: 3\.(0|1)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md 2>/dev/null | sed 's/version: //')
  echo "ABORT: workflow scaffolder version is $INSTALLED (need 3.0.0)."
  echo "       Apply prior migrations first via /update-agenticapps-workflow."
  echo "       Supported upgrade floor: 3.0.0 -> 3.1.0."
  exit 3
}

# 2. The scaffolder clone carries the payload this migration re-vendors.
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
for f in claude-md-workflow.md workflow-config.md agentic-apps-workflow-SKILL.md; do
  test -f "$SCAFFOLDER/setup/snapshot/$f" || {
    echo "ABORT: scaffolder clone at $SCAFFOLDER is missing setup/snapshot/$f."
    echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
    exit 3
  }
done

# 3. That payload is actually the RETARGETED one. This is the whole point of the
#    migration: re-vendoring from a clone that predates 0033 would copy the same
#    GSD-teaching bytes back over themselves and report success. Same failure
#    0031's pre-flight clause 2 exists to prevent.
if grep -qiE '/gsd-|GSD state' \
     "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" \
     "$SCAFFOLDER/setup/snapshot/workflow-config.md"; then
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0033 — its vendored"
  echo "       instruction payload still teaches GSD. Re-vendoring from it is a no-op."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
fi
```

## Steps

> **All three steps are vendored-file replacements.** The update runtime MUST
> byte-compare the project's copy against the scaffolder source before writing
> and, on a difference that is not simply the pre-0033 canonical, present the
> 3-way divergence pick defined in `update/SKILL.md` ("Divergence variant":
> **A** replace with canonical · **B** keep local copy · **C** vendor the local
> copy as canonical), defaulting to **B**. Several downstream copies of
> `workflow.md` have been hand-edited; clobbering them silently is exactly what
> that prompt exists to prevent.

### Step 1 — Re-vendor `.claude/claude-md/workflow.md`

Byte-copied from the scaffolder's snapshot — the single source of truth, and the
same idiom `0031` Step 1 used for the reindex engine and `0032` Step 6 for the
trigger skill. Not a sed patch: a re-copy picks up the whole retarget at once,
and "byte-identical to the vendored source" is a cleaner invariant to verify
than "does not contain these strings".

The check below returns 0 (skip — nothing to do) in BOTH of these cases, and
non-zero only when there is real work:

- **No vendored file at all.** `0009`/`0000` never ran here, or the project
  removed the file deliberately (one consuming repo has). Installing one is not
  this migration's job.
- **The file already matches the vendored source byte-for-byte.**

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
  echo "SKIP: no .claude/claude-md/workflow.md here. 0033 re-vendors an existing"
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

### Step 2 — Re-vendor the hooks section of `.claude/workflow-config.md`

**Section replacement, not a byte-copy — deliberately.** Setup Step 4b
substitutes `{{PROJECT_NAME}}`, `{{REPO}}`, `{{CLIENT}}`, `{{BUDGET}}` and the
tech-stack placeholders in this file with the project's real values, and
`setup/SKILL.md`'s own post-check asserts no `{{...}}` survives. A byte-copy of
the template would put every one of them back and silently destroy the
project's configuration. Only `## Superpowers Integration Hooks` — the section
that carries the GSD prose — is replaced; everything above it, and any section
the project added after it, is preserved.

**Idempotency check:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ ! -f .claude/workflow-config.md ]; then
  true
else
  _sect() {
    awk -v h="## Superpowers Integration Hooks" '
      $0 == h { inb=1; print; next }
      inb && /^## / { inb=0 }
      inb { print }' "$1"
  }
  _a="$(mktemp)"; _b="$(mktemp)"
  _sect "$SCAFFOLDER/setup/snapshot/workflow-config.md" > "$_a"
  _sect .claude/workflow-config.md > "$_b"
  cmp -s "$_a" "$_b"; _rc=$?
  rm -f "$_a" "$_b"
  test "$_rc" -eq 0
fi
```

**Pre-condition:**

```bash
test ! -f .claude/workflow-config.md || \
  grep -q '^## Superpowers Integration Hooks$' .claude/workflow-config.md
```

A project whose copy has no such heading is not one this step knows how to
patch; it fails the pre-condition and is reported rather than guessed at.

**Apply:**

```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
if [ -f .claude/workflow-config.md ]; then
  _sect() {
    awk -v h="## Superpowers Integration Hooks" '
      $0 == h { inb=1; print; next }
      inb && /^## / { inb=0 }
      inb { print }' "$1"
  }
  _canon="$(mktemp)"; _out="$(mktemp)"
  _sect "$SCAFFOLDER/setup/snapshot/workflow-config.md" > "$_canon"
  # Splice: on the heading line emit the canonical section (which starts with
  # that same heading), drop the old section body, resume at the next `## `.
  awk -v h="## Superpowers Integration Hooks" -v canon="$_canon" '
    $0 == h { inb=1; while ((getline line < canon) > 0) print line; close(canon); next }
    inb && /^## / { inb=0 }
    inb { next }
    { print }' .claude/workflow-config.md > "$_out" && mv "$_out" .claude/workflow-config.md
  rm -f "$_canon"
else
  echo "SKIP: no .claude/workflow-config.md here — nothing to re-vendor."
fi
```

**Rollback:**

```bash
git checkout -- .claude/workflow-config.md 2>/dev/null || {
  echo "ROLLBACK: .claude/workflow-config.md is not tracked — pre-migration bytes"
  echo "          are not recoverable. The project's own config sections above the"
  echo "          hooks section were never touched."
}
```

### Step 3 — Re-copy the trigger skill (3.0.0 → 3.1.0)

Same byte-copy idiom as `0032` Step 6. The snapshot copy carries `version:
3.1.0` and the `## Spec deltas` section with the §04 divergence bullet removed
— that delta is closed by Step 1, so carrying the disclosure forward would be
recording a divergence that no longer exists.

**Idempotency check:**

```bash
grep -q '^version: 3.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md
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

# 1. No GSD command reference survives in either vendored document. This is the
#    check the defect existed for: it survived five migrations because nothing
#    asserted it.
for f in .claude/claude-md/workflow.md .claude/workflow-config.md; do
  if [ -f "$f" ]; then
    ! grep -qiE '/gsd-|GSD state|gsd-execute-phase' "$f"
  fi
done

# 2. The vendored workflow reference is byte-identical to the scaffolder's copy
#    (a project that never had one still has none — correct, not a failure).
if [ -f .claude/claude-md/workflow.md ]; then
  cmp -s "$SCAFFOLDER/setup/snapshot/claude-md-workflow.md" .claude/claude-md/workflow.md
fi

# 3. Both documents now teach the OpenSpec lifecycle.
if [ -f .claude/claude-md/workflow.md ]; then
  grep -q 'openspec/changes/' .claude/claude-md/workflow.md
fi
if [ -f .claude/workflow-config.md ]; then
  grep -q '`lifecycle`' .claude/workflow-config.md
fi

# 4. Step 2 preserved the project's substituted config (a byte-copy of the
#    template would have put the placeholders back).
if [ -f .claude/workflow-config.md ]; then
  ! grep -q '{{PROJECT_NAME}}' .claude/workflow-config.md
  grep -q '^## Project$' .claude/workflow-config.md
fi

# 5. §04 reconciled: the red-flag block in the vendored workflow reference is
#    byte-identical to the canonical block in the installed trigger skill.
if [ -f .claude/claude-md/workflow.md ]; then
  _rf() {
    awk '/^## 14 Red Flags — STOP → DELETE → RESTART$/ { f=1; print; next }
         f && /^## / { exit }
         f { print }' "$1"
  }
  _x="$(mktemp)"; _y="$(mktemp)"
  _rf .claude/skills/agentic-apps-workflow/SKILL.md > "$_x"
  _rf .claude/claude-md/workflow.md > "$_y"
  cmp -s "$_x" "$_y"; _rc=$?
  rm -f "$_x" "$_y"
  test "$_rc" -eq 0
fi

# 6. Version bumped; spec claim unchanged.
grep -q '^version: 3.1.0$' .claude/skills/agentic-apps-workflow/SKILL.md
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 7. Nothing else moved.
test -d .planning
! test -e .claude/hooks/multi-ai-review-gate.sh
```

- Drift test green: SKILL.md `version` (3.1.0) == latest migration `to_version` (3.1.0)
- Snapshot parity green: rebuilt via `bash bin/build-snapshot.sh`

## Skip cases

- **`from_version` mismatch** (project not at 3.0.0) → migration framework skips
  silently per the standard rule. Projects below 3.0.0 replay `0032` first.
- **No `.claude/claude-md/workflow.md`** (never vendored, or removed
  deliberately) → Step 1 is a no-op. `0033` never installs one.
- **No `.claude/workflow-config.md`** → Step 2 is a no-op.
- **Already re-vendored** (both copies match the scaffolder) → every step's
  idempotency check is positive; the migration no-ops.
- **Local copy diverges** (hand-edited `workflow.md`) → the update runtime
  presents the 3-way pick and honours it. Choosing **B (keep local)** leaves the
  project on GSD-teaching prose *by explicit operator decision*, which is the
  point of the prompt; the step is logged as skipped and the migration outcome
  is partial.

## Compatibility

- **Additive (minor) bump** to `3.1.0`: no enforcement surface changes. Three
  documents are re-vendored; no hook, setting, config key, or gate moves.
- **`implements_spec` stays `1.0.0`, unchanged** — no spec moved. §04's §09
  item-1 obligation was already satisfied by `skill/SKILL.md` before this
  migration; `0033` extends the same byte-identity to the runtime copy and
  therefore retires the disclosure, which is a *reduction* in declared deltas,
  not a change of claim.
- **Drift coupling:** as the highest-numbered migration file, `0033`'s
  `to_version` (3.1.0) becomes the drift target asserted by
  `test_skill_md_version_matches_latest_migration_to_version`; `skill/SKILL.md`
  and `setup/snapshot/VERSION` move to `3.1.0` in the release that ships it.
- **Snapshot parity (ADR-0036):** snapshot rebuilt from the 3.1.0 end state;
  `migrations/check-snapshot-parity.sh` green.

## Downstream

Measured, not estimated — eleven repos carry a vendored copy today:

| Repo | `claude-md/workflow.md` | `workflow-config.md` |
|---|---|---|
| `agenticapps-roadmap` | yes | yes |
| `agents-task-viewer` | yes | yes |
| `workflow-testbed` | yes | yes |
| `bench-claude` | yes | yes |
| `bench-claude-2` | yes | yes |
| `workflow-testbed-claude` | yes | yes |
| `factiv/callbot` | yes | yes |
| `factiv/cparx` | yes | yes |
| `factiv/fbc-platform` | yes | yes |
| `factiv/fx-signal-agent` | yes | yes |
| `agenticapps-dashboard` | **no** (removed) | yes |

`agents-task-viewer`'s `CLAUDE.md` additionally carries the
`## GSD Workflow Enforcement` section inlined verbatim from the pre-0033
template. `0033` does not touch `CLAUDE.md`: stripping a section from the file
that carries the canonical §11 block is the surgery migrations `0029`, `0030`
and `0043` exist because of. Remove it by hand with the diff in front of you.

`cparx` and `agents-task-viewer` still carry `<!-- GSD:workflow -->` marker
blocks handled by `normalize-claude-md.sh`; those are unaffected because Step 1
never removes the file the hook keys off.

## References

- Defect disclosed but not fixed: `skill/SKILL.md` `## Spec deltas` §04 bullet
  (removed by this migration), [ADR-0040](../docs/decisions/0040-spec-0.9.0-conformance.md)
- Reconciliation rationale: [ADR-0045](../docs/decisions/0045-revendor-openspec-instruction-payload.md)
- Precedent for the byte-copy idiom: `0031` Step 1, `0032` Step 6
- Divergence prompt contract: `update/SKILL.md` "Divergence variant"
- Regression guards: `migrations/run-tests.sh`
  `test_no_gsd_refs_in_shipped_templates`, `test_workflow_md_red_flags_match_canonical`
