#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_root="${TMPDIR:-/tmp}/audio-format-guard-build"
output_dir="${1:-$app_root/dist}"
app_bundle="$output_dir/Audio Format Guard.app"
architecture="$(uname -m)"
if [[ "$architecture" == "arm64" ]]; then
  swift_arch="arm64"
else
  swift_arch="x86_64"
fi

mkdir -p "$build_root/module-cache" "$output_dir"
CLANG_MODULE_CACHE_PATH="$build_root/module-cache" \
  swift build --package-path "$app_root" --scratch-path "$build_root" -c release

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$build_root/$swift_arch-apple-macosx/release/AudioFormatGuard" \
  "$app_bundle/Contents/MacOS/AudioFormatGuard"
cat > "$app_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Audio Format Guard</string>
  <key>CFBundleDisplayName</key><string>Audio Format Guard</string>
  <key>CFBundleIdentifier</key><string>fi.sulopuisto.audio-format-guard</string>
  <key>CFBundleExecutable</key><string>AudioFormatGuard</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleShortVersionString</key><string>26.09.28.2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - --deep "$app_bundle"
echo "Built: $app_bundle"
