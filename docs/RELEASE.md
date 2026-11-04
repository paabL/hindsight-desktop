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
5. Attach the DMG, signed updater archive and signature, SHA-256 checksums,
   release manifest and beta feed to a GitHub prerelease. Verify the public
   downloads before publishing the feed used by installed apps. State the
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

## Build and sign

The free updater uses its own signing key, independent of Apple Developer ID.
The app embeds only the public key and requires update signatures bound to the
announced app version. Keep the private key out of source control and release
assets. On the maintainer’s Mac, it is stored in macOS Keychain under service
`io.github.paabL.hindsight-desktop.updater`, account `release-signing-key`.
For another build environment, provide `TAURI_SIGNING_PRIVATE_KEY` and, if
needed, `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` securely through the environment.
Retain a secure backup of the signing key; replacing it prevents existing
installations from trusting future updates.

To build after freezing the public sources:

```sh
cd desktop
HINDSIGHT_RELEASE_COMMIT=<full-public-commit> node scripts/package-release.mjs
```

The script applies the final ad hoc signatures before creating the updater
archive, then signs that archive with its app version. It writes the DMG,
`.app.tar.gz`, `.sig`, `SHA256SUMS.txt`, `release-manifest.json` and `beta.json`
to `desktop/release/`. It does not publish or install the app.

## Publish the beta feed last

The updater reads
`https://raw.githubusercontent.com/paabL/hindsight-desktop/main/updates/beta.json`.
This dedicated feed supports prereleases; GitHub’s `/releases/latest/` endpoint
does not serve this beta channel. The feed contains the version, exact release
asset URL and archive signature for `darwin-aarch64`.

1. Publish the release assets and verify unauthenticated downloads and checksums.
2. Verify the archive signature, version binding and installation behavior.
3. Copy the generated `beta.json` to `updates/beta.json` in the public repository
   and publish that commit only after those assets are available.
4. Check the public feed and the app’s **Check for updates** flow.

Version 0.1.2 and earlier need one manual installation of the updater-enabled
app. From version 0.1.3, users choose **Check for updates**, then **Update and
restart**. There are no automatic checks or downloads. Keep **View releases**
available as the manual fallback.
