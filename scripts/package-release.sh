#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-v2.0.0}"
BUNDLE_DIR="$ROOT_DIR/build/Aileron.app"
OUT_DIR="$ROOT_DIR/build/release"
ZIP_PATH="$OUT_DIR/Aileron-arm64.zip"
DMG_PATH="$OUT_DIR/Aileron-${VERSION}-arm64.dmg"

if [ ! -d "$BUNDLE_DIR" ] || [ "${AILERON_REBUILD:-0}" = "1" ]; then
  "$ROOT_DIR/scripts/bundle-app.sh" release
fi

codesign --verify --strict --verbose=2 "$BUNDLE_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

ditto -c -k --sequesterRsrc --keepParent "$BUNDLE_DIR" "$ZIP_PATH"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256")

STAGE_DIR="$(mktemp -d)"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

ditto "$BUNDLE_DIR" "$STAGE_DIR/Aileron.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "Aileron" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256")

echo "Packaged release artifacts in $OUT_DIR:"
ls -lh "$OUT_DIR"
