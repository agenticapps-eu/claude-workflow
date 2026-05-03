---
id: 0001
slug: go-impeccable-database-sentinel
title: Wire Go skill packs + impeccable + database-sentinel into AgenticApps workflow
from_version: 1.2.0
to_version: 1.3.0
applies_to:
  - .claude/workflow-config.md
  - .planning/config.json
  - CLAUDE.md
  - docs/decisions/
  - templates/adr-db-security-acceptance.md (new template artifact for project use)
requires:
  - skill: impeccable
    install: "npx skills add pbakaus/impeccable"
    verify: "test -f ~/.claude/skills/impeccable/SKILL.md"
  - skill: database-sentinel
    install: "git clone https://github.com/Farenhytee/database-sentinel ~/.claude/skills/database-sentinel"
    verify: "test -f ~/.claude/skills/database-sentinel/SKILL.md"
optional_for:
  - tag: go
    detect: "find . -name '*.go' -not -path '*/node_modules/*' -not -path '*/vendor/*' | head -1 | grep -q ."
    note: "Go-specific routing rows still install (they're just rows in markdown / JSON), but the runtime won't auto-trigger Go skill packs in non-Go projects."
---

# Migration 0001 — Wire Go skill packs + impeccable + database-sentinel

Brings projects from AgenticApps workflow v1.2.0 to v1.3.0 by adding three
new gate integrations — Go language routing, impeccable design quality, and
database-sentinel RLS audit — to the project's local workflow files.

This is a content-only migration: no breaking changes, no behavior changes
in unrelated paths. The project's existing hooks continue to fire as before;
new hooks fire only when their triggers match.

## Pre-flight

```bash
# Required: project at exactly v1.2.0 (or unknown — if migration framework
# rolls past, the update skill chains earlier migrations first)
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | sed 's/version: //')
test "$INSTALLED" = "1.2.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.2.0"; exit 1; }

# Required: skills must be installed (per requires block)
test -f ~/.claude/skills/impeccable/SKILL.md || { echo "ERROR: install impeccable first: npx skills add pbakaus/impeccable"; exit 1; }
test -f ~/.claude/skills/database-sentinel/SKILL.md || { echo "ERROR: install database-sentinel first: git clone https://github.com/Farenhytee/database-sentinel ~/.claude/skills/database-sentinel"; exit 1; }

# Required: project files exist (this migration patches them, doesn't create them)
test -f .claude/workflow-config.md || { echo "ERROR: .claude/workflow-config.md not found — was 0000-baseline applied?"; exit 1; }
test -f .planning/config.json || { echo "ERROR: .planning/config.json not found — was 0000-baseline applied?"; exit 1; }
test -f CLAUDE.md || { echo "ERROR: CLAUDE.md not found — was 0000-baseline applied?"; exit 1; }
```

## Steps

### Step 1: Add Backend language routing section to `.claude/workflow-config.md`

**Idempotency check:** `grep -q "^## Backend language routing" .claude/workflow-config.md`
**Pre-condition:** the file exists and has a `## Conventions` section
**Apply:** insert this block immediately after the `## Conventions` section
(before the `## Superpowers Integration Hooks` heading):

```markdown
## Backend language routing

| Detection | Skills auto-triggered | Notes |
|---|---|---|
| `*.go` files in plan | `samber:cc-skills-golang`, `netresearch:go-development-skill` | Auto-load on Go scope |
| `*.ts`, `*.tsx` files in plan | `QuantumLynx:ts-react-linter-driven-development` | Frontend + Node TS |
| `*.py` files in plan | (none yet — see README §Per-language skill packs → Python) | LLM/agent backends |

For mixed-language phases, all matching skill packs trigger; skills self-scope by file. Install per-project (not global) so non-language repos don't pay the context cost — see README "Per-language skill packs" for install commands.
```

**Rollback:** delete the inserted block (anchored by the `## Backend language routing` heading through the trailing paragraph that ends with "install commands.").

### Step 2: Add `design_critique` row to Pre-Phase hook table in `.claude/workflow-config.md`

**Idempotency check:** `grep -q "design_critique" .claude/workflow-config.md`
**Pre-condition:** the file has a `### Pre-Phase` table with a `brainstorm_architecture` row
**Apply:** insert this row immediately after the `brainstorm_architecture` row in the Pre-Phase table:

```markdown
| `design_critique` | After `/design-shotgun` produces variants, before user picks | `impeccable:critique` | Score variants against impeccable's 24 anti-patterns. Failing variants are flagged before reaching the user. |
```

**Rollback:** delete the row.

### Step 3: Replace Post-Phase `cso` row in `.claude/workflow-config.md`

**Idempotency check:** `grep -q "if Supabase / Postgres / MongoDB touched" .claude/workflow-config.md`
**Pre-condition:** the file has the original cso row (`| \`cso\` | Phase touches auth, storage, API, or LLM | \`/cso\` | OWASP security scan |`)
**Apply:** replace the existing cso row with:

