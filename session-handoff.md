# Session Handoff — 2026-05-16 (REDACTED_KEYS expansion + cparx v1.10.0 adoption verification)

Two parallel bundles of work, both on feature branches, neither pushed:

- **claude-workflow** `chore/redacted-keys-default-v0.3.2` — 2 commits
  ahead of `main @ 763d041`. v0.3.2 of `add-observability` skill +
  ts-react-vite template fix + cparx adoption report.
- **cparx** `chore/observability-adoption-v1.10.0` — 7 commits ahead
  of `main @ dee56e76`. Real-repo verification of the v1.10.0 +
  v1.11.0 migration chain on a delivered prototype.

User direction: "bundle later", "real branch in cparx", "no
clarifying questions". All work landed locally; user decides when /
whether to push + open PRs.

## Accomplished

### claude-workflow side

`8d76bb2 feat(add-observability): expand REDACTED_KEYS default (v0.3.1 → v0.3.2)`
- Closes Phase 15 /cso S1. Adds 4 universal token shapes to the
  redaction default: `secret`, `client_secret`, `refresh_token`,
  `access_token`.
- 5 stack templates (meta.yaml defaults + policy.md.template lists) +
  8 init reference fixtures synced. ts-react-vite preserves its
  browser-specific `credit_card` entry.
- Pure declarative-doc + template change; no migration; no scaffolder
  version bump per S1's "defer to skill minor".
- Skill `0.3.1 → 0.3.2`. Phase-15 smoke pin updated to match.

`2f24fc3 fix(ts-react-vite): re-export ObservabilityErrorBoundary from wrapper + cparx adoption report`
- F2 from cparx verification. Adds `export { ObservabilityErrorBoundary }
  from "./ErrorBoundary";` to `templates/ts-react-vite/lib-observability.ts`.
  INIT.md Phase 5 detail required this; init fixture documented it;
  template never matched. Direct evidence for why the deferred
  `test_init_fixtures()` harness matters.
- Adds `.planning/cparx-v1.10.0-adoption-verification/REPORT.md` —
  full walkthrough of the cparx adoption with 3 findings (1
  user-side blocker, 1 template bug, 1 soft gap) + reuse guidance
  for the next adoption target (fx-signal-agent).

### cparx side

7 commits taking `agenticapps-eu/cparx` from workflow `v1.9.3 / no
observability` to `v1.11.0 / spec §10 conformant`:

```
5c29da44 chore: migrate AgenticApps workflow 1.10.0 → 1.11.0 (migration 0012)
022c6680 chore: migrate AgenticApps workflow 1.9.3 → 1.10.0 (migration 0011 Steps 2-4)
cfc15d74 feat(observability): migration 0011 Step 1 — author baseline.json
571aea90 feat(observability): init Phase 6 — observability metadata block in CLAUDE.md
79df9e6b feat(observability): init Phase 5 — wire entry files + Sentry SDK deps (dual stack)
f0caa3d1 feat(observability): init Phase 4 — scaffold wrapper + middleware + policy (dual stack)
d6a6ccc2 chore: remove stale vendored add-observability skill (v0.2.1)
```

Pre-existing unrelated dirty state on cparx
(`codebase-analysis-docs/CODEBASE_KNOWLEDGE.md` + `workflows.png`)
was stashed as `pre-observability-adoption: snapshot of unrelated WIP`.

## Decisions

- **Stale vendored skill required removal before adoption**. cparx
  had `.claude/skills/add-observability/SKILL.md @ v0.2.1` shadowing
  the global v0.3.1. Without removal, `/add-observability init`
  would resolve to v0.2.1 (no init subcommand) and fail. Resolved by
  deleting the entire vendored tree.
- **Dev-machine global clone pulled to main pre-adoption**. The
  global `~/.claude/skills/agenticapps-workflow/` was at v1.10.0
  (HEAD `e587741`) — pre-init. Pulled to HEAD `763d041` to get
  v1.11.0 / v0.3.1. The chore branch's v0.3.2 isn't pushed yet, so
  cparx adoption used v0.3.1 defaults (6 keys backend, 7 keys vite).
  Once the chore branch merges, cparx can manually refresh policy.md
  to v0.3.2's 10/11-key list (or leave it — policy.md is
  user-editable).
- **Global slash-discovery symlink installed manually**.
  `~/.claude/skills/add-observability → ~/.claude/skills/agenticapps-workflow/add-observability`
  set up as a pre-step (equivalent to migration 0012 Step 4 against
  the dev box, not against any project).
- **F2 (ts-react-vite re-export bug) bundled into v0.3.2**.
  Discovered during cparx adoption; same chore branch is the natural
  home rather than a separate v0.3.3 release. CHANGELOG entry covers
  both REDACTED_KEYS and the F2 fix under `[1.11.0]`.
- **Hand-authored baseline.json on cparx**. 14 high-confidence gaps
  from a fast grep-based survey, NOT a real LLM-driven SCAN.md run.
  Schema-correct (jq verify passes); counts conservative.
  Documented in the commit message that teams should refresh with
  `claude /add-observability scan --update-baseline` before merging.
- **Multi-stack init: lex-first stack's policy.md goes in CLAUDE.md**.
  cparx's CLAUDE.md `observability.policy:` field names the Go
  backend's policy (`backend/internal/observability/policy.md`),
  not the Vite frontend's. Spec §10.8 line 157 requires scalar
  `policy:`; multi-stack `policy:` unification is deferred to a
  future spec amendment + matching parser change (per INIT.md
  Phase 6 "Schema constraint").
