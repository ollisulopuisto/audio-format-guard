#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_root="${TMPDIR:-/tmp}/audio-format-guard-build"
universal=false
create_zip=false
output_dir=""

if [[ "${UNIVERSAL:-false}" == "true" || "${BUILD_UNIVERSAL:-false}" == "true" ]]; then
  universal=true
fi
if [[ "${CREATE_ZIP:-false}" == "true" ]]; then
  create_zip=true
fi

for arg in "$@"; do
  case "$arg" in
    --universal)
      universal=true
      ;;
    --zip)
      create_zip=true
      ;;
    *)
      if [[ -z "$output_dir" ]]; then
        output_dir="$arg"
      fi
      ;;
  esac
done

output_dir="${output_dir:-$app_root/dist}"
app_bundle="$output_dir/Audio Format Guard.app"

mkdir -p "$build_root/module-cache" "$output_dir"

if [[ "$universal" == "true" ]]; then
  echo "Building universal release binary (arm64 + x86_64)..."
  CLANG_MODULE_CACHE_PATH="$build_root/module-cache" \
    swift build --package-path "$app_root" --scratch-path "$build_root" -c release --arch arm64 --arch x86_64
  binary_source="$build_root/apple/Products/Release/AudioFormatGuard"
else
  architecture="$(uname -m)"
  if [[ "$architecture" == "arm64" ]]; then
    swift_arch="arm64"
  else
    swift_arch="x86_64"
  fi
  echo "Building $swift_arch release binary..."
  CLANG_MODULE_CACHE_PATH="$build_root/module-cache" \
    swift build --package-path "$app_root" --scratch-path "$build_root" -c release
  binary_source="$build_root/$swift_arch-apple-macosx/release/AudioFormatGuard"
fi

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$binary_source" "$app_bundle/Contents/MacOS/AudioFormatGuard"
cp "$binary_source" "$output_dir/AudioFormatGuard"

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
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleShortVersionString</key><string>26.09.28.4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$output_dir/AudioFormatGuard"
codesign --force --sign - --deep "$app_bundle"

echo "Built binary: $output_dir/AudioFormatGuard"
echo "Built bundle: $app_bundle"

if [[ "$create_zip" == "true" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$output_dir/AudioFormatGuard.zip"
  echo "Built archive: $output_dir/AudioFormatGuard.zip"
fi

