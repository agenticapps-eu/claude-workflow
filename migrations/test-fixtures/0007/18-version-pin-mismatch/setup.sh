#!/bin/sh
. "$FIXTURES_ROOT/common-setup.sh"
# Make gitnexus report a different version
cat > "$HOME/bin/gitnexus" << 'EOF_GN'
#!/bin/sh
echo "gitnexus $*" >> "$HOME/.gn-record"
case "$1" in
  --version) echo "gitnexus 2.5.0" ;;
  *)         exit 0 ;;
esac
EOF_GN
chmod +x "$HOME/bin/gitnexus"