- **0011 Step 2 expected to be no-op when init lands before 0011**.
  When init runs first (v1.11.0 ordering), Step 2's "bump
  spec_version 0.2.1 → 0.3.0" is already done. Migration's
  idempotency check correctly handles this — positive finding,
  not a bug.

## Files modified

### claude-workflow (`chore/redacted-keys-default-v0.3.2`)

- 5× `add-observability/templates/<stack>/meta.yaml` — `REDACTED_KEYS`
  default + 4 entries each
- 5× `add-observability/templates/<stack>/policy.md.template` —
  `## Redacted attributes` list + 4 entries each
- `add-observability/templates/ts-react-vite/lib-observability.ts` —
  added `export { ObservabilityErrorBoundary }` line (F2 fix)
- 8× init fixture wrapper files — `REDACTED_KEYS=[…]` comment sync
- 7× init fixture `policy.md` files — bullet list sync
- `add-observability/SKILL.md` — version `0.3.1 → 0.3.2`
- `CHANGELOG.md` — entries for REDACTED_KEYS + F2 fix
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh` —
  skill-version pin updated to 0.3.2
- `.planning/cparx-v1.10.0-adoption-verification/REPORT.md` — new
  verification report

### cparx (`chore/observability-adoption-v1.10.0`)

Per-commit, see the 7 SHAs above. Net effect:

- Deleted: `.claude/skills/add-observability/` (28 files, 252K)
- Added: `backend/internal/observability/` (observability.go,
  middleware.go, policy.md)
- Added: `frontend/src/lib/observability/` (index.ts, ErrorBoundary.tsx,
  policy.md)
- Added: `.observability/baseline.json`
- Modified: `backend/cmd/api/main.go` (3 anchored insertions)
- Modified: `backend/go.mod` + `backend/go.sum` (sentry-go v0.46.2)
- Modified: `frontend/src/main.tsx` (2 anchored regions)
- Modified: `frontend/package.json` + `frontend/package-lock.json`
  (@sentry/react ^8.0.0 → resolved 8.55.2)
- Modified: `CLAUDE.md` (Observability section + enforcement subsection)
- Modified: `.claude/skills/agentic-apps-workflow/SKILL.md`
  (1.9.3 → 1.11.0)

## Verification

claude-workflow tests, post both commits:
- `migrations/run-tests.sh --strict-preflight | tail -3` → **PASS=131**,
  no FAIL line
- `.planning/phases/15-init-and-slash-discovery/smoke/run-smoke.sh
  | grep Passed/Failed` → **Passed: 9 / Failed: 0**

cparx build verification, post all 7 commits:
- `cd backend && go build ./...` → clean
- `cd frontend && npx tsc --noEmit | grep "src/lib/observability\|src/main.tsx" | wc -l` → 0

Migration 0011 post-checks (cparx):
- `jq -e '.spec_version == "0.3.0"' .observability/baseline.json` → true
- baseline.json schema (scanned_commit 40-char + policy_hash sha256:<64-hex>) → valid
- `^### Observability enforcement (local)` in CLAUDE.md → present
- `version: 1.11.0` in `.claude/skills/agentic-apps-workflow/SKILL.md` → present

Migration 0012 post-checks (cparx + dev box):
- `~/.claude/skills/add-observability` symlinks to
  `~/.claude/skills/agenticapps-workflow/add-observability` → yes
- target's `SKILL.md` reads `name: add-observability` → yes
- cparx SKILL.md at v1.11.0 → yes

## Next session: start here

1. **Decide push/PR order**. Two parallel branches; recommended:
   - Push & PR claude-workflow `chore/redacted-keys-default-v0.3.2`
     against `main` first. Includes both v0.3.2 and the F2 template
     fix + the cparx report as evidence.
   - After it merges, push cparx `chore/observability-adoption-v1.10.0`
     and decide whether to PR-merge into cparx main or keep as a
     reference branch.
2. **Optional: refresh cparx's baseline.json with a real scan** before
   the cparx PR. `cd cparx && claude /add-observability scan --update-baseline`
   produces authoritative counts via the SCAN.md procedure.
3. **F1 follow-up**: write a migration `0013-stale-vendored-cleanup.md`
   (or fold detection into 0011's pre-flight) so the next adopter
   doesn't hit the silent-blocker the way cparx did. Documented in
   the cparx report.

Plausible follow-ups after the two PRs merge:

- **fx-signal-agent adoption** with the cparx report as the
  reference. Likely runs cleaner than cparx because v0.3.2 ships
  the F2 fix, and the F1 detection lesson is now documented.
- **F3 (multi-binary Go entry detection)**: post-candidate-selection
  HTTP-shape verification, v0.3.4 or v0.4.0 of the skill.
- **test_init_fixtures() harness**: long-deferred (Phase 15 F4); F2
  is direct evidence for the value.

## Open questions (carried forward)

- **REDACTED_KEYS adoption on existing installs**: policy.md is
  user-editable so the v0.3.2 default doesn't propagate. Worth a
  one-line note in the CHANGELOG that teams can manually add the
  4 entries if they want them. (Already in commit `8d76bb2`'s
  message; not load-bearing.)
- **Multi-stack `policy:` field**: cparx and any other dual-stack
  project ships only the primary stack's path in CLAUDE.md.
  Secondary stack's policy.md exists and is referenced by its own
  wrapper, but spec §10.8 has no field for it. Future spec amendment
  could add `policies: [stack1/path, stack2/path]` array form +
  matching parser change in migration 0011.
- **Carried from prior sessions** (unchanged): CI workflow wiring
  for `--strict-preflight`; helper-script license consent for
  `index-family-repos.sh --all`; canonical install command for
  `/gsd-review`; Residual #32 (formal §1-§8 conformance audit doc).
