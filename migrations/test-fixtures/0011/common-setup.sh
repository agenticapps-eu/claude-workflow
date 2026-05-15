#!/bin/sh
# Sourced by individual fixture setup.sh scripts for migration 0011.
# Builds a sandbox $HOME with:
#   - scaffolder skill tree at ~/.claude/skills/agenticapps-workflow/
#   - stubbed claude + jq + shasum binaries in ~/bin
#   - per-fixture project directory at $PWD (= $tmp dir)
set -eu

SCAFFOLDER_DIR="$HOME/.claude/skills/agenticapps-workflow"

# 1. Stub scaffolder layout (the bits migration 0011 references).
#    Migration 0011 in v1.10.0 (local-only enforcement) only references
#    scan/SCAN.md — the CI workflow at enforcement/observability.yml.example
#    is NOT installed by the migration, so we don't need to stub it for
#    fixture state. If REAL_SCAFFOLDER_FILES=1 (set by the runner), the
#    runner pre-populated scan/SCAN.md with the real file shipped by this
#    branch.
mkdir -p "$SCAFFOLDER_DIR/add-observability/scan"

# Scaffolder SKILL.md frontmatter at 0.3.0 (required for migration's
# add-observability skill verify check)
cat > "$SCAFFOLDER_DIR/add-observability/SKILL.md" <<'EOF_SKILL'
---
name: add-observability
version: 0.3.0
implements_spec: 0.3.0
---
EOF_SKILL

if [ "${REAL_SCAFFOLDER_FILES:-0}" != "1" ]; then
  # Fallback stub when invoked without the runner (e.g. for local manual
  # fixture inspection). Real runs use the actual scan/SCAN.md file.
  cat > "$SCAFFOLDER_DIR/add-observability/scan/SCAN.md" <<'EOF_SCAN'
# scan stub for fixture sandbox
EOF_SCAN
fi

# 2. Stub bin dir
mkdir -p "$HOME/bin"

# claude stub: when called with `/add-observability scan --update-baseline`,
# writes a canned .observability/baseline.json into the project (CWD).
cat > "$HOME/bin/claude" <<'EOF_CLAUDE'
#!/bin/sh
# Stub that records every invocation and writes a canned baseline when
# asked to run /add-observability scan --update-baseline.
echo "claude $*" >> "$HOME/.claude-record"
case "$*" in
  *"/add-observability scan --update-baseline"*)
    mkdir -p .observability
    cat > .observability/baseline.json <<'EOF_BL'
{
  "spec_version": "0.3.0",
  "scanned_at": "2026-05-15T00:00:00Z",
  "scanned_commit": "0000000000000000000000000000000000000001",
  "module_roots": [],
  "counts": {
    "conformant": 0,
    "high_confidence_gaps": 0,
    "medium_confidence_findings": 0,
    "low_confidence_findings": 0
  },
  "high_confidence_gaps_by_checklist": {
    "C1": 0, "C2": 0, "C3": 0, "C4": 0
  },
  "policy_hash": "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}
EOF_BL
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF_CLAUDE
chmod +x "$HOME/bin/claude"

# Build a v1.9.3 project skeleton inside the sandbox CWD.
# Caller is expected to be `cd`'d into $tmp; we drop the project files
# at the working directory.
mkdir -p .claude/skills/agentic-apps-workflow
cat > .claude/skills/agentic-apps-workflow/SKILL.md <<'EOF_PROJ_SKILL'
---
name: agentic-apps-workflow
version: 1.9.3
---
EOF_PROJ_SKILL

# Default CLAUDE.md with an observability metadata block at v0.2.1
cat > CLAUDE.md <<'EOF_CLAUDE_MD'
# Project

## Observability

observability:
  spec_version: 0.2.1
  destinations:
    - errors: sentry
  policy: lib/observability/policy.md

## Skills

- /gsd-review
EOF_CLAUDE_MD

# Default policy.md (so the policy.md pre-condition passes)
mkdir -p lib/observability
cat > lib/observability/policy.md <<'EOF_POLICY'
# Observability policy

## Trivial errors
- pgx.ErrNoRows
EOF_POLICY

# Set PATH so the migration's `claude`/`jq` lookups resolve to our stubs.
# jq is expected on the host; if not, the migration aborts. We don't stub jq
# (it's a runtime tool, not something we want to simulate the output of).
export PATH="$HOME/bin:$PATH"
