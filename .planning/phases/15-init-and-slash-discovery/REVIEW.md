# Phase 15 — REVIEW.md (pre-landing structural review)

**Branch:** `feat/init-and-slash-discovery-v1.11.0` vs `main`
**Reviewed at HEAD:** `31f6546` (T15 — VERIFICATION shipped)
**Diff:** 114 files, +5501 / −200, 17 commits since `2fecb34`
**Reviewer:** Claude (T16 structural review, 2026-05-16)

## Scope check

**Scope: CLEAN.** The diff matches the stated phase intent (PLAN.md
T1-T15 work). No scope creep detected:

- `install.sh` — single LINKS row addition (T1).
- `migrations/0002` + `migrations/0012` + `migrations/test-fixtures/0012/` — slash-discovery wire-up (T2-T3).
- `add-observability/init/INIT.md` + `metadata-template.md` — init contract (T4 + T11).
- `add-observability/templates/*/policy.md.template` — per-stack policy bodies (T10).
- `migrations/test-fixtures/init-*/` — 7 fixture pairs (T5-T9).
- `add-observability/SKILL.md` 0.3.0 → 0.3.1 + routing-table invariant (T12).
- `skill/SKILL.md` 1.10.0 → 1.11.0 + `CHANGELOG.md` (T13).
- `smoke/`, `VERIFICATION.md` (T14-T15).
- `.planning/phases/15-init-and-slash-discovery/*` — phase artifacts.
- `session-handoff.md` — running handoff (mid-flight in this branch; will be refreshed in T17).

Plan completion audit (PLAN T1-T15 vs diff): **15/15 DONE.** T16 (this
file) is in progress; T17 (handoff + PR) is the only remaining task.

## Critical findings

**None.** No SQL safety issues (no SQL in scope), no LLM-output trust
boundary violations (no LLM payload parsing), no shell-injection
surfaces in the modified scripts, no concurrency hazards, no enum
exhaustiveness gaps in changed code paths.

## Informational findings

### F1 (confidence 7/10) — `migrations/0012-slash-discovery.md:74-91` — pre-flight rationalization comment

The pre-flight item-4 hard-abort message includes a comparative
argument: *"Phase 14's 'applied with warning' pattern does not apply
because 0012 has no scaffolder-owned content to overwrite — there is
nothing valid to install if the symlink is wrong."* This is reasoning
about a different migration's behaviour embedded in this migration's
source. The reasoning is correct but rots fast: if migration 0014
adopts a different abort-vs-warn policy, this comment becomes
misleading.

**Suggested fix**: keep the policy statement (HARD ABORT, no version
bump); drop the comparison to phase 14. The rationale belongs in the
phase 15 PLAN, not in the migration's stable artifact.

**Action**: would-fix-if-trivial; ASK item — not auto-applied because
phrasing is editorial.

### F2 (confidence 6/10) — `INIT.md` Phase 5→6 cross-phase skip rule is prose-only

