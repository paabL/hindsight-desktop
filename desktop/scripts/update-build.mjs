import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('../', import.meta.url));
// Destination distincte du bundle ouvert : aucune modification de l'app avant validation complète.
const env = {
  ...process.env,
  PATH: path.dirname(process.execPath) + path.delimiter + (process.env.PATH || '/usr/bin:/bin:/usr/sbin:/sbin'),
  CARGO_TARGET_DIR: path.join(root, '.update-target'),
};
const npm = path.join(path.dirname(process.execPath), 'npm');
for (const args of [
  ['ci', '--no-audit', '--no-fund'],
  ['run', 'tauri:build', '--', '--bundles', 'app'],
]) {
  const result = spawnSync(npm, args, { cwd: root, env, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}
