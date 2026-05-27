# Migration 0017 — known-wrapper-hashes.json hashing method & coverage

## What is hashed

`known-wrapper-hashes.json` records, per stack, the **sha256 of the CANONICAL
(structurally masked) form** of that stack's OLD (pre-1.16.0) scaffolded
observability **wrapper entry file** — the shape a downstream project
legitimately has before migration 0017 runs. The template bytes are taken from
the claude-workflow `main` branch at add-observability v0.4.x (the wrapper
templates that shipped before the Phase-21 role-based-destination rewrite),
then run through the masking transform described below before hashing.

The recorded digest is **NOT** the raw template bytes (schema_version 1 stored
those; schema_version 2 stores the masked digest). The reason is the
token-substitution reality described under "Canonicalisation" below: a real
materialised wrapper has its generator tokens substituted, so it never
byte-matches the raw template — only its masked form matches the masked
template.

Regenerate the file with:

```bash
bash migrations/test-fixtures/0017/regen-hashes.sh          # rewrite in place
bash migrations/test-fixtures/0017/regen-hashes.sh --check  # drift check (CI)
```

`regen-hashes.sh` extracts the masking program **verbatim** from the apply
engine (`templates/.claude/scripts/migrate-0017-axiom-destination.sh`,
`canonicalize_awk`) so the recorded baseline and the runtime detection can
never drift. `shasum -a 256` (BSD/macOS) and `sha256sum` (GNU) produce
identical digests; both the regen script and the engine accept either.

## Canonicalisation (structural masking)

A real materialised wrapper has the generator tokens substituted —
`{{SERVICE_NAME}}`→`"cparx-api"`, `{{DEBUG_SAMPLE_RATE}}`→`0.1`,
`env.{{ENV_VAR_DSN}}`→`env.SENTRY_DSN`, `{{REDACTED_KEYS}}`→a multi-line list,
`{{DESTINATION}}`→`sentry`, Go `{{PACKAGE_NAME}}`→`observability`, etc. — so its
on-disk bytes never match the raw template.

The detection engine therefore **masks every token-substitution site** in BOTH
the template and the candidate wrapper down to a fixed NUL-flanked placeholder
(`\x00TOK\x00<TOKEN>\x00TOK\x00`), then hashes the masked text. Masking is
**structural**, anchored on the surrounding code (the `const NAME =` / field /
header / `package` / array-literal each token sits in), so the substituted
VALUE is immaterial:

- `Service:` / `Destination:` header comment lines → value after the label.
- `const SERVICE_DEFAULT = "…"` (TS) and `serviceName = "…"` (Go) → quoted value.
- `const DEBUG_SAMPLE_RATE = …;` / `TRACE_SAMPLE_RATE` and the Go `…SampleRate = …`
  vars → RHS literal.
- `InitEnv` interface fields `IDENT?: string;` and env-var access sites
  (`env.IDENT`, `Deno.env.get("IDENT")`, `os.Getenv("IDENT")`) → the identifier.
- Go `package IDENT` / `// Package IDENT` → the package name.
- The `REDACTED_KEYS` / `redactedKeys` array body → its list elements collapse
  to a single placeholder. Only genuine list elements (quoted-string lines, the
  template token line, blanks) are collapsed; **any non-element line inside the
  array is emitted verbatim** so an injected statement still changes the hash.

Consequence (this is the whole point — and the direction-of-error guarantee):

```
canonical(unmodified template)   ==  canonical(unmodified substituted wrapper)  → CLEAN, auto-apply
canonical(hand-modified wrapper)  !=  canonical(template)                       → REFUSE
```

Any byte **outside** a recognised token site — an added import, an altered
function body, an extra statement, even a tweak to the non-token text on a
token-bearing line — survives masking and changes the canonical digest. An
unrecognised wrapper shape therefore never collapses onto the baseline and is
treated as hand-modified. **Direction of error is toward REFUSE**: the engine
never silently overwrites a wrapper it cannot prove unmodified.

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

## Fixture coverage (real projects vs. template-identity)

Two complementary fixture shapes exercise the canonicalisation:

- **Template-identity** (fixtures 01, 02, 03, 05, 06): wrappers materialised
  from the exact `main` template bytes (tokens NOT substituted). Masking the
  template and masking the template-bytes-on-disk produce the same digest, so
  these confirm the masked baseline matches an un-substituted wrapper.
- **Realistically-substituted** (fixture 07 — the regression guard for the P5
  review): wrappers with tokens replaced by real values (service `cparx-api`,
  DSN env var `SENTRY_DSN`, sample rates `0.1`/`0.05`, a real redacted-keys
  list, Go package `observability`) but otherwise unmodified. These DO NOT
  byte-match the template, only their masked form does — they must classify
  CLEAN and AUTO-APPLY. This is the case the previous implementation got wrong:
  it reversed only `ENV_VAR_DSN`, so a substituted wrapper was mis-classified
  hand-modified and the migration never auto-applied on a real project.
- **Substituted hand-modified** (fixture 04): a realistically-substituted
  wrapper carrying a bespoke edit OUTSIDE any token site. It must still REFUSE
  after correct canonicalisation — proving refuse is not a side effect of an
  un-substituted template.

If a wrapper's masked form does not match the baseline for its stack — for any
reason, including an unrecognised substitution shape — the engine treats the
root as hand-modified and refuses: fail-closed, never silently overwrite.
