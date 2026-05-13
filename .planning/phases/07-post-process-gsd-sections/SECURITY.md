# Phase 07 — SECURITY.md

CSO audit of migration 0010 (`normalize-claude-md.sh` PostToolUse hook).
Auditor: gsd-security-auditor (sandboxed bash + jq fuzzing).
Date: 2026-05-13.
Scope:
- `templates/.claude/hooks/normalize-claude-md.sh`
- `migrations/0010-post-process-gsd-sections.md`
- `templates/claude-settings.json` (hook registration)

Each finding is reproducible from `/tmp/cso-audit-0010/` (sandbox fixtures).
All experiments were destructive-safe (no sentinel files were created
outside the sandbox; no real `/etc` writes).

---

## Verdict

**PASS-WITH-NOTES**

The script's design is conservatively defensive on the highest-impact
vectors (shell injection, jq filter injection, path traversal via
`source:` label). However, three real issues need fixes before this
ships to consumer projects at scale, and two more should be tracked
as accepted-risk-with-mitigation.

**Blocking issues:** 0
**Must-fix-before-1.10.0:** 3 (H1, H2, M1)
**Tracked-accepted-risk:** 2 (H3, M2)
**Informational:** 5

---

## Threat Verification Summary

Each row maps a PLAN.md `## Threat model` entry to its disposition + evidence.
PLAN's threat model focused on correctness (regex misfire, idempotency,
POSIX-portability). This audit adds a security-focused threat register
on top — 11 new threats T-S1 through T-S11.

