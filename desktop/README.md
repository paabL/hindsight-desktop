# Hindsight Desktop — technical guide

For installation and first steps, see the [public guide](../README.md).
This is an independent community client, with no official affiliation with
Vectorize AI, Inc. See [License](../LICENSE), [Privacy](../PRIVACY.md) and
[Third-party notices](../THIRD_PARTY_NOTICES.md).

The app uses **Tauri 2 + React / TypeScript** on macOS 15 or newer. React is the
only frontend. The existing `HindsightCore` engine is reused through a private
Swift bridge; the Rust shell provides the native connection and file dialogs.
The interface offers English and French, light and dark themes. Overview is the
initial view. Memory, Knowledge, Search, Models, Sources and Activity are visible in the
sidebar; contextual tabs organize related views, and Settings stays at the bottom.

## Development

Requires Node.js 22.18+, Xcode 16+ / Swift 6 and stable Rust. Run these commands
from `desktop/`:

```sh
npm ci
npm run dev
```

The launcher uses system Rust, or the isolated `.toolchain/` installation when
present, without changing the user's PATH. It builds the Swift bridge automatically.

```sh
npm run tauri:build -- --bundles app
```

The app is written to `src-tauri/target/release/bundle/macos/Hindsight Desktop.app`
and is not installed automatically. Its bundle identifier is
`local.hindsight.desktop.tauri`. The built app includes the native bridge and
does not need Node.js or Rust to run.

`npm run web:dev` serves only the frontend in a browser. **Explore the example**
opens explicitly labeled fictional data. Native file and server access uses Tauri.

## Features

| View | Contents |
| --- | --- |
| Overview | Bank statistics, processing status and recent documents; initial view |
| Memory → Facts | Stored bank facts and links to their original documents |
| Knowledge | Read, create, refresh and delete knowledge pages and mental models with confirmation |
| Sources | The folders that feed the selected bank; a catalog folder shows its sources, collection and upload previews |
| Search | Recall, exact text and confirmed reflect; filters and links to original documents |
| Models | Every model setting: diagram with selectors, decision switches and tooltips; accounts; all roles; installation and services |
| Memory → Documents | Stored text, facts, history, attachments, tags, scopes, reprocessing and deletion |
| Sources → a folder | File comparison with the bank, **Upload all** or a selection, confirmed uploads; automatic folder sync is suspended |
| Activity → Processing | Queued and completed work, errors, pause and resume, and confirmed processing controls |
| Activity → Usage | Traces, costs, token rates, price lists and limits |
| Memory → Timeline | Event or mention dates, search and source documents, up to 20,000 facts |
| Memory → Graph | Memory atlas, groups, bridges, two-hop neighborhoods, paths, filters and source facts |
| Activity → Logs | Read history, model traces and access logs |
| Settings → Memory behavior | Missions, extraction, consolidation, recall, disposition and previews; advanced options collapsed and flagged; Expert JSON |
| Settings → Server | Server address, launchd service, launch script, backups and logs |
| Settings → Memory bank | Banks, directives, exports, cloning, merging, imports and deletions |

Bank configuration changes use the server API. Model settings are edited in the
local launch script. Features depend on server capabilities and separately
configured local tools. Usage shows server trace counts and an editable daily cost budget.

## Architecture and protections

```text
src/                       React / TypeScript frontend
src-tauri/                 Tauri shell, private command and file dialogs
../Sources/HindsightBridge Data projections and commands to HindsightCore
../Sources/HindsightCore   API, files, costs, services and confirmations
```

The bridge is a private child process using standard input and output. It opens
no additional HTTP server. Commands are explicitly declared; the renderer has
no Node.js access, direct filesystem access or generic shell command. Tauri uses
a restrictive content security policy. Documents are rendered without raw HTML.

Server writes, deletions, generations and service operations use the engine's
`ConfirmationRequest` mechanism. The bridge requires the active confirmation ID
and any required text, then consumes that confirmation before acting. Changing
banks or servers invalidates pending confirmations. Attachments are limited to
the open document; local source reads are confined to the selected `collection/`
folder after resolving symbolic links.

Preferences use `local.hindsight.desktop`. The local usage ledger is stored at
`~/Library/Application Support/HindsightDesktop/usage-ledger.json`; it contains
counts and metadata, without prompt or response text. Collection does not run
extraction or consolidation. No memory processing starts automatically on first
launch. Usage monitoring can run while the app is open; an automatic action on
reaching a limit requires explicit authorization in the limit settings.

## Checks

```sh
npm run bridge:build
npm test
npm run build
npx playwright install chromium  # Once, for browser rendering checks
npm run test:ui
```

Bridge tests use a fake HTTP server and in-memory settings. They cover read-only
requests, reflect confirmation, non-replayable confirmations, deletion text,
file confinement and URL validation. Browser checks use fictional data without
native access and write screenshots to `screenshots/`. They do not run real
collection, consolidation, deletion, sign-in or service control.

Run the Swift suite with `swift test --disable-sandbox -c release` from the repository root,
especially after changes to caching or asynchronous work.

`npm run docs:screenshots` regenerates the public images from the current frontend
with fictional data and a mocked native host. It never connects to a user's bank
or source folder. The regular rendering tests keep their captures in `screenshots/`.

## Updates

