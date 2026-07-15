# Changelog

All notable changes to the AgenticApps Claude Workflow scaffolder are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/),
and the project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]


**No version bump.** Neither change touches a migration's `to_version`: 0028 is
corrected in place (it is applied in zero downstream repos), and the §11 work is
this repo's own conformance rather than a change to what it scaffolds. Nothing
for downstream projects to re-run.

### Fixed
- **Migration 0028 appended a redundant entry under a subsuming `.claude`.**
  Step 1's idempotency check grepped `^\.claude/hooks/?$`, so a project already
  ignoring the whole `.claude` directory did not match and got `.claude/hooks/`
  appended beneath it — four lines of noise in a project file for no formatting
  effect, since a bare `.claude` already covers everything below it. The check
  and the apply condition now treat the subsuming forms (`.claude`, `.claude/`,
  `.claude/**`) as already-covered alongside the exact ones.

  Found by surveying the six downstream repos before a 2.5.0 → 2.6.0 sweep:
  `factiv/fbc-platform` ships exactly this shape, and is the only repo where
  0028's Step 1 would have done anything at all. Four of the six have no
  `.prettierignore` (permanent skip) and `callbot` already carries the exact
  entry from a hand-fix, so for them 0028 is a version stamp and nothing more.

- **The setup flow kept the old predicate (spec §08).** §08 requires setup to
  reach an end state equivalent to a full `0000`→latest replay. The widened
  predicate landed in migration 0028 but not in `setup/SKILL.md`, so on a
  project with a subsuming `.claude` (the `fbc-platform` shape) a **fresh
  install appended while an update skipped** — different end states from the
  same starting point. `check-snapshot-parity.sh` cannot catch this:
  `.prettierignore` is a project file, not snapshot payload, so the named §08
  guard has nothing to say about it. `run-tests.sh` now asserts the predicate
  directly — it collects every copy across the migration and `setup/SKILL.md`
  and requires exactly one distinct value.
- **This host did not reproduce the spec §11 canonical block (conformance gap).**
  §11 MUSTs the Coding Discipline block in the host's *primary
  project-instruction file*. `codex-workflow` and `opencode-workflow` both carry
  it in their `AGENTS.md`. This host — the source of canonical prose, claiming
  `full` — carried it nowhere, and declared no §11 delta. It ships the block to
  every project it scaffolds (migration 0014) and never reproduced it for itself.

  Nothing noticed for the life of the repo: core's `drift-report.sh` grepped the
  whole clone and kept finding the block in `templates/`, `setup/` and
  `migrations/0014` — payload shipped *into* other projects, which instructs
  nobody here. Surfaced by agenticapps-workflow-core#22, which scopes the check
  to declared instruction files.

  `CLAUDE.md` now carries the block verbatim, above the `<!-- gitnexus:start -->`
  region. Guarded by `test_claude_md_reproduces_spec_11_verbatim`, which diffs it
  against `templates/spec-mirrors/` (itself byte-identical to the spec).

### Changed
- **0028's fixtures now run the migration's own shell.** `verify.sh` in fixtures
  01-03 inlined a *copy* of Step 1's Apply block, so they tested the copy rather
  than the migration — a predicate fix could land in the document while every
  fixture went on exercising the old logic and passing. A shared
  `common-verify.sh` extracts Step 1's Apply block from the document and all
  four fixtures run that. Verified by mutation: reverting the document's
  predicate alone now fails fixture 04.

  The extractor is hardened against grabbing the wrong block: it accepts any
  fence language and cannot latch past the Apply block onto the Rollback (which
  would have turned `apply_step1` into a destructive `sed … /d`), and a sentinel
  asserts the extracted block actually appends to `.prettierignore`. Emptiness
  is not correctness.
- **`CLAUDE.md` is now tracked** (removed from `.gitignore`; `AGENTS.md` stays
  ignored). It was ignored as a "fully regenerable" GitNexus artifact, which left
  this host with **no tracked project-instruction file at all** — so §11's block
  had nowhere to live that would survive a clone. It is now part-authored and
  must be tracked.

  Placement is load-bearing: `gitnexus analyze` rewrites only between its own
  markers, so the block sits above them (verified — an `analyze` updated the
  stat line inside the region and left the block untouched). This is also the
  earliest point in the file, per §11's placement SHOULD. Note migration 0014
  injects §11 *before the first `## ` heading*, which for a GitNexus-managed
  CLAUDE.md would land **inside** the regenerated region — fixed forward by
  migration 0029 (2.7.0, below).

  Cost: an `analyze` that changes the graph rewrites the stat line inside the
  GitNexus region, producing a diff in a tracked file. That is the price of
  having a project-instruction file at all.


## [2.8.0] — 2026-07-15 — Re-sync stale spec §11 mirror bytes

### Fixed
- **Migration 0030 — two already-migrated projects carried a stale §11
  block, and no version bump caught it.** Nobody mis-transcribed anything:
  core introduced spec §11 without the blank lines around its anti-pattern
  lists (`5ea7ea9`, 2026-05-20); this repo mirrored it faithfully
  (`913360e`/#42, byte-identical to core at that moment) and shipped it as
  migration 0014; `cparx` and `fx-signal-agent` ran 0014 that same day and
  received it as it then read. Four days later core revised §11's prose *in
  place* — adding the four blank lines (`10f2c96`/#12, titled "blank lines
  around §11 anti-pattern lists (markdown/prettier-clean)") — **without
  bumping `spec_version`** (0.4.0 before and after). This repo mirrored that
  edit (`34ee72e`/#44, four insertions) but shipped no re-sync migration, so
  the two already-migrated projects were stranded on the old bytes.

  `callbot` also ran 0014 against the stale mirror (`4fa4dac`, 05-25 20:31 —
  twenty minutes *before* `34ee72e` at 20:51) and received the identical stale
  block. It self-healed four minutes later, when its own `format:check` ran
  prettier over `CLAUDE.md` (`1149187`, 20:35), independently landing on the
  bytes core would ship. Only `cparx` and `fx-signal-agent` need 0030.

  That is the mechanism in one line: prettier's "blank lines around lists"
  rule added the four lines at every site it ran — core's spec, callbot's
  `CLAUDE.md`, and this repo's mirror. Prettier never stripped anything from
  anyone. `cparx` and `fx-signal-agent` are stale for exactly one reason:
  nothing runs prettier over *their* `CLAUDE.md`.

  Provenance `@0.4.0` is a genuinely correct stamp on both sides of this
  change, because upstream never moved `spec_version` — a check keyed on the
  provenance version cannot tell the two states apart even in principle. 0030
  derives idempotency from the block's actual bytes instead: it extracts the
  managed region from `CLAUDE.md` and compares it to the vendored mirror,
  byte for byte, replacing only on mismatch. `implements_spec` stays `0.9.0`;
  no `0.4.1` is invented, since core never shipped one. See the "Root cause"
  section of `migrations/0030-resync-spec-11-mirror-bytes.md` for the full
  commit-by-commit account.

  A new CI guard, `test_mirror_matches_core_spec_11`, binds this repo's
  mirror to workflow-core's spec §11 at `ref: main` — unpinned — and `ci.yml`
  now also runs on a daily `schedule:` (an upstream commit to core cannot
  trigger this repo's workflow by itself, so the timer is what actually
  observes drift), so the next such in-place upstream revision turns this
  repo's suite red within a day instead of drifting silently for weeks.

## [2.7.0] — 2026-07-15 — Region-aware §11 placement

### Fixed
- **Migration 0029 — §11 could be injected inside a GitNexus-managed region.**
  0014 anchors the block before the first `## ` heading; in a `CLAUDE.md` that
  leads with the GitNexus block that heading is inside
  `<!-- gitnexus:start -->…<!-- gitnexus:end -->`, so a later `gitnexus analyze`
  destroyed the block silently. Recovery was closed — 0014's `to_version`
  (1.14.0) makes it permanently not-pending for 2.x repos, and its pre-flight
  refuses the `--migration` force path. 0029 fixes forward: anchor before the
  first `## ` heading **or** an anchored `<!-- gitnexus:start -->` line,
  whichever comes first. An unanchored marker regex would substring-match
  prose *mentioning* the marker — this repo's own `CLAUDE.md` line 2 does, and
  an unanchored anchor would have injected the block inside that guard
  comment. The alternation also had to widen every terminator (the strip pass
  and Rollback), not just the insert point — see ADR-0041. Heals four states
  (no-op / move-out-of-region / inject / refuse-hand-pasted-heading), covered
  by ten fixtures. Retires the Known issue recorded under Unreleased.
- **`agenticapps-dashboard` carried no §11 block while stamping
  `implements_spec: 0.9.0`.** Snapshot-installed at 2.3.0, before the setup
  flow's §11 step existed (#84, 2.5.0), with 0014 already past — so neither
  install path ever gave it the block. 0029 repairs it (`/update` chains 0028
  then 0029).
- **`setup/SKILL.md` step e2 carried the same naive anchor.** Mirrored to the
  region-aware rule and locked by a new `anchor-parity` guard (spec §08: setup
  end-state ≡ full replay), modelled on #87's predicate-parity guard.


## [2.6.0] — 2026-07-15 — Register .claude/hooks in .prettierignore

### Fixed
- **Migration 0028 — vendored hook fails host `prettier --check`.** The GitNexus
  reindex hook (`.claude/hooks/gitnexus-reindex.cjs`, migration 0026) is a
  CommonJS Node hook. Repos whose formatter runs over `.claude/` (a
  `prettier --check .` in CI) fail on its formatting, and Prettier has no
  whole-file ignore comment. Migration 0028 (and the setup flow) append
  `.claude/hooks/` to an **existing** `.prettierignore` — never creating one.
  The ESLint counterpart (`@typescript-eslint/no-require-imports`) was already
  handled at the source by the hook's file-level `eslint-disable` header
  (2.5.x). Surfaced during the 2.5.0 downstream rollout (callbot).

## [2.5.0] — 2026-07-14 — Honest spec 0.9.0 conformance claim

The conformance **claim** was incoherent, not the implementation.
`skill/SKILL.md` said `implements_spec: 0.4.0` while the repo shipped §14
(a 0.6.0 section) and §15 (a 0.7.0 section) wiring; core's ledger row said
`0.3.0`; and no "Spec deltas" section existed anywhere, which spec §09 requires
for any unsatisfied requirement — so neither `full` nor `partial` was honestly
claimable. This release raises the claim to **0.9.0**, brings the §04 red-flag
block in line with the composition rules core 0.8.0 introduced, and makes the
claim true. Core's spec 0.9.0 (upstream commit `9e19eb7`, ADR-0018) also
amends §08 so that a guarded snapshot install — this host's setup strategy
since ADR-0036 — is a named-conformant alternative to replay, resolving what
was drafted as an open §08 delta into a satisfied MUST. See ADR-0040.

### Fixed

- **§11's canonical "Coding Discipline" block never reached fresh installs —
  the only user-visible defect fixed in this release, and why it is a minor
  (not patch) bump.** `/setup-agenticapps-workflow` (the snapshot path,
  ADR-0036 — no migration replay) laid down the scaffolder skill, hooks, and
  config, but never injected the canonical `## Coding Discipline
  (NON-NEGOTIABLE)` block §11 requires verbatim in the project's primary
  instruction file — only the *update* path (migration `0014`) did.
  `setup/snapshot/MANIFEST.md` asserted the snapshot produces the same files a
  full replay would; on this one file, it didn't. `setup/SKILL.md` now injects
  the block from `setup/snapshot/spec-mirrors/11-coding-discipline-0.4.0.md`
  behind a `<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`
  provenance comment — refusing to overwrite a hand-pasted block rather than
  clobbering it — and `migrations/check-snapshot-parity.sh` asserts both that
  the mirror stays byte-identical to its `templates/` source and that setup
  actually wires the injection.
- **`design-critique` fired on the wrong condition — inverted vs spec §02.**
  `templates/config-hooks.json` gated it on `ui_hint_yes &&
  design_shotgun_completed`, but `design-shotgun`'s own trigger is
  `no_ui_spec_yet` — the two conditions are mutually exclusive, so critique
  could never fire once a UI-SPEC.md exists, exactly when §02 requires it to.
  Corrected to `ui_hint_yes && ui_spec_exists`. Fresh installs get the fix via
  the snapshot; `migrations/0027-spec-0.9.0-conformance.md` Step 4 now also
  rewrites an existing install's `.planning/config.json`
  (`hooks.pre_phase.design_critique.trigger`) when it still carries the
  inverted literal — surgically (no other hooks key is touched) and
  idempotently. `migrations/check-snapshot-parity.sh` asserts the corrected
  trigger on the snapshot side.
- **§04 red flags violated the 0.8.0 composition rule.** Core spec 0.8.0
  resolved a contradiction in §04 (it had required verbatim reproduction *and*
  permitted host additions — unsatisfiable together) by scoping what "verbatim"
  binds: host-specific flags MUST be appended **after** the canonical 13
  (position 14+), which keep positions **1–13** with the listed wording.
  Core's changelog names this host's violation: `skill/SKILL.md` carried
  ``/gsd-review` skipped — no `{phase}-REVIEWS.md` artifact`` at position **8**,
  renumbering canonical 8–13 into 9–14. It now sits at **14**. Core calls this
  "a reordering, not a rewrite" — the 13 canonical flags were already
  byte-identical here, so **no flag's wording changed**. The heading stays
  `## 14 Red Flags — STOP → DELETE → RESTART` (0.8.0 makes the leading count
  non-normative). Byte-identity of the canonical 13 against
  `spec/04-red-flags.md` is verified.
- **`observability-postphase-scan.sh` was a dead hook — removed from this
  repo's payload.** It shipped to `.claude/hooks/` on **both** install paths but
  was registered in **no** `settings.json` event, so it never fired as a
  lifecycle hook; it existed only as `programmatic_hook` metadata in
  `.planning/config.json`, whose own `_note` says orchestrator code does not
  read it. Migration `0018` here is a tombstone — the file and its real
  migration live in `agenticapps-observability`, which has owned this surface
  since 2.0.0, and `docs/UPGRADING.md` already states this repo ships no
  observability scaffolding. Because it was registered nowhere, removing it
  changes **no runtime behavior**. The advisory post-phase scan is unaffected:
  CLAUDE.md now invokes `/observability scan --since-commit` — the obs skill
  directly — instead of a file this repo no longer ships. This also un-breaks
  2.4.0's new dead-hook check, which failed (exit 1) on every fresh install.
- **`bin/build-snapshot.sh` never pruned deletions.** `hooks/`, `scripts/`, and
  `spec-mirrors/` are assembled purely by `cp` globs, so the build only ever
  ADDED: a file deleted from `templates/` lingered in the committed snapshot
  forever, `--check` reported DRIFT, and a plain rebuild could never converge.
  The three wholly-generated dirs are now pruned before repopulating. Found by
  removing the dead hook above.
- **Dangling `docs/workflow/ENFORCEMENT-PLAN.md` pointer** corrected to
  `docs/ENFORCEMENT-PLAN.md` across `skill/`, `templates/`, and `setup/`. The
  path never existed. (Historical references inside `migrations/0005` and prior
  CHANGELOG entries are left as-is — they are records of what shipped.)
- **`update/SKILL.md` claimed setup replays the migration chain** ("applies all
  migrations from `0000-baseline.md` forward … no parallel code path") — false
  since ADR-0036. It now states that setup installs from a prebuilt snapshot and
  that `check-snapshot-parity.sh`, not a shared code path, is what keeps the two
  from drifting.

### Changed

- **`implements_spec: 0.4.0` → `0.9.0`; `version: 2.4.0` → `2.5.0`** in
  `skill/SKILL.md`, with a new **"Spec deltas (spec 0.9.0)"** section naming
  four items per §09: §13's unwired implicit GSD trigger (SHOULD-level; `full`
  preserved), §14's trivial conformance (no LLM prompt-building surface in this
  scaffolder; `full` preserved), §10's delegation to the standalone
  `agenticapps-observability` skill (a satisfied MUST, recorded for clarity),
  and §08's setup/update equivalence — satisfied via the guarded snapshot
  install, recorded for clarity the same way §10 is.
- **`docs/ENFORCEMENT-PLAN.md` is now THE single hook-bindings table** required
  by §09 item 3. All **16** canonical §02 gates each get exactly one row with
  trigger, bound skill, and required evidence. Canonical gate names live in a
  `Gate` column with host key names (`multi_ai_plan_review`, `cso`,
  `code_quality_review`, …) in a separate `Host key` column, so the canonical
  name is unambiguous. `database-security` is **de-nested into its own row**
  (§02 forbids merging two gates into one); the two previously missing gates —
  `impeccable-audit` and `db-pre-launch-audit` — are added; `ts-declare-first`
  is bound to the `tdd` row per §13's SHOULD. Host extension gates are listed
  separately and marked as carrying no conformance weight. The stale inline
  `config.json` JSON dump is replaced by a pointer to `templates/config-hooks.json`
  — an inline duplicate is the second drifting table this file exists to replace.
  The programmatic-hooks count is corrected from a stale "5 hooks" to the actual
  **9 project-scoped + 1 global**, and the GitNexus reindex hook (2.4.0) gets the
  row it never had.

### Added

- **`migrations/0027-spec-0.9.0-conformance.md`** (2.4.0 → 2.5.0) — reorders the
  §04 block, inserts the Spec deltas section (extracted from the scaffolder's
  `skill/SKILL.md`, so a migrated install is byte-identical to a fresh snapshot
  install), raises the claim, repoints `_enforcement_contract` + drops the
  dangling `programmatic_hook` + corrects the inverted `design_critique`
  trigger, removes the dead hook, and bumps the version.
  Each step has an idempotency check and a rollback, plus six hard post-checks.
  Five fixtures under `migrations/test-fixtures/0027/`, wired as
  `test_migration_0027` in `run-tests.sh`.

  The dead-hook removal is **fail-safe**: it removes the file only when it is
  present AND registered in no event. A project that deliberately wired it keeps
  it — fixture `04-registered-hook-survives` is the negative twin that proves
  the migration never deletes a live hook.

### Known gaps

- **§13's implicit GSD trigger is still unwired** — disclosed in the Spec deltas
  section; §13 is SHOULD/MAY throughout, so `full` is preserved.
- **The §08 delta is resolved, not open.** It was drafted against core 0.8.0,
  under which `spec/08-migration-format.md` still carried `spec_version: 0.1.0`
  and said nothing about snapshots or parity guards, so the delta was recorded
  as genuinely open. Core has since shipped **spec 0.9.0** (commit `9e19eb7`,
  ADR-0018), amending §08 to recognize guarded-snapshot install as a
  named-conformant alternative to replay. This host's `migrations/check-snapshot-parity.sh`
  guard, run in CI on every change and named in `skill/SKILL.md`, satisfies the
  amended MUST as written — no longer a gap.
- **A divergent §04 copy survives in the CLAUDE.md payload.**
  `templates/claude-md-sections.md` and `templates/.claude/claude-md/workflow.md`
  carry their own 13-flag list with a reworded heading and reworded flags. §09
  item 1 binds the canonical block to the host's *primary instruction file*
  (`skill/SKILL.md` — the file carrying `implements_spec`), which is now
  conformant, so the 0.9.0 claim stands; but those copies are what agents read
  at runtime. Reconciling them needs its own migration.

### Migration-order note

This work originally targeted migration `0026` / `2.3.0 → 2.4.0`. The sibling
`feat/gitnexus-background-reindex` branch landed first and took both that slot
and 2.4.0, so it rebased to `0027` / `2.4.0 → 2.5.0` — the remedy the plan
prescribed for whichever branch merged second. Migration 0026 is untouched; both
harnesses coexist and both pass.

## [2.4.0] — GitNexus background reindex hook (reindex, not nudge)

Ships a claude-workflow-owned, **per-project** PostToolUse `matcher:"Bash"` hook
that runs a detached, incremental `gitnexus analyze` after a git commit, so a
repo's GitNexus index self-heals instead of relying on the agent to act on
gitnexus's global staleness *nudge*. The two coexist — our hook advances
`meta.lastCommit` to `HEAD`, so the global nudge self-silences on its next call.
Nothing global is modified. See ADR-0039.

### Added

- **`templates/.claude/hooks/gitnexus-reindex.cjs`** → `setup/snapshot/hooks/`
  → `.claude/hooks/gitnexus-reindex.cjs` — the reindex engine (ported from the
  validated `~/.gitnexus-hooks/reindex-on-change.cjs`, adding `$CLAUDE_PROJECT_DIR`-
  preferred root resolution). Fail-open (any error exits 0), lock-guarded
  (`.gitnexus/.reindex.lock`, `O_EXCL`, 10-min stale TTL), writer-pinned
  (`GITNEXUS_INVOCATION=gitnexus`), kill switch `GITNEXUS_AUTOREINDEX_DISABLED=1`,
  and a no-op in repos without a `.gitnexus/` directory.
- **PostToolUse `matcher:"Bash"` entry** in `templates/claude-settings.json`
  (→ snapshot) binding the engine with a 5s timeout.
- **`migrations/0026-gitnexus-background-reindex.md`** (2.3.0 → 2.4.0) — copies
  the engine from the scaffolder snapshot (idempotent — skips if byte-identical),
  wires the PostToolUse Bash entry if absent (guarded — never duplicates or
  overwrites a user edit), and bumps the installed version. Fixtures under
  `migrations/test-fixtures/0026/` (fresh-insert, idempotent-reapply,
  preserve-existing-posttooluse, engine-present-executable, engine-behaviour).
- **`docs/decisions/0039-gitnexus-background-reindex.md`** — the per-project-vs-global
  ownership decision and rejected alternatives (upstream, global installer).

### Changed

- **`bin/build-snapshot.sh`** now copies `templates/.claude/hooks/*.cjs` into the
  snapshot (and `chmod +x`), not just `*.sh`.
- **`migrations/check-snapshot-parity.sh`** — `gitnexus-reindex.cjs` added to the
  required hook bindings (§2) and a new §8 asserts the engine is present,
  executable, has a node shebang, and is bound on a PostToolUse Bash matcher.

## [2.3.0] — Knowledge capture into the Obsidian vault (spec §15)

Implements core spec **§15 (knowledge capture)** — the claude host now distills
1–5 **transferable** learnings into one Obsidian note per repo
(`~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/<repo-name>.md`)
as the final step of three rituals: **session handoff**, **plan completion**,
**phase completion**. The destination is config-routed (never hardcoded), the
write never blocks a ritual and is never committed to the repo, and machines
without the vault skip silently with one info line. See ADR-0038 and core
ADR-0017 / spec v0.7.0.

### Added

- **`skill/SKILL.md` → "Knowledge Capture — Ritual Tail (spec §15)"** — the
  wiring for the three trigger points: read
  `.planning/config.json → knowledge_capture`; graceful skip (block absent,
  `enabled: false`, or vault parent folder missing — never create it); distill
  1–5 learnings past the selectivity bar (write nothing if nothing qualifies);
  create the note from the embedded skeleton on first write; prepend an
  append-only Log entry; curate Key Learnings to ~10–20 items; report to the
  user. Vault safety: only the configured note, no secrets/client data.
- **`knowledge_capture` config block** seeded in `templates/config-hooks.json`
  → `setup/snapshot/planning-config.json` with a literal `<repo-name>`
  placeholder; `setup/SKILL.md` Step 4d resolves it to the repo directory name
  at install time, Step 5 post-checks it.
- **`templates/obsidian-learnings-note.md`** — canonical first-write skeleton
  (mirrors the vault-side schema CLAUDE.md).
- **`migrations/0025-knowledge-capture.md`** (2.2.0 → 2.3.0) — inserts the
  config block if missing (user opt-outs/custom notes preserved verbatim;
  creates the config if absent) and appends the ritual-tail section by
  extracting it from the scaffolder's `skill/SKILL.md` (single source of
  truth — migrated installs are byte-identical to fresh snapshot installs).
  Fixtures under `migrations/test-fixtures/0025/` (insert-and-wire,
  preserve-existing-block, idempotent-reapply, create-config-when-absent)
  wired into `run-tests.sh`.
