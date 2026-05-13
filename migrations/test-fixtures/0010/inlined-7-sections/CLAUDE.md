# Test Project — Inlined GSD Sections

A synthetic CLAUDE.md exercising all 7 GSD marker blocks.

## Workflow

See [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md) —
auto-synced.

<!-- GSD:project-start source:PROJECT.md -->
## Project

**Test Project Alpha**

A synthetic project for fixture purposes. Has a clear purpose, three
constraints, and a single core value statement.

**Core Value:** A test fixture worth its bytes proves the
post-processor handles the canonical 7-section pattern correctly.

### Constraints

- Budget: 1 fixture
- Timeline: until 0010 ships
- Tech stack: text only, no executable bits
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- TypeScript 5.6 - Frontend
- Go 1.25 - Backend
- SQL (PostgreSQL) - Storage
## Runtime
- Node.js 20+ - Frontend tooling
- Go 1.25.0 - Backend binary
## Frameworks
- React 19.0 - Frontend
- Chi - Backend HTTP routing
- TanStack Query 5.0 - API state
- Tailwind CSS 4.0 - Styling
- Vite 6.0 - Build tool
## Key Dependencies
- @supabase/supabase-js 2.45.0
- pgx (via sqlc)
## Configuration
- Frontend env: VITE_*
- Backend env: standard os.Getenv
## Platform Requirements
- macOS/Linux dev
- Node 20.x
- Go 1.25+
- PostgreSQL 15+
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- TypeScript/React: PascalCase for components
- Go: snake_case for packages
- No test-specific suffixes observed
## Code Style
- TypeScript/React: Vite default
- Go: gofmt
## Import Organization
- TypeScript: `@/*` maps to `./src/*`
## Error Handling
- Errors via TanStack Query error state
- Standard Go error handling
## Logging
- Go: log.Printf
- TypeScript: console methods
## Comments
- Go: exported functions
- TypeScript: type info as inline docs
## Function Design
- Go main() ~75 lines
- React component ~46 lines
## Module Design
- TypeScript: Default exports for components
- Go: domain-organized packages
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- Four-platform separation: Cloudflare Pages / Fly.io / Supabase / OpenRouter
- Single-tenant, prototype-scale
- Sequential LLM pipeline
- REST API contract
- Type-safe database layer (sqlc + pgx)
## Layers
- Frontend: Cloudflare Pages
- Backend: Fly.io
- Database: Supabase
- LLM router: OpenRouter
## Data Flow
- Server state: PostgreSQL
- Auth state: Supabase JWT
- Frontend cache: TanStack Query
- LLM: stateless via OpenRouter
- Files: Supabase Storage
## Key Abstractions
- Handlers: HTTP route to business logic
- Services: orchestration layer
- Pipeline: sequential DD analysis
- sqlc: type-safe DB queries
- Auth: Supabase JWT validation
## Entry Points
- Frontend: /frontend/src/main.tsx
- Backend: /backend/cmd/api/main.go
- Database: /supabase/migrations/
## Error Handling
- Queries retry with backoff
- Handler tuples (response, error)
- Panic recovery TODO
- RLS denials → 403
## Cross-Cutting Concerns
- Backend logs: log.Printf
- Frontend logs: console
- Validation: PG constraints + JSON marshaling
- Auth: middleware via JWKS
- CORS: hardcoded for now
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

| Skill | Description | Path |
|-------|-------------|------|
| test-skill | Synthetic test skill for fixture purposes | `.claude/skills/test-skill/SKILL.md` |
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes
- `/gsd-debug` for investigation
- `/gsd-execute-phase` for phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->

## Project notes

Trailing content after the GSD sections. Must be preserved.
