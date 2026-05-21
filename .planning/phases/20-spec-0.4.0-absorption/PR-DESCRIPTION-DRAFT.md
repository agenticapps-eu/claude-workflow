# Draft PR description — v1.14.0

Intended use:

```bash
# Once cross-repo PR agenticapps-eu/agenticapps-workflow-core#10 is MERGED:
gh pr create \
  --title "feat: spec 0.4.0 absorption (v1.14.0)" \
  --body-file .planning/phases/20-spec-0.4.0-absorption/PR-DESCRIPTION-DRAFT.md
```

Strip this preamble (everything above the `---` below) before piping
to `gh pr create`, or use:

```bash
gh pr create --title "feat: spec 0.4.0 absorption (v1.14.0)" \
  --body "$(awk '/^<!-- PR-BODY-START -->/,/^<!-- PR-BODY-END -->/' \
    .planning/phases/20-spec-0.4.0-absorption/PR-DESCRIPTION-DRAFT.md \
    | sed '1d;$d')"
```

---

<!-- PR-BODY-START -->

## Summary

claude-workflow v1.14.0 absorbs `agenticapps-workflow-core` spec **0.4.0** — four new sections / decisions ratified upstream.

- **§11 — Coding Discipline (NON-NEGOTIABLE)** — verbatim canonical block injected into project CLAUDE.md via migration 0014 behind a provenance-managed anchor. Vendored byte-identical copy at `templates/spec-mirrors/11-coding-discipline-0.4.0.md`.
- **§12 — Branchy workflows (Mermaid)** — audit pass on host SKILL.md files. 1 candidate converted (`ts-declare-first/SKILL.md`, newly authored at 0.4.0 — MUST satisfy). 4 deferred per §12's bulk-conversion waiver. Audit trail at `.planning/phases/20-spec-0.4.0-absorption/P3-AUDIT-LOG.md`.
- **§13 — Declare-first TypeScript** — new `ts-declare-first/` host skill scaffold. Three-commit atomicity (declare → failing test → implementation) structurally enforced. Migration 0015 installs the user-global slash-discovery symlink.
- **ADR-0015 — Secret-scanner choice (ratified)** — Status: Proposed → Accepted via cross-repo PR agenticapps-eu/agenticapps-workflow-core#10 (now merged). Decision: **STAY on gitleaks**. Locked-rule benchmark fired STAY via ties on TP recall + FP count criteria. Local mirror at `docs/decisions/0024-secret-scanner-choice.md`.

Also bundled:

- **Fix**: migration 0011's `requires.verify` preflight regex widened (`^0.3.0` literal → `^0\.[3-9]\.[0-9]+$`) — the add-observability skill has moved past 0.3.0 across v1.11.0/v1.12.0/v1.14.0; the literal pin was reporting FAIL since v1.11.0 in `--strict-preflight` mode.

## Migrations added

