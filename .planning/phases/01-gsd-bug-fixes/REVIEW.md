# Phase 1 Review — rogs.me GSD bug fixes

## Stage 1 — Spec compliance review

**Reviewer:** primary agent (self), against §2 of `tooling-research-2026-05-02-batch2.md` + Phase 1 of the hand-off prompt
**Diff scope:** `~/.config/gsd-patches/` (user's home — created from scratch), worktree adds `templates/gsd-patches/` mirror, ADR-0014, phase artifacts. Live patch in `~/.claude/get-shit-done/workflows/review.md:169` (out of scaffolder repo scope).

### Spec coverage

| Bug | rogs.me claim | This install | Action | Status |
|---|---|---|---|---|
| Bug 1 | `opencode run 2>/dev/null` causes hangs | Present at `workflows/review.md:169` verbatim | Strip ` 2>/dev/null` | ✅ APPLIED |
| Bug 2 | `claude -p --no-input` invalid flag | Not present (grep returns zero hits) | Skip | ✅ N/A |
| Bug 3 | Reviewers should be parallel | Upstream explicitly says sequential to avoid rate limits | Skip per user choice | ✅ DECISION-DOCUMENTED |

### Findings

| ID | Severity | Confidence | File | Finding | Action |
|---|---|---|---|---|---|
| S1-1 | INFORMATIONAL | 9/10 | `~/.claude/get-shit-done/workflows/review.md:142` | Upstream comment "not parallel — avoid rate limits" implies a recent design decision post-rogs.me. Worth opening an upstream PR discussion to confirm and possibly upstream a guarded `${GSD_PARALLEL_REVIEWS:-false}` flag. | **NO ACTION (this PR)** — captured as ADR Follow-up. |
| S1-2 | INFORMATIONAL | 8/10 | `templates/gsd-patches/bin/sync`, `templates/gsd-patches/bin/check` | Scripts use Bash 4 features (`mapfile`-equivalent via `find -print0` + `read -d ''`). Default macOS Bash is 3.x; on a stock-Bash-only system this could fail. Tested locally (user has Bash 4+ via brew). | **NO ACTION** — Donald's macOS has Bash 4 from brew. Document the prerequisite in templates README if a fresh-machine install ever fails. |
| S1-3 | INFORMATIONAL | 7/10 | ADR-0014 | I documented why the migration framework doesn't apply to GSD (foreign skill, not AgenticApps project). Adds a real boundary clarification — could be useful in `migrations/README.md` itself as a "what migrations DO NOT cover" note. | **NO ACTION (this PR)** — captured as a possible follow-up to add to `migrations/README.md` if it comes up in user feedback. |

### Stage 1 verdict

**STATUS: clean.** Bug 1 patched, canonical-storage infra working (check + sync both exit 0), templates mirror in place, ADR documents per-bug decision with transparent reasoning. No spec drift; one user-confirmed deliberate skip (Bug 3).

---

## Stage 2 — Independent code-quality review

**Status:** PENDING dispatch (will spawn after this artifact is committed; light review since the surface is small — bash scripts + markdown).
