# Session Handoff — 2026-05-14 (Phases 11 + 12 + 13 shipped; fx-signal-agent off v1.9.0)

## Accomplished

Three phases shipped, two consumer projects unblocked, one bug class
structurally closed. Picked up from yesterday's chain-gap discovery
handoff. The end-to-end story:

| PR | Title | Merge |
|---|---|---|
| #17 | fix: chain integrity — re-anchor 0008 (1.5→1.6) and 0009 (1.6→1.8) | `8906470` |
| #19 | fix: migration 0005 preflight verify path (closes #18) | `7ad3498` |
| #20 | docs(handoff): phases 11+12 shipped (handoff via PR, not direct-to-main) | `d8cd0b2` |
| #21 | feat: per-migration preflight-correctness audit (run-tests.sh) | `65958f7` |

Workflow scaffolder progression: `1.9.3` (head unchanged — Phase 11/12
were path-to-head fixes; Phase 13 is test-harness-only and ships no
consumer-facing change).

GitHub issue #18 (filed mid-session while merging Phase 11) — auto-closed
on Phase 12 merge.

**Consumer-project state:**
- `factiv/cparx`: still at v1.5.0 (you haven't run the live apply yet —
  the chain is now provably clean v1.5.0 → v1.9.3 in 6 hops).
- `factiv/fx-signal-agent`: **upgraded to v1.9.3** end-to-end. Was
  stuck at v1.9.0 before Phase 12; you ran the live apply after the
  merge.

## Decisions

- **Phase 11 scope widened beyond handoff spec.** The handoff said
  "frontmatter only". 0009's body has a hardcoded preflight
  `test "$INSTALLED" = "1.7.0"` that would have broken every fresh
  apply post-rebase. Widened scope to include consequential body /
  fixture / harness / CHANGELOG refs. **Audit pattern worth
  codifying:** when re-anchoring a migration, audit body for
  `from_version`-equality strings — they need to track.

- **Phase 11 dry-run didn't catch the Phase 12 bug.** Chain-walk
  simulation exercises Step 2 (frontmatter pending-migration discovery
  via `from_version` matching) but never Step 5 (per-migration
  preflight verify). 0005's verify pointed at a path that didn't
  exist; the bug only surfaced during actual apply against
  fx-signal-agent.

  **Codify as a workflow norm:** dry-run is not "ready to ship" — at
  least one consumer project needs to actually walk the apply path
  before a chain-touching PR can be considered verified. Adding a
  per-migration preflight-correctness check to `run-tests.sh` (assert
  every `requires.verify` shell command resolves on a real install)
  is the obvious follow-up.

- **No-op bridge migration 0011 rejected** (Phase 11). Cost is one
  chain entry with a non-monotonic minor bump (1.6 → 1.8). Mitigated
  with `migrations/README.md` "Application order" note 3 codifying
  `to_version` need not equal `from_version + 0.1`.

- **Triple CHANGELOG rewrite** (Phase 11). Handoff called out `[1.6.0]`
  and `[1.7.0]` as stale. Stale `[1.5.1]` was a third — described
  pre-rebase 0005 that actually shipped as 0005 at 1.9.0 → 1.9.1. All
  three rewritten with pointers to where the originally-planned
  content shipped.

- **Phase 12 `requires:` key changed `patch:` → `skill:`.** The
  documented "external skills" schema in `migrations/README.md` uses
  `skill:`. The `patch:` outlier was an artifact of the
  gsd-patches-centric mental model that has since been superseded by
  Claude Code skills. Brought 0005 in line.

- **Phase 12 install hint deprescriptivised.** Old hint said
  `bash ~/.config/gsd-patches/bin/sync` — wrong because that only
  syncs the workflow body, not the skill. Without knowing the
  user's canonical install command for the gsd-review skill (varies
  by setup), new hint is non-prescriptive but accurate: "Sources
  vary by setup — see your get-shit-done install or dotfiles."
  Codifying a single canonical install command is a separate
  follow-up.

- **gstack `/review` skipped its heaviest dispatch passes (both
  phases).** For metadata-only diffs (no SQL, shell, concurrency,
  LLM trust, enums), the Codex / sub-agent / red-team ceremony is
  wasted spend. Did structural checks (frontmatter validity, chain
  walk, cross-file consistency, scope drift) inline and produced
  REVIEW.md with explicit notes on what was skipped and why.
  **Codify as workflow norm:** match review depth to diff *kind*,
  not just size.