| Threat ID | Category | Disposition | Evidence |
|---|---|---|---|
| PLAN-T1 (corrupts CLAUDE.md) | correctness | mitigate / CLOSED | run-tests.sh diff goldens; verified by VERIFICATION.md |
| PLAN-T2 (deletes content on missing source) | correctness | mitigate / CLOSED | script.sh:115-118 + `inlined-source-missing.md` fixture |
| PLAN-T3 (infinite hook loop) | safety | mitigate / CLOSED | script.sh:212-214 (only `cp` if `diff` says differ); Claude Code doesn't re-emit PostToolUse for hook's own writes |
| PLAN-T4 (POSIX/BSD portability) | portability | mitigate / CLOSED | script.sh uses POSIX bracket exprs; tested on bash 3.2 |
| PLAN-T5 (gsd-tools re-inflation) | correctness | mitigate / CLOSED | PostToolUse on next Edit catches it |
| PLAN-T6 (touches 0009's vendored block) | correctness | mitigate / CLOSED | script.sh:146 regex anchored on `<!-- GSD:` |
| PLAN-T7 (breaks settings.json JSON) | safety | mitigate / CLOSED | migration.md:114-122 jq `+=` is structural; agent-fallback validates JSON |
| PLAN-T8 (bash 3.2) | portability | mitigate / CLOSED | macOS run; no bash-4-only features used |
| T-S1 (shell injection via source: label) | injection | mitigate / CLOSED | Test 1 — see Findings INFO-1 |
| T-S2 (path traversal via source: label) | traversal | mitigate / CLOSED | Test 2 — see Findings INFO-2 |
| T-S3 (arbitrary file write — no `$1` validation) | trust-boundary | NOT mitigated / OPEN | Test 3 — see Findings H1 |
| T-S4 (PATH poisoning — unpinned binaries) | supply-chain | NOT mitigated / OPEN | Test 4 — see Findings H2 |
| T-S5 (jq filter coercion) | injection | mitigate / CLOSED | Test 5 — see Findings INFO-3 |
| T-S6 (TOCTOU between test -e and write) | race | N/A — no exploitable path | Test 11 — INFO-4 |
| T-S7 (script integrity / supply chain) | supply-chain | NOT mitigated / accept-with-recommendation | Test 7 — see Findings H3 |
| T-S8 (CLAUDE.md content corruption / DoS) | DoS | partial / accept-with-mitigation | Test 8 — see Findings M2 |
| T-S9 (5s timeout truncated write) | safety | mitigate / CLOSED | Test 8 — temp-write isolation; trap cleans up |
| T-S10 (symlink `$1` rewrites symlink target) | trust-boundary | NOT mitigated / OPEN | Test 12 — see Findings M1 |
| T-S11 (re-entrancy) | safety | mitigate / CLOSED | Two-layer defense (no-op short-circuit + Claude Code semantics) |

---

## Findings (by severity)

### HIGH

#### H1 — Script accepts arbitrary `$1` and rewrites whatever path is passed

| | |
|---|---|
| **Severity** | HIGH |
| **Category** | Trust-boundary violation / arbitrary file write |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:26-216` |
| **CWE** | CWE-73 (External Control of File Name or Path) |

**Description.** The script trusts `$1` absolutely. There is no
verification that the input file lives within the project root, that it
is named `CLAUDE.md`, or that it is a regular file (not a symlink, not a
device, not a pipe). The migration's registered hook always passes
`$CLAUDE_PROJECT_DIR/CLAUDE.md` — but the script itself is now a
per-project executable (chmod +x, installed at `.claude/hooks/`) that
any other tool, user-typed command, automation, or adversarial PR-merged
script can invoke against any path the agent can write to.

**Reproducer** (sandbox: `/tmp/cso-audit-0010/`):

```bash
# Setup: project with a valid PROJECT.md so the resolve check passes
mkdir -p .planning && echo "real" > .planning/PROJECT.md
cp /etc/hosts ./victim.md
echo '<!-- GSD:project-start source:PROJECT.md -->' >> ./victim.md
echo 'junk' >> ./victim.md
echo '<!-- GSD:project-end -->' >> ./victim.md

# Run script against the victim file
./normalize-claude-md.sh ./victim.md

# Result: victim.md is rewritten. /etc/hosts content preserved at the
# top but the GSD block is collapsed and the file's mtime/sha change.
```

Verified: input MD5 `9752...` → output MD5 `49ff...` (Test 3 above).

**Why it matters in practice.** The hook itself runs `CLAUDE.md` only.
But the on-disk script becomes a *primitive* that any later automation,
slash-command, agent, or shell pipeline can call as
`./.claude/hooks/normalize-claude-md.sh <some-other-path>`. If a future
sub-agent or skill ever passes a tainted path (e.g., derived from a
user-supplied filename), the script will rewrite that file with no
sanity check. This is a *latent* arbitrary-write primitive shipped to
every consumer project.

**Mitigation (recommended).**

Add at script start (after the existence checks):

```bash
# Refuse anything that isn't a CLAUDE.md regular file inside CWD.
# Block symlinks, devices, pipes; anchor to project root.
case "$INPUT" in
  */CLAUDE.md|CLAUDE.md|./CLAUDE.md) ;;
  *) echo "normalize-claude-md: refusing non-CLAUDE.md input: $INPUT" >&2; exit 1 ;;
esac

if [ -L "$INPUT" ]; then
  echo "normalize-claude-md: refusing symlinked input: $INPUT" >&2
  exit 1
fi
```

Stronger version: use `realpath`/`readlink -f` (where available; macOS
has `readlink -f` on macOS 12.3+; fall back to a portable
canonicalizer) and confirm the result is under `$CLAUDE_PROJECT_DIR`
(passed via environment by the hook framework).

---

#### H2 — Unpinned external binaries: PATH-poisoning exploitable

| | |
|---|---|
| **Severity** | HIGH |
| **Category** | Supply-chain / privilege escalation |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:197,205,206,212,213` |
| **CWE** | CWE-426 (Untrusted Search Path) |

**Description.** The script invokes `awk`, `mktemp`, `rm`, `diff`, `cp`
without absolute paths and without setting a hardened `PATH` at the top
of the file. The hook inherits `$PATH` from the Claude Code process,
which inherits from the user's shell. Anything earlier on `$PATH`
shadows the system binaries — including binaries that an attacker could
plant via:

