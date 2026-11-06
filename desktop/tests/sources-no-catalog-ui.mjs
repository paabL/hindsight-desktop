import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Un dossier de documents ordinaire (sans catalog.json) n'est pas une erreur : pas de
// statistiques ni de collecte vides, seulement l'orientation vers les dossiers suivis.
const root = fileURLToPath(new URL('../', import.meta.url));
const port = 16432;
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(`http://127.0.0.1:${port}`)).ok) break;
    } catch {}
    if (i === 99) throw new Error('Vite unavailable');
    await new Promise((r) => setTimeout(r, 100));
  }
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    const snapshot = (section) => ({
      app: {
        connected: true,
        bank: 'garden',
        banks: [{ bank_id: 'garden', name: 'Garden notes', fact_count: 0 }],
        folder: '/Users/example/Notes',
        serverURL: 'http://127.0.0.1:8888',
        paused: [],
      },
      section,
      data:
        section === 'sources'
          ? {
              folder: '/Users/example/Notes',
              canCollect: false,
              catalogRevision: 'none',
              bank: 'garden',
              catalogMissing: true,
              bankMismatch: false,
              catalog: null,
            }
          : { roots: [], catalogFolder: '/Users/example/Notes', catalogFolderHasCatalog: false },
      confirmations: [],
      messages: [],
    });
    let section = 'sources';
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, payload) => {
        if (cmd !== 'bridge') throw new Error('Unexpected native call');
        const { command, args = {} } = payload.request;
        if (command === 'section' && args.section) section = args.section;
        return structuredClone(snapshot(section));
      },
    };
  });
  await page.goto(`http://127.0.0.1:${port}/#sources`);
  const notice = page.locator('.coverage-catalog-folder');
  await expect(notice).toContainText('No catalog in this folder');
  await expect(notice).toContainText('it will be tracked for the selected bank, “Garden notes”');
  await expect(page.locator('.archive-heading')).toContainText('No catalog');
  await expect(page.locator('.archive-stats')).toHaveCount(0);
  await expect(page.locator('.source-layout')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Collect sources' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Prepare upload to Hindsight' })).toHaveCount(0);
  await expect(page.getByRole('alert')).toHaveCount(0);
  if (process.env.SCREENSHOT) await page.screenshot({ path: process.env.SCREENSHOT });
  await notice.getByRole('button', { name: 'Open Tracked folders' }).click();
  const offer = page.locator('.coverage-catalog-folder');
  await expect(offer).toContainText('Folder open in the Catalog');
  await expect(offer).toContainText(
    'This folder has no catalog: it is an ordinary documents folder.',
  );
  await expect(offer.getByRole('button', { name: 'Track this folder' })).toBeVisible();
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(JSON.stringify({ noCatalogNotice: 'passed', trackingOffer: 'passed' }));
} finally {
  await browser?.close();
  server.kill();
}
