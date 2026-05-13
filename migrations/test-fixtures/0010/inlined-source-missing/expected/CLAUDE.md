# Inlined Source Missing fixture

Exercises the safety guard: when `source:` points to a non-existent
file, the block is preserved unchanged. Other blocks (with valid
sources) are still normalized.

<!-- GSD:project-start source:NONEXISTENT.md -->
## Project

**Test Project — source missing**

This block's `source:` attribute resolves to a path that does not exist
on disk. The post-processor MUST preserve this block unchanged and emit
a warning to stderr.
<!-- GSD:project-end -->

<!-- GSD:stack source:codebase/STACK.md /-->
## Technology Stack
See [`.planning/codebase/STACK.md`](./.planning/codebase/STACK.md) — auto-synced.

## Project notes

Trailing content; preserved.