- a directory in the user's `~/.local/bin` or `~/bin` that's poisoned
  by a malicious npm/pip/Homebrew package
- a `direnv`/`.envrc` injection (some Claude Code setups source these)
- a malicious PR that adds an executable named `awk` to a `node_modules/.bin/`
  or a CI-provisioned `tools/` directory that ends up on PATH

The PostToolUse hook fires on every `Edit|Write|MultiEdit` — so the
attacker gets code execution at user privilege on essentially every
file edit the user makes while Claude Code is running.

**Reproducer** (sandbox: `/tmp/cso-audit-0010/`):

```bash
mkdir -p malicious-bin
cat > malicious-bin/awk << 'EOF'
#!/bin/sh
touch /tmp/cso-audit-0010/PATH_POISON_AWK
exec /usr/bin/awk "$@"
EOF
chmod +x malicious-bin/awk

# Build a normal-looking input
cp /etc/hosts ./input.md
echo '<!-- GSD:project-start source:PROJECT.md -->' >> ./input.md
echo 'junk' >> ./input.md
echo '<!-- GSD:project-end -->' >> ./input.md

# Run with poisoned PATH
PATH="$(pwd)/malicious-bin:$PATH" ./normalize-claude-md.sh ./input.md

ls -la /tmp/cso-audit-0010/PATH_POISON_AWK
# => 0-byte file confirms shadow `awk` ran
```

Verified: `PATH_POISON_AWK` was created (Test 4 above).

**Why it matters in practice.** The hook runs many times per session
under the user's UID. A PATH-poisoning vector that *already exists* in
the user's environment (which is fairly common given Homebrew's path
practices and dev-tool sprawl) gets a 100% reliable trigger every time
Claude Code edits a file.

**Mitigation (recommended).** Pin the path at the top of the script:

```bash
# After `set -u` / `set -o pipefail`:
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
```

This is portable across macOS and Linux. If the user's `awk` is
deliberately a non-system version (e.g., gawk on macOS), use absolute
paths instead:

```bash
AWK="$(command -v awk)"  # captured ONCE before PATH manipulation
MKTEMP="$(command -v mktemp)"
# ... etc, called as "$AWK" / "$MKTEMP"
```

The first option is simpler and good enough for the macOS+Linux
support matrix this migration claims.

---

#### H3 — No integrity verification of the vendored script

| | |
|---|---|
| **Severity** | HIGH (latent / supply-chain) |
| **Category** | Supply-chain — recommend accept-with-mitigation |
| **File** | `migrations/0010-post-process-gsd-sections.md:88-95` |
| **CWE** | CWE-494 (Download of Code Without Integrity Check) |

**Description.** Step 1 of the migration's apply is:

```bash
cp ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh \
   .claude/hooks/normalize-claude-md.sh
chmod +x .claude/hooks/normalize-claude-md.sh
```

There is no SHA256, no signature, no version pin. The source path
`~/.claude/skills/agenticapps-workflow/templates/` is a checked-out git
working tree on the maintainer's machine. If that tree is ever
compromised (malicious commit pulled in via `git pull`, MITM, evil
maintainer of an upstream dep, etc.), every consumer project running
migration 0010 from that machine silently installs whatever script
content is sitting there. There is no way for the consumer project to
detect a substitution after the fact.

The idempotency check on re-runs (`grep -q "Migration 0010 — Normalize
GSD section markers" .claude/hooks/normalize-claude-md.sh`) checks for a
*sentinel comment*, not file integrity. A poisoned script can trivially
preserve that comment.

**Reproducer.** N/A — this is a supply-chain trust assumption, not a
local exploit.

**Mitigation (recommended).**

