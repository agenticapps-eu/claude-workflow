# Upgrading claude-workflow

## 1.21.0 → 2.0.0 (SPLIT-03: observability extracted)

claude-workflow 2.0.0 is a **deliberate breaking release**. Observability is no
longer shipped by this scaffolder — it has been extracted into the separate
[`agenticapps-observability`](https://github.com/agenticapps-eu/agenticapps-observability)
repository, which installs and updates independently.

### Supported upgrade floor

The supported upgrade path is **1.21.0 → 2.0.0**. `1.21.0` is the Phase 27
SPLIT-00 stable baseline at which all live downstream consumers are parked
(factiv/cparx, factiv/callbot, factiv/fx-signal-agent), pinned by git tag +
commit SHA.

Pre-baseline (`< 1.21.0`) full-chain replay is **out of support scope**. The
tombstoned migration slots (0012, 0013, 0017, 0018, 0019, 0020, 0021) keep the
migration chain contiguous so a pre-baseline replay does not hit a missing-number
gap — but no live consumer takes that path, and it is not tested or supported.
If you are below 1.21.0, advance to the 1.21.0 baseline first.

### Why 2.0.0 is breaking

- The observability skill (`init` / `scan` / `scan-apply`) was removed from this
  repository. claude-workflow no longer installs any observability scaffolding.
- The observability skill now lives in `agenticapps-observability` and is a
  **separate, independent install** into `~/.claude/skills` — not a submodule and
  not chained from `/setup-agenticapps-workflow`.
- The two version axes are now forked: claude-workflow advances on its own `2.x`
  axis; observability keeps its own consumer version axis.

### What changed

- The repo's `add-observability/` skill tree was removed.
- Migrations `0012`, `0013`, `0017`, `0018`, `0019`, `0020`, `0021` were
  tombstoned (no-op redirect stubs that keep the chain contiguous and point at
  `agenticapps-observability`).
- New migration `0022` repoints the observability install reference, replaces the
  Stop-hook Phase Sentinel with a deterministic shell hook (#58), and carries
  `to_version: 2.0.0` — bumping your project-local
  `.claude/skills/agentic-apps-workflow/SKILL.md` to `2.0.0` and resolving the
  prior 1.20.0 (skill) / 1.21.0 (tag) skew. (In the claude-workflow repo itself the
  same release bumps the source `skill/SKILL.md`; downstream projects only have the
  hyphenated installed-skill file.)

### What downstream projects must do

Observability is now a **second, independent install**. Install it separately:

```bash
git clone https://github.com/agenticapps-eu/agenticapps-observability \
  ~/.claude/skills/agenticapps-observability
bash ~/.claude/skills/agenticapps-observability/install.sh
# Creates ~/.claude/skills/observability (canonical) +
#         ~/.claude/skills/add-observability (legacy alias)
```

For full install/usage details, see the
[`agenticapps-observability` repo's `README.md` and `install.sh`](https://github.com/agenticapps-eu/agenticapps-observability)
directly — the obs repo's README and `install.sh` are the canonical install
contract (there is no separate standalone install doc to cross-reference).

The obs installer creates both the canonical `observability` skill and a legacy
`add-observability` alias. That alias is retained through obs `0.12.0`, so the
old-name references baked into already-shipped (immutable) claude-workflow
migrations continue to resolve at runtime — no manual fixups required.

### How to upgrade

1. Install `agenticapps-observability` as above (do this **first** — the 2.0.0
   migration verifies the skill is present and aborts with install instructions
   if it is absent; it never auto-installs).
2. Run `/update-agenticapps-workflow`. The migration engine applies migration
   `0022`, repoints the observability reference, swaps in the deterministic Phase
   Sentinel hook, and bumps the project to `2.0.0`.
3. Verify: the installed skill version reads `2.0.0`, and the git tag/commit SHA
   confirms you are on the 2.0.0 baseline.
