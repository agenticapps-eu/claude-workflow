# ADR-0017: Architecture audit scheduling — SessionStart reminder + weekly cron

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 4 of `feat/programmatic-hooks-architecture-audit`

## Context

Phase 3 installs `mattpocock-improve-architecture` but doesn't ensure it
*runs regularly*. Without a forcing function, the audit will be invoked
once on enthusiasm and forgotten. The hand-off prompt frames this as the
explicit goal: "how can I make sure this is done regularly?"

Two failure modes for "regular execution":

| Failure | Mechanism that catches it |
|---|---|
| "I forgot to audit before opening a new feature branch" | In-session reminder when a session starts on a stale project |
| "I haven't opened that project in 3 weeks; it's drifting" | Out-of-session weekly cron that scans all active projects |

Different failure modes need different mechanisms. Single-mechanism
solutions miss one or the other.

## Decision

Ship two complementary mechanisms with a shared snooze contract.

### Mechanism 1: In-session SessionStart hook

`templates/.claude/hooks/architecture-audit-check.sh` (new). Fires on
`SessionStart` (no matcher). Logic:

1. Detect AgenticApps project: `.planning/` present AND
   `agentic-apps-workflow` skill installed (project-local OR global
   symlink).
2. Honor snooze: skip if `.planning/audits/.snooze-until-{YYYY-MM-DD}`
   exists with a future date.
3. Check last audit: most recent `*-architecture.md` in
   `.planning/audits/`. If never audited OR > 7 days old, prompt.
4. Output: status + suggested command + snooze command. Always exit 0.

Wired in `templates/claude-settings.json` `SessionStart` array alongside
Hook 4b (session-bootstrap.sh from P2). Project-scoped (per-project
install).

### Mechanism 2: Out-of-session weekly cron

`bin/agenticapps-architecture-cron.sh` (new). Logic:

1. Source-of-truth for active projects per Q2: dashboard registry at
   `~/.agenticapps/dashboard/registry.json`. Filter by `tags ∋
   "active"`.
2. Heuristic fallback if registry empty/absent: scan
   `${AGENTICAPPS_SOURCECODE_ROOT:-~/Sourcecode}` for repos with
   `.planning/` (depth 3).
3. For each project: honor snooze (same contract as Mechanism 1).
4. Compute days-since-last-audit; collect overdues.
5. Notify: try Linear CLI, fall back to log at
   `~/.agenticapps/architecture-audit-cron.log`.

Two installers per Q4:

- `bin/install-architecture-cron.sh` — macOS LaunchAgent. Plist template
  at `templates/launchd/eu.agenticapps.architecture-cron.plist`. Fires
  Mondays 09:00 local.
- `bin/install-systemd-architecture-cron.sh` — Linux systemd-user.
  `.timer` + `.service` templates at `templates/systemd-user/`. Same
  schedule. Includes `Persistent=true` so a missed trigger fires on
  next boot.

Both installers idempotent (unload + reload).

### Shared snooze contract

Per-project. File-based: `mkdir -p .planning/audits && touch
.planning/audits/.snooze-until-{YYYY-MM-DD}`. Both Mechanism 1 and
Mechanism 2 honor the same marker. Auto-expires when the date passes.
User can delete the marker any time to be reminded earlier.

## Alternatives Rejected

- **Single mechanism (SessionStart only).** Rejected — misses projects
  Donald hasn't opened recently. Architectural drift accelerates in
  exactly the projects no one's looking at.
- **Single mechanism (cron only).** Rejected — relies on Linear/email
  to deliver the reminder. Misses the moment when intent is highest
  (just opened the project, ready to do work).
- **Run the audit automatically on stale projects.** Rejected — Q3
  user choice was "Linear backlog only, never auto-apply" (per ADR-0016).
  Auto-running would file Linear issues without consent and expose the
  user to skill-quality variance silently.
- **Use macOS Reminders + manual entry.** Rejected — manual systems
  decay; no shared snooze; no project enumeration.
- **Daily cadence instead of weekly.** Rejected — too noisy. Audits
  surface refactor candidates that take real effort to triage; weekly
  matches the cognitive cycle of "what should I actually work on this
  week."
- **Skill-form (`/agenticapps-architecture-audit-check`) instead of hook
  script.** Rejected — skills require manual invocation; the whole
  point is automatic firing on every session start. A `.sh` registered
  in `claude-settings.json` is the right shape. (We started with a
  SKILL.md and pivoted mid-phase; rejected SKILL.md is removed in
  this commit.)
- **Per-project cron instead of global.** Rejected — N installs per
  N projects. The global cron iterates over the registry; one install,
  scales free.

## Consequences

**Positive:**
- Both forgetting modes covered.
- Shared snooze contract means "I'm aware, leave me alone for a week"
  works in both contexts with one command.
- Linux + macOS both supported (Q4); pure-bash cron script is portable
  across both, only the install mechanism differs.
- Registry-first project discovery (Q2 option a's recommendation,
  upgraded to "robust" semantics: registry-first with heuristic fallback
  per Q2 option c) means the dashboard project becomes the source of
  truth without requiring it to be ready today.
- Cron logs to `~/.agenticapps/architecture-audit-cron.log` even when
  Linear access fails — observability never silently drops.

**Negative:**
- Two install steps for users (project setup runs the SessionStart hook
  via setup integration; cron requires running install-architecture-cron
  once per machine). Mitigated by README + post-merge install
  instructions.
- Cron runs at 09:00 Monday local. Users on holiday miss the trigger
  unless `Persistent=true` (systemd) catches up on next boot. macOS
  LaunchAgent doesn't have a direct equivalent of `Persistent=true`;
  if the laptop is closed at 09:00 Monday, the trigger fires on next
  wake. Acceptable; documented.
- Snooze format is filesystem-only (no central store). If a user
  snoozes locally then a teammate runs the cron, the cron doesn't see
  the snooze. Acceptable for now (single-user scope); revisit if team
  context emerges.

**Follow-ups:**
- After 4 weeks: audit `~/.agenticapps/architecture-audit-cron.log`
  to see how often the cron fires and how often Donald snoozes vs runs
  the audit. Tune threshold if behavior reveals a pattern.
- If dashboard project ships with auto-tagging logic (last commit < 14d
  → tag "active"), the cron's heuristic fallback can retire.
- Phase 4 of this work uses `claude-haiku-4-5-20251001` for the Phase
  Sentinel (Hook 3, P2). Consider migrating the architecture-audit-check
  hook from prose-output to a Haiku-prompt-type hook if the prompt
  consistency drifts.

## References

- Synthesis report §1 (mattpocock improve-architecture): `tooling-research-2026-05-02-batch2.md`
- Hand-off prompt Phase 4 (Mechanism 1 + Mechanism 2)
- Live: `templates/.claude/hooks/architecture-audit-check.sh`,
  `bin/agenticapps-architecture-cron.sh`,
  `templates/launchd/eu.agenticapps.architecture-cron.plist`,
  `templates/systemd-user/agenticapps-architecture-cron.{service,timer}`,
  `bin/install-architecture-cron.sh`,
  `bin/install-systemd-architecture-cron.sh`
- ADR-0016 — install of `mattpocock-improve-architecture` (this ADR's prerequisite)
- ADR-0015 — programmatic hooks layer (this hook is the 6th)
