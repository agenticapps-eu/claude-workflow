# ADR-0010: Backend language routing for Go

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 1 of `feat/wire-go-impeccable-database-sentinel`

## Context

Many AgenticApps backends are written in Go, but the workflow scaffolder previously
treated all phases as language-agnostic. Stage 2 review (`superpowers:requesting-code-review`)
ran the same checklist regardless of language, missing Go-specific issues that
language-aware linters and patterns catch:

- Idiomatic error wrapping
- Context propagation correctness
- Slice/map allocation pitfalls
- Resilience patterns for long-running services (retry, graceful shutdown, observability)
- DI framework idioms (wire/dig/fx)

Two community skill packs cover this gap:

- **`samber/cc-skills-golang`** — 40+ skills covering style, naming, errors, testing,
  security, observability, performance, concurrency, context, DI, CLI, config, gRPC,
  GraphQL, swagger. Each skill ships measured eval data (e.g. `golang-modernize` -61%
  error rate, `golang-samber-do` -81%).
- **`netresearch/go-development-skill`** — Production resilience: package structure,
  go-cron with FakeClock testing, retry/backoff/graceful shutdown, Docker client
  patterns, golangci-lint v2, fuzz/mutation testing, Prometheus observability.

They compose — samber covers breadth + idioms, netresearch covers production resilience.

## Decision

1. Add a **Backend language routing** section to `templates/workflow-config.md` declaring
   which skill packs auto-trigger on which file extensions.
2. Add **language-specific code-quality gates** as an extension of post-phase Stage 2
   in `docs/ENFORCEMENT-PLAN.md`.
3. Document install commands in `README.md` under **Per-language skill packs**.
4. Both Go skill packs are installed **per-project**, not globally.

The routing is declarative — it tells the agent which skills to invoke when a Go phase
is detected. The skills themselves self-scope by file content.

## Alternatives Rejected

- **Global install of both Go packs.** Rejected — non-Go repos would pay the context
  cost (skill descriptions still load even when not triggered), inflating context for
  TS-only or Python-only projects.
- **One bundled "polyglot" skill.** Rejected — bundling forces every project to absorb
  every language's rules. Per-language skills compose cleanly and let each language
  evolve independently.
- **Skip language routing entirely; rely on universal Stage 2 reviewer to know Go.**
  Rejected — generic reviewers miss language-specific anti-patterns. The samber eval
  data shows measurable error-rate reductions; ignoring those gains is leaving
  quality on the table.
- **Wait until netresearch publishes a stable release.** Rejected — the package is
  already in production use elsewhere; waiting indefinitely defers value. We adopt
  now and re-evaluate if the maintainer disappears.

## Consequences

**Positive:**
- Go phases get language-aware Stage 2 review, catching idiom violations and resilience
  bugs that generic review misses.
- Per-project installs keep context cost off non-Go repos.
- Routing is declarative + extensible — adding Python or Rust packs follows the same
  pattern (one row in workflow-config.md, one row in ENFORCEMENT-PLAN.md).

**Negative:**
- Per-project install requires one extra `git clone` per Go repo — not amortizable.
  Tracked: future migration could ship a one-liner installer.
- Bus factor on `samber/cc-skills-golang` and `netresearch/go-development-skill` is
  solo-maintainer. Mitigation: both are MIT-licensed; we can fork if abandoned.

**Follow-ups:**
- Phase 4 of this work ships a migration framework — future Go skill pack additions
  flow through that.
- Python skill pack TBD; cross-referenced from `templates/workflow-config.md`
  to README §Per-language skill packs → Python.

## References

- Action plan: `/Users/donald/Documents/Claude/Projects/agentic-workflow/tooling-action-plan-2026-05-02.md` §0
- `samber/cc-skills-golang`: https://github.com/samber/cc-skills-golang
- `netresearch/go-development-skill`: install via the upstream pack's README. The
  action plan documents an `npx @netresearch/skills add go-development`
  invocation but the package name and subcommand have not been independently
  verified in this scaffolder.
