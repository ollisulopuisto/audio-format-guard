#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_app="$app_root/dist/Audio Format Guard.app"
destination="$HOME/Applications/Audio Format Guard.app"
label="fi.sulopuisto.audio-format-guard"
plist="$HOME/Library/LaunchAgents/$label.plist"
legacy_label="fi.sulopuisto.denon-audio-format-watcher"
legacy_plist="$HOME/Library/LaunchAgents/$legacy_label.plist"

if [[ ! -d "$source_app" ]]; then
  echo "Build the app first: $app_root/build-app.sh" >&2
  exit 1
fi

mkdir -p "$HOME/Applications" "$(dirname "$plist")"
# Clean up legacy single-device watcher if present
if [[ -f "$legacy_plist" ]]; then
  launchctl bootout "gui/$(id -u)/$legacy_label" 2>/dev/null || true
  rm -f "$legacy_plist"
  echo "Cleaned up legacy watcher LaunchAgent ($legacy_label)."
fi
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
/usr/bin/osascript -e 'tell application id "fi.sulopuisto.audio-format-guard" to quit' 2>/dev/null || true
sleep 1
ditto "$source_app" "$destination"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/open</string><string>-a</string><string>$destination</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl kickstart "gui/$(id -u)/$label"
echo "Installed and started: $destination"
