#!/bin/sh
# Sourced by individual fixture setup.sh scripts.
# Builds a sandbox with stubbed node + npm + gitnexus + jq (if available on host).

# Baseline SKILL.md at 1.9.2
mkdir -p "$HOME/.claude/skills/agentic-apps-workflow"
cat > "$HOME/.claude/skills/agentic-apps-workflow/SKILL.md" <<EOF_SKILL
---
name: agentic-apps-workflow
version: 1.9.2
---
EOF_SKILL

# Stub bin dir
mkdir -p "$HOME/bin"
# node stub (reports version 18)
cat > "$HOME/bin/node" << 'EOF_NODE'
#!/bin/sh
case "$1" in
  -p|--print) echo "18" ;;
  -e|--eval)  exit 0 ;;
  *)          echo "v18.20.0" ;;
esac
EOF_NODE
chmod +x "$HOME/bin/node"
# npm stub (no-op but exits 0)
cat > "$HOME/bin/npm" << 'EOF_NPM'
#!/bin/sh
exit 0
EOF_NPM
chmod +x "$HOME/bin/npm"
# gitnexus stub: records invocation args + exits 0
cat > "$HOME/bin/gitnexus" << 'EOF_GN'
#!/bin/sh
echo "gitnexus $*" >> "$HOME/.gn-record"
case "$1" in
  --version) echo "gitnexus 2.4.0" ;;
  mcp)       exit 0 ;;
  analyze)   exit 0 ;;
  *)         exit 0 ;;
esac
EOF_GN
chmod +x "$HOME/bin/gitnexus"

# Path prefix for the install script
export PATH="$HOME/bin:$PATH"
