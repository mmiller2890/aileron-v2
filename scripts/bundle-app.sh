#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
APP_NAME="Aileron"
BUNDLE_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

EXTRA_FLAGS=()
if [ "${SWIFT_DISABLE_SANDBOX:-0}" = "1" ]; then
  EXTRA_FLAGS+=(--disable-sandbox)
fi

if [ "$CONFIG" = "release" ]; then
  swift build -c release "${EXTRA_FLAGS[@]}" --product Aileron
  BIN_PATH="$ROOT_DIR/.build/release/Aileron"
else
  swift build -c debug "${EXTRA_FLAGS[@]}" --product Aileron
  BIN_PATH="$ROOT_DIR/.build/debug/Aileron"
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

ICON_GEN="$ROOT_DIR/scripts/generate-icon.swift"
if [ -f "$ICON_GEN" ]; then
  swift "$ICON_GEN" "$RESOURCES_DIR/AppIcon.icns"
else
  ICON_SRC="$ROOT_DIR/../src-tauri/icons/icon.icns"
  if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
  fi
fi

for bundle in "$ROOT_DIR/.build/$CONFIG"/*.bundle; do
  if [ -d "$bundle" ]; then
    cp -R "$bundle" "$RESOURCES_DIR/"
  fi
done

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Aileron</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.aileron.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Aileron</string>
    <key>CFBundleDisplayName</key>
    <string>Aileron</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>200</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.2</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aileron uses the microphone for optional push-to-talk voice questions.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Aileron taps system audio locally on your Mac to transcribe interviews and meetings in real time.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Aileron captures your active screen when you request visual Q&amp;A.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_DIR"
echo "Built bundle: $BUNDLE_DIR"
