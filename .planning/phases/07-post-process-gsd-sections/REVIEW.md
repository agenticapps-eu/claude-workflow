# Phase 07 — REVIEW.md

## Stage 1 — Spec compliance (pr-review-toolkit:code-reviewer agent)

Scope: `git diff feat/vendor-claude-md-sections-0009..HEAD` (3 commits: RED
tests, GREEN script, packaging). Excludes unstaged changes in
`templates/config-hooks.json` and `docs/ENFORCEMENT-PLAN.md` (those are
ADR-0018 work, not phase 07).

### Method

1. Cross-checked every PLAN.md Step + CONTEXT.md Decision (A–G) against the diff.
2. Re-ran `bash migrations/run-tests.sh 0010` and the full harness — confirmed
   counts independently rather than trusting VERIFICATION.md.
3. Re-ran the end-to-end cparx simulation from VERIFICATION.md "End-to-end
   measurement" — confirmed 647 → 521 → 278 numerically.
4. Cross-checked ADR 0022's code-location citations against
   `/Users/donald/.claude/get-shit-done/bin/lib/profile-output.cjs`.
5. Verified rollback / idempotency-check correlation in the migration markdown
   against 0009's pattern.

### Verification of VERIFICATION.md claims

| Claim | Re-verified? | Notes |
|---|---|---|
| `bash migrations/run-tests.sh 0010` → 7 PASS | YES (re-ran) | Output matches VERIFICATION.md line 130–141 byte-for-byte. |
| Full harness → 57 PASS / 8 FAIL | YES (re-ran) | The 8 FAILs are all in `test_migration_0001` (`Step 1`–`Step 10` "needs apply on v1.2.0" checks). Pre-existing per session-handoff. Not introduced by 0010. |
| cparx end-to-end: 647 → 521 → 278 | YES (re-ran) | Reproduced exactly. `wc -l` output: 647 → sed-delete 154–285 + appended 6-line ref → 521 → script → 278. |
| `cparx-shape` fixture at 147L (≤ 200L) | YES (re-ran) | Fixture input 339L; script output 147L. |
| Bash 3.2 compatibility | YES (re-ran) | `/bin/bash --version` reports 3.2.57 on this macOS; harness PASSes under `/bin/bash`. |
| Hook 6 in `templates/claude-settings.json` parses cleanly | YES (visual + harness) | jq-shaped object, valid JSON. |
| ADR 0022 cites `buildSection` line 236 | YES | Matches `profile-output.cjs:236`. |
| ADR 0022 cites `extractSectionContent` line 226 | YES | Matches line 226. |
| ADR 0022 cites `hasMarkers` line 978 | YES | Matches line 978. |
| ADR 0022 cites `detectManualEdit` lines 257–262 + 980–991 | YES | Definition at 257; normalize logic at 260; auto-branch at 981–990. |
| ADR 0022 cites `--auto` at `cmdGenerateClaudeMd()` line 981 | PARTIAL | `cmdGenerateClaudeMd` is at line **911**, not 932. Line 981 is the `if (options.auto)` check inside that function. The 932 reference in CONTEXT.md/PLAN.md is `bin/gsd-tools.cjs` line 932 (the subcommand router), which is correct. ADR text reads as expected after careful parsing. |
| ADR 0022 cites `updateSection` "line 252" (overwrite-unconditional) | MINOR INACCURACY | Line 252 is inside `updateSection` (the `'replaced'` branch return). The call site that "runs regardless" is line 992 (and 995 for the append branch); the function definition is line 244. NIT-level. |
| ADR 0022 cites `updateSection` "appended" branch line 254 | YES | Line 254 is exactly `return { content: ..., action: 'appended' }`. |
| 0009 / 0010 boundary table | YES | All four shapes are correctly attributed. Verified by inspection of 0009's outputs (no `<!-- GSD: -->` markers) and 0010's regex `^<!--[[:space:]]*GSD:([a-z]+)-start` (cannot match plain markdown). |

### Plan → diff mapping (Steps 1–5)

| PLAN Step | CONTEXT Decision | Artifact in diff | Verdict |
|---|---|---|---|
| Step 1 — add post-processor script | Decision B + C | `templates/.claude/hooks/normalize-claude-md.sh` (216L, executable, sentinel header line 2) | DELIVERED |
| Step 2 — vendor into consumer projects | Decision C | Migration 0010 Step 1: `cp ~/.claude/skills/agenticapps-workflow/templates/.claude/hooks/normalize-claude-md.sh .claude/hooks/normalize-claude-md.sh`; chmod +x; rollback `rm -f` | DELIVERED |
| Step 3 — register hook in `claude-settings.json` | Decision C | Migration 0010 Step 2 (jq insert with hand-edit fallback) **AND** scaffolder-level edit to `templates/claude-settings.json` adding "Hook 6" PostToolUse block | DELIVERED |
| Step 4 — one-shot normalize existing CLAUDE.md | Decision D | Migration 0010 Step 3 with diff preview + A/B/C user prompt | DELIVERED |
| Step 5 — bump scaffolder version | (packaging) | `skill/SKILL.md` 1.8.0 → 1.9.0 (scaffolder side); migration's Step 4 bumps consumer's `.claude/skills/agentic-apps-workflow/SKILL.md` | DELIVERED |

