---
name: agentic-apps-workflow
version: 3.0.0
implements_spec: 1.0.0
description: |
  Enforces the spec-first development workflow using OpenSpec + Superpowers +
  gstack for any AgenticApps project. This skill MUST activate whenever Claude is
  asked to implement, build, code, fix, refactor, or design anything in the current
  project — regardless of whether the user explicitly mentions the workflow.
  Triggers on: "let's work on [issue]", "implement the [feature]", "build the
  [component]", "fix the [bug]", any task involving writing or changing code,
  creating architecture, or making technical decisions. The skill ensures every
  piece of work moves through the OpenSpec lifecycle (propose → validate →
  execute → archive) under the Superpowers execution discipline, and produces
  traceable decision artefacts. Use this even when the user just says "start
  working" or references a Linear issue number.
---

# AgenticApps Development Workflow — Enforcement Skill

**This is an enforcement skill, not documentation.** Its job is to make you
commit — publicly and in writing — to invoking the right OpenSpec, Superpowers,
and gstack skills in the right order. Once committed, the commitment principle
(Cialdini; Wharton GAIL 2025) keeps you consistent with what you said you'd do.

**Authoritative contract:** `docs/ENFORCEMENT-PLAN.md`. Read it if you
are unsure which skill gates which step. The lifecycle itself is explained in
`docs/WORKFLOW.md`.

**Front end: OpenSpec (spec §16–§19).** Planning is an OpenSpec *change*, not a
GSD phase. `openspec/specs/` is durable current truth, `openspec/changes/` are
in-flight deltas, `changes/archive/` is history. The CLI is bound upstream — run
`openspec --help` in the repo and use the verbs it reports; this prose is not
authoritative over the installed CLI. Execution discipline (TDD, evidence,
independent review) is unchanged Superpowers.

## Step 0 — The Commitment Ritual (NON-NEGOTIABLE)

As the FIRST user-facing output of your turn, before any tool call or
clarifying question, you MUST emit a `## Workflow commitment` block:

```
## Workflow commitment

I am using the agentic-apps-workflow skill for this task.
Task scope: {one-sentence description}
Task size: {tiny | small | medium | large}

Skills I will invoke, in order:
1. {skill-name} — {why it applies}
2. {skill-name} — {why it applies}
...

Post-phase gates (if applicable): {review | cso | qa}
Verification evidence I will produce: {list of artifacts}

Once I have stated this plan, I am committed to it. Deviating without
explicit user approval is a protocol violation.
```

Skipping this ritual is itself a protocol violation. You cannot rationalize
your way out of it — see the rationalization table below.

## Step 1 — Pick the task size, match the skill set

| Task size | Examples | Required skill invocations |
|---|---|---|
| **Tiny** (< 15 min) | Typo, config tweak, one-line fix | `superpowers:verification-before-completion` + commit. No change needed — the gate allows edits when none is open. |
| **Small** (15–60 min) | Single field, small bug | `superpowers:brainstorming` (3 bullets) → fix → `/review` → verification → commit |
| **Medium** (1–4 hours) | New endpoint, new component | Full lifecycle, lightweight ADR |
| **Large** (4+ hours) | New subsystem, major feature | Full lifecycle + detailed ADR + a spec delta per affected capability |

Anything Medium or larger opens an OpenSpec change. Tiny/Small work may proceed
without one — the §18 gate engages only once a change is open, mirroring §02's
out-of-phase permissiveness. That permission is for *incidental* edits, not a
loophole for shipping a feature without a spec.

## Step 2 — Route to the right lifecycle stage

The four stages (§17). `/opsx:*` are the OpenSpec-generated slash commands; the
plain `openspec …` verbs do the same work and are what a non-Claude agent uses.

| Stage | Entry point | When |
|---|---|---|
| 0 · explore | `/opsx:explore` | Open-ended idea, shape not yet clear |
| 1 · propose | `/opsx:propose` | Author proposal + design note + spec delta + tasks |
| 2 · validate | `openspec validate --all`, then `run-plan-review.sh <slug>` | **Before any code.** Both must pass. |
| 3 · execute | `/opsx:apply` + Superpowers | Implement the tasks under the retained gates |
| 4 · archive | `/opsx:archive` | Fold the delta into `specs/`, move the change to `archive/` |
| 5 · ship | `superpowers:finishing-a-development-branch` | The git commit + PR. **A separate act — `archive ≠ ship`.** |

