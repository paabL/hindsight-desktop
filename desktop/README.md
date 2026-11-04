# Hindsight Desktop — technical guide

For installation and first steps, see the [public guide](../README.md).
This is an independent community client, with no official affiliation with
Vectorize AI, Inc. See [License](../LICENSE), [Privacy](../PRIVACY.md) and
[Third-party notices](../THIRD_PARTY_NOTICES.md).

The app uses **Tauri 2 + React / TypeScript** on macOS 15 or newer. React is the
only frontend. The existing `HindsightCore` engine is reused through a private
Swift bridge; the Rust shell provides the native connection and file dialogs.
The interface offers English and French, light and dark themes. Memory is the
home view; specialized tools are grouped under Advanced.

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
| Memory | Local sources and Hindsight documents, version status, source selection, collection and upload previews |
| Summaries | Read, create, refresh and delete summaries with confirmation |
| Search | Recall, exact text and confirmed reflect; filters and links to original documents |
| Document reader | Stored text, facts, history, attachments, tags, scopes, reprocessing and deletion |
| Folder coverage | File coverage, selection and confirmed uploads; automatic folder sync is suspended |
| Usage | Traces, costs, token rates, subscription quota checks, price lists, limits and processing controls |
| Overview | Statistics, fact types, queues and recent documents |
| Timeline | Event or mention dates, search and source documents, up to 20,000 facts |
| Graph | Memory atlas, groups, bridges, two-hop neighborhoods, paths, filters and source facts |
| Activity & reads | Read history, model traces and access logs |
| Memory structure | Missions, extraction, consolidation, recall, disposition, advanced settings and previews |
| Server & models | launchd service, model roles, official sign-in clients, changes, backups and logs |
| Administration | Banks, directives, exports, cloning, merging, imports, sync previews and deletions |
| Import Hermes | Session previews and confirmed imports |

Bank configuration changes use the server API. Model settings are edited in the
local launch script. Features depend on server capabilities and separately
configured local tools. Quota checks require an explicit confirmed request in
Usage; the app does not enable automatic credential access for these checks.

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

Run the Swift suite with `swift test` from the repository root.

## Updates

Downloaded builds are updated by installing a new version from
[Releases](https://github.com/paabL/hindsight-desktop/releases).
**Settings → Application updates → Build from source (advanced)** is for a local
source checkout with Node.js, Xcode and Rust installed. It builds in
`desktop/.update-target/`, validates the bundle, replaces the open app and offers
to relaunch. A modified checkout blocks remote commits; **Rebuild this copy**
can rebuild local changes after confirmation. The previous bundle is restored
if replacement fails. Downloaded source code runs with the user's permissions.

## Local sources and uploads

At first launch, the memory folder is selected explicitly. Settings remain
accessible without a connected Hindsight server. The home view reads the chosen
folder's catalog. Optional collection is driven by a separately configured
`collect.py` and `projects.toml`. Filters cover project, repository, source type
and text, including original identifiers and provenance.

`internal_review` and `empty_export` records stay under **Separate archives**,
collapsed by default. They are excluded from the project's active source count.
A conversation title does not determine its classification. Filters also apply
to these readable archives.

**Refresh folder** runs collection and updates the local catalog without
contacting Hindsight. Collection requires confirmation. Codex and Claude Code
exports use Agent Dump; Hermes imports are separate. Source dates take priority
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

Advanced project sync previews list document IDs. `sync.py` binds approval to
the plan's exact content and metadata; changing the plan or script requires a
new preview. Its queue must be readable and empty at preparation and confirmation.
Folder uploads and Hermes imports also display their selection before approval.
Automatic folder sync is suspended, including previously enabled settings.
These protections do not govern other clients or direct Hindsight API calls.
