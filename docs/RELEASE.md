# Release

## One-time requirements

- Apple Developer Program membership.
- Developer ID Application certificate.
- App-specific password for `notarytool`.
- Sparkle EdDSA key pair generated with Sparkle tools.
- GitHub Actions secrets:
  - `APPLE_ID`
  - `TEAM_ID`
  - `APP_SPECIFIC_PASSWORD`
  - `CERT_P12_BASE64`
  - `CERT_PASSWORD`
  - `DEVELOPER_ID_APPLICATION`
  - `SPARKLE_PRIVATE_KEY`

## Manual release

```bash
HERMES_VERSION=v0.1.0 ./Scripts/bundle-runtime.sh
./Scripts/build.sh
IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/sign.sh
APPLE_ID=... TEAM_ID=... APP_SPECIFIC_PASSWORD=... ./Scripts/notarize.sh
IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARIZE_DMG=1 ./Scripts/make-dmg.sh
SPARKLE_PRIVATE_KEY=... ./Scripts/appcast.sh
```

## GitHub release

Push a semver tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow imports the certificate, bundles runtime, builds, signs, notarizes, creates the DMG, generates Sparkle appcast metadata, and uploads artifacts to GitHub Releases.

## Troubleshooting

- If `xcodebuild` says Command Line Tools are active, select Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- If notarization passes but Gatekeeper still blocks a previous download, bump the app version and distribute a fresh artifact.
- If Node native modules fail under hardened runtime, ensure every `.node`, `.dylib`, and executable file in `Contents/Resources/runtime` is signed before the app bundle is signed.