Debugging is not a lifecycle stage: a bug investigation goes straight to
`superpowers:systematic-debugging`, and only opens a change if the fix changes
what the spec promises.

If you are about to Edit / Write / or run git commands on product code with no
active change and the task is Medium or larger, **stop**. Either open one, or
state in one sentence why this task genuinely needs no spec delta.

## Step 3 — Invoke the skills mapped to each lifecycle gate

This is the gate-to-skill map (§17). Every row is a commitment.

### Stage 1 — propose (conditional)

- Change adds a UI surface → gstack `/design-shotgun` (3–4 variants, boot dev
  server, preview via `/browse`); the pick and its rationale land in `design.md`.
- Change adds a UI surface with a design contract already in place →
  `impeccable:critique` instead.
- Change adds a new service / model / integration →
  `superpowers:brainstorming`; record ≥2 alternatives in `design.md`.

### Stage 2 — validate (ALWAYS, before any code)

- `openspec validate --all` MUST be green. This is what `spec-review` used to do
  after the fact; it is now a machine check done first.
- `run-plan-review.sh <change-slug>` MUST write `changes/<slug>/REVIEWS.md` with
  **≥2 independent other-vendor reviewers**. This is the retargeted ADR-0018
  multi-AI review: the reviewers critique the *change* — proposal, design note,
  spec delta — not a PLAN.md, and they do it before code exists. The cParX pilot
  reviewer caught a real semantic defect in a spec delta at exactly this point.
- Both clauses are enforced by the §18 change-gate. It will block your edits.
  That is the gate working, not a malfunction — go get the review.

### Stage 3 — execute (retained)

- Task with `tdd="true"` → `superpowers:test-driven-development`. Required
  evidence: atomic `test(RED): <desc>` commit followed by
  `feat(GREEN): <desc>` commit. Optional `refactor:` commit.
- Before every task completion →
  `superpowers:verification-before-completion`. Post grep / test / curl /
  screenshot evidence.
- Always, after tasks → `superpowers:requesting-code-review` in an independent
  context. `openspec validate` is a spec check, not a code review, and does
  **not** discharge this (§17). §07's independence rule still binds.
- Change touches auth / storage / request handling / secrets / an LLM trust
  boundary → gstack `/cso` → SECURITY.md. Never conditional-away.
- Mid-change bug → `superpowers:systematic-debugging`. 4-phase protocol:
  Observe → Hypothesize → Test → Conclude.

### Stage 3 — execute (conditional)

- Touches schema / RLS / definer functions / storage policy →
  `database-sentinel:audit` → DB-AUDIT.md. Critical + High block.
- Ships user-visible behavior and a dev server is reachable → gstack `/qa`.
- Modifies a frontend component → boot the dev server + `/browse` screenshot,
  referenced in the commit message or the change dir.
- Alters a shipping visual surface → `impeccable:audit` (measured trial —
  ADR-0021 / MEASUREMENT.md; kept, not removed).
- TypeScript change introducing a new module's public API → `ts-declare-first`,
  now enforced as a **CI lint gate** rather than a per-task gate (§17).

### Stage 4/5 — archive, then ship

- Fold the delta into `openspec/specs/<capability>/spec.md`, then
  `openspec archive <slug> -y`. This produces **no git commit**.
- Feature branch ready to merge → `superpowers:finishing-a-development-branch`
  to compose the PR description. Link `changes/archive/<date>-<slug>/` and its
  evidence; reference the Linear issue id if there is one (§19 — loose
  convention, never a required sync).

## Step 4 — Record the decision

Non-trivial decisions (technology choice, architecture trade-off, algorithm
design, UX direction) get an ADR at `docs/decisions/NNNN-short-title.md`:

```
# ADR-NNNN: [Title]
**Status**: Accepted  **Date**: [YYYY-MM-DD]  **Linear**: [ISSUE-ID]

## Context
[Why did this decision come up?]

## Decision
[What we chose and the key reasons]

## Alternatives Rejected
[What we didn't choose and why]

## Consequences
[What this means for future work]
```

