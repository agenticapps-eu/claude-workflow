# v1.19.0 frozen baselines (codex M-1)

These files are byte-stable snapshots of the pre-Phase-25 (v1.19.0) `cron-monitor.ts`
state captured on 2026-05-31 before Plan 03 mutated the live templates under
`add-observability/templates/<stack>/`.

**DO NOT EDIT.** Their canonical hash is what the migrate-0021 engine compares
project state against. If a future phase needs new baselines (e.g., v1.20.0 → v1.21.0),
add a sibling `v1.20.0/` dir; never edit `v1.19.0/`.

Used by:
- `migrations/test-fixtures/0021/common-setup.sh` (seed_v1_19_0_* helpers cp from here).
- `migrate-0021-with-cron-and-queue-updates.sh` engine (computes v1.19.0 canonical hash from here at engine-init time — Plan 05).
