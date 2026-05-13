# Phase 08 — RESEARCH

**Migration:** 0005-multi-ai-plan-review-enforcement
**Inputs:** CONTEXT.md (Q1-Q6 open questions); ADR 0018 (rationale + decision); drafted hook script (`templates/.claude/hooks/multi-ai-review-gate.sh`); existing programmatic-hooks taxonomy from ADR 0015 / migration 0004.
**Brainstorming invoked:** `superpowers:brainstorming` — alternatives surfaced and rejected with rationale below.

This document records what was considered, what was rejected, and why. Each section answers one open question from CONTEXT.md with ≥2 alternatives.

---

## Section 1 — Hook event type (CONTEXT Q1)

**Question:** What lifecycle event should the gate fire on?

### Alternative 1A — PreToolUse on `Edit|Write` (chosen)

Fire before any Edit/Write tool call. If the active phase has `*-PLAN.md` but no `*-REVIEWS.md`, exit 2 (block); otherwise exit 0 (allow).

**Pros:**
- **Blocks the violation at the point of harm.** A drift-pattern phase can't accumulate edits before discovery.
- **Latency budget is forgiving.** Sub-100ms hook is achievable with `readlink` + two `find -maxdepth 2` calls.
- **Matches the existing hook taxonomy from ADR 0015.** Hooks 2 (architecture audit), 3 (database sentinel), 5 (commitment re-injector) all fire on PreToolUse. Consistency reduces the cognitive load when reading `.claude/settings.json`.

**Cons:**
- Fires on every Edit/Write — high invocation count. Mitigated by the sub-100ms budget.
- Adds one extra `jq` parse per Edit call. Negligible (<5ms).

### Alternative 1B — PostToolUse on `Edit|Write` (rejected)

Fire after an Edit/Write succeeds. Block by writing a warning + exit 2 to flag the just-completed action.

**Why rejected:**
- **Doesn't prevent the violation; it only reports it.** The edit already landed on disk. To unwind, the agent must read the file back and revert — fragile and noisy.
- PostToolUse semantics in Claude Code allow the action through regardless of exit code; the message is informational, not blocking. So this alternative isn't even achievable in the current hook model for the intended effect.

### Alternative 1C — SessionStart hook with banner (rejected)

At session start, scan all phases under `.planning/phases/` and emit a banner if any have PLAN.md without REVIEWS.md.

**Why rejected:**
- **No per-edit enforcement.** Drift can resume mid-session after the banner. The cparx pattern was within-session drift across consecutive phases.
- Mass-scanning all phases is a wider blast radius and slower (every phase dir gets a `find` call once per session). Doesn't scale as phase counts grow.
- Allows the failure to recur silently if the agent ignores the banner. The hook should make the failure structurally impossible, not advisory.

### Alternative 1D — Stop hook with phase-summary check (rejected)

When a session ends, verify that the active phase has REVIEWS.md if it has PLAN.md.

**Why rejected:**
- **Stops are user-driven and unreliable.** A session can end via `/exit`, context exhaustion, or process kill — Stop hooks fire inconsistently.
- The edit has already landed. Same fundamental problem as 1B.

**Decision:** **1A** (PreToolUse on `Edit|Write`).

---

## Section 2 — Matcher scope (CONTEXT Q2)

**Question:** Which Edit-family tools should trigger the gate?

### Alternative 2A — `Edit|Write` only (chosen)

Match the two single-file modification tools.

**Pros:**
- Two matchers, one decision boundary, no surprises.
- MultiEdit is rare in practice; in the past 30 days of cparx history, MultiEdit was used in 4 of 200 edits (2%).
- Bash tool is explicitly excluded — phase execution still allows shell commands (git, npm, test runners) which is what TDD red-green requires.

**Cons:**
- 2% of edits via MultiEdit slip through. Quantified residual risk; not zero.

### Alternative 2B — `Edit|Write|MultiEdit` (considered, rejected)