### Decision A–G compliance

| Decision | Spec | Diff delivers | Verdict |
|---|---|---|---|
| A — source identification | upstream `gsd-tools` traced to `profile-output.cjs:236`, owned by `pi-agentic-apps-workflow` family | ADR 0022 Context section captures all findings with line numbers | DELIVERED |
| B — post-processor design | self-closing form + heading + reference link; source-existence safety; idempotent; scope-guard regex; special-case workflow + profile | Script `resolve_source_path()` lines 40–53 (mapping table); `build_replacement()` lines 74–124 (workflow/profile special cases at 80–99; mapping path at 102–123); regex anchor at line 146; `collapse_blank_runs` at 196–200 | DELIVERED |
| C — install point | `templates/.claude/hooks/normalize-claude-md.sh` + PostToolUse hook on `Edit\|Write\|MultiEdit` | Script at the spec'd path; Hook 6 in `templates/claude-settings.json:42-51` | DELIVERED |
| D — one-shot + ongoing | both | Migration Step 3 (one-shot with diff preview); Hook 6 (ongoing) | DELIVERED |
| E — interaction with 0009 | 0010 regex cannot match 0009's output (plain markdown, no `<!-- GSD: -->`) | Fixture `with-0009-vendored` exercises this; harness asserts diff against expected; PASS | DELIVERED |
| F — coverage matrix | target ≤200L on cparx; estimate ~250L | Empirical: 278L on real cparx; 147L on `cparx-shape` fixture. **Target missed by 78L on real cparx.** | PARTIAL — see Findings F-1 below |
| G — verification fixtures | 5 fixtures: `fresh`, `inlined-7-sections`, `inlined-source-missing`, `after-normalized` (idempotency), `cparx-shape` | Diff ships 5 fixture dirs: `fresh`, `inlined-7-sections`, `inlined-source-missing`, `with-0009-vendored` (substitutes for `after-normalized`), `cparx-shape`. Idempotency is tested as a separate scenario (re-running `inlined-7-sections`), not a standalone fixture dir. | DELIVERED with naming variation — see Finding NIT-2 |

### Findings

#### BLOCK

(none)

#### FLAG

**FLAG-1** | `templates/.claude/hooks/normalize-claude-md.sh:107-118` + `migrations/test-fixtures/0010/inlined-source-missing/CLAUDE.md:7` + `PLAN.md:21` | **Source-existence safety guard at lines 115–118 is untested.** The threat-model row "Script deletes content when source file is missing" claims coverage via `inlined-source-missing.md`. But that fixture uses `source:NONEXISTENT.md`, which has no entry in `resolve_source_path()`'s case statement — so it hits the **unmapped-label** branch at line 107–109 (empty `link_path` → `return 1` → preserve), not the **mapped-label-but-file-missing** branch at line 115–118 (which has a distinct stderr warning at line 116 that never fires). Both branches preserve, so the user-visible behavior is the same, but the safety guard the threat model points at is never exercised. Fix: add a fixture or assertion that uses e.g. `source:PROJECT.md` without staging `.planning/PROJECT.md`, and assert the stderr warning text. Alternative: rename the fixture to `inlined-source-unmapped` and add a separate `inlined-source-mapped-but-missing` fixture.

**FLAG-2** | `.planning/phases/07-post-process-gsd-sections/PLAN.md:149-157` (T2–T10 estimated commits) + actual git log | **Plan promised ~24 commits via TDD pairs; delivered 3.** PLAN.md Task breakdown lists 15 tasks expected to produce ~24 commits (mostly RED→GREEN pairs). The actual phase shipped as 3 commits: one RED (fixtures + harness), one GREEN (script), one packaging (migration + ADR + version). The single GREEN commit collapsed T3–T10. This isn't a correctness defect (the harness PASSes, all decisions are delivered), but the TDD discipline the plan committed to was not honored at the commit granularity. Reasonable trade-off to ship faster; should be acknowledged in VERIFICATION.md "Process notes" or similar. Not a BLOCK because the plan explicitly framed commit count as "estimated" (line 164), and the spec's behavior contracts are fully covered by the harness.

**FLAG-3** | `.planning/phases/07-post-process-gsd-sections/VERIFICATION.md:21` + AC-4 | **AC-4 claims "7 assertions (fewer than estimated; the 5 fixtures double up)"; PLAN.md AC-4 specified "~15 assertions".** This is a process gap, not a correctness gap — the 7 assertions do cover every Decision-B rule and every fixture in CONTEXT.md Decision G. But the AC-4 row "MET" should clarify that the assertion count was reduced from the original ~15 estimate, not just state "MET" with parenthetical. Suggest: rewrite AC-4 evidence to say "Reduced from ~15 estimated to 7 actual; each fixture is exercised by ≥1 assertion and all Decision-B rules are covered. See test_migration_0010() lines 410–533." or similar.

