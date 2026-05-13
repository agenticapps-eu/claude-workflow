# Phase 09 — RESEARCH

**Migration:** 0006-llm-wiki-builder-integration
**Inputs:** CONTEXT.md, ADR 0019, drafted migration body (carry-over PR #12, cleaned for stale cross-refs), current local install state (`~/Sourcecode/agenticapps/{wiki-builder,.knowledge,.wiki-compiler.json}` already present).
**Brainstorming invoked:** `superpowers:brainstorming` — alternatives surfaced + rejected with rationale.

This document answers each CONTEXT.md open question (Q1-Q5) plus two design questions surfaced during plan drafting (symlink-target validation, apply-step ordering). Each section enumerates ≥2 alternatives.

---

## Section 1 — Family detection (CONTEXT Q1)

**Question:** How does the migration decide which family directories to write `.wiki-compiler.json` into?

### Alternative 1A — Dynamic scan of `~/Sourcecode/` (chosen)

```bash
for fam_dir in ~/Sourcecode/*/; do
  fam=$(basename "$fam_dir")
  case "$fam" in personal|shared|archive|.*) continue ;; esac
  test -d "$fam_dir" || continue
  # write per-family config
done
```

**Pros:**
- Picks up families added after this migration ships (e.g. a future `clientX/` family).
- No hardcoded list that goes stale.
- Skip-list (`personal`, `shared`, `archive`) is short and explicit.

**Cons:**
- Behavior depends on filesystem state at apply time. Two machines with different family layouts get different results — but that's the desired behavior.

### Alternative 1B — Hardcoded allowlist `agenticapps factiv neuroflash` (rejected)

```bash
for fam in agenticapps factiv neuroflash; do
  test -d ~/Sourcecode/$fam || continue
  # ...
done
```

**Why rejected:** Codifies today's families into the migration body. Adding a new family later requires either editing the migration (changing history) or shipping a follow-up migration. The dynamic scan handles new families for free.

### Alternative 1C — User passes families as a CLI arg / env var (rejected)

**Why rejected:** Adds a UX surface that the migration framework doesn't otherwise support. Migrations apply non-interactively from `setup`/`update` skills; an extra arg would break that contract.

**Decision:** **1A** (dynamic scan with skip-list).

### Post-codex F2 strengthening: child-`.git` heuristic

Codex F2 noted that the bare skip-list scan would pick up unrelated top-level directories like `experiments/` or `vendor/`. Strengthened heuristic:

```bash
is_family() {
  local dir="$1"
  # Must be a directory.
  [ -d "$dir" ] || return 1
  # Skip-list.
  case "$(basename "$dir")" in personal|shared|archive|.*) return 1 ;; esac
  # Must contain at least one immediate child that's a git repo
  # (i.e. <dir>/<child>/.git exists).
  find "$dir"/*/.git -maxdepth 1 -type d -print -quit 2>/dev/null | grep -q . && return 0
  return 1
}
```

A directory containing only loose files (no git repos as children) is not treated as a family. Fixture 12-non-family-dir-skipped asserts this behavior.

---

## Section 2 — Minimal `.wiki-compiler.json` shape (CONTEXT Q2)

**Question:** What content does the migration write for families that don't already have a config?

### Alternative 2A — Match the working `agenticapps/.wiki-compiler.json` shape (chosen)

```json
{
  "version": 2,
  "name": "<Family> Knowledge",
  "mode": "knowledge",
  "sources": [
    {"path": "<family>/<repo-with-adrs>/docs/decisions", "description": "ADRs"},
    {"path": "<family>/<repo>/README.md", "description": "Repo overview"},
    {"path": "<family>/<repo>/CLAUDE.md", "description": "Repo workflow"},
    {"path": "<family>/<repo>/.planning/phases", "description": "GSD planning artifacts"}
  ],
  "output": ".knowledge/wiki/"
}
```

**Pros:**
- Field-for-field compatible with the plugin's expectations (verified working locally).
- Sources list is family-discoverable: pick up ADRs + READMEs + CLAUDE.md files + `.planning/` from any repo in the family that has them.

**Cons:**
- The sources list as drafted in carry-over hardcodes specific repo names (e.g. `agenticapps/claude-workflow/docs/decisions`). For an unknown future family that doesn't have a `claude-workflow` clone, the config would point at non-existent paths.

**Mitigation:** The plugin treats missing source paths as warnings, not errors (verified by reading `wiki-builder/plugin/skills/wiki-compiler/SKILL.md`). So a config with non-existent paths just produces a warning, and the user edits the config to fit their family's actual layout.

**Refinement:** Use glob-friendly paths where possible. `<family>/*/docs/decisions` matches any repo's `docs/decisions` directory. The plugin's source resolver expands these.

### Alternative 2B — Empty config with TODO placeholder (rejected)

```json
{
  "version": 2,
  "name": "<Family> Knowledge",
  "mode": "knowledge",
  "sources": [],
  "output": ".knowledge/wiki/"
}
```

**Why rejected:** Forces every user to edit the config before `/wiki-compile` produces anything. Defeats the "fresh install works out of the box" property.

### Alternative 2C — Discover sources at install time by walking each repo (rejected)

Walk `<family>/*/` and probe for `docs/decisions/`, `README.md`, `CLAUDE.md`, `.planning/phases/` etc. Build a sources list from what's actually present.

**Why rejected:** Substantial logic in the migration script for a one-shot config write. The user is going to inspect/edit the config anyway after install (per CONTEXT Q5 — pre-existing configs are preserved). A glob-friendly template gets them 80% there with 5 lines of script vs 50.

**Decision:** **2A** with glob paths (e.g. `*/docs/decisions`).

---

## Section 3 — Rollback scope (CONTEXT Q3)

**Question:** What does rollback remove vs preserve?

### Alternative 3A — Remove symlink + version bump only; preserve all family data (chosen)

```bash
# Rollback
rm -f ~/.claude/plugins/llm-wiki-compiler
sed -i.bak 's/^version: 1\.9\.2$/version: 1.9.1/' .claude/skills/.../SKILL.md && rm -f ...SKILL.md.bak
# Family configs, .knowledge/ dirs, .gitignore, family CLAUDE.md additions: ALL PRESERVED
```

**Pros:**
- User-generated content (compiled wikis, raw notes) stays untouched.
- Re-applying the migration after rollback succeeds (idempotency-check finds the pre-existing data and skips creation).
- Aligns with Phase 08's lesson: destructive rollback creates fear-of-rollback.

**Cons:**
- A user who wants a clean uninstall has to manually `rm -rf <family>/.knowledge/ <family>/.wiki-compiler.json` afterwards. Documented in Notes.

### Alternative 3B — Remove everything the migration created (rejected)

`rm -rf <family>/.knowledge/`, `rm <family>/.wiki-compiler.json`, plus the symlink + version revert.

**Why rejected:** Destroys compiled wikis. The whole point of the wiki is durable compounded knowledge; rollback should not delete it.

### Alternative 3C — Interactive rollback with prompts (rejected)

Ask the user whether to remove family data.

**Why rejected:** Migrations run non-interactively from `setup`/`update`. The framework doesn't have prompts.

**Decision:** **3A** (preserve-data rollback).

---

## Section 4 — CLAUDE.md update style (CONTEXT Q4)

**Question:** How does the migration update family-level CLAUDE.md to document the new slash commands?

### Alternative 4A — Append `## Knowledge wiki` section, no GSD marker (chosen)

```markdown
## Knowledge wiki

This family has an LLM-compiled wiki at `.knowledge/wiki/`. Slash commands available after install:

- `/wiki-compile` — compile family sources into the wiki (incremental)
- `/wiki-lint` — health check (stale, orphans, contradictions, drift)
- `/wiki-query "<q>"` — ask the wiki a question
- `/wiki-search "<q>"` — full-text search

See migration 0006 / ADR 0019.
```

**Pros:**
- Simple. Idempotency check: `grep -q '## Knowledge wiki' <family>/CLAUDE.md`.
- No interaction with migration 0010's post-processor (which only normalizes 7 canonical slugs: project/stack/conventions/architecture/skills/workflow/profile — `wiki` isn't one of them).
- Easy for users to edit/customize.

