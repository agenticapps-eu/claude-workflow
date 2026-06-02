# SPLIT-00 — Prerequisites: 1.21.0 downstream upgrade

> Gating conditions for the claude-workflow split into three repos. Nothing
> in `SPLIT-01-agenticapps-shared.md` or `SPLIT-02-agenticapps-observability.md`
> may start until every checkbox here is true.

## Why we're splitting (one-paragraph reminder)

Phase 26 (2026-06-01, PR #60) was 100% observability work — DEF-1, DEF-2,
DEF-3, F-2, CR-D, CR-E all lived in `add-observability/` or in observability-
specific migration scripts/fixtures — but it had to ship as a `claude-workflow`
PR because the two concerns share a repo. The D-10a deferral (1.20.1 bump
parked under `[Unreleased]` because the migration drift test would have failed)
is the visible symptom of the version coupling. The split lets each layer ship
on its own cadence, lets observability be used without the workflow (and vice
versa), and lets the implementation be swapped (other destination SDKs beyond
Sentry+Axiom).

## End-state repo map

| Repo | Purpose | Skill name(s) | Starts at |
|---|---|---|---|
| `agenticapps-eu/claude-workflow` (existing, slimmed) | Agentic discipline: GSD commands, planning skills, non-observability migrations, workflow SKILL.md | `agentic-apps-workflow`, `gsd-*` | 1.21.0 → 2.0.0 (major, signals the split) |
| `agenticapps-eu/agenticapps-shared` (NEW) | Migration runner, drift test, common helpers shared by both other repos | (none — infrastructure, no end-user skill) | 1.0.0 |
| `agenticapps-eu/agenticapps-observability` (NEW) | Observability scaffolder; pluggable destination adapters (Sentry+Axiom first-party, others addable) | `observability` (renamed from `add-observability`) | 0.11.0 (continues from 0.10.0) |

## Gating conditions — ALL must be true before SPLIT-01 starts

### Workflow side

- [ ] **claude-workflow 1.21.0 shipped to main** with a tagged release.
  Recommended 1.21.0 scope:
  - PR #60 deferred items closed:
    - **WR-01** (cosmetic `grep -c || echo "0"` bug in `run-template-tests.sh:633-634`)
    - **WR-02** (supabase-edge D-02a test cleanup in `finally` block)
    - **WR-03** (direct `buildSentryOptions` unit tests × 3 stacks)
    - **WR-04** (openrouter `src/index.ts` decision — use helper or tighten docs)
  - **PROJECT.md retroactive bootstrap** (still missing across phases — STATE.md
    keeps pointing at "does not yet exist")
  - **STATE.md + ROADMAP.md drift refresh** post-Phase-26 (multiple downstream
    audits found the same drift family)
  - **Milestone v1.19.0 archive** (currently 100% complete but not archived) and
    new milestone cycle opened
  - Optional: **preparatory file-level decoupling** to make the SPLIT-01/02
    moves cleaner (e.g., factor out anything in `bin/gsd-tools.cjs` that's
    pure migration-framework vs workflow-discipline)
- [ ] **1.21.0 has been live on main ≥ 7 days** with no follow-up patches.
  Cooling-off — we're not chasing a moving regression target during the split.

### Downstream side (factiv family)

- [ ] **cparx upgraded to 1.21.0** (Phase 13.1 + whatever brings to 1.21.0)
  - See: `~/Sourcecode/factiv/cparx/.planning/phases/13.1-*/` (when authored)
  - ~~Workflow installed marker matches: `.claude/skills/agentic-apps-workflow/SKILL.md` `version: 1.21.0`~~
  - **Pin-by-tag (D-07c):** Downstream pins to git tag **`v1.21.0`** / commit SHA
    of claude-workflow, NOT the installed `SKILL.md` version field. Under A2
    (tag-only release, no migration), `SKILL.md` stays at `1.20.0` — reading
    `SKILL.md version` would incorrectly indicate `1.20.0` to an auditor.
    The installed `SKILL.md version: 1.20.0` is **not** acceptable evidence
    of the 1.21.0 baseline. See D-07/A2 in 27-CONTEXT.md.
- [ ] **callbot upgraded to 1.21.0** (Phase 10 + ...)
  - See: `~/Sourcecode/factiv/callbot/.planning/phases/10-*/`
  - **Pin-by-tag:** same as cparx — pin to git tag `v1.21.0` / commit SHA,
    not to SKILL.md version (which stays 1.20.0 under A2).
- [ ] **fx-signal-agent upgraded to 1.21.0** (Phase 08 + ...)
  - See: `~/Sourcecode/factiv/fx-signal-agent/.planning/phases/08-*/`
  - **Pin-by-tag:** same as cparx — pin to git tag `v1.21.0` / commit SHA,
    not to SKILL.md version (which stays 1.20.0 under A2).
- [ ] **Each downstream project's observability tests pass post-upgrade**
  - Sentry events arrive in each per-env (dev, staging, prod where applicable)
  - No regression in alert wiring (callbot's Phase 13 alert verification stays
    GREEN; fx-signal-agent's Sentry monitor upserts still apply per-env)

> **DOWNSTREAM-EVIDENCE RULE (SC-8/SC-9, codex review finding):**
> Each downstream MUST record the source tag **`v1.21.0`** and the commit SHA
> of the installed workflow in a durable place — its phase doc, STATE file, or
> upgrade PR body — as proof-of-baseline. This is the only acceptable evidence
> that the downstream is running the 1.21.0 baseline.
>
> The installed `SKILL.md version` field is **NOT** acceptable evidence of the
> 1.21.0 baseline. Under the A2 (tag-only) release strategy, SKILL.md stays at
> `1.20.0` because no new migration was shipped with 1.21.0. An auditor reading
> only SKILL.md would conclude the downstream is at 1.20.0 — that would be
> wrong. The git tag `v1.21.0` + commit SHA is the authoritative version marker
> for this release.

### Cooling-off

- [ ] **All three downstream repos stable on 1.21.0 for ≥ 7 days** before
  SPLIT-01 starts. If anyone hits a hotfix on 1.21.x, the cooling-off clock
  resets — we don't want the split work compounding with a production-pressure
  patch.

## Execution order

1. **SPLIT-01-agenticapps-shared.md** — extract shared infrastructure FIRST.
   - Why first: `agenticapps-observability` will depend on the shared migration
     runner; the runner has to exist as an extractable artifact before
     observability can reference it.
2. **SPLIT-02-agenticapps-observability.md** — extract observability SECOND.
   - Depends on: `agenticapps-shared` published + consumable.
3. **Post-split claude-workflow follow-up** (no separate file — captured at
   the end of SPLIT-02): clean up references, mark legacy `add-observability`
   skill as an alias for `observability`, ship `claude-workflow 2.0.0` with
   the split as the breaking-change rationale.

## After-split downstream upgrade story

Each consuming project's `.claude/skills/` directory will eventually have
two version markers instead of one:

```
.claude/skills/
├── agentic-apps-workflow/SKILL.md     # claude-workflow version (e.g., 2.0.0)
└── observability/SKILL.md              # agenticapps-observability version (e.g., 0.12.0)
```

Two slash commands for upgrades, each independent:

```
/update-agenticapps-workflow            # applies pending workflow migrations
/update-observability                   # applies pending observability migrations
```

This means D-10a-style version coupling becomes structurally impossible —
each skill has its own drift test against its own migrations directory.

## Open questions for the user before SPLIT-01 starts

1. **Sharing mechanism for `agenticapps-shared`:** git submodule, npm package,
   vendored copy, or something else? Default recommendation in SPLIT-01:
   **git submodule** for zero runtime dependency + clean version pinning.
2. **Skill alias deprecation timeline:** how long does `add-observability`
   stay as an alias to `observability`? Default recommendation in SPLIT-02:
   **2 minor releases** (0.11.0 + 0.12.0), then remove the alias in 0.13.0.
3. **Phase 26 planning artifacts:** stay in claude-workflow (historical accuracy)
   or move to observability repo (logical home)? Default recommendation:
   **stay in claude-workflow** — the planning happened there, moving rewrites
   history. Future obs phases get planning artifacts in the new repo.
4. **ADR ownership:** the observability runtime ADRs (0029, 0030, 0031, 0032,
   0033, 0034) move to observability repo; non-observability ADRs stay. Are
   there any ADRs on the boundary that need a decision? Default: anything that
   only references `add-observability/` or templates stack-specific runtime
   moves; anything that touches the workflow framework stays.

---

**Status:** Drafted 2026-06-02. Sleep on it. No action until the gates above
are checked.
