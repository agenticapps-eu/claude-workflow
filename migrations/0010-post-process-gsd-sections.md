---
id: 0010
slug: post-process-gsd-sections
title: Post-process GSD section markers in CLAUDE.md
from_version: 1.8.0
to_version: 1.9.0
applies_to:
  - .claude/hooks/normalize-claude-md.sh (new file in consumer repos)
  - .claude/settings.json (PostToolUse hook block added)
  - CLAUDE.md (one-shot normalization on user confirm)
  - .claude/skills/agentic-apps-workflow/SKILL.md (version bump)
requires: [0009]
optional_for: []
---

# Migration 0010 — Post-process GSD section markers in CLAUDE.md

Brings projects from AgenticApps workflow v1.8.0 to v1.9.0 by installing
`.claude/hooks/normalize-claude-md.sh` — a PostToolUse hook that
collapses inlined `<!-- GSD:{slug}-start source:{label} -->...<!-- GSD:{slug}-end -->`
blocks in `CLAUDE.md` into a self-closing reference form:

```text
<!-- GSD:{slug} source:{label} /-->
## {Heading}
See [`{linkPath}`](./{linkPath}) — auto-synced.
```

Why: migration 0009 vendored the Superpowers/GSD/gstack workflow block
(~150 lines per repo), but consumer repos still have the GSD-managed
section blocks inlined by the upstream `gsd-tools generate-claude-md`
CLI (`~/.claude/get-shit-done/bin/lib/profile-output.cjs`,
`buildSection()` line 236). Those blocks account for ~265 lines in
`factiv/cparx/CLAUDE.md` after 0009 applies — keeping cparx above the
200-line context-budget target.

0010 ships:

1. A POSIX bash 3.2+ script (no node dependency) that normalizes any
   marker block in-place. Idempotent; source-existence-safe (preserves
   block when the resolved source file is absent); aware of 0009's
   vendored `.claude/claude-md/workflow.md` (collapses the `workflow`
   block entirely once 0009 has applied).
2. A PostToolUse hook registration that re-runs the script after every
   `Edit|Write|MultiEdit` tool call on `CLAUDE.md`, defending against
   future `gsd-tools generate-claude-md` runs that re-inflate the blocks.
3. A one-shot pass during this migration's apply step (with user
   confirm and diff preview, consistent with 0009's Step 4 pattern) to
   seed the existing CLAUDE.md.

The post-processor does NOT touch:
- 0009's `## Workflow` reference block (it has no `<!-- GSD: -->` markers).
- Any non-GSD content in CLAUDE.md.
- Blocks whose `source:` attribute resolves to a missing file (the safety
  guard preserves them unchanged and emits a warning to stderr).

ADR 0022 captures the upstream-vs-post-process trade-off, why a hook in
claude-workflow was chosen over patching `gsd-tools` upstream, and the
0009/0010 boundary.

## Pre-flight

```bash
# Required: project at exactly v1.8.0
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.8.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.8.0"; exit 1; }

# Required: 0009's vendored workflow file (this migration relies on its
# existence to detect when the `workflow` GSD block can be removed)
test -f .claude/claude-md/workflow.md \
  || { echo "ERROR: .claude/claude-md/workflow.md missing — migration 0009 must apply first"; exit 1; }

# Required: project files exist
test -f CLAUDE.md || { echo "ERROR: CLAUDE.md not found"; exit 1; }
test -f .claude/settings.json || { echo "ERROR: .claude/settings.json not found — re-run /setup-agenticapps-workflow"; exit 1; }
test -f .claude/skills/agentic-apps-workflow/SKILL.md || { echo "ERROR: workflow skill missing"; exit 1; }

# Required: vendored template source available in the workflow scaffolder
test -x ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh \
  || { echo "ERROR: workflow scaffolder is older than 1.9.0 — git pull on ~/.claude/skills/agenticapps-workflow"; exit 1; }
```

## Steps

### Step 1: Vendor `normalize-claude-md.sh` into `.claude/hooks/`

**Idempotency check:** `test -x .claude/hooks/normalize-claude-md.sh && grep -q "Migration 0010 — Normalize GSD section markers" .claude/hooks/normalize-claude-md.sh`
**Pre-condition:** the source script exists at `~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh`
**Apply:**
```bash
mkdir -p .claude/hooks
cp ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh \
   .claude/hooks/normalize-claude-md.sh
chmod +x .claude/hooks/normalize-claude-md.sh
```
**Rollback:** `rm -f .claude/hooks/normalize-claude-md.sh`