**Cons:**
- Not normalized by 0010, so the section's content is inlined permanently rather than collapsed into a reference link. Acceptable: 7 lines isn't load-bearing bloat.

### Alternative 4B — Wrap in a new `<!-- GSD:wiki-start --> ... <!-- GSD:wiki-end -->` marker (rejected)

Pros: 0010 would normalize it consistently.
Cons: Requires extending the canonical slug allowlist in `normalize-claude-md.sh`. Out of scope for this phase. Could be done as a follow-up patch if the wiki section grows long enough to warrant normalization.

### Alternative 4C — No CLAUDE.md update; document only in the migration notes (rejected)

**Why rejected:** Users discover slash commands by reading their family's CLAUDE.md. Hiding the wiki in migration documentation is friction.

**Decision:** **4A** (append plain `## Knowledge wiki` section).

### Post-codex B3 lock: skip-when-missing semantics

Codex B3 noted the original draft never said what to do when `<family>/CLAUDE.md` doesn't exist at all. Locked policy:

```bash
if [ -f "<family>/CLAUDE.md" ]; then
  if ! grep -q '^## Knowledge wiki' "<family>/CLAUDE.md"; then
    cat >> "<family>/CLAUDE.md" << 'EOF'

## Knowledge wiki

This family has an LLM-compiled wiki at `.knowledge/wiki/`. Slash commands available after install:

- `/wiki-compile` — compile family sources into the wiki (incremental)
- `/wiki-lint` — health check (stale, orphans, contradictions, drift)
- `/wiki-query "<q>"` — ask the wiki a question
- `/wiki-search "<q>"` — full-text search

See migration 0006 / ADR 0019.
EOF
  fi
else
  echo "note: <family>/CLAUDE.md not present, skipping ## Knowledge wiki section addition" >&2
fi
```

