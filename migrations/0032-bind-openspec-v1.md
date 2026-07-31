---
id: 0032
slug: bind-openspec-v1
title: Bind the OpenSpec front end, retire GitNexus and the PLAN.md review gate (v2.9.0 -> 3.0.0)
from_version: 2.9.0
to_version: 3.0.0
applies_to:
  - ~/.agenticapps/bin/openspec-change-gate.sh          # NEW — the §18 host-agnostic gate (Step 1)
  - ~/.agenticapps/bin/run-plan-review.sh               # NEW — the multi-AI review producer (Step 1)
  - ~/.agenticapps/bin/reviewer-cli.sh                  # NEW — the producer's vendor wrapper, core 1.0.0 (Step 1)
  - .git/hooks/pre-commit                               # NEW — agent-agnostic enforcement floor (Step 1)
  - openspec/                                           # NEW — the spec slot, via `openspec init` (Step 2)
  - .claude/commands/opsx/                              # NEW — generated /opsx:* commands (Step 2)
  - .claude/hooks/openspec-change-gate.sh               # NEW — PreToolUse shim onto the global gate (Step 3)
  - .claude/hooks/multi-ai-review-gate.sh               # DELETED — superseded by the shim (Step 3)
  - .claude/hooks/gitnexus-reindex.cjs                  # DELETED — GitNexus removed (Step 4)
  - .claude/scripts/{install,rollback}-gitnexus.sh      # DELETED — GitNexus removed (Step 4)
  - .claude/scripts/index-family-repos.sh               # DELETED — GitNexus removed (Step 4)
  - .claude/settings.json                               # rebind PreToolUse; drop the gitnexus PostToolUse (Steps 3, 4)
  - .planning/config.json                               # hooks tree -> §17 lifecycle block; claim -> 1.0.0 (Step 5)
  - .claude/skills/agentic-apps-workflow/SKILL.md       # instruction surface retarget; 2.9.0 -> 3.0.0 (Steps 6, 7)
requires:
  - tool: openspec
    verify: "openspec --version"
    install: "npm i -g @fission-ai/openspec"
  - tool: jq
    verify: "command -v jq >/dev/null"
    install: "brew install jq"
optional_for:
  - tag: reviewers
    detect: "command -v gemini >/dev/null || command -v codex >/dev/null"
    note: "the gate installs regardless, but stage 2 cannot be satisfied without >=2 other-vendor reviewer CLIs; install them before opening a change"
---

# Migration 0032 — Bind OpenSpec (v2.9.0 → 3.0.0)

Adopts `agenticapps-workflow-core` **spec v1.0.0**: the OpenSpec + Superpowers
front end (§16–§19, core ADR-0021). This host's adoption decision is
[ADR-0044](../docs/decisions/0044-openspec-superpowers-adoption.md); the
lifecycle is explained in [`docs/WORKFLOW.md`](../docs/WORKFLOW.md).

It replaces the 0.x GSD phase engine as the **planning** discipline and leaves
the **execution** discipline (Superpowers — TDD, evidence, independent review)
untouched. It is the largest migration in the chain: it installs a new
enforcement gate, initializes a spec slot, restructures the gate-binding config,
and removes two subsystems.

**Three things this migration deliberately does NOT do:**

1. **It does not touch `.planning/`.** The phase tree is the project's effort
   history and its backup. Converting phases into `openspec/specs/` is a
   supervised, human-ratified job (phases merge into *capabilities*, not
   one-phase-one-spec) and is out of scope for an unattended script.
2. **It does not delete the migrations, ADRs, or fixtures that document
   GitNexus or the PLAN.md-era gate.** §08 supersede-don't-delete: they are the
   replay path for a project upgrading from a pre-3.0.0 version.
3. **It does not open a change for itself.** The gate it installs cannot gate
   its own installing session (§18 names this inherent). The pre-commit floor it
   also installs takes effect from the next commit.

**Supported upgrade floor:** `2.9.0 → 3.0.0`. Projects below 2.9.0 replay the
chain through `0031` first.

## Pre-flight (hard aborts on failure)

