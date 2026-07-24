# Session Handoff — 2026-07-16 (0029 §11-strip data-loss guard — MERGED)

## Status: DONE. PR #94 MERGED (squash 0331491) to main. Nothing in flight. Suite PASS=217.

Picked up handoff follow-up #3 (0029's §11 strip deletes user prose). It grew into
a 5-round cross-AI review cycle. **Shipped and merged.** CI green (CodeRabbit +
migrations-and-snapshot). Local main synced to 0331491.

## Accomplished
- **Migration 0029 fixed in place** (engine bugfix, NO version bump — 0028/85430f1
  precedent; to_version unchanged). Layered guard on BOTH Apply and Rollback:
  1. **Clean-text gate** — refuse any CLAUDE.md with a NUL or CR byte (toolchain
     is undefined on those: grep binary-skip, BSD awk NUL-truncation, CR anchor-miss).
  2. **`export LC_ALL=C`** in idempotency + Apply + Rollback → byte-deterministic
     grep/awk/sed (a UTF-8 locale splits them on `[^[:space:]]` over U+2028 & kin).
     Idempotency also runs the clean test so a dirty file routes to a loud refuse.
  3. **Exact-deletion-set guard** — reverse-run the strip's state machine to
     reproduce EXACTLY what it deletes (all provenance blocks), compare non-blank
     content to canonical×count; differ → refuse (exit 3), file untouched.
- 7 new fixtures (12–18), each mutation-proven + reachability-asserted. Suite 217.
- ADR-0043, CHANGELOG `[Unreleased]` (no bump).

## Decisions
- **Refuse over repair / preserve / end-marker** (user-confirmed approach A): differ
  from canonical modulo blanks → refuse. Rejected preserve-prose (ambiguous where
  prose goes when block moves) and §11 end-marker (needs own migration, verbatim-spec).
- **Guard BOTH Apply + Rollback** (user call) — no known-identical hole left behind.
- **Removed trailing-ws normalization** (round 2 added it, round 3 removed it): it
  couldn't fix a trailing-ws heading without diverging the guard from the strip, and
  risked rewriting a Markdown hard-break. Compare non-blank only, like 0030.

## The lesson that cost a whole round (SAVED to memory)
Round 5 I "found" a high-byte grep/awk data-loss and "fixed" it (awk-based presence
+ fixture 19). **It was my ugrep shim**, not real BSD grep — `/usr/bin/grep` matches
0x80 identically to awk (codex confirmed all 253 bytes agree). Reverted the phantom
fix + false-premise fixture. Memory `grep-shim-ignores-gitignore` extended: validate
migration shell with `/usr/bin/grep`, never the bare `grep` in the Bash tool, for
BYTE matching too (not just .gitignore).

## Files modified (all committed on the branch)
- `migrations/0029-region-aware-spec-11-placement.md` — the 3-layer guard
- `migrations/test-fixtures/0029/12..18-*/**` — 7 new fixtures + harness reachability
- `migrations/run-tests.sh` — anchor-parity 3→5 (guards carry the alternation)
- `docs/decisions/0043-*.md` (NEW), `CHANGELOG.md`

## Next session: start here
**Nothing in flight.** #94 merged. Deferred follow-ups, in value order: (#1) 0030's
own deferred codex MED/LOW findings; (#4) propagate to codex-workflow/opencode-workflow
(prompts still at those repo roots from the 0029 cycle). Do NOT run `gitnexus analyze`
in these repos (rewrites AGENTS.md/CLAUDE.md; --skip-agents-md mitigates). Note a
stale local branch `fix/0029-spec-11-region-aware-placement` exists (earlier session,
not from this work) — leave it unless the owner asks.

## Open questions / follow-ups
1. 0030 still has a duplicate-provenance false-refuse edge (documented, safe, degenerate).
2. Predictable guard temp paths hardened with rm-f; pre-existing strip/insert temps
   share the pattern family-wide (0030/0031) — out of scope, noted in migration doc.
3. codex review filter: security-framed prompts trip OpenAI's cyber filter; neutral
   "correctness review of a text transformation" framing works. Reuse that.
