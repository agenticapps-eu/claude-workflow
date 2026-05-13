# Phase 08 — Security Audit (CSO)

**Migration:** 0005-multi-ai-plan-review-enforcement (1.9.0 → 1.9.1)
**Branch:** `feat/phase-08-migration-0005-multi-ai-review`
**Diff base:** `origin/main`
**Auditor:** CSO-mode security review
**Date:** 2026-05-13

This audit verifies each of the 8 threats enumerated in `PLAN.md` Threat-model-STRIDE against the actual shipped code, and surfaces additional threats the model missed. Verdicts are based on direct command tracing of `templates/.claude/hooks/multi-ai-review-gate.sh`, `migrations/0005-multi-ai-plan-review-enforcement.md`, the 11 fixtures under `migrations/test-fixtures/0005/`, and `migrations/run-tests.sh` `test_migration_0005()`.

---

## Verdict

**PASS-WITH-NOTES**

All 8 PLAN.md threats are mitigated as claimed. The hostile-filename fixture (09) genuinely exercises the parsing branch — verified by `bash -x` trace. The harness assertion that `/tmp/HOSTILE_MARKER` survives the run is a real witness, not a paper assertion. However, the audit surfaced 4 additional threats not in the PLAN.md STRIDE table: one Medium (malformed-JSON failure mode), one Medium (curl supply chain in apply Step 1), one Low (FIFO hang on REVIEWS.md), and one Low (Verify-step smoke test can false-fail in an active-phase consumer). None are merge-blockers but two (T9, T10) deserve a follow-up patch.

---

## Critical findings (must fix before merge)

None.

---

## High findings (should fix before merge or document trade-off)

None.

---

## Medium / Low findings

### [M1] Malformed-JSON stdin causes hook to exit 5 (set-minus-e plus jq parse error) — not a block, but fails-open with no documentation

**Location:** `templates/.claude/hooks/multi-ai-review-gate.sh:23-27`

```bash
set -e
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
```

**Behavior:** If stdin is not valid JSON, `jq` writes a parse error to stderr and exits non-zero. `set -e` then aborts the script with exit code 5. Claude Code's PreToolUse contract treats exit 2 as BLOCK and anything-else-non-zero as "hook errored, but the operation is not blocked" (effectively fail-open).

**Reproduction:**

```
$ echo 'not json' | bash templates/.claude/hooks/multi-ai-review-gate.sh
jq: parse error: Invalid numeric literal at line 1, column 4
EXIT: 5
```

**Impact:** In practice Claude Code never sends garbage JSON, so the attack surface is internal (a misconfigured caller, a future API change, or a sibling hook upstream that pollutes stdin). PLAN.md threat 6 ("hook silently fails — bash 3 incompatibility") covers a related but distinct failure mode and is not a substitute.

