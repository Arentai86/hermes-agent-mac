# Development

## Local Build

```bash
./Scripts/package-dev-dmg.sh
```

The package script performs:

- project plist and scheme validation;
- shell syntax checks;
- Hermes runtime validation;
- Swift 6 typecheck;
- runtime smoke-test against `GET /api/status`;
- `arm64` and `x86_64` Swift compilation;
- `lipo` universal binary creation;
- strict ad-hoc codesign verification;
- DMG creation and mount-test.

## Refresh Bundled Hermes Runtime

```bash
HERMES_SOURCE_DIR=/path/to/hermes-agent ./Scripts/bundle-runtime.sh
./Scripts/bundle-official-skills.sh
```

The runtime script excludes local venvs, git metadata, caches, and `node_modules`; Python dependencies are created per user/architecture by the runtime runner.

## Smoke Test Runtime Only

```bash
./Scripts/smoke-test-runtime.sh
```