```bash
# 1. Workflow SKILL.md is at the supported floor (2.9.0), or 3.0.0 for re-apply.
grep -qE '^version: (2\.9|3\.0)\.0$' .claude/skills/agentic-apps-workflow/SKILL.md || {
  echo "ABORT: project is not at 2.9.0 (or 3.0.0). Replay the chain through 0031 first."
  exit 3
}

# 2. jq is required — Steps 4 and 5 edit JSON structurally, never with sed.
command -v jq >/dev/null || { echo "ABORT: jq required for migration 0032."; exit 3; }

# 3. Inside a git repo — Step 1 installs a pre-commit hook.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ABORT: run inside a git repository."; exit 3; }

# 4. The scaffolder clone carries the 3.0.0 payload (guards a stale clone).
#    BOTH halves of §18 are checked: the gate that consumes review evidence and
#    the wrapper that produces it. A clone carrying only the gate installs a
#    producer whose every reviewer arm dies on a missing file — and Step 1 does
#    not run under `set -e`, so that failure scrolls past as a stderr line while
#    the migration reports success.
#    Since ADR-0047 the scaffolder does not VENDOR those two files — it pins
#    them. So the staleness check moved to the pin: a clone that has the
#    resolver and the manifest can produce both halves, and one that has
#    neither predates 0032 exactly as a missing gate used to signal.
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
test -x "$SCAFFOLDER/bin/resolve-core-artifact.sh" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER predates 0032."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}
test -f "$SCAFFOLDER/tools/core-vendor.manifest" || {
  echo "ABORT: scaffolder clone at $SCAFFOLDER has no core pin — nothing to publish."
  echo "       cd $SCAFFOLDER && git pull --ff-only origin main"
  exit 3
}

# 5. openspec CLI — WARN, not abort. The gate installs and blocks either way
#    (an unvalidatable change must not pass, §18); only Step 2's init is skipped.
openspec --version >/dev/null 2>&1 || \
  echo "WARN: openspec CLI absent — Step 2 will be skipped. npm i -g @fission-ai/openspec"
```

## Steps

### Step 1 — Install the §18 gate, the review producer, and the git floor

**Idempotency check:** `test -x "$HOME/.agenticapps/bin/openspec-change-gate.sh" && test -x "$HOME/.agenticapps/bin/reviewer-cli.sh" && test -x "$(git rev-parse --git-path hooks)/pre-commit"`

The `reviewer-cli.sh` clause is deliberate. A project that applied an earlier
revision of this migration has the gate and the floor but no vendor wrapper, and
its producer would call a file that is not there. Reading that state as "already
applied" would strand it; reading it as "not applied" re-runs a step whose every
write is idempotent. Fix forward.
**Pre-condition:** none — fixes forward on any project.
**Apply:**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
mkdir -p "$HOME/.agenticapps/bin"
# The scaffolder pins these three rather than vendoring them (ADR-0047):
# core-vendor.manifest names one core commit and a sha256 per file, and
# resolve-core-artifact.sh turns that into verified bytes. Fails CLOSED — an
# unresolvable pin aborts the step rather than publishing whatever is at hand.
# This step does not run under `set -e`, so each resolve is checked explicitly.
_resolve() {
  "$SCAFFOLDER/bin/resolve-core-artifact.sh" "$SCAFFOLDER/tools/core-vendor.manifest" "$1"
}
_gate_src="$(_resolve bin/openspec-change-gate.sh)" || {
  echo "ABORT: could not resolve the gate from core — nothing published."; exit 3; }
_rp_src="$(_resolve bin/run-plan-review.sh)" || {
  echo "ABORT: could not resolve the producer from core — nothing published."; exit 3; }
_rc_src="$(_resolve bin/reviewer-cli.sh)" || {
  echo "ABORT: could not resolve the wrapper from core — nothing published."; exit 3; }
