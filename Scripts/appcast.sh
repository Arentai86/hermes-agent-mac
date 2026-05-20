#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${DMG:-$ROOT_DIR/build/HermesAgent.dmg}"
APPCAST_DIR="${APPCAST_DIR:-$ROOT_DIR/build/appcast}"
SPARKLE_BIN="${SPARKLE_BIN:-/Applications/Sparkle/bin}"

: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"

mkdir -p "$APPCAST_DIR"
cp "$DMG" "$APPCAST_DIR/"

"$SPARKLE_BIN/generate_appcast" \
  --ed-key-file <(printf "%s" "$SPARKLE_PRIVATE_KEY") \
  "$APPCAST_DIR"

echo "Generated $APPCAST_DIR/appcast.xml"

