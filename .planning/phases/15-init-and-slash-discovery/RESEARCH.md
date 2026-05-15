# Phase 15 — RESEARCH — Design alternatives for init + slash discovery

Per `superpowers:brainstorming` discipline, every non-obvious decision lists ≥ 2 alternatives, the trade-offs, and a recommendation. Decisions made in CONTEXT.md (slot 0012, version 1.11.0, scope cut, 5-stack coverage) are not re-litigated here.

## D1 — Slash-command discovery fix (#22)

Issue #22 documents four candidate fixes. CONTEXT.md already summarised them. This decision is the single biggest fork in the phase.

| Option | Mechanism | Touch surface |
|---|---|---|
| **A — symlink at install** | Migration 0002's Step 1 appends `ln -s "$PWD/.claude/skills/add-observability" "$HOME/.claude/skills/add-observability"` after the existing `cp -r`. Migration 0012 backports this fix for projects already on v1.10.0. | migrations/0002, migrations/0012. ~10 lines. |
| **B — global-only install** | Migration 0002 (and the new 0012 for upgrades) installs the skill into `~/.claude/skills/add-observability/` only. The path-root resolution at runtime stays project-relative because the skill reads CWD, not its own install path. Per-project `.claude/skills/add-observability/` becomes a marker file only. | migrations/0002, migrations/0012. Rollback semantics change (preserve-data for the global install is the new default). |
| **C — promote scaffolder layout** | Move `add-observability/` out of the nested scaffolder-skill directory. It becomes a sibling skill at `~/.claude/skills/add-observability/` that the scaffolder install handles directly (likely by symlinking or by being a separate clone target). Migration 0002 becomes a no-op for the discovery question. | skill/SKILL.md, setup/SKILL.md, migrations/0002, scaffolder install docs, every consumer's install path doc. ~50+ lines across many files. |
| **D — drop the slash claim** | Document in CLAUDE.md / SKILL.md / migration 0002 that the skill is invoked by asking Claude to "follow add-observability/scan/SCAN.md" rather than via `/add-observability scan`. | docs only. |

### Trade-offs

**Option A — symlink** is the smallest change. The trade-off is the "last project wins" semantics: if a developer applies migration 0002 in project P1, then in P2, the symlink at `~/.claude/skills/add-observability/` re-points to P2's local copy. Project P1's `/add-observability` still works (the symlink target is generic; the skill reads CWD anyway), but if P2 is on a different skill version, P1 gets P2's version. Workable but subtle. Mitigation: migration 0002 checks if the symlink already exists pointing somewhere reasonable, and warns rather than blindly overwriting.

**Option B — global-only** has cleaner semantics. The skill lives once, in one place. Per-project markers become annotations rather than installs. Trade-off: every project that adopts the workflow drops a per-project marker but doesn't actually install code — a slight conceptual drift from "migration installs files into the project". The rollback story changes too: rolling back migration 0002 removes the marker but should NOT uninstall the global skill (other projects depend on it).

**Option C — promote scaffolder layout** is the architecturally cleanest. The skill becomes a peer of `agentic-apps-workflow`, both installed globally at `~/.claude/skills/<skill-name>/`. The scaffolder repo gains a sibling layout: `add-observability/` lives alongside `skill/`, not under it. Issue #22 itself acknowledges this: *"the upstream copy that migration 0002 sources from lives nested inside the scaffolder skill directory, so it is also not a top-level entry under `~/.claude/skills/` and would not be discovered there either."* Fixing the upstream layout fixes both the upstream discovery and the per-project install path in one move. Trade-off: bigger refactor (move files, update docs, update setup skill, update migration 0002). But it's a one-time cost.

**Option D — drop the slash claim** is the honest minimum. If we never expect slash-discovery to work cleanly, document it. Trade-off: UX regression. Users have to type more to invoke the skill. The spec doesn't require slash-discoverability (§10.7 says the generator must "scaffold" / "wire" / "validate" / "apply with consent" — never specifies invocation mechanism). So D is conformance-clean but feels like giving up.

### Recommendation: **C** with **A** as a fallback if scope is too large

