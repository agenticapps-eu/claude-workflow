# Phase 07 — RESEARCH.md

Alternatives considered for migration 0010 (post-processing GSD section
markers in CLAUDE.md). Each alternative was evaluated against four
criteria: blast radius (how much of the broader AgenticApps ecosystem it
touches), reversibility (can we back out cleanly?), maintenance burden,
and time-to-cparx-relief.

---

## Alternative 1 (CHOSEN) — Post-processor hook in claude-workflow

**Shape:** A POSIX bash script vendored at
`templates/.claude/hooks/normalize-claude-md.sh`, installed into consumer
projects by migration 0010, and registered as a Claude Code PostToolUse
hook on `Edit|Write|MultiEdit`. The script walks `CLAUDE.md`, finds
`<!-- GSD:{slug}-start[ source:{path}] -->...<!-- GSD:{slug}-end -->`
blocks, and rewrites each into a self-closing
`<!-- GSD:{slug} source:{path} /-->` plus a heading and reference link.
The migration also runs the script once during apply (one-shot seed).

**Pros:**

- Stays inside the `claude-workflow` repo boundary. No coordination with
  `pi-agentic-apps-workflow` / `get-shit-done` upstream.
- Co-located with the project that consumes it — debuggable in-place.
- The script is small (~80 LOC bash + sed/awk). Easy to read, easy to
  patch, no node/python dependency.
- Idempotent by construction (self-closing form has no `-start` marker,
  so the regex skips it on rerun).
- Fast feedback loop: cparx drops to ≤200L the moment migration 0010
  applies to it. Doesn't wait on cross-repo PRs.
- Resilient to upstream changes — even if `gsd-tools` changes the marker
  format, the post-processor regex can be updated independently.

**Cons:**

- Fights the upstream tool. If a user runs `gsd-tools generate-claude-md`
  WITHOUT `--auto`, it re-inflates the sections. The PostToolUse hook
  catches this on the next Edit, but there's a brief inconsistent window.
- Bash regex parsing of HTML comment markers is fragile. We must scope
  the regex narrowly (`^<!-- GSD:[a-z]+-start`) and pin the end marker
  to the same slug; otherwise stray comments could match.
- Doesn't solve the root cause — the inlined-bloat output of gsd-tools
  itself. Users who never apply 0010 still see the same bug.

**Risks:**