```markdown
| `cso` | Phase touches auth, storage, API, or LLM | `gstack:/cso` + `database-sentinel:audit` (if Supabase / Postgres / MongoDB touched) | OWASP security scan + RLS / DB security audit on Supabase / Postgres / MongoDB scope. **BLOCKS branch close on unresolved Critical / High `database-sentinel` findings** unless accepted via `templates/adr-db-security-acceptance.md`. |
```

**Rollback:** restore the original row text.

### Step 4: Add `design_critique` entry to `.planning/config.json` `pre_phase` block

**Idempotency check:** `jq -e '.hooks.pre_phase.design_critique' .planning/config.json >/dev/null`
**Pre-condition:** `.planning/config.json` parses as JSON and has `.hooks.pre_phase.design_shotgun`
**Apply:** insert the following entry as a sibling of `design_shotgun`:

```json
"design_critique": {
  "enabled": true,
  "skill": "impeccable:critique",
  "trigger": "ui_hint_yes && design_shotgun_completed",
  "evidence": "UI-SPEC.md cites impeccable critique scores per variant"
}
```

**Rollback:** `jq 'del(.hooks.pre_phase.design_critique)' .planning/config.json > .tmp && mv .tmp .planning/config.json`

### Step 5: Extend `.planning/config.json` `post_phase.security` with `sub_gates` array

**Idempotency check:** `jq -e '(.hooks.post_phase.security.sub_gates // []) | any(.skill == "database-sentinel:audit")' .planning/config.json >/dev/null 2>&1`
**Pre-condition:** `.planning/config.json` has `.hooks.post_phase.security`
**Apply:** add a `sub_gates` array to the existing `security` entry. The
fragment to add (sibling of the existing `evidence` key inside `security`):

```json
"sub_gates": [
  {
    "skill": "database-sentinel:audit",
    "trigger": "scope matches supabase|postgres|mongodb",
    "evidence": "DB-AUDIT.md in phase directory; all High and Critical findings resolved or acknowledged via templates/adr-db-security-acceptance.md; otherwise BLOCKS branch close"
  }
]
```

For deterministic apply (avoids agent-prose ambiguity about nesting level):

```bash
jq '.hooks.post_phase.security.sub_gates = [
  {
    "skill": "database-sentinel:audit",
    "trigger": "scope matches supabase|postgres|mongodb",
    "evidence": "DB-AUDIT.md in phase directory; all High and Critical findings resolved or acknowledged via templates/adr-db-security-acceptance.md; otherwise BLOCKS branch close"
  }
]' .planning/config.json > .planning/config.json.tmp && mv .planning/config.json.tmp .planning/config.json
```

**Rollback:** `jq 'del(.hooks.post_phase.security.sub_gates)' .planning/config.json > .tmp && mv .tmp .planning/config.json`

### Step 6: Add `impeccable_audit` and `db_pre_launch_audit` entries to `.planning/config.json` `finishing` block

**Idempotency check:** `jq -e '.hooks.finishing.impeccable_audit and .hooks.finishing.db_pre_launch_audit' .planning/config.json >/dev/null`
**Pre-condition:** `.planning/config.json` has `.hooks.finishing.branch_close`
**Apply:** insert both entries as siblings of `branch_close` inside `.hooks.finishing`:

```json
"impeccable_audit": {
  "enabled": true,
  "skill": "impeccable:audit",
  "trigger": "feature touches frontend && branch ready to merge",
  "evidence": "audit report referenced in PR description; no Red findings unresolved"
},
"db_pre_launch_audit": {
  "enabled": true,
  "skill": "database-sentinel:audit",
  "scope": "full — audit every supported backend in the project, not phase-scoped",
  "trigger": "branch is main && app pre-launch checklist active",
  "evidence": "Pre-launch DB-AUDIT.md with zero Critical, zero High findings; otherwise BLOCKS launch"
}
```

For deterministic apply:

```bash
jq '.hooks.finishing += {
  "impeccable_audit": {
    "enabled": true,
    "skill": "impeccable:audit",
    "trigger": "feature touches frontend && branch ready to merge",
    "evidence": "audit report referenced in PR description; no Red findings unresolved"
  },
  "db_pre_launch_audit": {
    "enabled": true,
    "skill": "database-sentinel:audit",
    "scope": "full — audit every supported backend in the project, not phase-scoped",
    "trigger": "branch is main && app pre-launch checklist active",
    "evidence": "Pre-launch DB-AUDIT.md with zero Critical, zero High findings; otherwise BLOCKS launch"
  }
}' .planning/config.json > .planning/config.json.tmp && mv .planning/config.json.tmp .planning/config.json
```

**Rollback:** `jq 'del(.hooks.finishing.impeccable_audit) | del(.hooks.finishing.db_pre_launch_audit)' .planning/config.json > .tmp && mv .tmp .planning/config.json`

### Step 7: Replace Pre-Phase Hook 1 in `CLAUDE.md` with expanded version

**Idempotency check:** `grep -q "Brainstorm UI plans + design critique" CLAUDE.md`
**Pre-condition:** `CLAUDE.md` contains the existing Pre-Phase Hook 1 anchored by `1. **Brainstorm UI plans**`
**Apply:** replace the existing item 1 paragraph with:

