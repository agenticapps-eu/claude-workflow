# Project — fully migrated to vendored mode

CLAUDE.md is short and project-specific. Workflow content has been
extracted to `.claude/claude-md/workflow.md`.

## Project overview

Project-specific content.

## Conventions

- Use snake_case for file names.
- Tests in `tests/`.

## Workflow

This project follows the AgenticApps Superpowers + GSD + gstack workflow.
See [`.claude/claude-md/workflow.md`](.claude/claude-md/workflow.md) for the
full hooks, rituals, and red-flag tables. That file is **vendored** by
`claude-workflow` migrations — re-run `/update-agenticapps-workflow` to
re-sync; do not edit it directly. Project-specific overrides go in this
CLAUDE.md.