**Rationale:** CLAUDE.md is user territory. The migration documents the new slash commands when there's an existing file to edit, but it does NOT create a CLAUDE.md from scratch (that would be presumptuous and could clobber the user's onboarding flow). Users who want the family-level CLAUDE.md can run `claude init` separately. Fixture 11-missing-family-claudemd asserts skip-with-warning behavior.

---

## Section 5 — Pre-existing family config handling (CONTEXT Q5)

**Question:** What if `<family>/.wiki-compiler.json` already exists with custom content?

### Alternative 5A — Idempotency check on file presence; preserve any existing content (chosen)

```bash
test -f "<family>/.wiki-compiler.json" || cat > "<family>/.wiki-compiler.json" <<EOF
{...}
EOF
```

**Pros:**
- Users who tuned their config keep their tuning. The migration is a setup-once tool, not a config-management tool.
- Compatible with rollback-preserves-data semantics.

**Cons:**
- A user with a stale schema (e.g. `version: 1` from an old version of the plugin) won't get auto-upgraded. Acceptable: the plugin's lint command can detect and warn.

### Alternative 5B — Merge / migrate the existing config (rejected)

**Why rejected:** Requires schema-aware merging. The plugin already has a `wiki-init` slash command that handles config bootstrap; the migration shouldn't duplicate that logic.

### Alternative 5C — Refuse to apply if config exists (rejected)

**Why rejected:** Most reapply scenarios would hit this; the migration would never re-apply cleanly.

**Decision:** **5A** (preserve existing content; create only if absent).

---

## Section 6 — Symlink-target validation

**Question:** How does the migration safely create the `~/.claude/plugins/llm-wiki-compiler` symlink?

### Alternative 6A — Validate target type before symlink — **abort on wrong target** (chosen, post-codex B2 lock)

