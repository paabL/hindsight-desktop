import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const base = 'http://127.0.0.1:1427';
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1427', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
const errors = [];

async function nativePage(language = 'en', demo = false) {
  const page = await browser.newPage({ viewport: { width: 1200, height: 1000 } });
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript((language) => {
    localStorage.setItem('hindsight-desktop-language', language);
    const snapshot = {
      app: {
        connected: true,
        bank: 'example',
        banks: [{ bank_id: 'example', name: 'Example bank', fact_count: 0 }],
        serverURL: 'http://127.0.0.1:8888',
        paused: [],
      },
      section: 'settings',
      data: {},
      updates: { version: '0.1.3', state: 'idle' },
      confirmations: [],
      messages: [],
    };
    const fixture = {
      requests: [],
      finish: null,
      fail: null,
      finishBridge: null,
      snapshot,
    };
    window.__updaterFixture = fixture;
    window.__TAURI_INTERNALS__ = {
      invoke: async (command, args) => {
        if (command === 'release_update_check' || command === 'release_update_install') {
          fixture.requests.push({ command, args });
          return new Promise((resolve, reject) => {
            fixture.finish = resolve;
            fixture.fail = reject;
          });
        }
        if (command === 'bridge' && args.request.command === 'server.url') {
          return new Promise((resolve) => {
            fixture.finishBridge = () => resolve(structuredClone(snapshot));
          });
        }
        return structuredClone(snapshot);
      },
    };
  }, language);
  await page.goto(`${base}/${demo ? '?demo=1' : ''}#settings`);
  return page;
}

function card(page, french = false) {
  return page.locator('section.card').filter({
    has: page.getByRole('heading', {
      name: french ? 'Mises à jour de l’application' : 'Application updates',
      exact: true,
    }),
  });
}

async function count(page, command) {
  return page.evaluate(
    (command) => window.__updaterFixture.requests.filter((r) => r.command === command).length,
    command,
  );
}