- **`check-snapshot-parity.sh` §7 + §3 extension** — end-state invariants: the
  snapshot SKILL must carry the ritual-tail section, all three §15 trigger
  points, and the config-routed destination; the seeded config must keep the
  block with its `<repo-name>` placeholder.
- **ADR-0038** and a conformance-checklist line in
  `docs/standards/gsd-binding-and-planning.md`. `codex-workflow` and
  `opencode-workflow` must mirror §15 in their own idiom (their own host tag
  in log-entry headings).

### Changed

- `skill/SKILL.md` version → **2.3.0** (drift-coupled to 0025); snapshot
  rebuilt (`agentic-apps-workflow-SKILL.md`, `planning-config.json`,
  `VERSION`); `MANIFEST.md` documents the new block and parity §7.

## [2.2.0] — Commit phase artifacts (un-ignore `.planning/phases/`)

Phase artifacts under `.planning/phases/<NN>-<slug>/` (CONTEXT/PLAN/VERIFICATION/
REVIEW/HANDOFF-LOG) are the shared cross-host project plan and are now **committed
by default**, end to end. Motivated by the dual-host workflow-testbed benchmark
(rounds 1+2, 2026-07-01/02): scaffolded projects carried a whole-tree
`.planning/phases/` ignore, so **claude was the only host whose planning evidence
was not committed** (both rounds); codex needed `git add -f`, opencode un-ignored
the path mid-run. Root cause: the scaffolder shipped **no `.gitignore` at all**,
so nothing asserted the policy — the ignore came from the benchmark harness
baseline and was mis-attributed to "the GSD config." See ADR-0037.

### Added

- **`templates/gitignore` → `setup/snapshot/gitignore`** — a canonical scaffolded
  `.gitignore` that commits `.planning/phases/` and ignores only local/ephemeral
  paths (`.claude/worktrees/`, `.planning/current-phase`,
  `.planning/skill-observations/`, `*.tmp`, and narrow reviewer-scratch files
  *under* the tree). `setup/SKILL.md` Step 4h lays it down by **appending** to any
  existing project `.gitignore` (never clobbering stack ignores) and stripping a
  whole-tree phases ignore if present.
- **`migrations/0024-commit-planning-phases.md`** (2.1.0 → 2.2.0) — update-only
  migration that surgically removes a whole-tree `.planning/phases/` /
  `.planning/` / `.planning/*` ignore from an existing install's `.gitignore`
  (preserving every other entry), then bumps the version. Fixtures under
  `migrations/test-fixtures/0024/` (strip-when-ignored, noop-when-narrow-only,
  idempotent-reapply) wired into `run-tests.sh`.
- **`check-snapshot-parity.sh` §6** — end-state invariant: the drift guard now
  FAILs if the snapshot `.gitignore` ever ignores the phases tree, so the policy
  cannot regress into the seed.
