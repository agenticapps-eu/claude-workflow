# Phase 10 — SECURITY (CSO audit)

**Phase:** 10-gitnexus-code-graph-integration
**Migration:** 0007 (1.9.2 → 1.9.3)
**Branch:** `feat/phase-10-migration-0007-gitnexus`
**Date:** 2026-05-13
**ASVS level:** L1 (developer workstation tooling; not handling secrets at rest)
**Scope reviewed:**
- `templates/.claude/scripts/install-gitnexus.sh`
- `templates/.claude/scripts/rollback-gitnexus.sh`
- `templates/.claude/scripts/index-family-repos.sh`
- `migrations/0007-gitnexus-code-graph-integration.md`
- 16 fixtures under `migrations/test-fixtures/0007/`
- `migrations/run-tests.sh` `test_migration_0007` stanza (L968-L1099)

---

## Verdict

**REQUEST-CHANGES.**

The phase verifies clean against 6 of 8 PLAN.md threats and the docs are clear about license + information-disclosure. **However: PLAN's `~/.claude.json` corruption threat (row 4) is still alive in code.** Phase 09's own CSO H1 lesson — "`&&` chains under `set -e` silently swallow non-zero from the LHS" — was carried into the `sed`/version-bump step (correctly) but NOT into the jq atomic-write step. Empirical repro below.

Two more new findings warrant gating:
- The "preserve pre-existing unexpected-shape entry" contract is silently violated when the existing `gitnexus` value is a JSON string/number/bool (not an object) — the script overwrites it without exit 4.
- The node-version pre-flight fails open on non-numeric `NODE_MAJOR` values (e.g. `abc`, `v18`).

Nothing in this review is exploitable by an external attacker. The risks are user-data integrity (silent corruption / silent overwrite / pre-flight bypass on weird node setups). Closing the H1 finding is mandatory; H2/H3 are nice-to-have but I'd rather see them fixed than carried.

| Severity | Open | Notes |
|---|---|---|
| Critical | 0 | — |
| **High** | **1** | H1 — `jq && mv` chain repeats Phase 09 H1 mistake (atomic-write fails silently on jq error) |
| **Medium** | **2** | M1 — unexpected non-object entry overwritten despite exit-4 contract; M2 — `NODE_MAJOR` accepts non-numeric and falls through |
| Low | 3 | L1 — `GITNEXUS_BIN` env-var bypass undocumented for users; L2 — orphan `.tmp` file not cleaned on failure; L3 — symlink-replacement on `~/.claude.json` not considered |
| Informational | 2 | I1 — MCP schema minimality (PASS); I2 — info-disclosure docs (PASS but improvable) |

---

## H1 — `&&`-chain atomic-write silently swallows jq failure (HIGH)

**Location:** `install-gitnexus.sh:99-100`, `rollback-gitnexus.sh:16-17`

```bash
# install-gitnexus.sh
jq '.mcpServers = (.mcpServers // {}) | .mcpServers.gitnexus = {"command":"gitnexus","args":["mcp"]}' \
  "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"

# rollback-gitnexus.sh
jq 'del(.mcpServers.gitnexus)' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" \
  && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
```

**The exact thing Phase 09 CSO H1 warned about.** Under `set -e`, when `cmd1 && cmd2` has a non-zero `cmd1`, bash treats the whole compound as having "tested" exit status (because of the `&&` operator) and does NOT abort the script. Empirical proof — running a minimal repro that forces the jq side to return non-zero:

```text
$ set -e
$ jq '.invalid|||filter' file.json > file.json.tmp && mv file.json.tmp file.json
jq: error: syntax error...
$ echo "still here, exit=$?"
still here, exit=1
$ ls -la file.json.tmp
-rw-r--r--  1 user  staff  0 ... file.json.tmp   ← orphan zero-byte file
```

