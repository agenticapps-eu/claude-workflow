---
id: 0018
slug: postphase-observability-hook-moved
title: "[TOMBSTONE] postphase-observability-hook — moved to agenticapps-observability"
from_version: 1.16.0
to_version: 1.17.0
applies_to: []
moved_to: agenticapps-eu/agenticapps-observability
obs_migration: "0018 (1.16.0 -> 1.17.0)"
---

# Migration 0018 — [TOMBSTONE] Moved to agenticapps-observability

This migration was moved to the `agenticapps-eu/agenticapps-observability` repository
as part of `claude-workflow 2.0.0` (SPLIT-03). The observability skill is now a
separate installation:

```bash
git clone https://github.com/agenticapps-eu/agenticapps-observability \
  ~/.claude/skills/agenticapps-observability
bash ~/.claude/skills/agenticapps-observability/install.sh
```

Then run `/update-agenticapps-workflow` to apply any pending observability migrations
via the obs repo's own update chain.

This slot is a no-op tombstone. If your project is already past version 1.17.0, the
migration engine skips it automatically (it matches by `from_version`).