# ~/.agenticapps/bin is SHARED by claude / codex / opencode / pi. Writing it
# unconditionally is last-writer-wins: a host vendoring an older gate silently
# republishes it over a newer one and reverts the fix for every agent on the
# machine. The gate's own header requires installers to refuse a downgrade, so
# arbitrate on the version marker exactly as install.sh does.
# ONE awk, no pipeline, anchored X.Y.Z. `sed -n ... | head -n1 | grep . || echo
# 0.0.0` is a downgrade hole twice over, both verified: with enough marker lines
# head closes the pipe, sed takes SIGPIPE, and under `set -o pipefail` the
# fallback fires AFTER the real version printed — returning "9.9.9\n0.0.0", which
# sort -V reads as 0.0.0; and `[0-9][0-9.]*` parses `9.0.0junk` as `9.0.0`.
# Unparseable is 0.0.0, which fails safe in both directions.
gate_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# gate-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_incoming="$(gate_version "$_gate_src")"
_installed="$(gate_version "$HOME/.agenticapps/bin/openspec-change-gate.sh")"
_older="$(printf '%s\n%s\n' "$_incoming" "$_installed" | sort -V | head -n1)"
if [ "$_installed" != "$_incoming" ] && [ "$_older" = "$_incoming" ]; then
  echo "NOTE: shared gate is $_installed, newer than the pinned $_incoming — refusing to downgrade."
  echo "      Advance core_commit in the scaffolder's tools/core-vendor.manifest."
else
  install -m 0755 "$_gate_src" "$HOME/.agenticapps/bin/openspec-change-gate.sh"
fi
install -m 0755 "$_rp_src"      "$HOME/.agenticapps/bin/run-plan-review.sh"
# The producer's vendor wrapper is the SAME shared-path hazard as the gate, and
# it already fired: a host installer delivered the arbitrated 1.2.2 gate and, in
# the same run, blind-installed a 3-arm wrapper over the 4-arm one. The
# `opencode` arm vanished and the next review that asked for it was recorded as
# "reviewer unavailable" and waved through with one fewer opinion (core#41).
# Same rule, same reasoning, on `# reviewer-cli-version:`. Unmarked = 0.0.0.
# Same parser shape, and the same reasons, as gate_version above.
reviewer_cli_version() {
  [ -f "$1" ] || { echo "0.0.0"; return; }
  awk '/^# reviewer-cli-version: [0-9]+\.[0-9]+\.[0-9]+[ \t]*$/ { print $3; found=1; exit }
       END { if (!found) print "0.0.0" }' "$1"
}
_rc_incoming="$(reviewer_cli_version "$_rc_src")"
_rc_installed="$(reviewer_cli_version "$HOME/.agenticapps/bin/reviewer-cli.sh")"
_rc_older="$(printf '%s\n%s\n' "$_rc_incoming" "$_rc_installed" | sort -V | head -n1)"
if [ "$_rc_installed" != "$_rc_incoming" ] && [ "$_rc_older" = "$_rc_incoming" ]; then
  echo "NOTE: shared reviewer-cli is $_rc_installed, newer than the pinned $_rc_incoming — refusing to downgrade."
  echo "      Advance core_commit in the scaffolder's tools/core-vendor.manifest."
else
  install -m 0755 "$_rc_src" "$HOME/.agenticapps/bin/reviewer-cli.sh"
fi
rm -f "$_gate_src" "$_rp_src" "$_rc_src"
hooks_dir="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks_dir"
if [ -e "$hooks_dir/pre-commit" ] && ! grep -q 'openspec-change-gate' "$hooks_dir/pre-commit" 2>/dev/null; then
  # Never clobber a project's own pre-commit hook. Preserve it and report.
  cp "$hooks_dir/pre-commit" "$hooks_dir/pre-commit.pre-0032"
  echo "NOTE: existing pre-commit saved as pre-commit.pre-0032 — merge it by hand."
fi
install -m 0755 "$SCAFFOLDER/bin/git-hooks/pre-commit" "$hooks_dir/pre-commit"
```
**Rollback:**
```bash
rm -f "$HOME/.agenticapps/bin/openspec-change-gate.sh" "$HOME/.agenticapps/bin/run-plan-review.sh"
# reviewer-cli.sh is deliberately NOT removed. ~/.agenticapps/bin is shared by
# claude / codex / opencode / pi, and the wrapper carries no per-host ownership:
# deleting it here strips a vendor arm from every other agent on the machine,
# which is core#41's harm arriving by a different route. Rolling one host back
# must not disarm the others. (The two paths above have the same flaw and are
# left as-is — changing a released rollback recipe is its own change.)
hooks_dir="$(git rev-parse --git-path hooks)"
if [ -e "$hooks_dir/pre-commit.pre-0032" ]; then
  mv "$hooks_dir/pre-commit.pre-0032" "$hooks_dir/pre-commit"