**Consequence in install path:**
1. jq fails mid-pipeline (e.g. malformed input that snuck past `jq empty` pre-flight, disk full, OOM, signal). `$CLAUDE_JSON.tmp` is truncated to 0 bytes.
2. `&&` short-circuits, `mv` is skipped — so `~/.claude.json` itself is intact in this specific failure mode. **GOOD: the file is not corrupted.**
3. **BAD:** The script does NOT exit. It continues past Step 1 and runs Step 2 (version bump). The migration reports "Migration 0007 applied successfully." and exits 0. **User's SKILL.md is bumped to 1.9.3 but the MCP entry was never written.** Idempotency check on re-apply succeeds because version is now 1.9.3, so the user is stuck at "broken half-applied state, re-running won't help."
4. A zero-byte `~/.claude.json.tmp` is left on disk.

**Consequence in rollback path:**
1. jq fails. `~/.claude.json` is intact (good), but the version is then reverted to 1.9.2 anyway (because the rollback proceeds). User now has MCP entry pointing at gitnexus + SKILL.md at 1.9.2. Worse mismatch than install case because rollback printed "Migration 0007 rolled back" with exit 0.

The plan's "Mitigation: atomic write via `.tmp` + `mv`" row is structurally **half-correct**: it prevents partial-write of the destination file but NOT the orphan-tmp-with-silent-success failure mode that this idiom enables.

**Required fix** (matches Phase 09 H1 resolution pattern):

```bash
if jq '.mcpServers = (.mcpServers // {}) | .mcpServers.gitnexus = {"command":"gitnexus","args":["mcp"]}' \
     "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"; then
  mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
else
  rm -f "$CLAUDE_JSON.tmp"
  echo "ERROR: jq failed to write MCP entry to $CLAUDE_JSON" >&2
  exit 1
fi
```

Apply the same shape to `rollback-gitnexus.sh:16-17`.

**Why no fixture catches this:** All 16 fixtures stub `node` and `gitnexus`, and feed jq well-formed JSON that's been validated by the `jq empty` pre-flight. There is no fixture that arranges for the canonical write's jq invocation to fail. Adding one would require a destructive disk/quota harness — defer to inspection + the pattern fix.

---

## M1 — Non-object pre-existing entry is silently overwritten (MEDIUM)

**Location:** `install-gitnexus.sh:86-101`

**Claim** (migration body L77, PLAN.md threat row 3):

> "The script returns exit 4 if a pre-existing `mcpServers.gitnexus` entry has unexpected shape — applied successfully but the user should validate their MCP config manually."

**Reality:** The shape detection works only when `gitnexus` is itself a JSON object. If it's anything else (string / number / bool / array / null), jq's `// empty` masks the type error to stdout, `EXISTING_CMD` ends up empty, the `[ -n "$EXISTING_CMD" ]` branch is FALSE, and the script falls to the else branch which writes the canonical entry — **overwriting the user's non-object value silently with exit 0**.

Empirical:
```text
$ echo '{"mcpServers":{"gitnexus":"some-user-string"}}' > t.json
$ jq -r '.mcpServers.gitnexus.command // empty' t.json 2>/dev/null   # → ''
$ jq -r '.mcpServers.gitnexus.args[0] // empty' t.json 2>/dev/null   # → ''
# Then the script writes:
$ jq '.mcpServers.gitnexus = {"command":"gitnexus","args":["mcp"]}' t.json
{"mcpServers":{"gitnexus":{"command":"gitnexus","args":["mcp"]}}}   # ← overwritten
```

**Severity:** Medium because (a) non-object MCP entries are unusual but legal in user-edited JSON, (b) overwriting one violates the migration's stated preservation contract, (c) it's a silent integrity issue — no warning emitted.

**Fix:**

```bash
EXISTING_TYPE=$(jq -r '.mcpServers.gitnexus | type' "$CLAUDE_JSON" 2>/dev/null)
case "$EXISTING_TYPE" in
  null|"")  # absent — write canonical
    jq '.mcpServers = (.mcpServers // {}) | .mcpServers.gitnexus = ...' ...
    ;;
  object)
    # existing shape check (current code)
    ;;
  *)
    echo "warn: pre-existing gitnexus MCP entry is a $EXISTING_TYPE (not an object); preserving" >&2
    EXIT_CODE=4
    ;;
esac
```

