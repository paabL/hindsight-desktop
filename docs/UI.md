# Hindsight Desktop interface

The app's only frontend lives in `desktop/src/`: React, TypeScript, and CSS inside
Tauri. The former SwiftUI targets and stub-based UI checks have been removed.

## Visual design

- Cool surfaces with petroleum blue, eucalyptus, and indigo accents distinguish
  navigation, categories, and status.
- System typography, clear hierarchy, subtle borders, and restrained corner radii.
- No orange accents, playful decoration, marketing illustrations, or slogans.
- Dark and light themes, with the choice saved on the device.
- Source data, provenance, and processing status take priority.

Design tokens live in `desktop/src/tokens.css`. Shared buttons, cards, badges,
errors, dialogs, and typography live in `desktop/src/ui.tsx`.

## Navigation and language

The sidebar has six primary groups: **Overview**, **Memory**, **Knowledge**,
**Search**, **Sources**, and **Activity**. Overview is the initial view. Settings
stays at the bottom of the sidebar. All views are visible through these groups;
there is no Advanced navigation section.

| Group | Views |
| --- | --- |
| Overview | Bank statistics, processing status and recent documents |
| Memory | Facts, Documents, Timeline, Graph |
| Knowledge | Knowledge pages and mental models |
| Search | Recall, exact text and confirmed reflect |
| Sources | Catalog, Tracked folders, Imports |
| Activity | Processing, Usage, Logs |
| Settings | Application, Memory bank, Memory behavior, Server & models |

Groups with several views show a named tab bar above the page heading. A group
click returns to its last selected tab. The Settings shortcut opens Application. Existing hash links remain valid; in
particular, `#memory` still opens Memory behavior, while `#facts` opens the
bank's facts. Browser back and forward update the view and active group together.
The command palette lists every view and searches group and view names without
requiring accents.

The public interface defaults to English. French is an explicit choice in
Settings → Application → Language. Documents, source text, and content returned
by the server keep their original language.

**Memory** presents knowledge stored in the selected Hindsight bank. **Sources**
presents the local catalog before processing: projects, collectors, source
families, filters, and a reader with provenance. The local catalog is independent
of the selected bank and remains readable offline. Upload previews explain what
will be sent from Sources into Hindsight.

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
invalidates pending requests. Account quota checks require an explicit, confirmed
request and do not enable automatic OAuth access.

Slow requests show activity and disable relevant controls. Errors remain readable,
empty lists explain how to start, and missing information is shown as unknown.

## Accessibility and shortcuts

- Named buttons and fields, keyboard navigation, and visible focus.
- Focus stays inside dialogs; Escape closes the topmost dialog.
- Reduced-motion preferences are respected.
- `⌘K`: quick navigation; `⌘R`: refresh; `⌘,`: settings; `⌘1…6`: primary group defaults.

Example mode is explicitly enabled and visibly marks its data as fictional. It
does not replace error states from a real connection.

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
