import assert from 'node:assert/strict';
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.HINDSIGHT_SERVICE_TEST_PORT || 16473);
assert.ok(Number.isInteger(port) && port >= 16450 && port < 65536);
const base = `http://127.0.0.1:${port}`;
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
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
  await expect.poll(() => page.evaluate(() => window.__serviceFixture.starts)).toBe(2);
  await page.evaluate(() => {
    window.__serviceFixture.busy = false;
    window.__serviceFixture.error = null;
    window.__serviceFixture.reachable = true;
  });
  await expect(card).toContainText('Accessible', { timeout: 7000 });
  await expect(card).not.toContainText('missing reranker credential');
  assert.equal(await page.evaluate(() => window.__serviceFixture.starts), 2);
  // Les rôles se règlent dans Modèles, repliés sous le schéma.
  await page.goto(base + '/#model-settings');
  await page.locator('summary', { hasText: 'Tous les rôles et réglages avancés' }).click();
  await page.locator('.role-card').filter({ hasText: 'Décision' }).click();
  const editor = page.getByRole('dialog');
  for (const name of ['Modèle', 'Recherche', 'Réponses', 'Consolidation', 'Connaissances']) {
    await editor.getByRole('tab', { name, exact: true }).click();
    await expect(editor).toBeVisible();
  }
  await editor.getByRole('tab', { name: 'Modèle', exact: true }).click();
  await editor.locator('.model-advanced > summary').click();
  const footer = await editor
    .getByRole('button', { name: 'Préparer ces changements', exact: true })
    .boundingBox();
  assert.ok(footer.y + footer.height <= 760, 'Editor footer must remain in the small viewport');
  if (process.env.HINDSIGHT_SERVICE_SCREENSHOT) {
    const screenshot = path.resolve(process.env.HINDSIGHT_SERVICE_SCREENSHOT);
    await mkdir(path.dirname(screenshot), { recursive: true });
    await editor.screenshot({ path: screenshot });
  }
  assert.deepEqual(errors, []);
  console.log(
    'Offline service progress, repeated start protection, inline failure/recovery and compact editor on a small viewport verified.',
  );
} finally {
  await browser?.close();
  server.kill();
}
