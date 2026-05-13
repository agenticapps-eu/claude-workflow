# Phase 09 — Security Audit (CSO)

**Migration:** 0006-llm-wiki-builder-integration
**Version bump:** 1.9.1 → 1.9.2
**Branch:** `feat/phase-09-migration-0006-llm-wiki-builder`
**Diff base:** `origin/main`
**Date:** 2026-05-13
**Auditor:** CSO-mode review (Claude)
**Files audited:**
- `templates/.claude/scripts/install-wiki-compiler.sh` (186 lines)
- `templates/.claude/scripts/rollback-wiki-compiler.sh` (32 lines)
- `migrations/0006-llm-wiki-builder-integration.md`
- `migrations/test-fixtures/0006/*` (15 fixtures + README)
- `migrations/run-tests.sh` (`test_migration_0006` stanza, lines 853-969)

Harness baseline: **15/15 PASS** (re-run during audit).

---

## Verdict

**PASS-WITH-NOTES**

The threat model in PLAN.md is largely substantiated by the code. The locked B2 ABORT policy is correctly implemented (verified live). Threats 1, 3, 5, 6 are verifiably mitigated. Two threats (2 cross-family leak, 4 supply chain) are appropriately accepted/transferred. Threat 7 (version-bump partial state) is **partially mis-described** by PLAN.md — see H1.

No CRITICAL findings. One HIGH (silent partial-state success on Step 6 failure), one MEDIUM (JSON injection via adversarial family directory name), two LOW (case-sensitive skip-list, idempotency false-positive on code-fenced section heading) and a handful of advisory notes. None are blocking PR merge; recommend folding H1 and M1 into a fast-follow task or 1.9.3 micro-patch.

---

## Critical findings

None.

---

## High findings

### H1 — Step 6 (version bump) silently succeeds on sed failure

**File:** `templates/.claude/scripts/install-wiki-compiler.sh:181`

```bash
sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.2/' "$SKILL_MD" && rm -f "$SKILL_MD.bak"
```

The `&&`-chained form is a known `set -e` blind spot: bash treats a command in an `&&` list as "tested," so a non-zero exit from `sed` does NOT trigger script abort. The script proceeds to print *"Migration 0006 applied successfully"* and exits 0 even when `sed` printed `Permission denied` (or any other failure) to stderr.

**Reproduction (audited live in `/tmp/cso-09-sedfail`):**

```bash
chmod 555 $HOME/.claude/skills/agentic-apps-workflow   # make SKILL.md unwritable
bash install-wiki-compiler.sh
# stderr: "sed: …/SKILL.md: Permission denied"
# stdout: "Migration 0006 applied successfully (1 families processed)."
# exit:   0
# SKILL.md content: still "version: 1.9.1" (unchanged)
```

This contradicts PLAN.md's stated mitigation for **Threat 7 (version-bump partial state)**: *"Each step has its own idempotency check; re-applying is safe even after partial failure. The migration framework treats 'no version bump' as 'migration didn't apply' and retries the whole body next /update run."*

The observation that the framework can detect missing version bump via the SKILL.md grep is correct in theory, but the install script's own exit 0 misleads any direct caller (CI pipelines, ad-hoc operator runs, `setup-agenticapps-workflow`) into believing the apply succeeded. Stage 1/Stage 2 reviewers and CHANGELOG language all read "the migration is idempotent and reports failure on any step;" the code does NOT do that for Step 6.

**Recommended fix (post-merge, micro-patch 1.9.3):**

```bash
if grep -q '^version: 1.9.2$' "$SKILL_MD"; then
  :
else
  if ! sed -i.bak 's/^version: 1\.9\.1$/version: 1.9.2/' "$SKILL_MD"; then
    echo "ERROR: version bump failed at $SKILL_MD" >&2
    rm -f "$SKILL_MD.bak"
    exit 4
  fi
  rm -f "$SKILL_MD.bak"
fi
```

