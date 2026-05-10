---
id: 0002
slug: observability-spec-0.2.1
title: AgenticApps spec §10 v0.2.1 — install add-observability skill
from_version: 1.4.0
to_version: 1.5.0
applies_to: all
requires: []
optional_for: []
---

# Migration 0002 — Install `add-observability` skill (spec §10 v0.2.1)

## Summary

Installs the `add-observability` skill into the project's
`.claude/skills/` directory. After this migration, the project gains
three slash commands for AgenticApps observability:

- `/add-observability init` — scaffold the wrapper module + middleware into each detected stack
- `/add-observability scan` — audit conformance against spec §10.4, produce `.scan-report.md`
- `/add-observability scan-apply` — apply high-confidence gaps with per-file consent

**Non-destructive.** This migration only adds files under `.claude/skills/add-observability/` and bumps the workflow version. It does NOT instrument the project's source code. To do that, the project owner explicitly invokes `init` (greenfield) and/or `scan-apply` (brownfield) afterward, ideally on a feature branch with proper review per the project's CLAUDE.md discipline.

## Pre-flight

```bash
# Verify agenticapps-workflow skill is installed and at 1.4.x (this migration's prerequisite)
test -f .claude/skills/agentic-apps-workflow/SKILL.md \
  || (echo "ERROR: agenticapps-workflow skill not installed; run /setup-agenticapps-workflow first" && exit 1)

INSTALLED_VERSION=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | awk '{print $2}')
case "$INSTALLED_VERSION" in
  1.4.*) ;;
  *) echo "ERROR: requires agenticapps-workflow == 1.4.x (installed: $INSTALLED_VERSION). Apply earlier migrations first."; exit 1 ;;
esac

# Source repo must be available — the migration copies from there
SOURCE_DIR="${CLAUDE_WORKFLOW_SOURCE:-$HOME/Sourcecode/claude-workflow}"
test -d "$SOURCE_DIR/add-observability" \
  || (echo "ERROR: $SOURCE_DIR/add-observability not found. Set CLAUDE_WORKFLOW_SOURCE or clone claude-workflow." && exit 1)
test -f "$SOURCE_DIR/add-observability/SKILL.md" \
  || (echo "ERROR: $SOURCE_DIR/add-observability/SKILL.md missing — incomplete checkout?" && exit 1)
```

## Steps

### Step 1 — Install the `add-observability` skill

**Idempotency check:**

```bash
test -f .claude/skills/add-observability/SKILL.md \
  && grep -q "implements_spec: 0.2.1" .claude/skills/add-observability/SKILL.md
```

If this check passes, the skill is already installed at the target version — skip this step. Re-running this migration on an already-migrated project is a no-op for step 1.

**Pre-condition:**

```bash
test -d .claude/skills/ \
  && test -d "$SOURCE_DIR/add-observability/" \
  && test -d "$SOURCE_DIR/add-observability/templates/"
```

**Apply:**

```bash
# Copy the skill, including its sub-skills (init, scan, scan-apply)
# and per-stack templates.
cp -r "$SOURCE_DIR/add-observability" .claude/skills/add-observability

# Verify the copy includes everything we expect
test -f .claude/skills/add-observability/SKILL.md
test -f .claude/skills/add-observability/scan/SCAN.md
test -f .claude/skills/add-observability/scan/checklist.md
test -f .claude/skills/add-observability/scan/detectors.md
test -f .claude/skills/add-observability/scan-apply/APPLY.md
test -d .claude/skills/add-observability/templates/ts-cloudflare-worker
test -d .claude/skills/add-observability/templates/go-fly-http
test -d .claude/skills/add-observability/templates/ts-react-vite
test -d .claude/skills/add-observability/templates/ts-cloudflare-pages
test -d .claude/skills/add-observability/templates/ts-supabase-edge
```

**Rollback:**

```bash
rm -rf .claude/skills/add-observability/
```

### Step 2 — Bump the agenticapps-workflow installed version

**Idempotency check:**

```bash
grep -q "^version: 1\.5\.0" .claude/skills/agentic-apps-workflow/SKILL.md
```

**Pre-condition:**

```bash
grep -q "^version: 1\.4\." .claude/skills/agentic-apps-workflow/SKILL.md
```

**Apply:**

Edit `.claude/skills/agentic-apps-workflow/SKILL.md` frontmatter:

```diff
 ---
 name: agentic-apps-workflow
-version: 1.4.0
+version: 1.5.0
 ...
 ---
```

**Rollback:**

```diff
 ---
 name: agentic-apps-workflow
-version: 1.5.0
+version: 1.4.0
 ...
 ---
```

### Step 3 — Add a "Skills" reference to CLAUDE.md

**Idempotency check:**

```bash
grep -q "/add-observability" CLAUDE.md
```

**Pre-condition:**

```bash
test -f CLAUDE.md
```

