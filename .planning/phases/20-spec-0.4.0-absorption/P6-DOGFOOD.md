# P6.3 + P6.4 — Dogfood evidence

This file captures the dogfood run for migrations 0014 + 0015 +
the 0011 preflight fix-along, recording stdout for the commit
message and final PR description.

## Migration suite (canonical fixture-based dogfood)

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
  …
  ✓ 0011: test -f ~/.claude/skills/agenticapps-workflow/add-observability/scan/SCAN.md && grep -qE '^implements_spec: 0\.[3-9]\.[0-9]+$' ~/.claude/skills/agenticapps-workflow/add-observability/SKILL.md
  ✓ 0014: test -f $HOME/.claude/skills/agenticapps-workflow/templates/spec-mirrors/11-coding-discipline-0.4.0.md
  ✓ 0015: test -f $HOME/.claude/skills/agenticapps-workflow/ts-declare-first/SKILL.md
  Audit summary: PASS=19 FAIL=0 SKIP=4
  (counted in suite totals — strict mode: 0 audit FAIL to roll in.)

━━━ Summary ━━━
  PASS: 147
```

`FAIL=0` confirms green across the full migration suite under strict-preflight mode. The 0011 preflight rot fix (`^implements_spec: 0.3.0` literal → `^implements_spec: 0\.[3-9]\.[0-9]+$` extended-regex) is reflected in the strict audit line.

## Manual dogfood — Migration 0014 against a fresh /tmp project

Fresh fixture at `/tmp/dogfood-1.14.0-fixture/`:

- `CLAUDE.md` containing a stub `# Test Project` + one `## Existing Section`
- `.claude/skills/agentic-apps-workflow/SKILL.md` at `version: 1.12.0`, `implements_spec: 0.3.2`

### First run

```text
$ bash run-0014.sh
INFO: 0014 Step 1 — injected §11 block at @0.4.0 (before first ## heading).
INFO: 0014 Step 2 — bumped to 1.14.0 / implements_spec 0.4.0.
```

Post-apply state:

- `CLAUDE.md` line 5: `<!-- spec-source: agenticapps-workflow-core@0.4.0 §11 -->`
- `CLAUDE.md` lines 6-80: canonical §11 four-rule block (verbatim)
- `CLAUDE.md` line 82: `## Existing Section` (original content preserved)
- `.claude/skills/agentic-apps-workflow/SKILL.md`: `version: 1.14.0`, `implements_spec: 0.4.0`

### Second run (idempotency)

```text
$ bash run-0014.sh
INFO: 0014 Step 1 — already at @0.4.0; no change.
INFO: 0014 Step 2 — already at 1.14.0/0.4.0; no change.
```

### Byte-identity proof

```text
$ shasum -a 256 CLAUDE.md .claude/skills/agentic-apps-workflow/SKILL.md  # before second run
71ddfe8578b1388202823fee22b662262975952e1b37ca83fd6c388c93a88ad8  CLAUDE.md
47e433e589578feb5943f1211aa0c3941ee03b815d01e54e21332d539fbfd589  .claude/skills/agentic-apps-workflow/SKILL.md

$ shasum -a 256 CLAUDE.md .claude/skills/agentic-apps-workflow/SKILL.md  # after second run
71ddfe8578b1388202823fee22b662262975952e1b37ca83fd6c388c93a88ad8  CLAUDE.md
47e433e589578feb5943f1211aa0c3941ee03b815d01e54e21332d539fbfd589  .claude/skills/agentic-apps-workflow/SKILL.md
```

IDEMPOTENCY GATE: zero byte diff between first and second run.

## Migration 0015 — sandbox-only dogfood

0015's apply is `ln -sfn "$HOME/.claude/skills/agenticapps-workflow/ts-declare-first" "$HOME/.claude/skills/ts-declare-first"` — a user-global, environment-mutating operation. Running it live against the developer's `$HOME` would either be a no-op (if already applied) or modify the live skill directory. Authoritative idempotency dogfood is the 4 fixture cases under `migrations/test-fixtures/0015/` (sandboxed via fake_home + isolated `$HOME` env), all PASS in the suite above.

## Conclusion

P6.3 + P6.4 verification gate satisfied:

- Migration suite PASS=147 FAIL=0 (strict-preflight mode).
- Manual 0014 dogfood: first run applies cleanly with structural evidence; second run reports `no change` with byte-identical SHA-256 on both files.
- Migration 0015 idempotency covered by `02-already-installed` fixture.
- Preflight audit PASS=19 FAIL=0 SKIP=4 — including the 0011 rot fix.