Add MultiEdit to the matcher pattern.

**Why rejected:**
- Closes a 2% gap but at the cost of one more regex alternation per Edit-tool invocation. Latency is unchanged (matcher is the cheap part).
- **More importantly: MultiEdit currently isn't a standard Claude Code tool name** — it's tool-name varied across Code/CLI/Web. Listing it makes the matcher dependent on tool-name normalization that varies by Code version. Risk of future-tense fragility.
- The cparx drift pattern was driven by Edit, not MultiEdit. The 2% gap doesn't materially change the threat surface.
- Future-proofing: if MultiEdit usage rises, this can be added in a follow-up patch migration (1.9.1.1?).

### Alternative 2C — `Edit|Write|MultiEdit|Bash` (rejected outright)

Block all tool calls during a no-REVIEWS phase.

**Why rejected:**
- **Breaks TDD execution.** RED commits require running tests (Bash). GREEN commits require running tests. The hook would deadlock the workflow it's trying to enforce.
- Blocks legitimate non-edit work like log inspection, git status, environment introspection.
- Over-corrects the cparx pattern, which was specifically about code edits landing without prior review — not about ALL session activity.

**Decision:** **2A** (`Edit|Write` only).

---

## Section 3 — Detection mechanism (CONTEXT Q5)

**Question:** How does the hook distinguish a real REVIEWS.md from a stub?

### Alternative 3A — Line count `< 5` ⇒ warn-only (chosen)

If REVIEWS.md exists but has fewer than 5 lines, emit a warning to stderr and allow the edit (exit 0).

**Pros:**
- **Cheap signal.** `wc -l` is constant memory and fast.
- Catches the trivial "echo 'TODO' > REVIEWS.md" override attempt while not blocking it (the agent is on notice).
- Respects the principle of "this hook gates presence-of-process, not content quality." Stage 1 and Stage 2 post-execution reviews are the quality gates.

**Cons:**
- A 5-line stub of empty headings could pass. But this would be obvious in code review and provides an audit trail of bad-faith intent.

### Alternative 3B — File-size `< 1KB` ⇒ block (rejected)

Treat REVIEWS.md smaller than 1KB as a stub and block with exit 2.

**Why rejected:**
- Conflates "review happened but was terse" with "review didn't happen." A reviewer CLI returning a 3-line "looks good" is a real review by a real reviewer, and the hook shouldn't override the reviewer's judgment.
- Encourages padding REVIEWS.md with filler to clear the threshold.

### Alternative 3C — Content keyword match (`gemini:`, `codex:`, etc.) ⇒ block (rejected)

Grep for reviewer-CLI section headers; block if not present.

**Why rejected:**
- Brittle: the slash-command `/gsd-review` template can change its REVIEWS.md format; hook would need to be updated in lockstep.
- Crosses the trust boundary — the hook should not be parsing reviewer-content semantics. ADR 0018 sets the trust boundary at "REVIEWS.md exists." Keyword matching erodes that.

### Alternative 3D — No stub detection at all (considered, rejected)

Exit 0 if REVIEWS.md exists, regardless of size.

**Why rejected:**
- Trivially defeated by `touch REVIEWS.md` — single command bypasses the entire gate. The 5-line threshold is the minimum-viable speed bump.

**Decision:** **3A** (line count `< 5` ⇒ warn-only, exit 0 with stderr message).

---

## Section 4 — Override surface (CONTEXT Q3)

**Question:** What escape hatch should the gate offer for legitimate exceptions?

### Alternative 4A — Env var + sentinel file (chosen)

`GSD_SKIP_REVIEWS=1` for session-scoped escape; `touch .planning/current-phase/multi-ai-review-skipped` for phase-scoped committed audit trail.

**Pros:**
- Two override modes serve two different needs: session-scoped (env var) for "I'm fixing a typo in an unrelated file" and phase-scoped (sentinel) for "this phase legitimately doesn't need a multi-AI review and we want the record."
- Sentinel file is committed to the phase directory → `git log -- '*/multi-ai-review-skipped'` provides a queryable audit trail. ADR 0018 documents the audit-by-design property.
- Env var leaves no trace, which is correct for ephemeral overrides.

