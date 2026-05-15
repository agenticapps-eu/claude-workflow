# baseline-template.json — token reference

This file is a **template**, not literal JSON. The `{{TOKEN}}` placeholders are
filled at scan time by `SCAN.md` Phase 7 (writer) and `APPLY.md` Phase 6b
(regenerate-on-apply). The output written to `.observability/baseline.json`
in the user's project IS literal JSON that parses with `jq`.

The shape matches AgenticApps core spec §10.9.2 (`spec_version: 0.3.0`)
lines 184-217 byte-for-byte.

## Token reference

| Token | Source | Constraint |
|---|---|---|
| `{{DATE_ISO}}` | `date -u +%Y-%m-%dT%H:%M:%SZ` | RFC 3339 UTC. |
| `{{COMMIT_SHA}}` | `git rev-parse HEAD` | 40-char lowercase hex. **Never** abbreviated, **never** the string `"working-tree"`. If the project has no commits, scan aborts (Phase 7 pre-condition). |
| `{{STACK_ID}}` / `{{PATH}}` | SCAN.md Phase 1 detection | One `{stack, path}` object per detected module root. The `module_roots` array is sorted **lexicographically by `(stack, path)`** so re-scans of an unchanged project produce a byte-identical baseline. |
| `{{N_CONFORMANT}}` / `{{N_HIGH}}` / `{{N_MEDIUM}}` / `{{N_LOW}}` | SCAN.md Phase 5 aggregation | Non-negative integers (no quotes). |
| `{{N_C1}}` / `{{N_C2}}` / `{{N_C3}}` / `{{N_C4}}` | SCAN.md Phase 5 per-checklist tally | Non-negative integers. Sum equals `{{N_HIGH}}`. |
| `{{POLICY_HASH_HEX}}` | `shasum -a 256 <policy.md path>` | 64-char lowercase hex. The full rendered field is `"sha256:<HEX>"`. **Never** null, **never** a degraded value. Projects without `policy.md` cannot emit a baseline (Phase 7 pre-condition; migration 0011 pre-flight). |

## Why the strict schema?

The dashboard, CI gate, and drift-report tooling all read this file and
assume the spec-documented shape. Permitting `null` / `"working-tree"` / abbreviated
SHAs would force every consumer to special-case those values — a non-spec-conformant
artefact that pretends to satisfy §10.9.2 while breaking dependents downstream.

The migration that creates the initial baseline (0011) aborts pre-flight if any of
these invariants can't be satisfied, with a clear remediation message telling the
user to run `add-observability init` first.
