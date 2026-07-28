# Workflow Configuration

## Project
- **Name**: {{PROJECT_NAME}}
- **Repo**: {{REPO}}
- **Client**: {{CLIENT}}
- **Budget**: {{BUDGET}}

## Tech Stack
- **Backend**: {{BACKEND}}
- **Frontend**: {{FRONTEND}}
- **Database**: {{DATABASE}}
- **LLM**: {{LLM}}

## Environment Strategy
- **Production branch**: main
- **Feature branches**: branch off main, PR back to main
- **Never commit directly to main**

## Conventions
- **Commit format**: `[ISSUE-ID]: short description`
- **ADR path**: `docs/decisions/NNNN-short-title.md`
- **Languages**: code in English, user-facing as needed

## Backend language routing

| Detection | Skills auto-triggered | Notes |
|---|---|---|
| `*.go` files in plan | `samber:cc-skills-golang`, `netresearch:go-development-skill` | Auto-load on Go scope |
| `*.ts`, `*.tsx` files in plan | `QuantumLynx:ts-react-linter-driven-development` | Frontend + Node TS |
| `*.py` files in plan | (none yet — see README §Per-language skill packs → Python) | LLM/agent backends |

For mixed-language phases, all matching skill packs trigger; skills self-scope by file. Install per-project (not global) so non-language repos don't pay the context cost — see README "Per-language skill packs" for install commands.

## Superpowers Integration Hooks

These hooks enforce the OpenSpec + Superpowers + gstack workflow.
They are read from `.planning/config.json` → `lifecycle` and enforced via
CLAUDE.md rules. The one exception is the §18 change-gate, which has
programmatic teeth (`PreToolUse`, `git commit`, CI).

### Stage 1 — propose (authoring the change)

| Hook | Trigger | Skill | What it does |
|------|---------|-------|-------------|
| `brainstorm_ui` | Change adds a UI surface and `design.md` has no "Design alternatives" section | `superpowers:brainstorming` | Explore UI/UX alternatives, start dev server, preview with `/browse`, user picks direction |
| `brainstorm_architecture` | Change introduces new service/model/integration | `superpowers:brainstorming` | Identify edge cases, acceptance criteria, design alternatives |
| `design_critique` | After `/design-shotgun` produces variants, before user picks | `impeccable:critique` | Score variants against impeccable's 24 anti-patterns. Failing variants are flagged before reaching the user. |

### Stage 2 — validate (ALWAYS, before any code)

| Hook | Trigger | Rule | What it does |
|------|---------|------|-------------|
| `change_gate` | Any code edit while a change is open | `openspec validate --all` green AND `REVIEWS.md` carries ≥2 reviewers | Spec §18. Blocks the edit (exit 2) until both clauses hold. Same script runs as git `pre-commit` and in CI — that floor is the real guarantee. Override: `GSD_SKIP_REVIEWS=1` (logged). |
| `multi_ai_review` | Before the first code edit of a change | `run-plan-review.sh <slug>` | ≥2 independent other-vendor reviewer CLIs critique the proposal + design note + spec delta. Output: `openspec/changes/<slug>/REVIEWS.md`. |

### Stage 3 — execute (executor follows during task execution)

| Hook | Trigger | Rule | What it does |
|------|---------|------|-------------|
| `tdd` | Task has `tdd="true"` | Write failing test → verify fail → implement → verify pass | Strict red-green-refactor, no code-first |
| `ui_preview` | Task modifies frontend components | Start dev server, `/browse` screenshot | Visual verification before commit |
| `verification` | Before any task is marked complete in `tasks.md` | `superpowers:verification-before-completion` | Post grep / test / curl / screenshot evidence (§06) |
| `review` | Always, after the change's tasks | `/review`, then `superpowers:requesting-code-review` | Two non-collapsible review passes over the change diff: structural, then code quality in an independent context |
| `cso` | Change touches auth, storage, API, or LLM | `gstack:/cso` + `database-sentinel:audit` (if Supabase / Postgres / MongoDB touched) | OWASP security scan + RLS / DB security audit on Supabase / Postgres / MongoDB scope. **BLOCKS branch close on unresolved Critical / High `database-sentinel` findings** unless accepted via `templates/adr-db-security-acceptance.md`. |
| `qa` | Dev server reachable on localhost | `/qa` | Automated QA on affected pages |

### Stage 4/5 — archive, then ship

| Hook | Trigger | Skill | What it does |
|------|---------|-------|-------------|
| `archive` | The change's tasks are all complete | `openspec archive <slug> -y` | Folds the spec delta into `openspec/specs/<capability>/spec.md` and moves the change to `changes/archive/`. Produces **no git commit** — `archive ≠ ship`. |
| `branch_close` | Feature branch ready to merge | `superpowers:finishing-a-development-branch` | Composes the PR description: skills invoked, gates passed, evidence links |

### Hook execution order

```
/opsx:propose {change-slug}
  │
  ├── STAGE 1 — PROPOSE
  │   ├── brainstorm_ui (if the change adds a UI surface)
  │   └── brainstorm_architecture (if the change adds a service/model)
  │
  ├── STAGE 2 — VALIDATE (before any code; the §18 gate blocks otherwise)
  │   ├── openspec validate --all
  │   └── run-plan-review.sh {slug}  ->  REVIEWS.md (>= 2 reviewers)
  │
  ├── STAGE 3 — EXECUTE (/opsx:apply + Superpowers)
  │   ├── per-task: tdd, ui_preview, verification
  │   ├── /review (always)            — review pass 1, structural
  │   ├── requesting-code-review      — review pass 2, code quality
  │   ├── /cso (if auth/storage/api/llm scope)
  │   └── /qa (if dev server running)
  │
  ├── STAGE 4 — ARCHIVE (/opsx:archive — folds the delta, no git commit)
  │
  └── STAGE 5 — SHIP (finishing-a-development-branch -> commit + PR)
```