**Recommendation:** Either (a) `jq -e` plus fall through to `exit 0` on parse error (fail-open-into-allow is consistent with the rest of the script's "when in doubt, don't block" posture), or (b) `INPUT=$(jq -c '. // empty' 2>/dev/null) || exit 0`. Document the fail-open choice in ADR 0018 if accepted.

---

### [M2] Migration Apply Step 1 fetches the hook script from main over HTTPS with no integrity verification

**Location:** `migrations/0005-multi-ai-plan-review-enforcement.md:53-55`

```bash
curl -fsSL https://raw.githubusercontent.com/agenticapps-eu/claude-workflow/main/templates/.claude/hooks/multi-ai-review-gate.sh \
  > .claude/hooks/multi-ai-review-gate.sh
```

**Impact:** Consumers who run the apply block as-is download whatever happens to be at HEAD-of-main at apply time. There is no pinned commit, no checksum, and no signature. If `agenticapps-eu/claude-workflow` is ever compromised, or DNS/TLS to GitHub is MITM'd by a sufficiently capable adversary, the consumer installs an attacker-controlled hook script with PreToolUse privileges over Edit/Write/MultiEdit (i.e. read plus modify file paths the IDE was about to touch). This is a supply-chain surface the PLAN.md threat model does not enumerate.

**Mitigating factors already present:**
- The fallback `cp <workflow-repo>/templates/...` line is offered as an alternative (line 57) and is the path the dogfood plus harness use.
- The migration's pre-flight requires `.claude/settings.json` to exist, narrowing the install window.

**Recommendation:** Pin the curl URL to a release tag (e.g. `/refs/tags/v1.9.1/...`) and ship a SHA-256 of the hook script alongside the migration markdown. Verify with `shasum -a 256 -c` after download. Defer to follow-up patch (1.9.2) if not done in this PR; PLAN.md scope reasonably treats consumer-side curl-fetch as out-of-band.

---

### [L1] REVIEWS.md as a FIFO (named pipe) with no writer causes hook to hang until Claude Code timeout

**Location:** `templates/.claude/hooks/multi-ai-review-gate.sh:77` and `:80`

```bash
if [ "$(wc -l < "$REVIEWS" | tr -d ' ')" -lt 5 ]; then
```

**Reproduction:**

```
$ mkfifo .planning/phases/01-real/01-REVIEWS.md
$ echo '{"tool_name":"Edit","tool_input":{"file_path":"src/x.go"}}' \
    | timeout 3 bash multi-ai-review-gate.sh
$ echo $?
124
```

**Impact:** An attacker who can write into `.planning/current-phase/` (already a high bar — they have project-write access) could plant a FIFO that hangs every Edit/Write/MultiEdit. Claude Code's default PreToolUse timeout (5s) would terminate it, fail-open. Worst case is a slow DoS, not a bypass.

**Recommendation:** Guard with `[ -f "$REVIEWS" ]` (not just `-z "$REVIEWS"`) before invoking `wc -l`. `-f` returns false on FIFOs, sockets, and block devices. One-line fix.

---

### [L2] Migration Verify Step smoke test can false-fail when applied inside an already-active phase

**Location:** `migrations/0005-multi-ai-plan-review-enforcement.md:100-102`

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.txt"}}' | bash .claude/hooks/multi-ai-review-gate.sh
test $? -eq 0 || exit 1
```

**Impact:** If a consumer runs the migration's Verify step from within a project that already has `.planning/current-phase` pointing at a phase with `*-PLAN.md` but no `*-REVIEWS.md` (e.g. they're applying the migration during an in-flight phase), the smoke test will exit 2 — which the migration interprets as "Migration 0005 did NOT apply successfully" and aborts. The hook is working correctly; the verify shell snippet's expectation is wrong.

**Recommendation:** Either (a) `GSD_SKIP_REVIEWS=1 echo ... | bash ...` to bypass any active phase state, or (b) `cd /tmp && echo ... | bash <repo>/.claude/hooks/multi-ai-review-gate.sh` to escape the consumer's `.planning/` context.

---

## Threats verified mitigated

### [T1] Filename injection via tool_input.file_path — MITIGATED (verified)

**Claim:** `jq -r` returns a literal string. `basename` and `case` operate on that string as text. No `eval`, no command substitution.

**Evidence:** `bash -x` trace of fixture 09 invocation (`migrations/test-fixtures/0005/09-hostile-filename-edit/`):

```
+ FILE='src/$(rm -rf /tmp/HOSTILE_MARKER).go'    [jq -r returns literal]
+ case "$(basename "$FILE")" in                  [case fired; literal not expanded]
++ basename 'src/$(rm -rf /tmp/HOSTILE_MARKER).go'  [basename invoked on literal]
+ readlink .planning/current-phase                 [phase resolution reached]
+ CURRENT_PHASE=.planning/phases/01-fake           [parsing branch entered]
+ find .planning/phases/01-fake -maxdepth 2 -name '*-PLAN.md'
+ echo 'X Multi-AI Plan Review Gate: blocked edit during execution'
+ exit 2
EXIT: 2
```

Harness asserts `/tmp/HOSTILE_MARKER` still exists post-run; harness passes; manual `ls -la /tmp/HOSTILE_MARKER` post-harness confirms file still present (0 bytes, untouched). The fixture **does** reach the parsing branch — `tool_name=Edit` survives the matcher check, `FILE` non-empty survives the guard, the planning-artifact `case` falls through (`.go` doesn't match any pattern), `readlink` resolves the symlink, `find` matches `01-PLAN.md`, and the block fires due to missing REVIEWS.md (NOT due to filename content). Codex's B4 concern is addressed.

**Verdict:** Threat closed. The harness assertion (`if [ "$fixname" = "09-hostile-filename-edit" ] && [ ! -f /tmp/HOSTILE_MARKER ]`) at `migrations/run-tests.sh:814` is correct — verified by manually `rm /tmp/HOSTILE_MARKER` before re-running, which surfaces the expected `command-substitution executed!` failure.

---

### [T2] Symlink race on .planning/current-phase — MITIGATED (worst-case bounded)

**Claim:** `readlink` then `find` is TOCTOU-racy, but worst case is stale read leading to false-positive block OR false-negative miss; self-healing on next invocation. No persistent damage.

**Evidence:** Hook reads `.planning/current-phase` via `readlink` (line 46), then re-uses `$CURRENT_PHASE` in subsequent `find` calls (lines 56, 60). If the symlink is swapped between these calls, behavior is well-defined: it operates on the pre-swap target. There is no privilege escalation, no information disclosure, and no persistent state. Race is observable only by an attacker who already has write access to `.planning/`.

**Verdict:** Threat closed. Worst-case impact (an over-block of one Edit operation) is acceptable.

---

### [T3] Override sentinel committed accidentally — MITIGATED (auditable)

**Claim:** `git log -- '*/multi-ai-review-skipped'` finds every commit that introduced the sentinel. ADR 0018 records the audit pattern.

**Evidence:** `docs/decisions/0018-multi-ai-plan-review-enforcement.md` documents the audit trail. The sentinel file path is `.planning/current-phase/multi-ai-review-skipped` (resolves through the symlink to a real directory); accidental commits land in git history under the phase directory path (e.g. `.planning/phases/08-.../multi-ai-review-skipped`), discoverable via `git log -- '**/multi-ai-review-skipped'`.

**Verdict:** Threat closed. Detection is one-shot grep on git history.

---

### [T4] PATH manipulation in pre-flight CLI count — MITIGATED (verified)

**Claim:** `command -v` reports presence; does not execute the binary.

**Evidence:** Direct test with a hostile `gemini` binary planted on PATH:

```
$ cat > $tmp/gemini <<EOF
#!/bin/sh
echo "HOSTILE binary executed" > /tmp/HOSTILE_PRECHECK
EOF
$ chmod +x $tmp/gemini
$ PATH=$tmp:$PATH bash -c 'command -v gemini >/dev/null 2>&1 && echo found'
found
$ ls /tmp/HOSTILE_PRECHECK
ls: /tmp/HOSTILE_PRECHECK: No such file or directory
```

`command -v` is a pure-shell-builtin name lookup; no `exec()` happens. Migration 0005's pre-flight at `migrations/0005-multi-ai-plan-review-enforcement.md:42-44` is the only call site.

**Verdict:** Threat closed.

---

### [T5] REVIEWS.md size DoS via wc-minus-l on huge file — MITIGATED (structural)

**Claim:** `wc -l` is streaming, constant memory. Claude Code's hook timeout (5s) bounds CPU.

**Evidence:** `wc -l < "$REVIEWS"` reads byte-stream and counts newlines without loading into memory. A 10GB plain file takes ~5-10s on modern SSDs; Claude Code's PreToolUse default timeout terminates over-long hooks (fail-open). No infinite-loop or memory-exhaustion path was found in the hook body. Latency benchmark `latency-bench.txt` confirms normal-size REVIEWS.md (a few KB) measures 30-50ms.

**Verdict:** Threat closed (in normal-case). See L1 above for the related FIFO edge case.

---

### [T6] Hook silently fails (bash 3.2 incompatibility) — MITIGATED

**Claim:** Hook targets bash 3.2+. macOS bash 3.2.57 is the proxy CI target.

**Evidence:** `VERIFICATION.md` AC-1 records `bash --version` output (`GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`). Hook ran 100x per fixture in the latency benchmark with zero errors on this host. The script uses only POSIX-compatible bash 3.2 features (no `[[ ]]` with `=~`, no `mapfile`, no `${var^^}`, no associative arrays). `set -e` is the only fragile primitive and behaves consistently across bash 3.2 to 5.

**Verdict:** Threat closed (caveat: bash 3.2 testing is manual, not CI-gated, as noted in PLAN.md "Risks accepted").

---

### [T7] Override env var leaks across sessions — MITIGATED (documented)

**Claim:** `GSD_SKIP_REVIEWS` is session-scoped by definition. Persistent export in `.envrc`/`~/.zshrc` is a user choice, not a hook flaw.

**Evidence:** Hook checks `[ "${GSD_SKIP_REVIEWS:-}" = "1" ]` (line 34). Only the exact string `1` opens the gate; any other value (including empty, "true", "yes", arbitrary garbage) leaves it closed. Stderr message references both override surfaces explicitly when blocking. Verified by hostile-env-value test: `GSD_SKIP_REVIEWS="x; rm -rf /tmp/HOSTILE_2"` still blocks (env value is compared as a literal, not evaluated).

**Verdict:** Threat closed.

---

### [T8] Hook prevents legitimate emergency hotfix — MITIGATED (multiple escape hatches)

**Claim:** Two override surfaces (env var plus sentinel) plus full rollback documented in migration 0005.

**Evidence:** Hook header comment (lines 15-19) advertises both overrides. Stderr block message (lines 62-72) also lists both. Migration 0005 Rollback block (lines 108-114) fully removes the hook plus JSON wiring plus reverts version. Total time-to-disable: one shell command per surface (`export`, `touch`, or full rollback). Documented in ADR 0018.

**Verdict:** Threat closed.

---

## Threats added (not in PLAN.md threat model)

### [T9] Curl supply chain on Apply Step 1 — NEW (see M2 above)

The PLAN.md STRIDE table covers reviewer-CLI trust ("Reviewer-CLI output trust") but does not enumerate the migration's own curl-fetch as a supply-chain surface. Fix is small (pin to tag plus sha256), impact is large (full hook code-execution context).

---

### [T10] Malformed-JSON fail-open via set-minus-e plus jq — NEW (see M1 above)

PLAN.md threat 6 covers bash 3.2 incompatibility but not the more general "any non-2 non-zero exit fails open" surface. Worth documenting in ADR 0018 as a deliberate trade-off ("fail-open on degenerate input is safer than fail-closed-into-block-everything").

---

### [T11] FIFO/socket REVIEWS.md hangs the hook — NEW (see L1 above)

The PLAN.md size-DoS threat addressed huge regular files but not non-regular file types. One-character fix (`-f` predicate before `wc -l`).

---

### [T12] Migration Verify smoke test false-fails on in-flight-phase consumer — NEW (see L2 above)

Process bug, not a security bug per se, but it teaches a consumer to disable the hook ("the migration doesn't work, let me skip it") which IS a security regression. Worth fixing as part of operational hardening.

---

## Notes / recommendations

1. **The dogfood evidence is genuine.** `dogfood-evidence.txt` captures the block-to-allow cycle with the actual phase artifacts. The Edit plus MultiEdit attempts both produce the expected exit codes and the stderr message body matches the hook source byte-for-byte. AC-9 is structurally proved, not just asserted.

2. **The harness assertion at `migrations/run-tests.sh:814` is correct.** Verified by manually deleting `/tmp/HOSTILE_MARKER` before running the harness — the fixture failed loudly with `X 09-hostile-filename-edit — /tmp/HOSTILE_MARKER was deleted (command-substitution executed!)`. The marker file is a real witness, not a paper assertion.

3. **Codex's earlier finding about fixture 09 short-circuiting is correctly addressed.** The pre-amendment fixture 09 used `tool_name=Bash` (which short-circuited at line 30 before reaching the parsing branch). Post-amendment fixture 09 uses `tool_name=Edit`, which makes it past the matcher; the `bash -x` trace above proves the parsing branch is entered. New fixture 10 (`non-edit-tool`) takes over the short-circuit-coverage role. This refactor is correct and complete.

4. **Recommended follow-up patch for v1.9.2:**
   - M1 fix: graceful jq parse-error handling.
   - M2 fix: pin curl URL to release tag plus add SHA-256 verification block.
   - L1 fix: `[ -f "$REVIEWS" ]` guard before `wc -l`.
   - L2 fix: rewrite Verify smoke test to escape active-phase state.

   These four fixes together are <20 LOC and one ADR amendment. None are merge-blockers for phase 08.

5. **The "Risks accepted" section in PLAN.md remains accurate** with one addition: the curl-fetch supply-chain risk (T9 above) should be added to that list explicitly if the M2 fix is deferred to v1.9.2.

6. **Threats not added, despite consideration:**
   - **`find` with `-maxdepth 2` and weird filenames** — verified inert via fixture 09 and a manual test with newlines in filenames.
   - **`basename` on attacker-controlled `$FILE`** — pure text, no shell exec.
   - **Hook executable bit clobbering by attacker** — same threat model as any `.claude/hooks/` file; out of this hook's scope.
   - **JSON injection via `tool_name` field** — only literal-string comparisons; no eval.

**Final verdict: PASS-WITH-NOTES.** The 8 documented threats are all genuinely mitigated. The 4 new threats (1 M, 1 M, 2 L) are real but small. None block merge. Recommend filing the four follow-up items as a 1.9.2 tracker before this PR lands so the next phase picks them up.
