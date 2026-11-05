import assert from 'node:assert/strict';
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const base = 'http://127.0.0.1:16431';
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '16431', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    if (server.exitCode != null || i === 99) throw new Error('Vite did not start');
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  await mkdir(new URL('../screenshots/', import.meta.url), {recursive:true});
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1000, height: 760 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'fr');
    const fixture = (window.__serviceFixture = {
      busy: false,
      error: null,
      reachable: false,
      snapshots: 0,
      starts: 0,
      section: 'server',
    });
    window.__TAURI_INTERNALS__ = {
      invoke: async (_command, args) => {
        const { exampleSnapshot } = await import('/src/demo.ts');
        const request = args?.request || {};
        if (request.command === 'section') fixture.section = request.args.section;
        if (request.command === 'snapshot') fixture.snapshots++;
        if (request.command === 'service.start') {
          fixture.busy = true;
          fixture.error = null;
          fixture.starts++;
        }
        const result = structuredClone(exampleSnapshot(fixture.section));
        result.app.connected = fixture.reachable;
        result.app.connectionError = null;
        result.serviceBusy = fixture.busy;
        result.confirmations = [];
        result.messages = [];
        if (fixture.section === 'server')
          result.data.service = {
            installed: true,
            running: fixture.reachable,
            reachable: fixture.reachable,
            busy: fixture.busy,
            error: fixture.error,
            canStart: !fixture.busy && !fixture.reachable,
            canStop: fixture.reachable && !fixture.busy,
          };
        return result;
      },
    };
  });
  await page.goto(base + '/#server');
  const card = page.locator('.service-card');
  await expect(card.getByRole('button', { name: 'Démarrer', exact: true })).toBeEnabled();
  await card.getByRole('button', { name: 'Démarrer', exact: true }).click();
  await expect(card).toContainText('En cours…');
  await expect(card.getByRole('button', { name: 'Démarrer', exact: true })).toBeDisabled();
  await expect(card.getByRole('button', { name: 'Redémarrer', exact: true })).toBeDisabled();
  await expect
    .poll(() => page.evaluate(() => window.__serviceFixture.snapshots), { timeout: 7000 })
    .toBeGreaterThan(0);
  await page.evaluate(() => {
    window.__serviceFixture.busy = false;
    window.__serviceFixture.error = 'ValueError: missing reranker credential';
  });
  await expect(card).toContainText('missing reranker credential', { timeout: 7000 });
  await expect(card.getByRole('button', { name: 'Démarrer', exact: true })).toBeEnabled();
  await card.getByRole('button', { name: 'Démarrer', exact: true }).click();
  await page.evaluate(() => {
    window.__serviceFixture.busy = false;
    window.__serviceFixture.error = null;
    window.__serviceFixture.reachable = true;
  });
  await expect(card).toContainText('Accessible', { timeout: 7000 });
  await expect(card).not.toContainText('missing reranker credential');
  assert.equal(await page.evaluate(() => window.__serviceFixture.starts), 2);
  await page.locator('.role-card').filter({ hasText: 'Décision' }).click();
  const editor = page.getByRole('dialog');
  for (const name of ['Modèle', 'Recherche', 'Réponse', 'Consolidation', 'Pages']) {
    await editor.getByRole('tab', { name, exact: true }).click();
    await expect(editor).toBeVisible();
  }
  await editor.getByRole('tab', { name: 'Modèle', exact: true }).click();
  await editor.locator('.model-advanced > summary').click();
  const footer = await editor
    .getByRole('button', { name: 'Préparer ces changements', exact: true })
    .boundingBox();
  assert.ok(footer.y + footer.height <= 760, 'Editor footer must remain in the small viewport');
  await editor.screenshot({ path: root + 'screenshots/decision-compact.png' });
  assert.deepEqual(errors, []);
  console.log(
    'Offline service progress, repeated start protection, inline failure/recovery and compact editor on a small viewport verified.',
  );
} finally {
  await browser?.close();
  server.kill();
}
