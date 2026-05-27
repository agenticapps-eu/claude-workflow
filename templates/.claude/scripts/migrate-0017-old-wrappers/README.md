# Vendored OLD (pre-1.16.0) observability wrappers — migration 0017 runtime data

These are the **add-observability v0.4.x** wrapper entry files exactly as they
existed on `main` at commit `34ee72e` — the last commit before the 1.16.0 Axiom
merge (PR #45) replaced them with the role-based registry shape.

They are **engine runtime data**, co-located with
`migrate-0017-axiom-destination.sh`, and serve two consumers:

1. **The apply engine** uses each old template as the *extraction guide* when
   re-materialising a project's wrapper: a clean project wrapper is, by
   construction, a token-substituted copy of one of these files, so the engine
   recovers each token's real value by aligning the old-template token lines
   against the project wrapper, then injects those values into the new
   registry-dispatched template (preserving the project's service name, sample
   rates, redacted-keys list, env-var names, Go package name).

2. **The 0017 test fixtures** materialise synthetic project wrappers from these
   bytes (`migrations/test-fixtures/0017/common-setup.sh`), and the baseline
   regenerator (`migrations/test-fixtures/0017/regen-hashes.sh`) hashes their
   canonical form into `migrations/test-fixtures/0017/known-wrapper-hashes.json`.

## Why vendored instead of `git show main:...`

The fixtures and the regenerator originally sourced the OLD wrapper from
`git show main:...`. That silently broke the instant PR #45 merged, because
`main` then returned the NEW wrapper (which already contains `buildRegistry`),
so every "clean" fixture was mis-classified *already-applied* and the suite
became a no-op. Vendoring the bytes makes both the engine and the fixtures
hermetic — independent of git history and immune to any future movement of
`main`.

## Regenerating

If the v0.4.x baseline ever legitimately changes, re-vendor from the appropriate
commit and run `bash migrations/test-fixtures/0017/regen-hashes.sh` to recompute
`known-wrapper-hashes.json`. The recorded hashes correspond to the canonical
form of exactly these bytes.