| ID | Slug | from → to | What it does |
|----|------|-----------|--------------|
| 0014 | inject-spec-11-coding-discipline | 1.12.0 → 1.14.0 | Inject §11 canonical block + bump `skill/SKILL.md` to 1.14.0 / `implements_spec: 0.4.0` |
| 0015 | add-ts-declare-first-skill | 1.14.0 → 1.14.0 | Install user-global `ts-declare-first` symlink (rides on 0014's bump) |

## Migration test counts

7 fixtures for 0014 + 4 fixtures for 0015 = **11 new sandboxed cases**, all PASS.

```text
$ bash migrations/run-tests.sh --strict-preflight
…
━━━ Migration 0014 — Inject spec §11 canonical block ━━━
  ✓ 01-fresh-apply
  ✓ 02-already-applied
  ✓ 03-stale-anchor
  ✓ 04-unmanaged-conflict
  ✓ 05-no-claudemd
  ✓ 06-version-mid-apply
  ✓ 07-byte-identity-replace

━━━ Migration 0015 — Scaffold ts-declare-first skill ━━━
  ✓ 01-fresh-install
  ✓ 02-already-installed
  ✓ 03-non-symlink-refuses
  ✓ 04-redirected-symlink

━━━ Preflight-correctness audit (strict — failures gate exit) ━━━
  Audit summary: PASS=19 FAIL=0 SKIP=4

━━━ Summary ━━━
  PASS: 147
```

## Verification (PLAN.md §Cross-phase verification gate)

| Gate | State | Evidence |
|------|-------|----------|
| Migration test suite green (`run-tests.sh --strict-preflight`) | ✓ | PASS=147 FAIL=0 |
| §11 byte-identity (or no host CLAUDE.md) | ✓ | claude-workflow has no root CLAUDE.md (chosen per PLAN.md P1.3 conditional); byte-identity proven indirectly via `.planning/phases/20-spec-0.4.0-absorption/P6-DOGFOOD.md` SHA-256 stability across two applies |
| `gitleaks`/`betterleaks` count in shipped artefacts | ✓ | 0 (mentions limited to session-handoff.md, .planning/, docs/decisions/0024, CHANGELOG.md — all documentation sites; the shipped scaffolder bundle is clean) |
| Spec version bump | ✓ | `skill/SKILL.md`: `version: 1.14.0`, `implements_spec: 0.4.0` |
| Cross-repo ADR PR merged | ✓ | agenticapps-eu/agenticapps-workflow-core#10 MERGED |

## Phase scope (P0–P6)

- **P0** — scoping (`add9518`)
- **P1** — migration 0014 + fixtures (`53ee11d`, `cf042b7`, `b2e059a`, `22ab218`)
- **P2** — migration 0015 + fixtures (`9c90b14`, `e7027be`, `6e7442d`)
- **P3** — §12 Mermaid audit (`eaf18e1`)
- **P4** — scanner evaluation + cross-repo ADR PR + local ADR 0024 (`817fcd1`)
- **P5** — SKIPPED (reshape per divergence D2: STAY = no new CI fragment)
- **P6** — 1.14.0 / 0.4.0 bump + CHANGELOG + dogfood + 0011 fix-along (`4702652`, `6a58534`)

## Cross-references

- Spec source (now at 0.4.0): https://github.com/agenticapps-eu/agenticapps-workflow-core
- Cross-repo ADR PR (merged): https://github.com/agenticapps-eu/agenticapps-workflow-core/pull/10
- Local ADR 0024: `docs/decisions/0024-secret-scanner-choice.md`
- CHANGELOG entry: `CHANGELOG.md` `[1.14.0] — 2026-05-21`
- §12 audit log: `.planning/phases/20-spec-0.4.0-absorption/P3-AUDIT-LOG.md`
- Dogfood evidence: `.planning/phases/20-spec-0.4.0-absorption/P6-DOGFOOD.md`

## Out of scope / carried forward

- Tracking issues in `pi-agentic-apps-workflow` + `codex-workflow` — drafts preserved at `.planning/phases/20-spec-0.4.0-absorption/P6.5-DEFERRED-tracking-issues.md`, deferred per maintainer direction at ship time.
- Implicit-trigger wiring for `ts-declare-first` (host GSD design phase auto-detection) — §13 mandates this for TS-primary projects but it's a separate mechanism from the skill itself; future work.
- Criterion-4 inversion-as-explicit-re-eval-trigger in ADR 0024 — currently relies on 12-month calendar reminder; open question for the next ADR revision.
- `test_init_fixtures()` harness (Phase 15 F4), `policy:` multi-stack support (spec §10.8), ts-supabase-edge verification (PR #41) — all unchanged-deferred.

## Test plan

- [x] `bash migrations/run-tests.sh --strict-preflight` reports PASS=147 FAIL=0.
- [x] Manual 0014 dogfood at `/tmp/dogfood-1.14.0-fixture/`: SHA-256 byte-identity across two applies.
- [x] Migration 0015 idempotency: fixture cases `02-already-installed` + `04-redirected-symlink`.
- [x] 0011 preflight rot fixed: strict-preflight audit PASS=19 FAIL=0 SKIP=4.
- [x] §11 canonical block byte-identity vs `templates/spec-mirrors/11-coding-discipline-0.4.0.md` and upstream `spec/11-coding-discipline.md`.
- [x] `ts-declare-first/SKILL.md` Mermaid §12 conversion present + `<!-- §12 audit -->` HTML comments on KEEP candidates.
- [x] Cross-repo ADR PR #10 merged (PRECONDITION FOR OPENING THIS PR).

<!-- PR-BODY-END -->