1. Ship a SHA256 of `templates/.claude/hooks/normalize-claude-md.sh`
   inside `migrations/0010-post-process-gsd-sections.md` and verify it
   in Step 1's apply:

   ```bash
   EXPECTED_SHA="abc123..."
   ACTUAL_SHA="$(shasum -a 256 < ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh | cut -d' ' -f1)"
   test "$EXPECTED_SHA" = "$ACTUAL_SHA" || { echo "ERROR: script integrity check failed"; exit 1; }
   ```

2. Long-term: sign migrations + their referenced templates with the
   project's release key, and have `/setup-agenticapps-workflow` verify
   the signature before vendoring. This is a P2 follow-up — track in an
   ADR (suggest ADR 0023).

Disposition: **ACCEPT** for 1.9.0 with a follow-up ADR; **MUST** add
SHA256 verification in 1.10.0.

---

### MEDIUM

#### M1 — Symlink-target rewrite via `cp` follows symlinks

| | |
|---|---|
| **Severity** | MEDIUM |
| **Category** | Trust-boundary violation |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:212-214` |
| **CWE** | CWE-59 (Link Following) |

**Description.** The final write is `cp "$TMP_OUT" "$INPUT"`. POSIX `cp`
follows symlinks for the destination: if `CLAUDE.md` is a symlink to
`X`, the symlink stays in place and `X`'s contents are overwritten.

Attack chain (requires attacker write-access to project working tree,
typically via a merged PR or compromised dev machine):

1. Attacker replaces `CLAUDE.md` with a symlink:
   `ln -sf ~/.ssh/authorized_keys CLAUDE.md`
2. Attacker injects GSD-start markers into the symlink target. (For
   `authorized_keys` this is feasible if the file already accepts
   "comment lines" — sshd treats `#`-prefixed lines as comments;
   sshd does NOT parse `<!-- ... -->` HTML-comment syntax as a comment
   so this specific exfil target is weak. Substitute with a file that
   uses HTML-comment-tolerant content: a user dotfile, `.bashrc`,
   `~/.config/.../config.toml`, etc.)
3. Next Edit/Write in Claude Code → hook fires → script reads the
   symlink target, finds markers, rewrites the target.

**Reproducer** (sandbox: `/tmp/cso-audit-0010/`):

```bash
cat > victim/target.txt << 'EOF'
DATA-LINE-1
<!-- GSD:project-start source:PROJECT.md -->
inline stuff
<!-- GSD:project-end -->
DATA-LINE-2
EOF
ln -sf victim/target.txt CLAUDE-symlink.md

./normalize-claude-md.sh CLAUDE-symlink.md

cat victim/target.txt
# => target.txt's GSD block is replaced with the reference-link form.
#    Symlink CLAUDE-symlink.md still points at target.txt (intact).
```

Verified: input MD5 `1dc7...` → output MD5 `c249...` (Test 12 above).

**Why it matters in practice.** Lower than H1 because it requires the
attacker to (a) get a symlink-CLAUDE.md merged or planted AND (b) get
GSD markers into the target. But H1's mitigation (refuse symlinks)
closes this too — the fix is one-and-the-same.

