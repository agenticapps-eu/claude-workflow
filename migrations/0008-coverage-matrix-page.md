---
id: 0008
slug: coverage-matrix-page
title: Coverage Matrix Page — cross-family knowledge-layer freshness dashboard
type: workflow-surface
from_version: 1.5.0
to_version: 1.6.0
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
  - "Workflow version bump is consumer-passive: existing repos at any version below head will show as 'stale (behind: <local> → <head>)' in the dashboard's coverage matrix until updated. The matrix reads the workflow scaffolder's current head (1.9.3 at the time of writing), not this migration's to_version specifically."
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
3. Workflow head version bumps to 1.6.0 (consumer-passive — no skill-file edits required in consumer repos; the dashboard surface is workflow-repo-only)
4. Sidebar nav gains 'Observability' section with single 'Coverage' entry

## Verify

```bash
# 1. Dashboard daemon responds with schemaVersion 1
curl -sH "Authorization: Bearer $TOKEN" http://127.0.0.1:5193/api/coverage | jq '.schemaVersion'
# expect: 1

# 2. Workflow head is at least this migration's to_version
curl -sH "Authorization: Bearer $TOKEN" http://127.0.0.1:5193/api/coverage | jq -r '.workflowHeadVersion'
# expect: "1.9.3" (current head; "1.6.0" or later if checked before subsequent migrations apply)

# 3. GitNexus column reports installed status correctly
[ -d ~/.gitnexus ] && jq 'length' ~/.gitnexus/registry.json || echo "0 (not installed)"

# NOTE: jq '.repos | length' (used in migration 0007) is INCORRECT. The registry is a top-level array.
```

## Rollback

Removing this migration does not delete data — the dashboard's /coverage page simply
becomes unavailable. After re-anchor (Phase 11), 0008 is now `1.5.0 → 1.6.0`, so rolling
it back returns the chain head to 1.5.0 (the to_version of migration 0002). Consumer
repos that had their skill updated to a higher version are unaffected by removing the
dashboard surface — this migration does not write skill state in consumer repos.

## Related

- ADR 0018 — multi-ai-plan-review-enforcement (override-chip data source)
- ADR 0019 — llm-wiki-compiler-integration (Wiki column data source)
- ADR 0020 — gitnexus-code-graph-integration (GitNexus column data source; verify-script schema bug documented here)
- ADR 0023 — coverage-matrix-page (this migration's design ADR)
