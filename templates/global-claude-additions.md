
## Session startup

At the start of every session, check for a session-handoff.md in the current
project directory. If it exists and was modified in the last 7 days, read it
before doing anything else and confirm what you found.

## Session handoff

Before ending any session — when asked to exit, when the final task is done,
or when context is getting full — write a session-handoff.md in the current
project directory.

Format:

# Session Handoff — [date]

## Accomplished
- [what was done this session]

## Decisions
- [decision] — [why]

## Files modified
- [path] — [what changed]

## Next session: start here
[one paragraph on exactly where to pick up and what the first action should be]

## Open questions
- [anything unresolved or blocked]

Keep it under 150 lines. Write the file directly — do not print it to the terminal.