Same pattern applies to `rollback-wiki-compiler.sh:21` (identical `&&`-chain construct, identical bug — see L3 below; lumped under H1 because it's the same root cause).

**STRIDE:** Denial-of-state-consistency (D). **ASVS:** L1 V8.3 (error handling reveals consistent state).

---

## Medium findings

### M1 — JSON injection via family directory name with double-quote character

**File:** `templates/.claude/scripts/install-wiki-compiler.sh:118-143`

```bash
fam_name=$(basename "$fam")
fam_name_titlecase=$(echo "$fam_name" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
…
cat > "$config" <<EOF
{
  …
  "name": "$fam_name_titlecase Knowledge",
  …
}
EOF
```

The heredoc uses unquoted `<<EOF`, so `$fam_name_titlecase` is shell-interpolated into the JSON value without escaping. A family directory whose basename contains a literal `"`, `\`, control char, or newline produces invalid JSON.

**Reproduction (audited live in `/tmp/cso-09-inject2`):**

```bash
mkdir -p "$HOME/Sourcecode/foo\"x/repo/.git"
bash install-wiki-compiler.sh   # exits 0
cat "$HOME/Sourcecode/foo\"x/.wiki-compiler.json"
# → {"name": "Foo"x Knowledge", …}   ← invalid JSON
jq empty "$HOME/Sourcecode/foo\"x/.wiki-compiler.json"
# → parse error: Invalid numeric literal at line 3, column 17
```

**Impact:**
- Plugin compile-time will fail on this family (the `wiki-compile` command's `jq` parse aborts).
- The install script's *next* idempotent re-apply detects the file is present (line 122: `if [ -f "$config" ]`) and tries `jq empty "$config"` (line 123). On malformed input it now emits the F4 warning and preserves the broken file. So the family is permanently broken until the user manually fixes the config.
- Not a sandbox-escape or RCE: the JSON only flows to the plugin's compile step, which uses `jq` (no `eval`).
- Adversarial dirnames in `~/Sourcecode/` are uncommon but possible (cloning a repo whose name contains characters from a non-vetted source, or accidental shell-quoting mishaps when creating dirs).

**Recommended fix (post-merge, micro-patch 1.9.3):**

```bash
# JSON-escape via jq itself:
fam_name_json=$(printf '%s' "$fam_name_titlecase" | jq -Rs .)
# Then:
cat > "$config" <<EOF
{
  "version": 2,
  "name": $fam_name_json,
  …
}
EOF
```

Or, more conservatively, reject any family with non-portable basename characters during Step 2 (with a stderr warning).

**STRIDE:** Tampering (T) of generated config; mild Denial-of-Service against the wiki-compile step. **ASVS:** L1 V5.3.1 (output encoding by context).

---

## Low findings

### L1 — Skip-list is case-sensitive; capitalized variants get scaffolded

**File:** `templates/.claude/scripts/install-wiki-compiler.sh:75-77`

```bash
case "$(basename "$dir")" in
  personal|shared|archive|.*) return 1 ;;
esac
```

A user with `~/Sourcecode/Personal/`, `~/Sourcecode/Shared/`, or `~/Sourcecode/Archive/` (case-variant of the documented skip-list) gets that directory **scaffolded** with `.knowledge/` and `.wiki-compiler.json`, against the obvious intent. Audited live: `~/Sourcecode/Personal/{repo/.git}` was processed as a family.

**Impact:** Cosmetic / UX surprise. No security impact. Easy fix: lowercase the basename before matching, OR document the case-sensitivity in `migrations/0006-llm-wiki-builder-integration.md`.

**Recommended fix:**

```bash
case "$(basename "$dir" | tr '[:upper:]' '[:lower:]')" in
  personal|shared|archive|.*) return 1 ;;
esac
```

### L2 — Idempotency check false-positives on code-fenced section heading

**File:** `templates/.claude/scripts/install-wiki-compiler.sh:168`

```bash
if grep -q '^## Knowledge wiki' "$claudemd"; then
  : # already present
fi
```

A family `CLAUDE.md` that documents the marker syntax inside a code fence — e.g. a "here's what the section looks like" example — will start with `^## Knowledge wiki` and trip the idempotency check, **skipping the actual section append**. The user ends up with the example but no real section.

This was flagged by gemini's F2 in `09-REVIEWS.md` (case-sensitivity) and acknowledged as "low-impact, sticking with `grep -q '^## Knowledge wiki'`." The acknowledgment did NOT cover the in-fence case, which is the more common false-positive in practice.

Audited live in `/tmp/cso-09-codefence`: a CLAUDE.md containing a markdown code fence with `## Knowledge wiki` inside it caused the install to silently no-op the CLAUDE.md step. No section was added; no warning was emitted.

**Impact:** Functional discoverability. No security impact. Phase 07 (migration 0010 normalize-claude-md.sh) faced an analogous code-fence problem and fixed it with explicit fenced-block tracking; that pattern could be ported here if discoverability matters.

**Recommended action:** Document the constraint in `migrations/0006-llm-wiki-builder-integration.md` Notes section; defer code fix to a separate task if at all.

### L3 — Rollback `sed && rm` shares the H1 bug

**File:** `templates/.claude/scripts/rollback-wiki-compiler.sh:21`