**FLAG-4** | `migrations/0010-post-process-gsd-sections.md:194-196` (Step 3 rollback) | **Step 3 rollback says "Restore CLAUDE.md from the working-tree snapshot taken at Step 3 entry" but doesn't specify how the runtime takes that snapshot.** 0009's Step 4 has the same hand-wavy "the migration runtime has not committed yet" wording (line 198 of `0009-vendor-claude-md-sections.md`), so 0010 is consistent — but neither migration is precise about the snapshot mechanism. For a project that runs `update-agenticapps-workflow` and gets a Step 3 abort partway through, the rollback path is non-mechanical. Suggest: either add a concrete `cp CLAUDE.md /tmp/0010-step3-snapshot.md` directive in the apply block, or explicitly cross-reference the migration-runtime contract that owns snapshot management.

**FLAG-5** | `.planning/phases/07-post-process-gsd-sections/VERIFICATION.md:24` (AC-7) + user prompt | **AC-7 missed by 78L on real cparx (278 vs target ≤200).** Empirically verified: re-ran the procedure and reproduced 278L. The gap is non-GSD content (gstack skill table, anti-patterns, repo-structure diagram, project notes — ~232L combined per VERIFICATION.md lines 99–104). This is shippable because (a) 0010 still delivers the largest single delta in the chain (47% reduction from post-0009 baseline; 57% from original 647L), (b) the remaining gap is content the user authored as project-canonical (not mechanical migration territory), and (c) the cparx-shape fixture lands at 147L proving the script can hit ≤200L when the input has only marker-block content. **Partial-credit shippable**, BUT the user's original prompt set the expectation of "646L → 0009 → ~496L → 0010 → ~165L" (auto green). Actual 278L is between the post-0009 baseline (521L) and the stretch target (~165L) — closer to the stretch goal than the baseline. CHANGELOG and ADR 0022 already capture this gap correctly. The trade-off: shipping a 47% reduction now vs blocking for follow-up Phase 08 (vendor gstack skill list) + Phase 09 (collapse repo-structure diagram) to chase the additional ~50–60L. **Recommendation: ship 0010 as PARTIAL on the coverage matrix; do not block.**

#### NIT

**NIT-1** | `docs/decisions/0022-post-process-gsd-section-markers.md:45` and `:176` | "overwritten unconditionally via `updateSection()` at line 252" — line 252 is inside `updateSection` (the `'replaced'` branch return statement). The function definition is at line 244; the call site that runs unconditionally without `--auto` is line 992. Cleaner: cite "line 992 (the unconditional call from `cmdGenerateClaudeMd`)" or "line 244 (the function definition)". Doesn't affect any decision; reader can still find the right code.

**NIT-2** | `.planning/phases/07-post-process-gsd-sections/CONTEXT.md:262-264` + `migrations/test-fixtures/0010/` | Decision G enumerated 5 fixtures including `after-normalized.md`. The diff ships `with-0009-vendored` instead, and tests idempotency by re-running the script against `inlined-7-sections` output (run-tests.sh:506–519). This is functionally equivalent — idempotency is verified — but the fixture-name divergence from the spec is worth a quick CONTEXT.md or VERIFICATION.md note. Suggest: amend Decision G's fixture list, or document in VERIFICATION.md that "`after-normalized` was implemented as an inline second-pass on `inlined-7-sections` rather than a standalone fixture".

**NIT-3** | `templates/.claude/hooks/normalize-claude-md.sh:1-22` (header) | Header comment doesn't mention that the script atomically rewrites only when output differs (lines 212–214). This is a documented behavior that matters for the PostToolUse loop-avoidance threat-model row. One-line addition: "Atomically rewrites the input only when output differs (avoids re-triggering PostToolUse on the script's own write)."

**NIT-4** | `migrations/0010-post-process-gsd-sections.md:131` | Step 2's jq-less fallback `echo "ERROR: jq not available; agent-driven edit required" >&2; exit 1` aborts the bash apply block. PLAN.md Step 3 described "both paths documented in the migration", which is true at the prose level but the executable apply block only implements one path. Acceptable as-is (migrations are markdown contracts read by the agent runtime), but a comment clarifying "Agent-driven hand-edit fallback is documented above; the executable path requires jq" would tighten this.

### Stage-1 verdict

**APPROVE-WITH-FLAGS**

The spec is honored. Every Step in PLAN.md and every Decision (A–G) in
CONTEXT.md has a corresponding, behaviorally-correct artifact in the diff.
The harness PASSes 7/7 for migration 0010 with no regressions in 0009 (the
8 0001 FAILs are pre-existing, documented, unrelated to this phase).
VERIFICATION.md's numerical claims are honest — re-running the procedure
reproduces 647 → 521 → 278 byte-for-byte and the harness output matches
exactly. The ADR's code-location citations are accurate (one minor line-
reference imprecision noted as NIT-1).

