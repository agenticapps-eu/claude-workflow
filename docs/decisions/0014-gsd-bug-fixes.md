# ADR-0014: rogs.me GSD bug fixes — apply Bug 1, skip Bug 2 + 3

**Status:** Accepted
**Date:** 2026-05-03
**Linear:** —
**Phase:** Phase 1 of `feat/programmatic-hooks-architecture-audit`

## Context

[rogs.me's "I patched GSD" article](https://rogs.me/2026/04/i-patched-gsd-and-why-you-should-patch-it-too/)
calls out three bugs in vanilla GSD that affect anyone running the
`/gsd-review` cross-AI review flow:

1. `2>/dev/null` on the `opencode run` invocation causes opencode to hang
   waiting for something on the silenced stderr stream that never closes.
2. `claude -p --no-input` is an invalid flag — `--no-input` doesn't exist;
   the call silently fails.
3. The reviewers loop runs sequentially when (rogs.me argued) it could be
   parallelized with `&`/`wait` for ~3-6× speedup.

We audited the local install (`~/.claude/get-shit-done/`) against all
three claims to decide what to apply.

## Decision

### Bug 1 — APPLIED

`workflows/review.md:169` matches the rogs.me pattern verbatim:

```diff
-cat /tmp/gsd-review-prompt-{phase}.md | opencode run - 2>/dev/null > /tmp/gsd-review-opencode-{phase}.md
+cat /tmp/gsd-review-prompt-{phase}.md | opencode run - > /tmp/gsd-review-opencode-{phase}.md
```

Patched in place; canonical copy mirrored to
`~/.config/gsd-patches/patches/workflows/review.md` with sync/check
infrastructure (rogs.me's storage pattern, adopted because the
AgenticApps migration framework only handles AgenticApps-project
upgrades, not patches against external skills like GSD).

### Bug 2 — NOT PRESENT

`grep -rn "no-input\|--no-input" ~/.claude/get-shit-done/` returns zero
hits. Either the GSD author already removed the invalid flag in a
release after rogs.me's article, or this install never had it. **No
patch needed.**

### Bug 3 — SKIPPED (respect upstream)

`workflows/review.md:142` has an explicit design comment:

> For each selected CLI, invoke in sequence (not parallel — avoid rate limits)

rogs.me's parallelization patch contradicts an explicit upstream
decision made later than rogs.me's article. The trade-off is real:
parallel is faster but more rate-limit-sensitive; sequential is slower
but more reliable on rate-limited model APIs.

**We respect the upstream decision** rather than silently overriding
it. Surfaced to the user with three options (skip / apply / guarded
behind `${GSD_PARALLEL_REVIEWS:-true}` flag); user chose skip.

If rate-limit budgets improve and parallel becomes safe by default,
revisit and consider upstreaming a guarded-with-flag version to GSD.

## Alternatives Rejected

- **Apply all three patches verbatim from rogs.me.** Rejected — Bug 2
  isn't present (would be a no-op patch); Bug 3 contradicts an explicit
  upstream design choice that rogs.me's article didn't anticipate. Blind
  application would be sloppy.
- **Skip all three; treat the article as inspiration only.** Rejected —
  Bug 1 IS present and IS a real bug rogs.me empirically reported.
  Skipping a real free win because the other two don't apply is
  over-conservative.
- **Express the patch through the AgenticApps migration framework
  (v1.3.0+).** Rejected — the migration framework targets AgenticApps
  **projects**, not external skills like GSD. The framework's
  `migrations/` files patch a project's installed copy of the workflow
  scaffolder; GSD lives outside that scope. The right tool for foreign-
  skill patches is dotfile management, not the migration framework.
  This boundary is documented in `templates/gsd-patches/README.md`
  ("Future migration to AgenticApps migration framework" section) so
  it's revisitable if the framework grows foreign-skill support.

## Consequences

**Positive:**
- `/gsd-review` no longer hangs on the opencode reviewer.
- Canonical patch storage at `~/.config/gsd-patches/` survives `gsd
  update` wipes; `bin/sync` re-applies idempotently; `bin/check` flags
  drift before it bites.
- Pattern is reproducible across machines via the
  `templates/gsd-patches/` mirror in this scaffolder repo (clone, copy
  to `~/.config/gsd-patches/`, done).
- Future patches add a dated CHANGELOG entry + a file in `patches/`;
  no scope creep on the scaffolder repo for foreign-skill patches.

**Negative:**
- Adds one more user-side dotfile artifact to remember after a fresh
  laptop setup. Mitigated by templates mirror + README.md operating
  instructions.
- The sync/check pattern is one-way (patches → GSD). If the GSD author
  ships an upstream fix that conflicts with our patch, `check` flags
  drift but doesn't auto-resolve. User must manually reconcile and
  update `patches/`.
- We're carrying a private fork of one upstream file. Risk: GSD
  refactors the file structure and our patch becomes unapplyable. `check`
  catches this at sync time; the cost is "open the file, compare diffs,
  re-author the patch".

**Follow-ups:**
- Open an upstream issue in GSD's repo about Bug 1 so the patch can
  eventually retire. Carrying a private fork in perpetuity is a
  worse outcome than upstreaming.
- Consider a `gsd-customizations.md` companion (per rogs.me) listing
  every patch in human-readable form for project audits. Already
  partially done via `templates/gsd-patches/CHANGELOG.md`.

## References

- [rogs.me — I patched GSD, and why you should patch it too](https://rogs.me/2026/04/i-patched-gsd-and-why-you-should-patch-it-too/)
- Source synthesis: `tooling-research-2026-05-02-batch2.md` §2
- Hand-off prompt: Phase 1 of the batch-2 prompt
- Live patches: `~/.config/gsd-patches/`
- Mirror in this repo: `templates/gsd-patches/`
- Upstream file we patched: `~/.claude/get-shit-done/workflows/review.md` line 169
