# Phase 07 — PLAN.md

Migration 0010: post-process GSD section markers in CLAUDE.md.

**Phase goal:** Ship migration 0010 (claude-workflow v1.8.0 → v1.9.0) that
installs a `normalize-claude-md.sh` post-processor, registers it as a
Claude Code PostToolUse hook, and one-shot normalizes any existing
inlined `<!-- GSD:{slug}-start -->` blocks into a 3-line reference form.
Apply to cparx and verify CLAUDE.md drops from 647L → ≤200L.

**Predecessor:** Phase 06 (migration 0009, v1.7.0 → v1.8.0). 0009 must
have applied first; 0010 builds on the vendored workflow file location.

---

## Threat model

| Threat | Mitigation | Verified by |
|---|---|---|
| Script silently corrupts CLAUDE.md (wrong regex match) | Process line-by-line with explicit state machine. Verify each fixture transformation against `expected/` golden. | `run-tests.sh test_migration_0010()` diff assertions |
| Script deletes content when source file is missing | Safety guard: skip block if resolved source path doesn't exist. Emit warning. | Fixture `inlined-source-missing.md` (PRESERVE block) |
| Script runs in infinite loop because PostToolUse fires on its own write | Hook script reads CLAUDE.md, computes new content, compares — writes only if content changed. PostToolUse-on-Edit-of-CLAUDE.md after a no-op write doesn't re-fire (Claude Code doesn't re-emit PostToolUse for the hook's own writes). | Fixture `dual-state-after-gsd-tools.md` (run script twice; second is no-op) |
| Hook fails silently on platforms without GNU sed | Use POSIX-only constructs (no `sed -i`, no `\s`). Use `awk` or pure bash where sed differs across BSD/GNU. | macOS (BSD) + Linux (GNU) shell harness |
| `gsd-tools generate-claude-md` (no `--auto`) re-inflates between hook fires | PostToolUse on subsequent CLAUDE.md write catches it. Document `--auto` recommendation. | Manual scenario in ADR + `dual-state` fixture |
| Script accidentally touches 0009's vendored block (`.claude/claude-md/workflow.md` content reference) | Regex scoped to `<!-- GSD:[a-z]+-start` markers; 0009's reference is plain markdown. | Fixture `with-0009-vendored.md` |
| Hook registration breaks existing `claude-settings.json` JSON | Apply uses idempotent JSON patch: only insert if hook-id not present. Diff preview before applying. | Migration's Step 3 idempotency check |
| User on bash 3.2 (default macOS) — modern bash regex unavailable | Script targets bash 3.2 syntax + POSIX `grep`/`sed`/`awk`. CI matrix includes macOS bash 3.2. | `run-tests.sh` runs in default `/bin/bash` |

---

## Step breakdown

### Step 1 — Add post-processor script

**File:** `templates/.claude/hooks/normalize-claude-md.sh` (new)

**Apply:**
- Create `templates/.claude/hooks/normalize-claude-md.sh` with the
  post-processor logic.
- Make executable (`chmod +x`).
- Script accepts one arg: path to CLAUDE.md (defaults to
  `./CLAUDE.md`).
- Script exit codes: 0 = success (changed or unchanged), 1 = file not
  found, 2 = malformed input (unclosed marker).

**Idempotency check:** `test -f templates/.claude/hooks/normalize-claude-md.sh && test -x templates/.claude/hooks/normalize-claude-md.sh`

**Revert:** Remove the file.

**TDD:** Step 1 is purely creating the script. Tests in Step 5 verify
its behavior. The "RED" commit for Step 1 is the test harness expecting
the file to exist (fixture setup writes a CLAUDE.md, harness invokes
`./normalize-claude-md.sh fixture.md` — the harness fails at the
"file not found" check). The GREEN commit creates the script with the
minimum logic to pass the first assertion. Subsequent assertions get
their own RED+GREEN pairs.

---

### Step 2 — Vendor the script into consumer projects on migration apply

**Apply:**
```bash
mkdir -p .claude/hooks
cp "$SCAFFOLDER_ROOT/templates/.claude/hooks/normalize-claude-md.sh" .claude/hooks/normalize-claude-md.sh
chmod +x .claude/hooks/normalize-claude-md.sh
```

**Idempotency check:** `test -x .claude/hooks/normalize-claude-md.sh`

**Revert:** `rm -f .claude/hooks/normalize-claude-md.sh`

---

### Step 3 — Register the hook in `claude-settings.json`

**File modified:** `.claude/settings.json` (consumer-project copy of
`templates/claude-settings.json`)

