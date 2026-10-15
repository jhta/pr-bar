#!/bin/zsh
# magic.sh <on|off|toggle|status>
# Magic mode = a LaunchAgent that runs magic-tick.sh every few minutes. It is OFF unless you enable it
# here, and it expires on its own after PRBAR_MAGIC_HOURS.
source "${0:A:h}/lib.sh"
TICK="${0:A:h}/magic-tick.sh"
M="$PRBAR_STATE/magic"
LABEL="com.pr-bar.magic"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UIDN=$(id -u)

write_plist() {
cat > "$1" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$TICK</string></array>
  <key>StartInterval</key><integer>$PRBAR_MAGIC_INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$PRBAR_STATE/logs/magic-launchd.log</string>
  <key>StandardErrorPath</key><string>$PRBAR_STATE/logs/magic-launchd.log</string>
</dict></plist>
PL
}
[ "$1" = plist ] && { write_plist "$2"; exit 0; }

is_on() { [ -f "$M/enabled" ] && [ "$(cat "$M/enabled")" -gt "$(date +%s)" ]; }

on() {
  [ -n "$PRBAR_FIX_REPO" ] || { echo "Set PRBAR_FIX_REPO in $PRBAR_STATE/config"; exit 1; }
  ans=$(osascript -e "button returned of (display dialog \"Enable MAGIC MODE for $PRBAR_MAGIC_HOURS hours?\n\nIt will automatically fix merge conflicts and failing CI on your open PRs in $PRBAR_FIX_REPO, one at a time, and PUSH to their branches (max $PRBAR_MAGIC_MAX_ATTEMPTS attempts per PR). Review comments are never touched.\" buttons {\"No\",\"Yes\"} default button \"No\" cancel button \"No\" with icon caution with title \"Magic mode\")" 2>/dev/null)
  [ "$ans" = Yes ] || exit 0
  echo $(( $(date +%s) + PRBAR_MAGIC_HOURS * 3600 )) > "$M/enabled"
  mkdir -p "$HOME/Library/LaunchAgents"; write_plist "$PLIST"
  launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null
  launchctl bootstrap "gui/$UIDN" "$PLIST"
  terminal-notifier -title "🪄 Magic mode ON" -message "Until $(date -r "$(cat "$M/enabled")" +%H:%M)" >/dev/null 2>&1
}
off() {
  rm -f "$M/enabled" "$M/status"
  launchctl bootout "gui/$UIDN/$LABEL" 2>/dev/null
  rm -f "$PLIST"
  terminal-notifier -title "🪄 Magic mode OFF" -message "No more automatic fixes" >/dev/null 2>&1
}
case "$1" in
  on) on ;;
  off) off ;;
  toggle) if is_on; then off; else on; fi ;;
  status) if is_on; then echo "on until $(date -r "$(cat "$M/enabled")" +%H:%M)"; else echo off; fi ;;
  *) echo "usage: magic.sh on|off|toggle|status"; exit 2 ;;
esac