Option C closes both gaps (upstream discovery + per-project install) at the architectural level. The refactor is bounded (Phase 15's planned scope already requires touching the scaffolder install for the version bump; co-locating the layout change is incremental cost). The "promote" move:

1. `add-observability/` moves to scaffolder repo root as a sibling of `skill/`.
2. Scaffolder install (per `agentic-apps-workflow` SKILL.md's documented `git clone … ~/.claude/skills/agenticapps-workflow`) is augmented to symlink-or-clone `add-observability/` to `~/.claude/skills/add-observability/`.
3. Migration 0002 simplifies: just register a per-project marker; no skill content copy.
4. Migration 0012 backports the registration mechanism for projects on v1.10.0.

If during planning we find C's surface area is materially bigger than estimated, fall back to **A** (symlink at install time). A is shippable in 2-3 days; C in 3-5 days. Both close #22.

If the user has a strong preference, surface this at PLAN time.

## D2 — INIT.md procedure shape: interactive vs declarative

Init scaffolds wrapper, middleware, policy, entry-rewrite, and CLAUDE.md metadata. Two shapes:

| Option | Shape |
|---|---|
| **A — interactive walk** | Phase-by-phase prompts: "About to materialise wrapper to `<path>`. Apply? [y/n]". User consents per-phase. Matches the `scan-apply` consent model. |
| **B — declarative unified diff** | Compute all changes upfront, present a single unified diff covering all files, get one y/n. Matches `git apply --interactive` style. |
| **C — hybrid** | One consent for "scaffold new files" (wrapper, middleware, policy — no overwrite risk), separate consent for "edit entry file" and "edit CLAUDE.md" (overwrite risk). |

### Recommendation: **C**

The risk profile differs by phase. New-file materialisation (wrapper, middleware, policy.md) overwrites nothing — the target paths shouldn't exist on init. Edits to entry-file and CLAUDE.md DO modify existing user-authored content. C splits the consent surface by risk:

1. "Scaffold N new files at <list>. Apply? [y/n]" — one consent for the safe block.
2. "Rewrite `<entry-file>` to wrap handler with `withObservability`. Diff: <diff>. Apply? [y/n]" — separate consent.
3. "Add `observability:` block to CLAUDE.md. Diff: <diff>. Apply? [y/n]" — separate consent.

User can selectively reject the risky edits (e.g., apply the wrapper but hand-edit the entry file).

## D3 — Multi-stack monorepo handling

A project may have multiple module roots (e.g. cparx has `backend/go.mod` + `frontend/package.json`). Init must handle this.

| Option | Behaviour |
|---|---|
| **A — walk all detected stacks in one invocation** | Single `/add-observability init` runs detection, finds N stacks, scaffolds each in turn, writes ONE `observability:` metadata block in CLAUDE.md listing all N. |
| **B — one stack per invocation** | User invokes `/add-observability init --stack go-fly-http` for each. The CLAUDE.md metadata block grows incrementally. |
| **C — interactive selection** | `/add-observability init` lists detected stacks and asks the user which to scaffold this run. User can scaffold one, some, or all. |

### Recommendation: **A** with `--stack <id>` override

Default behaviour is walk-all (cparx-class projects don't want to invoke the skill N times). Add `--stack <id>` for the rare case where the user wants partial scaffolding (e.g., scaffold backend now, frontend later). The CLAUDE.md block uses spec §10.8's array shape so all detected stacks are listed in one place.

## D4 — policy.md content

Each stack ships scan/checklist.md trivial-errors defaults (e.g. `pgx.ErrNoRows` for Go, validation-error 4xx for TS). The init-generated `policy.md` needs to encode these so scan can read them.

| Option | Policy file shape |
|---|---|
| **A — single canonical template** | One `policy.md` template with all stacks' trivial errors. Project's actual content depends on detected stacks. |
| **B — per-stack template, one file per stack** | Each detected stack gets its own `policy.md` at its `target.policy_path`. |
| **C — single project-level `policy.md`** | One file at `<wrapper-dir>/policy.md` (per spec §10.5 reference). Init writes one even in multi-stack projects, with sections for each stack. |

### Recommendation: **B** for multi-stack, **A** for single-stack

The policy file is referenced from CLAUDE.md's `observability.policy` field — a single path. For single-stack projects, B and C are equivalent. For multi-stack (e.g. cparx with Go backend + Vite frontend), the trivial-errors lists are language-specific and shouldn't co-mingle. Two files, two paths in the metadata block, scan checks each.

Init writes a sensible default per-stack policy with these sections:
- `## Trivial errors` — pre-populated with the stack's default list.
- `## Redacted attributes` — defaults to `password`, `token`, `api_key`, `card_number`, `cvv`.
- `## Project event names` — empty section with a `<!-- add your domain events here -->` placeholder.

## D5 — `init --force` semantics

| Option | Behaviour |
|---|---|
| **A — strict first-run only** | Init refuses if the target wrapper file already exists. User must `rm -rf` manually to re-init. |
| **B — `--force` re-init** | Init detects existing wrapper, prompts to overwrite. `--force` skips prompt. |
| **C — diff-mode** | Init computes the diff against existing wrapper. User can accept changes or skip. |

### Recommendation: **A** for v0.3.1; consider B for future versions

Init is greenfield. Re-init is a different use case (refresh stale wrapper after a spec amendment) and warrants its own design pass. Strict-first-run is the simplest contract: if you want to refresh, `rm -rf <wrapper-dir>` first and re-init. Document this explicitly in INIT.md and the skill description.

## D6 — Entry-file rewrite safety + stale detection

If the user has customised the entry file between two init runs, blindly rewriting would lose their changes. Init must detect this.

| Option | Behaviour |
|---|---|
| **A — heuristic detection** | Scan the entry file for the canonical "Init() called at startup" signature; if found, assume init has run; refuse to re-wrap. |
| **B — anchor-comment marker** | Init writes a `// agenticapps:observability:start` / `:end` comment block around its insertions. Re-init detects the marker; refuses to re-wrap. |
| **C — git diff-of-entry** | Compare the current entry file against the pre-init shape (templated). If non-zero diff outside the wrap-shape, refuse. |

### Recommendation: **B** — anchor comments

Anchor comments are the standard pattern (mirrors how migration 0009 vendors CLAUDE.md sections with `<!-- workflow:start -->`/`<!-- workflow:end -->`). They:
- Are robust to whitespace and surrounding-line edits.
- Survive re-formatting (prettier, gofmt) as long as the comments themselves aren't removed.
- Provide a clean rollback boundary.
- Let init detect "already wrapped" cleanly.

Migration 0011's `scan-apply` Phase 6 already uses anchor comments for the report rewrite. Same pattern.

## D7 — Brownfield/init-after-scan interaction

A user might run `scan` first (no init), see gaps, then run init. Init's behaviour:

| Option | Behaviour |
|---|---|
| **A — independent operations** | Init runs whether or not scan was run. scan-apply requires init to have run; init does not require scan. |
| **B — chain hint** | If `.scan-report.md` exists at the project root, init prints a hint: "After init, your existing scan-report findings will be against the pre-init code. Re-run scan." |

### Recommendation: **B** — independent + chain hint

Init is greenfield. It shouldn't gate on scan-report existence. But a stale scan-report after init is a foot-gun; the hint catches it. Add to INIT.md Phase 9 (post-completion summary).

## D8 — Migration 0012 vs in-skill change

Issue #22's fix can be encoded either as a migration step (changes the on-disk install layout) or as a one-time in-skill init at the agentic-apps-workflow scaffolder install layer.

| Option | Where the fix lives |
|---|---|
| **A — migration 0012 for upgrade** | Existing v1.10.0 projects upgrade to v1.11.0 by running migration 0012 which adds the slash-discovery wire-up. |
| **B — `agentic-apps-workflow` setup-time fix** | The scaffolder install itself (one-time per machine) wires discovery. Migrations 0002 + 0012 don't have to do it. |
| **C — both** | A for upgrade existing projects; B so fresh installs work too. |

### Recommendation: **C** — both

Existing v1.10.0 projects need migration 0012 (they've already run 0002 with the broken install). New projects need the scaffolder-install layer to be correct so their first `/setup-agenticapps-workflow` gets a working discovery from the start. Both work-streams are short.

## Decision summary

| Decision | Recommendation | Defer to user-review? |
|---|---|---|
| D1 — slash discovery | C (promote scaffolder layout); A as scope-fallback | **yes** — high-touch refactor |
| D2 — INIT.md shape | C — hybrid consent | no |
| D3 — multi-stack | A — walk all + `--stack <id>` override | no |
| D4 — policy.md | per-stack file, one per detected stack | no |
| D5 — `--force` | strict first-run only at v0.3.1 | no |
| D6 — entry-file safety | anchor comments | no |
| D7 — chain hint after scan-report exists | independent + Phase 9 hint | no |
| D8 — migration 0012 vs setup-time | both (C) | no |

D1 is the only fork I'd want a sanity check on before drafting PLAN.md — option C is the right architecture but C is also the bigger refactor. Phase 15 PLAN.md will reflect the choice; surface in discuss.
