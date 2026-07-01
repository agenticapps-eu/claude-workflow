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
| `agentic-apps-workflow-SKILL.md` | `.claude/skills/agentic-apps-workflow/SKILL.md` | `skill/SKILL.md` (trigger skill) |
| `workflow-config.md` | `.claude/workflow-config.md` | `templates/workflow-config.md` (+ placeholder substitution) |
| `claude-settings.json` | `.claude/settings.json` | `templates/claude-settings.json` |
| `planning-config.json` | `.planning/config.json` | end-state of `config-hooks.json` after all hook migrations |
| `claude-md-workflow.md` | `.claude/claude-md/workflow.md` | `templates/.claude/claude-md/workflow.md` |
| `claude-md-reference-block.md` | appended to `CLAUDE.md` | migration `0000` Step 4b |
| `hooks/*` | `.claude/hooks/*` | `templates/.claude/hooks/*` |
| `scripts/*` | `.claude/scripts/*` | `templates/.claude/scripts/*` |
| `global-claude-additions.md` | `~/.claude/CLAUDE.md` (scope global/both) | `templates/global-claude-additions.md` |
| `adr-db-security-acceptance.md` | `templates/adr-db-security-acceptance.md` | migration `0001` |
| `VERSION` | stamped into the skill frontmatter | `skill/SKILL.md` `version:` |

## ⚠️ Seed vs verified

This directory was **seeded** from the current `templates/` + `skill/SKILL.md`,
which are maintained but **lag the last migrations**:

- `0015-add-ts-declare-first-skill` — ts-declare-first wiring
- `0023-prompt-injection-defense` — §14 prompt-injection contract

Until `bin/build-snapshot.sh` has been run on a host with the scaffolder + GSD
+ gstack installed (which replays the full chain and overwrites this dir with
the true end-state), the snapshot is **not yet verified latest**. The drift
guard will FAIL until parity holds — that failure is the signal to run the
generator. Do not ship a release with a red drift guard.

## Contract

Adding a migration now has two obligations:

1. Write the migration (the upgrade path for existing installs).
2. Run `bin/build-snapshot.sh` and commit the regenerated `snapshot/` (the
   fresh-install path). CI's `check-snapshot-parity.sh` fails the PR otherwise.
