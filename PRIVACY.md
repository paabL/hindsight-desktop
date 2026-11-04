# Privacy

Last updated: 2026-11-04.

Hindsight Desktop is an independent community client. The app adds no ads,
analytics or publisher-operated collection service. It connects to the
Hindsight server you configure and does not host your memories.

- **Local files.** Your selected memory folder contains source files, catalogs
  and upload state. Configured collectors may read conversations, repositories
  and documents. Review the preview before sending.
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
- **Subscription quotas.** An explicitly confirmed check in **Usage** uses
  existing Codex credentials and, when allowed, Claude Code credentials, only
  with their own services. Quota checks are not run automatically. These
  interfaces may change; no document or prompt is needed for the check.
- **Updates and GitHub.** Source update checks contact your configured Git
  repository. GitHub downloads and issue reports are also subject to GitHub's
  terms.

Removing the app leaves your server, memory banks, memory folder and official
accounts in place. To erase server memories, use confirmed server deletions and
check your host's backup policy. Never post conversations, credentials or
complete logs in a public report. See [Security](SECURITY.md).
