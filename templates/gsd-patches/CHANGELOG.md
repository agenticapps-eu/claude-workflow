# gsd-patches CHANGELOG

Local patches against `~/.claude/get-shit-done/`. Apply with `bin/sync`,
verify with `bin/check`. Storage pattern adapted from
[rogs.me — I patched GSD, and why you should patch it too](https://rogs.me/2026/04/i-patched-gsd-and-why-you-should-patch-it-too/).

## 2026-05-03 — Bug 1: opencode run hang

**Patch:** `patches/workflows/review.md`

Strip ` 2>/dev/null` from the `opencode run` invocation at line 169.

```diff
- cat /tmp/gsd-review-prompt-{phase}.md | opencode run - 2>/dev/null > /tmp/gsd-review-opencode-{phase}.md
+ cat /tmp/gsd-review-prompt-{phase}.md | opencode run - > /tmp/gsd-review-opencode-{phase}.md
```

**Why:** rogs.me reported that suppressing stderr causes `opencode run` to
hang waiting for something on stderr that never closes. Removing the
redirect lets opencode complete normally; stderr noise is acceptable
(reviewers' output goes to stdout into the per-phase file).

**Source:** rogs.me article + Donald confirmed the same behavior.

## 2026-05-03 — Bug 2 (rogs.me's `--no-input` claim): NOT PRESENT

`grep -rn "no-input\|--no-input" ~/.claude/get-shit-done/` returns zero
hits in this install. Either the GSD author already removed the invalid
flag in a release after rogs.me's article, or this install never had
it. **No patch needed.**

## 2026-05-03 — Bug 3 (rogs.me's parallel-reviewers): SKIPPED

Upstream `~/.claude/get-shit-done/workflows/review.md` line 142 has an
explicit design comment:

> For each selected CLI, invoke in sequence (not parallel — avoid rate limits)

rogs.me's parallelization patch (each CLI in `&` followed by `wait`)
contradicts an explicit upstream design decision. We respect the
upstream's choice rather than silently overriding it. If rate-limit
budget improves enough that parallel becomes safe, revisit.

**Decision:** SKIPPED. Documented in the workflow scaffolder ADR
`docs/decisions/0014-gsd-bug-fixes.md`.

---

## Operating instructions

After every `gsd update`:

```bash
~/.config/gsd-patches/bin/check  # verify state
# If drift: re-apply
~/.config/gsd-patches/bin/sync   # idempotent re-application
```

To add a new patch:

1. Edit the file in `~/.claude/get-shit-done/` directly to verify the
   change works.
2. Copy the patched file into `~/.config/gsd-patches/patches/<relpath>`
   preserving the relative path under `~/.claude/get-shit-done/`.
3. Add a dated CHANGELOG entry above with diff + rationale.
4. Commit `~/.config/gsd-patches/` to your dotfiles repo.