## Rationalization Table — Check Before Skipping Anything

| If you think... | The reality is... |
|---|---|
| "This task is too small for the commitment ritual" | The ritual takes 15 seconds. Skipping it is how discipline erodes. Emit the block. |
| "Skill is obvious, no need to announce it" | The announcement IS the commitment. Announcement → consistency pressure → compliance. |
| "TDD is impractical for frontend" | Snapshot tests, `/browse` screenshot diffs, visual regression count as TDD. Write the test first. |
| "I've already thought about alternatives" | If you didn't write them down, you didn't consider them. List ≥2 in RESEARCH.md. |
| "The multi-AI change review is excessive — one model's spec delta is fine" | Different LLMs catch different blind spots, and this review runs *before code exists*, where a fix is cheapest. Run it. (cparx phases 04.9 → 05 silently dropped its ancestor for 8 phases — the failure mode ADR-0018 closes. The cParX pilot's reviewer then caught a real semantic defect in a spec delta on the very first change.) |
| "`openspec validate` is green, so the change is reviewed" | Validate is a schema/structure check. It cannot tell you the delta describes the wrong behavior. That is what the ≥2 reviewers are for — §17 requires both, and the §18 gate enforces both. |
| "Two-stage review is excessive" | Stage 1 catches spec drift, Stage 2 catches code-quality drift. Different failures, different agents. |
| "Dev server isn't worth booting for this change" | If you touched JSX/TSX, boot it. 30 seconds. |
| "The user explicitly said ship fast" | Acknowledge urgency, explain risk in one sentence, offer minimum discipline that protects the critical path. |

## 14 Red Flags — STOP → DELETE → RESTART

1. Code written before the test (for TDD tasks)
2. Test added after implementation
3. Test passes on first run — no RED observed
4. Cannot explain why the test should have failed
5. Tests marked for "later" addition
6. "Just this once" reasoning
7. Manual testing claimed as verification evidence
8. Two-stage review collapsed into one
9. Framing discipline as "ritual" or "ceremony"
10. Keeping pre-written code as "reference" while writing tests
11. Sunk-cost reasoning about deleting unverified code
12. Describing discipline as "dogmatic"
13. "This case is different because..."
14. Code written under an active change whose `REVIEWS.md` has < 2 reviewers

## Pressure-Test Scenarios — Self-Check

Before you skip any step, ask yourself:
- Would I skip this step if this code were running in production serving real users?
- Would a senior engineer reviewing this work accept the shortcut?
- Am I rationalizing? Check the rationalization table above.

If any answer gives you pause, follow the protocol.

## Verification Check (after a change is archived)

Run this to prove the workflow actually fired. `$SLUG` is the change slug; a
just-archived change lives at `openspec/changes/archive/<date>-$SLUG/`.

```bash
CH=$(ls -d openspec/changes/archive/*"$SLUG" 2>/dev/null | tail -1)

# The spec slot states the new truth (the delta was folded, not just moved)
openspec validate --all

# Multi-AI review evidence, produced BEFORE code (>=2 independent reviewers)
grep -ciE '^##[[:space:]]*reviewer' "$CH/REVIEWS.md"

# TDD tasks produced RED + GREEN commits
git log --oneline "$BASE"..HEAD | grep -cE "^[a-f0-9]+ (test|feat)\("

# Independent Stage-2 code review happened (validate does not discharge it)
grep -rl "Stage 2" "$CH"

# Every task in the change is checked off
grep -c '^- \[ \]' "$CH/tasks.md"     # expect 0

# The gate agrees the repo is clean
bash ~/.agenticapps/bin/openspec-change-gate.sh --ci
```

If the reviewer count is < 2, or `tasks.md` still has unchecked items, or
`--ci` is red, the change did NOT honor the enforcement plan. File this as a
process bug, update `docs/ENFORCEMENT-PLAN.md` to close the loophole, and
re-run the failed gate.

## Daily Quick Reference

1. `openspec list` — what changes are open, where did I leave off?
2. Check Linear — highest-priority unblocked issue?
3. Pull latest from base branch
4. Pick the task, emit the commitment ritual
5. Open or resume a change (`/opsx:propose`), or say why none is needed
6. Validate + get ≥2 reviews **before** writing code
7. Invoke the mapped Superpowers skills in order
8. Archive the change, then ship it — two separate acts
9. Update decision log + session-handoff at end of session

## Spec deltas (spec 1.0.0)

Per core spec §09, a host names every requirement it does not satisfy verbatim,
with rationale. Audited 2026-07-14 (ADR-0040); re-audited 2026-07-24 for the
1.0.0 OpenSpec front end (ADR-0044).

- **§16–§19 OpenSpec front end — satisfied.** The spec slot (§16) is bound
  upstream via `openspec init --tools claude --profile core`; the lifecycle and
  gate mapping (§17) are declared in `.planning/config.json`'s `lifecycle`
  block; the change-gate (§18) ships as `bin/openspec-change-gate.sh` with the
  full exit-code truth table verified by direct invocation, wired at PreToolUse
  plus a git pre-commit and CI floor; §19's Linear coupling is the documented
  loose convention (a change may reference an issue id; nothing synchronizes).
- **§18 self-gating — inherent, disclosed.** A `PreToolUse` hook is loaded at
  session start and cannot gate the session that installs it. §18 names this an
  inherent property rather than a defect and requires (a) a fresh session
  enforces it and (b) the gate is demonstrable by direct invocation with
  simulated payloads. Both hold. The pre-commit + CI floor is what actually
  guarantees the rule, including against a human editor.
- **§13 implicit trigger — not wired; now a lint gate.** `ts-declare-first`
  ships and its explicit trigger works. §17 demotes the discipline to a CI lint
  gate, which this host declares in the config's `lifecycle.execute.lint` block;
  the *implicit* trigger (detecting a new TypeScript module in a TS-primary
  project without being asked) is still not implemented. §13's Conformance
  section is SHOULD/MAY throughout, and this scaffolder is not itself a
  TypeScript project (no `package.json`), so `full` is preserved.
- **§14 prompt-injection — trivially conformant.** This scaffolder builds no
  LLM prompts from non-self-authored values, so §14's trigger condition cannot
  occur; §09 requires only that the host say so. The §14 generator for
  consuming projects is delegated to the `injection-guard` skill
  (agenticapps-observability 0.13.0, `implements_spec: 0.6.0`), gated by
  migration 0023's pre-flight.
- **§10 observability — delegated, not omitted.** Satisfied via the standalone
  `agenticapps-observability` skill (0.13.0, `implements_spec: 0.3.2`),
  consumed through its own install surface. A satisfied MUST per §09, not a
  delta; recorded here because the skill no longer ships from this repo
  (removed at 2.0.0, commit 217baec). Migration 0022 fails closed if absent.
- **§08 setup/update equivalence — satisfied via guarded snapshot, recorded for
  clarity.** §08 as amended at core 0.9.0 (upstream ADR-0018) makes the setup
  flow's *end state* normative, not the mechanism: setup MUST reach an end
  state equivalent to a full `0000`→latest replay, by either **replay** or
  **snapshot** (a prebuilt artifact assembled from the same migration sources,
  PROVIDED a drift guard runs in CI and fails the build when the artifact and
  the sources disagree). A host choosing snapshot MUST name its guard in its
  instruction file. This host uses snapshot: ADR-0036 replaced replay-on-setup
  because the chain contains prose and agent steps that cannot be
  shell-replayed. The named guard is **`migrations/check-snapshot-parity.sh`**,
  which runs in CI on every change and proves the snapshot and the
  `migrations/` sources agree — satisfying the amended §08's naming
  requirement. Before core 0.9.0 this was recorded as a genuine open delta:
  `spec/08-migration-format.md` carried `spec_version: 0.1.0` and said nothing
  about snapshots, so the letter of the pre-amendment text was unmet even
  though the guarantee it protects (one source of truth for the on-disk shape)
  was. Core 0.9.0 resolved it by making the guarded-snapshot strategy a named,
  conformant alternative to replay. A satisfied MUST per §09, not a delta;
  recorded here — like §10 above — because the mechanism differs from a naive
  reading of the section, and disclosure keeps the claim auditable.
- **§04 — a divergent copy ships alongside the canonical block.** §09 item 1 is
  satisfied: the canonical 13 are byte-identical here, at positions 1–13, in
  this file — the one carrying `implements_spec`. But the vendored workflow
  reference installed into every scaffolded project
  (`.claude/claude-md/workflow.md`, from `templates/`) carries its own 13-flag
  list under a reworded heading (`### 13 Red Flags — Trigger Automatic STOP →
  DELETE → RESTART`) with four flags reworded (1, 6, 12, 13 — e.g. `Any "just
  this once" reasoning` for canonical `"Just this once" reasoning`). That copy
  is what agents read at runtime. It is not a §09 item-1 violation — the spec
  binds the block to the host's instruction file, not to every downstream
  artifact — but it is unreconciled canonical prose and is disclosed rather
  than left silent. Reconciling it changes the payload of every scaffolded
  project and needs its own migration; tracked separately.

## Knowledge Capture — Ritual Tail (spec §15)

Transferable learnings must not die in a per-repo `session-handoff.md` that the
next session overwrites. This step routes them to a cross-repo memory: **one
Obsidian note per repo** in the operator's vault. It is the FINAL step of three
rituals — run it AFTER:

1. **Session handoff** — after `session-handoff.md` is written.
2. **Plan completion** — after the plan is marked complete in `.planning/`.
3. **Phase completion** — after the phase artifacts are committed.

The three trigger names above are canonical §15 prose and are kept verbatim.
Under the 1.0.0 OpenSpec front end they map onto the lifecycle as: *plan
completion* → the change's `tasks.md` is fully checked off; *phase completion* →
the change is archived (delta folded into `specs/`). A repo still running a
`.planning/` tree reads them literally.

The vault write is machine-local and MUST NEVER be committed to the repo, and
it MUST NEVER fail, block, or roll back the ritual that triggered it — on any
failure, print one warning line and continue.

Procedure:

1. Read `.planning/config.json` → `knowledge_capture`. **Skip** — print at most
   one info line (`knowledge-capture: skipped (<reason>)`) and continue the
   ritual — when the block is absent, `enabled` is `false`, or the parent
   folder of the `note` path does not exist (expand a leading `~` against
   `$HOME`). NEVER create the parent folder: an absent vault means "not this
   machine", not "set up the vault".
2. Distill **1–5 transferable learnings** from the ritual just completed. The
   bar: a learning qualifies only if it would change how you, another agent,
   or another host works next time — gotchas whose root cause generalizes,
   decision rationale with reusable trade-offs, tooling/workflow insights
   (what made the agent fast or slow), wrong assumptions and what corrected
   them. Status updates, restatements of the plan, repo facts already in
   ADRs/handoffs/CHANGELOGs, and filler do NOT qualify. **If nothing clears
   the bar, write nothing** — no empty log entries, no placeholders.
3. If the configured note does not exist, create it from this skeleton
   (canonical copy: `templates/obsidian-learnings-note.md` in the scaffolder;
   fill `<...>` and dates):

   ```markdown
   ---
   type: agentic-learnings
   repo: <repo-name>
   path: ~/Sourcecode/<org>/<repo-name>
   hosts: [claude]
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   ---

   # <repo-name> — Agentic Coding Learnings

   ## Key Learnings
   <!-- CURATED. Dedupe, merge, promote from the log, demote stale. ~10–20 items. -->

   ## Log
   <!-- APPEND-ONLY. Never edit or delete existing entries. Newest first. -->
   ```

4. Prepend a log entry at the TOP of `## Log` (the section is append-only:
   never edit or delete existing entries), heading exactly:
   `### YYYY-MM-DD — <handoff|plan|phase> — <short title> (claude)`,
   with the learnings as bullets.
5. Curate `## Key Learnings`: dedupe, merge related items, promote log entries
   that earned it, demote or remove stale ones. Target ~10–20 highest-value
   items — each a bolded short title plus one to three sentences carrying the
   transferable insight, not the status.
6. Update frontmatter: set `updated:` to today; ensure `claude` is listed in
   `hosts`.
7. Report to the user, in one or two lines, what was written (or why the step
   was skipped).

Vault safety (hard rules): touch ONLY the configured note — never other repos'
notes, the folder's `CLAUDE.md`, or anything else in the vault. Never write
secrets, tokens, URLs with embedded credentials, or client-confidential data —
redact before writing.
