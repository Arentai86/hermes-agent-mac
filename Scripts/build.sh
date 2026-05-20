#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"

cd "$ROOT_DIR"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is not available. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

xcodebuild \
  -project HermesAgent.xcodeproj \
  -scheme HermesAgent \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  clean build

rm -rf "$ROOT_DIR/build/HermesAgent.app"
cp -R "$DERIVED_DATA/Build/Products/$CONFIGURATION/HermesAgent.app" "$ROOT_DIR/build/HermesAgent.app"
echo "Built $ROOT_DIR/build/HermesAgent.app"