INIT.md Phase 5 decline path says *"Phase 6 (CLAUDE.md observability
block) WILL NOT run on this decline path — writing the metadata block
now would falsely claim conformance to §10.7 obligation (2)."* This is
a critical correctness rule (writing a CLAUDE.md block when the entry
file isn't wired = false-conformance claim to scan & migration 0011).
The rule lives only in Phase 5's prose decline-path; Phase 6's entry
text does not re-state "skip if a stack is in gate-2-decline state."

**Risk**: a future maintainer refactoring Phase 6 might not re-read
Phase 5's decline-path text and could accidentally remove the
cross-phase skip. The structural assertion gate in Phase 9 doesn't
catch this (it only checks final post-state structural invariants, not
per-stack consent flow).

**Suggested fix**: add a one-line prerequisite to Phase 6's entry:
*"Prerequisite: for each stack, gate 2 (Phase 5) must have been
accepted. Stacks in gate-2-decline state are skipped entirely in
Phase 6."*

**Action**: would-fix-if-trivial; ASK item — single-paragraph addition
to INIT.md, low risk.

### F3 (confidence 5/10) — Migration 0012 Step 1 `ln -sfn` is belt-and-suspenders

Pre-flight items 3-4 already abort on (a) existing non-symlink at
target, (b) existing wrong-target symlink. After pre-flight, the only
possible state at `$HOME/.claude/skills/add-observability` is "missing"
or "right-target symlink". Step 1 then uses `ln -sfn` (force-replace
even existing right-target). The `-f` is dead in practice — a
right-target symlink is already idempotent under plain `ln -s` (no, it
errors on EEXIST — so `-f` is necessary for the right-target idempotent
case). Verified by reading the apply path: `-sfn` is correct.

**Action**: no change. This is not a finding; it's me verifying my
suspicion was unfounded. Recorded for transparency.

### F4 (confidence 8/10) — Vite fixture `expected-after/index.ts` is a structural stub

`migrations/test-fixtures/init-ts-react-vite/expected-after/src/lib/observability/index.ts`
contains a structural stub (~36 lines) rather than the ~12k of
token-substituted real template output. The stub's `init()` body is a
comment, not executable code. The fixture's preamble documents this
explicitly ("Fixture stub — the real init produces ~12k…").

**Risk**: if a future test attempts byte-equivalence comparison
between the fixture and the materialised init output, it'll fail.
**Mitigation in place**: `migrations/run-tests.sh` doesn't currently
run init-fixture comparisons (the init fixtures are reference-only at
v1.11.0). VERIFICATION.md F4-row explicitly flags the two-tier design
and the structural-vs-byte-equivalent distinction.

**Action**: no fix needed at v1.11.0. Flagged for future phase that
adds a `test_init_fixtures()` harness function — that phase will need
to choose: (a) inflate stub to full template output, or (b) compare
structurally (existence + grep) only.

### F5 (confidence 6/10) — `enforcement/observability.yml.example` not in routing-table invariant scope

The routing-table structural invariant in `add-observability/SKILL.md`
checks paths under `./<sub>/` referenced from the routing table.
`./enforcement/README.md` IS referenced and exists. The example CI
workflow `./enforcement/observability.yml.example` is NOT referenced
from the routing table (it's documentation/reference, not a sub-skill
prompt) — so it's correctly outside the invariant's scope. Flagged for
the record so a future maintainer doesn't add it to the routing table
by accident and break the invariant.

**Action**: no change.

## Documentation staleness check

- `README.md`: no scope-relevant changes detected in the diff.
- `CHANGELOG.md`: updated this branch (T13).
- `setup/SKILL.md`: updated this branch (T1 — describes add-observability registration).
- `docs/decisions/`: no new ADR for v1.11.0; the rationale lives in the phase PLAN + CHANGELOG. **Flagged**: phase 15's two structural decisions (scalar `policy:` value at v0.3.1; cross-tree `applies_to` in migration 0012) are individually small but together codify two new conventions. Consider a single small ADR after merge documenting the two precedents so future phases inherit the rationale via decisions/ rather than digging in old PLAN.md files.
- `migrations/README.md`: updated this branch (T2 — chain table entry).

**Action**: ADR for the two new precedents is **NOT a blocker** for
this phase; flagged as a follow-up for the post-ship doc sync (the
`document-release` skill handles this category of cross-doc reconciliation).

## TODOS cross-reference

No `TODOS.md` at repo root. Skipping.

## Adversarial pass — single-reviewer mode

Skipped the gstack /review skill's specialist subagent army and codex
adversarial pass for this phase. Reasoning:

- The diff is +5501/−200 but ~85% docs/fixtures/templates. Code
  changes concentrate in 3 surfaces: `install.sh` (single LINKS row),
  migration 0012 (3 steps), and `add-observability/SKILL.md` frontmatter
  + routing-table-invariant section.
- Codex + gemini + Claude already reviewed PLAN.md v1 → v2 with the
  20-item revision list applied (see `15-REVIEWS.md`).
- The structural / correctness load-bearing properties (scalar `policy:`,
  POLICY_PATH parser idempotency, gate-2-decline → Phase-6-skip) are
  asserted in VERIFICATION.md against actual fixture output.

If the PR-time reviewer wants a second-AI pass, the canonical command
is `codex review --base main` against this branch.

## Summary

**No CRITICAL findings. 4 INFORMATIONAL findings (3 documentation /
hardening; 1 transparency note).** Of the 4:

- F1 (rationalization comment in migration 0012) — would-fix-if-trivial; ASK.
- F2 (Phase 5→6 cross-phase skip rule documentation hardening) — would-fix-if-trivial; ASK.
- F4 (Vite fixture stub) — no fix at v1.11.0; flagged for future harness phase.
- F5 (enforcement workflow scope) — transparency note only.

F3 was a false alarm verified by reading the apply path.

**Phase 15 is structurally ready to land.** /cso follow-up (next
section of T16) will examine the security-specific concerns the PLAN
T16 called out (REDACTED_KEYS default, anchor-comment injection,
symlink-target tampering).

---

# Phase 15 — SECURITY.md (post-phase /cso section)

**Scope per PLAN T16**: REDACTED_KEYS default sufficiency, anchor-comment
injection bypass surface, symlink-based-discovery CVE pattern.

## S1 — Default REDACTED_KEYS sufficiency (confidence 7/10)

The default list (from `meta.yaml`, mirrored across all 5 stacks) is:

```
["password","token","api_key","card_number","cvv","ssn","credit_card"]
```

Coverage assessment:

- **PII (high-sensitivity)**: ✓ `ssn`, `credit_card`, `card_number`, `cvv`.
- **Authentication tokens**: ✓ `token`, `api_key`, `password`.
- **Gaps**: no entries for `secret`, `private_key`, `client_secret`,
  `authorization`, `bearer`, `session`, `cookie`, `refresh_token`,
  `access_token`. These are common headers/field names in production
  payloads. Sentry's own default scrubber covers a broader set
  (`Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, etc.) so the
  field-level scrubber is layered on top of Sentry's transport-level
  scrubber.

**Verdict**: the default list catches the high-signal PII and the most
common token-shaped fields but is intentionally narrow — `policy.md`
is editable and the spec §10 contract puts the project owner in charge
of expanding it. Sentry's transport-level scrubber covers the headers
not in this list.

**Recommendation (INFORMATIONAL, not blocking)**: add `secret`,
`client_secret`, `refresh_token`, `access_token` to the default. These
are universal-enough across stacks that "redact by default" is the
defensible position. Cost: 4 entries in 7 fixtures + 5 templates.
Defer to a v0.3.2 or v0.4.0 minor of the skill — not load-bearing for
v1.11.0 ship.

## S2 — Anchor-comment injection bypass (confidence 9/10)

PLAN T16 asked: *"can attacker-contributed code inject anchor comments
to bypass detection?"*

The anchor pair (`// agenticapps:observability:start` / `:end`) serves
two roles:

1. **Idempotent re-detection** in Phase 2 of init re-runs (refuse to
   write a wrapper that already exists in anchored form).
2. **Block boundary** for Phase 6's CLAUDE.md update path.

**Attack vector**: a malicious contributor adds anchor comments around
unrelated code in `src/lib/observability/index.ts` (or in CLAUDE.md),
expecting init's re-run to treat the anchored region as
"already-initialised" and skip the real wrapper write.

**Impact assessment**:

- Wrapper-level (init Phase 2): if anchors are present in
  `<target.wrapper_path>`, init's strict-first-run refuses to proceed
  with code 1 and prints "already initialised". This is **fail-safe**:
  the worst the attacker achieves is denial-of-init, not silent
  conformance bypass. The user sees the message and investigates.
- CLAUDE.md-level (init Phase 6): if anchors are present in CLAUDE.md
  but the block content is wrong, init's Phase 6 self-check (the
  POLICY_PATH parser at line 1104-1107) will reject a missing or
  whitespace-quoted `policy:` value with exit 1. Migration 0011's
  pre-flight will also reject (`scan-apply` runs the same parser).
- **Scan-side**: `add-observability scan` walks files independently of
  anchor presence; anchors don't bypass scan's gap detection.

**Verdict**: the anchor pattern is structurally fail-safe. Anchor
injection is a denial-of-service vector against init's re-run path,
not a conformance-bypass vector. The fail-safe design (refuse to
proceed if anchors are present in unexpected places) is correct.

**Recommendation**: none required for v1.11.0. Document the
threat-model statement explicitly in `INIT.md` (one-paragraph
addition under "Important rules") so future maintainers don't relax
the fail-safe semantics under "improve UX of re-init" refactors.

## S3 — Symlink-based discovery CVE pattern (confidence 8/10)

PLAN T16 asked: *"symlink-following CVEs are a real pattern; should we
check for symlink-target tampering?"*

The new attack surface introduced by migration 0012:
`$HOME/.claude/skills/add-observability` is a symlink whose target the
migration controls during apply. Threats:

- **(T1) Symlink-time-of-check-to-time-of-use (TOCTOU)**: pre-flight
  reads the target via `readlink`, then Step 1 calls `ln -sfn` to
  overwrite. Between the two, an attacker with write access to
  `$HOME/.claude/skills/` could swap the target. But: this attack
  requires the attacker to already have write access to the user's
  `$HOME/.claude/`, in which case they can mutate any skill file
  directly without needing a TOCTOU race.
- **(T2) Symlink redirected post-install**: after migration 0012
  applies, a malicious actor (or accidental user action) could `ln
  -sfn /tmp/evil ~/.claude/skills/add-observability`. Subsequent
  invocations of `/add-observability` would load from the new target.
  Mitigation: the rollback path explicitly checks the symlink target
  before removing (`grep -q '/agenticapps-workflow/add-observability$'`)
  so a redirected symlink survives rollback. The user is responsible
  for verifying their own `$HOME/.claude/skills/` is clean.
- **(T3) Symlink to network filesystem / FUSE**: target could be a
  remote filesystem. Out of scope — same as any other file under
  `$HOME/.claude/skills/`.

**Verdict**: the threat model for symlink-based skill discovery is
**the same as the threat model for any file-system-installed Claude
Code skill**. Skills loaded from `$HOME/.claude/skills/` are trusted
code that runs in the user's session; if an attacker can write to
that directory, they don't need a symlink trick. Migration 0012
doesn't introduce a new vulnerability class — it inherits the
existing one.

**Recommendation**: none for v1.11.0. The threat boundary is
`$HOME/.claude/skills/` itself, not the symlink mechanism specifically.

## S4 — Cross-tree `applies_to` precedent (confidence 6/10)

Migration 0012's `applies_to` references `~/.claude/skills/add-observability`
— a path outside the project tree. This is novel; all prior migrations
operate inside the project. Future migrations might use this as a
precedent for "anything in $HOME is fair game."

**Risk**: a future migration could read or modify files outside
`$HOME/.claude/skills/` (config files, ssh keys, credentials) and the
framework would not refuse, because the `applies_to` field is
documentary only — there's no enforcement.

**Mitigation in place**: the inline NOTE in 0012's `applies_to`
explicitly flags this as a one-off precedent: *"This is novel for the
migrations framework — existing migrations reference project-relative
paths only. The cross-tree path is documented here so a future
maintainer doesn't take it as a precedent for arbitrary host-system
mutation."*

**Recommendation (INFORMATIONAL)**: consider adding a structural
enforcement at the migration-framework level (e.g., a `host_paths:`
explicit allow-list field that defaults to empty, or a runner-level
allowlist of approved cross-tree paths). Defer to a future migrations-
framework hardening phase; not blocking v1.11.0.

## Summary

**No CRITICAL security findings. 4 informational items:**

- **S1** — REDACTED_KEYS default could be expanded by 4 entries; not blocking.
- **S2** — Anchor-comment injection is structurally fail-safe; recommend documenting threat model in INIT.md.
- **S3** — Symlink discovery shares its trust boundary with the general $HOME/.claude/skills/ space; no new vulnerability.
- **S4** — Cross-tree `applies_to` precedent flagged inline; suggest future framework-level enforcement.

**Phase 15 ships clean from a security standpoint.** No threat
mitigations required before merge. All four items are improvement
suggestions deferrable to future minor versions.
