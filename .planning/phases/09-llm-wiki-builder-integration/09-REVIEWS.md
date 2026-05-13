# Phase 09 — Multi-AI Plan Reviews

**Plan reviewed:** PLAN.md (this phase)
**Date:** 2026-05-13
**Reviewers invoked:** gemini (Google), codex (OpenAI)
**Floor satisfied:** ≥2 (codex + gemini) → PASS

This is the dogfood artifact for Phase 09. Same discipline as Phase 08: PLAN.md goes through ≥2 independent reviewer CLIs *before* T1 execution, with a structured BLOCK / FLAG / STRENGTHS verdict.

---

## Aggregate verdict

| Reviewer | Verdict | BLOCKs | FLAGs | STRENGTHS |
|---|---|---|---|---|
| gemini | APPROVE-WITH-FLAGS | 0 | 3 | 4 |
| codex | **REQUEST-CHANGES** | **3** | 4 | 3 |

**Action:** REQUEST-CHANGES wins. PLAN.md amendments land below before T1.

---

## Gemini review (summary)

APPROVE-WITH-FLAGS, 0 BLOCKs. Three minor FLAGs:

- **F1 (gemini)** — ADR 0019 should explicitly carry the supply-chain + always-on-hooks threat-model notes from PLAN.md. T2's ADR cleanup doesn't list this explicitly.
- **F2 (gemini)** — CLAUDE.md idempotency check `grep -q '## Knowledge wiki'` is good but case-sensitive; a `grep -iq '^##.*wiki'` would catch user variations like `## Wiki Details`.
- **F3 (gemini)** — Defense-in-depth: add post-generation validation that `.wiki-compiler.json` sources resolve under the family root.

Verdict prose: "Exceptionally well-structured and low-risk plan that benefits from the discipline established in previous phases."

## Codex review (raw)

```
## VERDICT
REQUEST-CHANGES

## BLOCK findings
- [B1] The plan never proves the migrated install produces a usable wiki
  integration — the Goal and "Goal-backward verification matrix" require
  "the same wiki integration that's currently set up manually on this dev
  host," but "Won't-do" explicitly avoids invoking /wiki-compile, and T5
  verifies only filesystem state (symlink, dirs, config files, CLAUDE.md,
  version bump). That blocks ship confidence because a malformed
  .wiki-compiler.json, unsupported glob pattern, or non-discoverable plugin
  command surface can still pass every planned check.

- [B2] Wrong-target symlink handling is inconsistent and too destructive
  for a host-level migration — the "Threat model preview" says to abort if
  ~/.claude/plugins/llm-wiki-compiler is a wrong-target symlink, but
  RESEARCH §6A changes this to "WARNING ... replacing," and T1 has no
  fixture for that case. Silently repointing an existing host-global
  plugin symlink can overwrite a user's manual or forked install for every
  Claude session, so this needs a locked policy and test coverage before
  execution.

- [B3] Family CLAUDE.md existence/creation semantics are undefined on the
  happy path — Scope #7, RESEARCH §4, T2, and T5 all require updating a
  family-level CLAUDE.md, but Dependencies never establish that file
  exists and T1 only tests idempotent duplication, not absence. On a
  fresh machine or teammate setup without a family-root CLAUDE.md, the
  migration can fail after partial host/family writes or create an
  incomplete file, so the plan does not yet cover the stated consumer
  install path.

## FLAG findings
- [F1] Fake-$HOME sandboxing is directionally right but not complete by
  itself — T1/T3 rely on HOME=$TMP/home, but the plan has no escape check
  for accidental absolute-path writes (/Users/..., pre-expanded ~, or any
  future command that ignores HOME). Add a harness guard that fails on
  real-home path usage or greps the generated apply script for non-
  sandboxed absolute paths.

- [F2] Dynamic family detection is too broad for an install migration —
  RESEARCH §1A scans every ~/Sourcecode/*/ except a short skip-list,
  which means unrelated top-level dirs like experiments, vendor, or future
  non-family buckets will get .wiki-compiler.json and .knowledge/
  scaffolding. Add a stronger family heuristic or an explicit allow/deny
  contract.

- [F3] The threat model drifts on config-path safety — the CONTEXT
  "Threat model preview" says pre-flight validates sources[*].path stays
  under the family root, while the PLAN threat model says T2 "does NOT
  validate path-resolution at write time." That mismatch matters because
  it changes whether cross-family leakage is actually mitigated or merely
  documented.

- [F4] Verification is still light on path-collision edge cases — T1
  covers real-file collision and correct-symlink reuse, but not missing
  ~/.claude/plugins parent, .knowledge existing as a file/symlink, or an
  existing malformed .wiki-compiler.json that is preserved but unusable.

## STRENGTHS
- [S1] The plan is disciplined about idempotency and rollback semantics;
  preserving family data while reverting only the host symlink and
  version bump is the right default.
- [S2] T1's fixture matrix is concrete and already covers several high-
  value install-time cases.
- [S3] Carries forward Phase 08 lessons well.

## Summary
The plan is close, but it still has a goal-vs-verification gap: it proves
scaffolding, not a working wiki integration. The must-fix items are an
end-to-end usability smoke test, a safe policy for wrong-target symlinks,
and explicit behavior when family CLAUDE.md is missing.
```

