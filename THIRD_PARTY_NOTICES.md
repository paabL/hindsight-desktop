# Third-party notices

Hindsight Desktop uses independently licensed components. Its own code is
licensed under [MIT](LICENSE). The complete component inventory, copyright
notices, and license texts are in
[THIRD_PARTY_NOTICES.txt](desktop/public/THIRD_PARTY_NOTICES.txt), also included
in the built frontend. The [Rust standard library notices](desktop/public/RUST_STANDARD_LIBRARY_NOTICES.txt)
are included alongside them. Versions are fixed by `desktop/package-lock.json`
and `desktop/src-tauri/Cargo.lock`.

- **Hindsight API specification and generated models** — Vectorize AI, Inc.;
  [upstream MIT license](https://github.com/vectorize-io/hindsight/blob/v1.2.0/LICENSE).
  The included OpenAPI document additionally declares Apache-2.0; that text is
  preserved in the complete notices. The server and model weights are not bundled.
- **React, Lucide, Markdown rendering and related frontend libraries** — MIT/ISC,
  with the individual notices preserved in the complete inventory.
- **Tauri, its dialog plugin and native Rust dependencies** — the licenses in
  the complete inventory. Multi-licensed dependencies are used under MIT where
  available. Dependencies requiring combined notices retain all applicable texts.
- **MPL-2.0 components** — `cssparser`, `cssparser-macros`, `dtoa-short`,
  `selectors`, and `servo_arc` are used without modifications. Their exact
  source packages are available from the versioned crates.io download links
  listed in the complete inventory. These files remain under MPL-2.0; this
  does not change the license of Hindsight Desktop's independent files.

Apple system frameworks are supplied by macOS. Build tools and third-party
services installed separately remain governed by their own terms.
