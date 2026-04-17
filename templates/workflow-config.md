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

## Superpowers Integration Hooks

These hooks enforce the Superpowers + GSD + gstack workflow.
They are read from `.planning/config.json` → `hooks` and enforced via CLAUDE.md rules.

### Pre-Phase (orchestrator runs before spawning executors)

| Hook | Trigger | Skill | What it does |
|------|---------|-------|-------------|
| `brainstorm_ui` | Plan has frontend files in `files_modified` or ROADMAP `UI hint: yes` | `superpowers:brainstorming` | Explore UI/UX alternatives, start dev server, preview with `/browse`, user picks direction |
| `brainstorm_architecture` | Plan introduces new service/model/integration | `superpowers:brainstorming` | Identify edge cases, acceptance criteria, design alternatives |

### Per-Plan (executor follows during task execution)

| Hook | Trigger | Rule | What it does |
|------|---------|------|-------------|
| `tdd_enforcement` | Task has `tdd="true"` | Write failing test → verify fail → implement → verify pass | Strict red-green-refactor, no code-first |
| `ui_preview` | Plan modifies frontend components | Start dev server, `/browse` screenshot | Visual verification before commit |

### Post-Phase (orchestrator runs after all executors, before verifier)

| Hook | Trigger | Skill | What it does |
|------|---------|-------|-------------|
| `review` | Always | `/review` | Pre-landing structural review of phase diff |
| `cso` | Phase touches auth, storage, API, or LLM | `/cso` | OWASP security scan |
| `qa` | Dev server reachable on localhost | `/qa` | Automated QA on affected pages |

### Hook execution order

```
/gsd-execute-phase {N}
  │
  ├── PRE-PHASE HOOKS
  │   ├── brainstorm_ui (if UI plans exist)
  │   └── brainstorm_architecture (if arch plans exist)
  │
  ├── WAVE EXECUTION (GSD executor agents)
  │   └── per-plan: tdd_enforcement, ui_preview
  │
  ├── POST-PHASE HOOKS (before verifier)
  │   ├── /review (always)
  │   ├── /cso (if auth/storage/api/llm scope)
  │   └── /qa (if dev server running)
  │
  └── PHASE VERIFICATION (GSD verifier agent)
```
