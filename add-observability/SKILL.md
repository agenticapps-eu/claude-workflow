---
name: add-observability
version: 0.2.1
implements_spec: 0.2.1
description: |
  Generate or audit an observability wrapper that satisfies AgenticApps
  core spec §10 for the project's tech stack. Three subcommands:

    init        — greenfield scaffold (write wrapper, wire middleware, add env stubs)
    scan        — brownfield validate, produce .scan-report.md
    scan-apply  — apply high-confidence scan findings with per-file consent

  The scan subcommand is implemented as a prompt-based procedure (this
  skill drives Claude Code's Read/Grep/Write tools); init and scan-apply
  use the same pattern. Stack templates live alongside this skill in
  ./templates/<stack-id>/.
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
| `init`       | `./init/INIT.md`              | Greenfield scaffold + wiring (task #2 / #3 work).  |
| `scan`       | `./scan/SCAN.md`              | Walk project, produce `.scan-report.md`.           |
| `scan-apply` | `./scan-apply/APPLY.md`       | Apply high-confidence findings with consent.       |

If the subcommand is omitted, default to `scan` (the safest no-op
operation; produces a report without modifying anything).

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
