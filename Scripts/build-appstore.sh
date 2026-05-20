#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData-AppStore"
TEAM_ID="${TEAM_ID:-93727V2U64}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_NAME="${ARCHIVE_NAME:-HermesAgent-AppStore-$(date +%Y%m%d-%H%M%S).xcarchive}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$ARCHIVE_NAME}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$ROOT_DIR/appstore/HermesAgent-AppStoreExportOptions.plist}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_DIR/HermesAgent-AppStore-Export}"
EXPORT_APP="${EXPORT_APP:-1}"

cd "$ROOT_DIR"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is not available. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

plutil -lint \
  HermesAgent/Resources/Info.plist \
  HermesAgent/Resources/HermesAgent-AppStore.entitlements \
  "$EXPORT_OPTIONS" >/dev/null

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild \
  -project HermesAgent.xcodeproj \
  -scheme HermesAgent \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -disableAutomaticPackageResolution \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_ENTITLEMENTS=HermesAgent/Resources/HermesAgent-AppStore.entitlements \
  ENABLE_HARDENED_RUNTIME=YES \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  clean archive

if [ "$EXPORT_APP" = "1" ]; then
  rm -rf "$EXPORT_PATH"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH"
fi

echo "Created App Store archive: $ARCHIVE_PATH"
if [ "$EXPORT_APP" = "1" ]; then
  echo "Exported App Store package: $EXPORT_PATH"
fi
