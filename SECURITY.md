# Security

This is an early community beta. Use the latest release, keep backups of
important memories and connect remote servers over HTTPS. The app accesses
local files and can control a local Hindsight service when explicitly configured.

## Application updates

In-app updates use a fixed HTTPS beta feed and an embedded public key. Tauri
verifies each update package’s signature, including its signed app version,
before installation. Checks and installation require explicit actions in
Settings. The private release signing key is never distributed with the app
or committed to the repository.

This verification is free and independent of Apple notarization. Public beta
builds remain unnotarized; follow the documented per-app macOS approval for the
first installation. Keep macOS security protections enabled. Manual downloads
and SHA-256 checksums remain available from
[Releases](https://github.com/paabL/hindsight-desktop/releases).

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/paabL/hindsight-desktop/security/advisories/new).
Include the app/macOS versions, a minimal reproduction with invented data and
the expected impact. Do not include credentials, personal memories,
conversation exports or complete logs.

If that form is unavailable, open an issue requesting a private contact without
disclosing exploit details or sensitive data. Ordinary bugs belong in
[Issues](https://github.com/paabL/hindsight-desktop/issues).

There is no guaranteed response time. Vulnerabilities in the Hindsight server
should also be reported through the upstream project's
[security policy](https://github.com/vectorize-io/hindsight/security/policy).
