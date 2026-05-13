# Phase 10 — Multi-AI Plan Reviews

**Plan reviewed:** PLAN.md
**Date:** 2026-05-13
**Reviewers:** gemini, codex
**Floor:** ≥2 ✅

---

## Aggregate verdict

| Reviewer | Verdict | BLOCKs | FLAGs | STRENGTHS |
|---|---|---|---|---|
| gemini | APPROVE-WITH-FLAGS | 0 | 2 | 5 |
| codex | **REQUEST-CHANGES** | **3** | 3 | 4 |

Action: PLAN.md amended below before T1.

---

## Codex BLOCK findings + resolutions

### B1 — Install/runtime model internally inconsistent

**Finding:** RESEARCH §1 makes `gitnexus` a verify-only global prerequisite, but RESEARCH §2 / §5 wire the MCP server to `npx -y gitnexus@... mcp`. The MCP command doesn't use the verified global binary — npx fetches it fresh from the registry on first invocation. So:
1. Verify-only check is meaningless (MCP doesn't use the verified binary).
2. License/supply-chain story breaks (user consents to `npm install -g gitnexus` for nothing; npx-based MCP still pulls PolyForm software at first MCP invocation, no distinct consent).

**Resolution:** MCP command changed from `npx -y gitnexus@<v> mcp` to `gitnexus mcp` (use the verified global binary). Three coordinated changes:
- RESEARCH §2 + §5 amended.
- Install script's MCP-add command uses `gitnexus` directly (not `npx`).
- Pre-flight verify-only step is now load-bearing — if `gitnexus` is missing, the MCP command would fail at session start; pre-flight catches it.

**Status:** ✅ Plan amended. Implementation in T2.

### B2 — Idempotency = "entry exists" not "entry is valid"

**Finding:** Scope step 3, AC-6, fixture `06-existing-mcp-entry`, and the threat-model row all preserve any pre-existing `gitnexus` entry unchanged. A stale/malformed entry yields false green (version bumps to 1.9.3, MCP doesn't work).

**Resolution:** Idempotency check tightened to validate entry shape:
- Existing entry's `command` field equals `gitnexus` (or `npx` for legacy entries — accept and warn).
- Existing entry's `args[]` starts with `mcp` (or `-y gitnexus@... mcp` for legacy).
- If shape doesn't match: log `warn: pre-existing gitnexus MCP entry has unexpected shape; preserving but server may not work` to stderr, AND fail-loud at the end of apply (exit 4 = "applied but external state suspicious").

**Status:** ✅ Plan amended. New exit code (4) added.

### B3 — Verification never proves end-to-end works

**Finding:** T1/T4/T5 verify file writes, rollback, `bash -n`. No positive-path test that the MCP command can start, no test that helper script's `--family X` dispatch actually parses args correctly.

**Resolution:** Two new fixtures + a behavioral check on the install:
- **Fixture 13 — mcp-command-startup-smoke:** stub `gitnexus` as a bash script that, when invoked as `gitnexus mcp`, exits 0 and writes a recording file. After install, harness invokes the MCP command extracted from `~/.claude.json` and asserts the stub's recording file exists.
- **Fixture 14 — helper-script-family-dispatch:** invoke `index-family-repos.sh --family factiv` with a stubbed `gitnexus` that records args. Assert the stub was invoked with the expected per-repo args (one per family repo).
- **Fixture 15 — helper-script-default-set-dispatch:** invoke with `--default-set`, assert exactly the curated subset of repos got args-recorded.

**Status:** ✅ Plan amended. Fixture count grows 12 → 15.

---

## Codex FLAG findings + resolutions

| # | Finding | Resolution |
|---|---|---|
| **F1** | jq fallback for missing `~/.claude.json` (fresh user) underspecified | New fixture **16-no-claude-json-yet**: harness setup has no `~/.claude.json`; install creates it as `{"mcpServers":{"gitnexus":{...}}}`. Fixture count 15 → 16. |
| **F2** | Code-disclosure risk from `gitnexus analyze` missing from threat model | Added "Information Disclosure" row in PLAN threat model. Helper script's usage block updated with a sharper warning about per-repo content + credentials. |
| **F3** | Preconditions drift (CONTEXT vs RESEARCH vs T2) | CONTEXT Scope §1 trimmed: pre-flight = node ≥ 18 + jq + gitnexus. No internet check. T2 acceptance reflects the locked list. New fixture **17-no-jq** confirms jq pre-flight fires. Fixture count 16 → 17. |

---

## Gemini FLAG findings + resolutions

| # | Finding | Resolution |
|---|---|---|
| **F1 (gemini)** | Pre-flight should verify gitnexus version compatibility | Pre-flight extracts gitnexus's `--version`, compares against `GITNEXUS_VERSION` env (default a known-good pin). Mismatch: log warn but proceed (forward-compat). New fixture **18-version-pin-mismatch** asserts warn-but-proceed. Fixture count 17 → 18. |
| **F2 (gemini)** | Verify pinned version exists on npm before writing config | **Rejected** — would add a network operation back into the migration. Verify-only contract holds; if the user has gitnexus installed, that's our proof of npm availability. |

---

## Fixture count update

PLAN.md grows from **12 fixtures** to **18 fixtures**. New: 13 (mcp-command-startup), 14 (helper family dispatch), 15 (helper default-set dispatch), 16 (no claude.json yet), 17 (no jq), 18 (version pin mismatch).

---

## Summary

Codex caught the most important miss: the verify-only install was theater because the MCP command used `npx`, not the verified binary. Plan amended structurally (`gitnexus mcp` instead of `npx`). Idempotency tightened to validate entry shape. Behavioral fixtures added for end-to-end positive paths. F2 information-disclosure threat surfaced.

Ready to proceed to T1.