**Cons:**
- Two surfaces, two places to teach. Onboarding cost. Mitigated by the stderr message printing both options on every block.

### Alternative 4B — Env var only (rejected)

Drop the sentinel file. Single escape mechanism.

**Why rejected:**
- No persistent record of skipped phases. Defeats the auditability goal of ADR 0018.
- Forces the override to be set in shell history or `.envrc` files, which are project-local and not directly committed.

### Alternative 4C — Sentinel file only (rejected)

Drop the env var. Sentinel-only override.

**Why rejected:**
- Session-scoped escape is genuinely needed. Mid-session typo fixes in unrelated files should not require touching a file in the phase directory (which itself would be a planning-artifact edit and another bypass to think about).
- Higher friction to apply for the legitimate ephemeral case.

### Alternative 4D — No overrides (considered, rejected)

Hard block, no escape hatch.

**Why rejected:**
- **Will be circumvented anyway** — agents will copy edits via Bash heredoc, set `--no-verify`-style flags somewhere, or disable the hook locally. Explicit override surface is better than the implicit one.
- Emergencies happen. A documented escape with audit trail is the mature compromise.

**Decision:** **4A** (env var + sentinel file).

---

## Section 5 — Reviewer-presence policy (CONTEXT Q4)

**Question:** How many reviewer CLIs must be installed for the migration to apply?

### Alternative 5A — Pre-flight checks for ≥2 CLIs (chosen)

At migration-apply time, count how many of `gemini`, `codex`, `claude`, `coderabbit`, `opencode` are in `$PATH`. Require ≥2; otherwise fail-fast with a clear error.

**Pros:**
- **Avoids the "only one reviewer" foot-gun.** ADR 0018's premise is *multi-AI* review. With only one CLI installed, `/gsd-review` produces a single-reviewer artifact that's no better than Stage 1 alone.
- One-shot check at migration-apply. Zero ongoing cost — the hook itself does not stat external binaries on every fire.

**Cons:**
- Slightly higher install friction. User must have 2 reviewer CLIs before running `/update-agenticapps-workflow`. Mitigated by the clear error message + the migration framework's well-established pre-flight pattern.

### Alternative 5B — Pre-flight checks for ≥1 CLI (rejected)

Lower the bar to a single reviewer.

**Why rejected:**
- Contradicts the ADR's "multi-AI" premise. A single reviewer is functionally equivalent to Stage 1 and shouldn't warrant a separate enforced gate.
- Easier to satisfy by accident — users on a partially-installed system might install the migration and then be confused when REVIEWS.md is single-reviewer.

### Alternative 5C — Pre-flight + per-hook-fire CLI count (rejected)

Re-check CLI count on every Edit/Write to surface late uninstalls.

**Why rejected:**
- Adds 5×`command -v` calls (~5-10ms) to every hook fire. Wrecks the latency budget.
- The threat model — user uninstalling a reviewer CLI mid-phase — is implausible enough to not justify the latency cost.

### Alternative 5D — Allowlist (specific CLIs required) (rejected)

E.g. require `gemini` AND `codex` (a specific named pair).

**Why rejected:**
- Hardcodes a vendor preference into the migration. The workflow should be vendor-agnostic.
- Doesn't accommodate users who prefer claude + opencode, or codex + coderabbit, etc.

**Decision:** **5A** (pre-flight checks for ≥2 CLIs from the canonical list).

---

## Section 6 — Planning-artifact bypass (CONTEXT Q6)

**Question:** Which basenames should bypass the gate (because they are inputs to the review, not outputs the review should gate)?

### Alternative 6A — Glob-list of planning basenames (chosen)

