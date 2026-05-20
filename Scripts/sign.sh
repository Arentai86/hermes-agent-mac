#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$ROOT_DIR/build/HermesAgent.app}"
IDENTITY="${IDENTITY:-}"
ENTITLEMENTS="$ROOT_DIR/HermesAgent/Resources/HermesAgent.entitlements"

if [[ -z "$IDENTITY" ]]; then
  echo "IDENTITY is required, for example: Developer ID Application: Your Name (TEAMID)" >&2
  exit 1
fi

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

RUNTIME="$APP/Contents/Resources/runtime"
if [[ -d "$RUNTIME" ]]; then
  find "$RUNTIME" -type f \( -name "*.dylib" -o -name "*.node" -o -perm -111 \) -print0 |
    while IFS= read -r -d '' file; do
      codesign --force --sign "$IDENTITY" --options runtime --timestamp "$file"
    done
fi

codesign --force --deep --sign "$IDENTITY" --options runtime \
  --entitlements "$ENTITLEMENTS" --timestamp "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv -t install "$APP"