From version 0.1.3, **Settings → Application updates → Check for updates** checks
the public beta feed. **Update and restart** downloads the offered version,
verifies its signature and installs it. No update check or download runs
automatically. Public update packages currently target macOS 15+ on Apple Silicon.
Version 0.1.2 and earlier need one manual installation of a newer build from
[Releases](https://github.com/paabL/hindsight-desktop/releases). That page also
remains the manual fallback. When an update fails, the app names the cause
(download, replacement refused by macOS, disk space) and writes the technical
detail to `~/Library/Logs/local.hindsight.desktop.tauri/updates.log`.

The Rust shell uses Tauri’s updater with a fixed HTTPS feed and embedded public
key. Update signatures are bound to the app version. The private signing key is
kept outside the repository. This free signature system is independent of Apple
Developer ID and notarization; first-install macOS approval can still be needed.
See the [release guide](../docs/RELEASE.md).

**Settings → Application updates → Build from source (advanced)** is for a local
source checkout with Node.js, Xcode and Rust installed. It builds in
`desktop/.update-target/`, validates the bundle, replaces the open app and offers
to relaunch. A modified checkout blocks remote commits; **Rebuild this copy**
can rebuild local changes after confirmation. The previous bundle is restored
if replacement fails. Downloaded source code runs with the user's permissions.

## Local sources and uploads

Each bank lists its own source folders; nothing is tracked until you add a folder.
Settings remain accessible without a connected Hindsight server. Overview summarizes
the selected bank; Sources keeps local files separate from stored memory. A folder
with a catalog opens on that catalog in the bank named by its `memory-policy.json`.
Optional collection is driven by a separately configured `collect.py` and
`projects.toml`. Filters cover project, repository, source type
and text, including original identifiers and provenance.

The manifest is displayed immediately with unchecked, locked source states.
Inventory comparison then runs in the background. Reopening Sources reuses its
displayed catalog while checking it again; initial display is not proof that the
comparison has finished. `⌘R` refreshes this comparison without collecting.
Loads and cached display data are scoped to server, bank and folder; late results
from an old context cannot replace the new view.

`internal_review` and `empty_export` records stay under **Separate archives**,
collapsed by default. They are excluded from the project's active source count.
A conversation title does not determine its classification. Filters also apply
to these readable archives.

**Refresh folder** explicitly starts collection and updates the local catalog without
contacting Hindsight. It runs in the background, with status and output available
while the user navigates. Configured collectors may contact their own source services.
Codex and Claude Code exports use Agent Dump. Source dates take priority
over archive dates, and collection-date fallbacks are labeled.

**Add documents** accepts `.md`, `.tex` and `.pdf` files and a configured project.
After confirmation, `collect.py --project ID --import-file PATH` copies originals
into `documents/<project>/` and indexes those documents only. Other collectors
are not run. Markdown is readable in the app, TeX is shown as text and PDFs open
in the local viewer. This does not extract PDFs, compile TeX or run Hindsight.
Reimporting the same path updates its copy; identical names from different paths
remain separate. Original files are kept.

**Prepare upload** compares already collected files with the selected bank and
previews additions and changes to enabled sources. It works from the catalog
even if the collector is unavailable and does not collect again. Nothing is
uploaded until **Send** is confirmed. Full text is sent with stable identifiers;
changed sources replace their stored versions. PDFs need a TeX or Markdown
source for this text-upload workflow.

**Remove from memory** requires confirmation, backs up the document, removes
it from Hindsight and excludes future uploads while keeping the local file.
Disabling a source alone keeps its stored version. Documents added by other
tools can be linked explicitly to a catalog source.

Selection and tracking state are stored per bank in
`collection/.memory-workspace.json`; resumable batches are kept in
`collection/.memory-operations/`. Interrupted uploads require an explicit resume
using the original batch identifier. This workflow does not start consolidation
or summary refreshes; automatic server processing follows the bank's settings.

**Up to date** compares the document identifier and full-text fingerprint, not
collection timestamps. Matching sources are skipped in later previews. A batch
marked complete by the server may have only queued extraction tasks; sources
remain **In progress** until memorization finishes. Failures remain visible and
require renewed approval. Legacy tracking recovery uses saved batches without
uploading again and first backs up the state to
`collection/.memory-workspace.pre-tracking-v2.json`.

Folder uploads display their selection before approval.
Automatic folder sync is suspended, including previously enabled settings.
These protections do not govern other clients or direct Hindsight API calls.

Catalog parsing and source fingerprints are cached using file identity, size,
modification time and change time. Browsing does not retain every source's full
text; upload preparation and confirmation reread the selected texts. Unchanged
snapshots reuse the catalog, while incremental snapshots update changed rows,
ordering and removals. See [Sources performance and validation](../docs/SOURCES-PERFORMANCE.md).

## Model choices and account status

The sidebar **Models** view holds every model setting around one native
launch-script draft. The diagram supports Answer, Remember, Pages and Search; the
role cards, account sign-in and installation sit under it on the same page.
Saving uses the existing diff, confirmation and backup flow. Restarting is separate.

Provider and Model dropdowns use the native catalog and configured identifiers;
Codex can also use its local public model list. The advanced **Other model…**
option allows an explicit custom identifier. Provider-specific fields appear only
for the selected provider, and cancelling the dialog leaves the draft untouched.
Account indicators use native state values: connected, disconnected, pending or
unknown; localized status text remains alongside the color.

The diagram explains roles on hover, keyboard focus and tap. Answer's return loop
requests more evidence; Search ranking and Answer decisions are independent.
Embeddings are read-only in the quick view. See the [model workflow guide](../docs/MODEL-SETTINGS.md).
