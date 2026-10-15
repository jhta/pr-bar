#!/bin/zsh
# pr-bar installer / updater. Safe to re-run.
#   One line (works while the repo is private, needs `gh` logged in):
#     gh api repos/jhta/pr-bar/contents/install.sh -H "Accept: application/vnd.github.raw" | zsh
set -e
SRC="$HOME/.pr-bar/src"
HERE=${0:A:h}

# Bootstrap: when piped from the one-liner there is no checkout next to us, so clone or update one.
if [ ! -f "$HERE/swiftbar/prs.2m.sh" ]; then
  command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login"; exit 1; }
  mkdir -p "$HOME/.pr-bar"
  if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only -q; else gh repo clone jhta/pr-bar "$SRC" -- -q; fi
  exec "$SRC/install.sh" "$@"
fi

PLUGINS="${1:-$HOME/SwiftBar}"
mkdir -p "$PLUGINS" "$HOME/.pr-bar"

# Dependencies (Homebrew)
if command -v brew >/dev/null; then
  for f in jq terminal-notifier; do command -v $f >/dev/null || brew install $f; done
  [ -d /Applications/SwiftBar.app ] || brew install --cask swiftbar
else
  echo "Homebrew not found; install jq, terminal-notifier and SwiftBar manually."
fi
command -v claude >/dev/null || echo "Note: 'claude' (Claude Code) not found. Status works, fix actions need it."

# Plugin + config
ln -sf "$HERE/swiftbar/prs.2m.sh" "$PLUGINS/prs.2m.sh"
new_config=0
[ -f "$HOME/.pr-bar/config" ] || { cp "$HERE/config.example" "$HOME/.pr-bar/config"; new_config=1; }

# Point SwiftBar at the plugin folder and (re)start it
defaults write com.ameba.SwiftBar PluginDirectory -string "$PLUGINS"
pkill -x SwiftBar 2>/dev/null || true
open /Applications/SwiftBar.app 2>/dev/null || true

echo "✓ pr-bar installed (plugin refreshes every 2 min; change by renaming $PLUGINS/prs.2m.sh)."
[ $new_config = 1 ] && echo "→ Edit ~/.pr-bar/config (org, repo, checkout path), then click Refresh in the menu bar."
echo "→ Update any time by re-running the install one-liner."
