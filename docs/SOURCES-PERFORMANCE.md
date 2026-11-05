# Sources: performance and stability

Measured on 2026-11-04 against the locally installed baseline, on the same Mac.
The local catalog contained 2,585 entries and about 124 MB of readable text.
The combined catalog and live Hindsight 1.2 inventory contained 3,341 rows.
All benchmark selection changes were made in a disposable copy. The live server
was accessed through a loopback relay that rejects every method except GET.
No real collector, extraction, consolidation or model call was run.

## Final paired measurement

| Operation | Before | After |
| --- | ---: | ---: |
| First local source list visible | 1,775 ms | 126 ms |
| First complete verification | 1,775 ms | 1,790 ms, in background |
| Subsequent inventory refresh, median of 3 | 1,088 ms | 732 ms |
| Change source selection, median of 6 | 431 ms | 200 ms |
| Bridge resident memory after selection, median | 229 MiB | 71 MiB |
| Selection response size | 4.55 MB | 0.30 MB |

These are local wall-clock measurements, not universal guarantees. The first
display now contains the local manifest with unchecked, locked source states;
the full comparison finishes separately. The IDs and memory states of all 3,341
rows have the same canonical hash before and after. The first verification still depends on
the server and filesystem. Collector duration also depends on external services;
background execution makes the app usable while collection continues.

Earlier paired readings put repeat refreshes around 0.5–0.7 seconds and selection
changes around 0.2 seconds. Browser checks with 12,000 fictional sources measured
filtering at 69–119 ms and cached return navigation at 48–114 ms. Browser timings
include interaction/rendering; native timings include bridge transport and JSON
decoding. Resident memory is the Swift bridge process, not the entire app or peak
memory during an approved upload.

## Changes

- Show the manifest immediately and verify the inventory asynchronously. Keep
  collection off the command queue so navigation and status updates remain usable.
- Cache catalog parsing and per-file digests using path, device, inode, size,
  modification time and change time. Ordinary navigation retains no full source
  texts. Selected texts are reread for upload preparation and confirmation.
- Reuse unchanged catalog rows and transfer only changed rows while preserving
  ordering and removals. Metadata-only polling keeps the current catalog object.
- Cache source ordering/search fields, defer text filtering, and avoid searching
  the separate archives while they are closed.
- Scope loads to server, bank and folder. Cancel obsolete work and discard late
  replies. Keep reader selection current, and ignore a previous document's late
  text response after another document is opened.

## Validation

- Release Swift suite: 357 Core tests and 21 API tests passed.
- Node suite: 63 tests passed, including held server responses, bank switches,
  background collection, stale revisions and incremental catalog reconciliation.
- Native cases cover same-size edits with restored modification times, symlink
  replacement, manifest-only first display and upload confirmation revalidation.
- Browser checks cover 17 views, navigation/history, both interface languages and
  themes, plus the 12,000-source reader/filter/selection stress scenario.

No pagination or source count cap was introduced. Existing archives, exclusions,
links, stored versions, imports, removal safeguards and confirmed uploads remain
available. Embeddings and runtime model settings are unchanged.

## Reproduction

Use an explicit disposable copy under `/tmp/hindsight-sources-bench/`. Never point
the benchmark at the original source folder. Preserve the previous bridge binary
before building the candidate, and run them sequentially against the same copy:

```sh
cd desktop
node scripts/benchmark-sources.mjs BEFORE_BINARY /tmp/hindsight-sources-bench/fixture /tmp/before.json LOCAL_SERVER_URL BANK_ID progressive
node scripts/benchmark-sources.mjs native/HindsightBridge /tmp/hindsight-sources-bench/fixture /tmp/after.json LOCAL_SERVER_URL BANK_ID progressive
node tests/sources-ui.mjs
```

Omit the server URL and bank ID to use the deterministic fake inventory. The
script restores its fixture's selection ledger and policy afterwards. Compare
the semantic hashes as well as timings. Results contain counts, timings, hashes
and memory readings, not document text.
