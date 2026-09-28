#!/bin/bash
set -e

# Change directory to the folder containing this script
cd "$(dirname "$0")"

echo "================================================"
echo "  Audio Format Guard - Gatekeeper Unquarantine  "
echo "================================================"
echo ""

found=0
opened=0

# Helper function to unquarantine an app bundle
unquarantine_app() {
  local target="$1"
  if [[ -d "$target" ]]; then
    echo "Found app bundle: $target"
    xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
    chmod -R +x "$target/Contents/MacOS" 2>/dev/null || true
    found=1
    last_app="$target"
  fi
}

# Helper function to unquarantine a binary
unquarantine_bin() {
  local target="$1"
  if [[ -f "$target" ]]; then
    echo "Found executable binary: $target"
    xattr -d com.apple.quarantine "$target" 2>/dev/null || true
    chmod +x "$target" 2>/dev/null || true
    found=1
  fi
}

last_app=""

# 1. Check current directory
unquarantine_app "Audio Format Guard.app"
unquarantine_bin "AudioFormatGuard"

# 2. Check standard Applications folders
unquarantine_app "$HOME/Applications/Audio Format Guard.app"
unquarantine_app "/Applications/Audio Format Guard.app"

# 3. Check dist directory if run from repo
unquarantine_app "dist/Audio Format Guard.app"
unquarantine_bin "dist/AudioFormatGuard"

echo ""
if [[ $found -eq 1 ]]; then
  echo "✅ Quarantine attributes removed successfully!"
  echo ""
  if [[ -n "$last_app" ]]; then
    read -r -p "Would you like to open Audio Format Guard now? [Y/n] " answer
    case "$answer" in
      [nN][oO]|[nN])
        echo "Done. You can open Audio Format Guard whenever you like."
        ;;
      *)
        echo "Opening Audio Format Guard..."
        open "$last_app"
        opened=1
        ;;
    esac
  fi
else
  echo "⚠️  Could not find 'Audio Format Guard.app' or 'AudioFormatGuard'."
  echo "Place this script in the same folder as the app and run it again,"
  echo "or copy Audio Format Guard.app to /Applications or ~/Applications."
fi

echo ""
read -n 1 -s -r -p "Press any key to close..."
echo ""