The AC-7 line-count miss (278L vs ≤200L target) is shippable as PARTIAL
because the remaining gap is non-GSD content explicitly out-of-scope for
0010, the chain still delivers a 57%-from-original reduction, and CHANGELOG
+ ADR-0022 + VERIFICATION.md all document the gap with empirical math and
a follow-up path. Recommend landing 0010 with FLAG-1 (untested
existence-guard branch) addressed before merge, and FLAG-2 through FLAG-5
acknowledged in CHANGELOG or VERIFICATION.md without blocking the ship.

## Stage 2 — Independent code review (pr-review-toolkit:silent-failure-hunter agent)

Independent attack pass on the committed artifact (`templates/.claude/hooks/normalize-claude-md.sh`, the migration prose, the test harness stanza). All findings reproduced empirically against the on-disk script as of 2026-05-13 13:52 local (post-CSO hardening — H1/H2/M1/M2 guards already merged). Stage-2 contract: zero trust, prove each claim or refute it.

### Findings — BLOCK

#### BLOCK-1 | `templates/.claude/hooks/normalize-claude-md.sh:242-248` | Silent data destruction on binary / NUL-byte input

**Description.** `normalize | collapse_blank_runs >TMP_OUT` returns exit 0 for a file whose first byte is NUL (or other binary content). The bash `while IFS= read -r line || [ -n "$line" ]` produces zero iterations (bash treats NUL as a line terminator/EOF on some libc paths; the leftover `$line` is empty so the `|| [ -n "$line" ]` fallback fails). `normalize` writes nothing, `collapse_blank_runs` produces an empty stream, `diff -q "$INPUT" "$TMP_OUT"` reports "differ," and `cp "$TMP_OUT" "$INPUT"` overwrites the original. Result: a 400-byte binary file → 0 bytes, exit 0. No warning. No error. No backup.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"
python3 -c "import sys; sys.stdout.buffer.write(b'\x00\x01\x02\xff' * 100)" > CLAUDE.md
"$SCRIPT" CLAUDE.md       # exit 0
wc -c CLAUDE.md           # 0 bytes — original 400 bytes destroyed
```

**Hidden errors.** Any non-text content reaching the hook is silently wiped. CLAUDE.md is supposed to be UTF-8 markdown, but the hook is wired into PostToolUse with no MIME/encoding check; a misconfiguration (e.g., user symlinks CLAUDE.md → image.png — already blocked by M1) or a user pasting a screenshot into the file via an external tool corrupts the file irrecoverably.

**Suggested fix.** Before the `cp` step, sanity-check: if the produced output is empty AND the input is non-empty, abort with exit code and stderr message. Belt-and-braces variant: file-magic check at the top (refuse non-UTF-8 input) — but the simpler invariant `[ -s "$TMP_OUT" ] || [ ! -s "$INPUT" ]` is sufficient.

```bash
# Right before `cp "$TMP_OUT" "$INPUT"`:
if [ ! -s "$TMP_OUT" ] && [ -s "$INPUT" ]; then
  echo "normalize-claude-md: refusing to truncate non-empty CLAUDE.md to empty output (likely binary input)" >&2
  exit 2
