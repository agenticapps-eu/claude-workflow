#!/bin/sh
# Fixture 02 — idempotent reapply (after state).
# Project that already has migration 0011 applied. Idempotency checks
# should all return 0 ("already applied").
set -eu
. "$FIXTURES_ROOT/common-setup.sh"

# Transform sandbox to the after-state by applying each step's effect:

# Step 1: copy scaffolder workflow into place
mkdir -p .github/workflows
cp "$HOME/.claude/skills/agenticapps-workflow/add-observability/ci/observability.yml" .github/workflows/observability.yml

# Step 2: synthesize a v0.3.0 baseline.json (canned shape)
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

# Step 3: bump observability metadata + add enforcement sub-block
# Replace spec_version line and append enforcement: block right after policy: line
awk '
  /^  spec_version: 0\.2\.1$/ { print "  spec_version: 0.3.0"; next }
  /^  policy:/ {
    print
    print "  enforcement:"
    print "    baseline: .observability/baseline.json"
    print "    ci: .github/workflows/observability.yml"
    print "    pre_commit: optional"
    next
  }
  { print }
' CLAUDE.md > CLAUDE.md.new && mv CLAUDE.md.new CLAUDE.md

# Step 4: append per-PR enforcement command line under Skills section
printf '\nObservability enforcement: `claude /add-observability scan --since-commit main` before opening a PR; CI gate enforces post-push.\n' >> CLAUDE.md

# Step 5: bump SKILL.md version
sed -i.bak 's/^version: 1.9.3$/version: 1.10.0/' .claude/skills/agentic-apps-workflow/SKILL.md
rm -f .claude/skills/agentic-apps-workflow/SKILL.md.bak