```bash
TARGET=~/.claude/plugins/llm-wiki-compiler
EXPECTED=~/Sourcecode/agenticapps/wiki-builder/plugin
if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
  echo "ERROR: $TARGET exists as a regular file/directory, not a symlink. Refusing to overwrite." >&2
  exit 1
fi
if [ -L "$TARGET" ]; then
  ACTUAL=$(readlink "$TARGET")
  if [ "$ACTUAL" = "$EXPECTED" ]; then
    exit 0  # already correct — idempotent no-op
  fi
  # codex B2: ABORT on wrong target — do NOT silently repoint.
  echo "ERROR: $TARGET is a symlink to $ACTUAL; refusing to repoint to $EXPECTED" >&2
  echo "       (rollback first if you want to reinstall: rm -f $TARGET)" >&2
  exit 1
fi
ln -sfn "$EXPECTED" "$TARGET"
```

**Pros:**
- Refuses to clobber a real file (defensive — protects user's manual installs).
- **Refuses to silently repoint an existing wrong-target symlink** — a user with a manual or forked install at that path gets a clear error, not a hostile overwrite.
- Idempotent on the correct-target case (early exit 0).

**Cons:**
- A user with a custom symlink who *wants* this migration to repoint must run rollback first. Explicit two-step is the right friction here — codex B2 made the argument that silent repointing is too destructive for a host-level install.

### Alternative 6B — Bare `ln -sfn` (rejected)

**Why rejected:** `ln -sfn` with `-f` will delete an existing file at the target path. If a user had a real `~/.claude/plugins/llm-wiki-compiler/` directory with custom content, this destroys it silently.

**Decision:** **6A** (validate before symlink).

---

## Section 7 — Apply-step ordering

**Question:** Which step runs first: symlink, family configs, or `.knowledge/` dirs?

### Alternative 7A — symlink → family configs → `.knowledge/` dirs → CLAUDE.md → version bump (chosen)

**Rationale:**
- Symlink first: it's the only host-level step. If it fails (refusal to overwrite a real file), abort before touching family directories.
- Family configs before `.knowledge/` dirs: the config references `output: .knowledge/wiki/`; creating the config first surfaces config errors before creating dirs.
- CLAUDE.md before version bump: failed CLAUDE.md update shouldn't leave the version bumped (so re-running the migration retries CLAUDE.md).
- Version bump last: the migration framework uses the version field as the apply-success marker.

### Alternative 7B — `.knowledge/` dirs → family configs → symlink (rejected)

**Why rejected:** If symlink fails (due to existing real-file conflict), we've already created directories the user didn't ask for.

**Decision:** **7A**.

---

## Summary

| # | Decision | Outcome |
|---|---|---|
| 1 | Family detection | Dynamic scan with skip-list (`personal\|shared\|archive`) |
| 2 | Default `.wiki-compiler.json` shape | Glob-friendly sources list matching working agenticapps shape |
| 3 | Rollback scope | Symlink + version only; preserve all family data |
| 4 | Family CLAUDE.md update | Append plain `## Knowledge wiki` section; no GSD marker |
| 5 | Pre-existing family config | Preserve unconditionally; create only if absent |
| 6 | Symlink installation | Validate target type; refuse to overwrite real files |
| 7 | Apply-step ordering | Symlink → configs → dirs → CLAUDE.md → version bump |

These choices align with the carry-over draft's intent but tighten the safety properties (FLAG-A-equivalent: don't clobber real files; FLAG-D-equivalent: preserve user customizations). The drafted migration body needs three structural changes to ship under these decisions:

1. **Replace bare `ln -sfn`** (Step 1) with the validated form from §6.
2. **Strike all references** to a non-existent prior migration's scaffolding (sections that say "Already created by migration 0005" or "Per-family .knowledge/sources.yaml.legacy files (created by migration 0005)" — those refer to a draft of 0005 that no longer exists).
3. **Add `**Idempotency check:**` markers** to all 5 apply steps + the rollback path (Phase 08 BLOCK-1 lesson).

These edits land in T2 of PLAN.md.