fi
```

---

#### BLOCK-2 | `templates/.claude/hooks/normalize-claude-md.sh:180` | Markers inside fenced code blocks are silently normalized, destroying documentation

**Description.** The marker-detection regex anchors on `^<!--` but has no awareness of fenced code blocks (` ``` ` or `~~~`). Any GSD marker shown inside a fenced markdown code block — e.g., a project document explaining how the hook works — has its `<!-- GSD:project-start ... -->` … `<!-- GSD:project-end -->` example replaced with the live reference link, ruining the documentation.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
cat > CLAUDE.md <<'EOF'
# header
```markdown
<!-- GSD:project-start source:PROJECT.md -->
## Project
example body
<!-- GSD:project-end -->
```
EOF
"$SCRIPT" CLAUDE.md
cat CLAUDE.md   # The example inside the fenced block has been rewritten in place.
```

**Hidden errors.** Migrations 0011+, README sections, or developer notes that show inline GSD-marker examples will be destroyed on every CLAUDE.md write. ADR 0022 acknowledges this risk and claims "line-leading anchor (`^<!--`) keeps embedded markers within code blocks safe most of the time" — that claim is false (fenced code-block content is line-leading too).

**Suggested fix.** Add a fenced-code-block state-machine: track `^(\`\`\`|~~~)` toggles and skip marker detection when `in_fence=1`. ~10 lines of additional bash.

```awk
# pseudo-code in awk; same logic applies in the bash read-loop:
/^[\`]{3}|^~{3}/ { in_fence = !in_fence }
in_fence { print; next }
# … existing logic …
```

Alternatively: bracket marker detection on a sentinel like `^<!-- GSD:[a-z]+-(start|end)` *and* require the preceding non-blank line to NOT start with a fence delimiter. Either approach is fine; the absence of any guard is the bug.

---

#### BLOCK-3 | `templates/.claude/hooks/normalize-claude-md.sh:170,232` | CRLF line endings silently bypass normalization

**Description.** `read -r` on Linux/macOS bash keeps trailing `\r` as part of the line. The regex `^\<!--…--\>$` does NOT allow `\r` between `-->` and `$`, so CRLF-encoded CLAUDE.md files have every marker line silently skipped — markers pass through verbatim, no warning. Worse, `collapse_blank_runs`' awk pattern `/^[[:space:]]*$/` matches lines containing only `\r` (POSIX `[:space:]` includes CR), so the blank-line collapser DOES fire on those files — partially mutating content while leaving markers untouched.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
printf '<!-- GSD:project-start source:PROJECT.md -->\r\n## Project\r\nbody\r\n<!-- GSD:project-end -->\r\n' > CLAUDE.md
"$SCRIPT" CLAUDE.md            # exit 0
grep -c 'GSD:project-start' CLAUDE.md   # 1 — marker NOT normalized
```

**Hidden errors.** A Windows-edited CLAUDE.md (or one round-tripped through a tool that writes CRLF) silently fails to normalize. The user sees inflated CLAUDE.md, can't figure out why the hook isn't doing its job, and there's nothing in stderr to diagnose. Worse, the partial blank-line collapse means the file IS being touched on every Edit/Write — a hidden mutation with no benefit.

**Suggested fix.** Strip `\r` at line read time:

```bash
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"   # tolerate CRLF
  # … existing logic …
done
```

Optionally detect CRLF up-front and emit a one-shot stderr "this file has CRLF; normalizing line endings to LF as part of post-processing" — but that's behavior expansion; the minimal correctness fix is the strip.

---

#### BLOCK-4 | `templates/.claude/hooks/normalize-claude-md.sh:242-248` | `cp` is non-atomic; concurrent invocations corrupt CLAUDE.md

**Description.** `cp "$TMP_OUT" "$INPUT"` is NOT an atomic file replacement. When two PostToolUse fires race (possible during MultiEdit-then-Edit chains, or two concurrent Claude sessions in the same project tree, or a user-driven hot reload that triggers two writes within ms), one process's `cp` can write the same destination while another process's `normalize | collapse_blank_runs` pipeline is reading it via `<"$INPUT"`. The second process then produces a malformed output and writes that back.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
# Create a CLAUDE.md with 50 markers (long enough that processing overlaps)
{ echo header; for i in $(seq 1 50); do
    printf '<!-- GSD:project-start source:PROJECT.md -->\n## Project iter %s\nA\nB\n<!-- GSD:project-end -->\n\n' "$i"
  done; } > CLAUDE.md
for i in $(seq 1 20); do "$SCRIPT" CLAUDE.md & done; wait
# Observed: partial lines, "unclosed marker block for slug=project" on stderr,
# trailing garbage like "PROJECT.md /-->" appearing mid-file.
```

**Hidden errors.** File corruption with no error reporting. The script even silently emits "unclosed marker block" to stderr from one racing process while another succeeds — but the corrupt output stays committed because the LAST `cp` wins, and there's no fsync/checksum/locking.

**Suggested fix.** Use `mv` + temp-in-same-dir for atomic rename within a filesystem, plus a `flock` advisory lock:

```bash
LOCK="$INPUT.lock"
exec 9>"$LOCK"
flock -n 9 || { echo "normalize-claude-md: another instance is running, skipping" >&2; exit 0; }
TMP_OUT="$(mktemp "${INPUT}.normalize.XXXXXX")"
trap 'rm -f "$TMP_OUT" "$LOCK"' EXIT
# … pipeline …
mv "$TMP_OUT" "$INPUT"   # atomic on same FS
```

`flock` is not POSIX, but it IS available on macOS (via `brew install util-linux`) and is shipped by default on every Linux distribution. Cheaper alternative for POSIX-only environments: an open-with-O_EXCL sentinel + skip-if-already-running pattern. The current "no protection at all" stance is not defensible for a hook that fires on every Edit/Write.

---

#### BLOCK-5 | `templates/.claude/hooks/normalize-claude-md.sh:163-214` | Custom user-authored GSD blocks with canonical source labels are silently replaced with reference links

**Description.** The script normalizes any `<!-- GSD:{slug}-start source:{label} --> … <!-- GSD:{slug}-end -->` block where `resolve_source_path "$label"` returns a non-empty path AND that path exists — irrespective of whether `{slug}` is one of the seven canonical GSD-managed slugs. A user who has written a custom slug `<!-- GSD:wibble-start source:PROJECT.md -->\nMy hand-written prose\n<!-- GSD:wibble-end -->` will have their hand-written prose silently replaced with `## wibble\nSee [.planning/PROJECT.md](./.planning/PROJECT.md) — auto-synced.` on the next Edit/Write of CLAUDE.md.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
cat > CLAUDE.md <<'EOF'
<!-- GSD:wibble-start source:PROJECT.md -->
## My custom section
custom content
that should be preserved
<!-- GSD:wibble-end -->
EOF
"$SCRIPT" CLAUDE.md
cat CLAUDE.md   # Original 4 lines of custom prose replaced with 3-line reference stub.
```

**Hidden errors.** Documentation loss with no undo. ADR 0022 ("Bad / risks") flags the upstream-fight risk but does NOT warn about user-content destruction for non-canonical slugs. The "source-existence safety" guard claims to preserve information by default, but it only protects against missing source files — not against the slug-is-custom case.

**Suggested fix.** Restrict normalization to the canonical slug allowlist (`project|stack|conventions|architecture|skills|workflow|profile`); for any other slug, emit a stderr warning and preserve the block byte-for-byte. The existing `case` in `heading_for_slug` already enumerates the canonical set — reuse it:

```bash
case "$slug" in
  project|stack|conventions|architecture|skills|workflow|profile) ;;
  *)
    echo "normalize-claude-md: refusing to normalize non-canonical slug '$slug'; preserving block" >&2
    return 1
    ;;
