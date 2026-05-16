# Session Handoff — 2026-05-16 (REDACTED_KEYS v0.3.2 shipped + migration 0013 planned)

## Status snapshot

- **claude-workflow PR #34** open at https://github.com/agenticapps-eu/claude-workflow/pull/34
  - 3 commits ahead of `main @ 763d041`:
    `8d76bb2` REDACTED_KEYS expansion (v0.3.1 → v0.3.2) +
    `2f24fc3` ts-react-vite re-export fix + cparx report +
    `ba5c77a` handoff snapshot
  - Migration suite `--strict-preflight` → PASS=131 FAIL=0
  - Phase-15 smoke → 9/9 pass
  - Awaiting review/merge
- **cparx adoption branch** — discarded. The 7-commit verification
  branch (last SHA `5c29da44`) was deleted per user direction
  ("Option B — discard the branch, redo manually after #34 merges").
  cparx is back on `main` with pre-existing dirty state
  (`codebase-analysis-docs/CODEBASE_KNOWLEDGE.md` mod + `workflows.png`
  untracked) restored from the stash.
- **Dev-machine state retained** (these are normal-maintenance side
  effects, no rollback needed):
  - `~/.claude/skills/agenticapps-workflow/` pulled to main HEAD `763d041`
  - `~/.claude/skills/add-observability` slash-discovery symlink in
    place (idempotent target — what migration 0012 installs anyway)

## Next session: start here

### 1. Watch PR #34 land

CodeRabbit / Autofix Bot will likely fire nit-level suggestions on the
CHANGELOG bullets or report formatting. Apply the 3-round nit-loop
ceiling carried forward from phases 17/18/19. If a finding is genuinely
load-bearing, address it; otherwise close as "out of scope for this PR".

