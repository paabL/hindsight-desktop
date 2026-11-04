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

// Construction locale uniquement : ne publie rien, n'installe rien, ne contacte aucun serveur mémoire.
const desktop = fileURLToPath(new URL('../', import.meta.url));
const root = path.dirname(desktop);
if (process.platform !== 'darwin' || process.arch !== 'arm64')
  throw new Error('Cette distribution est destinée à macOS sur Apple Silicon.');
const commit = process.env.HINDSIGHT_RELEASE_COMMIT;
if (!commit || !/^[a-f0-9]{40}$/.test(commit))
  throw new Error('Indiquez HINDSIGHT_RELEASE_COMMIT avec le commit du dépôt public vérifié.');
const { version } = JSON.parse(readFileSync(path.join(desktop, 'package.json'), 'utf8'));
const output = path.join(desktop, 'release');
mkdirSync(output, { recursive: true });
const run = (command, args, env = process.env) => {
  const result = spawnSync(command, args, { cwd: desktop, stdio: 'inherit', env });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(command)} : échec (${result.status}).`);
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
  if (!existsSync(file)) throw new Error(`Fichier absent : ${file}`);
  run('/usr/bin/lipo', ['-verify_arch', 'arm64', file]);
}
// Signature locale gratuite, sans prétendre être une signature Developer ID ou une notarisation.
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
    `Hindsight Desktop ${version} — community beta / bêta communautaire

macOS 15+ · Apple Silicon (M1 ou plus récent / M1 or newer)
Français / English : Réglages → Langue / Settings → Language.

FR : Glissez Hindsight Desktop dans Applications. Cette bêta gratuite n'est pas
notariée par Apple. Si macOS bloque l'ouverture après votre première tentative,
consultez Réglages Système → Confidentialité et sécurité → Ouvrir quand même.
Vérifiez la provenance du téléchargement ; ne désactivez pas les protections.
L'app nécessite votre propre serveur Hindsight pour les fonctions de mémoire.
Le mode exemple fonctionne sans serveur. Le serveur et les modèles sont séparés.

EN: Drag Hindsight Desktop into Applications. This free beta is not notarized by
Apple. If macOS blocks it after your first attempt to open it, see System Settings
→ Privacy & Security → Open Anyway. Verify the download's origin; keep macOS
security protections enabled. Memory features require your own Hindsight server.
Example mode works without a server. Server and models are separate.

https://github.com/paabL/hindsight-desktop
Independent client, not affiliated with Vectorize AI, Inc.
Client indépendant, sans affiliation officielle avec Vectorize AI, Inc.
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
  const sha256 = createHash('sha256').update(readFileSync(dmg)).digest('hex');
  writeFileSync(path.join(output, 'SHA256SUMS.txt'), `${sha256}  ${name}\n`);
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
      },
      null,
      2,
    ) + '\n',
  );
  console.log(`Distribution prête : ${dmg}`);
} finally {
  rmSync(stage, { recursive: true, force: true });
}