esac
```

Place this at the top of `build_replacement` immediately after the function header.

---

#### BLOCK-6 | `templates/.claude/hooks/normalize-claude-md.sh:163-214` | Nested or malformed marker blocks silently destroy content

**Description.** When `<!-- GSD:project-start ... -->` opens a block and a SECOND `-start` marker for a different slug appears before the first block's `-end`, the inner `-start` is silently consumed as block content. When the outer `-end` arrives, the entire region (including the inner content) is replaced by the normalized reference for the outer slug. The inner marker block disappears with no warning.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
cat > CLAUDE.md <<'EOF'
<!-- GSD:project-start source:PROJECT.md -->
## Project
<!-- GSD:stack-start source:CONVENTIONS.md -->
inner content that gets nuked
<!-- GSD:project-end -->
trailing
EOF
"$SCRIPT" CLAUDE.md
cat CLAUDE.md   # The entire region from stack-start onward is gone.
```

**Hidden errors.** Malformed markdown (e.g., gsd-tools wrote a half-block before a tool crash) silently truncates user content. The user sees data loss but has no diagnostic in stderr.

**Suggested fix.** When `in_block=1` and a new `-start` marker is detected, exit with code 2 and a clear message: "nested or unclosed marker block: encountered `<slug>-start` while inside `<slug>-start` block." Mirror the existing unclosed-block handler in `normalize()` at line 218-222.

---

### Findings — FLAG

#### FLAG-A | `templates/.claude/hooks/normalize-claude-md.sh:170,191` | Always-on collapse + missing-trailing-newline add silently mutates content unrelated to GSD markers