The idempotency check pairs file-existence with a content-sentinel
(grep for the well-known header line). The sentinel guards against
"file exists but is stale" — re-running this step on a project that
upgraded the script via a future migration is safe (the new version
also carries the sentinel).

### Step 2: Register the PostToolUse hook in `.claude/settings.json`

**Idempotency check:** `grep -q "normalize-claude-md.sh" .claude/settings.json`
**Pre-condition:** Step 1 succeeded (`.claude/hooks/normalize-claude-md.sh` exists), and `.claude/settings.json` exists and is valid JSON.
**Apply:** Insert a `PostToolUse` hook block matching `Edit|Write|MultiEdit`. Two paths depending on environment:

```bash
# Preferred: jq-based insert (if jq available, structural correctness guaranteed)
if command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp)"
  jq '.hooks.PostToolUse += [{
    "_hook": "Hook 6 — Normalize CLAUDE.md after Edit/Write (migration 0010)",
    "matcher": "Edit|Write|MultiEdit",
    "hooks": [{
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/normalize-claude-md.sh \"$CLAUDE_PROJECT_DIR/CLAUDE.md\"",
      "timeout": 5000
    }]
  }]' .claude/settings.json > "$TMP" && mv "$TMP" .claude/settings.json
else
  # Fallback: agent-driven hand-edit — the migration runtime opens
  # .claude/settings.json, locates `"PostToolUse": [`, and appends the
  # new hook entry preserving array shape and surrounding indentation.
  # The runtime MUST validate the resulting JSON parses cleanly before
  # writing back (e.g. via `python -m json.tool < .claude/settings.json
  # > /dev/null`). Abort the step on parse failure; revert to original.
  echo "ERROR: jq not available; agent-driven edit required" >&2
  exit 1
fi
```

**Rollback:** Remove the hook entry. With jq:
```bash
jq '.hooks.PostToolUse |= map(select(._hook != "Hook 6 — Normalize CLAUDE.md after Edit/Write (migration 0010)"))' \
  .claude/settings.json > "$TMP" && mv "$TMP" .claude/settings.json
```
Without jq: agent-driven removal anchored on the unique `_hook` label.

The hook script's first action is to check whether the input file's
basename is exactly `CLAUDE.md`. If not, the script **refuses** the
invocation with exit code 1 (Stage-2 + CSO hardening: prevents the
hook from clobbering arbitrary files). PostToolUse fires on every
Edit/Write — even though the script exits cheaply on non-CLAUDE.md
paths, the basename check is the security boundary, not just an
optimization. This filter lives in the script (not the matcher)
because Claude Code matchers operate on tool names, not file-path
arguments.

### Step 3: One-shot normalize existing CLAUDE.md

**Idempotency check:** `! grep -qE "^<!--[[:space:]]*GSD:[a-z]+-start" CLAUDE.md`
**Pre-condition:** Step 1 + Step 2 succeeded. `.claude/hooks/normalize-claude-md.sh` is in place and executable.
**Apply:** The migration runtime evaluates whether CLAUDE.md contains
any inlined GSD marker blocks. If yes, it generates a diff preview and
prompts the user:

```bash
# Detect inlined blocks
HAS_MARKERS=0
grep -qE "^<!--[[:space:]]*GSD:[a-z]+-start" CLAUDE.md && HAS_MARKERS=1

if [ "$HAS_MARKERS" = "1" ]; then
  # Dry-run: produce normalized output without modifying the real file.
  # Note: the post-processor refuses to operate on any path whose
  # basename is not exactly `CLAUDE.md`. The preview lives in its own
  # subdirectory so the basename stays canonical, and so the
  # source-existence guard resolves `.planning/PROJECT.md` etc.
  # relative to the preview-CWD's view of the project tree (achieved
  # via `cd` plus symlinks back to `.planning/` and `.claude/`).
  PREVIEW_DIR="$(mktemp -d)"
  cp CLAUDE.md "$PREVIEW_DIR/CLAUDE.md"
  ln -s "$(pwd)/.planning" "$PREVIEW_DIR/.planning"
  ln -s "$(pwd)/.claude"   "$PREVIEW_DIR/.claude"
  ( cd "$PREVIEW_DIR" && .claude/hooks/normalize-claude-md.sh "$PREVIEW_DIR/CLAUDE.md" )
  diff -u CLAUDE.md "$PREVIEW_DIR/CLAUDE.md"
fi
```

The user-facing prompt:

> CLAUDE.md contains N inlined GSD marker blocks (project, stack,
> conventions, architecture, skills, workflow, profile). Migration 0010's
> post-processor will convert each into a self-closing reference form.
> Diff: [show]. Choose:
> A) Apply normalization now (CLAUDE.md drops ~X lines)
> B) Skip — only install the hook; let it normalize on the next
>    Edit/Write of CLAUDE.md (subtler steady-state convergence)
> C) Show resolved file paths for each `source:` label (lets you verify
>    they exist before normalizing)

When user picks A, the runtime runs the script in place:
```bash
.claude/hooks/normalize-claude-md.sh CLAUDE.md
```

Source-missing blocks are preserved (the script's safety guard handles
this and emits a stderr warning per block).

If the user picks B, the migration completes with partial outcome
(hook installed but CLAUDE.md still has inlined blocks until the next
Edit/Write). Re-running 0010 with `--migration 0010` retries Step 3's
prompt.

**Rollback:** Restore CLAUDE.md from the working-tree snapshot taken
at Step 3 entry. The migration runtime has not committed yet during
0010's execution (consistent with 0009's per-step rollback model).

### Step 4: Bump installed version field in `.claude/skills/agentic-apps-workflow/SKILL.md`

**Idempotency check:** `grep -q '^version: 1.9.0' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** `.claude/skills/agentic-apps-workflow/SKILL.md` exists and currently has `version: 1.8.0`
**Apply:** Edit the file frontmatter to change `version: 1.8.0` → `version: 1.9.0`.
**Rollback:** Edit `version: 1.9.0` → `version: 1.8.0`.

## Post-checks

```bash
# Hook script exists and is executable
test -x .claude/hooks/normalize-claude-md.sh

# Hook is registered in settings.json
grep -q "normalize-claude-md.sh" .claude/settings.json

# Sanity check: settings.json is still valid JSON
python -m json.tool < .claude/settings.json >/dev/null \
  || (command -v jq >/dev/null && jq empty .claude/settings.json) \
  || { echo "ERROR: .claude/settings.json is invalid JSON after migration"; exit 1; }

# CLAUDE.md has no inlined marker blocks (only if user picked A in Step 3)
if grep -qE "^<!--[[:space:]]*GSD:[a-z]+-start" CLAUDE.md; then
  echo "WARN: inlined GSD marker blocks still present in CLAUDE.md (Step 3 was skipped or partial). The PostToolUse hook will normalize them on the next Edit/Write, or re-run with --migration 0010 to retry."
fi

# Version bumped
grep -q '^version: 1.9.0' .claude/skills/agentic-apps-workflow/SKILL.md
```

## Skip cases

- **Project not at v1.8.0** — pre-flight blocks. The update skill chains
  migration 0009 first if the project is on 1.7.0 or older.
- **Workflow scaffolder older than 1.9.0** (vendored script source missing)
  — pre-flight blocks with `git pull` instruction.
- **`.claude/claude-md/workflow.md` missing** — pre-flight blocks. 0010
  requires 0009 (the `workflow` GSD-block-removal special case in the
  script depends on this file existing as the sentinel for "0009 has
  applied"). Re-run 0009 first.
- **`.claude/settings.json` invalid JSON** — Step 2 aborts. User must
  repair the settings file manually before retrying.
- **Step 3 user-skipped** — migration completes with partial outcome;
  hook is installed and will normalize on the next Edit/Write. CLAUDE.md
  retains inlined blocks until then.

## ADR opportunities

After this migration, the update skill prompts: "Want to draft a project
ADR documenting why your CLAUDE.md is now reference-link form? Recommended
only if your project has customized any of the GSD-managed section
contents (e.g. team-specific architecture notes that lived in the inlined
block). Otherwise upstream ADR 0022 is the canonical rationale."
Default: skip.

## Notes for runtime implementers

The Step 3 detection bash is portable across BSD `grep` (macOS default)
and GNU `grep` (Linux). The character class `^<!--[[:space:]]*GSD:[a-z]+-start`
uses POSIX bracket expressions, not GNU `\s` shorthand.

Step 2's jq-based insert preserves whitespace and key ordering reasonably
well. If a project's `.claude/settings.json` has been hand-formatted with
specific indentation, jq's default 2-space pretty-print may diff from the
original. The migration runtime SHOULD diff jq's output against the
original and fall back to agent-driven hand-edit if the structural diff
is larger than the new hook entry alone (i.e. jq has reformatted the
entire file).

The post-processor script's `set -o pipefail` is important: the
`normalize | collapse_blank_runs` pipeline must propagate the
`return 2` from `normalize()` (unclosed marker) instead of being masked
by the trailing `awk` success exit. Without pipefail, malformed input
would silently produce broken output with exit 0.
