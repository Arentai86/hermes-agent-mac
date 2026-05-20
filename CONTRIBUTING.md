# Contributing

Thanks for helping improve HermesAgent for macOS.

## Workflow

1. Open an issue for behavioral changes.
2. Keep pull requests focused.
3. Include screenshots for UI changes.
4. Include release-script notes for signing, notarization, or bundling changes.

## Local checks

```bash
plutil -lint HermesAgent/Resources/Info.plist HermesAgent/Resources/HermesAgent.entitlements
bash -n Scripts/*.sh
```

Run an Xcode build before requesting review when Xcode is available.