**Apply:** Append a PostToolUse hook block:
```json
{
  "_hook": "Normalize CLAUDE.md after Edit/Write (migration 0010)",
  "matcher": "Edit|Write|MultiEdit",
  "hooks": [
    {
      "type": "command",
      "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/normalize-claude-md.sh \"$CLAUDE_PROJECT_DIR/CLAUDE.md\"",
      "timeout": 5000
    }
  ]
}
```

The agent uses a small `jq` patch (or hand-edits the JSON depending on
whether `jq` is available — both paths documented in the migration).

**Idempotency check:** `grep -q "normalize-claude-md.sh" .claude/settings.json`

**Revert:** Remove the block. Safe because the `_hook` label is unique.

**Also update `templates/claude-settings.json`** in the scaffolder repo
so fresh installs pick up the hook automatically. This is a scaffolder-
level change (not consumer-project).

---

### Step 4 — One-shot normalization of existing CLAUDE.md

**Apply:** Detect whether `CLAUDE.md` has any `<!-- GSD:[a-z]+-start`
markers. If yes, present a diff preview, ask user to confirm
(consistent with migration 0009's UX). On confirm, run:
```bash
bash .claude/hooks/normalize-claude-md.sh CLAUDE.md
```

**Idempotency check:** `! grep -qE "<!-- GSD:[a-z]+-start" CLAUDE.md`
("applied" means no inlined marker blocks remain — either they were
removed or never existed).

**Revert:** Restore from git (`git checkout -- CLAUDE.md`). Migration
runtime captures the pre-state via `git diff > /tmp/0010-revert.patch`
before running Step 4 — revert applies the patch in reverse.

---

### Step 5 — Bump scaffolder version markers

**Files modified:**
- `skill/SKILL.md` frontmatter: `version: 1.8.0` → `version: 1.9.0`
- `CHANGELOG.md`: Add `## [1.9.0]` section documenting 0010.

**Idempotency check:** `grep -q "^version: 1.9.0" skill/SKILL.md`

**Revert:** Revert to 1.8.0.

---

## Task breakdown (for `gsd-execute-phase`)

Each task is a RED → GREEN TDD pair where applicable. `tdd="true"` tasks
require an atomic RED test commit (failing) followed by a GREEN
implementation commit. Other tasks (mechanical file creation, version
bump) are single-commit.

| # | Task | TDD | Estimated commits |
|---|---|---|---|
| T1 | Add `migrations/test-fixtures/0010/` skeleton + 5 fixtures (`fresh.md`, `inlined-7-sections.md`, `inlined-source-missing.md`, `cparx-shape.md`, `with-0009-vendored.md`) plus matching `expected/` goldens | no | 1 |
| T2 | Add `test_migration_0010()` stanza to `migrations/run-tests.sh` — assertions for fixture diff parity, idempotency double-run, ≤200L on cparx-shape | yes (RED: harness fails because script missing) | 2 |
| T3 | Create `templates/.claude/hooks/normalize-claude-md.sh` skeleton — empty pass-through that copies stdin to stdout. Confirms harness wiring works. | yes (still RED: skeleton fails diff against goldens) | 2 |
| T4 | Implement marker-block detection: line-by-line scan, capture `(slug, source_label, content_lines)` tuples | yes (RED → GREEN on `inlined-7-sections.md`) | 2 |
| T5 | Implement transformation: emit self-closing form + heading + reference link, with source-label → file-path resolution | yes (RED → GREEN on expected golden of `inlined-7-sections.md`) | 2 |
| T6 | Implement source-existence safety guard | yes (RED → GREEN on `inlined-source-missing.md`) | 2 |
| T7 | Implement special cases: `workflow` (defers to 0009 vendored file), `profile` (no source attr) | yes (RED → GREEN on fixtures containing those slugs) | 2 |
| T8 | Implement idempotency — script is no-op on already-self-closing markers | yes (RED → GREEN on `dual-state-after-gsd-tools.md`) | 2 |
| T9 | Implement no-op short-circuit: don't rewrite the file if content is unchanged (prevents PostToolUse loops) | yes (RED → GREEN: harness checks mtime/sha after no-op run) | 2 |
| T10 | Verify cparx-shape fixture drops to ≤200L after script runs | yes (RED: assertion fails because line count exceeds) — may bubble up that the projection in CONTEXT.md needs adjustment | 1 |
| T11 | Write `migrations/0010-post-process-gsd-sections.md` with frontmatter (1.8.0 → 1.9.0), 5 steps, apply/revert blocks for each | no | 1 |
| T12 | Update `templates/claude-settings.json` to include the new PostToolUse hook | no | 1 |
| T13 | Update `migrations/README.md` Migration index table — add row for 0010 | no | 1 |
| T14 | Write ADR `docs/decisions/0022-post-process-gsd-section-markers.md` capturing source identification + chosen approach + 0009/0010 boundary + Alt-2 follow-up | no | 1 |
| T15 | Bump `skill/SKILL.md` frontmatter version 1.8.0 → 1.9.0, update CHANGELOG | no | 1 |

**Total estimated commits:** ~24 (mostly TDD pairs).

---

## Goal-backward check

**Goal:** cparx CLAUDE.md drops from 647L → ≤200L after 0009 + 0010.

Working backward:

1. ≤200L on cparx is the acceptance criterion.
2. cparx-shape fixture must verify this empirically — T10.
3. T10 depends on T7 (special cases for `workflow` + `profile`) and T5
   (transformation). If T5/T7 implementations differ from the design,
   line count might come out wrong. T10 is the integration test.
4. T2 (run-tests.sh stanza) is the harness everything plugs into.
5. T1 (fixtures) is the data the harness consumes.

Critical path: T1 → T2 → T3 → T4 → T5 → T7 → T10.

T6 (source-existence safety), T8 (idempotency), T9 (no-op short-circuit)
are independent quality gates that can run in parallel with the
critical path.

T11 (migration markdown), T12 (settings update), T13 (README), T14
(ADR), T15 (version bump) are documentation / packaging tasks that can
fire after T10 passes.

---

## Risks & open issues

- **Line-count projection might miss the target.** Decision F estimated
  ~250L, target is ≤200L. If T10 fails, options are:
  (a) Tighten the reference-link form to 2 lines instead of 3
  (drop the `## Heading` line, since gsd-tools doesn't actually require
  it — verify against `extractSectionContent` at profile-output.cjs:225).
  (b) Document a stretch target and ship 0010 even if cparx ends up at
  220L — the bulk of the win is captured and remaining bloat is non-GSD.
  Decide if T10 fails; don't block 0010 on perfect 200L compliance.

- **Bash 3.2 compatibility.** macOS default `/bin/bash` is 3.2. Regex
  features differ from bash 4+. Test the script under
  `/bin/bash --norc` explicitly. Avoid `${var//pattern/repl}` features
  that vary across versions.

- **JSON-patching `claude-settings.json` without breaking existing user
  customizations.** Some users have edited `.claude/settings.json`
  manually. Step 3's apply must be a surgical insert, not a wholesale
  template overwrite. Detection bash: `grep -q "normalize-claude-md.sh"`
  before inserting. If hook exists, skip. If JSON is structurally
  invalid, abort with clear error.

- **PostToolUse on every `Edit|Write|MultiEdit` adds 5–50ms overhead.**
  Mitigation: the script's first check is "does the path end with
  `CLAUDE.md`?" — early-exit for the 99% of Edit calls that don't.
  Verify with a perf-noise fixture.

---

## Verification artifact contract

`VERIFICATION.md` will contain, at minimum:

- A pre/post line count table:
  - cparx-shape fixture: 647L → XL (target ≤200L)
  - inlined-7-sections fixture: NL → ML
- Fixture diff parity: every fixture's actual output matches its
  `expected/` golden byte-for-byte (sha256 hashes recorded).
- Idempotency proof: second invocation of script produces zero diff.
- Hook registration smoke test: synthetic project with
  `claude-settings.json`, run migration apply, assert hook block is
  present.
- 0001 + 0009 + 0010 harness run: all PASS, no regressions.

Every "must_have" in this PLAN has a 1:1 evidence entry in
VERIFICATION.md.

---

## Definition of done

- [ ] All 15 tasks complete; harness PASSES.
- [ ] cparx-shape fixture line count ≤ 200L (or stretch-target decision
      documented if not met).
- [ ] ADR 0022 committed.
- [ ] Migration 0010 + 0009 + 0001 harness runs clean (no regressions).
- [ ] Stage 1 `/review` (spec compliance) — REVIEW.md.
- [ ] Stage 2 `superpowers:requesting-code-review` (independent code
      quality) — REVIEW.md Stage 2 section.
- [ ] `/cso` audit — SECURITY.md (shell injection / arbitrary path
      writes / hook escalation paths).
- [ ] VERIFICATION.md with 1:1 evidence per must_have.
- [ ] CHANGELOG section for 1.9.0.
- [ ] Branch `feat/post-process-gsd-sections-0010` pushed; PR opened
      with VERIFICATION.md as body.