else
  rm -f "$hooks_dir/pre-commit"
fi
```

### Step 2 — Initialize the spec slot and generate the `/opsx:*` commands

Bound **upstream** (§16): the CLI generates the slot and the per-tool command
files. Nothing is vendored or hand-authored here.

**Idempotency check:** `test -d openspec/changes && test -d openspec/specs`
**Pre-condition:** `openspec --version >/dev/null 2>&1` — else SKIP this step
with a note (see Skip cases).
**Apply:**
```bash
openspec init --tools claude --profile core
```
**Rollback:** `rm -rf openspec .claude/commands/opsx`

> Adopt the OPSX **Core** profile (`explore` / `propose` / `apply` / `archive`).
> The Expanded profile's `/opsx:verify` overlaps
> `superpowers:verification-before-completion`, and Superpowers stays the
> authority on verification — two verification surfaces is how one gets skipped.

### Step 3 — Retarget the PreToolUse gate

Same hook slot, new predicate. The project-local hook becomes a thin shim so
there is exactly one place the rule lives.

**Idempotency check:** `test -x .claude/hooks/openspec-change-gate.sh && ! test -e .claude/hooks/multi-ai-review-gate.sh`
**Pre-condition:** `.claude/settings.json` parses as JSON.
**Apply:**
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
install -m 0755 "$SCAFFOLDER/templates/.claude/hooks/openspec-change-gate.sh" \
  .claude/hooks/openspec-change-gate.sh
rm -f .claude/hooks/multi-ai-review-gate.sh
tmp="$(mktemp)"
jq '
  .hooks.PreToolUse = [
    ( .hooks.PreToolUse // [] )[]
    # Drop only the RETIRED COMMANDS, not the whole entry. An entry whose hooks
    # array holds both the old gate and a project-owned hook must keep the
    # latter; filtering by entry silently deleted it.
    | .hooks = [ (.hooks // [])[] | select((.command // "") | test("multi-ai-review-gate|openspec-change-gate") | not) ]
    # An entry left with no hooks was only ever the old gate — drop it.
    | select((.hooks | length) > 0)
  ] + [{
    "_hook": "Hook 7 — OpenSpec Change Gate (spec §18; retarget of the multi-AI plan-review gate)",
    "matcher": "Edit|Write|MultiEdit|NotebookEdit",
    "hooks": [{
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/openspec-change-gate.sh",
      "timeout": 15000
    }]
  }]
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json
```
> The filter drops **both** the old binding and any existing
> `openspec-change-gate` one before appending. Dropping only the old name would
> make the step non-idempotent: the append is unconditional, so a re-run would
> add a second identical gate binding and the hook would fire twice per edit.
> (Caught by fixture `02-idempotent-reapply`.)

**Rollback:** `git checkout -- .claude/settings.json && git checkout -- .claude/hooks/multi-ai-review-gate.sh 2>/dev/null; rm -f .claude/hooks/openspec-change-gate.sh`

### Step 4 — Remove GitNexus

**Idempotency check:** `! test -e .claude/hooks/gitnexus-reindex.cjs && ! jq -e '[.. | .command? // empty | select(test("gitnexus"))] | length > 0' .claude/settings.json >/dev/null 2>&1`
**Pre-condition:** none — a project that never installed GitNexus no-ops.
**Apply:**
```bash
rm -f .claude/hooks/gitnexus-reindex.cjs \
      .claude/scripts/install-gitnexus.sh \
      .claude/scripts/rollback-gitnexus.sh \
      .claude/scripts/index-family-repos.sh
rm -rf .gitnexus
tmp="$(mktemp)"
jq '
  .hooks.PostToolUse = [
    ( .hooks.PostToolUse // [] )[]
    # Same surgical rule as PreToolUse: remove the gitnexus command, keep any
    # co-registered project hook that shares the entry.
    | .hooks = [ (.hooks // [])[] | select((.command // "") | test("gitnexus") | not) ]
    | select((.hooks | length) > 0)
  ]
' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json
```
**Rollback:** `git checkout -- .claude/settings.json .claude/hooks .claude/scripts 2>/dev/null; true`