```markdown
1. **Brainstorm UI plans + design critique** — For any plan with `UI hint: yes` in ROADMAP or
   frontend files in `files_modified`, you MUST invoke `superpowers:brainstorming`
   before planning. For phases generating new visual surfaces, you MUST ALSO
   run gstack `/design-shotgun` to generate 3–4 visual variants. **Then run
   `impeccable:critique` against each variant.** Variants scoring below the
   impeccable quality bar are eliminated before the user picks. Boot the dev
   server, preview via `/browse`, and get the user's explicit pick into
   UI-SPEC.md, with the impeccable score for the chosen variant recorded.
   No skipping this for "obvious" designs.
```

**Rollback:** restore the original Hook 1 text (the v1.2.0 version, three lines, no impeccable).

### Step 8: Expand Post-Phase Hook 8 in `CLAUDE.md` with database-sentinel sub-gate

**Idempotency check:** `grep -q "produces exact SQL DDL fixes" CLAUDE.md`
**Pre-condition:** `CLAUDE.md` contains the existing Post-Phase Hook 8 anchored by `8. **Security scan** — Run gstack \`/cso\``
**Apply:** replace the existing Hook 8 paragraph with:

```markdown
8. **Security scan** — Run gstack `/cso` when the phase touches auth, storage,
   API endpoints, or LLM prompt construction. Output: SECURITY.md.
   **Additionally,** when the phase touches Supabase / Postgres / MongoDB,
   you MUST also run `database-sentinel:audit`. Output: DB-AUDIT.md.
   Critical or High findings BLOCK branch close — they must be fixed
   (database-sentinel produces exact SQL DDL fixes) or accepted via ADR with
   user-explicit override using the template at
   `templates/adr-db-security-acceptance.md`.
```

**Rollback:** restore the original Hook 8 text (two lines, no Additionally clause).

### Step 9: Copy `templates/adr-db-security-acceptance.md` into the project's `templates/` directory

**Idempotency check:** `test -f templates/adr-db-security-acceptance.md`
**Pre-condition:** the source template exists at `~/.claude/skills/agenticapps-workflow/templates/adr-db-security-acceptance.md`
**Apply:**
```bash
mkdir -p templates
cp ~/.claude/skills/agenticapps-workflow/templates/adr-db-security-acceptance.md templates/adr-db-security-acceptance.md
```
**Rollback:** `rm -f templates/adr-db-security-acceptance.md`

### Step 10: Bump installed version field in `.claude/skills/agentic-apps-workflow/SKILL.md`

**Idempotency check:** `grep -q '^version: 1.3.0' .claude/skills/agentic-apps-workflow/SKILL.md`
**Pre-condition:** `.claude/skills/agentic-apps-workflow/SKILL.md` exists and currently has `version: 1.2.0`
**Apply:** Edit the file frontmatter to change `version: 1.2.0` → `version: 1.3.0`.
**Rollback:** Edit `version: 1.3.0` → `version: 1.2.0`.

## Post-checks

```bash
# Markdown patches landed
grep -q "^## Backend language routing" .claude/workflow-config.md
grep -q "design_critique" .claude/workflow-config.md
grep -q "if Supabase / Postgres / MongoDB touched" .claude/workflow-config.md  # anchor on phrase, not backtick-bracketed token (matches Step 3 idempotency-check fix)

# JSON entries present + structurally valid
jq -e '.hooks.pre_phase.design_critique' .planning/config.json
jq -e '.hooks.post_phase.security.sub_gates[0]' .planning/config.json
jq -e '.hooks.finishing.impeccable_audit' .planning/config.json
jq -e '.hooks.finishing.db_pre_launch_audit' .planning/config.json

# CLAUDE.md updated
grep -q "Brainstorm UI plans + design critique" CLAUDE.md
grep -q "database-sentinel:audit" CLAUDE.md

# ADR template copied
test -f templates/adr-db-security-acceptance.md

# Version bumped
grep -q '^version: 1.3.0' .claude/skills/agentic-apps-workflow/SKILL.md
```

The update skill runs each post-check and reports any failures.

## ADR opportunities

After this migration, the update skill prompts: "Want to draft project ADRs
for the new gates? Three options: (a) ADR per gate (3 ADRs), (b) one bundled
ADR, (c) skip — accept upstream's ADRs as the rationale." Default: (c).
The upstream ADRs (0010, 0011, 0012 in the workflow scaffolder repo) are
the canonical rationale; per-project ADRs are only needed if the project
overrides defaults (e.g. raises the impeccable quality bar, narrows the
database-sentinel trigger scope).

## Skip cases

- **Project not at v1.2.0** — pre-flight blocks. The update skill is responsible
  for chaining earlier migrations first if the project is older.
- **Required skills not installed** — pre-flight blocks. The update skill prompts
  the user with the install commands and waits.
- **`.planning/config.json` missing** — pre-flight blocks with "no GSD setup
  detected; use /setup-agenticapps-workflow first."
- **Already at 1.3.0** — every step's idempotency check returns 0; entire
  migration short-circuits to "0 of 10 steps applied (all already present)".
