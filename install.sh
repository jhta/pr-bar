#!/bin/zsh
# Symlink the SwiftBar plugin into your plugin folder and create the config.
set -e
ROOT=${0:A:h}
PLUGINS="${1:-$HOME/SwiftBar}"
mkdir -p "$PLUGINS" "$HOME/.pr-bar"
ln -sf "$ROOT/swiftbar/prs.2m.sh" "$PLUGINS/prs.2m.sh"
[ -f "$HOME/.pr-bar/config" ] || cp "$ROOT/config.example" "$HOME/.pr-bar/config"
for c in gh jq claude terminal-notifier; do command -v $c >/dev/null || echo "missing: $c"; done
[ -d /Applications/SwiftBar.app ] || echo "missing: SwiftBar (brew install --cask swiftbar)"
echo "Installed. Edit ~/.pr-bar/config, set SwiftBar's plugin folder to $PLUGINS, then Refresh."