try {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    if (server.exitCode != null || attempt === 99) throw new Error('UI test server did not start.');
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  browser = await chromium.launch({
    headless: true,
    executablePath:
      process.env.HINDSIGHT_BROWSER_EXECUTABLE ||
      (existsSync('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
        : undefined),
  });

  const page = await nativePage();
  const updates = card(page);
  const check = updates.getByRole('button', { name: 'Check for updates', exact: true });
  const install = updates.getByRole('button', { name: 'Update and restart', exact: true });
  await expect(check).toBeEnabled();
  expect(await count(page, 'release_update_check')).toBe(0);
  await expect(install).toHaveCount(0);
  await expect(updates.getByRole('button', { name: 'Rebuild this copy' })).toBeHidden();

  // No network request is made on startup; rapid clicks start one check only.
  await check.evaluate((button) => {
    button.click();
    button.click();
  });
  await expect(check).toBeDisabled();
  await expect(updates.getByRole('status')).toHaveText('Checking for updates…');
  await expect.poll(() => count(page, 'release_update_check')).toBe(1);
  await page.evaluate(() => window.__updaterFixture.finish(null));
  await expect(updates.getByRole('status')).toHaveText('You’re up to date.');
  await expect(check).toBeEnabled();

  await check.click();
  await expect.poll(() => count(page, 'release_update_check')).toBe(2);
  await page.evaluate(() =>
    window.__updaterFixture.finish({ version: '0.1.4', body: '<script>untrusted notes</script>' }),
  );
  await expect(updates.getByRole('status')).toHaveText('Version 0.1.4 is available.');
  await expect(updates).not.toContainText('untrusted notes');
  await expect(install).toBeEnabled();
  await install.evaluate((button) => {
    button.click();
    button.click();
  });
  await expect.poll(() => count(page, 'release_update_install')).toBe(1);
  expect(await page.evaluate(() => window.__updaterFixture.requests.at(-1).args)).toEqual({
    version: '0.1.4',
  });
  await expect(install).toBeDisabled();
  await expect(check).toBeDisabled();
  await expect(updates.getByRole('button', { name: 'View releases', exact: true })).toBeDisabled();
  await expect(updates.getByRole('status')).toContainText('Downloading and verifying…');
  await page.evaluate(() => window.__updaterFixture.fail('UPDATE_UNTRUSTED_SOURCE'));
  await expect(updates.getByRole('alert')).toContainText('could not be verified');
  await expect(install).toHaveCount(0);
  await expect(check).toBeEnabled();
  await expect(updates.getByRole('button', { name: 'View releases', exact: true })).toBeEnabled();

  // A failed check clears the old offer and exposes a safe, retryable message.
  await check.click();
  await expect.poll(() => count(page, 'release_update_check')).toBe(3);
  await page.evaluate(() => window.__updaterFixture.fail('/private/example/token=secret'));
  await expect(updates.getByRole('alert')).toContainText('Could not check for updates.');
  await expect(updates).not.toContainText('token=secret');
  await expect(install).toHaveCount(0);

  // An active request disables both update and restart until it has completed.
  await page.getByRole('button', { name: 'Apply and reconnect', exact: true }).click();
  await expect(check).toBeDisabled();
  await expect
    .poll(() => page.evaluate(() => typeof window.__updaterFixture.finishBridge))
    .toBe('function');
  await page.evaluate(() => window.__updaterFixture.finishBridge());
  await expect(check).toBeEnabled();
  await check.click();
  await expect.poll(() => count(page, 'release_update_check')).toBe(4);
  await page.evaluate(() => window.__updaterFixture.finish({ version: '0.1.4' }));
  await install.click();
  await expect.poll(() => count(page, 'release_update_install')).toBe(2);
  await page.evaluate(() => window.__updaterFixture.finish(null));
  await expect(updates.getByRole('status')).toHaveText('Restarting the app…');
  await expect(check).toBeDisabled();
  await expect(install).toBeDisabled();

  const french = await nativePage('fr');
  const frUpdates = card(french, true);
  const frCheck = frUpdates.getByRole('button', {
    name: 'Rechercher les mises à jour',
    exact: true,
  });
  await expect(frCheck).toBeEnabled();
  await frCheck.click();
  await expect.poll(() => count(french, 'release_update_check')).toBe(1);
  await french.evaluate(() => window.__updaterFixture.finish({ version: '0.1.4' }));
  await expect(frUpdates.getByRole('status')).toHaveText('La version 0.1.4 est disponible.');
  await frUpdates.getByRole('button', { name: 'Mettre à jour et redémarrer' }).click();
  await expect.poll(() => count(french, 'release_update_install')).toBe(1);
  await french.evaluate(() => window.__updaterFixture.fail('UPDATE_MOVE_TO_APPLICATIONS'));
  await expect(frUpdates.getByRole('alert')).toContainText('dans Applications');
  await expect(frCheck).toBeEnabled();
  await frCheck.click();
  await expect.poll(() => count(french, 'release_update_check')).toBe(2);
  await french.evaluate(() => window.__updaterFixture.finish(null));
  await expect(frUpdates.getByRole('status')).toHaveText('Vous utilisez la dernière version.');

  const demo = await nativePage('en', true);
  await expect(
    card(demo).getByRole('button', { name: 'Check for updates', exact: true }),
  ).toBeDisabled();
  expect(await count(demo, 'release_update_check')).toBe(0);

  const web = await browser.newPage();
  web.on('pageerror', (error) => errors.push(error.message));
  await web.goto(`${base}/#settings`);
  await expect(
    card(web).getByRole('button', { name: 'Check for updates', exact: true }),
  ).toBeDisabled();
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Release updates verified: explicit checks, current/available/error/retry states, one install per click, busy protection, English/French and disabled demo/browser actions.',
  );
} finally {
  await browser?.close();
  server.kill();
}
