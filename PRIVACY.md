# Privacy

Last updated: 2026-11-04.

Hindsight Desktop is an independent community client. The app adds no ads,
analytics or publisher-operated collection service. It connects to the
Hindsight server you configure and does not host your memories.

- **Local files.** Your selected memory folder contains source files, catalogs
  and upload state. Configured collectors may read conversations, repositories
  and documents. Review the preview before sending.
- **Source browsing.** Opening the catalog reads its local manifest, then checks
  files and the selected bank's document inventory. It does not run collectors or
  upload sources. File fingerprints are cached in memory; full source texts are
  reread for upload preparation and confirmation. **Refresh folder** explicitly
  runs the configured collectors in the background; these may contact their own
  source services.
- **Uploads and queries.** The server receives the documents and queries needed
  for your requested actions. It may send them to its configured model
  providers, whose fees and retention policies apply. A local server does not
  necessarily mean local model processing.
- **App storage.** macOS preferences are stored under `local.hindsight.desktop`.
  The local ledger at
  `~/Library/Application Support/HindsightDesktop/usage-ledger.json` stores
  counts, provider/model names, timestamps and bank/document identifiers,
  without prompt or response text. Files, saved upload plans and backups in
  the memory folder may contain your document content.
- **Accounts.** Sign-in uses separately installed official clients. Hindsight
  Cloud stores its key in `~/.hindsight/cloud/credentials.json`. Local sign-out
  does not revoke that cloud key.
- **Updates and GitHub.** Choosing **Check for updates** contacts the public
  beta feed at
  `https://raw.githubusercontent.com/paabL/hindsight-desktop/main/updates/beta.json`.
  Choosing **Update and restart** downloads the signed app package from GitHub
  Releases. These requests send no memory, document or conversation content;
  GitHub receives normal connection information such as your IP address and
  request headers. No update check or download runs automatically. Advanced
  source update checks contact your configured Git repository. GitHub downloads
  and issue reports are subject to GitHub's terms.

Removing the app leaves your server, memory banks, memory folder and official
accounts in place. To erase server memories, use confirmed server deletions and
check your host's backup policy. Never post conversations, credentials or
complete logs in a public report. See [Security](SECURITY.md).