**Description.** Even when CLAUDE.md has zero GSD markers, the script runs `collapse_blank_runs` on the output AND the read-loop adds a trailing `\n` to files that lack one. This means *every PostToolUse fire on CLAUDE.md* potentially mutates a file unrelated to any GSD content — collapsing leading/trailing blank lines, normalizing line endings, adding final newlines. The hook's stated purpose ("normalize GSD section markers") doesn't match its actual behavior ("normalize everything about CLAUDE.md whitespace").

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"
printf '\n\n\n# header\ntext\n' > CLAUDE.md   # 3 leading blank lines, no markers
"$SCRIPT" CLAUDE.md
cat -A CLAUDE.md    # 3 blank lines → 1 blank line; mutated despite no markers
```

**Suggested fix.** Either (a) skip the `cp` write when no markers were found in the input (track a `markers_found` flag in `normalize()`), or (b) document the broader "whitespace tidier" scope in the script header and ADR 0022. Currently the behavior exceeds the documented contract.

---

#### FLAG-B | `migrations/0010-post-process-gsd-sections.md:142-146` | Migration prose lies about an "early exit if not CLAUDE.md" check

**Description.** Step 2's prose states: *"The hook script's first action is to check whether the file path passed to it ends with `CLAUDE.md` (early exit otherwise). PostToolUse fires on every Edit/Write — without the early exit the 5ms cost would multiply."* This was true of a contemplated design; the actual script has a `basename ... != CLAUDE.md` REFUSAL (exits with code 1, not 0). The hook command in `claude-settings.json` hard-codes the argument to `$CLAUDE_PROJECT_DIR/CLAUDE.md`, so the script always processes CLAUDE.md regardless of which file was just edited.

**Hidden cost.** Every Edit/Write of ANY file in the project triggers a full read/regex/awk/diff cycle on CLAUDE.md. For a 200L CLAUDE.md, this is sub-50ms. For a hypothetical 5MiB file (just under the DoS guard), this is non-trivial. The "early exit" the prose promises does not exist.

**Suggested fix.** Either:
1. **Implement the optimization.** Read `$CLAUDE_TOOL_INPUT` (or whatever Claude Code's PostToolUse passes in stdin/env) and early-exit if the edited file's basename isn't CLAUDE.md. Per https://docs.claude.com/en/docs/claude-code/hooks the tool_input is available on stdin as JSON; parse `.tool_input.file_path` with `jq` or grep, and short-circuit.
2. **Fix the documentation.** Update migration 0010 step 2 prose to accurately describe the current behavior (always-runs, relying on `diff -q` to short-circuit the `cp`).

---

#### FLAG-C | `migrations/0010-post-process-gsd-sections.md:163` | `$TMPDIR` assumed set without fallback

**Description.** Step 3 prose: `cp CLAUDE.md "$TMPDIR/CLAUDE.md.preview"`. On macOS `$TMPDIR` is set by launchd. On stripped-down Linux shells (e.g., systemd services, Docker `FROM scratch+busybox`, env-i invocations), `$TMPDIR` is unset and the prose becomes `cp CLAUDE.md "/CLAUDE.md.preview"` — clobbering a rootfs file (needs sudo; in a container running as root, succeeds and corrupts).

**Reproducer.**

```bash
env -i bash -c 'echo "TMPDIR=[$TMPDIR]"'   # empty
```

**Suggested fix.** Use `mktemp -d` for the preview directory:

```bash
PREVIEW_DIR="$(mktemp -d)"
cp CLAUDE.md "$PREVIEW_DIR/CLAUDE.md.preview"
.claude/hooks/normalize-claude-md.sh "$PREVIEW_DIR/CLAUDE.md.preview"
# … but note: the script now refuses non-CLAUDE.md basename (BLOCK guard H1),
# so the preview path MUST keep the basename CLAUDE.md.
```

Second-order bug: the basename guard H1 (added during CSO review) makes the prose's `CLAUDE.md.preview` argument FAIL — the script will refuse to operate. The migration prose is now incompatible with the script's own security check. Either rename the preview to keep `CLAUDE.md` as basename, or special-case the basename check (e.g., accept `CLAUDE.md` or `CLAUDE.md.<extension>`).

---

#### FLAG-D | `templates/.claude/hooks/normalize-claude-md.sh:74-87, 141-143` | Silent preservation of unmapped source labels — no stderr warning

**Description.** The fixture README `migrations/test-fixtures/0010/inlined-source-missing/CLAUDE.md` line 14 claims: *"the post-processor MUST … emit a warning to stderr."* But the script only logs the warning when the source label maps to a known path AND that path is missing on disk (line 150). For unmapped labels like `source:NONEXISTENT.md` (which falls through to `*) echo "" ;;` at line 85), the script silently returns 1 from `build_replacement` and preserves the block with no stderr output.

**Reproducer.**

```bash
SCRIPT=templates/.claude/hooks/normalize-claude-md.sh
TMP=$(mktemp -d); cd "$TMP"; mkdir -p .planning && touch .planning/PROJECT.md
cat > CLAUDE.md <<'EOF'
<!-- GSD:project-start source:NONEXISTENT.md -->
## Project
preserved
<!-- GSD:project-end -->
EOF
"$SCRIPT" CLAUDE.md 2>stderr.log
wc -l stderr.log   # 0 — silent, despite the README's "MUST emit warning" claim
```

**Suggested fix.** In `build_replacement` at line 141-143, emit a stderr warning before `return 1`:

```bash
if [ -z "$link_path" ]; then
  echo "normalize-claude-md: unknown source label '$source_label' for slug=$slug; preserving block" >&2
  return 1
fi
```

This brings behavior in line with the fixture's stated contract and gives users a diagnostic when they typo a label.

---

#### FLAG-E | `templates/.claude/hooks/normalize-claude-md.sh:32` | PATH pinning may break in environments without `/usr/bin/awk`

**Description.** Line 32 hard-pins `PATH="/usr/bin:/bin:/usr/sbin:/sbin"`. On macOS and most Linux distros this is fine. Alpine Linux (busybox-based) puts coreutils at `/bin` only; `/usr/bin/awk` may not exist. NixOS puts everything under `/nix/store/.../bin` — neither `/usr/bin` nor `/bin` contain `awk`. On those systems the hook fails. The intent (CSO H2 — defend against PATH poisoning) is sound; the implementation excludes legitimate alternate layouts.

**Suggested fix.** Either (a) probe for `awk`, `cp`, `diff`, `mktemp` and emit a clear "tool not found" diagnostic if any are missing, or (b) accept the original PATH but validate the chosen `awk`'s realpath is in `/usr/bin`, `/bin`, or `/nix/store/`. For now (a) is the cheap fix:

```bash
for tool in awk diff cp mktemp basename wc tr; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "normalize-claude-md: required tool '$tool' not in PATH=$PATH" >&2
    exit 1
  }