---

## M2 — Pre-flight node-version check fails open on non-numeric input (MEDIUM)

**Location:** `install-gitnexus.sh:47-51`

```bash
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)
if [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
  echo "ERROR: node version too old (major=$NODE_MAJOR), need >= 18" >&2
  exit 1
fi
```

The `2>/dev/null` on the `[ ]` test suppresses the syntax error that arises when `NODE_MAJOR` isn't numeric. Empirical:

```text
NODE_MAJOR='abc'  →  passes (no exit)
NODE_MAJOR='v18'  →  passes
NODE_MAJOR='18 \nfoo'  →  passes (newline-tainted)
NODE_MAJOR='0'    →  exits (good)
NODE_MAJOR='17'   →  exits (good)
NODE_MAJOR=''     →  exits (good — empty is treated as 0 < 18)
```

**Attack scenario** (low-probability but real): a user has a custom `node` shim that prints a version string formatted differently from `process.versions.node`, OR a `node` alias to e.g. `deno` or `bun` that responds to `-p` with arbitrary output. The check fails open. The downstream gitnexus MCP server may or may not work depending on the actual JS runtime.

**Fix:**

```bash
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo "")
case "$NODE_MAJOR" in
  ''|*[!0-9]*)
    echo "ERROR: could not parse node major version (got '$NODE_MAJOR'); need >= 18" >&2
    exit 1
    ;;
esac
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "ERROR: node version too old (major=$NODE_MAJOR), need >= 18" >&2
  exit 1
fi
```

---

## L1 — `GITNEXUS_BIN` env-var bypass is undocumented in user-facing surface (LOW)

**Location:** `install-gitnexus.sh:17,53`, `index-family-repos.sh:14`

Both scripts honor `GITNEXUS_BIN="$path"` to override the `command -v gitnexus` lookup. This was added for test fixtures (which set it to a stub at `$HOME/bin/gitnexus`). The install script's header comment marks it as "for testing":

```bash
# Environment overrides (for testing):
#   ...
#   GITNEXUS_BIN          — gitnexus binary path (default: command -v gitnexus)
```

**Concern:** The helper script (`index-family-repos.sh`) honors the same env var with **no testing-only annotation**. If a user inherits a `GITNEXUS_BIN` from a parent process or sources a stale `.envrc`, the helper will execute whatever path that var points to — bypassing both the install script's existence check (the helper does its own check at L90-93 but trusts the env-pointed path implicitly) and the user's expectation that "`gitnexus` means `command -v gitnexus`".

**Severity:** Low because (a) the user would have to actively set `GITNEXUS_BIN`, (b) the executable bit check at L90 prevents pointing at a non-executable, (c) this is a workstation tool not a privileged path. But it's still an information-leak-style concern: helper-script-driven `gitnexus analyze` sends repo content to whatever binary the env var points at, which could be a different (e.g. tampered) gitnexus binary.

**Recommendation:** Either (a) remove `GITNEXUS_BIN` handling from `index-family-repos.sh` and rely only on `command -v gitnexus`, OR (b) add a startup warning when `GITNEXUS_BIN` is set:

```bash
if [ -n "${GITNEXUS_BIN:-}" ]; then
  echo "warn: GITNEXUS_BIN is set to '$GITNEXUS_BIN' — using override instead of PATH lookup" >&2
fi
```

This is a defense-in-depth improvement, not a functional fix.

---

## L2 — Orphan `.tmp` file is not cleaned up on jq failure (LOW)

**Location:** consequence of H1 (`install-gitnexus.sh:100`, `rollback-gitnexus.sh:16`)

When the `jq … > $CLAUDE_JSON.tmp` half of the chain fails, a zero-byte (or partial) `$CLAUDE_JSON.tmp` is left on disk. The next run will overwrite it, so this is purely cosmetic — but a future `ls ~/.claude.json*` will show the user a confusing leftover. The H1 fix (`if ... else rm -f $tmp; fi`) also resolves this.

