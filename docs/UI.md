# Hindsight Desktop interface

The app's only frontend lives in `desktop/src/`: React, TypeScript, and CSS inside
Tauri. The former SwiftUI targets and stub-based UI checks have been removed.

## Visual design

- Cool surfaces with petroleum blue, eucalyptus, and indigo accents distinguish
  navigation, categories, and status.
- System typography, clear hierarchy, subtle borders, and restrained corner radii.
- Amber identifies decision steps and pending states; color communicates function
  or status rather than decoration. Status text remains available alongside color.
- Dark and light themes, with the choice saved on the device.
- Source data, provenance, and processing status take priority.

Design tokens live in `desktop/src/tokens.css`. Shared buttons, cards, badges,
errors, dialogs, and typography live in `desktop/src/ui.tsx`.

## Simple by default, fine control kept

Every view follows the same rules. Check a new screen or setting against them:

- **One page answers one question** and carries at most one primary action.
  Navigation stays in the sidebar and tabs, not in page buttons.
- **One place per thing.** Everything about models is in **Models**; the server's
  address, service, launch script, backups and log are in **Settings → Server**.
  The same number, button or description is not repeated on a page.
- **Essentials visible, details one click away on the same page.** Fine settings
  sit in a collapsed **Advanced options** section that flags changed values and
  values specific to the bank, with a way back to the defaults. Nothing useful is
  removed to simplify a page.
- **The user's words first.** Server vocabulary appears only in help text.
- **Frequent actions take one click** (for example **Upload all**), while a precise
  selection stays possible.

## Navigation and language

The sidebar has seven primary groups. The first six show the selected bank:
**Overview**, **Memory**, **Knowledge**, **Search**, **Sources** and **Activity**.
**Models** concerns the server rather than one bank, so it sits below a thin line
at the bottom of the sidebar, next to Settings. Overview is the initial view. All
views are visible through these groups; there is no Advanced navigation section.

| Group | Views |
| --- | --- |
| Overview | Bank statistics, processing status and recent documents |
| Memory | Facts, Documents, Timeline, Graph |
| Knowledge | Knowledge pages and mental models |
| Search | Recall, exact text and confirmed reflect |
| Models | The model behind each memory function: diagram, accounts, every role and installation |
| Sources | The folders on this Mac that feed the selected bank |
| Activity | Processing, Usage, Logs |
| Settings | Application, Memory bank, Memory behavior, Server |

Groups with several views show a named tab bar above the page heading. A group
click returns to its last selected tab. The Settings shortcut opens Application. Existing hash links remain valid; in
particular, `#memory` still opens Memory behavior, while `#facts` opens the
bank's facts. `#model-settings` opens Models without requiring a bank; `#models` still opens Knowledge. Browser back and forward update the view and active group together.
The command palette lists every view and searches group and view names without
requiring accents.

The public interface defaults to English. French is an explicit choice in
Settings → Application → Language. Documents, source text, and content returned
by the server keep their original language.

**Memory** presents knowledge stored in the selected Hindsight bank. **Sources**
lists the folders on this Mac that feed that bank, each with a one-line summary,
and a single **Add a folder** action. Each bank has its own list; the same folder
can feed several banks, each with its own status. Without a server, the list of
the last selected bank stays readable. Clicking a folder opens it:

- An **ordinary folder** shows its files compared with the bank's documents.
  **Upload all** sends every file that is not sent, modified or without facts.
  Selecting files turns it into **Upload (n)** and shows **Remove from memory** for
  the selection. Every upload is confirmed. Only documents are compared unless the
  folder includes all text files.
- A **folder with a catalog** (`catalog.json`, gathered by its `collect.py`
  collector) shows its catalog: projects, collectors, source families, filters,
  and a reader with provenance. It belongs to the bank named in its
  `memory-policy.json`; there, it feeds the bank only through its catalog. In any
  other bank it is an ordinary folder. A catalog without a declared bank joins the
  bank of its first upload.

Opening a folder, switching banks or removing the open folder returns to the
list. A folder that disappeared from the Mac cannot be opened; it can only stop
being tracked. Sources never tracks, collects or uploads a folder on navigation.

A catalog first displays its manifest with unchecked, locked entries, then compares
the existing files with the bank in the background. Cached navigation keeps the
list visible on return. Collection also runs in the background with progress and
output available. **Refresh folder** collects; the top-bar refresh only rechecks
the catalog and memory. A reader stays open when inclusion changes, and late text
responses cannot replace the newly selected source.

If a catalog loses its `catalog.json` while open, the page says so neutrally,
hides collection controls and empty statistics, and returns to the list, where the
folder now appears as an ordinary folder. Loading is shown before the folder list
arrives, never an empty list. Sidebar numbers use the `⌘` prefix to identify
keyboard shortcuts.

**Facts** has a single search over the whole bank: words apply when submitted,
the type applies at once, and the line under the search says what is shown, with
**Clear search**. The Timeline searches the bank the same way.

**Knowledge** lists knowledge pages, kept up to date by the server, and mental
models, which follow a question you ask. Each card names its kind.

**Processing** carries the pause: **Pause** or **Resume processing** for the
selected bank. **More processing options** (⋯) applies the pause to all banks,
freezes the server queue or clears pending operations. **Retry failed operations**
and **Reconsolidate** appear only when there is something to retry.

Processing keeps its selected status during automatic refreshes and preserves
opened pages. Large lists render in groups of 100 with **Load more**; this does
not impose a total-operation limit. Global status counts are distinguished from
counts based only on loaded rows. They use current operation-list totals rather
than the server's cached bank statistics, so retrying failures updates the summary
and filtered list together. Counter reads request at most one row per status;
a completely loaded bank list needs no extra reads. If a counter read fails, the summary
explicitly falls back to the loaded operations.

