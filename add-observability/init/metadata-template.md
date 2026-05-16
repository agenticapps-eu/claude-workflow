# `observability:` CLAUDE.md metadata block — canonical schema

This is the authoritative reference for the `observability:` YAML block
that init's Phase 6 writes into a project's CLAUDE.md (per spec §10.8).
Init's Phase 6 references this document; the schema below is the
source of truth for the block's shape and validation contract at
add-observability v0.3.1 (`implements_spec: 0.3.0`).

## Canonical block shape

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: <primary-stack-wrapper-dir>/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

The block is wrapped in anchor comments when init writes it:

```markdown
<!-- agenticapps:observability:start -->
observability:
  spec_version: 0.3.0
  ...
<!-- agenticapps:observability:end -->
```

The anchors are load-bearing: they let init's re-detection logic
(see "Add vs update vs conflict" below) target the block precisely
without touching surrounding hand-written content.

## Field contract

### `spec_version` (required)

The spec version this project conforms to. At v0.3.1 of the
`add-observability` skill, this MUST be `0.3.0` — the spec version
implemented by the current `implements_spec` declaration. This field
is what migration 0011's pre-flight compares against to decide
whether the project has been initialised under a compatible spec.

### `destinations` (required, list)

The configured emission destinations. Each list item is a
single-key map: the key is the data class (`errors`, `logs`,
`analytics`), the value is the destination identifier (vendor name
or `self-hosted`).

Minimum at v0.3.0:

- `errors:` — required. Default ships `sentry`.
- `logs:` — required. Default ships `structured-json-stdout` (host
  runtime captures stdout JSON; no separate ingestion needed).
- `analytics:` — OPTIONAL per spec §10.8. Omitted by default; users
  who run analytics-class events through the wrapper add this line
  manually.

### `policy:` (required, **scalar string**)

A single string path — relative to the project root — pointing at
the active policy.md file (per stack templates from
`templates/<stack>/policy.md.template` materialised at init time).

**Schema constraint (v0.3.1)**: this field MUST be a scalar string,
NOT a list, NOT a map. This constraint is load-bearing because
migration 0011's POLICY_PATH parser at
`migrations/0011-observability-enforcement.md:63` is:

```bash
POLICY_PATH=$(awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md | tr -d '"')
```

The parser reads the second whitespace-separated token on the
`policy:` line and exits on the first match. A list or map shape
would yield a non-path string (`[` or `{`) and break 0011's
pre-flight. Per-stack policy unification (one path per stack)
awaits a spec amendment; until then, multi-stack projects ship the
**primary stack's** path only (see "Multi-stack handling" below).

### `enforcement:` (OPTIONAL, object)

Added in spec v0.3.0. The sub-block governs how observability
conformance is enforced over time (per spec §10.9). Init's Phase 6
ships the `enforcement:` sub-block by default with the two fields
below; declaring the sub-block obligates the project to satisfy the
§10.9 contract for each field listed.

#### `enforcement.baseline` (required when `enforcement:` declared)

Path to the canonical baseline JSON file maintained by the scan
subcommand. Default: `.observability/baseline.json` — this is the
spec's canonical path per §10.9.2. Hosts MAY support alternate
paths via configuration, but the dashboard expects this default.

#### `enforcement.ci` (OPTIONAL — omitted by default at v0.3.1)

Path to a host-specific CI workflow that runs the delta-scan gate
(per spec §10.9.3). Example values:

- `.github/workflows/observability.yml`
- `.circleci/config.yml#observability-job`

**Omitted by init at v0.3.1** because the current option-4 shape
ships no auto-installed CI workflow. Users who add a CI workflow
manually MAY add this field; the spec uses its presence to mark
which projects have a CI gate wired up.

#### `enforcement.pre_commit` (OPTIONAL — defaults to `optional`)

One of `optional` | `enabled` | `disabled`. Controls whether a
pre-commit hook runs the scan subcommand locally before each commit
(per spec §10.9.4). Init ships `optional` by default. Projects that
flip to `enabled` MUST also ship the hook configuration; the
v0.3.1 init does NOT install the hook automatically (see PLAN.md
"Out of scope" — deferred to v0.4.0+).

## Multi-stack handling

When init detects multiple stacks, the `policy:` field ships the
**primary stack's** policy.md path only. Primary stack =
lexicographic first detected stack ID (matching the wrapper write
order in Phase 4).

Other stacks' policy.md files are still materialised by Phase 4
(each at `<stack-module-root>/<target.policy_path>`), but they are
NOT referenced from the CLAUDE.md `observability:` block at v0.3.1.

Init's Phase 6 prints an explicit notice before the consent prompt
when multi-stack is detected:

```
Multi-stack project detected (<stack-1>, <stack-2>, ...). The
`observability:` block's `policy:` field is scalar for v0.3.1 per
spec §10.8. Primary stack `<stack-1>`'s policy path is recorded.
Other stacks' policy.md files are materialised but not referenced
from CLAUDE.md. Per-stack policy unification awaits a spec
amendment.
```

