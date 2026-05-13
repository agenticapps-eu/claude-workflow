#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
cat > "$HOME/bin/node" << 'EOF_NODE'
#!/bin/sh
case "$1" in
  -p|--print) echo "16" ;;
  *)          echo "v16.20.0" ;;
esac
EOF_NODE
chmod +x "$HOME/bin/node"