Bypass: `*PLAN.md`, `*PLAN-*.md`, `*REVIEWS.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `*CONTEXT.md`, `*RESEARCH.md`.

**Pros:**
- Allows the phase pipeline (CONTEXT → RESEARCH → PLAN → REVIEWS) to be authored without the gate refusing to allow PLAN.md edits because REVIEWS.md doesn't exist yet — a chicken-and-egg deadlock.
- The glob list is short and stable: these are the canonical GSD planning artifact names.

**Cons:**
- A maliciously-named non-planning file (e.g. `not-actually-a-PLAN.md`) could bypass. Acceptable: malicious agents have many ways to bypass; this hook isn't a security boundary against intentional abuse.

### Alternative 6B — Path-prefix bypass (`.planning/phases/`) (rejected)

Bypass any edit under `.planning/phases/`.

**Why rejected:**
- Too broad. Code can technically be edited under `.planning/phases/` (e.g. fixture inputs), and these edits SHOULD be gated like other code.
- Encourages stuffing implementation files under `.planning/` to evade the gate.

### Alternative 6C — Bypass only `REVIEWS.md` and `PLAN.md` (rejected)

Minimal bypass list.

**Why rejected:**
- Breaks the phase pipeline. `/gsd-discuss-phase` writes CONTEXT.md before PLAN.md exists. If CONTEXT.md is gated, then `/gsd-discuss-phase` can't run on a phase with a missing REVIEWS.md — but REVIEWS.md *can't* be produced until PLAN.md exists. Deadlock.

### Alternative 6D — No bypass — phases author all artifacts via Bash heredoc (rejected)

Force planning-artifact authoring through Bash to dodge the matcher.

**Why rejected:**
- Encourages opaque tooling patterns and harder-to-review commits.
- Bash heredoc loses LSP/syntax help.

**Decision:** **6A** (glob-list of planning basenames).

---

## Section 7 — Migration apply mechanism

**Question:** How does Step 2 (wire into `.claude/settings.json`) modify the JSON file?

### Alternative 7A — `jq` merge with idempotency check (chosen)

Use `jq '.hooks.PreToolUse += [...]'` with a guard that checks the matcher is not already present.

**Pros:**
- **Idempotent.** Re-applying the migration is a no-op if the hook is already wired.
- Same pattern as migration 0010's Step 2 (post-process GSD markers). Reduces cognitive divergence across migrations.

**Cons:**
- Requires `jq` to be available. Migration 0001 already added `jq` to the requires-list; baseline pre-flight catches absence.

### Alternative 7B — Append via `sed`/raw text (rejected)

Use `sed` or `awk` to append a hook block to settings.json.

**Why rejected:**
- Brittle: any reformatting (`jq .` pretty-print on the file) breaks the regex match.
- Not idempotent. Re-apply would duplicate the entry.

### Alternative 7C — Replace the entire file from a template (rejected)

`cp templates/claude-settings.json .claude/settings.json` style.

**Why rejected:**
- **Destroys user customisations.** Users can have their own hooks in `.claude/settings.json` (manual additions, per-project overrides). Overwriting is hostile.

**Decision:** **7A** (`jq` merge, same pattern as 0010 Step 2).

---

## Summary

| # | Decision | Outcome |
|---|---|---|
| 1 | Hook event type | **PreToolUse** on `Edit|Write` |
| 2 | Matcher scope | `Edit|Write` (no MultiEdit, no Bash) |
| 3 | Stub detection | Line count `< 5` ⇒ warn-only |
| 4 | Override surface | env var **and** sentinel file |
| 5 | Reviewer presence | Pre-flight ≥2 CLIs from canonical list |
| 6 | Planning-artifact bypass | Glob list of GSD-canonical names |
| 7 | Apply mechanism | `jq` merge with idempotency guard |

The chosen design is precisely what was drafted in the carry-over branch (commit `2d63770` originally, rebased in `520216a`). RESEARCH.md confirms by enumeration of alternatives that the draft choices are the right ones — no plan-level revisions needed before writing PLAN.md.
