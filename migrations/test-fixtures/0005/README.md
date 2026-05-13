# Test fixture — Migration 0005

Validates the multi-AI plan review enforcement hook.

## Cases

1. **No active phase** — `.planning/current-phase` symlink missing → hook returns 0 (allow).
2. **Active phase, no PLAN.md yet** — planning hasn't started → hook returns 0.
3. **Active phase, PLAN.md present, no REVIEWS.md** → hook returns 2 (block) on code Edit, returns 0 on PLAN.md edit.
4. **Active phase, both PLAN.md and REVIEWS.md** → hook returns 0.
5. **Override sentinel present** → hook returns 0 even with PLAN.md but no REVIEWS.md.
6. **GSD_SKIP_REVIEWS=1 env** → hook returns 0 unconditionally.

## How to run

From this directory:

```bash
bash run-tests.sh
```

(See `migrations/run-tests.sh` for the runner harness.)