After merge:
- Tag close + provenance comment if appropriate
- Pull `~/.claude/skills/agenticapps-workflow/` to pick up v0.3.2
- Note in CHANGELOG hygiene that `[1.11.0]` is still the active
  version absorbing follow-up entries (this PR doesn't bump scaffolder)

### 2. Build migration 0013 — close the F1 + F2-orchestration gap

The cparx verification report (PR #34's
`.planning/cparx-v1.10.0-adoption-verification/REPORT.md`) identified
two adopter-side frictions that should be fixed in claude-workflow
before fx-signal-agent (or any other project) tries to adopt:

**F1 (HIGH, from report)**: stale project-local
`.claude/skills/add-observability/` (vendored at v0.2.x via the
pre-slash-discovery setup pattern) shadows the global v0.3.1+ skill.
`claude /add-observability init` resolves to the vendored copy which
has no `init` subcommand — adopter gets "unknown subcommand" and has
to manually `rm -rf .claude/skills/add-observability/` before
proceeding. cparx hit this; fx-signal-agent will too.

**Two-update friction (raised this session)**: even after F1 is
resolved, the current chain is:

1. `claude /update-agenticapps-workflow` → migration 0011 pre-flight
   aborts with "no observability metadata; run init first"
2. `claude /add-observability init` → 9-phase scaffold
3. `claude /update-agenticapps-workflow` → resumes; applies 0011
   Steps 1-4, then 0012 Step 1-3

Two `/update-agenticapps-workflow` invocations with a separate `init`
sandwiched in. User wants this collapsed to ONE invocation.

#### Migration 0013 design — proposed shape

**from_version**: `1.11.0`
**to_version**: `1.12.0`
**slug**: `auto-init-and-stale-vendored-cleanup`

##### Step 1 — Detect & remediate stale project-local vendored skill (F1)

```bash
# Idempotency: no project-local add-observability skill present
test ! -e .claude/skills/add-observability
```

```bash
# Apply: if present, check version; warn loudly + remove
if [ -d .claude/skills/add-observability ]; then
  VENDORED_VERSION=$(awk '/^version:/{print $2; exit}' \
    .claude/skills/add-observability/SKILL.md 2>/dev/null)
  GLOBAL_VERSION=$(awk '/^version:/{print $2; exit}' \
    "$HOME/.claude/skills/agenticapps-workflow/add-observability/SKILL.md")

  echo "Migration 0013: removing stale project-local add-observability"
  echo "  Project-local: v${VENDORED_VERSION:-unknown} at .claude/skills/add-observability/"
  echo "  Global (will take over): v${GLOBAL_VERSION} at ~/.claude/skills/add-observability"
  echo ""
  echo "  Project-local copies were the install pattern pre-v1.11.0;"
  echo "  slash-discovery (migration 0012) makes the global symlink"
  echo "  canonical. Project-local copies shadow the global at"
  echo "  Claude Code's project-scope precedence, causing 'unknown"
  echo "  subcommand: init' on older vendored versions."

  # Show what's being removed for transparency
  find .claude/skills/add-observability -type f | head -10
  echo "  ... ($(find .claude/skills/add-observability -type f | wc -l) files total)"

  git rm -rf .claude/skills/add-observability
fi
```

**Hard-abort path** (vendored copy is at *current* version, not
stale): print a confused-state message and refuse. This shouldn't
happen in practice but covers the edge case where someone
hand-vendored the latest skill into a project.

##### Step 2 — Auto-init if observability metadata missing

Detect missing observability state and chain `/add-observability init`
inline rather than aborting:

```bash
# Idempotency: observability: block already in CLAUDE.md
grep -q '^observability:' CLAUDE.md
```

```bash
# Apply: if no observability metadata, run init
if ! grep -q '^observability:' CLAUDE.md; then
  echo "Migration 0013: no observability metadata detected;"
  echo "                running '/add-observability init' inline"
  echo "                to scaffold spec §10 wrapper before proceeding."
  echo ""
  echo "Init follows the 9-phase procedure with 3 consent gates"
  echo "(scaffold, entry-file rewrite, CLAUDE.md metadata)."
  echo "Decline any gate to halt the migration cleanly."

  # The consuming agent (Claude Code session running
  # /update-agenticapps-workflow) executes
  # ~/.claude/skills/agenticapps-workflow/add-observability/init/INIT.md
  # Phases 1-9. Decline paths from init exit the migration with the
  # same rollback hints as a direct init invocation.

  # Post-init: re-check that observability block was written
  grep -q '^observability:' CLAUDE.md || {
    echo "ABORT: init completed but observability: block not in CLAUDE.md."
    echo "       Migration 0013 cannot continue. Inspect CLAUDE.md."
    exit 3
  }
fi
```

This step is a no-op for projects that already ran init manually
(idempotency check passes immediately).

##### Step 3 — Bump scaffolder version

```bash
sed -i.bak 's/^version: 1\.11\.0$/version: 1.12.0/' \
  .claude/skills/agentic-apps-workflow/SKILL.md
rm .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

##### Pre-flight

```bash
# 1. Project at v1.11.0 (or v1.12.0 for re-apply)
grep -qE '^version: 1\.(11\.0|12\.0)$' \
  .claude/skills/agentic-apps-workflow/SKILL.md
```

##### Test fixtures (5 scenarios)

`migrations/test-fixtures/0013/`:

- `01-fresh-apply-no-vendored-no-init/`: project at v1.11.0, no
  vendored skill, no observability metadata. Migration runs init
  inline, materialises wrapper, bumps version. End state: fully
  initialised v1.12.0.
- `02-fresh-apply-stale-vendored-no-init/`: project has v0.2.1
  vendored skill + no observability metadata. Migration removes
  vendored, runs init, bumps version.
- `03-fresh-apply-no-vendored-with-init/`: init already done.
  Migration skips Step 2 idempotently; bumps version.
- `04-current-vendored-refuses/`: project has *current* version
  vendored locally. Migration refuses with confused-state message.
- `05-idempotent-reapply/`: project already at v1.12.0. All steps
  no-op.

##### Migration 0011 retroactive update (within 0013's PR)

Update migration 0011's pre-flight to reflect that 0013 handles the
missing-init case for v1.11.0+ projects:

```bash
# 1. Project HAS run /add-observability init (so observability: metadata block exists)
grep -q '^observability:' CLAUDE.md || {
  echo "ABORT: CLAUDE.md has no observability: metadata block."
  echo "Run 'claude /add-observability init' first to scaffold observability,"
  echo "then re-run /update-agenticapps-workflow."
  echo ""
  echo "(NOTE: projects on workflow v1.11.0+ can use migration 0013's"
  echo " auto-init instead — upgrade via /update-agenticapps-workflow"
  echo " when you reach v1.12.0+.)"
  exit 3
}
```

##### Open design questions for migration 0013

- **Where does init's interactive consent surface?** Inside
  `/update-agenticapps-workflow`'s flow, or does 0013 print "Run
  /add-observability init manually then re-run update" if it can't
  prompt? The migration framework currently doesn't have a model for
  "ask the user mid-migration"; this needs design discussion. Cleanest
  fallback: 0013 detects missing metadata, prints a clear "Run
  /add-observability init now, then re-run /update-agenticapps-workflow"
  hint, and exits 3. That preserves the two-update flow for projects
  on the v1.11.0 → v1.12.0 path but avoids it FROM v1.12.0 ONWARD.
- **OR** — write 0013 such that the "auto-init" step is documented as
  a procedural instruction to the consuming LLM agent (per the
  existing migration pattern where Step 1 of 0011 says "the consuming
  agent follows the scan procedure in SCAN.md"). The LLM agent
  running `/update-agenticapps-workflow` reads "run init" and does so
  in-session. This matches how 0011 Step 1 chains into SCAN.md.
- **Tradeoff**: pure-shell auto-init isn't possible (init needs 3
  consent gates). LLM-driven auto-init works but ties update behavior
  to LLM-session execution. Documenting it as "consuming agent runs
  init" is honest about the constraint.

### 3. After 0013 ships → run on cparx

With v1.12.0 of the workflow installed globally:

```bash
cd ~/Sourcecode/factiv/cparx
# Stash unrelated WIP first if dirty
claude /update-agenticapps-workflow
# Migration 0011 may still trigger the two-step flow if cparx is at
# v1.9.3 (since 0013 only helps from v1.11.0 onward). For cparx
# specifically, this is:
#   0011 abort → /add-observability init → 0011 resume → 0012 → 0013
# Four migrations, one init, but two /update invocations.

# After cparx reaches v1.12.0:
claude /add-observability scan --update-baseline
claude /add-observability scan-apply --confidence high
```

OR alternatively for cparx (since the verification proved the path),
hand-execute the same sequence the discarded branch had:

1. Manually remove `.claude/skills/add-observability/` (0013 would
   automate this from v1.11.0+ but cparx is at v1.9.3 still)
2. `claude /add-observability init` (Phases 1-9; templates now
   correct per F2 fix in PR #34)
3. `claude /update-agenticapps-workflow` (applies 0011 + 0012 + 0013
   in one go)
4. `claude /add-observability scan --update-baseline`
5. `claude /add-observability scan-apply --confidence high` (this
   step was NOT in the discarded branch — it's the actual gap
   remediation, ~14 high-confidence fixes across cparx app code)

Each step commits atomically per the cparx report's pattern.

### 4. After cparx adoption succeeds → fx-signal-agent

Same flow. Should be cleaner because:
- v0.3.2 ships F2 fix (no manual `index.ts` patch needed)
- v1.12.0 ships 0013 (no manual vendored-skill removal needed,
  IF fx-signal-agent has already reached v1.11.0)

Check fx-signal-agent's workflow version first:

```bash
grep '^version:' ~/Sourcecode/agenticapps/fx-signal-agent/.claude/skills/agentic-apps-workflow/SKILL.md
```

If at v1.9.x → same two-update path as cparx today.
If at v1.11.0+ → 0013 handles it cleanly.

## Plausible follow-ups (after 0013 lands)

- **F3 from cparx report**: go-fly-http multi-binary entry detection.
  Post-candidate-selection HTTP-shape verification. Scaffolder
  v0.3.4 or v0.4.0 of the skill. Low severity.
- **test_init_fixtures() harness**: long-deferred (Phase 15 F4); F2
  evidence makes the case stronger. Would catch template-vs-fixture
  drift like F2 automatically. Worth a dedicated phase for v1.13.0.
- **`policy:` multi-stack support**: cparx-style dual-stack repos
  ship only the primary stack's path in CLAUDE.md (per spec §10.8
  scalar `policy:`). Future spec amendment + matching parser change
  could add `policies: [path1, path2]` array form. Out of scope for
  0013.
- **Drain CHANGELOG hygiene** if `[1.11.0]` accumulates many more
  entries — at some point bump scaffolder to v1.12.0 and date-stamp
  `[1.11.0]` as released.

## Open questions (carried forward)

- **Authoritative baseline.json for cparx**: hand-authored counts on
  the discarded branch were conservative. Real adoption (post-#34
  merge) should run `claude /add-observability scan --update-baseline`
  for authoritative numbers, not reuse the hand-authored shape.
- **`enforcement.ci:` field**: still omitted by default. v1.10.0
  Option-4 stance carried forward. The opt-in CI workflow remains
  copy-paste from `add-observability/enforcement/observability.yml.example`.
- **CI workflow wiring for `--strict-preflight`**: flag exists; no
  GHA workflow uses it yet. Could land alongside 0013 if you want
  to gate the migration framework on strict-preflight.
- **Carried from prior sessions**: Residual #32 formal §1-§8
  conformance audit doc; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`; fx-signal-agent v1.10.0 adoption verification.