> The `<!-- gitnexus:start -->` region is **not** stripped from `CLAUDE.md` here.
> Removing it is a §11-adjacent text surgery on a file that carries the canonical
> block, and migrations 0029/0030/0043 exist because that surgery is where data
> loss happens. With the engine gone nothing rewrites the region any more, so it
> is inert; leave it, or remove it by hand with the diff in front of you.

### Step 5 — Restructure `.planning/config.json` onto the §17 lifecycle

Wholesale restructure, not a field edit: the `hooks` tree
(`pre_phase`/`per_plan`/`pre_execute_gates`/`post_phase`/`finishing`) is replaced
by the `lifecycle` block. The repo-specific `knowledge_capture` block (§15) is
**preserved** across the swap.

**Idempotency check:** `jq -e '.lifecycle.validate.change_gate' .planning/config.json >/dev/null`
**Pre-condition:** `jq -e '.hooks.pre_execute_gates.multi_ai_plan_review // .hooks.post_phase' .planning/config.json >/dev/null` (a 0.x-shaped config)
**Apply:**
```bash
TPL=~/.claude/skills/agenticapps-workflow/templates/config-hooks.json
tmp="$(mktemp)"
# Start from the PROJECT's config and overlay the template, then drop only the
# retired 0.x `hooks` tree. `$tpl[0] + .` would have discarded every key the
# project owns — `.workflow` (host-tool-written), repo policy, anything custom —
# which contradicts both this migration's surgical framing and the snapshot
# guard's own note that `.workflow` is not ours to touch.
jq --slurpfile tpl "$TPL" \
  '. as $proj | $proj + $tpl[0]
   | if $proj.knowledge_capture then .knowledge_capture = $proj.knowledge_capture else . end
   | del(.hooks)' \
  .planning/config.json > "$tmp" && mv "$tmp" .planning/config.json
```
**Rollback:** `git checkout -- .planning/config.json`

### Step 6 — Retarget the instruction surface

**Idempotency check:** `grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** none — prose replacement.
**Apply:** re-copy the trigger skill from the scaffolder snapshot (the same
byte-copy idiom 0031 used for the engine — a re-copy picks up the whole
retarget, and byte-equality with the vendored source is a cleaner invariant
than "contains a heading"):
```bash
SCAFFOLDER=~/.claude/skills/agenticapps-workflow
install -m 0644 "$SCAFFOLDER/setup/snapshot/agentic-apps-workflow-SKILL.md" \
  .claude/skills/agentic-apps-workflow/SKILL.md
```
**Rollback:** `git checkout -- .claude/skills/agentic-apps-workflow/SKILL.md`

> Step 6 supersedes 0027's Step 1/2 text surgery for this upgrade: the whole
> file is replaced, so the §04 red-flag ordering and the `## Spec deltas`
> section arrive correct by construction rather than by patch.

### Step 7 — Record the new version

**Idempotency check:** `grep -q '^version: 3.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** Step 6 applied (the copied file already carries 3.0.0).
**Apply:** the snapshot copy in Step 6 carries `version: 3.0.0` and
`implements_spec: 1.0.0`; no separate edit is needed. Verify:
```bash
grep -q '^version: 3.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
```
**Rollback:** covered by Step 6's rollback.

## Post-checks

```bash
# 1. The gate is installed and answers the §18 truth table.
test -x "$HOME/.agenticapps/bin/openspec-change-gate.sh"
printf '{"tool":"Edit","tool_input":{"file_path":"x.ts"}}' \
  | "$HOME/.agenticapps/bin/openspec-change-gate.sh"; test $? -eq 0   # no active change -> allow
