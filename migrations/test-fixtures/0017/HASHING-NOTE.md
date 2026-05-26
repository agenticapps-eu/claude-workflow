# Migration 0017 — known-wrapper-hashes.json hashing method & coverage

## What is hashed

`known-wrapper-hashes.json` records the **sha256 of the file bytes** of each
stack's OLD (pre-1.16.0) scaffolded observability **wrapper entry file** — the
shape a downstream project legitimately has before migration 0017 runs. The
bytes are taken verbatim from the claude-workflow `main` branch at
add-observability v0.4.x (the wrapper templates that shipped before the
Phase-21 role-based-destination rewrite).

Regenerate any entry with:

```bash
git show main:add-observability/templates/<stack>/<wrapper_file> | shasum -a 256
```

`shasum -a 256` (BSD/macOS) and `sha256sum` (GNU) produce identical digests; the
migration's detection script accepts either.

## Version coverage

Only the **v0.4.x** baseline is included. Rationale:

- v0.4.x is the wrapper shape that shipped on `main` immediately before this
  branch (the `withSentry`/`Sentry.init` inline-Sentry wrapper). Every project
  eligible for 0017 (`from_version: 1.15.0`) carries this shape.
- v0.3.x wrappers (spec 0.2.1 / 0.3.0 era) are NOT included. Those projects
  would have been brought to the v0.4.x wrapper by the spec-0.4.0 absorption
  (workflow 1.14.0, migration 0014 + the add-observability 0.4.0 retarget)
  BEFORE they could reach `from_version: 1.15.0`. A project still on a v0.3.x
  wrapper is below `from_version` and is gated out by 0017's pre-flight, so a
  v0.3.x baseline hash would be dead weight. If a future audit discovers
  surviving v0.3.x wrappers in the wild, add a `"0.3.x"` sub-key per stack with
  the digest recovered from the relevant historical `main` commit.

`ts-cloudflare-pages` is intentionally **absent**: it shipped no wrapper before
1.16.0 (its full contract harness was backfilled on this same branch, P2.3), so
no downstream cf-pages project can have a pre-existing wrapper to detect. A
cf-pages project reaching 0017 has no materialised wrapper for that stack and is
handled by the "no wrapper (pre-init)" skip path.

## Token-substitution caveat (real projects vs. fixtures)

The recorded digests are over the **template** bytes, which still contain
generator tokens (e.g. `{{ENV_VAR_DSN}}`, `{{service_name_default}}`). A real
materialised project has those tokens substituted, so its on-disk wrapper will
NOT byte-match the template digest directly.

The detection script therefore **canonicalises** a candidate wrapper back toward
the template form before hashing — it re-inserts the known generator tokens by
reversing the documented substitutions (DSN env var name, service name,
deploy-env) read from the project's own `observability:`/env metadata. The test
fixtures exercise the byte-identical path (they materialise wrappers from the
exact template bytes, so canonicalisation is a no-op and the digest matches
directly); the canonicalisation step is what makes the same check meaningful
against a genuinely substituted downstream wrapper. If canonicalisation cannot
fully reconstruct the template form (unknown substitution), the script treats
the root as hand-modified and refuses — fail-closed, never silently overwrite.
