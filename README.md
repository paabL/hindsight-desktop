# Hindsight Desktop

**An independent macOS client for [Hindsight](https://github.com/vectorize-io/hindsight).**
Browse local sources, search memories, choose models and manage your server in a
simple desktop interface. A free community beta under the [MIT license](LICENSE), with no
official affiliation with Vectorize AI, Inc.

[Download](https://github.com/paabL/hindsight-desktop/releases) · [User guide](docs/USER_GUIDE.md) · [Privacy](PRIVACY.md) · [Report a bug](https://github.com/paabL/hindsight-desktop/issues)

![Hindsight Desktop — model choices, decision toggle and memory workflow](docs/images/hindsight-desktop.png)

The **Models** view: choose each model directly in the diagram, switch specialized
decisions on or off, and follow the arrows through memory search and answers.
Screenshot rendered from the current interface with fictional data.

## Install

**Requires macOS 15 or newer.** Download the file for your Mac from
[Releases](https://github.com/paabL/hindsight-desktop/releases), open the DMG and
drag **Hindsight Desktop** into **Applications**. Only architectures explicitly
listed in the release are supported. No developer tools are needed to run it.

This early beta is **not notarized by Apple**. After trying to open it, macOS may
require **System Settings → Privacy & Security → Open Anyway**. Only approve a
download whose source you have verified. [Apple's instructions](https://support.apple.com/102445).
Do not disable macOS security protections.

## Get started

For the everyday workflow, see the short [user guide](docs/USER_GUIDE.md).

1. Open the app. The interface uses English by default; French is available in
   **Settings → Interface language**.
2. In **Settings → Server**, enter the address of an existing Hindsight server
   (`http://127.0.0.1:8888` for a local server). Recent features target API 1.2.0;
   availability depends on your server.
3. Choose a memory bank. **Overview** summarizes it; **Memory** shows its stored
   facts, documents, timeline and graph. **Knowledge** contains knowledge pages.
4. Open **Models** to choose the model behind each memory function. Accounts,
   every role and installation are on the same page, under the diagram. Save
   prepared changes, then restart the server separately when ready.
5. Open **Documents** and add the folders on this Mac that should feed the bank.
   Each bank has its own folders, still listed without a server. Open a folder to
   compare its files with the bank, then confirm what to upload. A folder with a
   catalog shows its collected sources first while version checks and collection
   run in the background, so you can keep navigating.
6. Use **Activity** for processing, usage and logs. Related views appear as tabs;
   connection and bank configuration stay in **Settings**.

The app **does not include the server or model weights**. Follow the
[official server setup documentation](https://hindsight.vectorize.io).
Optional local collectors require separate configuration. Model calls can incur
fees according to your server settings.

Deletions and processing actions require confirmation in the app. Your server
may send uploaded content to its configured model providers. Read
[Privacy](PRIVACY.md) before importing sensitive information.

## Help and updates

- [Report a bug](https://github.com/paabL/hindsight-desktop/issues) without private
  conversations, credentials or complete logs.
- [Report a security vulnerability privately](SECURITY.md).
- From version 0.1.3, open **Settings → Application updates → Check for updates**,
  then choose **Update and restart**. The app verifies the signed download before
  installing it. Checks and downloads start only when requested.
- Version 0.1.2 and earlier need one manual installation from
  [Releases](https://github.com/paabL/hindsight-desktop/releases) to enable in-app
  updates. Manual downloads remain available. Rebuilding from source in Settings
  is an advanced option for developers.

## Develop

Tauri 2 + React / TypeScript, with an internal Swift engine. Development requires
macOS 15+, Node.js 22.18+, Xcode 16+ / Swift 6 and stable Rust.

```sh
cd desktop
npm ci
npm run dev
```

```sh
# From the repository root
swift test
cd desktop
npm run bridge:build
npm test
npm run build
npm run tauri:build -- --bundles app,dmg
```

The bundle includes the native bridge. See the [technical guide](desktop/README.md),
[testing guide](docs/TESTING.md), [interface notes](docs/UI.md) and
[third-party notices](THIRD_PARTY_NOTICES.md).
The [model workflow guide](docs/MODEL-SETTINGS.md) explains role selection and
decision loops; the [Sources performance notes](docs/SOURCES-PERFORMANCE.md)
describe loading, validation and measured results.
API models are generated from `docs/openapi.json`.
