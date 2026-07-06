# ADR-0038: Knowledge capture ritual tail — spec §15 in the claude host

**Status**: Accepted  **Date**: 2026-07-06  **Linear**: —
**Core contract**: `agenticapps-workflow-core/spec/15-knowledge-capture.md` (v0.7.0), core ADR-0017

## Context

Core ADR-0017 added spec §15: every host writes 1–5 distilled, transferable
learnings to **one Obsidian note per repo**
(`~/Obsidian/Memex/40-49 Resources/44 Agentic Coding Learnings/<repo-name>.md`)
at three ritual boundaries — session handoff, plan completion, phase
completion. Today those learnings die where they were made: the per-repo
`session-handoff.md` is overwritten by the next session, and ADRs/CHANGELOGs
capture repo-scoped facts by design. Nothing carries a root cause from
`fx-signal-agent` to an agent working in `cparx`, or a Codex insight to a
Claude session.

claude-workflow is the reference host, so it implements §15 first. The
architecture is the two-layer shape observability established (core ADR-0014;
here: the §14 injection-guard precedent, ADR-0037's snapshot+migration
propagation pattern): the normative contract lives in core; this host ships
its own wiring in its own idiom; the repo stays self-contained because the
destination comes from per-repo configuration, never from skill logic.

## Decision

1. **Wiring is a skill section, not a hook.** `skill/SKILL.md` gains
   `## Knowledge Capture — Ritual Tail (spec §15)` — prose instructions the
   agent executes as the FINAL step of the three rituals. §15 explicitly
   permits any mechanism; a skill step matches how this host wires every other
   ritual (commitment principle), needs no new runtime, and keeps the
   selectivity bar (an LLM judgment call) where an LLM executes it. The
   section embeds the note skeleton (canonical copy:
   `templates/obsidian-learnings-note.md`) so first-write creation is
   deterministic and installed repos stay self-contained.
2. **Destination is config-routed.** `.planning/config.json` gains
   `knowledge_capture: {enabled, note}` (spec §15.2). The skill reads it at
   trigger time; graceful skip (§15.3) when the block is absent, disabled, or
   the vault parent folder does not exist — at most one info line, never
   create the folder, never fail the ritual. The vault write is never
   committed to the repo.
3. **Fresh installs: snapshot.** `templates/config-hooks.json` seeds the block
   with a literal `<repo-name>` placeholder; `setup/SKILL.md` Step 4d resolves
   it to the repo directory name at install time (per §15.2 the name is
   written out at configuration time, never substituted at runtime).
4. **Existing installs: migration 0025** (2.2.0 → 2.3.0). Inserts the block
   only if missing (user opt-outs and custom notes are preserved verbatim) and
   appends the ritual-tail section by **extracting it from the scaffolder's
   `skill/SKILL.md`** — single source of truth, so a migrated install is
   byte-identical to a fresh snapshot install and the text cannot drift.
5. **Drift guard.** `check-snapshot-parity.sh` gains §7 (snapshot SKILL must
   carry the section, the three trigger points, and the config-routed
   destination) and a §3 extension (config block shape + unresolved
   placeholder), in the §6 gitignore-invariant style: the step can never
   silently drop out of the seed.

## Alternatives Rejected

- **A Stop/PostToolUse hook that writes the note.** Deterministic firing, but
  the selectivity bar ("write nothing if nothing qualifies") and Key-Learnings
  curation are judgment calls a shell hook cannot make; a hook would also need
  vault-path logic outside per-repo config. Spec §15 non-requirements
  explicitly bless a skill step.
- **Hardcoding the vault path in the skill.** Violates repo self-containment
  and breaks every machine that is not the operator's workstation — the exact
  reason core ADR-0017 made the path per-repo config.
- **Duplicating the section text inside migration 0025.** The 0024-style
  self-contained heredoc drifts the moment the skill text changes; extraction
  from the scaffolder source keeps one canonical copy (pre-flight aborts on a
  stale clone instead of installing stale text).
- **Writing learnings into the family wiki (`.knowledge/`).** Regenerable
  synthesis — writes are lost on recompile, and the vault schema explicitly
  separates the learnings folder from the wiki plane.

## Consequences

- v2.3.0 (minor, additive). Fleet reaches it via `/update-agenticapps-workflow`;
  fresh installs get it from the snapshot. Repos opt out per-repo
  (`enabled: false`) or per-machine (no vault folder) without touching code.
- The vault-side `CLAUDE.md` in the learnings folder stays authoritative for
  the note format; the skill section and `templates/obsidian-learnings-note.md`
  mirror it and must be patched if it changes (same sync obligation core §15.4
  documents).
- `implements_spec` in the skill frontmatter stays at 0.4.0: it tracks the
  last full-conformance audit, and bumping it to 0.7.0 requires auditing
  §§ added in 0.5.0/0.6.0 — out of scope here; §15 wiring is real either way.
- Downstream: `codex-workflow` and `opencode-workflow` must mirror §15 in
  their own idiom (config seed + three trigger points + graceful skip), with
  their own host tag in log-entry headings. Tracked here and in migration
  0025's downstream note, per the ADR-0037 propagation pattern.
