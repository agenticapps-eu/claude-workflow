# Phase 06 — SECURITY (/cso-style audit)

**Audited at**: 2026-05-13.
**Mode**: targeted — this phase ships a migration that auto-rewrites
arbitrary consumer projects' `CLAUDE.md`. Auto-mutation of always-loaded
agent context is a security-relevant boundary even though no traditional
attack surface exists. Audit focused on: (a) blast radius of the migration's
file mutations, (b) input handling against malicious-project scenarios,
(c) supply-chain considerations for the vendored template.

## Threat model

### What this phase changes that affects trust boundaries

| Change | Trust-boundary implication |
|---|---|
| Migration 0009 writes `<repo>/.claude/claude-md/workflow.md` from a template under `~/.claude/skills/agenticapps-workflow/templates/` | Source-of-truth for an always-loaded agent instruction file moves from `templates/claude-md-sections.md` (read at setup time) to `templates/.claude/claude-md/workflow.md` (read at every setup + every upgrade). Compromise of either file → compromise of every consumer project's runtime instructions. |
| Migration 0009 Step 4 deletes line ranges from `CLAUDE.md` based on a regex-derived extraction boundary | A malicious or buggy project layout could push the extraction boundary past intended bounds, deleting project-owned content. Mitigated by: (i) the start anchor must match a known-template marker (heading-agnostic Superpowers regex or smoking-gun H1 — both are template-derived strings, not user input); (ii) end anchor is bounded to a known-template-H2 set OR the next non-template H2; (iii) every deletion is gated by user confirmation with diff preview (`update/SKILL.md` Step 5 #5). |
| Migration 0000 patched in-place to vendor instead of inline | New consumer projects auto-create `.claude/claude-md/workflow.md` on first install. The directory permissions follow the project's umask (typically 755); the file's content is the template content (not user input). |
| Heading-agnostic regex `^#{2,4} Superpowers Integration Hooks \(MANDATORY` | Regex character class is bounded; no `.` wildcard, no DoS-able `*` at the start. ReDoS analysis: linear time on input length. Safe. |

### What this phase does NOT change

- No new network calls. The migration runtime never fetches from the meta-repo at runtime (ADR 0021's "self-contained repo" property).
- No new credentials, tokens, or secrets paths.
- No new exec / shell-out surfaces beyond the migration runtime's existing per-step Apply prompt (already bounded by the user-confirmation requirement).
- No change to the workflow scaffolder repo's auth model — install instructions still use `git clone` + per-user SSH/HTTPS.

## Findings

### F1 — Vendored template is the new always-loaded supply-chain root [INFORMATIONAL]

**Description**: `templates/.claude/claude-md/workflow.md` is now the canonical source for the workflow block that every consumer project loads on every Claude Code conversation. Any change to this file in the meta-repo propagates to every consumer project on next `/update-agenticapps-workflow`.

**Risk**: a malicious commit to `templates/.claude/claude-md/workflow.md` (e.g. via compromised maintainer credentials, social-engineered PR merge) could inject instructions into every consumer project's always-loaded context — instructing the agent to leak files, alter commit signatures, etc.

**Existing mitigations**:
- Repo is private + maintainer-controlled (per agenticapps governance — out of scope of this phase).
- The migration runtime always shows a diff before applying the new content (`update/SKILL.md` Step 5 #5 — divergence variant added in this phase).
- The user has to explicitly run `/update-agenticapps-workflow` to pick up changes; passive auto-update is not present.
- Git history of the meta-repo is the audit trail.

**Recommendation**: not a blocker for this phase. Track as a property worth re-auditing whenever the meta-repo's contributor list or merge policies change. Aligned with the existing supply-chain posture for `templates/claude-md-sections.md` (which had the same property pre-1.8.0); this phase doesn't expand the surface, it just relocates it.

### F2 — Step 4's line-range deletion is bounded but not formally verified [LOW]

**Description**: Step 4's extraction range uses regex anchors (start: smoking-gun H1 or heading-agnostic Superpowers; end: end-of-routing-rules-list / next non-template H2 / EOF). The bounds are precisely specified in the migration prose, but the actual line-range deletion happens via the agent runtime's interpretation of that prose — there is no ground-truth assertion that the agent's chosen line range matches the spec.

**Risk**: an agent runtime bug could pick a wrong end line (e.g. mistake a project's own `## Skill routing` as part of the inlined block and extend extraction past the project's content). This would manifest as silent data loss in CLAUDE.md.

**Existing mitigations**:
- Per-step user confirmation with diff preview (the user sees exactly what range is being deleted before approving).
- The "Detection ambiguous" outcome (third bullet in Step 4's outcome table) is the documented escape hatch when bounds can't be determined.
- The harness covers Step 4's apply-bash detection (`INLINED` variable lands correctly) but does NOT cover the line-range deletion itself.

**Recommendation**: not a blocker. The user-confirmation gate is the primary defence. As a follow-up enhancement (FLAG-5 in REVIEW.md): extend the harness to apply the line-range deletion against fixtures and diff against `after-vendored` CLAUDE.md, asserting byte-equality. This would catch agent-runtime bugs in extraction-range computation.

### F3 — Migration 0000 in-place patch widens the trusted-changes window [LOW]

**Description**: Migration 0000 was patched in-place (Step 4: `cat` → vendor). The migration framework's convention is that migrations are immutable once shipped; this phase explicitly breaks that convention.

**Risk**: future readers of `migrations/0000-baseline.md` see a Step 4 that doesn't match the migration's `to_version: 1.2.0` semantics (the literal v1.2.0 disk shape was inlined, not vendored). Reproducing a v1.2.0 install is no longer possible from the migration alone — git history of the migration file is required.

**Existing mitigations**:
- ADR 0021's Consequences section now explicitly acknowledges this (FLAG-2 fix).
- A `> **Why vendor instead of inline?**` block was added inside the patched Step 4 documenting the rationale.
- The pre-flight refuses to run 0000 against an existing install, so the patched behavior cannot affect any project past 1.2.0.

**Recommendation**: accepted as documented. Trade-off favors fresh installs going straight to vendored state (no transient broken intermediate) over strict immutability.

### F4 — Em-dash character class in detection regex [INFORMATIONAL]

**Description**: The smoking-gun H1 detection regex uses `[—-]` (em-dash + hyphen-minus character class) to tolerate editor-save normalisation.

**Risk**: a project whose CLAUDE.md was saved by an editor that normalises `—` to `–` (en-dash, U+2013) would slip past the smoking-gun detector. The Superpowers heading regex is unaffected (anchored on `(MANDATORY`).

**Existing mitigations**:
- Smoking-gun H1 is a fallback signal; primary detection is the heading-agnostic Superpowers regex which doesn't depend on dash characters.
- Even without the smoking-gun H1, the Superpowers regex catches the inlined block.

**Recommendation**: accepted. The fallback chain is robust to single-character normalisation.

## Cross-cuts

- **OWASP Top 10 (2021)**: not applicable — no web surface, no SQL, no auth.
- **STRIDE**: Tampering is the primary concern (F1), addressed via existing mitigations. Information disclosure / Repudiation / DoS / EoP not applicable.
- **Supply chain (SLSA-style)**: F1 captures it. No new dependency added by this phase.
- **Database security (database-sentinel scope)**: not applicable — no database touched.
- **LLM prompt construction**: the vendored template *is* prompt content (always-loaded into the agent's context). F1 covers it.

## Verdict

**PASS.**

No BLOCK or HIGH findings. The phase ships within the existing trust boundaries. The novel logic (Step 4 line-range deletion) is gated by user confirmation, the new file vendoring follows the same supply-chain pattern as the prior inlined-template approach, and the in-place 0000 patch is documented in ADR 0021.

The four INFORMATIONAL/LOW findings are accepted with documented rationale; the two follow-up recommendations (F2: extend harness to verify line-range deletion; F4: monitor for additional dash normalisations) are queued as v1.9.0+ enhancements.

No new threat vectors introduced. The "meta-repo never referenced at
runtime" property in ADR 0021 actually *narrows* the existing surface
(consumer projects no longer need read access to the meta-repo path at
agent startup).
