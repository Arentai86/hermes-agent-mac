#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$ROOT_DIR/build/HermesAgent.app}"
ZIP="$ROOT_DIR/build/HermesAgent.zip"

: "${APPLE_ID:?APPLE_ID is required}"
: "${TEAM_ID:?TEAM_ID is required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD is required}"

ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