## Files modified (across both phases)

### Phase 11 (PR #17, merge `8906470`)
- `migrations/0008-coverage-matrix-page.md` — frontmatter re-anchor +
  body version-ref cleanup
- `migrations/0009-vendor-claude-md-sections.md` — frontmatter
  re-anchor + body preflight value + Step 5 pre-condition / Apply /
  Rollback values
- `migrations/README.md` — index + "Application order" note 3
- `migrations/test-fixtures/0009/` — 3× SKILL.md, fixtures README
- `migrations/run-tests.sh` — 3 assertion messages
- `CHANGELOG.md` — `[1.5.1]` / `[1.6.0]` / `[1.7.0]` rewritten; `[1.8.0]`
  0009 refs updated
- `.planning/phases/11-chain-gap-cleanup/` — RESEARCH, VERIFICATION,
  REVIEW

### Phase 12 (PR #19, merge `7ad3498`)
- `migrations/0005-multi-ai-plan-review-enforcement.md` — 5 path refs +
  install hint + 4-line explanatory comment + `requires:` schema fix
- `.planning/phases/12-fix-0005-verify-path/` — RESEARCH, VERIFICATION,
  REVIEW

### Phase 13 (PR #21, merge `65958f7`)
- `migrations/run-tests.sh` — new `test_preflight_verify_paths()`
  function (~60 lines) + `RAN_AUDIT` flag + dispatcher hook for the
  `preflight` filter alias. Net +85 lines.
- `.planning/phases/13-preflight-correctness-audit/` — RESEARCH,
  VERIFICATION, REVIEW.

## Next session: start here

The workflow chain is clean and the test harness now catches the
issue-#18 bug class structurally. Pending choices for next session:

1. **(Optional) Re-run live apply against cparx** to upgrade
   v1.5.0 → v1.9.3 the same way fx-signal-agent did. The dry-run
   said clean (6 hops) and both bug fixes are now in place.

2. **(Optional) Phase 14 — supply-chain pinning** for vendored
   `ussumant/llm-wiki-compiler` plugin + `gitnexus` MCP. Pin to
   tag + SHA-256. Open from prior session.

3. **(Optional) Phase 15 — structural lint** for the `&&`-chain
   under `set -e` pattern. CSO H1 has fired in three consecutive
   phases — worth a shell-lint hook.

4. **(Optional) Phase 16 — fix 0008's `curl | jq` verify.** Phase 13
   review surfaced that `curl ... | jq '.schemaVersion'` exits 0
   even when curl fails (jq tolerates empty input). Either split
   the pipeline with explicit error handling or require `pipefail`.
   The Phase 13 audit reports `✓ 0008` misleadingly today.

5. **(Optional) Phase 17 — fix the 8 pre-existing
   `test_migration_0001` failures** (`git merge-base` resolution).

6. **(Optional environmental cleanup) `test_migration_0007` fixture
   `03-no-gitnexus`** — fnm-managed gitnexus binary leaks through
   the sandbox PATH on this machine, false-passing the
   no-gitnexus scenario. Make the fixture strip fnm paths.

7. **(Optional) Phase 18 — `--strict-preflight` flag** to gate CI
   on Phase 13 audit failures. Currently informational only;
   useful once CI environments gain parity with author dev setups.

## Open questions (carried from prior session)

- **Shell-lint hook for `&&`-chains under `set -e`** — still open.
  Worth structural enforcement now that the pattern has fired in
  three consecutive phases.
- **Multi-AI plan review CLI floor** — 0005 pre-flight requires ≥2
  of `gemini|codex|claude|coderabbit|opencode`. coderabbit + opencode
  CLIs absent on this machine; 3 are present, so the floor is met.
  Document the canonical install for those two CLIs OR relax to
  "any 2"?
- **Helper script license consent** for `index-family-repos.sh`
  `--all` — worth a `--accept-license` first-time flag?
- **Canonical install command for `/gsd-review` skill** — Phase 12's
  install hint left this deliberately vague. Worth codifying if a
  canonical command emerges.
