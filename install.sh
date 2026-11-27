#!/usr/bin/env bash
set -euo pipefail

REPO="mmiller2890/aileron-v2"
ASSET_NAME="Aileron-arm64.zip"
CHECKSUM_NAME="Aileron-arm64.zip.sha256"
VERSION="${AILERON_VERSION:-latest}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: Aileron requires macOS 14.2+ on Apple Silicon." >&2
  exit 1
fi

if [ "$(uname -m)" != "arm64" ]; then
  echo "Error: Aileron requires an Apple Silicon Mac (M1 / M2 / M3 / M4)." >&2
  exit 1
fi

OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
OS_REST="${OS_VER#*.}"
OS_MINOR="${OS_REST%%.*}"
if [ "$OS_MAJOR" -lt 14 ] || { [ "$OS_MAJOR" -eq 14 ] && [ "$OS_MINOR" -lt 2 ]; }; then
  echo "Error: Aileron requires macOS 14.2 Sonoma or newer (detected $OS_VER)." >&2
  exit 1
fi

if [ "$VERSION" = "latest" ]; then
  BASE_URL="https://github.com/$REPO/releases/latest/download"
else
  BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading Aileron ($VERSION) for Apple Silicon..."
curl -fL --progress-bar "$BASE_URL/$ASSET_NAME" -o "$TMP_DIR/$ASSET_NAME"
curl -fsSL "$BASE_URL/$CHECKSUM_NAME" -o "$TMP_DIR/$CHECKSUM_NAME"

echo "Verifying SHA-256 checksum..."
EXPECTED_SHA="$(awk '{print $1}' "$TMP_DIR/$CHECKSUM_NAME")"
ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/$ASSET_NAME" | awk '{print $1}')"
if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
  echo "Error: Checksum mismatch! Expected $EXPECTED_SHA, got $ACTUAL_SHA." >&2
  exit 1
fi

echo "Extracting Aileron.app..."
ditto -xk "$TMP_DIR/$ASSET_NAME" "$TMP_DIR/extracted"
SRC_APP="$TMP_DIR/extracted/Aileron.app"
if [ ! -d "$SRC_APP" ]; then
  echo "Error: Aileron.app not found in release archive." >&2
  exit 1
fi

codesign --verify --strict "$SRC_APP"

if osascript -e 'application "Aileron" is running' 2>/dev/null | grep -qi true; then
  echo "Closing running Aileron instance..."
  osascript -e 'tell application "Aileron" to quit' >/dev/null 2>&1 || true
  sleep 1
fi

if [ -w "/Applications" ]; then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
  mkdir -p "$INSTALL_DIR"
fi

DEST_APP="$INSTALL_DIR/Aileron.app"
rm -rf "$DEST_APP"
ditto "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" >/dev/null 2>&1 || true

echo ""
echo "Installed Aileron to $DEST_APP"
echo "Launching Aileron..."
open "$DEST_APP"
echo ""
echo "First run tips:"
echo "  1. Grant System Audio & Microphone permissions in the guided setup sheet."
echo "  2. Open Models & Speech to pick Ollama (local) or add an OpenAI / Anthropic / Gemini / Groq API key."
echo "  3. Click Listen — Parakeet speech models (~1.2 GB) download once on first use."
