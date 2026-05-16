# Session Handoff — 2026-05-16 (Residual #31 + polish backlog drained)

On branch `chore/issue-31-implements-spec-and-polish`, 3 atomic commits
ahead of `main @ 5b75fc7`. Working tree clean except for this handoff
file. Migration suite still **PASS=131 FAIL=0** in both loose and
strict modes — the polish pass did not move any test-relevant code.
PR pending push + open.

## Accomplished

Drained residual #31 + the in-repo half of the polish backlog from the
prior handoff. All three changes are declarative-doc-only — no code
path moved, no migration, no scaffolder version bump.

### Residual #31 — `implements_spec: 0.3.0` on `skill/SKILL.md` (`f916b09`)

- One-line YAML frontmatter addition after `version:`, mirroring the
  same field on `add-observability/SKILL.md`.
- Makes the spec-conformance assertion machine-verifiable on the
  canonical scaffolder skill itself (not only on the observability
  sub-skill). `agenticapps-workflow-core/reference-implementations/README.md`
  already declares this repo at `0.3.0 / full` (workflow-core PR #6,
  merged 2026-05-16); this lets drift-detection tooling find that
  assertion locally without leaving the repo.
- Per #31's "out of scope if treated as scaffolder-only" option: no
  migration. Installed projects' `.claude/skills/agentic-apps-workflow/SKILL.md`
  is unaffected at v1.11.0 — future migration that touches SKILL.md
  can pick it up.
- CHANGELOG entry under `[1.11.0]` `### Added`.

### Anchor-comment threat-model paragraph in INIT.md (`add2c62`)

- Closes the Phase 15 /cso S2 recommendation (REVIEW.md lines 253-256).
  Adds one bullet under "Important rules" capturing the threat model:
  anchor pair is structurally fail-safe (denial-of-init, not silent
  conformance bypass).
- Locks the fail-safe stance against future "improve UX of re-init"
  refactor pressure: Phase 2 strict-first-run + Phase 6 POLICY_PATH
  self-check MUST be preserved.
- Cross-references the full S2 threat assessment so maintainers can
  jump to the analysis without re-deriving it.
- CHANGELOG entry under `[1.11.0]` `### Added`.

### CHANGELOG date-stamp hygiene (`e0d30a0`)

- Stamped `[1.5.0]`, `[1.6.0]`, `[1.8.0]`, `[1.9.0]`, `[1.9.1]`,
  `[1.9.2]`, `[1.9.3]` as released on 2026-05-13. Dates pulled from
  git log of the version-defining commits.
- `[1.7.0]` and `[1.5.1]` retain `"Skipped (no migration)"` — correct,
  no version-bump occurred for those slots.
- `[1.10.0]` and `[1.11.0]` retain `"Unreleased"` per handoff scope —
  `[1.11.0]` is still absorbing follow-up entries (this PR adds two
  more to it).

## Decisions

- **Bundle three changes into one PR, three atomic commits** — each
  commit is independently revertable; the PR is a single coherent
  "polish pass" rather than three sub-1-line PRs that would clutter
  history. Matches the cluster-of-small-changes pattern from phases
  17/18/19.
- **No migration for #31** — explicit per #31's acceptance criteria
  ("Out of scope if treated as a scaffolder-only declarative-doc
  change"). The field is declarative-only at v1.11.0; nothing parses
  it yet.
- **CHANGELOG bullet order** — new bullets placed at the TOP of the
  `[1.11.0] ### Added` block (newest first), pushing the existing
  `--strict-preflight` entry down by two. Consistent with prior
  newest-first ordering inside each version's section.
- **Skip `[1.10.0]`/`[1.11.0]` date-stamping** — explicit per prior
  session-handoff: hygiene was scoped to `[1.9.3]` and earlier.
  `[1.11.0]` is the active version absorbing new work.
- **Adversarial review skipped on /review** — 24-line docs-only diff
  has no executable code path, no state mutation, no LLM/SQL/auth
  trust boundary. Category checklist (concurrency, injection, enum
  completeness) does not apply. PR Quality Score 10/10.

## Files modified

Commits on the feature branch (in landing order):

- `f916b09` — `skill/SKILL.md` (+1 line), `CHANGELOG.md` (+1 bullet).
- `add2c62` — `add-observability/init/INIT.md` (+14 lines under
  "Important rules"), `CHANGELOG.md` (+1 bullet).
- `e0d30a0` — `CHANGELOG.md` (7 date-stamp swaps; `Unreleased` →
  `2026-05-13` for the 1.5.0/1.6.0/1.8.0/1.9.x sections).

Plus the next commit on this branch: `session-handoff.md` refresh.

`.planning/current-phase` unchanged (still phase 19; this work is
out-of-phase polish).

## Verification

- `bash migrations/run-tests.sh | tail -3` → **PASS: 131**, no FAIL
  line. (no code path moved, sanity check only.)
- `bash .planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh
  | grep -E '(Passed|Failed):'` → **Passed: 9 / Failed: 0**.
- `grep -n "^implements_spec:" skill/SKILL.md` → `4:implements_spec: 0.3.0`.
- `grep -c "^## \[" CHANGELOG.md` → 14 section headers (unchanged).
- `grep "Unreleased" CHANGELOG.md | wc -l` → 2 (`[1.11.0]` + `[1.10.0]`,
  both intentional).
- `/review main..HEAD` → 0 findings, PR Quality Score 10/10.

## Next session: start here

1. **Push branch + open PR**: `git push -u origin chore/issue-31-implements-spec-and-polish`
   then `gh pr create` against `main`. PR body: link #31 as the
   tracking issue, name the three commits, note that no code path
   moved (so smoke + migration suite are unchanged).
2. **Watch for CodeRabbit nits** — small PR but CodeRabbit might flag
   the CHANGELOG bullet style; apply 3-round nit-loop ceiling
   inherited from phases 17/18/19.
3. **After merge**: close #31 with provenance comment pointing at the
   PR; refresh handoff; choose next direction.

Plausible follow-ups after this lands:

- **REDACTED_KEYS default expansion** — Phase 15 /cso S1 (defer to a
  v0.3.2 minor of `add-observability`). Genuinely belongs in a
  feature phase, not polish.
- **fx-signal-agent v1.10.0 adoption verification** — cross-repo task.
- **Open the next feature phase** — no specific candidate teed up.
- **CI workflow wiring for `--strict-preflight`** — flag exists; no
  GHA workflow yet uses it.

## Open questions (carried forward, mostly unchanged)

- **Residual #32** — formal §1-§8 conformance audit doc (optional;
  codex-workflow precedent says implicit conformance is acceptable).
- **Init harness expansion** — Phase 15 VERIFICATION F4 flagged the
  7 init fixture pairs as reference-only at v1.11.0. A future phase
  could add `test_init_fixtures()` to `run-tests.sh`.
- **Cross-tree `applies_to` framework hardening** — migration 0012's
  `~/.claude/skills/...` reference flagged as a new precedent worth a
  framework-level `host_paths:` allowlist.
- **REDACTED_KEYS default expansion** — defer to a v0.3.2 minor of
  `add-observability`.
- **CI workflow wiring for `--strict-preflight`** — the flag is now
  available, but no GitHub Actions workflow yet runs it.
- **Hermetic-sandbox pattern reuse** — if future migration tests grow
  shell-execution fixtures, carry the `env -i HOME=…
  PATH=…/bin:/usr/bin:/bin` pattern forward by default.
- **Carried from prior sessions** (unchanged): fx-signal-agent v1.10.0
  adoption verification; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`.
