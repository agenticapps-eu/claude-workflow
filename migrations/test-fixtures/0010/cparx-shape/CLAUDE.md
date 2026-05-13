# CLAUDE.md — Test Project (cparx-shape)

> This file is the authoritative source for Claude Code context in this repo.
> Read this before any code generation, architecture decisions, or workflow steps.

---

## Project Overview

**Test Project** is a synthetic project mimicking cparx's CLAUDE.md
shape for fixture purposes. The same section structure, similar prose
density, post-0009 state (Superpowers block already vendored).

**Client:** AgenticApps
**Timeline:** Synthetic
**Repo:** test-fixture

---

## Workflow

See [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md) —
auto-synced from the AgenticApps Claude Workflow scaffolder. Includes
commitment ritual, GSD gates, 13 Red Flags, and rationalization table.

---

## Tech Stack

### Frontend
- Vite + React + React Router (SPA)
- shadcn/ui + TanStack Table + Tailwind CSS
- TanStack Query v5
- TypeScript

### Backend
- Go 1.25+, Chi, sqlc + pgx
- PDF processing: ledongthuc/pdf
- LLM via OpenRouter

### Database/Auth/Storage
- PostgreSQL with RLS
- Supabase Auth + Storage
- pgvector for embeddings

### LLM Layer
- Primary: Claude Sonnet 4
- Dev: DeepSeek R1
- JSON mode for structured output

---

## Repo Structure

```
project/
├── frontend/
│   ├── src/{components,pages,hooks,lib,types}/
│   └── package.json
├── backend/
│   ├── cmd/api/
│   ├── internal/{handler,middleware,service,pipeline,parser,store}/
│   ├── sqlc.yaml
│   └── Dockerfile
├── supabase/
│   ├── config.toml
│   └── migrations/
├── .github/workflows/
├── .claude/{skills,commands}/
└── docs/decisions/
```

---

## Environment Strategy

| Env | Purpose | Branch |
|---|---|---|
| local | Developer machine | feature branches |
| staging | Demo/QA | main |
| production | Live | tags |

---

## Constraints

- Budget: 80 hours
- Timeline: 4 weeks
- Tech stack: locked per ADR-0002 and ADR-0003
- No Python
- Single developer
- Document format: PDF (ledongthuc/pdf), spreadsheets, images — no external OCR

---

## Anti-patterns to avoid

- Don't add Python — pure Go backend, single Dockerfile
- Don't optimize prematurely — prototype ships first
- Don't introduce LangChain or similar orchestrators
- Don't bypass RLS — every query must respect auth.uid()

## gstack

Use the `/browse` skill from gstack for **all web browsing**. Never use `mcp__claude-in-chrome__*` tools.

### Available skills

