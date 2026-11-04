# Testing Hindsight Desktop

## Native core and API contract

From the repository root:

```sh
swift test
```

XCTest covers the API client, ViewModels, confirmations, files, cost estimates, and
service safeguards. Client tests compare requests with `docs/openapi.json` and decode
both minimal and complete responses. Do not edit generated models by hand.

After changing the contract, update `docs/openapi.json`, run
`python3 scripts/generate_models.py`, then rerun the tests.

`TransportSecurityTests` uses two temporary loopback HTTP servers to check real
redirects: a same-origin redirect preserves the request, while a cross-origin
redirect receives neither credentials nor document content. These tests require
permission to bind local ports. Other tests cover cancelled requests, restored
server addresses, and rejection of misleading hostnames.

### Server 1.2 and earlier versions

`Server120Tests` and `desktop/tests/server120.test.mjs` cover recall's `rerank`
options: inherit the bank setting, enable, disable, and omit them on server 1.1.
They also check confirmed bank settings and `split_by=model` usage statistics.

Specialized services use indicative hosted prices. Statistics do not identify
the provider or endpoint, so they do not prove that a call was billed. Local
inference has no per-token service charge. Changing servers clears the readings;
failures remain visible and retryable; changing prices also revalues cached data.

From `desktop/`, `npm run test:models` checks search controls, bank switches,
indicative costs, and Hindsight model choices with synthetic data at two window
widths.

The settings catalog supports `hindsight` for decision, reranking, and embedding
models. Dedicated keys may be left empty after `hindsight-admin cloud login`.
Search → Filters applies prune/dedup choices only to the current request; persistent
defaults belong in Memory structure → Search. Recall needs a configured decision
model. Changing embedding models requires reindexing; changing rerankers does not.

## Native bridge and frontend

From `desktop/`:

```sh
npm run bridge:build
npm test
npm run build
```

Bridge tests use a fake HTTP server, in-memory settings, and temporary files. They
check that reads do not write, reflect waits for confirmation, confirmations cannot
be replayed, deletions require the expected text, changing banks invalidates pending
requests, file reads stay within the selected folder after resolving symlinks, and
unsupported URLs or commands are refused. Subscription quota checks require a
separate confirmation and remain inactive when cancelled.

## Browser rendering

```sh
cd desktop
npx playwright install chromium
npm run test:ui
npm run test:i18n
```

Rendering tests use synthetic data. They visit views, open documents and summaries,
search facts, filter sources, inspect the graph, exercise shortcuts, and check both
themes. Language checks cover English and the optional French interface. Screenshots
are written to `desktop/screenshots/`.

Browser tests do not verify native Tauri dialogs or macOS permissions. Check those
in the packaged app.

## Signed application updates

`npm run test:updates` uses a mocked native host and fictional data to cover the
explicit update check, available/current states, download failures, repeated
clicks, active work, and English/French messages. It never installs an app.

From `desktop/src-tauri`, `cargo test --locked` checks the native release source,
selected version, installation location and rejection of altered or incorrectly
versioned signatures. The ignored release qualification test accepts the built
archive and feed through `HINDSIGHT_VERIFY_ARCHIVE` and
`HINDSIGHT_VERIFY_FEED`; it verifies and installs into its own temporary bundle,
then checks the installed version and code signature. It does not modify the
app in Applications.

## Build and check Tauri

```sh
cd desktop
npm run tauri:build -- --bundles app
```

Open `desktop/src-tauri/target/release/bundle/macos/Hindsight Desktop.app`.

1. Load a local catalog with the server offline, then connect and load banks.
2. Inspect a source and its provenance, filter by project and source family, and
   check collector status.
3. Read a summary and a document with attachments; check history and text highlights.
4. Check recall and exact text search. For reflect, inspect the estimate and
   confirmation, then cancel.
5. Prepare a write, reprocessing action, or deletion. Inspect its details and any
   required confirmation text, then cancel.
6. Inspect quota timestamps and the distinction between usage fees and subscription
   tokens. Request an account quota check only when explicitly authorized.
7. Test folder selection and the export save dialog using temporary files.
8. Inspect models, diffs, and backups without saving or restarting the server.
9. Check that displayed fields, diffs, and logs mask secrets.
10. Check themes, keyboard navigation, quick navigation, language selection, windows,
    and the minimum window size.
11. Quit the exact tested app instance and verify that its private bridge exits.
    When comparing installed and mounted copies, identify each by its full path.

Real collection, extraction, consolidation, deletion, OAuth access, and service
operations need explicit authorization. Read-only tests must not trigger them.

For distribution packaging, signing, architecture, notices, and checksums, follow
[RELEASE.md](RELEASE.md).

## Legacy frontend migration

`HindsightUI`, `HindsightMac`, the SwiftUI stubs, and the old installation scripts
have been removed. Consumers of the old UI module must migrate their integration
before updating this dependency. `HindsightAPI` and `HindsightCore` remain available.

## Source updates

`AppUpdateTests` checks Tauri rebuilds in a separate destination, bundle identifier
validation, replacement, rejection of local modifications, and repository changes
after confirmation. In Settings → App updates, inspect the log and state without
confirming a real installation. Update status should remain responsive regardless
of the Hindsight server connection.

## Interactive memory graph

From `desktop/`, `npm run test:graph` checks groups, stable selection, two-hop
neighborhoods, accent-insensitive search, paths between ideas, inspecting a path step
without losing the route, filters that break a path, provenance, pan/zoom, keyboard
controls, themes, and overflow at three widths. The browser is isolated and all data
is synthetic. Tests prefer an installed Playwright Chromium; on macOS they can use
an existing Chrome installation. `HINDSIGHT_BROWSER_EXECUTABLE` selects an executable.

Graph model tests cover topology, duplicates, isolated nodes, filters, deterministic
groups, and layout for 1,000 nodes. The bridge test covers server totals, mode
persistence, and access to a fact's source. `swift test --filter GraphTests` checks
data loading without unnecessary native layout simulation.

The visual test also includes a dense synthetic map of 100 nodes: group aggregation,
exact connection counts, opening group members, and expanding nodes on zoom.
