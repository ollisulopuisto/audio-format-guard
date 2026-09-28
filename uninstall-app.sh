#!/bin/bash
set -euo pipefail

label="fi.sulopuisto.audio-format-guard"
plist="$HOME/Library/LaunchAgents/$label.plist"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -f "$plist"
echo "Removed the Audio Format Guard login service. The app remains in ~/Applications."