---

## L3 — Symlink replacement on `~/.claude.json` not considered (LOW)

**Location:** `install-gitnexus.sh:100`, `rollback-gitnexus.sh:17`

If `$HOME/.claude.json` is a symlink to a system file (e.g. a user has set up `~/.claude.json -> ~/.config/claude/.claude.json` for dotfile management), the `mv $tmp $orig` pattern atomically replaces the symlink with a regular file. The target file is left untouched but the symlink is gone.

The wiki-compiler install script (`install-wiki-compiler.sh:62,72,119`) handles this scenario explicitly with `readlink` checks. The gitnexus scripts do not.

**Severity:** Low because (a) symlinked `~/.claude.json` is unusual, (b) jq's atomic-write idiom is the standard pattern accepted by most config tools, (c) the underlying target file is preserved (only the symlink is replaced). Document, don't gate.

**Recommendation:** Add a `readlink` check before the write:

```bash
if [ -L "$CLAUDE_JSON" ]; then
  CLAUDE_JSON_TARGET=$(readlink "$CLAUDE_JSON")
  echo "info: $CLAUDE_JSON is a symlink to $CLAUDE_JSON_TARGET; will write through symlink" >&2
  # If we want to preserve the symlink: write to the target directly.
fi
```

---

## I1 — MCP entry minimality: command + args only (INFORMATIONAL — PASS)

**Concern raised in review:** "Does the schema require other fields (`env`, `cwd`)? Could the bare entry break Claude Code's MCP loader?"

**Verdict:** The bare `{"command":"gitnexus","args":["mcp"]}` shape matches the documented `claude mcp add` CLI output and is the canonical stdio-server shape. `env` and `cwd` are optional in the Claude Code MCP loader spec. The 13-mcp-startup-smoke fixture explicitly invokes `$CMD $ARG` (i.e. `gitnexus mcp`) and asserts it runs to exit 0 via stub. Real-world breakage would surface immediately on first `claude mcp list`. PASS.

Note however: the smoke fixture is a stub roundtrip (`gitnexus` is a bash script that just exits 0). It does NOT verify Claude Code's MCP loader actually accepts the entry shape. That requires live integration testing, which is out of scope for the harness model. Documented limitation.

---

## I2 — Information disclosure via `gitnexus analyze` (INFORMATIONAL — adequate but improvable)

**Concern raised in review:** "Information disclosure via `gitnexus analyze` (sends repo content to LLM provider — does our docs make this clear enough?)"

**Disclosure points found:**
- `migrations/0007-...md:135` (Notes section): "**Information disclosure** — `gitnexus analyze` sends repository content to the LLM provider configured in gitnexus's settings. Users should verify that's acceptable for their codebase before invoking the helper." — clear and direct.
- `migrations/0007-...md:112`: "explicit warnings about LLM calls (repository content sent to the configured LLM provider)..."
- `index-family-repos.sh:36-38` usage block: "`gitnexus analyze` invokes a third-party LLM to build the code graph. Repository content is sent to the LLM provider configured in your gitnexus settings."

**Verdict:** Adequate. Clear language. The warning is in the default-no-args usage output, which is what 80% of users will see first.

**Suggested enhancement (not a blocker):** PLAN.md's threat row for info disclosure is captured in CONTEXT/RESEARCH but not in the live PLAN.md threat table (verified by grep — `Information disclosure` only appears in CONTEXT/REVIEW prose, not in the STRIDE matrix). Adding a row makes the audit trail complete:

```markdown
| Repo content sent to third-party LLM | **I** | `gitnexus analyze` (helper-script-only) | Helper-script usage block surfaces warning before any invocation; migration Notes explicit; user must pass flag (no default mass-index) | Helper usage output + migration Notes. |
```

---

## Threats verified mitigated (PLAN.md threat model)