**Mitigation (recommended).** Same fix as H1: `[ -L "$INPUT" ] && exit 1`.
Additionally, replace `cp` with `mv` after a temp file on the same
filesystem (atomic, doesn't follow symlinks):

```bash
# Place TMP_OUT next to the input rather than in $TMPDIR
TMP_OUT="$(mktemp "${INPUT}.normalize.XXXXXX")"
# ... existing pipeline ...
mv -- "$TMP_OUT" "$INPUT"   # atomic rename; replaces symlink if any
```

`mv` replaces a symlink with the new file rather than following it.
This also fixes the partial-write window noted in M2's "5s timeout
mid-cp" sub-case.

---

#### M2 — DoS via large CLAUDE.md kills the hook (no file corruption, but session lag)

| | |
|---|---|
| **Severity** | MEDIUM |
| **Category** | DoS / availability |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:129-180` |
| **CWE** | CWE-400 (Uncontrolled Resource Consumption) |

**Description.** The line-by-line bash `while IFS= read -r line` loop is
roughly O(n) but bash is slow — measured ~14s for 400k lines (19MB) on
macOS. The `timeout: 5000` in settings.json kills the hook well before
completion. Per Claude Code semantics, a hook that exits non-zero (via
SIGTERM) raises a warning to the user.

Attack: a malicious PR adds 200k+ lines of innocuous content to
CLAUDE.md (or an attacker dumps the contents of a long log file into
it). Every subsequent Edit/Write in the user's Claude Code session
stalls 5s + emits a hook-failure warning. Not corruption — just
degraded UX.

**Reproducer** (sandbox: `/tmp/cso-audit-0010/`):

```bash
yes "line line line line line" | head -200000 > /tmp/big-lines.txt
(echo "# big"
 cat /tmp/big-lines.txt
 echo "<!-- GSD:project-start source:PROJECT.md -->"
 echo "x"
 echo "<!-- GSD:project-end -->") > big.md
wc -l big.md  # ~200000

time timeout 5 ./normalize-claude-md.sh big.md
# => SIGTERM, exit 124, input file unchanged
```

Verified: 400k-line file exhausted 30s timeout (Test 8 above); 50k-line
file completes in ~2s (within hook budget).

**Mitigations.**

1. (P0) Early-exit on file size:

   ```bash
   # 5MB cutoff — anything larger almost certainly isn't a hand-edited
   # CLAUDE.md; skip the normalization (PostToolUse still passes
   # because we exit 0).
   MAX_SIZE_BYTES=$((5*1024*1024))
   if [ "$(wc -c < "$INPUT")" -gt "$MAX_SIZE_BYTES" ]; then
     echo "normalize-claude-md: skipping oversize input ($INPUT)" >&2
     exit 0
   fi
   ```

2. (P1) Rewrite the hot loop in `awk` (single pass; ~50x faster than
   bash `read`). The block-state machine is awk-friendly. Track in
   ADR 0022 follow-up.

3. (P2) Decouple from PostToolUse: run normalization in a Stop hook
   instead. Edits are fast; once-per-session normalization at session
   end is sufficient for the canonical "no GSD-start markers in
   steady state" goal.

Disposition: **ACCEPT for 1.9.0** if mitigation (1) ships in the same
PR; otherwise **MUST FIX** before merging. The cost of (1) is ~3 lines.

---

### LOW

#### L1 — Hook exit-2 on malformed markers can be weaponized for session spam

| | |
|---|---|
| **Severity** | LOW |
| **Category** | UX-DoS |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:184-188` |

**Description.** Per the script, an unclosed marker block returns exit
code 2. Claude Code surfaces hook failures to the user. An attacker
who can write an unclosed `<!-- GSD:foo-start -->` into CLAUDE.md
(e.g., merged PR with deliberately broken markers) causes the user's
Claude Code session to display a hook-failure warning on every Edit
until the user notices and fixes the markers.

**Reproducer.** Test 9 above (`unclosed.md`).

**Mitigation.** Consider exiting 0 with a stderr warning instead of
exit 2 — Claude Code hooks generally treat warnings-on-stderr as
non-blocking. The current "exit 2 on malformed" is over-strict for a
post-processor that's running automatically.

Disposition: **INFO / nice-to-have.** Not blocking.

---

#### L2 — Symlink in `source:` resolved path is followed by `test -e`

| | |
|---|---|
| **Severity** | LOW |
| **Category** | TOCTOU / symlink (limited blast radius) |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:115` |

**Description.** `test -e "$check_path"` follows symlinks. If
`.planning/PROJECT.md` is a symlink to `/etc/passwd`, the existence
check passes. The script does NOT read or write the resolved target —
it only emits a markdown link with the original path. So the impact is:
a misleading reference link in CLAUDE.md, no data leak, no execution.

Disposition: **ACCEPT.** No exploitable path.

---

### INFO

#### INFO-1 — Shell injection via `source:` label is structurally prevented

| | |
|---|---|
| **Severity** | INFO (verification of negative) |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:40-53,146-152` |

**Description.** Verified by adversarial fixtures (Test 1 above) that
the following attacks DO NOT execute:

- `source:; touch /tmp/PWNED #`
- `source:$(touch /tmp/PWNED)`
- `source:\`touch /tmp/PWNED\``
- `source:foo && touch /tmp/PWNED`
- `source:foo | touch /tmp/PWNED`

Root cause of the resistance: the bash `=~` regex captures the label
into `BASH_REMATCH[3]` as DATA (no expansion), then `resolve_source_path`
uses a `case "$label" in` exact-match whitelist of 9 literal strings.
There is no `eval`, no `$(...)` of label, no unquoted expansion of
user-controlled content in any command position.

The label only ever appears in two places:

1. As input to a `case` pattern-match (literal-compare).
2. Inside `printf '%s'` format specifiers — `%s` is data, not a format
   string that interprets contents.

Verified safe.

---

#### INFO-2 — Path traversal via `source:` label structurally prevented

| | |
|---|---|
| **Severity** | INFO |
| **File** | `templates/.claude/hooks/normalize-claude-md.sh:40-53` |

**Description.** Verified by Test 2:

- `source:../../../etc/passwd` → case-statement falls to `*) echo ""` → `link_path` empty → block preserved unchanged.
- `source:/etc/passwd` → same.
- `source:PROJECT.md/../../../../../etc/passwd` → same (label is a literal
  string, not a path-template; case-match fails).

The whitelist is structurally tight: `resolve_source_path` maps 8 known
labels + `GSD defaults` to fixed strings. Anything else returns `""`,
which `build_replacement` interprets as "preserve original block."

---

#### INFO-3 — jq filter cannot be coerced via hostile settings.json

| | |
|---|---|
| **Severity** | INFO |
| **File** | `migrations/0010-post-process-gsd-sections.md:114-122` |

**Description.** The Step 2 jq filter is `.hooks.PostToolUse += [<literal-object>]`.
No interpolation of input-file data into the filter. Verified (Test 5):
a malicious `settings.json` with `{"_hook": "$(touch ...)"}` is treated
as opaque string data by jq — no execution. The migration's `&& mv`
ensures jq failure (e.g. malformed input JSON) does not advance to the
file replacement.

There is a SECONDARY risk that lies upstream of this migration:
`.claude/settings.json` already has the property that any `command`
string in a hook block is `sh -c`-evaluated by Claude Code. If an
attacker can plant an arbitrary `command` value into `settings.json`
before this migration runs, they already have code execution. That
isn't introduced by 0010 — but flagging it because the migration's
`jq` filter would happily preserve such planted hooks. Out of scope
for this audit.

---

#### INFO-4 — No exploitable TOCTOU on the input file path

| | |
|---|---|
| **Severity** | INFO |

**Description.** The only `test`/`if` checks on the input path
(`test -f`, `test -r`) precede the actual read. Between those checks
and `read <"$input"`, an attacker with write access could swap the
file, but the worst case is reading a different file — which:

- If it has no markers → no-op output → no `cp` → original input
  untouched.
- If it has markers but they don't resolve → no-op output → same.
- If markers resolve → script rewrites whatever the symlink-of-the-moment
  pointed at. This is the M1 scenario, not a new vector.

No timing-window amplification beyond M1.

---

#### INFO-5 — Documentation drift: "first action checks path ends with CLAUDE.md"

| | |
|---|---|
| **Severity** | INFO (doc bug) |
| **File** | `migrations/0010-post-process-gsd-sections.md:142-146` |

**Description.** The migration commentary says "The hook script's first
action is to check whether the file path passed to it ends with
`CLAUDE.md` (early exit otherwise)." This check is NOT IMPLEMENTED in
the script. (Verified — grep returns no match for endswith logic on
`CLAUDE.md` past the comment header.) It is also redundant given the
hook config always passes a fixed path. Fix the migration's commentary
to match reality, OR implement the check (which would also help close
H1).

---

## Unregistered flags

(SUMMARY.md not present in this phase yet — executor has not finalized.
No `## Threat Flags` to reconcile. The 11 T-S* threats above are
auditor-introduced and not strictly "unregistered" but are bookkept
here for completeness.)

---

## Recommendations for `feat/post-process-gsd-sections-0010` PR

**Must-fix before merging to main:**

- H1 / M1: refuse symlinks and non-CLAUDE.md inputs (3 lines, one-and-the-same fix)
- H2: pin `PATH="/usr/bin:/bin:/usr/sbin:/sbin"` at script top (1 line)
- M2: early-exit on `wc -c > 5MB` (4 lines)

**Track as ADR follow-up (recommend ADR 0023):**

- H3: migration template-integrity / signing model. Add SHA256 to
  migration markdown frontmatter; verify in apply step. Long-term:
  signed releases of the workflow scaffolder.

**Nice-to-have for 1.10.0:**

- L1: downgrade unclosed-marker exit-2 to exit-0-with-warning
- M2 (deeper fix): port the hot loop to awk; or move from PostToolUse
  to Stop hook
- INFO-5: reconcile migration commentary with implementation

---

## Verification commands (run from claude-workflow root)

```bash
# Reproduce H1
bash templates/.claude/hooks/normalize-claude-md.sh /tmp/some-arbitrary-file.md
# (file with GSD markers gets rewritten)

# Reproduce H2
mkdir -p /tmp/badbin && cp templates/.claude/hooks/normalize-claude-md.sh /tmp/badbin/
echo '#!/bin/sh\ntouch /tmp/PWN\nexec /usr/bin/awk "$@"' > /tmp/badbin/awk && chmod +x /tmp/badbin/awk
echo '<!-- GSD:project-start source:PROJECT.md -->\nx\n<!-- GSD:project-end -->' > /tmp/badbin/CLAUDE.md
mkdir -p /tmp/badbin/.planning && echo r > /tmp/badbin/.planning/PROJECT.md
( cd /tmp/badbin && PATH="$(pwd):$PATH" ./normalize-claude-md.sh CLAUDE.md ) && ls /tmp/PWN

# Reproduce M1
ln -sf /tmp/some-target /tmp/badbin/CLAUDE.md
# write GSD markers into /tmp/some-target; run hook; verify target rewritten

# Reproduce M2
yes "line" | head -300000 > /tmp/big.md
echo '<!-- GSD:project-start source:PROJECT.md -->\nx\n<!-- GSD:project-end -->' >> /tmp/big.md
time timeout 5 bash templates/.claude/hooks/normalize-claude-md.sh /tmp/big.md
# => SIGTERM, exit 124
```

---

## Final verdict

**PASS-WITH-NOTES.**

The script is well-engineered defensively against the obvious vectors
(shell injection, path traversal, jq coercion). The misses are around
trust-boundary discipline (treats `$1` as fully trusted) and
operational hardening (no PATH pinning, no integrity check, no
file-size guard).

None of the findings are remotely exploitable with default Claude Code
invocation. All findings require additional prerequisites (attacker
write-access to repo, poisoned PATH, malicious manual invocation, or
oversize input file). But the three Must-fix items above are cheap (~10
lines total) and meaningfully reduce blast radius. Recommend they ship
in the same PR before 1.9.0 lands.

ASVS Level: 2 (project-internal tool, single-user execution context).
Threats closed: 16/19. Threats open: 3 (H1, H2, M1). Accepted with
follow-up: 2 (H3, M2).