| Risk | Mitigation |
|---|---|
| Bash regex matches the wrong content (e.g., text inside a fenced code block that mentions `<!-- GSD: -->`) | The script processes only line-leading matches; embedded markers in code blocks are skipped (they'd be inside ``` fences which the script can detect). Verified in `test-fixtures/0010/edge-case-fenced-marker.md`. |
| Source file referenced in `source:` doesn't exist after a project move | Safety rule: if the resolved file path doesn't exist, preserve the inlined block unchanged + emit warning to stderr. Verified in fixture `inlined-source-missing.md`. |
| `gsd-tools generate-claude-md` (no `--auto`) re-inflates content between hook fires | PostToolUse on Edit\|Write covers any subsequent CLAUDE.md write. Document the `--auto` flag recommendation in the ADR and CHANGELOG. |
| 0009's vendored workflow block (`.claude/claude-md/workflow.md`) is accidentally referenced/touched | Regex is scoped to `<!-- GSD: -->` markers only; 0009 emits no such markers. Verified in fixture `with-0009-vendored.md`. |
| Self-closing form `<!-- GSD:{slug} /-->` re-attracts a fresh `-start` block on the next gsd-tools run, leaving BOTH in CLAUDE.md | The next PostToolUse fire re-normalizes — collapsing the new `-start...-end` pair back to self-closing form, then ignoring the already-self-closing one. Verified in fixture `dual-state-after-gsd-tools.md` (idempotency test). |

---

## Alternative 2 (REJECTED) — Patch `gsd-tools` upstream

**Shape:** Submit a PR to `pi-agentic-apps-workflow` adding a
`--reference-mode` flag to `gsd-tools generate-claude-md`. When the
flag is set, `buildSection` emits the self-closing reference form
directly. Optionally, add a config key in `.planning/config.json`
(`claude_md.compile_mode: "reference"`) so projects opt in once.

**Pros:**

- Fixes the root cause. Every gsd-tools user benefits, not just
  claude-workflow consumers.
- The flag lives where `buildSection` already lives — colocated with
  the function being changed. Cleaner architecture.
- No need for a downstream post-processor at all.

**Cons:**

- Cross-repo work. Requires a PR to `pi-agentic-apps-workflow`, review
  cycle, release of a new gsd-tools version, then user upgrade. Slow
  feedback for cparx.
- Doesn't help projects on older gsd-tools versions (1.34.2 and earlier).
- gsd-tools' release cadence is not under claude-workflow's control.
  If the PR sits unreviewed for weeks, cparx remains bloated.
- Doesn't catch the case where someone hand-edits CLAUDE.md to add an
  inlined block (rare but possible — happened in cparx's history).

**Why rejected:** The user's prompt explicitly framed this as
"assuming source is owned by someone else and not changeable upstream."
While `pi-agentic-apps-workflow` is technically within the user's
broader AgenticApps ecosystem (so this is solvable), the time-to-cparx
relief is much slower than Alt-1. Recommend doing this AS A FOLLOWUP
once 0010 is shipping, captured as a TODO in the ADR.

---

## Alternative 3 (REJECTED) — Standalone CLI + manual cron

**Shape:** Ship `bin/normalize-claude-md.sh` as a project-level
executable that users invoke manually or schedule via `cron` /
`launchd`. No Claude Code hook integration.

**Pros:**

- Simpler — no hook lifecycle, no JSON manipulation in
  `claude-settings.json`.
- Easier to test in isolation; same script can run in CI.
- No risk of hook firing at the wrong time.

**Cons:**

- Manual. Defeats the goal of "drop cparx to ≤200L and KEEP it there."
- cron/launchd config differs per OS. Users must set it up themselves.
- No event-driven catch — if `gsd-tools generate-claude-md` runs at
  09:30 and the cron job fires at 10:00, CLAUDE.md is inconsistent for
  30 minutes.

**Why rejected:** Loses the "ongoing protection" half of Decision D.
The user explicitly requested both one-shot and ongoing. Manual-only
doesn't deliver ongoing.

---

## Alternative 4 (REJECTED) — Node script with proper HTML comment parser

**Shape:** Ship a node script using a real HTML comment parser (e.g.,
parse5 or a hand-rolled FSM). Distribute as `.claude/hooks/normalize-claude-md.mjs`.

**Pros:**

- Handles edge cases the bash regex can't (nested markers, unusual
  whitespace, embedded `-->` strings, etc.) more robustly.
- Already have node available — `gsd-tools` itself is node, so any
  project using gsd-tools has node installed.

**Cons:**

- Adds a runtime dependency on node for the hook. Some consumer
  projects might not have node (Go-only services, Python services).
- Adds an npm install step or vendors `node_modules`. Either bloats the
  template or introduces install friction.
- Edge cases the bash version can't handle are vanishingly rare in
  practice — the marker format is generated by `buildSection` and is
  always single-line, line-leading, with predictable whitespace.

**Why rejected:** Cost (dependency, install friction) outweighs benefit
(handling edge cases that don't occur in practice). Revisit if bash
implementation surfaces a real bug.

---

## Comparison matrix

| Criterion | Alt 1 (post-processor) | Alt 2 (upstream) | Alt 3 (CLI+cron) | Alt 4 (node) |
|---|---|---|---|---|
| Time to cparx ≤200L | **Hours** | Weeks | Hours (manual) | Hours |
| Blast radius | claude-workflow only | get-shit-done + downstream | claude-workflow only | claude-workflow + node dep |
| Ongoing protection | **Yes** (PostToolUse) | Yes (native) | No (manual) | Yes |
| Reversibility | Hook off + remove script | Revert PR upstream | Stop running it | Hook off + remove script |
| Maintenance burden | Low (bash, 80 LOC) | Low (one PR, native) | Low | Medium (node deps) |
| Cross-repo coordination | None | High | None | None |

**Choice:** Alternative 1. It satisfies the time-to-relief constraint
and the ongoing-protection requirement with minimal blast radius. The
ADR captures Alternative 2 as a recommended follow-up for the upstream
root-cause fix.

---

## Implementation notes for PLAN.md

- The post-processor script is the **central artifact**. Get it right
  first; the migration steps + hook registration are mechanical.
- Use line-by-line scanning with state (in-block / out-of-block) rather
  than a single multi-line regex — bash regex with `[[:space:]]*\n.*`
  is fragile across implementations (BSD vs GNU sed differ on multiline
  mode). State machine is portable.
- Reserve the test harness for empirical line-count verification —
  CONTEXT.md Decision F's estimate (250L post-0010) needs to be
  validated against the cparx-shape fixture, not asserted from theory.
- TDD strict: every assertion in `run-tests.sh test_migration_0010()`
  gets its own commit pair (RED test fails → GREEN script makes it pass).