| # | Threat | PLAN row | Status | Evidence |
|---|---|---|---|---|
| T1 | Supply chain via `npm install -g` | row 1 | **MITIGATED** | Pre-flight at L42-58 fails fast if `gitnexus` absent. Install command echoed at L56. Fixture `03-no-gitnexus/expected-stderr.txt` asserts presence. License note at L56-57. |
| T2 | `@latest` MCP command auto-loads compromised versions | row 2 | **MITIGATED** | Install writes `{"command":"gitnexus","args":["mcp"]}` — no `@latest` anywhere. Uses the global binary (codex B1 fix). Fixture 12 verifies command/args. Note: ironically this means the threat is mitigated by NOT pinning at all (no `npx -y gitnexus@X.Y.Z` — just runs whatever's globally installed). The supply-chain risk moves to whoever pinned the global install. |
| T3 | Existing MCP entry overwritten | row 3 | **PARTIALLY MITIGATED** | Canonical-shape detection at L86-95 works. Wrong-object-shape detection works (exit 4). Fixture 06 verifies preservation. **GAP: non-object pre-existing values silently overwritten — see M1.** |
| T4 | `~/.claude.json` corruption via partial write | row 4 | **NOT FULLY MITIGATED** | Atomic-write pattern present BUT the `&&`-chain idiom causes the script to continue past a failed jq invocation, producing half-applied state — see **H1**. The PLAN's claimed mitigation ("atomic write via .tmp + mv") is structurally incomplete: it prevents target-file corruption but not silent-half-success. |
| T5 | Malformed `~/.claude.json` swallows error | row 5 | **MITIGATED** | `jq empty "$CLAUDE_JSON"` pre-flight at L68-72 aborts with exit 1 on parse failure before any writes. Fixture 11 verifies stderr contains "is not valid JSON" and exit-1. |
| T6 | License non-compliance | row 6 | **MITIGATED** | Grep-verified in 4 places: migration Notes L132, ADR 0020 (referenced), CHANGELOG `### License` block, helper usage `⚠ LICENSE` block. |
| T7 | Bash 3.2 incompatibility | row 7 | **MITIGATED** | `bash -n` clean on all 3 scripts. No `[[ ]]` in `$()` substitutions, no `${var,,}`, no `$EPOCHREALTIME`. The `${SOURCECODE_ROOT:-...}` and `${WIKI_SKILL_MD:-...}` parameter expansions are POSIX. The bash array `DEFAULT_SET=(...)` in helper script requires bash 4+ syntactically — but bash 3.2.57 (macOS default) DOES support indexed arrays since bash 2.x. Re-verified. |
| T8 | Mass per-repo modification | row 8 | **MITIGATED** | Migration body grep'd — no `gitnexus analyze` in Apply section (only in Notes + helper-script docs). Helper script defaults to printing usage (fixture 08 verifies). |

---

## Threats added during audit (not in PLAN.md threat model)

| # | Threat | Severity | STRIDE | Source |
|---|---|---|---|---|
| N1 | `&&`-chain silent half-success in atomic write | High | T (Tampering — half-applied state) | Phase 09 H1 lesson incompletely applied — see H1 |
| N2 | Non-object pre-existing entry silently overwritten | Medium | I (Info disclosure of user customization) | See M1 |
| N3 | `NODE_MAJOR` non-numeric fail-open | Medium | D (Denial — but here, fail-open to broken state) | See M2 |
| N4 | `GITNEXUS_BIN` env-var bypass in helper | Low | T (Tampering — wrong binary executed) | See L1 |
| N5 | Symlink `~/.claude.json` replaced by atomic-mv | Low | I (Integrity of user's dotfile setup) | See L3 |

---

## Specific verifications performed

1. **`&&`-chain repro:** Ran a controlled set-e reproduction (`/tmp/jq_fail_repro.sh`) confirming jq failure short-circuits the chain without aborting the script. Exit code observed: outer 0 despite jq returning 1. Orphan `.tmp` file confirmed left on disk.
2. **Shape-validation completeness:** Tested `EXISTING_CMD=$(jq -r '.mcpServers.gitnexus.command // empty' ...)` against (a) `gitnexus` as string, (b) `gitnexus` as null, (c) `gitnexus` as object with bad shape. Case (a) returns empty (silent fallthrough). Case (b) returns empty (correct behavior — write canonical). Case (c) returns mismatched cmd (correctly triggers exit-4 branch).
3. **Node-version edge cases:** Tested `NODE_MAJOR` parsing against `0`, ``, `17`, `abc`, `v18`, `18\nfoo`. First three exit correctly; last three pass through.
4. **MCP schema:** Confirmed the bare `{"command":"gitnexus","args":["mcp"]}` shape is the documented stdio-server shape; `env`/`cwd` are optional. Smoke fixture 13 verifies stub roundtrip but not live loader.
5. **Info-disclosure surface:** Grep'd "LLM", "sent to", "provider" across migration body + helper. Three explicit warnings found at appropriate user-facing entry points.
6. **`GITNEXUS_BIN` usage:** Grep'd repo for the env var — found in 3 places (install header L17, install code L53, helper code L14). User-facing docs do not mention it; helper script does not gate on it.
7. **Fixture coverage:** Confirmed 16/16 PASS per VERIFICATION.md. Fixtures 01 (no-node) and 17 (no-jq) intentionally dropped — REVIEW.md FLAG-B documents harness limitation. Acceptable.
8. **Rollback symmetry:** rollback-gitnexus.sh checks `jq empty` before attempting delete (L14) — graceful no-op if the file is already invalid. Good. But carries the same H1 pattern at L16-17.

---

## Required actions before PR merge

- **MUST FIX (H1):** Replace `jq … > tmp && mv tmp orig` with explicit `if then mv else rm -f tmp; exit 1; fi` in both `install-gitnexus.sh:99-100` and `rollback-gitnexus.sh:16-17`. This is the same structural fix landed in Phase 09 CSO H1. **No new fixtures required** — the pattern is the contract.

## Recommended (not gating)

- **SHOULD FIX (M1):** Add type-check on pre-existing `.mcpServers.gitnexus` so non-object values trigger the exit-4 preserve branch instead of being overwritten.
- **SHOULD FIX (M2):** Validate `NODE_MAJOR` is purely numeric before the `-lt` comparison; fail closed.
- **NICE-TO-HAVE (L1):** Either remove `GITNEXUS_BIN` from `index-family-repos.sh` or emit a warning when set.
- **NICE-TO-HAVE (L3):** Add a `readlink` info-message when `~/.claude.json` is a symlink.
- **DOCS (I2):** Add the info-disclosure row to PLAN.md's STRIDE table so the audit trail is complete (already mentioned in CONTEXT/REVIEW but missing from the threat matrix).

---

## Lessons for future phases

1. **Phase 09 H1 is a load-bearing pattern.** The `&&`-chain idiom is the single most common shell-script anti-pattern in this codebase and it has now caused two phases (09, 10) of grief. Consider promoting "atomic-write via if/then/else" to a SKILL.md authoritative section or a lint rule in `migrations/run-tests.sh` that fails on the literal regex `jq.*> .*\.tmp\s*&&\s*mv`.
2. **Shape validation must consider primitive types, not just object-with-wrong-shape.** `// empty` is too lenient when the goal is "preserve unexpected." Use `jq '.field | type'` first.
3. **`2>/dev/null` on `[ ]` numeric tests fails open.** Validate input shape before comparing.
4. **The harness model cannot test "missing binary truly absent."** Documented in REVIEW.md FLAG-B — fine, but means certain pre-flight paths rely on inspection.

---

## Summary

The phase ships a thoughtful, well-scoped migration. The threat model is right-sized for what's actually shipped (verify-only install, helper-only mass-index, preserve-data rollback). License + info-disclosure surfaces are well-documented across 4 artifacts. 16/16 fixtures green.

**The gating issue is H1.** It's literally the same mistake the prior phase's CSO already caught, in the same shape, in scripts that even reference the H1 lesson in their comments (L21, L104). Fix the `&&`-chain pattern in both atomic-write paths and this phase is PASS-WITH-NOTES.