done
```

---

#### FLAG-F | `templates/.claude/hooks/normalize-claude-md.sh:239` | `mktemp` failure → `set -u` doesn't catch it; trap runs `rm -f ""` and pipeline continues

**Description.** `TMP_OUT="$(mktemp -t normalize-claude-md.XXXXXX)"` — if `mktemp` fails (tmpfs full, permission denied, `TMPDIR` unwritable), the command substitution returns empty, `$TMP_OUT=""`, and `set -u` does NOT trigger (variable IS assigned, just to empty). The trap then runs `rm -f ""`, a no-op. The pipeline `>"$TMP_OUT"` becomes `>""` which fails with "No such file or directory" — `pipefail` catches it and the script exits 2. Acceptable failure mode by accident, but not deliberately handled.

**Suggested fix.** Explicit check:

```bash
TMP_OUT="$(mktemp -t normalize-claude-md.XXXXXX)" || {
  echo "normalize-claude-md: mktemp failed" >&2
  exit 1
}
```

---

### Findings — NIT

#### NIT-α | `templates/.claude/hooks/normalize-claude-md.sh:185` | Comment claims "trim trailing whitespace the greedy match may have included" but the trim happens only IF the source attr was captured

**Description.** Line 184-185: `block_source="${BASH_REMATCH[3]:-}"; block_source="${block_source%"${block_source##*[![:space:]]}"}"`. When the regex's optional `source:(.+)` group didn't match, `BASH_REMATCH[3]` is unset and `:-` defaults to empty string. The trim then runs on the empty string, which is fine. Comment could be tightened to clarify the trim handles both cases — but functionally it's correct. Leaving as a nit.

---

#### NIT-β | `templates/.claude/hooks/normalize-claude-md.sh:154-156` | Reference-link form duplicates the path inside backticks and inside the URL

**Description.** Output line: ``See [`.planning/PROJECT.md`](./.planning/PROJECT.md) — auto-synced.`` The display label and the URL are the same. Pure presentation choice; not a defect. Mention for cosmetic-polish discussion only.

---

#### NIT-γ | `migrations/test-fixtures/0010/inlined-7-sections/expected/CLAUDE.md:8-9` | Inconsistent blank-line spacing around block boundaries

**Description.** Expected golden alternates between blocks with a single blank between them. In some cases there's one blank, in others none. Not a behavioral bug — `collapse_blank_runs` is what produces this — but the golden is the source of truth and could be hand-tightened for visual consistency.

---

#### NIT-δ | `migrations/0010-post-process-gsd-sections.md:267-271` | Notes-for-implementers section asserts pipefail importance but doesn't acknowledge BLOCK-1

**Description.** The note that `set -o pipefail` propagates the `return 2` from `normalize()` is accurate. But it claims "Without pipefail, malformed input would silently produce broken output with exit 0" — which suggests the author has thought about silent-failure modes. BLOCK-1 (binary-input → empty-output → cp-clobber) is exactly that class of silent failure, and pipefail does NOT save you from it. Worth tightening.

---

### Stage-2 verdict

**REQUEST-CHANGES.**

The Stage-1 review correctly identified that the artifact functionally honors the spec — but it under-attacked the script's behavior at the edges, where the real damage lives. Three categories of issue surface only under Stage-2's adversarial pass:

1. **Silent data destruction** under pathological inputs (BLOCK-1 binary, BLOCK-2 fenced markers, BLOCK-5 custom slugs, BLOCK-6 malformed/nested). The script's mantra of "source-existence-safe; never loses information" is not held under any of these inputs.
2. **Bypass + partial-mutate** on CRLF input (BLOCK-3) — markers ignored, blank-line collapse still fires.
3. **Concurrency hazard** with non-atomic `cp` (BLOCK-4) — confirmed reproducible with 20 racing invocations producing visibly corrupt output and stderr noise.

Plus a doc/code mismatch on the "early exit" claim (FLAG-B), a `$TMPDIR` foot-gun in the migration prose (FLAG-C, exacerbated by basename guard H1), and a fixture-README-vs-script behavioral mismatch on the "MUST warn on missing source" claim (FLAG-D).

Recommended pre-merge fixes (minimum bar to flip Stage-2 to APPROVE-WITH-NITS):

- **BLOCK-1:** Add the `[ ! -s "$TMP_OUT" ] && [ -s "$INPUT" ] && exit 2` guard.
- **BLOCK-2:** Add a fenced-code-block state machine to the line walker.
- **BLOCK-3:** Strip `\r` from `$line` in the read loop.
- **BLOCK-5:** Add the canonical-slug allowlist guard at the top of `build_replacement`.
- **BLOCK-6:** Treat a nested `-start` inside an open block as malformed; exit 2.
- **FLAG-B + FLAG-C:** Reconcile the prose with the as-shipped script.

BLOCK-4 (atomicity) is harder to fix portably; recommend at least documenting the concurrent-edit hazard in ADR 0022's "Bad / risks" section and tracking `flock`-based hardening as a follow-up phase. The other FLAGs and NITs can land as a follow-up patch.

The 10/10 harness PASS does not refute these findings — the fixtures simply don't exercise these inputs. The harness is well-built for what it tests; what it tests is just incomplete.
