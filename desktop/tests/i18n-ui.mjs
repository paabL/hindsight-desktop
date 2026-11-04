import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1426', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch('http://127.0.0.1:1426')).ok) break;
    } catch {}
    if (server.exitCode != null || attempt === 99)
      throw new Error('Le serveur de test ne démarre pas.');
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
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 }, locale: 'fr-CA' });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('http://127.0.0.1:1426/');
  await expect(page.getByRole('heading', { name: 'Welcome to Hindsight Desktop' })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  expect(await page.evaluate(() => navigator.language)).toBe('fr-CA');
  await page.getByRole('button', { name: 'Connect my server', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Connect to Hindsight' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'View releases', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Rebuild this copy', exact: true })).toBeHidden();
  await page.getByRole('combobox', { name: 'Interface language' }).selectOption('fr');
  await expect(page.getByRole('heading', { name: 'Connexion à Hindsight' })).toBeVisible();
  await expect(page.locator('html')).toHaveAttribute('lang', 'fr');
  await page.reload();
  await expect(page.getByRole('combobox', { name: 'Langue de l’interface' })).toHaveValue('fr');
  await page.getByRole('button', { name: 'Explorer l’exemple', exact: true }).click();
  await expect(page.getByText('Exemple · données fictives', { exact: true })).toBeVisible();
  await page
    .getByRole('navigation', { name: 'Navigation principale' })
    .getByRole('button', { name: /^Mémoire/ })
    .click();
  await page.keyboard.press('Meta+5');
  await expect(page.getByRole('heading', { name: 'Mémoire', exact: true })).toBeVisible();
  await page.locator('.source-row').first().click();
  await expect(page.locator('.modal .markdown')).toBeVisible();
  const originalDocument = await page.locator('.modal .markdown').textContent();
  await page.getByRole('button', { name: 'Fermer', exact: true }).click();
  await page.getByRole('button', { name: 'Réglages', exact: false }).first().click();
  await page.getByRole('combobox', { name: 'Langue de l’interface' }).selectOption('en');
  await expect(page.getByRole('navigation', { name: 'Main navigation' })).toContainText('Memory');
  await page
    .getByRole('navigation', { name: 'Main navigation' })
    .getByRole('button', { name: /^Memory/ })
    .click();
  await page.locator('.source-row').first().click();
  await expect(page.locator('.modal .markdown')).toBeVisible();
  expect(await page.locator('.modal .markdown').textContent()).toBe(originalDocument);
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Settings', exact: false }).first().click();
  await page.reload();
  await expect(page.getByRole('combobox', { name: 'Interface language' })).toHaveValue('en');

  // The public screenshot uses an isolated fixture, never a real memory bank.
  const preview = await browser.newPage({
    viewport: { width: 1440, height: 1000 },
    locale: 'fr-CA',
  });
  preview.on('pageerror', (error) => errors.push(error.message));
  await preview.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    localStorage.setItem('hindsight-desktop-theme-v2', 'dark');
    const timestamp = '2026-11-04T14:30:00Z';
    const names = [
      'Designing a simpler workspace',
      'Choosing a durable architecture',
      'Prototype feedback and next steps',
      'First evaluation results',
      'Clarifying the source collection workflow',
      'Adding provenance to search results',
      'Comparing memory strategies',
      'Design decisions — November',
      'Preparing a reproducible evaluation',
      'Reference model performance report',
      'Notes on thermal comfort',
      'Preserving context between sessions',
    ];
    const records = names.map((title, index) => ({
      id: `public-example-${index}`,
      title,
      kind: ['conversations', 'github', 'wandb', 'benchmarks'][index % 4],
      project: index % 4 === 0 ? 'workshop' : 'horizon',
      project_name: index % 4 === 0 ? 'Workshop' : 'Horizon Project',
      repository: index % 3 === 0 ? 'horizon-app' : 'horizon-research',
      collected_at: timestamp,
      source_updated_at: timestamp,
      context: { provider: index % 2 ? 'claude-code' : 'codex', directory: 'horizon-app' },
      files: { 'document.md': `examples/${index}/document.md` },
      memory: {
        state: index % 4 === 0 ? 'new' : 'current',
        enabled: true,
        stored: index % 4 !== 0,
      },
    }));
    const snapshot = {
      app: {
        connected: true,
        bank: 'horizon',
        banks: [{ bank_id: 'horizon', name: 'Horizon Project', fact_count: 2648 }],
        serverURL: 'http://127.0.0.1:8888',
        paused: [],
      },
      section: 'sources',
      confirmations: [],
      messages: [],
      data: {
        folder: '/Example/horizon-memory',
        canCollect: true,
        catalog: {
          version: 1,
          generated_at: timestamp,
          records,
          sources: ['conversations', 'github', 'wandb', 'benchmarks'].map((kind, index) => ({
            id: `example-collector-${index}`,
            kind,
            status: 'ok',
            count: 3,
          })),
        },
      },
    };
    window.__TAURI_INTERNALS__ = { invoke: async () => structuredClone(snapshot) };
  });
  await preview.goto('http://127.0.0.1:1426/');
  await expect(preview.getByRole('heading', { name: 'Memory', exact: true })).toBeVisible();
  await expect(preview.locator('.source-row')).toHaveCount(12);
  await preview.screenshot({
    path: fileURLToPath(new URL('../../docs/images/hindsight-desktop.png', import.meta.url)),
  });

  // The native titlebar is absent in Chromium; verify its reserved area under
  // the Tauri layout, including the sidebar scroll that caused the overlap.
  await preview.getByRole('button', { name: 'Advanced', exact: true }).click();
  for (const width of [1440, 1200, 980]) {
    await preview.setViewportSize({ width, height: 680 });
    for (const theme of ['dark', 'light']) {
      if ((await preview.locator('html').getAttribute('data-theme')) !== theme)
        await preview.getByRole('button', { name: `Use ${theme} theme`, exact: true }).click();
      const sidebar = preview.locator('.sidebar');
      const scroll = preview.locator('.sidebar-scroll');
      const drag = preview.locator('.window-drag');
      const reserved = await drag.boundingBox();
      expect(reserved.y).toBe(0);
      expect(reserved.height).toBeGreaterThanOrEqual(32);
      expect((await scroll.boundingBox()).y).toBeGreaterThanOrEqual(reserved.y + reserved.height);
      await scroll.evaluate((element) => {
        element.scrollTop = 0;
      });
      const activeRow = await preview.locator('.nav-item.active').boundingBox();
      const activeUnderTitlebar = activeRow.y + activeRow.height / 2 - 18;
      for (const position of [100, activeUnderTitlebar, 10000, 0]) {
        await scroll.evaluate((element, value) => {
          element.scrollTop = value;
        }, position);
        if (position)
          expect(await scroll.evaluate((element) => element.scrollTop)).toBeGreaterThan(0);
        expect(await drag.boundingBox()).toEqual(reserved);
        expect(await sidebar.evaluate((element) => element.scrollTop)).toBe(0);
        for (const x of [18, 50])
          expect(
            await preview.evaluate(
              (left) => !!document.elementFromPoint(left, 18)?.closest('button, a, input, select'),
              x,
            ),
          ).toBe(false);
      }
      await preview.locator('.workspace-switch').click();
      const menu = preview.locator('.bank-menu');
      await expect(menu).toBeVisible();
      const menuBounds = await menu.boundingBox();
      const sidebarBounds = await sidebar.boundingBox();
      expect(menuBounds.x + menuBounds.width).toBeLessThanOrEqual(
        sidebarBounds.x + sidebarBounds.width,
      );
      await preview.getByRole('button', { name: 'Close memory bank menu', exact: true }).click();
    }
  }
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'English default, saved languages and unchanged content verified. Native titlebar space stays clear while scrolling, in both themes and three window widths.',
  );
} finally {
  await browser?.close();
  server.kill();
}
