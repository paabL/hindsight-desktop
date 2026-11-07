import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Filet de sécurité : si la politique d'un catalogue ouvert désigne une autre banque (fichier modifié
// pendant la consultation), le catalogue reste consultable mais rien ne s'envoie dans la banque choisie :
// bandeau, compteurs honnêtes, envoi bloqué, bascule vers la banque du dossier ou retour à la liste.
const root = fileURLToPath(new URL('../', import.meta.url));
const port = 16431;
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
  await page.addInitScript((theme) => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    if (theme) localStorage.setItem('hindsight-desktop-theme-v2', theme);
    const folder = '/Users/example/orchard-archive';
    const state = (window.__bankTest = { requests: [], bank: 'garden', open: folder });
    const rows = Array.from({ length: 40 }, (_, i) => ({
      id: `orchard:${i}`,
      title: `Orchard source ${i}`,
      kind: 'documents',
      project: 'orchard',
      project_name: 'Orchard',
      repository: 'orchard-archive',
      source_updated_at: '2026-11-04T12:00:00Z',
      files: { 'document.md': `${i}.md` },
      memory: {
        state: 'other_bank',
        enabled: false,
        stored: false,
        locked: true,
        can_remove: false,
        document_id: `source:orchard:${i}`,
        reason:
          'Ce dossier est rattaché à la banque « orchard ». Sélectionnez-la pour envoyer ou retirer ses sources.',
      },
    }));
    function snapshot() {
      const mismatch = state.bank !== 'orchard';
      return structuredClone({
        app: {
          connected: true,
          bank: state.bank,
          banks: [
            { bank_id: 'garden', name: 'Garden notes', fact_count: 0 },
            { bank_id: 'orchard', name: 'Orchard', fact_count: 2187 },
          ],
          folder: state.open,
          serverURL: 'http://127.0.0.1:8888',
          paused: [],
        },
        section: 'sources',
        data: state.open
          ? {
              folder,
              open: folder,
              openKind: 'catalog',
              listBank: state.bank,
              folders: [{ path: folder, name: 'orchard-archive', kind: 'catalog', sources: 40 }],
              canCollect: true,
              catalogRevision: `${state.bank}-1`,
              boundBank: 'orchard',
              bankMismatch: mismatch,
              bank: state.bank,
              catalogMissing: false,
              catalog: {
                records: rows,
                projects: [{ id: 'orchard', name: 'Orchard' }],
                sources: [
                  { id: 'docs', kind: 'documents', status: 'ok', count: 40, project: 'orchard' },
                  { id: 'wandb', kind: 'wandb', status: 'disabled', count: 0, project: 'orchard' },
                ],
                generated_at: '2026-11-05T00:22:00Z',
              },
            }
          : {
              bank: state.bank,
              listBank: state.bank,
              open: null,
              openKind: null,
              folders: [
                {
                  path: folder,
                  name: 'orchard-archive',
                  kind: 'catalog',
                  sources: 40,
                  catalogBank: 'orchard',
                },
              ],
            },
        confirmations: [],
        messages: [],
      });
    }
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, payload) => {
        if (cmd !== 'bridge') throw new Error('Unexpected native call');
        const { command, args = {} } = payload.request;
        state.requests.push({ command, args });
        // Changer de banque referme le dossier ouvert, comme le pont.
        if (command === 'bank.select') {
          state.bank = args.id;
          state.open = null;
        }
        return snapshot();
      },
    };
  }, process.env.THEME || '');
  await page.goto(`http://127.0.0.1:${port}/#sources`);
  const banner = page.getByRole('alert').filter({ hasText: 'This folder belongs to' });
  await expect(banner).toContainText(
    'This folder belongs to the “Orchard” memory bank, not “Garden notes”.',
  );
  await expect(page.locator('.archive-heading')).toContainText('“Orchard” memory bank');
  await expect(page.getByRole('button', { name: 'Prepare upload to Hindsight' })).toBeDisabled();
  const stats = page.locator('.archive-stats');
  await expect(stats).toContainText('Catalog sources');
  await expect(stats).toContainText('In “Garden notes”');
  await expect(stats.locator('div').nth(1).locator('strong')).toHaveText('0');
  await expect(page.locator('.source-row').first()).toContainText('Other memory bank');
  await expect(page.locator('.collector-card')).toContainText('1 active');
  if (process.env.SCREENSHOT) await page.screenshot({ path: process.env.SCREENSHOT });
  await banner.getByRole('button', { name: 'Switch to “Orchard”' }).click();
  await expect(banner).toHaveCount(0);
  // Dans sa banque, le dossier figure parmi les sources, avec son catalogue.
  await expect(page.getByRole('heading', { name: 'Sources', exact: true })).toBeVisible();
  await expect(page.locator('.folder-row')).toContainText('orchard-archive');
  await expect(page.locator('.folder-row')).toContainText('40 collected sources');
  const switched = await page.evaluate(() =>
    window.__bankTest.requests.some((r) => r.command === 'bank.select' && r.args.id === 'orchard'),
  );
  if (!switched) throw new Error('The switch button did not select the folder’s bank');
  const uploads = await page.evaluate(
    () => window.__bankTest.requests.filter((r) => r.command.startsWith('folder.prepare')).length,
  );
  if (uploads) throw new Error('A foreign catalog prepared an upload');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    JSON.stringify({ otherBankBanner: 'passed', uploadBlocked: 'passed', switchBank: 'passed' }),
  );
} finally {
  await browser?.close();
  server.kill();
}
