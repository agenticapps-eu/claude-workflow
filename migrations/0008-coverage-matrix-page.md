---
id: 0008
slug: coverage-matrix-page
title: Coverage Matrix Page — cross-family knowledge-layer freshness dashboard
type: workflow-surface
from_version: 1.7.0
to_version: 1.8.0
applies_to:
  - agenticapps-dashboard's new /coverage route (no skill file mutations required on consumer repos)
  - Migration tracks dashboard-side capability bump; consumer repos auto-discover the new workflow surface
requires:
  - tool: agenticapps-dashboard
    install: "See dashboard repo install instructions"
    verify: "curl -H 'Authorization: Bearer $TOKEN' http://127.0.0.1:5193/api/coverage | jq '.schemaVersion'  # → 1"
  - node: ">= 18"
optional_for:
  - GitNexus index (handled gracefully when absent — see ADR 0023 §Empty States)
  - Wiki compilation (clipboard-only in v1 — see ADR 0023 §Decisions: Wiki refresh)
notes:
  - "Wiki refresh is clipboard-only in v1.0 — no headless `/wiki-compile` runner exists; the dashboard surfaces a 'Copy command' affordance instead. See ADR 0023."
  - "GitNexus registry verify: use `jq 'length' ~/.gitnexus/registry.json 2>/dev/null || echo 0` (top-level array). Migration 0007's verify snippet `jq '.repos | length'` was incorrect — the registry has no .repos property."
  - "Workflow version bump is consumer-passive: existing repos with version: 1.7.0 will show as 'stale (behind: 1.7.0 → 1.8.0)' in the dashboard's coverage matrix until updated."
---

# Migration 0008: Coverage Matrix Page

## Why

The AgenticApps Superpowers + GSD + gstack workflow defines a knowledge layer per repo
(CLAUDE.md), per family (wiki), globally (GitNexus index), and per workflow installation
(skill version). Until agenticapps-dashboard Phase 10, there was NO surface answering
"which repos are doing their knowledge-layer homework, and what needs attention?"

This migration documents the shipping of the `/coverage` page in agenticapps-dashboard.
See ADR 0023 for full design rationale.

## What changes

1. agenticapps-dashboard ships a new `/coverage` route — cross-family knowledge-layer freshness dashboard
2. New daemon endpoints: `GET /api/coverage`, `POST /api/coverage/refresh`
3. Workflow head version bumps to 1.8.0 — no skill-file edits required in consumer repos
4. Sidebar nav gains 'Observability' section with single 'Coverage' entry

## Verify

```bash
# 1. Dashboard daemon responds with schemaVersion 1
curl -sH "Authorization: Bearer $TOKEN" http://127.0.0.1:5193/api/coverage | jq '.schemaVersion'
# expect: 1

# 2. Workflow head matches this migration
curl -sH "Authorization: Bearer $TOKEN" http://127.0.0.1:5193/api/coverage | jq -r '.workflowHeadVersion'
# expect: "1.8.0" (or later if newer migrations are present)

# 3. GitNexus column reports installed status correctly
[ -d ~/.gitnexus ] && jq 'length' ~/.gitnexus/registry.json || echo "0 (not installed)"

# NOTE: jq '.repos | length' (used in migration 0007) is INCORRECT. The registry is a top-level array.
```

## Rollback

Removing this migration does not delete data — the dashboard's /coverage page simply
becomes unavailable. The workflow head version reverts to 1.7.0 (from migration 0007).
Consumer repos that had their skill updated to 1.8.0 will then show as "ahead" instead
of "fresh" in any future coverage matrix.

## Related

- ADR 0018 — multi-ai-plan-review-enforcement (override-chip data source)
- ADR 0019 — llm-wiki-compiler-integration (Wiki column data source)
- ADR 0020 — gitnexus-code-graph-integration (GitNexus column data source; verify-script schema bug documented here)
- ADR 0023 — coverage-matrix-page (this migration's design ADR)
