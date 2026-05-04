# Phase 4 Verification — Scheduling layer

**Phase:** 04-scheduling
**Spec source:** Hand-off prompt Phase 4 + synthesis report §1
**Date:** 2026-05-03

## Mechanism 1: In-session SessionStart hook

### MH-1: `templates/.claude/hooks/architecture-audit-check.sh` written + executable

- **Evidence:** File present, +x, smoke-tested in 3 cwd shapes (no .planning, .planning + no AgenticApps install, real cparx). All paths exit 0; prompt only emits when AgenticApps install detected AND audit absent or stale.
- **Status:** ✅ PASS

### MH-2: Wired into `templates/claude-settings.json` SessionStart array

- **Evidence:** `jq '.hooks.SessionStart'` shows entry alongside Hook 4b session-bootstrap; both fire on every SessionStart. JSON valid.
- **Status:** ✅ PASS

### MH-3: Snooze mechanism functional

- **Evidence:** Hook reads `.planning/audits/.snooze-until-*` markers; honors future-dated snoozes; ignores past-dated. Smoke-tested in `/tmp/scratch-aac` fixture.
- **Status:** ✅ PASS

## Mechanism 2: Weekly cron

### MH-4: `bin/agenticapps-architecture-cron.sh` written + executable

- **Evidence:** Script ~140 lines. Smoke-tested with `AGENTICAPPS_REGISTRY=/nonexistent AGENTICAPPS_SOURCECODE_ROOT=/tmp/no-such-dir` → "No AgenticApps projects detected", exit 0. Logs to `~/.agenticapps/architecture-audit-cron.log`.
- **Status:** ✅ PASS

### MH-5: Registry-first source-of-truth (Q2 robust semantics)

- **Evidence:** Reads `~/.agenticapps/dashboard/registry.json` filtering by `tags ∋ "active"`. Falls back to `find ~/Sourcecode -maxdepth 3 -name .planning -prune` when registry empty/absent. Both paths exercise the same overdue-detection logic downstream.
- **Status:** ✅ PASS

### MH-6: Snooze contract shared with Mechanism 1

- **Evidence:** Cron uses identical `.planning/audits/.snooze-until-*` marker check as the SessionStart hook. Same date format, same comparison. Snooze in one is honored by both.
- **Status:** ✅ PASS

### MH-7: Linear notification with fallback

- **Evidence:** Tries `linear` CLI first; falls back to log file at `~/.agenticapps/architecture-audit-cron.log` if CLI unavailable. Both paths exit 0.
- **Status:** ✅ PASS

## Installers (Q4: yes Linux sibling)

### MH-8: `bin/install-architecture-cron.sh` (macOS launchd)

- **Evidence:** Refuses on non-darwin (`OSTYPE != darwin*`). Generates `~/Library/LaunchAgents/eu.agenticapps.architecture-cron.plist` from template via `sed` substitution. Idempotent: `launchctl unload -w` then `launchctl load -w`. Schedule: Mondays 09:00 local.
- **Status:** ✅ PASS (script ready; install deferred to user post-merge per spec)

### MH-9: `bin/install-systemd-architecture-cron.sh` (Linux)

- **Evidence:** Refuses on darwin. Generates `~/.config/systemd/user/agenticapps-architecture-cron.{service,timer}` from templates. Idempotent: stop + disable + reload + enable + start. `Persistent=true` on the timer means missed triggers fire on next boot.
- **Status:** ✅ PASS

### MH-10: Plist + systemd unit templates ship with `{SCAFFOLDER_BIN}` and `{HOME}` placeholders

- **Evidence:** Both installers `sed`-substitute these to absolute paths derived from script location; users don't edit the templates. Tested by previewing the macOS plist post-substitution.
- **Status:** ✅ PASS

## ADR

### MH-11: ADR-0017 written

- **Evidence:** `docs/decisions/0017-architecture-audit-scheduling.md` documents the two-mechanism decision, seven rejected alternatives (single-mechanism, auto-run, manual, daily, skill-form, per-project cron, etc.), positive + negative consequences, follow-ups.
- **Status:** ✅ PASS

## Out of scope for this phase

- **Live install of the cron on Donald's machine:** the installer is ready; per spec the install command is documented in the PR body for Donald to run post-merge (`~/.claude/skills/agenticapps-workflow/bin/install-architecture-cron.sh`).
- **Setup-skill integration:** the SessionStart hook gets installed via the same migration step that copies `templates/.claude/hooks/*` to projects (lands in P5's migration 0004). Until P5 ships, projects must manually `cp` the hook + merge settings.
- **Project SessionStart skill registration:** the architecture-audit-check hook is listed in `templates/claude-settings.json`. P5's migration 0004 handles the merge into projects' settings.json.

## Skills invoked this phase

1. `superpowers:writing-plans` — phase plan held inline (clear Q4/Q5/Q6 architecture choices already locked)
2. gstack `/review` — Stage 1 self-review (mechanisms verified by smoke tests + registry/snooze logic)
3. `pr-review-toolkit:code-reviewer` — Stage 2 inline (bash + plist + systemd unit templates; surface manageable; smoke tests + idempotent install logic exercise the failure paths)

## Mid-phase pivot

Initially wrote `architecture-audit-check/SKILL.md` (skill-form) before realizing the spec said hook-form ("alongside Hook 4b session-bootstrap.sh"). Pivoted: removed the SKILL.md, wrote `templates/.claude/hooks/architecture-audit-check.sh`, registered in `templates/claude-settings.json` SessionStart chain. Logged in ADR-0017 Alternatives Rejected for transparency.
