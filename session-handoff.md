# Session Handoff — 2026-07-25 (bind OpenSpec v1 — PARKED, waiting on core)

## Status
**PR #95 is OPEN, green, mergeable — deliberately NOT merged.**
https://github.com/agenticapps-eu/claude-workflow/pull/95
Branch `feat/bind-openspec-v1` · 15 commits · 71 files · +3252/−2306 · 0 behind main
· working tree clean, everything pushed · suite 197 PASS / 0 FAIL.

**Why parked:** `agenticapps-workflow-core` is actively building the shared
`gate/` script. This PR carries three gate fixes as a *recorded divergence* that
becomes redundant once core publishes. Owner's call was to wait rather than ship
a divergence about to be superseded. Cost of waiting: a large diff ages against a
repo others are touching — re-check `git rev-list --count HEAD..origin/main`
before resuming.

---

## ▶ RESUME TRIGGER: core publishes `gate/`

Check it in one command:
```bash
git -C ../agenticapps-workflow-core fetch -q origin main
git -C ../agenticapps-workflow-core ls-tree -r --name-only origin/main | grep '^gate/'
```
Today that prints **nothing** — `gate/` and `prompts/` are NOT in version control
in core (uncommitted local dirs only, absent from `origin/main`). That absence is
the root cause of the whole fleet drift; see "Structural finding" below.

### Then do exactly this
1. `git -C ../agenticapps-workflow-core pull` and confirm `gate/openspec-change-gate.sh` is tracked.
2. `bash migrations/run-tests.sh gate-parity` — it flips itself from
   `RECORDED-DIVERGENCE` to enforcing byte-identity. No code change needed to
   activate it.
3. **Fold these four fixes into core's published version** (all four are enumerated
   with rationale in `bin/GATE-DIVERGENCE.md`, which exists for this handoff):
   - exemption bypass anchored to `$ROOT/openspec/` (also the `--pre-commit` filter)
   - reviewer counting: fence-aware, colon+name required, distinct names, no YAML fallback
   - fail-open on parse errors only, never on policy
   - `# gate-version:` marker so installers can refuse a downgrade
4. Bump `# gate-version:` above `1.1.0`.
5. Re-vendor: `cp ../agenticapps-workflow-core/gate/openspec-change-gate.sh bin/`
6. **Delete `bin/GATE-DIVERGENCE.md`** — the guard FAILS if the record outlives
   the fork. That is intentional; it stops a stale exemption lingering.
7. `bash bin/build-snapshot.sh && bash migrations/run-tests.sh` → expect green.
8. Rebase on main if it moved, then merge #95.

---

## Structural finding (the reason any of this was needed)
§18's design is ONE shared enforcement script every host calls. That invariant was
**unenforced and already broken**:
- `gate/` is not published anywhere → nothing to sync from.
- `opencode-workflow` therefore re-authored its copy (**~256 lines diverged**).
- All three copies carried the same exemption bypass.

This PR adds the missing teeth: `test_gate_matches_core_canonical` (parity vs core,
via the `CORE_SPEC_DIR` checkout the §11 mirror test already uses) plus a
`# gate-version:` marker + installer downgrade-refusal.

---

## ⚠ Live issue NOT fixed here — do this regardless of #95
**`opencode-workflow` ships the exemption bypass in already-merged code**, and its
installer has the same shared-path propagation vector. Concretely, on this machine:
`~/.agenticapps/bin/openspec-change-gate.sh` is written unconditionally by every
host's installer (last-writer-wins), so **running opencode's installer republishes
the bypassed gate for every agent**. Needs its own PR. Every host installer needs
the version check — one host without it still clobbers.

Reproduce the bypass in ~30s:
```bash
# in a repo with an active, unreviewed change:
printf '{"tool":"Edit","tool_input":{"file_path":"src/openspec/app.ts"}}' \
  | bash <gate>            # exits 0 (should be 2)
```

---

## Deferred codex findings (all recorded, none blocking)
HIGH 8 idempotency checks describe partial end states · HIGH 10 rollback recipes
over-delete (`rm -rf openspec/`, `git checkout --` whole dirs) · `find` errors read
as "no active change" in ci/pre-commit · no-jq path misses `notebook_path` ·
newline-in-filename handling · no timeout binary on stock macOS · producer counts
duplicate/failed reviewers.

## Open questions
1. Should this repo dogfood its own gate (`openspec init` here)? The `gate` CI job
   currently passes trivially because there is no `openspec/` slot — it proves
   nothing until then. Deliberate act, not mid-PR.
2. `.planning/` (35 phase dirs) still needs the supervised Tier-2 fold into
   `openspec/specs/` capabilities. Explicitly out of migration 0032's scope.
3. CodeRabbit was rate-limited on every run — its ✅ is not a real second opinion.
   The actual review coverage was codex + gemini + my own pass.

## Then: remaining hosts
Prompt 01 still to run for `codex-workflow` and `pi-agentic-apps-workflow`
(opencode done). Their hook surfaces are the least-proven: codex's `apply_patch`
matcher and pi's hook mechanism.
