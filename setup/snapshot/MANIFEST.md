# Snapshot manifest

`setup/snapshot/` is the **materialized latest end-state** that
`setup-agenticapps-workflow` lays down on a fresh project — the same files a
full `0000`→latest migration replay would produce, captured once. It is a
**generated artifact**: regenerate with `bin/build-snapshot.sh` after adding
or editing any migration, and the drift guard
(`migrations/check-snapshot-parity.sh`) enforces parity in CI.

## Contents → install target

| Snapshot file | Installed to | Source of truth |
|---|---|---|
| `agentic-apps-workflow-SKILL.md` | `.claude/skills/agentic-apps-workflow/SKILL.md` | `skill/SKILL.md` (trigger skill; carries the §15 knowledge-capture ritual tail — parity §7) |
| `workflow-config.md` | `.claude/workflow-config.md` | `templates/workflow-config.md` (+ placeholder substitution) |
| `claude-settings.json` | `.claude/settings.json` | `templates/claude-settings.json` |
| `planning-config.json` | `.planning/config.json` | end-state of `config-hooks.json` after all hook migrations; includes the `knowledge_capture` block (spec §15) whose `<repo-name>` placeholder setup Step 4d resolves at install time |
| `claude-md-workflow.md` | `.claude/claude-md/workflow.md` | `templates/.claude/claude-md/workflow.md` |
| `claude-md-reference-block.md` | appended to `CLAUDE.md` | migration `0000` Step 4b |
| `hooks/*` | `.claude/hooks/*` | `templates/.claude/hooks/*` (all `.sh`; the `.cjs` gitnexus-reindex engine was removed in v3.0.0 — ADR-0044) |
| `scripts/*` | `.claude/scripts/*` | `templates/.claude/scripts/*` |
| `global-claude-additions.md` | `~/.claude/CLAUDE.md` (scope global/both) | `templates/global-claude-additions.md` |
| `adr-db-security-acceptance.md` | `templates/adr-db-security-acceptance.md` | migration `0001` |
| `gitignore` | appended to project `.gitignore` (commits `.planning/phases/`; narrow local ignores only — ADR-0037) | `templates/gitignore` |
| `spec-mirrors/11-coding-discipline-0.4.0.md` | injected into `CLAUDE.md` behind the `@0.4.0 §11` provenance anchor (byte-identical to migration 0014's output) | `templates/spec-mirrors/11-coding-discipline-0.4.0.md` |
| `VERSION` | stamped into the skill frontmatter | `skill/SKILL.md` `version:` |

## Verified

The snapshot is assembled from source by `bin/build-snapshot.sh` (copies from
`templates/` + `skill/SKILL.md`, plus a `jq` transform for
`claude-settings.json`) and enforced by `migrations/check-snapshot-parity.sh`
in CI. To regenerate after changing a migration or template, run
`bash bin/build-snapshot.sh` and commit the result.

## Contract

Adding a migration now has two obligations:

1. Write the migration (the upgrade path for existing installs).
2. Run `bin/build-snapshot.sh` and commit the regenerated `snapshot/` (the
   fresh-install path). CI's `check-snapshot-parity.sh` fails the PR otherwise.
