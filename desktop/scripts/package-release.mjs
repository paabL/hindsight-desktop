import { spawnSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Local build only: does not publish, install, or contact a memory server.
const desktop = fileURLToPath(new URL('../', import.meta.url));
const root = path.dirname(desktop);
if (process.platform !== 'darwin' || process.arch !== 'arm64')
  throw new Error('This package targets macOS on Apple Silicon.');
const commit = process.env.HINDSIGHT_RELEASE_COMMIT;
if (!commit || !/^[a-f0-9]{40}$/.test(commit))
  throw new Error('Set HINDSIGHT_RELEASE_COMMIT to the verified public source commit.');
const { version } = JSON.parse(readFileSync(path.join(desktop, 'package.json'), 'utf8'));
// The private update key stays outside source control. Local release builds use
// macOS Keychain; CI may provide its own protected environment variables.
let signingKey = process.env.TAURI_SIGNING_PRIVATE_KEY;
if (!signingKey) {
  const stored = spawnSync(
    '/usr/bin/security',
    [
      'find-generic-password',
      '-s',
      'io.github.paabL.hindsight-desktop.updater',
      '-a',
      'release-signing-key',
      '-w',
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  );
  if (stored.status !== 0 || !stored.stdout.trim())
    throw new Error(
      'Provide TAURI_SIGNING_PRIVATE_KEY or configure the release signing key in macOS Keychain.',
    );
  signingKey = stored.stdout.trim();
}
const output = path.join(desktop, 'release');
mkdirSync(output, { recursive: true });
const run = (command, args, env = process.env) => {
  const result = spawnSync(command, args, { cwd: desktop, stdio: 'inherit', env });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(command)}: failed (${result.status}).`);
};
run(
  process.execPath,
  ['scripts/tauri.mjs', 'build', '--bundles', 'app', '--ci', '--', '--locked'],
  {
    ...process.env,
    HINDSIGHT_DISTRIBUTION_BUILD: '1',
    HINDSIGHT_RELEASE_COMMIT: commit,
    RUSTFLAGS: [process.env.RUSTFLAGS, `--remap-path-prefix=${root}=/source/hindsight-desktop`]
      .filter(Boolean)
      .join(' '),
  },
);
const app = path.join(desktop, 'src-tauri/target/release/bundle/macos/Hindsight Desktop.app');
const bridge = path.join(app, 'Contents/Resources/native/HindsightBridge');
for (const file of [path.join(app, 'Contents/MacOS/hindsight-desktop'), bridge]) {
  if (!existsSync(file)) throw new Error(`Missing file: ${file}`);
  run('/usr/bin/lipo', ['-verify_arch', 'arm64', file]);
}
// Free ad-hoc signing; this is neither Developer ID signing nor notarization.
run('/usr/bin/codesign', ['--force', '--sign', '-', '--timestamp=none', bridge]);
run('/usr/bin/codesign', ['--force', '--sign', '-', '--timestamp=none', app]);
run('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', app]);
const stage = mkdtempSync(path.join(output, '.package-'));
const name = `Hindsight-Desktop_${version}_macOS-Apple-Silicon.dmg`;
const dmg = path.join(output, name);
try {
  cpSync(app, path.join(stage, 'Hindsight Desktop.app'), { recursive: true });
  symlinkSync('/Applications', path.join(stage, 'Applications'));
  for (const file of ['LICENSE', 'NOTICE', 'PRIVACY.md', 'SECURITY.md'])
    cpSync(path.join(root, file), path.join(stage, file));
  writeFileSync(
    path.join(stage, 'START-HERE.txt'),
    `Hindsight Desktop ${version} — community beta

macOS 15+ · Apple Silicon (M1 or newer)

Drag Hindsight Desktop into Applications. This free beta is not notarized by
Apple. If macOS blocks it after your first attempt to open it, see System Settings
→ Privacy & Security → Open Anyway. Verify the download's origin and keep macOS
security protections enabled.

Memory features require your own Hindsight server. The server and models are
separate. Example mode works without a server.

The app starts in English. French is available in Settings → Language.

https://github.com/paabL/hindsight-desktop
Independent client, not affiliated with Vectorize AI, Inc.

`,
  );
  run('/usr/bin/hdiutil', [
    'create',
    '-volname',
    'Hindsight Desktop',
    '-srcfolder',
    stage,
    '-ov',
    '-format',
    'UDZO',
    dmg,
  ]);
  run('/usr/bin/hdiutil', ['verify', dmg]);
  // Archive only the final signed bundle, after every modification above.
  // Signature verification is separate from Apple Developer ID/notarization.
  const archiveName = `Hindsight-Desktop_${version}_macOS-Apple-Silicon.app.tar.gz`;
  const archive = path.join(output, archiveName);
  run('/usr/bin/tar', ['-czf', archive, '-C', path.dirname(app), path.basename(app)], {
    ...process.env,
    COPYFILE_DISABLE: '1',
  });
  run(
    process.execPath,
    ['scripts/tauri.mjs', 'signer', 'sign', '--app-version', version, archive],
    {
      ...process.env,
      TAURI_SIGNING_PRIVATE_KEY: signingKey,
      TAURI_SIGNING_PRIVATE_KEY_PASSWORD: process.env.TAURI_SIGNING_PRIVATE_KEY_PASSWORD || '',
    },
  );
  const signature = readFileSync(`${archive}.sig`, 'utf8').trim();
  if (!signature) throw new Error('Missing updater archive signature.');
  const sha256 = createHash('sha256').update(readFileSync(dmg)).digest('hex');
  const archiveSHA256 = createHash('sha256').update(readFileSync(archive)).digest('hex');
  writeFileSync(
    path.join(output, 'SHA256SUMS.txt'),
    `${sha256}  ${name}\n${archiveSHA256}  ${archiveName}\n`,
  );
  const entry = {
    url: `https://github.com/paabL/hindsight-desktop/releases/download/v${version}/${archiveName}`,
    signature,
  };
  writeFileSync(
    path.join(output, 'beta.json'),
    JSON.stringify(
      {
        version,
        notes: `Hindsight Desktop ${version} community beta.`,
        pub_date: new Date().toISOString(),
        // "darwin" repeats the same archive for installed versions up to 0.2.1, whose installer
        // looked the feed up by OS alone. Same file, same version-bound signature.
        platforms: { 'darwin-aarch64': entry, darwin: entry },
      },
      null,
      2,
    ) + '\n',
  );
  writeFileSync(
    path.join(output, 'release-manifest.json'),
    JSON.stringify(
      {
        version,
        source: 'https://github.com/paabL/hindsight-desktop',
        commit,
        architecture: 'arm64',
        minimumMacOS: '15.0',
        signing: 'ad-hoc',
        notarized: false,
        file: name,
        sha256,
        updater: {
          file: archiveName,
          sha256: archiveSHA256,
          signature: `${archiveName}.sig`,
          signedVersion: version,
        },
      },
      null,
      2,
    ) + '\n',
  );
  console.log(`Release package ready: ${dmg}`);
} finally {
  rmSync(stage, { recursive: true, force: true });
}
