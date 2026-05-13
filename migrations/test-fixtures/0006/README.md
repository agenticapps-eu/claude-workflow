# Migration 0006 test fixtures

15 scenarios covering every decision branch of the LLM wiki compiler install
script (`templates/.claude/scripts/install-wiki-compiler.sh`). Run via the
`test_migration_0006()` stanza in `migrations/run-tests.sh`.

## Sandbox model

Each fixture's `setup.sh` runs with `HOME=$TMP/home` (the harness creates
a fake `$HOME`). The install script reads `$HOME`-relative paths exclusively
(no hardcoded `/Users/...`). The harness greps the script post-build for
non-sandboxed absolute paths as a sanity guard (codex F1).

## Layout per fixture

| File | Purpose |
|---|---|
| `setup.sh` | Materializes pre-apply state inside the sandbox |
| `expected-exit` | Single integer exit code the install script must produce |
| `expected-stderr.txt` (optional) | Non-empty → every line must appear (substring) in actual stderr |
| `verify.sh` (optional) | Post-apply assertions |

`setup.sh` has access to two env vars: `$REPO_ROOT` (workflow repo root) and
`$FIXTURES_ROOT` (this dir). The harness sets them before invoking.

## Scenarios

| # | Name | Tests |
|---|---|---|
| 01 | plugin-missing | pre-flight aborts when vendored plugin not present |
| 02 | fresh-install | full apply on clean sandbox |
| 03 | idempotent-reapply | running install twice produces same state |
| 04 | rollback | apply + rollback preserves family data |
| 05 | zero-families | host symlink works even with no families detected |
| 06 | existing-config-preserved | custom `.wiki-compiler.json` not clobbered |
| 07 | symlink-target-collision | real file at symlink path → ABORT |
| 08 | existing-correct-symlink | idempotent on already-installed symlink |
| 09 | claudemd-update-idempotency | re-apply doesn't duplicate `## Knowledge wiki` heading |
| 10 | wrong-target-symlink | symlink to other-target → ABORT (codex B2) |
| 11 | missing-family-claudemd | family without CLAUDE.md → skip-with-note (codex B3) |
| 12 | non-family-dir-skipped | directory without child .git → not scaffolded (codex F2) |
| 13 | missing-plugins-parent | `~/.claude/plugins/` doesn't exist → mkdir -p creates it (codex F4) |
| 14 | knowledge-as-file | `.knowledge` exists as regular file → ABORT exit 3 (codex F4) |
| 15 | malformed-existing-config | pre-existing config is invalid JSON → preserve+warn (codex F4) |