Per-stack policy unification is tracked as a follow-up against the
agenticapps-workflow-core spec.

## Validation

Init's Phase 9 verifies the written block by running the canonical
0011 parser invocation against the materialised CLAUDE.md:

```bash
awk '/<!-- agenticapps:observability:start -->/,/<!-- agenticapps:observability:end -->/' CLAUDE.md \
  | grep -qE '^observability:' \
  && awk '/^observability:/{flag=1} flag && /^[[:space:]]*policy:/{print $2; exit}' CLAUDE.md \
     | grep -qE '^[^ ]+$'
```

If gate 3 was accepted but the assertions fail, init exits with
code 1 and the failing assertion is printed. The assertions check
two invariants:

1. The anchor pair brackets an `observability:` block (top-level
   YAML key present inside the anchored region).
2. The `policy:` field parses to a single-token scalar string
   (the only shape 0011's parser accepts).

## Add vs update vs conflict — detection paths

Init's Phase 6 distinguishes three pre-existing-state cases when it
inspects the project's CLAUDE.md before writing:

| Pre-existing state | Detection | Path |
|--------------------|-----------|------|
| No `observability:` line; no anchor markers | Neither anchor nor `^observability:` line found by grep | **Add** — append the block at end of file, anchored |
| Anchored block present (init was run before) | Anchor pair found AND `^observability:` line inside the anchors | **Update** — replace the anchored region's body with the freshly computed block; preserve surrounding hand-written content. Show unified diff for the consent prompt. |
| Unanchored `observability:` line present (manual hand-curated block, predates anchor convention) | `^observability:` line found AND no anchor pair around it | **Conflict** — print manual-merge hint; treat as gate-3 decline |

### Add path

The clean case: no observability metadata present. Init appends:

```
\n<!-- agenticapps:observability:start -->
<the computed block>
<!-- agenticapps:observability:end -->
```

at the end of CLAUDE.md (with one separating blank line above the
opening anchor).

### Update path

The re-init case (will become relevant at v0.4.0+ when `--force` is
unlocked; at v0.3.1 strict-first-run, init typically aborts in
Phase 2 if wrappers already exist — but the metadata block can be
out of date even when wrappers are valid, e.g. after a spec bump).

Init replaces only the content between the anchor markers. The
unified diff in the consent prompt shows the swap. Content outside
the anchors is preserved byte-for-byte.

### Conflict path

A project's CLAUDE.md may already declare `observability:` via a
hand-written block predating the anchor convention (or written by
a different tool). Auto-replacing it risks losing user-tuned values
(e.g. a custom `policy:` path, an `analytics:` destination init
wouldn't have added). Conflict mode prints:

```
CLAUDE.md already declares an `observability:` block, but it is
not wrapped in `<!-- agenticapps:observability:start -->` /
`<!-- agenticapps:observability:end -->` anchor markers. Init will
NOT overwrite hand-curated metadata blindly.

To resolve:
  1. Verify the existing block satisfies the §10.8 schema (see
     add-observability/init/metadata-template.md for the canonical
     shape).
  2. Wrap the block with the anchor comments above and below.
  3. Re-run `/add-observability init` — Phase 6 will then detect
     the anchored block and switch to the update path.

Phase 6 is being skipped. The wrapper and entry-file scaffolding
from Phases 4-5 remain in place; only the metadata-block update
is blocked.
```

Init treats this as a gate-3 decline (per Phase 6 decline-path
contract): the wrapper + entry-file rewrites stay, but the
CLAUDE.md block is not modified.

## Examples

### Single-stack worker

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: src/lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

### Multi-stack monorepo (Go backend + Vite frontend; Go is
primary by lexicographic order)

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
  policy: backend/internal/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    pre_commit: optional
```

(Note: the frontend's `frontend/src/lib/observability/policy.md`
is materialised on disk but not referenced from the block. Per
spec §10.5 each stack's policy.md still governs that stack's
emissions; the CLAUDE.md scalar `policy:` field is the
project-level citation for the primary stack only.)

### Project with CI gate wired (user adds `enforcement.ci:`
manually post-init)

```yaml
observability:
  spec_version: 0.3.0
  destinations:
    - errors: sentry
    - logs: structured-json-stdout
    - analytics: posthog
  policy: src/lib/observability/policy.md
  enforcement:
    baseline: .observability/baseline.json
    ci: .github/workflows/observability.yml
    pre_commit: enabled
```

## References

- Spec §10.8 (project metadata): `agenticapps-workflow-core/spec/10-observability.md`
- Spec §10.9 (conformance enforcement): same file
- Migration 0011 POLICY_PATH parser: `migrations/0011-observability-enforcement.md:63`
- Init Phase 6 procedure: `./INIT.md` (search for "Phase 6 — Write")
- Phase plan: `.planning/phases/15-init-and-slash-discovery/PLAN.md` (T11)