printf '{"tool":"Write","tool_input":{"file_path":"openspec/changes/a/proposal.md"}}' \
  | "$HOME/.agenticapps/bin/openspec-change-gate.sh"; test $? -eq 0   # openspec artifact -> exempt

# 2. The spec slot exists and the PreToolUse gate is bound.
test -d openspec/changes && test -d openspec/specs
jq -e '[.hooks.PreToolUse[]?.hooks[]?.command? | select(test("openspec-change-gate"))] | length == 1' \
  .claude/settings.json >/dev/null

# 3. The retired surfaces are gone.
! test -e .claude/hooks/multi-ai-review-gate.sh
! test -e .claude/hooks/gitnexus-reindex.cjs
! jq -e '[.. | .command? // empty | select(test("gitnexus"))] | length > 0' \
    .claude/settings.json >/dev/null 2>&1

# 4. Config is on the lifecycle, both §18 clauses bound, no standalone gate.
jq -e '.lifecycle.validate.change_gate and .lifecycle.validate.multi_ai_review' .planning/config.json >/dev/null
jq -e '.implements_spec == "1.0.0" and .front_end == "openspec"' .planning/config.json >/dev/null
jq -e '(.hooks.pre_execute_gates.multi_ai_plan_review // null) == null' .planning/config.json >/dev/null

# 5. knowledge_capture survived the restructure (§15).
jq -e '.knowledge_capture.enabled | type == "boolean"' .planning/config.json >/dev/null

# 6. Version + claim mirrored.
grep -q '^version: 3.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md
grep -q '^implements_spec: 1.0.0$' .claude/skills/agentic-apps-workflow/SKILL.md

# 7. .planning/ untouched.
test -d .planning/phases
```

- Drift test green: SKILL.md `version` (3.0.0) == latest migration `to_version` (3.0.0)
- Snapshot parity green: rebuilt via `bash bin/build-snapshot.sh`

## Skip cases

- **`from_version` mismatch** (project not at 2.9.0) → framework skips silently;
  projects below 2.9.0 replay the chain through `0031` first.
- **Already at 3.0.0** (config has `.lifecycle.validate.change_gate`) → every
  step's idempotency check is positive; the migration no-ops.
- **`openspec` CLI absent** → Step 2 is skipped with a note. The gate still
  installs, and it **blocks** while the CLI is missing: an unvalidatable change
  must not pass (§18). Install the CLI and re-run.
- **Fewer than 2 other-vendor reviewer CLIs** → the gate installs and blocks the
  first change until reviewers exist. Use `GSD_SKIP_REVIEWS=1` for a logged
  emergency override; do not remove the gate.
- **No `.planning/config.json`** (project never ran `0000`) → Step 5's
  pre-condition fails; the rest still applies.

## Compatibility

- **Minor → major:** `implements_spec` 0.9.0 → **1.0.0**, workflow `version`
  2.9.0 → **3.0.0**. A front-end replacement, the largest change since baseline.
- **Superpowers execution discipline unchanged** (§01/§03/§04/§05/§06/§11) — the
  commitment ritual, the rationalisation table, the canonical 13 red flags, the
  evidence rules, and the §11 Coding Discipline block all carry forward verbatim.
- **plan-review reconciliation:** the multi-AI review is **KEPT** and retargeted
  at the active change; §17 forbids shipping it as a standalone gate, so it
  lives as the §18 change-gate predicate plus `run-plan-review.sh`. The 0.x
  `plan_review` binding and `multi-ai-review-gate.sh` are retired (ADR-0018 is
  superseded-by-retarget, not reversed).
- **Retired by this migration:** `0005`, `0007`, `0016`, `0026`, `0031`. Their
  docs and fixtures stay on disk; their test bodies now assert the *absence* of
  the payload, so a revert that reintroduces it fails the suite.
- **Shape tolerance:** `0001`'s Steps 4–6 and `0027`'s section matchers were made
  address-tolerant so the chain still replays against a 1.0.0-shaped config.
- **Drift coupling:** as the highest-numbered migration, `0032`'s `to_version`
  (3.0.0) is the drift target; the trigger SKILL.md moves in lockstep.
- **Snapshot parity (ADR-0036):** snapshot rebuilt from the 3.0.0 end state.