---

## Resolution of codex BLOCKs (PLAN.md amended)

| # | Finding | Resolution |
|---|---|---|
| **B1** | Goal-vs-verification gap — scaffolding doesn't prove usability | **New task T5b** — post-apply smoke test: verify (a) `~/.claude/plugins/llm-wiki-compiler/.claude-plugin/plugin.json` parses with `jq empty`, (b) the plugin manifest declares at least the canonical commands (`wiki-compile`, `wiki-lint`), (c) every `<family>/.wiki-compiler.json` parses with `jq empty` and at least one `sources[*].path` glob resolves to ≥1 file via `compgen -G`. This is cheaper than running an actual `/wiki-compile` (no LLM round-trip) but catches malformed manifests/configs/globs. Adds a tight feedback loop that scaffolding ≠ working install. |
| **B2** | Wrong-target symlink policy inconsistent | **Locked policy: ABORT (not replace)** on wrong-target symlink. RESEARCH §6 amended to match the threat-model "abort" stance. Fixture **10-wrong-target-symlink** added: existing symlink points at `/tmp/other-plugin`; migration exits non-zero with `ERROR: ~/.claude/plugins/llm-wiki-compiler is a symlink to <other>; refusing to repoint (use rollback first if you want to reinstall)`. |
| **B3** | Family CLAUDE.md absence undefined | **Skip-with-warning policy.** If `<family>/CLAUDE.md` doesn't exist, the migration logs `note: <family>/CLAUDE.md not present, skipping ## Knowledge wiki section addition` and proceeds. It does NOT create the file (that's user territory). Fixture **11-missing-family-claudemd** asserts skip behavior + no partial state. Documented in Notes section + migration body's Step 4. |

## Resolution of codex FLAGs

| # | Finding | Resolution |
|---|---|---|
| **F1** | Sandbox escape check | **Harness pre-run guard** added: before running each fixture's apply, `grep -E '/Users/donald|/home/$USER' migration-script.sh` and fail if matched. Catches pre-expanded `~` or hardcoded paths. |
| **F2** | Family heuristic too broad | **Stronger heuristic:** a directory under `~/Sourcecode/` is treated as a family if and only if it contains at least one immediate child that's a git repo (i.e. `find <dir>/*/.git -maxdepth 1 -type d -print -quit` returns non-empty). Plus the existing skip-list (`personal\|shared\|archive\|.*`). RESEARCH §1A updated. Fixture **12-non-family-dir-skipped** asserts that `~/Sourcecode/experiments/` (no child .git dirs) doesn't get scaffolded. |
| **F3** | CONTEXT vs PLAN drift on path validation | **Locked: no path-resolution at write time.** Updated CONTEXT threat model preview to match PLAN: "pre-flight does NOT validate `sources[*].path` resolution; the plugin handles missing-source warnings at compile time. Cross-family leak risk is low because the migration writes only the default config." T5b smoke test (B1 resolution) catches malformed globs; user customization is user-territory. |
| **F4** | More edge cases | Three new fixtures: **13-missing-plugins-parent** (`~/.claude/` lacks `plugins/` subdir — migration creates it), **14-knowledge-as-file** (path collision on `.knowledge` as regular file — abort), **15-malformed-existing-config** (pre-existing `.wiki-compiler.json` is invalid JSON — preserve but warn). |

## Resolution of gemini FLAGs

| # | Finding | Resolution |
|---|---|---|
| **F1 (gemini)** | ADR 0019 should carry threat-model notes | **T2 (ADR cleanup) extended** to add a "Threat model" section in ADR 0019 with the 7 STRIDE rows from PLAN.md. |
| **F2 (gemini)** | Case-sensitive CLAUDE.md idempotency check | Acknowledged as low-impact. Sticking with `grep -q '^## Knowledge wiki'` (exact-match for the section we own). If a user has a custom section, we don't claim collision-detection of arbitrary headers — that's a separate concern from idempotency. |
| **F3 (gemini)** | Path-resolution validation in config | Addressed by codex F3 resolution (no path validation at write time; T5b smoke test catches malformed configs at apply time). |

---

## Fixture count update

PLAN.md grows from **9 fixtures** to **15 fixtures**. New: 10 (wrong-target symlink), 11 (missing family CLAUDE.md), 12 (non-family dir skipped), 13 (missing plugins parent), 14 (.knowledge as file), 15 (malformed existing config). Plus T5b smoke test as a separate driver.

---

## Conclusion

REQUEST-CHANGES → PLAN.md amended structurally → ready to proceed to T1.

The B1 fix (T5b smoke test) is the biggest substantive change — it moves AC verification from "scaffolding exists" to "scaffolding produces a parseable, functional plugin install." That's the right bar for a migration that adds a host-level surface.

The B2/B3 resolutions tighten safety: abort-on-wrong-target prevents silent clobbering of forked installs; skip-on-missing-CLAUDE.md prevents accidentally creating user files. Both are correct defaults for an install-time migration.
