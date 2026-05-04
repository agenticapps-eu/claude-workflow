# gsd-patches

Local patches to vanilla GSD that survive `gsd update` wipes. Adapted
from [rogs.me's pattern](https://rogs.me/2026/04/i-patched-gsd-and-why-you-should-patch-it-too/).

## Layout

```
~/.config/gsd-patches/
├── README.md          (this file)
├── CHANGELOG.md       (dated patch entries with diffs + rationale)
├── patches/           (mirror of ~/.claude/get-shit-done/ for patched files)
│   └── workflows/
│       └── review.md  (Bug 1 fix: strip 2>/dev/null from opencode run)
└── bin/
    ├── sync           (cp patched files into GSD install; idempotent)
    └── check          (cmp -s per file; exits non-zero on drift)
```

## Quick start

```bash
# After every `gsd update`, verify state and re-apply if needed:
~/.config/gsd-patches/bin/check
# If drift detected:
~/.config/gsd-patches/bin/sync
```

## Add to dotfiles

```bash
# In your dotfiles repo (chezmoi / yadm / bare git / whatever):
ln -s ~/dotfiles/.config/gsd-patches ~/.config/gsd-patches
```

Or commit `~/.config/gsd-patches/` directly into a tracked dotfiles
location.

## Override GSD install location

Default: `~/.claude/get-shit-done/`. Override:

```bash
GSD_DIR=/custom/path ~/.config/gsd-patches/bin/sync
```

## Future migration to AgenticApps migration framework

The `agenticapps-eu/claude-workflow` migration framework (v1.3.0+) handles
non-destructive upgrades for AgenticApps **projects**. It does NOT handle
patches against external skills like GSD, which is why this dotfile-based
pattern is the right tool for now. Revisit if the migration framework grows
"foreign skill patch" support.