**Apply:**

If CLAUDE.md has a `## Skills` or `## Available skills` section, add a row to its table or list:

```markdown
- `/add-observability` — AgenticApps spec §10 observability scaffolder + auditor (init / scan / scan-apply)
```

If CLAUDE.md has no such section, append a new section near the bottom:

```markdown
---

## Available skills

- `/add-observability` — AgenticApps spec §10 observability scaffolder + auditor.
  - `init` — greenfield: scaffold wrapper + middleware into each detected stack.
  - `scan` — audit conformance, produce `.scan-report.md`.
  - `scan-apply` — apply high-confidence gaps with per-file consent.
```

**Rollback:**

Remove the added line / section.

## Post-checks

```bash
# Skill installed and at the right version
test -f .claude/skills/add-observability/SKILL.md
grep -q "implements_spec: 0.2.1" .claude/skills/add-observability/SKILL.md

# Templates present
for stack in ts-cloudflare-worker go-fly-http ts-react-vite ts-cloudflare-pages ts-supabase-edge; do
  test -f ".claude/skills/add-observability/templates/$stack/meta.yaml" \
    || (echo "MISSING template: $stack" && exit 1)
done

# Workflow version bumped
grep -q "^version: 1\.5\.0" .claude/skills/agentic-apps-workflow/SKILL.md

# CLAUDE.md references the skill
grep -q "/add-observability" CLAUDE.md
```

## Skip cases

- **`--skip 0002`** — skill is not installed; project stays at workflow 1.4.x with respect to observability tooling. Future migrations targeting 1.5.x or beyond will refuse to run until 0002 is applied.
- **Read-only checkout** — if `.claude/skills/` is not writable, the migration aborts cleanly. Re-run after permissions are fixed.

## After this migration

The project has the skill but is **not yet instrumented**. Three paths from here:

### Greenfield path (new project, or first observability adoption)

```
/add-observability init
```

This scaffolds the wrapper, middleware, and policy.md into each detected stack (Go module roots, TypeScript package roots, Supabase functions). It does NOT modify any existing source code outside the wrapper directories — it only adds files and edits the entry-point file (`cmd/api/main.go`, `src/main.tsx`, etc.) to call `Init()` and mount the middleware.

After init, run `scan` to confirm:

```
/add-observability scan
```

### Brownfield path (existing project with established code)

```
/add-observability scan
```

Read the resulting `.scan-report.md`. The report classifies findings as high-confidence gaps (mechanical fixes), medium (heuristic — needs review), and low (suggestions).

Then:

```
/add-observability scan-apply --confidence high
```

This walks each high-confidence gap, shows a unified diff, and applies only with explicit per-file consent. Medium and low findings remain for manual review.

### Production path (cparx, fx-signals, agenticapps-dashboard)

For projects with mandatory `/review`, `/cso`, and ADR discipline (per CLAUDE.md):

1. Cut a feature branch off `main`.
2. `/superpowers:brainstorming` for an architecture brainstorm — there's an ADR template at `docs/decisions/0014-observability-adoption.md` worth filling in.
3. `/add-observability init` (one or many stacks).
4. `/add-observability scan` to surface gaps.
5. `/add-observability scan-apply --confidence high` to fix mechanical ones.
6. Manually instrument the medium-confidence business events from the report.
7. `/review` and `/cso` (and `/qa` if a dev server is reachable).
8. Open a PR.

The `pilot-cparx-2026-05-10.md` artifact in the workflow design folder shows the manual version of this flow against cparx.

## Compatibility notes

- **Spec version**: this migration installs spec §10 v0.2.1. Future spec patches (v0.2.x) are clarification-only and don't require a new migration. Spec minor bumps (v0.3.0+) ship a new migration (0003+) per ADR-0013.

- **Stack templates**: ships v0.2.1 templates for `ts-cloudflare-worker`, `ts-cloudflare-pages`, `ts-supabase-edge`, `ts-react-vite`, `go-fly-http`. Projects on stacks not in this list can still use the wrapper interface (spec §10.1) — the generator-obligation (§10.7) MUST be satisfied per host, and additional templates can be contributed as future migration patches.

- **Sentry default**: templates default to Sentry as the destination because it has mature SDKs across all five runtimes and OTLP-compatible trace format. Projects can swap to Axiom, Grafana Cloud, OpenTelemetry-collector, or self-hosted Postgres by editing the wrapper module's destination block — the application code never changes.

## References

- Spec: `agenticapps-workflow-core/spec/10-observability.md` v0.2.1
- ADR: `agenticapps-workflow-core/adrs/0014-observability-architecture.md`
- Migration framework: ADR-0013 (`docs/decisions/0013-migration-framework.md`)
- Skill scaffold: `claude-workflow/add-observability/SKILL.md`
- Pilot report: `agentic-workflow/pilot-cparx-2026-05-10.md`
