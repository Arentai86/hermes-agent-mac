#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP="$BUILD_DIR/test/HermesAgent.app"
STAGING="$BUILD_DIR/dmg-staging"
DMG_NAME="${DMG_NAME:-HermesAgent-dev-tested.dmg}"
DMG="$BUILD_DIR/$DMG_NAME"
VERSION="${VERSION:-0.1.0-test}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="$BUILD_DIR/module-cache"
ARCH_BUILD_DIR="$BUILD_DIR/arch"

cd "$ROOT_DIR"

echo "Keeping existing DMG files until the new image is verified"
mkdir -p "$BUILD_DIR"

echo "Validating project metadata"
plutil -lint \
  HermesAgent.xcodeproj/project.pbxproj \
  HermesAgent/Resources/Info.plist \
  HermesAgent/Resources/HermesAgent.entitlements >/dev/null
xmllint --noout HermesAgent.xcodeproj/xcshareddata/xcschemes/HermesAgent.xcscheme
bash -n Scripts/*.sh

echo "Validating bundled Hermes runtime"
test -x HermesAgent/Resources/runtime/bin/run-hermes-dashboard.sh
test -f HermesAgent/Resources/runtime/server/hermes
test -f HermesAgent/Resources/runtime/server/pyproject.toml
test -f HermesAgent/Resources/runtime/server/hermes_cli/web_dist/index.html
test -d HermesAgent/Resources/skills
test "$(find HermesAgent/Resources/skills -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')" -gt 0

echo "Typechecking Swift 6 sources"
mkdir -p "$MODULE_CACHE"
env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" xcrun --sdk macosx swiftc \
  -swift-version 6 \
  -typecheck \
  HermesAgent/App/*.swift \
  HermesAgent/Server/*.swift \
  HermesAgent/Runtime/*.swift \
  HermesAgent/Wizard/*.swift \
  HermesAgent/Wizard/Steps/*.swift \
  HermesAgent/MenuBar/*.swift \
  HermesAgent/Preferences/*.swift \
  HermesAgent/Updates/*.swift \
  HermesAgent/Storage/*.swift \
  HermesAgent/Uninstall/*.swift

echo "Creating app bundle"
rm -rf "$BUILD_DIR/test" "$STAGING" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R HermesAgent/Resources/runtime "$APP/Contents/Resources/runtime"
cp -R HermesAgent/Resources/skills "$APP/Contents/Resources/skills"
cp HermesAgent/Resources/HermesAgent.icns "$APP/Contents/Resources/HermesAgent.icns"
cp HermesAgent/Resources/OpenzenMark.png "$APP/Contents/Resources/OpenzenMark.png"
cp HermesAgent/Resources/Info.plist "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable HermesAgent" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.hermes.app" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile HermesAgent" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Hermes Agent" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Hermes Agent" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

echo "Smoke-testing app-bundled runtime"
TEST_PORT="$(ruby -rsocket -e 's = TCPServer.new("127.0.0.1", 0); puts s.addr[1]; s.close')"
TEST_HOME="$BUILD_DIR/hermes-smoke-home"
rm -rf "$TEST_HOME"
mkdir -p "$TEST_HOME"
"$APP/Contents/Resources/runtime/bin/run-hermes-dashboard.sh" \
  --port "$TEST_PORT" \
  --data-dir "$TEST_HOME" >"$BUILD_DIR/runtime-smoke.log" 2>&1 &
SERVER_PID=$!
cleanup_server() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  wait "$SERVER_PID" >/dev/null 2>&1 || true
}
trap cleanup_server EXIT

for _ in {1..2400}; do
  if curl -fsS "http://127.0.0.1:$TEST_PORT/api/status" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "Hermes runtime exited early:" >&2
    cat "$BUILD_DIR/runtime-smoke.log" >&2 || true
    exit 1
  fi
  sleep 0.25
done
curl -fsS "http://127.0.0.1:$TEST_PORT/api/status" >/dev/null
curl -fsS "http://127.0.0.1:$TEST_PORT/" >/dev/null
cleanup_server
trap - EXIT

echo "Compiling app executable"
rm -rf "$ARCH_BUILD_DIR"
mkdir -p "$ARCH_BUILD_DIR" "$MODULE_CACHE/arm64" "$MODULE_CACHE/x86_64"

compile_arch() {
  local arch="$1"
  local target="$2"
  local output="$ARCH_BUILD_DIR/HermesAgent-$arch"
  echo "Compiling $arch"
  find HermesAgent -name "*.swift" -print0 | xargs -0 xcrun --sdk macosx swiftc \
    -swift-version 6 \
    -target "$target" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE/$arch" \
    -parse-as-library \
    -O \
    -o "$output"
}

compile_arch arm64 arm64-apple-macosx13.0
compile_arch x86_64 x86_64-apple-macosx13.0
lipo -create "$ARCH_BUILD_DIR/HermesAgent-arm64" "$ARCH_BUILD_DIR/HermesAgent-x86_64" \
  -output "$APP/Contents/MacOS/HermesAgent"
chmod +x "$APP/Contents/MacOS/HermesAgent"
lipo -info "$APP/Contents/MacOS/HermesAgent"

echo "Signing app ad-hoc"
codesign --force --deep --sign - --entitlements HermesAgent/Resources/HermesAgent.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Creating DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/HermesAgent.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Hermes Agent Test" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "Mount-testing DMG"
MOUNT_INFO="$(hdiutil attach "$DMG" -nobrowse -readonly)"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_INFO" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"
test -d "$MOUNT_POINT/HermesAgent.app"
test -L "$MOUNT_POINT/Applications"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT_POINT/HermesAgent.app/Contents/Info.plist")" = "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$MOUNT_POINT/HermesAgent.app/Contents/Info.plist")" = "Hermes Agent"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$MOUNT_POINT/HermesAgent.app/Contents/Info.plist")" = "HermesAgent"
test -f "$MOUNT_POINT/HermesAgent.app/Contents/Resources/HermesAgent.icns"
test -f "$MOUNT_POINT/HermesAgent.app/Contents/Resources/OpenzenMark.png"
test -x "$MOUNT_POINT/HermesAgent.app/Contents/Resources/runtime/bin/run-hermes-dashboard.sh"
test -f "$MOUNT_POINT/HermesAgent.app/Contents/Resources/runtime/server/hermes_cli/web_dist/index.html"
test "$(find "$MOUNT_POINT/HermesAgent.app/Contents/Resources/skills" -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')" -gt 0
hdiutil detach "$MOUNT_POINT"

echo "Cleaning packaging intermediates"
rm -rf "$BUILD_DIR/test" "$STAGING" "$BUILD_DIR/runtime-smoke.log" "$TEST_HOME" "$MODULE_CACHE" "$ARCH_BUILD_DIR"

echo "Created $DMG"
ls -lh "$DMG"
