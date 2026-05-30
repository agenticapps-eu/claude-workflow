---
id: 0020
slug: openrouter-integration
title: OpenRouter integration kit (SDK-first)
from_version: 1.18.0
to_version: 1.19.0
applies_to:
  - .claude/skills/agentic-apps-workflow/SKILL.md  # version 1.18.0 → 1.19.0
optional_for:
  - projects that do NOT call OpenRouter / OpenAI SDK
auto_apply: false
adoption: runbook-or-init
---

# Migration 0020 — OpenRouter integration kit (SDK-first)

Brings projects from AgenticApps workflow v1.18.0 to v1.19.0. The substantive work — `recordLLMResponseMeta` helper across 3 TS stacks, the `openrouter-monitor` Worker scaffold, the runbook, and the INIT.md §5.5 consent gate — is **additive and opt-in**. Existing projects do not require any mechanical migration to remain conforming to v1.19.0.

Per CONTEXT [D-01](../.planning/phases/24-openrouter-integration/CONTEXT.md) + [ADR-0030](../docs/decisions/0030-openrouter-integration-sdk-first.md): no migration script ships. The scaffolder version bump alone moves the project's recorded `version:` marker. Adoption of the new templates happens via:

- **`add-observability/openrouter-integration.md`** — the runbook, for manual adoption against an existing wrapper.
- **`add-observability/init/INIT.md` Phase 5.5 §"Optional: LLM observability"** — consent gate 4 during `/add-observability init` runs (auto-detects OpenRouter usage; defaults to skip on `--yes`).

This migration exists primarily to satisfy the F4 drift-test invariant (Phase 23: "every `skill/SKILL.md` version must have a corresponding migration with matching `to_version`") and to document the upgrade path in the canonical place. There is no mechanical state to migrate.

## Pre-flight

```bash
INSTALLED=$(grep -E '^version:' .claude/skills/agentic-apps-workflow/SKILL.md | head -1 | sed 's/version: //' | tr -d '[:space:]')
test "$INSTALLED" = "1.18.0" || { echo "ERROR: installed version is $INSTALLED, this migration requires 1.18.0"; exit 1; }
```

## Steps

### Step 1 — Bump the recorded version marker

**Idempotency check:** `grep -q '^version: 1.19.0$' .claude/skills/agentic-apps-workflow/SKILL.md`

**Apply:**

```bash
sed -i.bak 's/^version: 1\.18\.0$/version: 1.19.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

**Verify:** `grep -q '^version: 1.19.0$' .claude/skills/agentic-apps-workflow/SKILL.md`

## Adoption (optional, opt-in)

If your project calls OpenRouter via the OpenAI SDK and you want to capture the signals Sentry AI Monitoring doesn't surface (rate-limit headroom + cache_ratio), follow the runbook:

1. Read `add-observability/openrouter-integration.md` — 5-section adoption guide.
2. Upgrade `@sentry/<host>` to `≥ 10.2.0` if you want AI Monitoring (`openAIIntegration`).
3. Copy `add-observability/templates/<your-stack>/llm-response-meta.ts` into your wrapper directory.
4. Wire `recordLLMResponseMeta` at SDK call sites using the `.withResponse()` pattern.
5. (Optional) Deploy `add-observability/templates/openrouter-monitor/` as a standalone Worker for proactive budget alerting.

If your project is **greenfield** (running `/add-observability init` afresh), Phase 5.5 of INIT.md will offer the consent-gated install during the standard init flow.

If your project does **not** use OpenRouter / OpenAI SDK, this migration is a no-op beyond the version-marker bump.

## Rollback

```bash
sed -i.bak 's/^version: 1\.19\.0$/version: 1.18.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
```

(The new templates ship in the scaffolder repo regardless; downgrading the version marker simply re-locks the project to v1.18.0 conformance. The new templates remain available for forward re-adoption.)

## See also

- ADR-0030 — OpenRouter integration: SDK-first
- ADR-0029 — Cron-monitor SDK composition (Guarded Shape A) — monitor's heartbeat
- ADR-0014 — Observability architecture — helper destination-independence
- `.planning/phases/24-openrouter-integration/CONTEXT.md` — locked decisions D-01 — D-19
- `.planning/phases/24-openrouter-integration/24-REVIEWS.md` — multi-AI plan review (gemini + codex)
