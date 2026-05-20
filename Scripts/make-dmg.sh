#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$ROOT_DIR/build/HermesAgent.app}"
DMG="$ROOT_DIR/build/HermesAgent.dmg"
IDENTITY="${IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  echo "IDENTITY is required, for example: Developer ID Application: Your Name (TEAMID)" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg is required. Install with: npm install -g create-dmg" >&2
  exit 1
fi

rm -f "$DMG"
create-dmg \
  --volname "HermesAgent" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "HermesAgent.app" 175 190 \
  --app-drop-link 425 190 \
  --no-internet-enable \
  "$DMG" \
  "$APP"

codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [[ "${NOTARIZE_DMG:-0}" == "1" ]]; then
  : "${APPLE_ID:?APPLE_ID is required}"
  : "${TEAM_ID:?TEAM_ID is required}"
  : "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required}"
  xcrun notarytool submit "$DMG" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait
  xcrun stapler staple "$DMG"
fi

echo "Created $DMG"