- **ADR-0037** and a conformance-checklist line in
  `docs/standards/gsd-binding-and-planning.md` ("MUST NOT gitignore
  `.planning/phases/`"). `codex-workflow` and `opencode-workflow` must mirror both
  in their vendored copy.

### Changed

- `bin/build-snapshot.sh` assembles `gitignore` into the snapshot; `MANIFEST.md`
  documents it. `skill/SKILL.md` version → **2.2.0** (drift-coupled to 0024).

## [2.0.0] — SPLIT-03: extract observability to agenticapps-observability

**Breaking change.** Observability is no longer shipped by this scaffolder. It
has been extracted into the separate
[`agenticapps-observability`](https://github.com/agenticapps-eu/agenticapps-observability)
repository, which installs and updates independently. See
[`docs/UPGRADING.md`](docs/UPGRADING.md) for the 1.21.0 → 2.0.0 upgrade path.

### Removed (BREAKING)

- The `add-observability/` skill tree (`init` / `scan` / `scan-apply` and all
  per-stack templates) is removed from this repository. claude-workflow installs
  no observability scaffolding. Install `agenticapps-observability` separately
  (two independent installs — no submodule, no setup chaining).
- The `add-observability` skill-pair was dropped from `install.sh` (the LINKS
  array entry, the `/add-observability` help line, and the discovery grep hint).

### Added

- **`docs/UPGRADING.md`** — documents the 1.21.0 → 2.0.0 transition, the
  supported upgrade floor (1.21.0, the Phase 27 SPLIT-00 baseline), and the
  `agenticapps-observability` separate-install cross-reference.
- **Migration `0022`** (`from_version: 1.20.0`, `to_version: 2.0.0`) — repoints
  the observability install reference from `add-observability` to the canonical
  `observability` skill (verifies presence, aborts with install instructions if
  absent — no auto-install), and folds in the #58 deterministic Phase Sentinel
  hook swap. `0011` is not mutated (immutability contract).
- **Migration tombstones** for the slots moved to the obs repo (`0012`, `0013`,
  `0017`, `0018`, `0019`, `0020`, `0021`) — no-op redirect stubs that keep the
  migration chain contiguous and point downstream at the obs repo.

### Changed

- **#58 — deterministic Phase Sentinel Stop hook.** The Haiku `prompt`-type Stop
  hook is replaced with `templates/.claude/hooks/phase-sentinel.sh` (a
  deterministic shell hook: allow stop unless `.planning/current-phase/checklist.md`
  has unchecked `- [ ]` items). Shipped to new projects via template and to
  existing projects via the 2.0.0 migration.
- Forward-looking references in non-immutable files (`README.md`, `install.sh`,
  `setup/SKILL.md`, `templates/config-hooks.json`,
  `templates/.claude/hooks/observability-postphase-scan.sh`,
  `templates/.claude/claude-md/workflow.md`) repointed from `add-observability`
  to `observability` (slash invocations → `/observability`). Immutable shipped
  migrations keep their old-name references — the obs repo's `add-observability`
  alias resolves them at runtime.
- **`skill/SKILL.md` version → 2.0.0** (migration-coupled with `0022`'s
  `to_version`), resolving the prior 1.20.0 (skill) / 1.21.0 (tag) skew.

## [Unreleased] — SPLIT-01: extract shared migration infrastructure to agenticapps-shared

### Added

- **`vendor/agenticapps-shared` git submodule** — `agenticapps-eu/agenticapps-shared` vendored
  as a git submodule pinned by gitlink SHA `1f5d543bc6ca080ab6e3ba188df33cf3d193e3d4`
  (tag `v1.0.0` is provenance only — the gitlink SHA is the canonical pin artifact, A4).
  Submodule contains the shared migration runner lib (helpers / fixture-runner / preflight /
  drift-test) carved from `migrations/run-tests.sh` in Wave 1 (plans 28-01, 28-02).

### Changed

- **`migrations/run-tests.sh` refactored as a consumer (D-28e source-and-keep)** — sources
  the four shared lib files from the submodule
  (`helpers.sh / fixture-runner.sh / preflight.sh / drift-test.sh`) via `BASH_SOURCE[0]`
  dirname path resolution. SHARED function bodies (`extract_to`, `run_check`, `assert_check`,
  `_runtests_do_cleanup`) removed from this file (now sourced). `setup_fixture` REBUILT as a
  **WORKFLOW wrapper** that calls shared `extract_to` and layers the workflow-specific template
  paths (`templates/workflow-config.md`, `config-hooks.json`, `claude-md-sections.md`) and the
  1.3.0 ADR special-case on top (A1 — workflow template paths are not generic). All per-migration
  WORKFLOW bodies (`test_migration_0001`…`test_migration_0021`) plus the dispatcher and summary
  blocks are kept verbatim. Drift + preflight are thin WORKFLOW policy wrappers over the shared
  mechanism functions (`run_drift_test`, `run_preflight_verify_paths`).
- **Suite baseline preserved EXACTLY:** `PASS=186 FAIL=4`. The 4 failures are pre-existing
  `test_migration_0017` / FIX-0017 scope — unchanged, not regressed, not "fixed" here.
  Drift test (`test-skill-md-version-matches-latest-migration-to-version`) still **PASSES**.
- **`install.sh` advances the submodule on every run** — when `.gitmodules` exists, always runs
  `git submodule sync --recursive && git submodule update --init --recursive` (idempotent on
  existing clones; advances a stale gitlink after `git pull`; A3).
- **`docs/decisions/0035-shared-extraction-boundaries.md` ADR-0035 amended** — `setup_fixture`
  demoted from SHARED to WORKFLOW set (A1, codex HIGH, user-locked); `extract_to` remains SHARED.
  SHARED count drops 9→8; WORKFLOW count rises 20→21.

### Notes

- `claude-workflow` VERSION and `skill/SKILL.md` intentionally NOT bumped — version bump decided
  at SPLIT-02 ship time (likely 2.0.0-rc.X).
- GSD command outputs (`/gsd-progress`, `/gsd-stats`, `/gsd-help` equivalents) verified
  byte-identical before and after the refactor (A6, SC-6).
- ADR-0035 amendment + `run-tests.sh` WORKFLOW annotation were staged in plan 28-01 and
  committed here alongside the behavioral refactor (plan 28-03).

## [Unreleased]

## [1.21.0] — stable baseline (SPLIT-00 gate) — 2026-06-02

> **Versioning note (migration-locked-version policy):** This is an **A2 (tag-only) release**.
> The **release/baseline tag** `v1.21.0` leads the **skill version** (`skill/SKILL.md`),
> which is migration-coupled and TRAILS at `1.20.0` — it advances only when a migration's
> `to_version` advances (user rule `versioning-tracks-migrations`; A2 decision D-07;
> see `.planning/PROJECT.md` §"Versioning policy"). Phase 27 ships NO new migration;
> therefore `skill/SKILL.md` stays at `1.20.0` and the drift test
> (`test_skill_md_version_matches_latest_migration_to_version` in `migrations/run-tests.sh`)
> stays GREEN (`SKILL.md 1.20.0 == migration 0021 to_version 1.20.0`). This is
> deliberate policy, NOT an inconsistency — downstreams verify the 1.21.0 baseline
> via the **git tag `v1.21.0` + commit SHA**, not by reading the installed `SKILL.md` version.
> `add-observability` stays at `0.10.0` — its template fixes are internal until the
> deferred DEF-1/DEF-2 re-rev migration (D-07d). Mirrors `.planning/PROJECT.md`
> §"Versioning policy" standardized two-axis version model.
>
> **SPLIT-00 gate note:** The CHANGELOG section landing in the PR does NOT by itself
> satisfy the SPLIT-00 gate. The `v1.21.0` tag must exist on `main` (see Task 2
> manual release action below). The 7-day cooling-off clock starts after tagging.

### Fixed (Phase 27 — WR-01, WR-02)

- **WR-01: go-test counter double-count** (`add-observability/templates/run-template-tests.sh`, lines 633-634) — `grep -c` always prints a count (`0` on no match) and exits 1 on no match, so the prior `|| echo "0"` appended a second `0`, yielding `"0\n0"` and inflating the pass/fail display. Fixed by dropping the redundant fallback (`|| true` used to suppress the non-zero exit). Lines 128, 130, 558, 559 (which use `grep -oE … | grep -oE '^[0-9]+'`) are correct and unchanged — those emit nothing on no match and do need `|| echo "0"`.
- **WR-02: supabase-edge `_resetForTest` cleanup in `finally`** (`add-observability/templates/ts-supabase-edge/index.test.ts`) — `Deno.test("D-02a init() repeated-init determinism")` restored `console.log` in its `finally` block but never called `_resetForTest()`, causing `initialized=true` and env-a singletons to leak into subsequent tests. Added `_resetForTest()` to the `finally` block alongside `console.log` restoration. Closes test-isolation gap (Phase 26 carry-forward D-02a).

### Added (Phase 27 — WR-03, PROJECT.md, ADR-0035, boundary annotations)

- **WR-03: direct `buildSentryOptions` unit tests × 3 stacks** — new dedicated test blocks for `buildSentryOptions(env)` across cf-worker (`lib-observability.test.ts`), cf-pages (`lib-observability.test.ts`), and openrouter-monitor (`src/observability/index.test.ts`). Assertions (5 per stack): `tracesSampleRate === TRACE_SAMPLE_RATE` (baked constant), `environment === env.DEPLOY_ENV ?? "dev"`, `release === env.SERVICE_NAME ?? SERVICE_DEFAULT`, `sendDefaultPii === false`, `dsn === env.SENTRY_DSN`. Completes DEF-1 unit-test coverage for the helper that Phase 26 added.
- **`.planning/PROJECT.md`** — canonical product identity document: core value, two-axis versioning policy (release/baseline tag vs skill version), known downstream consumers, current milestone, and 3-repo split overview. Forward-looking only; history lives in `.planning/phases/` and the git log.
- **`docs/decisions/0035-shared-extraction-boundaries.md`** — ADR records the SHARED/WORKFLOW boundary audit for `migrations/run-tests.sh` extraction into `agenticapps-shared`. Documents what belongs in each layer, the extraction sequence, and explicitly defers code movement to SPLIT-01 (post-1.21.0 cooling-off).
- **`migrations/run-tests.sh` `# SHARED /` and `# WORKFLOW` boundary annotations** — audit-only; no code movement. Comments mark which test stanzas belong to the future `agenticapps-shared` layer vs the claude-workflow-specific layer, giving SPLIT-01 a clear extraction map.

### Changed (Phase 27 — WR-04, STATE/ROADMAP refresh, SPLIT doc fixes)

- **WR-04: openrouter-monitor entry routes Sentry options through `buildSentryOptions(env)`** (`add-observability/templates/openrouter-monitor/src/index.ts`) — replaces the hardcoded inline options object (`tracesSampleRate: 0.1` et al., lines 48-57) with `withSentry(env => buildSentryOptions(env), …)`, completing DEF-1 wiring in the worked example. Snapshot-unchanged invariant confirmed; 17 openrouter tests GREEN.
- **`STATE.md` + `ROADMAP.md` drift refresh** — updated to reflect Phase 27 execution progress, v1.21.0 milestone entry, and tag-only release framing.
- **`SPLIT-01-agenticapps-shared.md` premise correction** — corrected an inaccurate framing of what SPLIT-01 extracts; aligned with ADR-0035 boundary decision.
- **`SPLIT-00-PREREQUISITES.md` gate changed to pin-by-tag** — replaces the prior `SKILL.md` version check with a git tag `v1.21.0` + commit SHA pin. `SKILL.md version: 1.20.0` is not acceptable evidence of the 1.21.0 baseline under A2 (an auditor would incorrectly read it as 1.20.0).

### Fixed (Phase 26 — promoted from [Unreleased]; engine + harness + fixture hardening — 2026-06-01)

- **`_filter_index_ts_requires_co_anchor` content-marker firewall** (Phase 26 D-06 / CR-D) — `migrate-0019-sentry-crons-and-healthz.sh` now content-checks `index.ts` against `grep -qiE "observability|lib-observability|withObservability|sentry|agenticapps:observability"` before classifying as an alias wrapper anchor. Closes the CodeRabbit Phase 25 finding D false-positive class. Regression detector: `migrations/test-fixtures/0019/13-index-ts-without-observability-content/`. Engine-only fix.
- **Harness pin hardening — DUAL strategy** (Phase 26 D-03, D-03a, D-03b, D-03c — corrected per cross-AI review codex HIGH-4) — `run-template-tests.sh` pins `vitest` to **EXACT `3.2.4`** (no operator) in 3 heredocs (cf-worker, cf-pages, ts-react-vite). The prior tilde-pin proposal (`~3.2.4`) was insufficient: npm tilde semantics permit `>=3.2.4 <3.3.0`, which still allows vitest@3.2.5 — exactly the drift event Phase 25 audit-time identified. Exact pin blocks it. Separately, `@sentry/cloudflare` pins to **TILDE `~8.55.0`** (patch drift acceptable; SDK is more stable than vitest). D-03b policy comment documents the DUAL strategy. ts-react-vite uses `@sentry/react` and is excluded from the cloudflare pin. supabase-edge runner block (negative-asserted per D-03c) contains zero pins — `deno test`, no npm install.
- **Fixture `0021/04` TS1038 fix** (Phase 26 D-07a / CR-E) — replaces TS1038-illegal `declare const console` inside `declare global` with canonical `interface Console + declare var console: Console` ambient pattern.
- **Fixture `0021/04` honest fail-fast** (Phase 26 D-07b / CR-E) — `verify.sh` no longer `exit 0`s when `npx` is unavailable. New: `exit 1` with `fixture 0021/04 FAIL — npx required for tsc typecheck (install Node 18+ which bundles npx)`.

### Notes

- All Phase 26 changes are template-surface / engine-binary / fixture-level — no migration 0022 (D-04).
- `add-observability` ships 0.10.0 with template-surface changes; see `add-observability/CHANGELOG.md`. That track is decoupled from the migration chain.
- **Cross-AI review (codex) corrections incorporated in engine/harness scope:** HIGH-4 (vitest exact pin, not tilde); MED-2 (fixture 13 verify.sh strengthens SC-5 evidence via sha + skip-classification grep); Mechanical-1 (single-capture suite runs across tasks).
- **`skill/SKILL.md` stays at `1.20.0`** — A2 invariant. No migration ships in Phase 27.
- **`add-observability` stays at `0.10.0`** — D-07e; template fixes are internal until the deferred DEF-1/DEF-2 re-rev migration.
- **Manual release action (Task 2 — deferred to ship time):** After the Phase 27 PR merges to `main`, create the annotated tag on the merge commit:
  ```
  git tag -a v1.21.0 -m "claude-workflow 1.21.0 — stable baseline (SPLIT-00 gate)"
  git push origin v1.21.0
  ```
  Then verify: `git tag --list 'v1.21.0'` shows the tag; `git describe --tags` points at the merge commit. Do NOT bump `skill/SKILL.md` to 1.21.0 — the drift test would FAIL.

## [1.20.0] — 2026-05-31

### Added — Migration 0021: re-rev cron-monitor + ship queue-monitor for v1.19.0 projects (`add-observability` 0.8.0 → 0.9.0, Phase 25, ADR-0033)

Delivers to projects already at v1.19.0 the Phase 25 template changes that Migration 0019 cannot retrigger on per its `from_version: 1.17.0` contract. Two deliverables ship together.

- **Updated `cron-monitor.ts`** (all 3 TS stacks + openrouter-monitor subtree) — discriminated-union `CronMonitorSchedule` type (D-03, all 3 TS stacks + openrouter); narrowed `withCronMonitor<E>` generic for cf-worker + openrouter-monitor (D-05); exports `buildMonitorConfig` + `isConfigured` for queue-monitor consumer (D-19, cf-worker + cf-pages + openrouter-monitor; supabase-edge omitted per codex H-6). cf-pages uses `<R>` return-type generic (codex H-3 verified). openrouter-monitor stays byte-symmetric with cf-worker (D-21). Fixes both cron-related Findings in issue #56.
- **New `queue-monitor.ts`** (cf-worker + cf-pages ONLY — Supabase Edge has no Cloudflare-Queue equivalent, per codex H-6) — Guarded Shape A semantics (ADR-0029/ADR-0033): `handlerStarted` flag prevents double-ack on `batch.ackAll()`, per-message retry on handler error, Sentry crons heartbeat via `withMonitor`. Imports `buildMonitorConfig` + `isConfigured` from `./cron-monitor` (D-19 import contract). `withQueueMonitor<E, Body>` generic: `E` = env, `Body` = queue message body.
- **Migration 0021 engine** (`templates/.claude/scripts/migrate-0021-with-cron-and-queue-updates.sh`) — re-rev with dirty detection. Mirrors Migration 0019's `canonicalize_awk` verbatim (Mirror-not-fork anti-pattern per `migrations/0019-sentry-crons-and-healthz.md:260`). Twofold idempotency marker (codex M-8): SKIP only when BOTH `queue-monitor.ts` present AND `cron-monitor.ts` canonical hash matches v1.20.0 baseline. Dirty detection (codex M-9): refuses on hand-modified `cron-monitor.ts`, emits `.observability-0021.patch` to project root.
- **`migrations/0021-with-cron-and-queue-updates.md`** — migration spec with two-phase apply (discovery + canonicalisation gate + apply), twofold idempotency, recovery instructions (callbot drop-LOCAL-PATCH path), and re-rev rationale (codex H-7).
- **`docs/decisions/0033-with-queue-monitor.md`** — ADR records Guarded Shape A queue-monitor architecture, re-rev rationale, dirty-detection contract, and explicit rejected alternatives.

### Fixed (`add-observability` 0.8.0 → 0.9.0, Phase 25 D-03/D-05, issue #56)

- **D-03 — `CronMonitorSchedule` discriminated union**: `{ type: "crontab"; value: string } | { type: "interval"; value: number; unit: string }` replaces the bare `type MonitorSchedule = { type: string; value?: ... }` shape that allowed invalid combinations at the type level. All three TS stacks updated.
- **D-05 — `withCronMonitor<E>` generic narrowing** (cf-worker + openrouter-monitor): env parameter now typed `E extends { SENTRY_DSN?: string; SERVICE_NAME?: string }` (strict CallbotEnv-style env with no index signature compiles without cast). cf-pages uses `<R>` return-type generic per H-3. supabase-edge has no generic.
- **Migration 0019 D-11 fix**: fresh applies of Migration 0019 now copy `queue-monitor.ts` to cf-worker + cf-pages wrappers (was omitted pre-Phase-25). Supabase Edge carve-out maintained (codex H-6).

### Notes

- Re-rev rationale (short): an additive-only Migration 0021 that shipped only `queue-monitor.ts` would leave v1.19.0 consumers' `cron-monitor.ts` at the pre-Phase-25 broken state — Findings 2 and 3 of issue #56 would not close. The re-rev ships BOTH fixes, which is what closes the findings end-to-end. See ADR-0033 §"Re-rev rationale".
- Dirty detection: projects with hand-modified `cron-monitor.ts` are refused with a patch file. Callbot's LOCAL-PATCH cast (`:141-149`) is rendered unnecessary by D-03/D-05 — drop it before running Migration 0021.
- `skill/SKILL.md` frontmatter `version: 1.19.0 → 1.20.0` (minor — new migration + template fixes).
- `add-observability/SKILL.md` frontmatter `version: 0.8.0 → 0.9.0` (minor — new queue-monitor template + cron-monitor fixes).
- Pre-execute multi-AI plan review (`gemini` + `codex` via `/gsd-review`) caught 7 HIGH + 6 MEDIUM issues that landed as CONTEXT rev 2/3 + PLAN rev 2/3 before code shipped. Notable HIGH fixes (H-1 through H-6): SC5 typecheck fixture local ambient decls (H-2); tsconfig paths mapping for `@sentry/cloudflare` in standalone tsc run (H-1); cf-pages `<R>` generic vs cf-worker `<E>` generic (H-3); frozen v1.19.0 baselines as literal files not generated from mutable templates (codex M-1); supabase-edge queue-monitor scope carve-out (H-6); dirty detection for hand-modified cron-monitor (H-7 / D-02b revised).

## [1.19.0] — 2026-05-29

### Added — OpenRouter integration kit (`add-observability` 0.7.0 → 0.8.0, Phase 24, ADR-0030)

Four SDK-first deliverables ship together. No migration — purely additive. Existing projects adopt via the runbook (`add-observability/openrouter-integration.md`) or via INIT for greenfield (consent gate 4).

- **`recordLLMResponseMeta` helper** across 3 TS stacks (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`). Post-processes the OpenAI SDK's raw response to capture `x-ratelimit-remaining` / `x-ratelimit-reset` headers + cache_ratio (`prompt_tokens_details.cached_tokens / prompt_tokens` with divide-by-zero guard). Signals Sentry AI Monitoring's `openAIIntegration` doesn't surface. Dependency-injected `LogEventFn` per §10.6 destination-independence — destination-agnostic. Per-stack import paths: worker/pages use bundler-style `./index`; supabase-edge uses Deno explicit-extension `./index.ts`. Skipped for `ts-react-vite` (browser must not hold OpenRouter keys) and `go-fly-http` (no Go LLM consumer in scope). +21 helper test fixtures across the template harness.
- **`add-observability/openrouter-integration.md`** — 5-section runbook covering Sentry AI Monitoring `openAIIntegration` enablement (with loud PII gate), Anthropic SDK generic path (`anthropicIntegration`), helper wiring at SDK call sites (`.withResponse()` pattern), pointer to the credit-check Worker, and adoption checklist. Requires `@sentry/<host> ≥ 10.2.0` for AI Monitoring in the main app. PII gate carves out synthetic / non-user / approved-eval data with written `policy.md` approval (callbot / cparx defaults must stay `false`).
- **`add-observability/templates/openrouter-monitor/`** — standalone Cloudflare Worker scaffold for proactive budget alerting. Polls `OpenRouter /api/v1/key` every 15 min. Emits `openrouter.credit_pulse` always, `openrouter.credit_low` warn at ≥85%, `OpenRouterBudgetCriticalError` at ≥95%, `OpenRouterHealthcheckFailedError` on non-2xx / network / parse failure. Inverted-threshold misconfig handling + invalid-env-var fallback + `limit:null` (OpenRouter unlimited-key shape) all covered. Wrapped with `withCronMonitor` (ADR-0029 Guarded Shape A) so the monitor has its own Sentry Crons heartbeat. Composition chain: `withSentry(env => ({...}))(withObservabilityScheduled(withCronMonitor(checkCredit, { monitorSlug })))` — all three layers are mandatory. Ships bundled `src/observability/` subtree (canonical wrapper subtree from `ts-cloudflare-worker` template) so the scaffold is standalone. README leads with the `keys:read`-scope warning + ships a "Security & Secret Lifecycle" subsection covering rotation cadence, accidental-commit prevention, leak-response runbook, operator offboarding. 12 fixture handler tests.
- **`init/INIT.md` Phase 5.5 §"Optional: LLM observability"** — consent gate 4 (additive). Detection logic broadened beyond `package.json + src/`: matches workspace `package.json`s, `wrangler.toml` env vars, `.dev.vars`, `.env.example`. SDK-version prerequisite check (≥10.2.0) gates the integration-insertion action. Three actions (insert integration / copy helper / skip) — default on `--yes` is skip (runbook is canonical manual-adoption path).
- **`docs/decisions/0030-openrouter-integration-sdk-first.md`** — ADR records the SDK-first architecture rationale, with explicit rejected alternatives (raw-fetch `wrapLLMCall`, bundled `pricing.json`, Anthropic-specific helper, CLI subcommand for the monitor, `OPENROUTER_BUDGET_OVERRIDE`).

Pre-execute multi-AI plan review (`gemini` + `codex` via `/gsd-review`) caught 4 HIGH + 5 MEDIUM issues that landed as fixes in CONTEXT rev 2 / PLAN rev 2 before code shipped. Notable HIGH fixes:

- Per-stack helper import path (worker/pages `./index`; supabase-edge `./index.ts`).
- Monitor scaffold bundles the observability subtree (worker template wrapper, with placeholders substituted to `SERVICE_NAME = "openrouter-monitor"`).
- Monitor composition uses the FULL `withSentry` → `withObservabilityScheduled` → `withCronMonitor` chain (skipping `withObservabilityScheduled` would no-op `logEvent` / `captureError` silently).
- Severity literal `"warn"` (NOT `"warning"`) — matches the shipped `Severity` union.

See `.planning/phases/24-openrouter-integration/24-REVIEWS.md` for the full review record.

### Notes

- SDK-first only. No raw-fetch helper ships in this PR — both target consumers (factiv/callbot, factiv/fx-signal-agent post-PROMPT-C0) use the OpenAI SDK. Raw-fetch instrumentation is an explicitly-deferred ADR slot.
- `skill/SKILL.md` frontmatter `version: 1.18.0 → 1.19.0` (minor — purely additive).
- `add-observability/SKILL.md` frontmatter `version: 0.7.0 → 0.8.0` (minor — purely additive).
- `add-observability/templates/openrouter-monitor/package.json` pins `@sentry/cloudflare ^8.0.0` (matches the bundled wrapper subtree's baseline). The 10.2.0 minimum applies to the main app using AI Monitoring; the monitor itself makes no LLM calls.
- Test surface delta: +21 helper fixtures (across worker/pages/supabase-edge template harness) + 13 monitor fixtures (separate `npm test` in the scaffold dir; +1 from the post-`/review` contract guard for 200-OK-missing-data).
- Phase 24 `/review` flagged 3 pre-existing concerns in the worker-template wrapper subtree (also inherited by the monitor's bundled copy): `TRACE_SAMPLE_RATE` declared but unwired; `REDACTED_KEYS` missing `authorization`/`bearer`; module-level mutable `serviceName`/`deployEnv` singletons. Carried forward to a Phase 25.x worker-template cleanup — the fix-shape spans worker + pages + supabase-edge simultaneously and is out of scope for this PR.

### Fixed (`add-observability` 0.5.0 → 0.5.1 — wrapper template correctness, issue #49)

No scaffolder version bump and **no migration**: the wrapper public interface (spec §10.1) is byte-identical, so downstreams already on 1.16.0 pick up the patches by re-materialising the wrapper (re-run `add-observability`). CodeRabbit flagged these on `agenticapps-eu/callbot#40`; fixing them upstream keeps every downstream wrapper coherent with the migration hash baseline. See ADR-0026.

- **Nested-secret redaction (gap #1, all 4 TS stacks)** — `redactObject`/`redactValue` now recurse into plain objects and arrays. Secrets nested below the top level (e.g. `attrs.request.headers.secret`, arrays of objects) are scrubbed; `null` and non-plain objects (`Date`, class instances) pass through; input is never mutated.
- **`captureError` visibility (gap #2, all 4 TS stacks)** — caller `severity` is coerced to `error` (preserving an explicit `fatal`) before `emit`, so a caller-supplied `severity: "debug"` can no longer be sample-rate-gated and silently dropped.
- **Browser Axiom same-origin enforcement (gap #3, `ts-react-vite`)** — the Axiom adapter `isConfigured`/`init` resolve `AXIOM_PROXY_URL` through a same-origin guard: relative paths accepted, protocol-relative (`//host`) and cross-origin absolute URLs rejected, fail-closed when `location` is absent. A misconfigured `VITE_AXIOM_PROXY_URL` can no longer exfiltrate envelopes cross-origin.
- **`parseTraceparent` semantics (gap #4, all 4 TS stacks)** — beyond the structural regex, reject reserved/unknown version (≠ `00`) and all-zero trace-id / parent-id that downstream collectors discard or mis-attribute. No new `zod` dependency.
- **`_resetForTest` completeness (gap #5, `ts-react-vite`)** — now also clears `spanStack`, resets `serviceName`/`deployEnv` to defaults, and restores `window.fetch` from the original (`init` stores the original reference, binds only the interceptor base) so the next `init` re-patches a clean global. Eliminates cross-suite test leakage.
- **Regression coverage** — new tests across `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, and `ts-react-vite` (incl. the browser Axiom cross-origin cases). Full template suite green (worker 43, pages 30, react-vite 41, supabase-edge 25, go-fly-http 25); migration suite 168 PASS / 0 FAIL.

## [1.18.0] — 2026-05-29

### Added — Sentry Crons heartbeats (`withCronMonitor`) + `/healthz` convention (issue Phase 22)

- New optional `withCronMonitor` / `WithCronMonitor` wrapper exported by 4 stack templates (worker / pages / supabase-edge / go-fly-http). Composes innermost in the scheduled chain (worker); 2-deep `withObservability(withCronMonitor(...))` on supabase-edge (D5b); generic async-fn shape on pages (D5c); functional-options style in Go (D5d). Fail-safe when `SENTRY_DSN` is unset (zero checkins, no exception). 3-source slug resolution: explicit > env-var (`SENTRY_CRON_MONITOR_SLUG_<HANDLER>`) > auto-derived. Multi-cron workers must pass explicit `monitorSlug` (D11). `monitorConfig` (schedule + maxRuntime) forwarded as Sentry's 2nd arg on `in_progress` checkin only (D12). Opt-in `SENTRY_DEBUG=1` surfaces swallowed checkin errors. See `add-observability/uptime-setup-runbook.md` for Sentry UI configuration.
- New `healthz-snippet.{ts,go}` template per stack — copy-only (operator decides where to mount). 200 ok / 503 degraded contract with per-check breakdown. **Fail-closed on zero probes configured** (R06 — returns 503 with `reason: "no probes configured"`). Intentionally NOT routed through `withObservability` (D4) to keep Sentry's transaction view free of probe noise. Top-of-file WARNING block instructs adapt-or-don't-mount.
- New `add-observability/uptime-setup-runbook.md` — operator-facing walkthrough of Sentry UI configuration for Crons + Uptime + `policy.md` cross-link template + Part 4 Security & Public Exposure (`?detail=true` gating, `/healthz` vs `/readyz` deferral, probe authentication).
- Migration 0019 (`from_version: 1.17.0`, `to_version: 1.18.0`) — additive adoption; refuses on hand-modified wrappers via content-hash check mirroring 0017's style-insensitive canonicalization. **2-pass atomic apply** (classify all roots → all-clean gate → apply) per codex's HIGH-severity review finding R08. 7 fixtures (fresh / already-applied / hand-modified-refuse / cparx-shape / fxsa-multi-module / mixed-clean-dirty-refuses-all / react-vite-only).
- ADR-0028 records host-discretion-vs-spec-mandate decision (no spec amendment).

### Fixed

- `skill/SKILL.md` version drift: PR #52 declared `to_version: 1.17.0` (migration 0018) but left the SKILL.md frontmatter at `1.16.0`. Folded as commit 1 of this branch (`122aafa`) — keeps the 1:1 version-tracks-migrations invariant intact.

### Compatibility

- All v0.5.1 template exports byte-identical across 5 stacks. 170 existing template-suite tests pass unchanged; 58 new tests across cron-monitor + healthz contracts bring total to 228 PASS.
- v1.17.0 projects can skip migration 0019; no breaking change.
- react-vite stack: no changes (browser bundle has no scheduled handlers; no server-side healthz).

## [1.17.0] — 2026-05-27

### Added (GSD post-phase observability hook — advisory, issue #50)

Migration **0018** (1.16.0 → 1.17.0). Ships the one piece of §10.9 enforcement that belongs upstream as a post-phase agent gate. Does **not** add the §10.9.3 CI gate or §10.9.4 pre-commit hook (both still deferred pending the deterministic Node scanner port). See ADR-0027.

- **`templates/.claude/hooks/observability-postphase-scan.sh`** — advisory hook that delta-scans the phase diff (`add-observability scan --since-commit <phase-base>`) on phase completion and WARNS when `counts.high_confidence_gaps > 0`, pointing at `scan-apply --confidence high`. Resolves the phase base via `git merge-base HEAD origin/<default>`.
- **Wired into the GSD post-phase chain** — `config-hooks.json` → `hooks.post_phase.observability_scan` (installed into projects as `.planning/config.json`), alongside `spec_review`/`code_quality_review`/`security`/`qa`. Documented in `workflow.md` post-phase hooks. Chosen over a Claude Code `Stop` hook (which fires every turn-end — wrong frequency + recursion-prone for an LLM scan).
- **Advisory, never blocking** — `set +e` + `trap 'exit 0'`; always exits 0. Promote to blocking once the deterministic scanner ships.
- **No-op when enforcement not adopted** — explicit one-line notice + exit 0 when `.observability/baseline.json` is absent.
- **Migration 0018** — idempotent (copy hook → merge config entry → bump version), with pre-flight, post-checks, and rollback per step. Tests: `test-fixtures/0018` (needs-apply / already-applied) + advisory-contract smoke; migration suite 171 PASS / 0 FAIL.

## [1.16.0] — 2026-05-26

### Added (Axiom as logs destination — Sentry stays errors-only)

- **Destination registry** across all 5 stack templates (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `ts-react-vite`, `go-fly-http`): each wrapper gains `destinations/{registry,sentry,axiom}` adapters. `logEvent` routes to the logs destination; `captureError` routes to the errors destination. NO dual-ship: Sentry=errors, Axiom=logs by default. Spec §10.6/§10.8 — no spec change.
- **Fail-closed `resolveConfig`** — role map baked at init (`DESTINATIONS_CONFIG`) + `OBS_DESTINATIONS` env override. Unsupported role mappings (e.g. `errors=axiom`, which declares only logs+analytics) are REJECTED at init; errors can never silently route to Axiom.
- **Axiom adapter** — POSTs to `https://api.axiom.co/v1/datasets/<dataset>/ingest` (`AXIOM_INGEST_URL` override for all stacks). Never-throws into app code: try/catch + rate-limited warn + `ctx.waitUntil`/`EdgeRuntime.waitUntil`/Go goroutine drained by the existing `Flush()`. No-op when `AXIOM_TOKEN`+`AXIOM_DATASET` are absent.
- **Browser (ts-react-vite) safety** — no ingest token in the browser; Axiom adapter is console-only unless `VITE_AXIOM_PROXY_URL` (same-origin proxy) is set. `VITE_AXIOM_TOKEN`/`VITE_AXIOM_DATASET` are never read.
- **ts-cloudflare-pages full contract-test harness (D3)** — cf-pages shipped zero tests before this release; now has its own wrapper + ~16 contract tests + Axiom tests (27 total). Closes a pre-existing coverage gap.
- **Materialize-and-test harness** `add-observability/templates/run-template-tests.sh` — runs each stack's tests by materializing the template into a temp project (vitest/deno/go). Reproduces the full baseline + new tests. **148 stack tests total green** (cf-worker 40, cf-pages 27, react-vite 34, supabase-edge 22, go-fly-http 25).
- **`meta.yaml` `destinations:` block** (×5: available/defaults/roles_supported) + a `test_meta_destinations_consistency` check asserting meta `roles_supported` matches each adapter's role table.
- **INIT.md** — `--destinations errors=sentry,logs=axiom` flag + "Destination role assignment" phase; copies only role-referenced adapters; writes the v0.4.0 `observability:` block.
- **Migration `0017-add-axiom-logs-destination.md`** (from_version 1.15.0 → to_version 1.16.0) — adopts the registry shape on existing v0.3.x/v0.4.x projects via an executable engine. §10.7 consent: structural-masking hash detection refuses hand-modified wrappers (writes ZERO files on refuse by default; `--allow-partial` to apply clean roots only); auto-generates a `.observability-0017.patch` on refuse. Rewrites CLAUDE.md `observability:` v0.3.0→v0.4.0 via anchor-managed range. 11 test fixtures.

### Fixed (migration 0017 engine — caught pre-adoption; no version bump)

These repair the 1.16.0 migration-0017 apply engine before any downstream
project adopted it; 0017 stays a 1.15.0 → 1.16.0 migration (no new migration,
no SKILL.md bump — versions track migrations 1:1 in this repo).

- **Apply materialises tokens (Bug #1).** The engine copied the v1.16.0 wrapper + adapter templates verbatim, leaving generator tokens (`{{SERVICE_NAME}}`, `{{ENV_VAR_DSN}}`, `{{REDACTED_KEYS}}`, …) in the output — invalid TS/Go — while `smoke_build` only advised. It now recovers each token's real value from the project's existing wrapper (using the vendored OLD v0.4.x template as an alignment guide) and injects them into the new wrapper + adapters, **preserving** project values (a customised `TRACE_SAMPLE_RATE` is not reset). A toolchain-independent token-free guard refuses any root whose output still carries a token (ZERO writes), and `smoke_build` is now fatal (rolls the root back + exits non-zero). Per-token extraction picks an unambiguous prefix/suffix site so the cf-worker InitEnv block (three env tokens sharing one signature) does not collapse all three to the DSN env var.
- **Anchored wrappers apply (Bug #2).** `canonicalize_awk` now strips `// agenticapps:observability:start`/`:end` marker lines before hashing, so a pristine anchor-wrapped wrapper (migration-0014 / init idiom) canonicalises to the baseline and classifies CLEAN instead of being wrongly refused (this had blocked migrating frontends).
- **No version bump on a zero-migrate run (Bug #3).** `bump_version` now runs only when ≥1 root actually migrated, so an `--allow-partial` run that skips every dirty root (or a run where every clean root fails the guard/smoke) no longer leaves the repo claiming 1.16.0 with un-migrated wrappers.
- **Hermetic test baseline.** The 0017 fixtures + `regen-hashes.sh` sourced the OLD wrapper from `git show main:`, which PR #45's merge turned into the NEW registry wrapper — silently making the whole suite a no-op. The OLD v0.4.x wrappers are now vendored as engine runtime data (`templates/.claude/scripts/migrate-0017-old-wrappers/`, shared by engine + tests).
- **Style-insensitive canonicalization (issue #47).** The masking rules assumed the template's style (double quotes, trailing semicolons), so a downstream `.prettierrc` (single quotes / no semicolons) defeated every rule and a clean wrapper was refused — blocking real projects (callbot) from migrating. `canonicalize_awk` now folds both sides to one canonical style (quotes, semicolons, trailing commas, whitespace) before masking; a shared `NORMALIZE_ONLY` mode keeps token extraction aligned across styles. Line reflow (print width) is still not normalised. Genuinely customised wrappers remain correctly refused → recovery patch. Hashes regenerated. Suite 11/11; full migration suite 168.

### Changed

- **`skill/SKILL.md`** version 1.15.0→1.16.0 (`implements_spec` stays 0.4.0). **`add-observability/SKILL.md`** 0.4.0→0.5.0 (`implements_spec` stays 0.3.2).
- **Version-metadata note**: `add-observability`'s `version` bumps (0.4.0→0.5.0, new declarative destination surface) but its `implements_spec` stays `0.3.2` deliberately — the wrapper RUNTIME contract (§10.1–10.7) is unchanged; the multi-destination shape it now materialises is a §10.8 project-metadata concern already permitted at 0.3.x. Not a drift bug.

### Notes / deferred to 1.17.0

- Axiom span emission (analytics role), ingest batching, error mirroring to Axiom, destinations beyond Sentry+Axiom. Downstream adoption (cparx/fx-signal-agent/callbot) is separate post-1.16.0 work.

## [1.15.0] — 2026-05-25

### Fixed (ADR 0025 — multi-AI review gate phase resolution)

- **Migration `0016-fix-multi-ai-review-gate-resolution.md`** — promotes 1.14.0 → 1.15.0. Replaces the `multi-ai-review-gate.sh` hook (installed by migration 0005 / ADR 0018) with the **ADR 0025 hybrid resolver**. Root cause: the prior hook resolved the active phase with `readlink .planning/current-phase`, assuming a symlink to the phase dir — but the design-shotgun and database-sentinel gates use `.planning/current-phase/` as a **directory** of approval sentinels. `readlink` on a directory returns empty, so the gate hit its allow-path and exited 0 on every edit. A 2026-05-25 audit found the gate installed and wired in cparx, fx-signal-agent, and callbot yet **firing in none of them** — a convention collision silent since migration 0005. The new resolver is a fail-open chain: (1) legacy symlink, (2) `STATE.md` `## Current Phase` (cheap awk parse, before node), (3) GSD `state json` `current_phase` (node fallback), (4) newest `*-PLAN.md` by mtime, (5) allow. Step 2 bumps the skill version 1.14.0 → 1.15.0. Idempotent; settings wiring unchanged (hook command path is identical to 0005, so no `.claude/settings.json` edit). Apply order is automatic (ascending id: 0015 → 0016).
- **Grandfather guard on the block condition** — the gate now blocks **only** when the resolved phase has `*-PLAN.md` AND no `*-REVIEWS.md` AND no `*-SUMMARY.md`. The `!SUMMARY` guard prevents bricking repos that already shipped phases without reviews: enforcement is go-forward, so only new planned-but-unexecuted phases block. Per ADR 0018, already-shipped phases are never blocked; historical backfill stays optional and out of scope.
- **ADR 0025 — Fix multi-AI review gate phase resolution (`docs/decisions/0025-fix-multi-ai-review-gate-resolution.md`, NEW)** — Status: Accepted, 2026-05-25. Related: ADR 0018, migrations 0005 + 0016. Alternatives rejected: GSD-state-only (`gsd-tools state json` returned `status: unknown` in callbot — unreliable as sole signal), newest-PLAN-only (mtime fragile across `git checkout`/clone — kept as last resort before fail-open, not primary), and block-all-unreviewed (would brick fx-signal-agent/callbot — forbidden by ADR 0018).
- **Prettier-clean the vendored §11 block** (#44, no version change) — `templates/spec-mirrors/11-coding-discipline-0.4.0.md` gained blank lines around lists to satisfy prettier. Declarative/formatting-only; the byte-identity contract with workflow-core's canonical fence is unaffected.

### Notes

- **codex-workflow and pi-agentic-apps-workflow need the same resolver** — tracked as conformance follow-ups in workflow-core spec `02-hook-taxonomy.md`.

## [1.14.0] — 2026-05-21

### Added (spec 0.4.0 absorption)

- **Migration `0014-inject-spec-11-coding-discipline.md`** — promotes 1.12.0 → 1.14.0. Closes spec 0.4.0 §11 conformance for AgenticApps workflow projects by injecting the canonical "Coding Discipline (NON-NEGOTIABLE)" four-rule block (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven Execution) verbatim into the project's CLAUDE.md, behind a provenance-managed anchor (`<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`) that supports drift detection and clean re-injection across future spec revisions. Vendored block at `templates/spec-mirrors/11-coding-discipline-0.4.0.md`, byte-identical to workflow-core's `spec/11-coding-discipline.md` canonical fence (lines 26-102 between ```` fences). Placement: immediately before the first `## ` level-2 heading per §12's "near the top" advisory and to keep the replacement boundary unambiguous (the prior "after H1 + first blank" placement was discovered by fixture 07-byte-identity-replace to leak preamble paragraphs into the managed range). Pre-flight refuses the conflict case (`## Coding Discipline (NON-NEGOTIABLE)` heading present without provenance comment) with two operator hand-resolution paths (remove the section OR add the provenance line to adopt the existing block as canonical). **The version bump itself** (1.12.0 → 1.14.0 on `skill/SKILL.md`; `implements_spec` 0.3.2 → 0.4.0) is bundled here in Step 2 because spec 0.4.0 absorption is the only structural change in 1.14.0 that requires a SKILL.md-level claim — migration 0015 lands at the same target version and rides on this bump (its `from_version: 1.14.0`).
- **Migration 0014 test fixtures** — `migrations/test-fixtures/0014/` with 7 sandboxed scenarios (`01-fresh-apply`, `02-already-applied` for idempotency on the matching-provenance no-op path, `03-stale-anchor` for cross-version replace, `04-unmanaged-conflict` for the heading-without-provenance refuse path, `05-no-claudemd` for the permissive no-CLAUDE.md branch, `06-version-mid-apply` for Step 2 idempotency when Step 1 ran but the SKILL.md bump partially landed, and `07-byte-identity-replace` — added post-initial-commit when the naïve "stop at first ##" replace logic was discovered to leave the old block body in place because the canonical block contains its own `## ` level-2 heading). `test_migration_0014()` stanza added to `migrations/run-tests.sh`. **All pass.**
- **Migration `0015-add-ts-declare-first-skill.md`** — rides on 0014's version bump (`from_version: 1.14.0`, `to_version: 1.14.0`). Closes spec 0.4.0 §13 conformance by symlinking the `ts-declare-first` skill into the user-global skills directory (`$HOME/.claude/skills/agenticapps-workflow/ts-declare-first → claude-workflow/ts-declare-first`) — same install idiom as migration 0012's slash-discovery for `add-observability`. TS-primary detection per §13 heuristic: `package.json` present AND any of {`"types"` field, `"main"` resolves to `.ts`, `typescript` in deps/devDeps}. Non-TS projects no-op with informational message; the skill is opt-in per §13's MAY-level mandate.
- **Migration 0015 test fixtures** — `migrations/test-fixtures/0015/` with 4 sandboxed scenarios (`01-fresh-install` for first-time symlink creation, `02-already-installed` for the matching-target idempotency no-op, `03-non-symlink-refuses` for the safety abort when a real directory exists at the target path, `04-redirected-symlink` for the abort when the symlink points elsewhere). `test_migration_0015()` stanza added to `migrations/run-tests.sh`. **All pass.**
- **`ts-declare-first/` skill scaffold (NEW host skill)** — closes spec §13 conformance on the host scaffolder itself, not only downstream. Frontmatter `version: 0.1.0`, `implements_spec: 0.4.0`. Enforces three ATOMIC commits in order for new TS modules: Phase 1 declaration (`<name>.declare.ts` — `declare`-only type-surface, no implementation bodies, no expression initialisers, type-checks clean against `tsc --noEmit`); Phase 2 failing tests (observable as failing in the expected way at this commit — declarations exist, implementations don't); Phase 3 implementation (signatures match declaration exactly; tests now pass). The skill **REFUSES** to bundle Phase 1 and Phase 3 into a single commit — the three-commit atomicity IS the structural evidence that the discipline was followed; collapsing it erases the evidence. Templates: `example.declare.ts` (non-normative bounded-queue declaration), `example.test.ts` (matching failing-test stub), `example.impl.ts` (matching implementation) — kept as separate files so the three-commit shape is structurally enforced when an operator copies the templates.
- **ADR 0024 — Secret-scanner choice (`docs/decisions/0024-secret-scanner-choice.md`, NEW)** — local mirror that ratifies workflow-core's ADR-0015 ("Secret-scanner choice"). Decision: **STAY on gitleaks**. Cross-repo PR opened against workflow-core (<https://github.com/agenticapps-eu/agenticapps-workflow-core/pull/10>) flips ADR-0015 Status: Proposed → Accepted. Locked-rule benchmark (RESEARCH.md A4) fired STAY via ties on criterion 1 (TP recall) and criterion 2 (FP count). Secondary finding worth noting: **criterion 4 inverted vs RESEARCH.md A1's prediction** — gitleaks 8.30.1 decodes inline base64 by default and finds an AWS-shape key inside the encoded payload; betterleaks 1.3.0 does NOT surface the encoded form with default flags, `--max-decode-depth 10`, or any of 5 tried `--experiments` values. This is a credibility-positive signal for the incumbent. Full per-criterion methodology + raw artefacts (tool versions, fixture metadata, 7 criterion files, baseline SARIF+JSON pairs, DECISION.md) in the host-local evaluation directory `<host-local>/scanner-eval-2026-05-20/` (intentionally off-repo — see RESEARCH.md §A5 for the rationale: error logs may contain real secret material). **RESEARCH.md A1 drift recorded in tool-versions.txt + both ADRs**: betterleaks canonical repo is `github.com/betterleaks/betterleaks` (not `aikidosec/betterleaks` — that URL 404s at evaluation date); betterleaks IS available via homebrew-core (`brew install betterleaks` → 1.3.0), contra A1's "no homebrew tap" claim. 12-month re-evaluation reminder named in ADR Consequences.

### Changed

- **`implements_spec: 0.3.2 → 0.4.0` and `version: 1.12.0 → 1.14.0`** on `skill/SKILL.md` frontmatter. claude-workflow now claims conformance to `agenticapps-workflow-core` v0.4.0 — which absorbed §11 "Coding Discipline (NON-NEGOTIABLE)", §12 "Branchy workflows", §13 "Declare-first TypeScript", and ratified ADR-0015 "Secret-scanner choice". All four sections have load-bearing artefacts in this PR (migrations 0014 + 0015, `ts-declare-first/` skill, ADR 0024 + cross-repo PR #10).
- **`ts-declare-first/SKILL.md` §12 conversion** — see `.planning/phases/20-spec-0.4.0-absorption/P3-AUDIT-LOG.md` for the full audit trail. The skill is newly authored at 0.4.0 adoption and so **MUST satisfy** §12 per the audit rule (≥2 decision branches AND ≥1 cycle/fallback → render as `flowchart TD` Mermaid + 1-3 sentences of judgment-prose immediately below). 1 paragraph converted (the Refusals section). Pre-existing host files (`skill/SKILL.md`, `add-observability/SKILL.md`) are **deferred** per §12's explicit bulk-conversion waiver (4 candidates total: Step 2 GSD entry-point routing + Verification Check in `skill/SKILL.md`, Dispatch table in `add-observability/SKILL.md`, plus a marginal 14-Red-Flags candidate). The audit log is the deferral evidence; future PRs that materially rewrite either pre-existing file SHOULD revisit and apply the deferred conversions.

### Fixed

- **Migration 0011 preflight verify-path rot** — `requires.verify` for the `add-observability` skill dependency literally pinned `^implements_spec: 0.3.0` via `grep -q` (not `-qE`). The skill has since moved 0.3.0 → 0.3.1 (v1.11.0 INIT) → 0.3.2 (v1.12.0 Sentry v8 / Trace context fixes from #39/#40) → 0.4.0 (this version); the literal pin reported FAIL in `--strict-preflight` mode on every fresh-machine audit since v1.11.0 (and FAIL in the loose audit's informational output, where it was the *one* known carry-over since v1.11.0). Widened to `grep -qE '^implements_spec: 0\.[3-9]\.[0-9]+$'` extended-regex: 0011's local-enforcement step is forward-compatible with all 0.3.x and 0.4.x add-observability skill versions because the `spec_version` value it writes into the consumer's `observability:` block (0.2.1 → 0.3.0) is unchanged and the dependency just needs to be at least at that spec_version. Preflight audit now reports **PASS=19 FAIL=0 SKIP=4** on a fresh strict run; full migration suite PASS=147 FAIL=0 holds. Test/declarative-only change; no scaffolder semantics moved.

### Notes

- **No 1.13.x release.** 1.14.0 is the bundled jump for spec 0.4.0 absorption (per migration 0014's `from_version: 1.12.0 → to_version: 1.14.0`). The two-minor jump signals "structural spec absorption" semantically — bystanders reading the version history know the gap was deliberate, not a missing release.
- **STAY translates to "no new CI fragment".** Per phase 20 PLAN.md P5 reshape (divergence D2), the STAY outcome means claude-workflow does NOT ship `add-observability/enforcement/secret-scan.yml.example`. Phase 0's `grep -RIn 'gitleaks\|betterleaks'` count of zero is unchanged post-this-PR. Downstream projects choose a secret scanner locally.
- **12-month re-evaluation reminder; inversion-watch carried.** ADR 0024's Consequences §Follow-ups names a 12-month re-eval. If betterleaks ships an inline-base64 decoder OR gitleaks regresses its default decode behaviour before then, the criterion-4 inversion flips and the STAY decision weakens. The calendar reminder catches forward motion naturally, but the inversion-as-explicit-re-eval-trigger is not yet named in the ADR — carried as an open question for the next ADR revision.
- **Cross-repo merge ordering — IMPORTANT.** Cross-repo PR <https://github.com/agenticapps-eu/agenticapps-workflow-core/pull/10> (Proposed → Accepted on `adrs/0015-secret-scanner.md`) MUST merge before this 1.14.0 PR opens for code review. Local ADR 0024 references the cross-repo ADR; the link resolves once #10 merges.
- **Cparx fixture fallback.** RESEARCH.md A2 named cparx as the preferred scanner-eval fixture, but cparx lacks a documented seeded-secret catalog (the cparx pilot docs are about observability scanning, not secret scanning). Fell back to A2's named alternative — `vercel-labs/deepsec/fixtures/vulnerable-app/` — recorded in the eval directory's `fixture-meta.md`.
- **Downstream pickup.** cparx + fx-signal-agent are at v1.12.0 + add-observability v0.4.0 on feature branches but unmerged at the time of this entry. They pick up 0014 + 0015 via `/update-agenticapps-workflow` once this PR lands and the global scaffolder bundle ships 1.14.0.
- **Carry-forward.** Phase 15 F4 (`test_init_fixtures()` harness exercising the 7 init fixture pairs) remains deferred. `policy:` multi-stack support for spec §10.8 remains deferred. ts-supabase-edge verification (from PR #41) remains deferred.

## [1.12.0] — 2026-05-16

### Fixed (template fidelity — `add-observability` v0.3.3 → v0.4.0)

- **`ts-cloudflare-worker` template: drop `Sentry.init` for `withSentry`** (closes [#40](https://github.com/agenticapps-eu/claude-workflow/issues/40) Bug 1) — `@sentry/cloudflare` v8 removed the top-level `Sentry.init` export in favour of the `withSentry(optionsCallback, handler)` pattern that initialises the Sentry client per-Worker-isolate request. The wrapper's `init()` previously called `Sentry.init({...})` and would fail TS compilation immediately after materialisation against any project pulling `@sentry/cloudflare` v8.x. `init()` now only sets local module state (service name, deploy env, waitUntil binding) and records the DSN-presence flag for downstream `Sentry.withScope` / `captureException` / `addBreadcrumb` calls — Sentry SDK initialisation moves to the entry-file site where `withSentry((env) => ({...}), { fetch, scheduled })` wraps the whole ExportedHandler object. INIT.md Phase 5 detail for `ts-cloudflare-worker` updated in lockstep: the rewrite shape now imports `withSentry` from `@sentry/cloudflare` and wraps the default-export object with the v8-canonical pattern. **Affects only future `init` runs** — existing materialised wrappers at v0.3.x are user-editable and can adopt the new shape manually if they pull `@sentry/cloudflare` v8+. fx-signal-agent's workaround (no-op Sentry.init block) documented in #40 reverses cleanly once a project re-runs init at v0.4.0.
- **`ts-cloudflare-worker` middleware: `ScheduledEvent` → `ScheduledController`** (closes [#40](https://github.com/agenticapps-eu/claude-workflow/issues/40) Bug 2) — Cloudflare Workers' cron handler signature is `scheduled(controller: ScheduledController, env, ctx)`; the wrapper's `withObservabilityScheduled` declared the parameter as the unrelated `ScheduledEvent` type. Both `controller.cron` and `controller.scheduledTime` exist on `ScheduledController`, so the middleware's runtime logic was correct — purely a wrong-type-name bug propagating to every Worker entry rewritten in Phase 5. Pure type rename; no behaviour change.
- **`go-fly-http` template: native Sentry `Contexts["trace"]` in `CaptureError`** (closes [#39](https://github.com/agenticapps-eu/claude-workflow/issues/39)) — the wrapper previously wrote W3C trace IDs as free-form Sentry tags only (`trace_id:<hex>` searchable via Discover), but did NOT populate Sentry's native `Contexts["trace"]` map. Consequence: searching `trace:<hex>` (Sentry's built-in field syntax — the operator's first instinct) returned 0 hits, AND the Trace Explorer UI rendered events without span trees. Adds a `scope.SetContext("trace", map[string]any{...})` call alongside the existing `SetTag` pair — additive, mapping the wrapper's `TraceContext` 1:1 onto Sentry's schema (`trace_id`, `span_id`, `parent_span_id` when present, `op` = event name, `status` from a new `sentryTraceStatus(Severity)` helper that maps error/fatal → `internal_error` and everything else → `ok`). Existing `SetTag("trace_id", ...)` and `SetTag("span_id", ...)` calls preserved so free-form tag searches keep working — zero behaviour change for adopters that already query by tag, full native Trace UI for adopters that don't. Witness: factiv/cparx PR #48 + #50 (the `POST /api/admin/sentry-test` endpoint) — operator wasted ~10 minutes searching `trace:<hex>` before realising the wrapper wrote `trace_id:<hex>` only. **Contract test added**: `TestSentryTraceStatusMapping` in `observability_test.go` pins the Severity → trace-status enum mapping. **Scope**: only `go-fly-http` is affected — TS templates integrate with Sentry's native trace context via `@sentry/cloudflare`'s automatic span scoping (which `withSentry` enables — see #40 Bug 1 above). `ts-supabase-edge` ships `@sentry/deno` v8 which still exports `Sentry.init` (different runtime model from the Cloudflare SDK), so neither #40 fix applies there at v0.4.0; documented as a separate verification item when the next Supabase Edge adopter lands.

### Changed

- **`implements_spec` bumped 0.3.0 → 0.3.2** on both `skill/SKILL.md` and `add-observability/SKILL.md` frontmatter (declarative-only — no migration, no behavior change). claude-workflow now claims conformance to `agenticapps-workflow-core` v0.3.2 (spec PR <https://github.com/agenticapps-eu/agenticapps-workflow-core/pull/7>). Coverage of the new spec requirement: spec §10.5 "Flush primitive" — all 5 stack templates satisfy it; `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, and `ts-react-vite` satisfy implicitly via host-runtime await (Worker `ctx.waitUntil`, browser SPA long-lifecycle, Deno Deploy isolate behaviour); `go-fly-http` exposes explicit `Flush(timeout)` per [PR #36](https://github.com/agenticapps-eu/claude-workflow/pull/36) (`add-observability` v0.3.3). Existing adopters at workflow v1.12.0 inherit the conformance bump on their next git pull of the scaffolder — no migration required, no project-side change required. The `reference-implementations/README.md` row in `agenticapps-workflow-core` is updated to reflect the new spec version on the spec PR.

### Fixed

- **`go-fly-http` template: emission-goroutine vs. `sentry.Flush` race** (`add-observability` v0.3.2 → v0.3.3) — discovered during the cparx Sentry-wiring verification (factiv/cparx PR #48). The Go wrapper's `safeFireAndForget` pattern launches a goroutine for each Sentry emission (CaptureError + per-event breadcrumb). `sentry.Flush` waits for the SDK transport's buffer to drain but does NOT wait for goroutines that haven't yet *enqueued* into that buffer. In long-running services this race is benign — goroutines have plenty of scheduler time between requests. In short-lived processes (CLI tools, tests, the `cmd/sentry-smoke` verification binary) the race silently loses events: Flush returns true on an empty buffer because the emission goroutine hasn't reached `sentry.CaptureException` yet. Diagnosed by running `cmd/sentry-direct` (direct synchronous `sentry.CaptureException` — arrived in Sentry) alongside `cmd/sentry-smoke` (wrapper-routed — did not arrive), isolating the race to the `safeFireAndForget` layer. **Fix**: track every `safeFireAndForget` goroutine in a `sync.WaitGroup` (`emissionWG`); expose a new public `Flush(timeout time.Duration) bool` that waits for the WaitGroup *first*, then calls `sentry.Flush` with the remaining time budget; when `sentryReady=false` (test runs without a DSN, dev smoke runs), skip the SDK-Flush call and report success once the WG drains. Also adds `SENTRY_DEBUG=1` env-gate on `sentry.Init`'s Debug option for future verification runs (production leaves it unset). Long-running HTTP servers do NOT need to call `Flush` — per-request goroutines have time to complete naturally. CLI tools and tests MUST use `observability.Flush` instead of `sentry.Flush` directly. **Contract test added** (`add-observability/templates/go-fly-http/observability_test.go`) — `TestFlushDrainsInFlightEmissions` regression-guards the WG-drain behaviour, `TestFlushReturnsTrueWithNoEmissions` covers the idle case, `TestFlushTimesOutOnStuckEmission` covers the bounded-wait case. **15/15 tests pass** (12 prior + 3 new) verified via materialise-and-test against cparx's wrapper directory. TS templates are unaffected — Worker `ctx.waitUntil` and browser SPA long-lifecycle handle drain natively; only Go (no equivalent runtime-await for short-lived processes) needed an explicit Flush primitive. CONTRACT-VERIFICATION.md gains a parity row + a deliberate-divergence row documenting the rationale. cparx PR #48 ships the same fix downstream as the witness of this bug.

### Added

- **Migration `0013-auto-init-and-stale-vendored-cleanup.md`** — promotes 1.11.0 → 1.12.0 in 3 steps. Closes two adopter-side frictions surfaced by the cparx v1.10.0+v1.11.0 adoption verification (PR #34's `.planning/cparx-v1.10.0-adoption-verification/REPORT.md`): (1) stale project-local `.claude/skills/add-observability/` copies at v0.2.x silently shadow the global v0.3.2+ skill installed by 0012, producing "unknown subcommand: init" when adopters run `claude /add-observability init`; (2) the two-`/update-agenticapps-workflow` flow for projects that haven't yet run init — 0011's pre-flight aborts on missing `observability:` metadata, the user runs init manually, then re-runs `/update-agenticapps-workflow`. 0013 detects and removes the stale vendored copy (Step 1), chains the init procedure inline when metadata is missing (Step 2, delegates to `add-observability/init/INIT.md` via the same LLM-driven idiom as 0011 Step 1 → `scan/SCAN.md`), and bumps the scaffolder to v1.12.0 (Step 3). Pre-flight refuses the confused state where the project-local copy matches the global version (would mean someone hand-vendored the current skill — Step 1's remove-and-defer heuristic is no longer safe).
- **Migration 0013 test fixtures** — `migrations/test-fixtures/0013/` with 5 sandboxed scenarios (fresh-apply-no-vendored-no-init, fresh-apply-stale-vendored-no-init, fresh-apply-no-vendored-with-init, current-vendored-refuses, idempotent-reapply). `test_migration_0013()` stanza added to `migrations/run-tests.sh`. **5/5 pass.**

### Changed

- **Migration 0011 pre-flight abort message** — adds a NOTE pointing v1.11.0+ adopters at migration 0013's auto-init for the missing-`observability:`-metadata case. Existing v1.9.3 → v1.10.0 transition behaviour unchanged.

### Notes

- **F2 from cparx report was fixed in v1.11.0's `[1.11.0]` window** (skill v0.3.2 re-export of `ObservabilityErrorBoundary`). 0013 closes F1 (stale vendored cleanup) + the implicit two-update friction; F3 (go-fly-http multi-binary entry detection) remains deferred to a future scaffolder version.
- **Step 2 of 0013 is LLM-driven by design** — `init` requires three consent gates (scaffold, entry-rewrite, CLAUDE.md metadata) which the migration framework's pure-shell model can't surface. The consuming agent (Claude Code session running `/update-agenticapps-workflow`) follows the same chain-to-procedure idiom 0011 Step 1 uses for `scan/SCAN.md`. Decline paths exit migration cleanly with exit 3 and the same rollback hints as a direct init invocation.

## [1.11.0] — 2026-05-16

### Fixed

- **`ts-react-vite` template missing `ObservabilityErrorBoundary` re-export** (`add-observability` v0.3.1 → v0.3.2) — discovered during the cparx v1.10.0 adoption verification (see `.planning/cparx-v1.10.0-adoption-verification/REPORT.md` F2). `add-observability/templates/ts-react-vite/lib-observability.ts` was missing the line `export { ObservabilityErrorBoundary } from "./ErrorBoundary";`. INIT.md Phase 5 detail (line 632-634) requires the materialised `src/lib/observability/index.ts` to re-export the boundary so `main.tsx` can `import { init, ObservabilityErrorBoundary } from "./lib/observability"` as a single import. Without the re-export, the materialised wrapper compiled but the entry-file rewrite broke at type-check with "Module './lib/observability' has no exported member 'ObservabilityErrorBoundary'". The init fixture at `migrations/test-fixtures/init-ts-react-vite/expected-after/src/lib/observability/index.ts` line 22 already showed the correct shape, so the fixture documented the contract but the template never matched — direct evidence for why the deferred `test_init_fixtures()` harness (Phase 15 VERIFICATION F4) matters. Fix is one line added between the JSDoc header and the rest of the module body. Affects only future `init` runs (existing wrappers already materialised at v0.3.1 are user-editable; teams can add the line manually).
- **`test_migration_0007` hermetic sandbox** (phase 18) — `run_0007_fixture` invoked the install + verify scripts with `PATH="$fake_home/bin:$PATH"`, so a host-installed `gitnexus` (e.g., from `fnm`-managed node at `$HOME/.local/state/fnm_multishells/.../bin/gitnexus`) shadowed the missing-stub case in the `03-no-gitnexus` fixture. The install script's `command -v gitnexus` resolved to the host binary, the script exited 0, and the test logged the last remaining carry-over failure since v1.9.3. Replaced the leaky invocation with `env -i HOME=… PATH="$fake_home/bin:/usr/bin:/bin" bash …`: the host PATH and any host `GITNEXUS_*` / `WIKI_SKILL_MD` env vars no longer cross the sandbox boundary. Full migration suite now reports **PASS=131 FAIL=0** — clean baseline. Phase 15 smoke regression-guard tightened from `PASS≥130 FAIL≤1` to `PASS≥131 FAIL=0` (no known-fail allowlist needed) and the parser now treats a missing `FAIL: 0` line from `run-tests.sh` as zero. Test-only change; no scaffolder semantics moved.
- **`test_migration_0001` baseline-anchor regression** (phase 17) — the test extracted its "before" fixture from `git merge-base HEAD origin/main`, which resolves to HEAD itself when running on `main` post-merge. Both fixtures then carried the post-0001 template state and all 8 "needs apply on v1.2.0" assertions failed (8 of the 9 known carry-over failures since v1.3.0). The fix anchors `before_ref` to the parent of the commit that first introduced migration 0001's `## Backend language routing` marker in `templates/workflow-config.md` — a self-locating lookup that resolves to the v1.2.0 baseline (`7dafa63`) regardless of branch. The legacy merge-base chain is retained as a fallback for stripped clones or feature branches that haven't merged 0001 yet. Full migration suite now reports **PASS=130 FAIL=1** (only Phase 18's `03-no-gitnexus` carry-over remains). Phase 15 smoke regression-guard thresholds tightened in lockstep from `PASS≥122 FAIL≤9` to `PASS≥130 FAIL≤1`. Test-only change; no scaffolder semantics moved.

### Added

- **REDACTED_KEYS default expansion** (`add-observability` v0.3.1 → v0.3.2) — closes Phase 15 /cso S1 (REVIEW.md lines 183-205). Default scrub list gains four universal-by-default token shapes: `secret`, `client_secret`, `refresh_token`, `access_token`. Applied symmetrically to all 5 stack templates (`meta.yaml` defaults + `policy.md.template` `## Redacted attributes` lists) and all 8 init reference fixtures (`policy.md` outputs + `REDACTED_KEYS=[…]` provenance comments in wrapper sources). `ts-react-vite`'s browser-specific `credit_card` entry is preserved at its existing position. Pure declarative-doc + template change: no migration, no scaffolder version bump — installed projects' user-editable `lib/observability/policy.md` is unaffected; only new `init` runs pick up the expanded default. Skill minor bump per S1's "defer to v0.3.2 or v0.4.0".
- **Anchor-comment threat-model documentation in `INIT.md` "Important rules"** — captures the Phase 15 /cso S2 recommendation (REVIEW.md lines 253-256): the anchor pair is structurally fail-safe (denial-of-init, not silent conformance bypass) and future refactors MUST preserve the Phase 2 strict-first-run and Phase 6 POLICY_PATH self-check under "improve UX of re-init" pressure. Cross-references the full S2 threat assessment for maintainers.
- **`implements_spec: 0.3.0` on `skill/SKILL.md` frontmatter** (closes #31) — declarative-only field, immediately after `version:`. Mirrors the same field on `add-observability/SKILL.md` so the spec-conformance assertion is machine-verifiable on the canonical scaffolder skill itself (not only on the observability sub-skill). The `reference-implementations/README.md` row in `agenticapps-workflow-core` already declares this repo at `0.3.0 / full`; this change lets drift-detection tooling find and verify that assertion locally without leaving the repo. No migration: scaffolder-only declarative-doc change per #31's "out of scope if treated as scaffolder-only" option. Installed projects' `.claude/skills/agentic-apps-workflow/SKILL.md` is unaffected at v1.11.0.
- **`--strict-preflight` flag for `migrations/run-tests.sh`** (phase 19) — rolls the Phase 13 preflight-correctness audit's `FAIL` count into the global `FAIL` count when set, so CI environments with parity to author dev environments can gate merges on verify-path rot (the issue-#18 bug class). Also accepts `STRICT_PREFLIGHT=1` as an env-var alias for CI-runner ergonomics. Default (loose) mode is unchanged: audit failures still print but don't affect exit code, so dev machines with partial host dependencies aren't false-positive failed. In strict mode the audit's mode-aware header reads `Preflight-correctness audit (strict — failures gate exit)` and the disclaimer reports `(counted in suite totals — strict mode: N FAIL rolled into global FAIL.)`. PyYAML-missing is also strict-aware: loose mode skips with a `~` warning, strict mode emits `✗ python3 with PyYAML not available — audit cannot run (strict)` and increments `FAIL` by 1. New `--help` flag prints the usage block; unknown flags exit 2 (distinct from FAIL → exit 1 so CI can distinguish user error from test failure). Phase 15 smoke runs without the flag and remains unaffected. `migrations/README.md` gains a "Preflight-correctness audit" section documenting both modes.
- **`add-observability/init/INIT.md` shipped** (phase 15) — closes #26 + spec §10.7 obligations (1) wrapper scaffold and (2) middleware/trace-propagation wiring. Nine-phase init flow with three consent gates (consent-1 plan, consent-2 entry-rewrite, consent-3 CLAUDE.md metadata), idempotent re-detection via anchor comments, and per-stack subsections for all five supported stacks (`ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `ts-react-vite`, `go-fly-http`). Decline paths preserve partial work + print rollback hints instead of half-applying.
- **Slash-discovery via global `~/.claude/skills/` symlink** — closes #22 on both code paths: fresh install via `install.sh` LINKS row (Step T1) and existing installs via migration 0012 Step 4 (1.10.0 → 1.11.0 upgrade path). After either path, `claude /add-observability …` resolves directly without prefixing the project skill directory.
- **Migration `0012-slash-discovery.md`** — promotes 1.10.0 → 1.11.0 in one step: idempotently symlinks `~/.claude/skills/add-observability` to the scaffolder's `add-observability/` directory + bumps `skill/SKILL.md` version. Refuses to overwrite a hand-curated real directory at the target path; warns and aborts if the symlink already points elsewhere.
- **Migration 0012 test fixtures** — `migrations/test-fixtures/0012/` with 5 sandboxed scenarios (fresh apply, idempotent re-apply, wrong-target abort, real-directory abort, version-bump idempotency). `test_migration_0012()` stanza added to `migrations/run-tests.sh`. **5/5 pass.**
- **Per-stack init fixtures** — `migrations/test-fixtures/init-<stack>/` × 6 (7 fixture pairs total: 1 worker + 1 pages + 1 supabase + 1 vite + 3 go for chi/gorilla/std priority detection). Each pair has `before/` + `expected-after/` capturing the canonical wrapper scaffold, middleware wiring, entry-file rewrite, `policy.md` materialisation, and CLAUDE.md observability metadata block. Reference-only at v1.11.0 (no automated harness function yet) — load-bearing as the structural reference for INIT.md's per-stack subsections.
- **Per-stack `policy.md.template` files** — `add-observability/templates/<stack>/policy.md.template` × 5. Anchorless template body; init wraps with `<!-- BEGIN observability policy -->` / `<!-- END observability policy -->` and substitutes `{{SERVICE_NAME}}` at materialisation. Byte-equivalence verified: each of the 7 fixture `policy.md` files = template body + anchor wrap + service-name substitution.
- **`add-observability/init/metadata-template.md`** — canonical §10.8 metadata schema reference (NEW, 413 lines). Documents the observability CLAUDE.md block shape, the three pre-existing-state paths (add / update-via-anchor / conflict-via-unanchored-grep), `enforcement.ci:` as an optional manual field (omitted by default per §10.8 line 160 + Option-4 stance), and the post-write 0011-parser self-check (`awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}'`) that init runs to prove the block is parseable. The parser invocation is byte-identical across metadata-template, INIT Phase 6 (block writer), and INIT Phase 9 (post-write self-check) to lock the contract.
- **`add-observability/SKILL.md` bumped 0.3.0 → 0.3.1** — `implements_spec: 0.3.0` unchanged (spec semantics didn't move; only the implementation surface grew). Init row description expanded to name all 9 phases + 3 consent gates + 5 stacks. New **Routing-table structural invariant** section codifies the Q8 mechanical check (every manifest- or routing-table-referenced path MUST resolve OR be explicitly annotated `(create)` / `(new)`) as a permanent contract on the skill, not just a phase-15 review heuristic.

### Notes

- **Closes 1.10.0's init-blocker**: migration 0011's hard pre-flight aborted with "run init first" when observability metadata or `policy.md` was missing. At v1.10.0 there was no init to run — the abort was correct but the path forward was empty. v1.11.0 ships init, so the v1.10.0 → v1.11.0 chain (or the fresh-install path) now has a fully-walkable end-to-end story for new projects.
- **`enforcement.ci:` omitted by default**: per spec §10.8 line 160 + the Option-4 local-first stance carried forward from v1.10.0. Init's metadata writer ships the field neither set nor referenced; teams wiring CI gates add it manually. The metadata-template documents the field for users who go that path.
- **`policy:` is scalar (single string), not array, at v0.3.1**: PLAN T11's explicit decision, locked by migration 0011's POLICY_PATH parser which expects a single-token value at `^[[:space:]]*policy:`. Multi-stack `policy:` unification is deferred to a future spec amendment + matching parser change. T15's regression row runs `bash migrations/run-tests.sh 0011` post-T1-T13 as the explicit guard against scalar-policy regression.
- **CLAUDE.md add/update/conflict paths**: Phase 6 of init distinguishes three pre-existing-state cases via anchor comments + `^observability:` grep. Anchored block ⇒ update in place. No block ⇒ append fresh. Unanchored observability block (hand-curated) ⇒ refuse to auto-overwrite — print manual-merge hint + treat as consent-gate-3 decline. The conflict branch protects user-tuned metadata from silent destruction.
- **Phase 15 multi-AI review**: BLOCK by codex on PLAN.md v1 (REQUEST-CHANGES by gemini + Claude); 20-item revision list applied to produce PLAN v2 (see `.planning/phases/15-init-and-slash-discovery/15-REVIEWS.md`). Codex caught the Q1 routing-table integrity gap (manifest referenced `./init/INIT.md` which didn't exist at PLAN v1 time) — the lesson was codified as the Q8 mechanical check and embedded in the skill itself per T12.
- **Q8 regex bugfix**: PLAN v1's Q8 script used `[a-z/-]+\.md` (lowercase-only) and missed `./init/INIT.md` because of the uppercase `INIT`. PLAN v2's corrected case-insensitive form `grep -oiE '\./[a-zA-Z/_-]+\.md'` is now the canonical reference encoded in `add-observability/SKILL.md`'s structural-invariant section so future phases inherit the fix instead of rediscovering it.
- **T6-T9 bundled commit**: the four per-stack init subsections + their fixtures landed as a single commit (`047b963`) rather than the per-task atomic pattern T1-T5 / T10-T12 followed. Rationale: shared Phase 5 contract, per-stack subsection headers + named fixture dirs preserve traceability without ~470-line edit-revert ping-pong. Flagged as a one-off precedent; future phases default back to atomic-per-task unless the PLAN explicitly bundles.
- **Out of scope, deferred to future versions**: init harness function in `run-tests.sh` exercising the 7 init fixture pairs (currently reference-only); standalone Node scanner port (carry-over from 1.10.0 deferred list); pre-commit hook template (§10.9.4 MAY); GitLab / CircleCI workflows; retroactive enforcement on fx-signal-agent.

## [1.10.0] — 2026-05-15

### Added

- **Spec §10.9 observability enforcement — local-first** (phase 14) — the `add-observability` skill bumps to `0.3.0` / `implements_spec: 0.3.0`. v1.10.0 ships the two §10.9 MUSTs (delta scan, baseline file) fully implemented + a §10.9.3 reference CI workflow as opt-in example. Migration 0011 installs only the local-enforcement layer; CI is left as a manual opt-in for advanced setups.
- **`scan --since-commit <ref>` flag** (§10.9.1) — limits the walk to files in `git diff --name-only <ref>...HEAD` (triple-dot, merge-base relative). Resolves `<ref>` to a 40-char SHA via `git rev-parse --verify`. Empty deltas still emit `.observability/delta.json` with zero counts — the machine-readable summary obligation is unconditional. Mutually exclusive with `--update-baseline`.
- **`scan --update-baseline` flag** (§10.9.2) — full-scan-only; atomically writes `.observability/baseline.json` to the spec-mandated canonical path with strict schema: `scanned_commit` always 40-char hex, `policy_hash` always `sha256:<64-hex>`, `module_roots` sorted by `(stack, path)`. Aborts if `policy.md` missing or repo has no commits.
- **`.observability/delta.json`** (§10.9.1) — per-PR machine-readable summary. Emitted unconditionally whenever `--since-commit` is set. Same `counts` + `high_confidence_gaps_by_checklist` shape as baseline, plus `since_commit` / `head_commit` / `files_walked` fields.
- **`.observability/baseline.json`** (§10.9.2) — canonical conformance state. Written only by `scan --update-baseline` (manual) and `scan-apply` success (automatic). Regular `scan` runs read but never rewrite the baseline (per spec §10.9.2 line 219).
- **`scan-apply/APPLY.md` Phase 6b** (§10.9.2) — regenerates `baseline.json` automatically after a successful apply. Skipped when zero findings were applied.
- **`add-observability/enforcement/README.md`** — local-first enforcement guide. Documents the canonical pre-PR command (`claude /add-observability scan --since-commit main`), how to interpret `delta.counts.high_confidence_gaps`, when to refresh baseline, suggested team norms (PR checklist line, pre-push muscle memory alias, monthly full-scan audit). Also documents the opt-in CI workflow path, threat model (pull_request vs pull_request_target trap), and baseline merge-conflict resolution.
- **Reference CI workflow `add-observability/enforcement/observability.yml.example`** (§10.9.3, opt-in only) — fully-spec-conformant GitHub Actions workflow with SHA-pinned actions (`actions/checkout@de0fac2…` v6.0.2, `marocchino/sticky-pull-request-comment@0ea0beb…` v3.0.4), env-var indirection for every `${{ }}` interpolation inside `run:` blocks, top-level `permissions: contents: read`, concurrency block, `pull_request` trigger (NEVER `pull_request_target`). NOT installed by migration 0011 in v1.10.0 — copied manually by projects with self-hosted GHA runners or post-v1.11.0 Node-scanner adopters.
- **Report frontmatter for scan reports** — `.scan-report.md` now declares `scope: full | delta` at the top, plus `since_commit` / `head_commit` / `scanned_at` for delta scans. Includes a delta banner under the H1 listing files walked (or "0 files changed" on empty deltas).
- **Migration `0011-observability-enforcement.md`** — promotes 1.9.3 → 1.10.0 in **4 steps** (local-only): (1) authors initial `.observability/baseline.json` via `claude /add-observability scan --update-baseline`, (2) bumps `observability.spec_version` 0.2.1 → 0.3.0 and adds the new `enforcement:` sub-block (`baseline:` + `pre_commit: optional` — **no `ci:` field**) to CLAUDE.md, (3) appends a per-PR enforcement section to CLAUDE.md documenting both the canonical command and how to interpret `delta.counts.high_confidence_gaps`, (4) bumps `.claude/skills/agentic-apps-workflow/SKILL.md` version. Hard pre-flight aborts on three preconditions (no observability metadata → "run init first"; no policy.md → "run init first"; no `claude` CLI → "install separately") rather than silent skips. Migration does NOT install the CI workflow.
- **`migrations/test-fixtures/0011/` with 6 sandboxed scenarios** — 01-fresh-apply (before-state idempotency for all 4 steps), 02-idempotent-reapply (after-state idempotency + jq schema-strictness check on baseline.json + assertion that NO CI workflow was installed), 03-no-observability-metadata (pre-flight 1 abort), 04-no-policy-md (pre-flight 2 abort), 05-baseline-already-present (Step 1 idempotency catches pre-existing v0.3.0 baseline), 06-no-claude-cli (`requires.tool.claude.verify` abort). `test_migration_0011()` stanza added to `run-tests.sh`. **6/6 pass.**
- **CONTRACT-VERIFICATION.md** gains a v0.3.0 §10.9 coverage matrix mapping each obligation to its load-bearing artefact and verification evidence.

### Notes

- **Local-first enforcement choice**: v1.10.0 ships §10.9.1 + §10.9.2 (the MUSTs) and treats §10.9.3 (the SHOULD) as opt-in. Rationale: Claude Code's CI installation isn't first-class on hosted GitHub runners as of 2026-05; running an LLM-driven scan in CI on every PR has cost, latency, determinism, and prompt-injection trade-offs that aren't worth it for most teams. The example workflow is shipped so adoption is one-`cp` away when the trade-offs change (v1.11.0 Node scanner port closes the install/cost/determinism gaps).
- **Phase 14 multi-AI review**: BLOCK (codex Q1 on three spec-conformance gaps) → REQUEST-CHANGES (gemini + Claude on CI security) → APPROVE after 21-item PLAN.md v2 revision. See `.planning/phases/14-spec-10-9-enforcement/14-REVIEWS.md`. Codex's BLOCK caught two genuinely load-bearing issues: empty-delta path was silently skipping `delta.json` emission, and the original baseline schema allowed `policy_hash: null` / `scanned_commit: "working-tree"` non-conformant placeholders. Both fixed in v1.10.0.
- **Post-review pivot to Option 4 (local-only)**: after the multi-AI review approved a "ship the CI workflow as the primary enforcement mechanism" PLAN, a course-correction pivoted to local-first. The shipped workflow file was renamed `observability.yml.example` and migration 0011 dropped its install step. The §10.9.3 spec obligation is SHOULD not MUST; shipping an example is defensible conformance at "example-only" level.
- **Out of scope, deferred**: pre-commit hook template (§10.9.4 MAY), standalone Node scanner port (closes the CI-feasibility gap), GitLab / CircleCI workflows, retroactive enforcement on fx-signal-agent, dashboard `baseline.json` rendering. Each tracked as a v1.11.0 follow-up.
- **Backward compatibility**: projects that do NOT run migration 0011 keep working at v1.9.3 — no breaking changes in scan/init/scan-apply behaviour at v0.3.0.
- **Init-blocker (resolved in v1.11.0)**: migration 0011's hard pre-flight aborted with "run init first" when observability metadata or `policy.md` was missing, but `add-observability/init/` was not yet shipped at v1.10.0. Projects starting at v1.9.3 with no prior observability state had no walkable path forward at v1.10.0 alone. **Resolved in v1.11.0** by shipping `add-observability/init/INIT.md` + per-stack templates; the v1.10.0 pre-flight messages now point at a real init command (see `[1.11.0]` above).

## [1.9.3] — 2026-05-13

### Added

- **GitNexus code-graph MCP integration (setup-only)** — new install script `templates/.claude/scripts/install-gitnexus.sh` registers the `gitnexus` MCP server in `~/.claude.json` and bumps the workflow scaffolder. Migration does NOT install gitnexus itself (verify-only — user runs `npm install -g gitnexus`) and does NOT invoke `gitnexus analyze` on any repo (helper script for that). Pre-flight: jq + node ≥ 18 + global gitnexus + valid `~/.claude.json` (or bootstraps if absent). Idempotency validates entry SHAPE (`command=gitnexus`, `args[0]=mcp`) — a malformed pre-existing entry warns + exits 4 (applied-with-warnings) per codex review BLOCK-2.
- **Companion rollback script** `templates/.claude/scripts/rollback-gitnexus.sh` — preserve-data: removes only MCP entry + version bump. Leaves `~/.gitnexus/`, the npm install, and per-repo skills/hooks/CLAUDE.md blocks untouched.
- **Helper script for user-initiated per-repo indexing** — `templates/.claude/scripts/index-family-repos.sh` supports `--family <name>`, `--all`, `--default-set`, `--help`. Default no-args behavior prints usage + explicit warnings about LLM calls (repository content sent to configured LLM provider) and PolyForm Noncommercial license terms. Curated `--default-set` covers 7 active-development repos.
- **Migration `0007-gitnexus-code-graph-integration.md`** — promotes 1.9.2 → 1.9.3 by running the install script. Setup-only scope: no `gitnexus analyze` runs during apply. ADR 0020 records the design rationale (multi-repo registry, MCP-native, license analysis).
- **Hand-built test fixtures for migration 0007** — `migrations/test-fixtures/0007/` with 16 sandboxed scenarios covering: old-node pre-flight, missing-gitnexus pre-flight, fresh apply, idempotent re-apply, existing canonical entry preserved, rollback preserves data, helper script usage / --help, claude CLI absence (no dependency), malformed `~/.claude.json` aborts, canonical entry shape, behavioral MCP startup smoke (codex B3), helper family/default-set dispatch (codex B3), no-claude-json bootstrap (codex F1), version-pin mismatch warn-but-proceed (gemini F1).
- **`test_migration_0007()` stanza** in `migrations/run-tests.sh` — 16 fixtures, each sandboxed via `HOME=$TMP/home` with stubbed `node`/`npm`/`gitnexus` binaries in `$HOME/bin` (PATH-prepended). Behavioral fixtures use a recording stub that logs invocation args to `$HOME/.gn-record` so the harness can assert what was called.

### License

**GitNexus is PolyForm Noncommercial 1.0.** Using GitNexus to help develop a commercial product (factiv, neuroflash) is the permitted "internal use" path. Embedding the GitNexus runtime in a shipped commercial product, or hosting it as a service for third parties, requires an enterprise license from akonlabs.com. See ADR 0020 for the full analysis. Running `npm install -g gitnexus` constitutes license acceptance.

### Notes

- **Phase 10 dogfood**: PLAN.md ran through codex + gemini before T1. Codex returned REQUEST-CHANGES (3 BLOCKs + 3 FLAGs) — all addressed in PLAN.md amendments. B1: MCP command uses `gitnexus mcp` (global binary), not `npx -y gitnexus@... mcp` — makes verify-only actually load-bearing. B2: idempotency validates entry shape, not just presence. B3: behavioral fixtures added (MCP startup smoke, helper dispatch). Plus codex F1 (no-claude-json case), F2 (info-disclosure threat row in plan), F3 (preconditions drift fixed), and gemini F1 (version-pin mismatch warn-but-proceed).
- **Scope reduction**: original draft of migration 0007 (in carry-over PR #12) ran `npm install -g gitnexus` + `gitnexus setup` + per-repo `gitnexus analyze` (30-90 min of LLM work) during apply. Phase 10 strips that to setup-only. Per-repo indexing becomes user-initiated.
- **Fixture count**: 16 (originally 18 — dropped 01-no-node and 17-no-jq because the harness can't sandbox missing-binary-on-host scenarios cleanly; those pre-flight checks are simple `command -v` lines verified by inspection).

## [1.9.2] — 2026-05-13

### Added

- **LLM wiki compiler integration** — new install script `templates/.claude/scripts/install-wiki-compiler.sh` (POSIX bash, sandbox-friendly via `$HOME`) symlinks the vendored `ussumant/llm-wiki-compiler` plugin into `~/.claude/plugins/`, scaffolds per-family `.knowledge/{raw,wiki}/` dirs + default `.wiki-compiler.json` configs, and appends a `## Knowledge wiki` section to each family's `CLAUDE.md`. Companion rollback script `templates/.claude/scripts/rollback-wiki-compiler.sh` preserves family data (removes only the host symlink + version bump).
- **Migration `0006-llm-wiki-builder-integration.md`** — promotes 1.9.1 → 1.9.2 by running the install script. Pre-flight verifies the vendored plugin exists at `~/Sourcecode/agenticapps/wiki-builder/plugin/` and SKILL.md is at 1.9.1. ABORT-on-wrong-target-symlink policy (won't silently repoint a forked install). Skip-when-CLAUDE.md-absent policy (won't create user files from scratch). Family heuristic: directory under `~/Sourcecode/` containing at least one immediate child git repo, excluding `personal|shared|archive`.
- **ADR 0019** — LLM wiki compiler integration. Records Andrej Karpathy's LLM Knowledge Base pattern, the per-family vs per-repo decision, why vendor instead of npm-install, the `.wiki-compiler.json` schema choice, and the threat model (symlink overwrites, supply-chain trust, plugin session hooks, preserve-data rollback).
- **Hand-built test fixtures for migration 0006** — `migrations/test-fixtures/0006/` with 15 sandboxed scenarios covering every decision branch: plugin-missing pre-flight, fresh install, idempotent re-apply, rollback, zero-families, existing-config-preserved, real-file collision (ABORT), correct-symlink idempotency, CLAUDE.md update idempotency, wrong-target symlink (ABORT, codex B2), missing-family-CLAUDE.md (skip-with-note, codex B3), non-family directory skipped via child-`.git` heuristic (codex F2), missing-plugins-parent (mkdir -p, codex F4), `.knowledge` exists as file (ABORT exit 3, codex F4), malformed existing config (preserve+warn, codex F4).
- **`test_migration_0006()` stanza** added to `migrations/run-tests.sh` — 15 fixtures, each sandboxed via `HOME=$TMP/home`. Strict line-presence stderr matching. Codex F1 sandbox-escape guard rejects any install script containing hardcoded real-home paths.

### Notes

- **Phase 09 dogfood**: PLAN.md ran through codex + gemini before T1. Codex returned REQUEST-CHANGES (3 BLOCKs + 4 FLAGs) — all addressed in PLAN.md amendments before execution. B1 (goal-vs-verify gap) → new T5b smoke test verifies plugin manifest parses, declares canonical commands, family configs parse, source globs resolve. B2 (wrong-target symlink) → ABORT policy locked. B3 (missing family CLAUDE.md) → skip-with-warning. Fixture count grew 9 → 15.
- **Scope reach**: migration 0006 touches three scope levels — host (`~/.claude/plugins/` symlink), family (`<family>/`-rooted scaffolding), per-project (SKILL.md version). This is intentional and follows the precedent of migration 0001 (global plugin installs).
- **Self-contained**: earlier draft of this migration assumed an old draft of 0005 had scaffolded `.knowledge/{raw,wiki}/` first. The shipped 0005 (multi-AI review enforcement) is unrelated; migration 0006 now owns the entire scaffolding chain.

## [1.9.1] — 2026-05-13

### Added

- **Multi-AI plan review enforcement gate** — new POSIX bash 3.2+ script `templates/.claude/hooks/multi-ai-review-gate.sh` (hook 6 in the programmatic-hooks taxonomy from ADR 0015). Fires as PreToolUse on `Edit|Write|MultiEdit`. Reads the active phase via `.planning/current-phase` symlink, looks for `*-PLAN.md` and `*-REVIEWS.md` with `find -maxdepth 2`, blocks (exit 2) when PLAN.md is present but REVIEWS.md is missing. Sub-100ms latency (measured: avg 22-48ms across all 11 fixture scenarios). Override surfaces are `GSD_SKIP_REVIEWS=1` (session-scoped escape) and `touch .planning/current-phase/multi-ai-review-skipped` (phase-scoped, committed audit trail). Edits to planning artifacts (`*PLAN.md`, `*REVIEWS.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `*CONTEXT.md`, `*RESEARCH.md`) bypass the gate to avoid chicken-and-egg deadlock.
- **Migration `0005-multi-ai-plan-review-enforcement.md`** — promotes 1.9.0 → 1.9.1 by installing hook 6, wiring it into `.claude/settings.json` PreToolUse hooks array (jq-based insert with idempotency guard), bumping `skill/SKILL.md` to `version: 1.9.1`, and recording the gate in `docs/workflow/ENFORCEMENT-PLAN.md` if vendored. Pre-flight checks for `/gsd-review` slash command installation and ≥2 reviewer CLIs from `gemini|codex|claude|coderabbit|opencode`. Three steps; each ships with idempotency check + rollback.
- **ADR 0018** — Multi-AI plan review enforcement. Documents the drift pattern observed in `factiv/cparx/.planning/phases/` (eight consecutive phases 04.9 → 05-handover produced PLAN.md but no REVIEWS.md), the choice to promote `/gsd-review` from optional gsd-patch slash command to enforced contract gate, the dual-override-surface design (env var + sentinel), and the trust-boundary at "REVIEWS.md exists" (not at reviewer-content quality).
- **Hand-built test fixtures for migration 0005** — `migrations/test-fixtures/0005/` with 11 pair-shaped scenarios covering every decision branch: no-active-phase, no-plans, plan-no-reviews (the canonical block), plan-with-reviews, stub-reviews (≤5 lines), env-override, sentinel-override, planning-artifact-edit, hostile-filename-edit (proves shell-injection inertness), non-Edit-tool, and MultiEdit-tool (proves matcher closure).
- **`test_migration_0005()` stanza** added to `migrations/run-tests.sh` — 11 assertions, strict line-presence stderr matching, mktemp-per-fixture isolation. FAIL-not-SKIP if the hook script is missing (the script IS the migration's artifact under test). Fixture 09 additionally asserts `/tmp/HOSTILE_MARKER` survives the run as evidence that `$(rm -rf …)` in `tool_input.file_path` is never command-substituted.
- **Contract entry** — `templates/config-hooks.json` gains a `pre_execute_gates.multi_ai_plan_review` block; `docs/ENFORCEMENT-PLAN.md` gains a row in the planning-gates table that references the gate's evidence requirement (`{padded_phase}-REVIEWS.md` exists and is non-stub).

### Notes

- **Phase 08 dogfood**: the gate was exercised on its own creation phase. Multi-AI plan review (`08-REVIEWS.md`) produced by **codex + gemini** — codex returned REQUEST-CHANGES with 4 BLOCKs and 3 FLAGs, all addressed in PLAN.md amendments before T1 execution (MultiEdit added to matcher per B3, fixture 09 redesigned to actually exercise the parsing branch per B4, T6b added for live apply/rollback verification per B1, T-dogfood added for self-test per B2).
- **Subtractive TDD pattern**: hook script was drafted in the PR #12 carry-over and cherry-picked into phase 08. The RED→GREEN sequence proves the hook (existing) matches the fixture decision matrix (new). Same pattern as migration 0010.
- **Bash 3.2 compatibility**: hook script + harness target macOS bash 3.2.57 explicitly. Empty-array expansion guarded with `${env_args[@]+"${env_args[@]}"}`. Latency benchmark uses python3 brackets around N=100 batches to amortize timing overhead.

## [1.9.0] — 2026-05-13

### Added

- **Post-processor for inlined GSD section markers** — new POSIX bash 3.2+ script `templates/.claude/hooks/normalize-claude-md.sh` walks CLAUDE.md and rewrites every `<!-- GSD:{slug}-start source:{label} -->...<!-- GSD:{slug}-end -->` block into a 3-line self-closing reference (`<!-- GSD:{slug} source:{label} /-->` + `## {Heading}` + `See [`{path}`](./{path}) — auto-synced.`). Resolves `source:` labels to actual `.planning/`-rooted file paths. Idempotent. Source-existence-safe (preserves blocks with missing sources). Special-cases the `workflow` block (removed entirely once 0009's `.claude/claude-md/workflow.md` exists) and the `profile` block (no `source:` attr; emits `/gsd-profile-user` placeholder). Collapses 2+ consecutive blanks to 1 (mirrors gsd-tools' own normalization).
- **PostToolUse hook registration** — `templates/claude-settings.json` gains "Hook 6 — Normalize CLAUDE.md after Edit/Write (migration 0010)" matching `Edit|Write|MultiEdit`. Defends against future `gsd-tools generate-claude-md` invocations that would re-inflate the marker blocks.
- **Migration `0010-post-process-gsd-sections.md`** — promotes 1.8.0 → 1.9.0 by vendoring the post-processor into consumer projects, registering the PostToolUse hook in `.claude/settings.json` (jq-based insert with hand-edit fallback), and one-shot normalizing existing CLAUDE.md with user-confirmed diff preview. 4 steps; each ships with idempotency check + rollback.
- **ADR 0022** — Post-process GSD section markers via downstream hook (not upstream patch). Documents the source-identification finding (`gsd-tools generate-claude-md` from `~/.claude/get-shit-done/`, owned by upstream `pi-agentic-apps-workflow` family), the post-processor-vs-upstream-patch trade-off, the 0009/0010 boundary (disjoint marker shapes — no regex overlap), and the `--auto` recommendation for users running `gsd-tools` directly.
- **Hand-built test fixtures for migration 0010** — `migrations/test-fixtures/0010/` with 5 pair-shaped scenarios (`fresh` no-op, `inlined-7-sections` full normalization, `inlined-source-missing` safety preservation, `with-0009-vendored` 0009 coexistence, `cparx-shape` ≤200L line-count target). Unlike 0009's fixtures (idempotency-check-only), 0010's harness actually runs the script and diffs against expected goldens.
- **`test_migration_0010()` stanza** added to `migrations/run-tests.sh` — 7 assertions covering all 5 fixtures plus idempotency double-run and missing-input exit code. Diverges from 0001/0009's SKIP-on-missing pattern: 0010 FAILs the harness when the script is absent, because the script IS the migration's artifact under test.

### Notes

- **cparx-shape fixture** (~339L representative input) normalizes to 147L — well under the ≤200L target.
- **Real cparx (647L)** end-to-end projection: 647 → 0009 → ~496L → 0010 → ~270L. The remaining ~70L gap to the user's stated ~165L target is non-GSD content (gstack skill table, anti-patterns list, repo-structure ASCII diagram, project-specific notes — ~232L of non-marker content). Closing the gap requires a follow-up phase trimming non-GSD content; out of scope for 0010.
- **Upstream patch recommended as follow-up** — ADR 0022 captures the rationale for shipping the downstream post-processor first while leaving a TODO for an upstream PR to `pi-agentic-apps-workflow` adding a `--reference-mode` flag to `gsd-tools generate-claude-md`. After upstream lands, 0010's post-processor becomes defense-in-depth.

## [1.8.0] — 2026-05-13

### Added

- **Vendored CLAUDE.md workflow block** — `templates/.claude/claude-md/workflow.md` is the new canonical location for the Superpowers/GSD/gstack hooks, commitment ritual, rationalization table, and 13 Red Flags. Each consumer project gets `<repo>/.claude/claude-md/workflow.md` vendored on first install (via patched migration 0000) or on upgrade (via migration 0009). CLAUDE.md links to that path with a 5-line reference block instead of inlining ~150 lines. Self-contained — repo never references the meta-repo at runtime.
- **ADR 0021** — Vendor the workflow block as a per-repo file instead of inlining it into CLAUDE.md. Documents the inline → vendor pivot, alternatives rejected (symlink, runtime fetch, `@import`), and why the meta-repo is never referenced at runtime. Captures the "patch 0000 in-place" decision that lets fresh installs go straight to vendored state.
- **Migration `0009-vendor-claude-md-sections.md`** — promotes 1.6.0 → 1.8.0 (re-anchored in Phase 11; the runner matches on `from_version` only, so the 1.6 → 1.8 jump skipping 1.7 is supported) by vendoring the workflow block, adding a reference to CLAUDE.md, and detecting + (with user confirmation) extracting any pre-existing inlined block. Three-way pick on customised inlined blocks: replace-with-canonical / preserve-as-vendored / skip. Five steps; each ships with idempotency check + rollback.
- **Hand-built test fixtures for migration 0009** — `migrations/test-fixtures/0009/` with five scenarios (fresh, inlined-pristine, inlined-customised, after-vendored, after-idempotent). 29 assertions cover every step's idempotency check across every scenario. Distinct from migration 0001's git-ref-extracted fixtures because 0009's "pre-existing inlined block" state isn't in claude-workflow's own history.

### Changed

- **Migration `0000-baseline.md` Step 4 patched in-place** — previously `cat`-ed `templates/claude-md-sections.md` directly into CLAUDE.md (the root cause of cparx 646L and fx-signal-agent 372L). Now writes `.claude/claude-md/workflow.md` from the vendored template + appends a 5-line `## Workflow` reference section to CLAUDE.md. Legitimate in-place patch because 0000's pre-flight already refuses re-execution against existing installs. Note in the patched step documents the rationale.
- **`templates/claude-md-sections.md` H1 rewritten** — was `# CLAUDE.md Sections — paste into your project's CLAUDE.md`, which is the literal smoking-gun line found in fx-signal-agent's CLAUDE.md proving the file was pasted verbatim. New H1 (`# DEPRECATED — vendored as .claude/claude-md/workflow.md since v1.8.0`) carries a "do not paste" banner and explains migration 0009's detection logic. The file is retained for migration 0009's grep-detection of pre-existing pastes in older repos.
- **`setup/SKILL.md`** — post-setup summary now lists `.claude/claude-md/workflow.md` as a created file. Migration history table updated with 0002, 0004–0007, and 0009 entries (was stale at 0001). Notes the v1.8.0 vendor-mode pivot.
- **`update/SKILL.md` Step 5** — adds a "divergence variant" of the per-step Apply prompt: when a vendored file's local copy byte-differs from the canonical scaffolder source, present a 3-way pick (Replace / Keep / Vendor-local). Default to Keep (diverging is usually intentional). Failure modes table extended with vendored-file divergence and inlined-block extraction-ambiguous outcomes.
- **`migrations/README.md`** — added a Migration index table near the top showing the current chain and the v1.8.0 vendor-mode property of 0000.
- **`skill/SKILL.md`** frontmatter version bumped 1.6.0 → 1.8.0 (re-anchored in Phase 11; the prior frontmatter `1.7.0 → 1.8.0` was retired alongside the [1.5.1]/[1.6.0]/[1.7.0] slots).
- **`migrations/run-tests.sh`** — added `test_migration_0009()` stanza (29 assertions). Existing `test_migration_0001()` kept as-is; its 8 pre-existing FAILs (caused by `git merge-base` resolving to a post-0001-merge commit) are unrelated to this phase and tracked separately.

### Notes

- **fx-signal-agent** drops from 372 lines to ~201 after applying migration 0009 (the inlined block extraction is the single largest reduction).
- **cparx** drops from 646 lines to ~496 after migration 0009. Getting it ≤200L requires migration 0010 (GSD compiler reference-mode for auto-managed PROJECT/STACK/CONVENTIONS/ARCHITECTURE sections), queued as a separate phase. ADR 0021 records why 0010 is not bundled into this release.
- Existing 1.6.0 projects pick up the fix via `/update-agenticapps-workflow`; the migration runtime walks them through the inlined-block extraction prompt with diff preview.

## [1.7.0] — Skipped (no migration)

This version slot is intentionally skipped by the migration chain. Migration
0009 promotes `1.6.0 → 1.8.0` directly — the runner matches on
`from_version` only, so `to_version` need not be `from_version + 0.1`. See
`migrations/README.md` "Application order" note 3.

The previous draft of this entry described the GitNexus code-graph
integration that was once planned to ship as migration 0007 at
`1.6.0 → 1.7.0`. After Phase 10's scope reduction and Phase 11's chain
rebase, GitNexus actually shipped via migration 0007 at `1.9.2 → 1.9.3`.
See **[1.9.3]** for the content that landed.

## [1.6.0] — 2026-05-13

### Added

- **Coverage Matrix Page** — agenticapps-dashboard ships a new `/coverage`
  route, a cross-family knowledge-layer freshness dashboard. Workflow-repo
  surface only; no consumer-project state changes. ADR 0023.
- **Migration `0008-coverage-matrix-page.md`** — promotes `1.5.0 → 1.6.0`.
  Re-anchored in Phase 11 from a previously-planned `1.7.0 → 1.8.0` slot;
  the prior chain had a gap at `1.5 → 1.7` and a `0008/0009` collision at
  `1.7 → 1.8`. Re-anchoring closed both without touching shipped
  migrations 0010 / 0005 / 0006 / 0007.

### Notes

- The previous draft of this entry described the LLM wiki compiler
  integration that was once planned to ship as migration 0006 at
  `1.5.1 → 1.6.0`. After Phase 11's chain rebase, the wiki compiler
  actually shipped via migration 0006 at `1.9.1 → 1.9.2`. See **[1.9.2]**
  for the content that landed.

## [1.5.1] — Skipped (no migration)

This version slot is intentionally skipped by the migration chain. After
Phase 11's chain rebase, migration `0008` promotes `1.5.0 → 1.6.0`
directly, so no migration claims `1.5.1` as its `to_version`.

The previous draft of this entry described the multi-AI plan review
enforcement gate that was once planned to ship as migration 0005 at
`1.5.0 → 1.5.1`. After the rebase, the gate actually shipped via
migration 0005 at `1.9.0 → 1.9.1`. See **[1.9.1]** for the content that
landed.

## [1.5.0] — 2026-05-13

### Fixed

- **`.claude/settings.json` is now installed at baseline.** Migration
  `0000-baseline.md` gains a new Step 6 that bootstraps the file as
  `{}` if missing. Previously, no migration in the chain ever created
  it — `migrations/0004-programmatic-hooks-architecture-audit.md`
  asserted its existence at pre-flight but baseline never installed
  it, so any 1.3.0 project trying to update to 1.4.0 hit a hard fail.
  Migration 0004's pre-flight now also self-heals (creates the file if
  missing) as belt-and-braces for older projects baselined before this
  fix. Reported in
  [agenticapps-eu/claude-workflow#8](https://github.com/agenticapps-eu/claude-workflow/issues/8).

### Added

- **`add-observability` skill** — Claude Code implementation of
  AgenticApps core spec §10 v0.2.1 (observability contract). Three
  subcommands:
  - `init` — greenfield: scaffold the wrapper module + middleware into
    each detected stack.
  - `scan` — brownfield: audit conformance against §10.4 mandatory
    instrumentation points; produce `.scan-report.md` with findings
    classified high / medium / low confidence.
  - `scan-apply` — apply high-confidence gaps with **per-file or
    per-batch consent in chat** (§10.7 fourth bullet). Edit-tool
    content-matching is the safety net; stale findings flagged for
    re-scan rather than fuzzy-merged.
- **Five stack templates** ship with the skill at
  `add-observability/templates/`:
  - `ts-cloudflare-worker` (Workers fetch / scheduled / queue handlers)
  - `ts-cloudflare-pages` (Pages Functions; inherits worker wrapper)
  - `ts-supabase-edge` (Deno; uses `npm:@sentry/deno`)
  - `ts-react-vite` (browser; module-level span stack +
    `ObservabilityErrorBoundary` for React)
  - `go-fly-http` (chi / std net/http; `context.Context` propagation)
- **61 contract tests across 4 runtimes** ship with the templates and
  pass against materialized-from-template wrappers (vitest+jsdom for
  TS, deno test for Deno, go test for Go).
- **Migration `0002-observability-spec-0.2.1.md`** — installs the skill
  on `/update-agenticapps-workflow` for projects on 1.4.x. Steps:
  install skill, bump version, add `/add-observability` reference to
  CLAUDE.md. Non-destructive — does not instrument any source code;
  the user explicitly invokes `init` / `scan-apply` afterward.

### Spec context

- This release implements AgenticApps core spec §10 v0.2.1.
  v0.2.1 patches over v0.2.0:
  - §10.5 — added a note clarifying interaction with framework-level
    recoverer middleware (mount inside Recoverer).
  - §10.7.1 — clarified that target paths resolve against the
    *language module root* (`go.mod`, `package.json`, `Cargo.toml`,
    `supabase/config.toml`), not the repo root. Supports monorepos and
    non-root manifests (e.g. cparx's `backend/go.mod`).
- The spec text itself lives in the (still-pending) `agenticapps-workflow-core` repo;
  this release ships the implementation that satisfies it. The skill's
  `SKILL.md` declares `implements_spec: 0.2.1` for forward-compat
  conformance tracking.

### Pilot

- **cparx pilot (2026-05-10)** validated the templates end-to-end
  against the cparx Go backend. `go build ./...`, `go vet ./...`, and
  the existing test suite all passed after the templates were applied.
  Six gaps surfaced and were resolved in v0.2.1 (G1 module-root
  resolution, G2 transport composition for custom RoundTrippers, G4
  recoverer ordering, G6 contract test fixtures shipping with each
  template). G3 detached-goroutine instrumentation and G5 RequestID
  coexistence deferred to v0.3.0+. Pilot artifacts live in the design
  folder; the cparx adoption itself happens via the project's own
  feature-branch + GSD workflow.

### Changed

- `skill/SKILL.md` frontmatter version bumped 1.4.0 → 1.5.0.

## [1.4.0] — 2026-05-03

### Added

- **Programmatic hooks layer (5 hooks)** — deterministic enforcement at
  the tool-call boundary. Complements (does not replace) the conceptual
  CLAUDE.md prose layer. Closes the "prose degrades on compaction"
  failure mode that Sah and Damle's articles identify.
  - **Hook 1 — Database Sentinel** (`PreToolUse: Bash|Edit|Write`) —
    blocks `DROP/TRUNCATE TABLE`, `DELETE FROM` without `WHERE`, edits
    to `.env*`, edits to `migrations/*` without phase approval.
  - **Hook 2 — Design Shotgun Pre-Flight Gate** (`PreToolUse:
    Edit|Write`) — blocks design-surface edits without
    `.planning/current-phase/design-shotgun-passed` sentinel.
  - **Hook 3 — Phase Sentinel** (`Stop`, prompt-type, Haiku 4.5) —
    compares `.planning/current-phase/checklist.md` against the
    conversation; blocks `Stop` if items remain unchecked.
  - **Hook 4 — Skill Router Audit Log** (`PostToolUse` + `SessionStart`) —
    JSONL log of every skill invocation to
    `.planning/skill-observations/skill-router-{date}.jsonl`; warm
    context on each new session via tail-20.
  - **Hook 5 — Commitment Re-Injector** (`SessionStart matcher: compact`,
    GLOBAL) — re-injects `head -50 CLAUDE.md` + current-phase
    `COMMITMENT.md` after compaction. cwd-aware: no-ops on non-AgenticApps
    projects.
  - 43 bats tests across 4 hook test files; all green. `bin/check-hooks.sh`
    validates installation.
- **Architecture audit scheduling** — two complementary mechanisms with
  shared snooze contract:
  - **In-session SessionStart hook** (`templates/.claude/hooks/architecture-audit-check.sh`)
    nags when last audit > 7 days. Honors
    `.planning/audits/.snooze-until-{YYYY-MM-DD}` markers.
  - **Out-of-session weekly cron** (`bin/agenticapps-architecture-cron.sh`)
    Mondays 09:00 local. Reads `~/.agenticapps/dashboard/registry.json`
    `tags: ["active"]` (heuristic fallback for empty registry). Files
    Linear issues with reminder, falls back to log file.
  - Two installers: `bin/install-architecture-cron.sh` (macOS LaunchAgent)
    and `bin/install-systemd-architecture-cron.sh` (Linux systemd-user).
  - Plist + systemd unit templates with `{SCAFFOLDER_BIN}` / `{HOME}`
    placeholders that installers `sed`-substitute.
- **Mattpocock skills installed** — `mattpocock-improve-architecture` +
  `mattpocock-grill-with-docs` cloned from upstream into
  `~/.claude/skills/`. Closes the cross-PR architectural drift gap.
- **`templates/gsd-patches/`** — mirror of the rogs.me-style canonical
  patch storage at `~/.config/gsd-patches/`. Cross-machine
  reproducibility: clone scaffolder → copy → `bin/sync` to apply patches
  to the live `~/.claude/get-shit-done/` install.
- **GSD bug fix** — `~/.claude/get-shit-done/workflows/review.md:169`
  patched to strip `2>/dev/null` from the `opencode run` invocation
  (rogs.me's Bug 1). Bug 2 (`--no-input` flag) not present in this
  install. Bug 3 (sequential reviewers) skipped to respect upstream's
  explicit "(not parallel — avoid rate limits)" comment.
- **`migrations/0004-programmatic-hooks-architecture-audit.md`** —
  applies hooks + settings merge + version bump to v1.3.0 projects via
  `/update-agenticapps-workflow`.
- **4 new ADRs:** 0014 (GSD bug fixes), 0015 (programmatic hooks layer),
  0016 (mattpocock architecture audit), 0017 (audit scheduling).

### Changed

- **`templates/claude-settings.json`** — added entries for Hooks 1–4 +
  architecture-audit-check (5 entries total). Hook 5 is global,
  not project-scoped.
- **`docs/ENFORCEMENT-PLAN.md`** — new "Two-layer enforcement:
  programmatic + conceptual" section between Finishing gates and the
  Commitment ritual. Documents the split rule, lists all 6 hooks,
  points at `bin/check-hooks.sh`.
- **`skill/SKILL.md`** version bumped 1.3.0 → 1.4.0.

### Migration path for existing projects (v1.3.0 → v1.4.0)

```bash
# 1. Pull the latest scaffolder + re-run install.sh (in case new skill
#    subdirs were added; v1.4.0 didn't add any but the discipline holds)
cd ~/.claude/skills/agenticapps-workflow && git pull && ./install.sh && cd -

# 2. Install mattpocock skills (required by 0004 pre-flight)
git clone https://github.com/mattpocock/skills /tmp/mattpocock-skills
mkdir -p ~/.claude/skills/mattpocock-improve-architecture ~/.claude/skills/mattpocock-grill-with-docs
cp -r /tmp/mattpocock-skills/skills/engineering/improve-codebase-architecture/. ~/.claude/skills/mattpocock-improve-architecture/
cp -r /tmp/mattpocock-skills/skills/engineering/grill-with-docs/. ~/.claude/skills/mattpocock-grill-with-docs/

# 3. Preview, then apply
cd <your-project>
claude "/update-agenticapps-workflow --dry-run"
claude "/update-agenticapps-workflow"

# 4. Install Hook 5 (Commitment Re-Injector) GLOBALLY (one-time per machine)
cp ~/.claude/skills/agenticapps-workflow/templates/global-hooks/commitment-reinject.sh \
   ~/.claude/hooks/commitment-reinject.sh 2>/dev/null \
  || echo "TODO: Hook 5 will live at templates/global-hooks/ once setup-skill installs it; for now copy from your local Claude Code session that ran P2A"
chmod +x ~/.claude/hooks/commitment-reinject.sh
# Then add SessionStart matcher: compact entry to ~/.claude/settings.json

# 5. Install the weekly cron (optional but recommended)
~/.claude/skills/agenticapps-workflow/bin/install-architecture-cron.sh   # macOS
# OR
~/.claude/skills/agenticapps-workflow/bin/install-systemd-architecture-cron.sh   # Linux
```

### Removed

Nothing. v1.4.0 is purely additive.

## [1.3.0] — 2026-05-03

### Added

- **Backend language routing for Go** — phases that touch `*.go` files
  auto-trigger `samber:cc-skills-golang` (40+ Go skills with measured eval
  data) and `netresearch:go-development-skill` (production resilience
  patterns: retry/backoff/graceful-shutdown/observability). Per-project
  install — non-Go repos don't pay the context cost. See README
  § "Per-language skill packs."
- **`impeccable:critique` as pre-phase design gate** — runs after
  `gstack:/design-shotgun`, scores each variant against ~24 AI-slop
  anti-patterns, eliminates sub-bar variants before the user picks. Score
  recorded in UI-SPEC.md.
- **`impeccable:audit` as finishing gate** — runs against deployed
  frontend before branch close. Red findings BLOCK close.
- **`database-sentinel:audit` as security sub-gate** — fires under existing
  `gstack:/cso` when the phase touches Supabase / Postgres / MongoDB.
  Output: `DB-AUDIT.md`. Critical / High findings BLOCK branch close
  unless accepted via the new `templates/adr-db-security-acceptance.md`
  ADR template.
- **`database-sentinel:audit` (full-surface) as pre-launch finishing gate**
  — runs before any AgenticApps client app goes live. Zero Critical / zero
  High required to clear.
- **Versioned migration framework** — `migrations/` directory holds
  numbered migration files (`NNNN-slug.md`) with frontmatter, idempotency
  checks, pre-conditions, apply blocks, and per-step rollback. Each
  migration brings projects from one version to the next non-destructively.
- **`update-agenticapps-workflow` skill** — applies pending migrations to
  an installed project. Detect installed version → find pending → show
  plan → pre-flight (skill installs) → apply each step (idempotency /
  diff / confirm / apply / commit) → summary. Supports `--dry-run`,
  `--migration N`, `--from V` flags.
- **`setup-agenticapps-workflow` skill REWRITTEN** — now applies all
  migrations from `0000-baseline.md` forward. Eliminates the previous
  "setup and any future update would maintain divergent shapes" code-path
  bug. Setup and update share one runtime.
- **`migrations/0000-baseline.md`** — codifies the v1.2.0 starting state
  as a 6-step migration (skill copy, workflow-config substitution, hooks
  config, CLAUDE.md append, optional global CLAUDE.md, version bump).
- **`migrations/0001-go-impeccable-database-sentinel.md`** — codifies
  this release's deltas as a 10-step migration with deterministic `jq`
  apply commands for JSON inserts.
- **`migrations/run-tests.sh`** — TDD test harness using git refs as
  fixtures. Verifies every migration step's idempotency check behaves
  correctly against before-state and after-state. 20/20 PASS for 0001.
- **`docs/decisions/0010..0013`** — four new ADRs documenting the Go
  routing, impeccable, database-sentinel, and migration framework
  decisions with their rejected alternatives.
- **`templates/adr-db-security-acceptance.md`** — standalone ADR template
  for accepting Critical/High `database-sentinel` findings (time-boxed,
  compensating control required, single owner).
- **`skill/SKILL.md` frontmatter `version: 1.3.0`** — installed version
  is now recorded explicitly. `update-agenticapps-workflow` reads this
  field to determine pending migrations.
- **`install.sh`** — bootstraps Claude Code's skill discovery by
  symlinking `skill/`, `setup/`, `update/` subdirectories out to their
  canonical `~/.claude/skills/<name>/` paths. Idempotent. Required after
  initial clone AND after every `git pull` that adds new skill subdirs.
  Fixes a long-standing bug where `/setup-agenticapps-workflow` and the
  new `/update-agenticapps-workflow` weren't actually registered as
  slash commands (the loader scans one level deep; this repo nests
  skills two levels deep for logical grouping). README install steps
  now invoke `install.sh` automatically.

### Changed

- **Pre-Phase Hook 1** in `templates/claude-md-sections.md` — expanded to
  require `impeccable:critique` against each `/design-shotgun` variant
  before the user picks.
- **Post-Phase Hook 8** in `templates/claude-md-sections.md` — expanded to
  require `database-sentinel:audit` when the phase touches supported
  databases. BLOCK on Critical / High unresolved findings.
- **`templates/workflow-config.md`** — added "Backend language routing"
  section; widened `cso` Post-Phase row to name database-sentinel +
  Supabase/Postgres/MongoDB scope + BLOCK semantics.
- **`templates/config-hooks.json`** — added `pre_phase.design_critique`,
  `post_phase.security.sub_gates[]` (with database-sentinel),
  `finishing.impeccable_audit`, `finishing.db_pre_launch_audit`. Schema
  now uses `sub_gates` arrays (new pattern; documented in ENFORCEMENT-PLAN.md).
- **`docs/ENFORCEMENT-PLAN.md`** — new "Language-specific code-quality
  gates" subsection (extension of post-phase Stage 2); new post-phase
  database-sentinel row; new pre-phase impeccable critique row.

### Migration path for existing projects

Projects on v1.2.0 upgrade to v1.3.0 by:

```bash
# Pull the latest scaffolder AND re-run install.sh (idempotent — required
# because v1.3.0 introduces a new update/ skill subdir that needs symlinking)
cd ~/.claude/skills/agenticapps-workflow && git pull && ./install.sh && cd -

# Preview, then apply
cd <your-project>
claude "/update-agenticapps-workflow --dry-run"
claude "/update-agenticapps-workflow"
```

Migration `0001-go-impeccable-database-sentinel.md` handles all 10 deltas
from this release. Pre-flight will prompt to install impeccable +
database-sentinel skills if missing.

### Removed

Nothing. This release is purely additive. All v1.2.0 hooks continue to
fire as before.

## [1.2.0] — Pre-this-release baseline

The starting state codified by `migrations/0000-baseline.md`. Pre-1.3.0
projects have no `version` field in their installed
`.claude/skills/agentic-apps-workflow/SKILL.md`; the `update` skill
prompts for `--from 1.2.0` if it can't auto-detect.
