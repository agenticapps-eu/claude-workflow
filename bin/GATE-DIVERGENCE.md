# Sanctioned divergence — `bin/openspec-change-gate.sh`

**Status:** temporary · **Opened:** 2026-07-25 · **Closes when:** upstreamed

This repo's copy of the §18 change-gate currently differs from the canonical
copy in `agenticapps-workflow-core/gate/openspec-change-gate.sh`. The §18 design
is ONE shared enforcement script, so a fork is a defect, not a feature — this
file exists to make the fork visible, bounded, and closable rather than silent.

`test_gate_matches_core_canonical` compares the two and requires the divergence
to hash-match the value below. Any *further* unrecorded change to either side
fails the suite.

## Recorded divergence

```
2a6c94ae54b8c3aae2d73c57bdd86f57169df9d41f6afa4fbe4f8f5985c1a8c0
```

## Why we diverged

Three defects found by the cross-AI review of PR #95, all present in the
canonical copy and all verified by direct invocation:

1. **Exemption bypass (the serious one).** `is_openspec_artifact` matched any
   path containing an `openspec/` component, so with the gate unsatisfied
   `src/openspec/app.ts` and even `/tmp/openspec/x.ts` were exempt and edited
   freely. Now resolved against `$ROOT` and required to sit under
   `$ROOT/openspec/`. The `--pre-commit` staged filter had the same hole
   (`(^|/)openspec/`) and is now anchored at `^`.
2. **Reviewer counting was satisfiable without reviews.** `## Reviewer` headings
   inside fenced code blocks counted, a colon-less `## Reviewers` heading
   counted, a bare `reviewers: [a, b]` line counted, and two sections from one
   vendor counted as two independent reviewers. Now: fences skipped, colon and
   a non-empty name required, distinct names only, YAML fallback removed.
3. **Fail-open inverted on parse error.** An unparseable payload fell through to
   policy evaluation and could BLOCK (visible under `OPENSPEC_GATE_STRICT=1`).
   §18 requires failing open on a *parse* error and never on policy.

## Why it is not upstreamed yet

`gate/` is **not in version control** in `agenticapps-workflow-core` — it does
not exist on `origin/main`, only as an uncommitted local directory. There is no
published canonical artifact to send a fix to, which is also why
`opencode-workflow` re-authored its copy (~256 lines diverged) instead of
reusing it.

## To close this

1. Publish `gate/` in `agenticapps-workflow-core` (commit + push).
2. Apply the three fixes above to the canonical copy.
3. Re-sync this repo: `cp <core>/gate/openspec-change-gate.sh bin/`, then delete
   this file. The guard flips from "recorded divergence" to enforcing
   byte-identity on its own.
4. **Re-sync `opencode-workflow` too** — its merged copy carries defect 1, the
   live bypass.
