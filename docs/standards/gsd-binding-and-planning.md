# Standard — AgenticApps × GSD binding & planning layout

**Status:** Accepted · **Applies to:** `claude-workflow`, `opencode-workflow`,
`codex-workflow` (identical copy shipped in each, per the self-contained-repos
principle). Promote to `agenticapps-workflow-core` when convenient.

This is the shared contract that makes the three host workflows follow the same
concepts and keep a single, portable project plan across hosts.

## 1. Bind upstream GSD + Superpowers — do not re-port

Each host repo **binds** the maintained upstream distribution of GSD (TÂCHES
lineage) and Superpowers for its host, and ships only the AgenticApps layer on
top. No host re-implements GSD's discuss/plan/execute/verify or Superpowers'
discipline skills.

| Host | GSD binding | Superpowers |
|---|---|---|
| claude | `get-shit-done` (public) or `get-shit-done-multi` | Superpowers plugin |
| opencode | `rokicool/gsd-opencode` | Superpowers plugin (`opencode.json`) |
| codex | `get-shit-done-multi` (`--codex`) or `get-shit-done-codex` | Superpowers (Codex) |

Rationale: GSD and Superpowers are large, fast-moving upstreams that already
support these hosts. Re-porting means tracking them by hand and diverging (which
is exactly what produced incompatible `.planning/` layouts). See each repo's
binding brief / ADR.

## 2. Follow GSD's original `.planning/` layout — the TÂCHES standard

All hosts use GSD's native project state (get-shit-done v1.42.x layout),
unchanged. Phase work lives in **per-phase subdirectories**:

```
PROJECT.md  REQUIREMENTS.md  ROADMAP.md  STATE.md
.planning/
  research/
  phases/<NN>-<slug>/                 # e.g. 03-checkout/ — <NN> zero-padded phase, <slug> kebab title
    <NN>-CONTEXT.md                   # /gsd-discuss-phase
    <NN>-<N>-PLAN.md                  # /gsd-plan-phase
    <NN>-VERIFICATION.md              # verify
    REVIEW.md  QA.md  DB-AUDIT.md     # AgenticApps gate outputs, same phase dir
  quick/<NNN>-<slug>/
docs/decisions/NNNN-<slug>.md         # ADRs (already common across hosts)
```

**Do not invent alternative phase layouts.** The canonical form is
`.planning/phases/<NN>-<slug>/`. codex-workflow's earlier **bare**
`.planning/phases/<NN>/` (no slug) is superseded by the slugged GSD-native form
so plans are byte-compatible across hosts. Whatever the bound GSD distribution
writes is authoritative; the AgenticApps layer reads it, it does not reshape it.

## 3. The AgenticApps layer is a thin per-host binding

On top of the bound GSD + Superpowers, each host repo ships only:

- the spec-first **trigger** skill (routing + commitment ritual),
- the **gstack/AgenticApps gates** that have no GSD/Superpowers equivalent
  (cso, qa, design-shotgun, design-critique, database-sentinel, impeccable,
  spec-review, ts-declare-first),
- **snapshot install** (fresh installs lay down the end-state; migrations are
  upgrade-only),
- host instructions (`AGENTS.md` / `CLAUDE.md`).

## 4. Coexistence in one working tree

Two hosts may share one repo **iff** they use different instruction files and
different marker dirs:

| Pair | Coexist? | Why |
|---|---|---|
| claude + codex | ✅ | `CLAUDE.md`+`.claude/` vs `AGENTS.md`+`.codex/` |
| claude + opencode | ✅ | `CLAUDE.md`+`.claude/` vs `AGENTS.md`+`.opencode/` |
| codex + opencode | ❌ | both read `AGENTS.md` — run in separate worktrees |

Required for any shared pair:

- **Host-scoped session handoff:** `.<host>/session-handoff.md`; never read
  another host's handoff or a bare root one.
- **Namespaced hook config:** `.planning/config.claude.json`,
  `.planning/config.opencode.json`, `.planning/config.codex.json` — each host
  reads its own. (Hook schemas are host-specific.)

## 5. Shared vs host-specific state (this is what makes plan handoff work)

- **Shared (the unified project plan):** `PROJECT.md`, `REQUIREMENTS.md`,
  `ROADMAP.md`, `STATE.md`, all `.planning/` phase artifacts, `docs/decisions/`.
  Start a plan in one host, continue in another — the plan is right there.
- **Host-specific:** `.planning/config.<host>.json`, `.<host>/` marker dir,
  the host instruction file, `.<host>/session-handoff.md`.

## 6. Enforcement parity

Gate requirements are consistent by task size across hosts: medium/large tasks
require the independent code-review gate **and** an ADR for any locked design
decision; tiny/small stay fast. (See the per-repo enforcement brief.)

## Conformance checklist (per repo)

- [ ] Binds an upstream GSD distribution (no custom `gsd-*` port).
- [ ] Emits GSD's native `.planning/phases/<NN>-<slug>/` layout (no bare-number or flat variants).
- [ ] AgenticApps layer limited to trigger + gstack gates + snapshot + host file.
- [ ] `.planning/config.<host>.json` namespaced; handoff host-scoped.
- [ ] Medium/large enforce review gate + ADR.
