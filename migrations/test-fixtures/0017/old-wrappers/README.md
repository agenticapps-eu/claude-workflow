# Vendored OLD (pre-1.16.0) observability wrappers — migration 0017 baseline

These are the **add-observability v0.4.x** wrapper entry files exactly as they
existed on `main` at commit `34ee72e` — the last commit before the 1.16.0 Axiom
merge (PR #45) replaced them with the role-based registry shape.

Migration 0017 detects whether a downstream project's wrapper is an *unmodified*
v0.4.x wrapper (safe to replace) by comparing the canonical (structurally-masked)
form of these bytes against `../known-wrapper-hashes.json`. Both the fixture
materialiser (`../common-setup.sh`) and the baseline regenerator
(`../regen-hashes.sh`) read the OLD wrapper from **here**.

## Why vendored instead of `git show main:...`

The fixtures originally sourced the OLD wrapper from `git show main:...`. That
silently broke the instant PR #45 merged, because `main` then returned the NEW
wrapper (which already contains `buildRegistry`), so every "clean" fixture was
mis-classified *already-applied* and the suite became a no-op. Vendoring the
bytes makes the fixtures hermetic — independent of git history and immune to any
future movement of `main`.

## Regenerating

If the v0.4.x baseline ever legitimately changes, re-vendor from the appropriate
commit and run `bash ../regen-hashes.sh` to recompute `known-wrapper-hashes.json`.
The recorded hashes correspond to the canonical form of exactly these bytes.