## Models and accounts

**Models** is the only place for model settings. At the top, its Answer, Remember,
Pages and Search tabs show colored roles connected by arrows, including the return
path when more evidence is needed. Each role explains itself on hover, focus or
tap. Model menus and the decision switch prepare changes in a shared draft.
Embeddings remain read-only in the diagram. Save and server restart are separate
actions.

Under the diagram, on the same page: account connections, then two collapsed
sections. **All roles and advanced settings** has one card per role for providers,
keys, endpoints and custom models; the diagram's settings buttons open the same
role. **Model installation and services** installs, starts and stops Hindsight
models on this Mac or connects Hindsight Cloud. Provider and Model use dropdowns,
and changing the provider updates the model choices. Custom identifiers require
the explicit advanced **Other model…** option. Cancelling a dialog discards its
local edits.

**Memory behavior** (Settings) shows the essentials of each tab. The rest is in
**Advanced options**, which opens by itself when it holds unsaved changes and
otherwise shows how many values are specific to the bank. **Save (n)** counts the
changes, **Discard changes** drops them, and **Reset to server settings** removes
every value specific to the bank. The **Expert** tab keeps the raw JSON.

Account indicators show green for an available session or signed-in account,
red for disconnected/unavailable/failed, amber for checking or connecting, and
gray for unchecked. Availability is distinct from a successful model call or a
quota check. The adjacent text describes the state without relying on color.

Documents open a reader with text, facts, history, and management controls.
Attachments appear in the corresponding content blocks. Reader search highlights
matching words.

## Data and actions

`desktop/src/transport.ts` is the frontend entry point for Tauri commands. The Rust
shell communicates with `HindsightBridge`, a private child process that reuses
`HindsightCore` ViewModels. The renderer has no direct access to the filesystem,
Node, or a shell. Documents render without executing raw HTML.

Writes and costly actions display confirmations produced by the native core. The
active confirmation ID and required text are checked again in native code. A
confirmation is consumed before its action runs. Changing banks or servers
invalidates pending requests. Claude/Codex subscription quota checks have been removed.

Slow requests show activity and disable relevant controls without locking unrelated
navigation. Errors remain readable,
empty lists explain how to start, and missing information is shown as unknown.

## Vocabulary

One name per memory function and one verb per action, identical in the sidebar,
tabs, settings, Activity, server roles and engine messages. Do not introduce a
synonym in a new view.

| Server function | French | English |
| --- | --- | --- |
| `retain` | Extraction des faits (tab: Extraction) | Fact extraction (tab: Extraction) |
| `consolidation` | Consolidation | Consolidation |
| `recall` | Recherche | Search |
| `reflect` | Réponses | Answers |
| mental models | Connaissances: page de connaissance, modèle mental | Knowledge: knowledge page, mental model |

A fact is any memory unit counted by the server's `fact_count`, observations
included.

| Action | French | English | Effect |
| --- | --- | --- | --- |
| Reread data (↻ icon) | Actualiser | Refresh | Changes nothing anywhere |
| Run the folder collector | Collecter | Collect | Updates this Mac's catalog only |
| Send sources | Envoyer | Upload | Starts fact extraction in Hindsight |
| Start consolidation | Consolider | Consolidate | LLM calls; facts become observations |
| Rewrite a knowledge item | Régénérer | Regenerate | LLM call |
| Extract one document again | Retraiter | Reprocess | LLM calls |
| Requeue failed work | Relancer | Retry | May use LLM calls |

## Accessibility and shortcuts

- Named buttons and fields, keyboard navigation, and visible focus.
- Focus stays inside dialogs; Escape closes the topmost dialog.
- Reduced-motion preferences are respected.
- `⌘K`: quick navigation; `⌘R`: refresh; `⌘,`: settings; `⌘1…7`: Overview, Memory, Knowledge,
  Search, Sources, Activity and Models.

Example mode is explicitly enabled and visibly marks its data as fictional. It
does not replace error states from a real connection.

## Documentation captures

Run `npm run docs:screenshots` from `desktop/` to capture the current frontend with
a mocked native host and fictional data. The README shows Models in the dark
theme; the guide shows Sources and account indicators in the light theme.
The capture script cannot access a native bridge and blocks external page requests.
Language/layout regression checks write separate images under `desktop/screenshots/`
so they cannot silently replace the public README image.

## Integrations

The Swift package no longer exposes `HindsightUI` or the `HindsightMac` executable.
Consumers of the old interface must migrate. The internal `HindsightAPI` and
`HindsightCore` libraries remain available.

## Memory graph

The graph has entity and fact modes. Groups use local weighted modularity
optimization over loaded connections. Names favor readable, highly connected
subjects over technical markers. Colors distinguish groups; node size represents
degree in the filtered view. Mention count is a separate inspector metric.

One-hop and two-hop neighborhoods, bridge nodes, and accent-insensitive search offer
several ways into the graph. “Connect to…” finds an undirected path with the fewest
connections under the active filters. No path in a sample does not establish that
there is no relationship in the full bank. Facts link to their source documents.

Layout is deterministic and stays stable during inspection. Labels avoid collisions
and mainly appear for selection, search, and hover. The wheel zooms around the
pointer; dragging the background pans the map; the keyboard pans, zooms, and fits
the view. Server totals make sampling visible.

Above 80 nodes, the initial view aggregates nodes into circles showing group sizes,
with at most 70 connections between groups. Clicking a group opens its members;
zooming expands individual nodes. Detailed rendering uses a budget of 120–1,800
connections while retaining selected and path connections. Analysis still uses all
retained connections.
