---
name: add-observability
version: 0.3.1
implements_spec: 0.3.0
description: |
  Generate or audit an observability wrapper that satisfies AgenticApps
  core spec §10 for the project's tech stack. Three subcommands:

    init        — greenfield scaffold per the 9-phase procedure in
                  ./init/INIT.md (shipped v0.3.1; closes #26). Detect
                  stacks → resolve targets → show plan → materialise
                  wrapper+middleware+policy (consent gate 1) → rewrite
                  entry file (consent gate 2) → write `observability:`
                  block in CLAUDE.md (consent gate 3) → smoke-verify →
                  summary + chain hint → structural assertions before
                  exit. Strict first-run at v0.3.1 (refuses if wrapper
                  dir already exists). Per-stack rewrite shapes for
                  ts-cloudflare-worker / ts-cloudflare-pages /
                  ts-supabase-edge / ts-react-vite / go-fly-http live
                  in INIT.md's Phase 5 detail subsections; canonical
                  CLAUDE.md metadata schema lives at
                  ./init/metadata-template.md.
    scan        — brownfield validate, produce .scan-report.md
                  Flags (v0.3.0 §10.9):
                    --since-commit <ref>  delta scan limited to files changed
                                          since <ref>; emits .observability/delta.json
                                          unconditionally (machine-readable summary)
                    --update-baseline     after a full scan, rewrite
                                          .observability/baseline.json with strict
                                          v0.3.0 schema (40-char SHA scanned_commit,
                                          sha256:<hex> policy_hash). Mutually
                                          exclusive with --since-commit.
    scan-apply  — apply high-confidence scan findings with per-file consent.
                  Regenerates .observability/baseline.json automatically on
                  successful apply (v0.3.0 §10.9.2).

  The scan subcommand is implemented as a prompt-based procedure (this
  skill drives Claude Code's Read/Grep/Write tools); init and scan-apply
  use the same pattern. Stack templates live alongside this skill in
  ./templates/<stack-id>/. Local-first enforcement guidance lives in
  ./enforcement/README.md; an opt-in §10.9.3 reference CI workflow is
  shipped as ./enforcement/observability.yml.example (NOT installed by
  migration 0011 in v1.10.0 — see enforcement/README.md for the
  rationale).
---

# add-observability — AgenticApps observability scaffolder + auditor

This skill implements the **generator obligation** in core spec §10.7
for AgenticApps projects (`cparx`, `fx-signals`, `agenticapps-dashboard`,
and future projects). It is a Claude Code skill: when invoked, you (the
agent) follow the procedure prompts below using the Read, Grep, Write,
and Edit tools.

## Dispatch

The skill takes one positional argument (the subcommand) and delegates
to a sub-skill prompt:

| Subcommand   | Sub-skill prompt              | Purpose                                            |
|--------------|-------------------------------|----------------------------------------------------|
| `init`       | `./init/INIT.md`              | Greenfield scaffold + wiring (9 phases, 3 consent gates; shipped v0.3.1, closes #26). |
| `scan`       | `./scan/SCAN.md`              | Walk project, produce `.scan-report.md`.           |
| `scan-apply` | `./scan-apply/APPLY.md`       | Apply high-confidence findings with consent.       |

If the subcommand is omitted, default to `scan` (the safest no-op
operation; produces a report without modifying anything).

**Routing-table structural invariant**: every `Sub-skill prompt` path
in the table above MUST exist on disk inside this skill directory.
This is a contractual invariant — slash-discovery loads the skill via
the symlink at `~/.claude/skills/add-observability` (per migration
0002 Step 4 / migration 0012), and dispatch resolves the routed paths
relative to the skill root. A missing routed path means the
subcommand is unrunnable. The mechanical Q8 check enforced during
phase planning (introduced phase 15; codified in `.planning/`'s
gsd-review prompt template per the PLAN v2 lesson) is:

```bash
grep -oiE '\./[a-zA-Z/_-]+\.md' add-observability/SKILL.md | sort -u | while read rel; do
  abs="add-observability/${rel#./}"
  [ -f "$abs" ] && echo "  OK $rel" || echo "  MISSING $rel"
done
```

All four routed paths (`./init/INIT.md`, `./scan/SCAN.md`,
`./scan-apply/APPLY.md`, `./enforcement/README.md`) resolve as of
v0.3.1. The `./init/INIT.md` path was historically MISSING at v0.3.0
(issue #26); shipping that file structurally closes #26 and is the
load-bearing piece of this version bump.

## Resolution rules

Per spec §10.7.1 (added v0.2.1), all target paths in this skill are
resolved against the **language module root**, not the project root.
The init and scan procedures detect module roots by scanning for
`path_root` manifest files declared in each stack's `templates/<stack-id>/meta.yaml`.

## Stack templates

The per-stack code templates live at `./templates/<stack-id>/`. Each
contains `meta.yaml` (detection signals + target paths + parameters),
the wrapper module, the middleware, env-additions docs, and a contract
test fixture.

Currently shipped:

| Stack ID                  | Manifest          | Purpose                                          |
|---------------------------|-------------------|--------------------------------------------------|
| `ts-cloudflare-worker`    | `package.json`    | Cloudflare Workers (fetch, scheduled, queue).    |
| `ts-cloudflare-pages`     | `package.json`    | Cloudflare Pages Functions.                      |
| `ts-supabase-edge`        | `supabase/config.toml` | Supabase Edge Functions (Deno).             |
| `ts-react-vite`           | `package.json`    | React + Vite SPA frontends.                      |
| `go-fly-http`             | `go.mod`          | Go HTTP services on Fly.io (chi, std net/http).  |

## Conformance with spec §10.7

This skill satisfies §10.7's four generator-obligation requirements:

1. **Scaffolds wrapper modules per stack** — `init` subcommand emits
   into the project from `templates/<stack-id>/`.
2. **Wires trace propagation middleware** — `init` writes the
   middleware files and edits the entry-point file.
3. **Validates existing projects** — `scan` subcommand walks the
   project against `scan/checklist.md` and emits a confidence-ranked
   report.
4. **Apply only with consent** — `scan-apply` shows per-file diffs and
   requires explicit confirmation; never auto-applies.

## When to invoke

| User intent                                            | Subcommand    |
|--------------------------------------------------------|---------------|
| New project; wire observability from scratch           | `init`        |
| Existing project; check conformance, no changes        | `scan`        |
| Existing project; apply scan-found high-confidence gaps | `scan-apply`  |
| Migration framework upgrade (per ADR-0013)             | `init` then `scan` |

The Claude Code workflow integration lives in
`migrations-fragment.md` and is consumed by the migrations framework
(per ADR-0013) when adopting spec v0.2.x in an existing project.
