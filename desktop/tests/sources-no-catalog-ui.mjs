import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Un catalogue disparu pendant la consultation (catalog.json supprimé ou déplacé) n'est pas une erreur :
// ni statistiques ni collecte vides, seulement le retour aux sources, où le dossier devient ordinaire.
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
    const folder = '/Users/example/Notes';
    const state = (window.__noCatalogTest = { open: folder, requests: [] });
    // Le pont recalcule la nature des dossiers à chaque réponse : sans catalog.json, c'est un dossier ordinaire.
    const folders = [{ path: folder, name: 'Notes', kind: 'folder', files: 2, toSend: 2 }];
    const snapshot = (section) => ({
      app: {
        connected: true,
        bank: 'garden',
        banks: [{ bank_id: 'garden', name: 'Garden notes', fact_count: 0 }],
        folder: state.open,
        serverURL: 'http://127.0.0.1:8888',
        pause: { all: false, banks: [] },
      },
      section,
      data:
        section !== 'sources'
          ? {}
          : state.open
            ? {
                folder,
                open: folder,
                openKind: 'catalog',
                listBank: 'garden',
                folders,
                canCollect: false,
                catalogRevision: 'none',
                bank: 'garden',
                catalogMissing: true,
                bankMismatch: false,
                catalog: null,
              }
            : { bank: 'garden', listBank: 'garden', open: null, openKind: null, folders },
      confirmations: [],
      messages: [],
    });
    let section = 'sources';
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, payload) => {
        if (cmd !== 'bridge') throw new Error('Unexpected native call');
        const { command, args = {} } = payload.request;
        state.requests.push(command);
        if (command === 'section' && args.section) section = args.section;
        if (command === 'folder.close') state.open = null;
        return structuredClone(snapshot(section));
      },
    };
  });
  await page.goto(`http://127.0.0.1:${port}/#sources`);
  const notice = page.getByRole('status').filter({ hasText: 'no longer has a catalog' });
  await expect(notice).toContainText(
    'This folder no longer has a catalog (catalog.json not found).',
  );
  await expect(page.locator('.archive-stats')).toHaveCount(0);
  await expect(page.locator('.source-layout')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Collect sources' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Prepare upload to Hindsight' })).toHaveCount(0);
  await expect(page.getByRole('alert')).toHaveCount(0);
  if (process.env.SCREENSHOT) await page.screenshot({ path: process.env.SCREENSHOT });
  await page.getByRole('button', { name: 'All documents', exact: true }).click();
  const row = page.locator('.folder-row');
  await expect(row).toContainText('Notes');
  await expect(row).toContainText('2 files · 2 to upload');
  await expect(row.locator('.badge')).toHaveCount(0);
  const requests = await page.evaluate(() => window.__noCatalogTest.requests);
  if (requests.some((command) => command.startsWith('coverage.') || command === 'folder.refresh'))
    throw new Error(`A missing catalog triggered ${requests.join(', ')}`);
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(JSON.stringify({ missingCatalogNotice: 'passed', backToOrdinaryFolder: 'passed' }));
} finally {
  await browser?.close();
  server.kill();
}
