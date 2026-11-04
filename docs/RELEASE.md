# Release a macOS beta

Public repository: `paabL/hindsight-desktop`. Keep the development repository
private and export only reviewed source files. Preserve the public history when
publishing updates. Exclude `.git`,
`.claude`, personal data, real-data screenshots, build folders, `node_modules`,
local toolchains and secrets from the export.

1. Verify Swift tests, the native bridge, frontend tests, rendering and the
   TypeScript build. Open the bundle with test settings and no personal data.
2. Regenerate notices after dependency changes. Include LICENSE, NOTICE,
   Privacy and the complete third-party notices in the distribution.
3. Build for the advertised architecture. The included Swift bridge must match
   the app. Do not advertise Intel support without a tested Intel bundle.
4. Without an Apple Developer account, clearly label the release an
   **unnotarized beta**. An ad hoc signature does not verify publisher identity.
   Explain the per-app approval in System Settings. Never ask users to disable
   Gatekeeper or remove quarantine globally.
5. Attach the DMG and its SHA-256 checksum to a GitHub prerelease. State the
   version, minimum macOS, supported architecture, required server, checks that
   actually passed and known limitations. Keep public documentation and release
   notes in English; French remains an option inside the app.
6. Enable private vulnerability reporting and verify the public download links.
   Coordinate upstream announcements with the maintainer before posting. Use
   the [official community channels](UPSTREAM.md) and do not imply affiliation.

Apple-verified distribution can be added later with a Developer ID Application
certificate, signatures for the bridge and app, notarization and ticket stapling.
References: [Tauri macOS signing](https://v2.tauri.app/distribute/sign/macos/),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Apple app-opening instructions](https://support.apple.com/102445).

To build the free DMG after freezing the public sources:

```sh
cd desktop
HINDSIGHT_RELEASE_COMMIT=<full-public-commit> node scripts/package-release.mjs
```

The package, checksum and manifest are written to `desktop/release/`.
The script does not publish or install the app.
