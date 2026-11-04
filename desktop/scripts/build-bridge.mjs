import { spawnSync } from 'node:child_process';
import { mkdirSync, copyFileSync, chmodSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
if (process.platform !== 'darwin')
  throw new Error('Le moteur local HindsightCore nécessite macOS 15+.');
const argumentsForSwift = [
  'build',
  '--disable-sandbox',
  '-c',
  'release',
  '--product',
  'HindsightBridge',
];
if (process.env.HINDSIGHT_DISTRIBUTION_BUILD) {
  // Les chemins de compilation du Mac de l'éditeur n'ont pas leur place dans une distribution.
  const mapping = `${path.resolve(root)}=/source`;
  argumentsForSwift.push(
    '-Xswiftc',
    '-debug-prefix-map',
    '-Xswiftc',
    mapping,
    '-Xswiftc',
    '-file-prefix-map',
    '-Xswiftc',
    mapping,
  );
}
const result = spawnSync('swift', argumentsForSwift, {
  cwd: root,
  stdio: 'inherit',
  env: {
    ...process.env,
    CLANG_MODULE_CACHE_PATH: path.join(root, '.build/desktop-module-cache'),
    SWIFTPM_MODULECACHE_OVERRIDE: path.join(root, '.build/desktop-module-cache'),
  },
});
if (result.status !== 0) process.exit(result.status || 1);
const output = path.join(root, 'desktop/native');
mkdirSync(output, { recursive: true });
copyFileSync(
  path.join(root, '.build/release/HindsightBridge'),
  path.join(output, 'HindsightBridge'),
);
chmodSync(path.join(output, 'HindsightBridge'), 0o755);
if (process.env.HINDSIGHT_DISTRIBUTION_BUILD) {
  const bridge = path.join(output, 'HindsightBridge');
  // Le linker garde encore les chemins des fichiers objets dans les symboles de débogage.
  // Les retirer avant de signer laisse le moteur exécutable et ne distribue aucun dSYM.
  for (const [command, args] of [
    ['/usr/bin/strip', ['-S', bridge]],
    ['/usr/bin/codesign', ['--force', '--sign', '-', '--timestamp=none', bridge]],
  ]) {
    const signed = spawnSync(command, args, { stdio: 'inherit' });
    if (signed.error) throw signed.error;
    if (signed.status !== 0) process.exit(signed.status || 1);
  }
}