`/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/connect-chrome`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/setup-deploy`, `/retro`, `/investigate`, `/document-release`, `/codex`, `/cso`, `/autoplan`, `/plan-devex-review`, `/devex-review`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Test Project Beta**

An AI-powered platform prototype for an unnamed client. Processes documents through five DD dimensions using an LLM pipeline, produces per-dimension findings and scores, combines into an overall investment rating. Employee-facing with three UI variants for A/B testing.

**Core Value:** An employee can open the app, select a case, trigger DD analysis, and see structured findings with scores demonstrated in a live walkthrough.

### Constraints

- Budget: 80 hours total
- Timeline: 4 weeks
- Tech stack: Locked per ADR-0002 and ADR-0003
- No Python
- Single developer
- Document format: PDFs, spreadsheets, images
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- TypeScript 5.6 - Frontend application
- Go 1.25 - Backend API server
- SQL (PostgreSQL) - Database schemas
- HTML/CSS - Frontend markup (via Tailwind 4.0)
## Runtime
- Node.js 20+ - Frontend tooling
- Go 1.25.0 - Backend binary compilation
- Linux Alpine - Production runtime
- npm - Node deps
- go mod - Go deps
- Lockfile: frontend/package.json + backend/go.mod
## Frameworks
- React 19.0 - Frontend
- React Router 7.0 - SPA routing
- Chi - Backend HTTP routing
- TanStack Query 5.0 - API state
- Tailwind 4.0 - Styling
- Vite 6.0 - Build tool
- TypeScript 5.6 - Type checking
## Key Dependencies
- @supabase/supabase-js 2.45.0
- @tanstack/react-query 5.0
- Go stdlib net/http, encoding/json
- pgx (via sqlc)
- Supabase CLI
## Configuration
- Frontend env: VITE_*
- Backend env: standard os.Getenv
- Frontend: frontend/vite.config.ts
- Backend: backend/Dockerfile
- Database: backend/sqlc.yaml
## Platform Requirements
- macOS/Linux dev
- Node 20.x
- Go 1.25+
- PostgreSQL 15+
- OpenRouter API key
- Fly.io Frankfurt
- Cloudflare Pages
- Supabase Frankfurt
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- TypeScript/React: PascalCase for components
- Go: snake_case for packages, lowercase files
- No test suffixes yet
- TypeScript: camelCase for functions
- Go: PascalCase exported, camelCase unexported
- TypeScript: camelCase for variables
- Go: camelCase locals, PascalCase exported
- Constants: UPPERCASE in Go
- TypeScript: PascalCase for types/interfaces
- Go: PascalCase for structs/types
- sqlc types use PascalCase with JSON tags
- React hooks: camelCase (useQuery, etc.)
## Code Style
- TypeScript/React: Vite default
- Go: gofmt
- TypeScript/React: ESLint v9
- Go: go vet in CI
## Import Organization
- TypeScript: @/* maps to ./src/*
- Example: @/lib/supabase → frontend/src/lib/supabase.ts
## Error Handling
- TanStack Query error state
- App.tsx: welcome.error?.message
- No try/catch (Query handles async)
- HTTP errors: if (!res.ok) throw
- Go: if err != nil { ... }
- main.go: explicit error checks
- HTTP errors: http.Error helper
- No panic; recover gracefully
## Logging
- Go: log.Printf, log.Fatal
- TypeScript: console methods
- Go logs structured via format strings
- Minimal logging: startup + fatal only
- No structured logging framework yet
## Comments
- Go: comments on exported funcs/types
- Inline for non-obvious logic
- Not strictly enforced
- TypeScript: type info as docs
## Function Design
- Go main() ~75 lines OK for prototype
- React App() ~46 lines
- Go: explicit params, no destructuring
- TypeScript: destructuring for props
- Go: multiple returns (result, error)
- TypeScript: single return / destructured hooks
- React: JSX from components
## Module Design
- TypeScript: Default export for components
- Named exports for utilities
- Go: single-letter receivers, domain packages
- Each module exports its own
## Special Conventions
- Frontend: import.meta.env.VITE_*
- Go: os.Getenv()
- Examples: VITE_SUPABASE_URL, etc.
- mux.HandleFunc("METHOD /path", handler)
- CORS in handler (manual)
- TanStack Query: useQuery
- import.meta.env for Vite env vars
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Four-platform separation: Cloudflare / Fly.io / Supabase / OpenRouter
- Single-tenant, prototype-scale
- Sequential LLM pipeline in Go
- REST API contract: Frontend ↔ Fly.io HTTP/JSON
- Fly.io ↔ Supabase: PostgREST + native PG
- Type-safe DB layer: sqlc + pgx
## Layers
- Frontend: Serve React SPA, location /frontend/src/, depends on Supabase Auth + Fly.io API
- Backend: REST API + AI orchestration, /backend/cmd/api/main.go + /backend/internal/, depends on Supabase + OpenRouter
- Database: PostgreSQL + RLS + JWT auth + storage, /supabase/migrations/
- LLM Router: OpenRouter, called from backend/internal/pipeline/
## Data Flow
- Server state: PostgreSQL
- Auth state: Supabase JWT (ephemeral)
- Frontend cache: TanStack Query
- LLM: stateless OpenRouter
- Files: Supabase Storage
## Key Abstractions
- Handlers: HTTP routes to business logic
- Services: business logic, orchestration
- Pipeline: sequential DD across categories (legal, financial, ESG, tech, market)
- sqlc: type-safe queries, zero runtime overhead
- Auth: JWT issuance + validation via Supabase
## Entry Points
- Frontend: /frontend/src/main.tsx
- Backend: /backend/cmd/api/main.go
- Database: /supabase/migrations/
## Error Handling
- Queries: retry 2x with backoff
- App.tsx: welcome.error?.message
- Unrecoverable: UI fallback or redirect
- Handlers return (response, error)
- Errors logged + HTTP code returned
- JSON error: {"error": "..."}
- Panic recovery: TODO middleware
- RLS denials → 403 Forbidden
## Cross-Cutting Concerns
- Backend logs: log.Printf (consider slog in P2)
- Frontend logs: console only
- main.go: log.Printf("cPARX API starting on :%s")
- Frontend validation: none yet
- Backend validation: JSON marshal + type safety
- DB: NOT NULL, UNIQUE, CHECK constraints
- Auth middleware: JWT via JWKS, no key caching
- Token: Authorization header
- Protected routes: all /api/* except /health, /api/welcome
- CORS: hardcoded for now, centralize in P2
- Allowed origin: * (prototype); restrict in prod
- Rate limiting: not implemented
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| agentic-apps-workflow | Enforces the spec-first development workflow using Superpowers + GSD + gstack | `.claude/skills/agentic-apps-workflow/SKILL.md` |
| add-observability | AgenticApps spec §10 v0.2.1 observability scaffolder | `.claude/skills/add-observability/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill tool.

Skill discovery priority:
1. Direct match in available skills list
2. Slash command in user message
3. Implicit topic match
4. Default to general-purpose

## Notes

Trailing project notes. Reference materials, runbooks, etc. Preserved by post-processor.
