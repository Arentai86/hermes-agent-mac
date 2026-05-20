# Hermes Agent Mac Implementation Report

Date: 2026-05-19

## Result

- Project: `/Users/artem/Projects 2/hermes-agent-mac`
- DMG: `/Users/artem/Projects 2/hermes-agent-mac/build/HermesAgent-dev-tested.dmg`
- Version: `0.1.0-test`
- Size: `67 MB`
- SHA-256: `3354d16b4850848415410533de74f448e50c884848adebea6427893d13856dfb`

## Implemented

- Created a separate Hermes Agent macOS launcher project in `Projects 2`.
- Replaced OpenClaw naming with Hermes Agent in the app bundle, menu bar launcher, docs, scripts, and project metadata.
- Generated `.icns` app assets from `/Users/artem/Desktop/001.png`.
- Bundled Hermes Agent server source from the local Hermes checkout.
- Bundled 166 Hermes Agent skills into `HermesAgent/Resources/skills`.
- Switched the default local dashboard port to `9119`.
- Replaced Node/OpenClaw launch with `run-hermes-dashboard.sh`.
- Added runtime bootstrap for Apple Silicon and Intel:
  - uses an existing Python 3.11+ environment when usable;
  - otherwise installs `uv` into Application Support and creates a per-user venv;
  - copies read-only bundled source into writable Application Support before editable install.
- Removed non-portable Homebrew venv and stale `node_modules` symlink noise from the app bundle.

## Verification

- Swift 6 typecheck passed.
- Runtime smoke-test passed against `GET /api/status`.
- Universal binary verified with `lipo`: `x86_64 arm64`.
- Strict ad-hoc codesign verification passed.
- `hdiutil verify` passed.
- DMG mount-test passed.
- Independent read-only mounted DMG runtime test passed:
  - app mounted from `/Volumes/Hermes Agent Test/HermesAgent.app`;
  - strict codesign passed;
  - no broken runtime symlinks found;
  - dashboard answered `/api/status` on localhost.

## Notes

- This is a development/testing DMG with ad-hoc signing.
- Public distribution still requires Developer ID signing and Apple notarization.
- On a clean Mac, first Hermes dashboard launch can take longer because Python/uv/dependencies may be bootstrapped into `~/Library/Application Support/Hermes Agent/runtime`.

## 2026-05-20 repack after user edits

- Preserved the old `HermesAgent.dmg` until the new image passed verification.
- Updated `Scripts/package-dev-dmg.sh` so it does not delete existing `*.dmg` files at the beginning of packaging.
- Built a fresh verified image: `/Users/artem/Projects 2/hermes-agent-mac/build/HermesAgent-20260520-verified.dmg`.
- Removed the old DMG only after the new image passed verification.
- Verification passed:
  - plist and Xcode scheme validation
  - shell script syntax checks
  - Hermes runtime layout validation
  - Swift 6 typecheck
  - app-bundled runtime smoke test
  - universal `arm64 + x86_64` build
  - strict ad-hoc codesign verification
  - `hdiutil verify`
  - read-only DMG mount inspection
  - mounted runtime `/api/status` check
  - 166 bundled Hermes skills
- Current verified DMG: `/Users/artem/Projects 2/hermes-agent-mac/build/HermesAgent-20260520-verified.dmg`
- Current verified DMG version: `0.1.0-test` build `1`
- Current DMG SHA-256: `10849bb478aace6361d23f1defe0058d04aae32931bab2a2268370ce326df8f3`