```bash
sed -i.bak 's/^version: 1\.9\.2$/version: 1.9.1/' "$SKILL_MD" && rm -f "$SKILL_MD.bak"
```

Same `set -e` blind spot as H1. A rollback against a read-only SKILL.md prints "Migration 0006 rolled back" with exit 0, leaving version stuck at 1.9.2. Fold into H1's fix.

---

## Advisory notes (not findings)

### N1 — Idempotency on correct-target symlink stored in non-canonical form

**Behavior:** A user with a manually-installed symlink at `~/.claude/plugins/llm-wiki-compiler` pointing to the right physical location but stored in a different lexical form (relative path, trailing slash, `~`-literal, intermediate symlink chain) gets **ABORTed** by the locked B2 policy on re-apply.

Audited live: relative-path correct-target → exit 2; trailing-slash → exit 2; chained-symlink → exit 2.

This is **intentional** per codex B2 / RESEARCH §6A: ABORT on any mismatch, even if both resolve to the same dir, rather than risk silent repointing. Documented in `migrations/0006-llm-wiki-builder-integration.md:124`. Worth noting in the consumer-facing release notes for 1.9.2 that hand-installed symlinks should be removed before the first `/update`.

### N2 — `set -e` is the only strict-mode option

Neither script uses `set -u` or `set -o pipefail`. Side-effects:
- Undefined env vars silently default to empty (`WIKI_PLUGIN_SOURCE`, `WIKI_SOURCECODE`, `WIKI_SKILL_MD` all have safe defaults, but a future maintainer's typo could resolve to `/`).
- Pipe failures swallowed (e.g. `grep -E '^version:' "$SKILL_MD" 2>/dev/null | head -1 | sed … | tr …` at line 29 — if `grep` fails, `head/sed/tr` still produce empty and the trim-check sees `''`, which correctly fails the equality check, so this happens to be safe).

Switching to `set -euo pipefail` is a recommended hardening for the H1/L3 follow-up patch.

### N3 — `compgen -G` referenced in PLAN.md T5b but not in shipped code

PLAN.md line 151 names `compgen -G` as a smoke-test mechanism. **The shipped install script never calls `compgen`**, and `migrations/run-tests.sh` doesn't either. So the question of bash-3.2 portability for `compgen` is moot for the shipped artifact. (For the record: `compgen` is a bash builtin since 2.04 and works on macOS's stock 3.2; if it ever does ship in the install script, it's portable.)

### N4 — Vendored plugin's session hooks (Threat 5) are a documented trade-off

Once `~/.claude/plugins/llm-wiki-compiler` is in place, every Claude Code session on the host loads the plugin's hooks at `wiki-builder/plugin/hooks/`. The audit confirms this is documented as a known trade-off in ADR 0019 + migration body. ADR explicitly records the supply-chain trust assumption — equivalent to "you trust upstream `ussumant/llm-wiki-compiler` as much as you trust any community plugin." No new attack surface vs the current manual install.

### N5 — Rollback by design does NOT remove family-level data

The locked **preserve-data rollback** semantics mean `~/Sourcecode/*/.knowledge/`, `*/.wiki-compiler.json`, and `## Knowledge wiki` CLAUDE.md sections survive `rollback-wiki-compiler.sh`. This is correct per RESEARCH §3 and Threat 6 — the rollback Notes section gives explicit cleanup commands. Tested live via fixture 04.

### N6 — `.knowledge/.gitignore` is preserved, not clobbered

The user's question about "could that overwrite a user's existing .gitignore" is answered by line 105: `if [ ! -f "$knowledge/.gitignore" ]; then`. Verified live — a pre-existing `.gitignore` is preserved verbatim. Also note: the `.gitignore` is written *inside* `.knowledge/`, not at the family root, so it can't clobber a family-level `.gitignore` even if the existence check were buggy.

### N7 — Heredoc append to CLAUDE.md handles missing-trailing-newline correctly

Tested live: a CLAUDE.md ending mid-line (no `\n` at EOF) gets the section appended cleanly because `$KNOWLEDGE_SECTION` begins with a literal newline in the source. No risk of joining the last existing line to `## Knowledge wiki`.

### N8 — `find "$dir"/*/.git -maxdepth 1 -type d` does not follow symlink-`.git`

`-type d` matches only real directories. A repo using a symlinked `.git` (git worktrees, certain submodule configs) won't trip the family heuristic. Availability quirk, not security. Worth documenting in migration body if worktree users complain.

### N9 — Harness sandbox-escape guard (codex F1) verified

`migrations/run-tests.sh:879` greps the install script for hardcoded `/Users/donald` or `/home/$USER` and fails fast if found. Verified active and effective.

---

## Threats verified mitigated

| # | Threat | Disposition | Evidence |
|---|--------|-------------|----------|
| 1 | Symlink overwrites real file at `~/.claude/plugins/llm-wiki-compiler` | mitigate | `install-wiki-compiler.sh:46-49` ABORTs with exit 2 + clear stderr. Fixture 07 (`expected-exit: 2`, stderr "exists as a regular file") GREEN. |
| 2 | Cross-family `.wiki-compiler.json` leak via misconfigured `sources[*].path` | accept | PLAN.md threat model + ADR 0019 explicitly **accept** the risk: default config writes are family-rooted; user customizations are user-territory. Path validation deferred to plugin compile time. Documented in migration Notes. |
| 3 | Family CLAUDE.md collision via `## Knowledge wiki` heading | mitigate | `install-wiki-compiler.sh:168` `grep -q '^## Knowledge wiki'` idempotency check. Fixture 09 (`expected-exit: 0`, post-state grep count == 1) GREEN. *Caveat: see L2 for code-fence false-positive.* |
| 4 | Plugin supply chain (vendored copy compromised) | transfer | Documented in ADR 0019 as a known trade-off, equivalent to any community-plugin trust assumption. Recommended future hardening (tag + SHA-256 pin) tracked as a deferred follow-up. Same posture as Phase 08 CSO M2. |
| 5 | Vendored plugin contains hooks that fire at session start | transfer | Documented in ADR 0019 + migration Notes. User can audit `wiki-builder/plugin/hooks/` before symlinking. Same posture as any community plugin install. |
| 6 | Rollback leaves orphan files (preserve-data by design) | accept | Documented in migration body's Rollback section with explicit cleanup commands. Fixture 04 verifies preserve-data semantics live. |
| 7 | Version-bump partial state | mitigate | **PARTIALLY mitigated.** Step 6's idempotency check (`grep -q '^version: 1.9.2$'`) is correct; *but* the `&&`-chained `sed` does not propagate failure on errors (see H1). The framework-level retry IS a real backstop, but the install script does not itself report Step 6 failure to its caller. |

---

## Threats added (not in PLAN.md threat model)

### TX-1 — Adversarial family directory name corrupts generated JSON (M1)

Not anticipated by PLAN.md. Family-name interpolation into the heredoc is unescaped. Impact: malformed config + permanent broken-state for that family until manual fix.

**STRIDE:** Tampering. **Disposition:** Recommend mitigate via `jq -Rs .` JSON-escape in micro-patch.

### TX-2 — `set -e` insufficient for `&&`-chained idempotent ops (H1, L3)

Not anticipated by PLAN.md. The plan documented Threat 7 as covered by step-level idempotency + framework retry; the actual code defect is at the *exit-code* level — the script lies to its caller about success. Equivalent to a silent-failure CI bug.

**STRIDE:** Repudiation (R) / Denial-of-state-consistency (D). **Disposition:** Mitigate in micro-patch (explicit `if !` check around sed in both install + rollback).

### TX-3 — Case-sensitive skip-list (L1)

Not anticipated by PLAN.md. Doesn't change the threat model (still no info disclosure / no privilege escalation), but the documented skip-list contract drifts from the code contract.

**STRIDE:** None — UX/contract drift only. **Disposition:** Document or normalize to lowercase.

### TX-4 — Idempotency false-positive on code-fenced section heading (L2)

Not anticipated by PLAN.md. gemini's F2 noted case-sensitivity but not in-fence false-positives. Equivalent in shape to phase 07 BLOCK-2 (markers inside code fences).

**STRIDE:** None — functional discoverability only. **Disposition:** Document or port the phase 07 fence-tracking pattern.

---

## Summary table

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 0 | — |
| High | 1 | H1 |
| Medium | 1 | M1 |
| Low | 3 | L1, L2, L3 |
| Advisory | 9 | N1-N9 |
| Threats verified mitigated | 7/7 | (T7 partially — see H1) |
| Threats added | 4 | TX-1..TX-4 |

**Recommendation:** Ship 1.9.2 as planned. Open a follow-up issue / micro-patch (1.9.3) to land H1 + M1 fixes plus the recommended `set -euo pipefail` hardening across both scripts. None of the findings are exploit-grade; H1 is the only one with operational consequences (silent failure of version bump under permission-denied conditions).

The locked B2 ABORT policy works correctly. The harness's sandbox-escape guard (codex F1) is active. PLAN.md's threat-model dispositions are honest about what is accepted/transferred. The only meaningful gap is Threat 7's mitigation overclaim — easy to fix and not blocking.
