import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const localCargo = path.join(root, '.toolchain/cargo');
const env = { ...process.env };
// Le développement peut employer un Rust isolé au projet, sans changer le PATH de l'utilisateur.
if (existsSync(path.join(localCargo, 'bin/cargo'))) {
  env.CARGO_HOME = localCargo;
  env.RUSTUP_HOME = path.join(root, '.toolchain/rustup');
  env.PATH = path.join(localCargo, 'bin') + path.delimiter + env.PATH;
}
const child = spawn(
  process.execPath,
  ['node_modules/@tauri-apps/cli/tauri.js', ...process.argv.slice(2)],
  { cwd: root, stdio: 'inherit', env },
);
process.on('SIGINT', () => child.kill('SIGINT'));
process.on('SIGTERM', () => child.kill('SIGTERM'));
child.on('exit', (code) => process.exit(code || 0));
child.on('error', (error) => {
  console.error(error.message);
  process.exit(1);
});
