import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Un dossier mémoire déclaré pour une autre banque se consulte, mais ne s'envoie jamais
// dans la banque sélectionnée : bandeau, compteurs honnêtes, envoi bloqué, bascule proposée.
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
    const state = (window.__bankTest = { requests: [], bank: 'garden' });
    const rows = Array.from({ length: 40 }, (_, i) => ({
      id: `nomad:${i}`,
      title: `Nomad source ${i}`,
      kind: 'documents',
      project: 'nomad',
      project_name: 'NOMAD',
      repository: 'nomad-memory',
      source_updated_at: '2026-11-04T12:00:00Z',
      files: { 'document.md': `${i}.md` },
      memory: {
        state: 'other_bank',
        enabled: false,
        stored: false,
        locked: true,
        can_remove: false,
        document_id: `source:nomad:${i}`,
        reason:
          'Ce dossier est rattaché à la banque « nomad-rl ». Sélectionnez-la pour envoyer ou retirer ses sources.',
      },
    }));
    function snapshot() {
      const mismatch = state.bank !== 'nomad-rl';
      return structuredClone({
        app: {
          connected: true,
          bank: state.bank,
          banks: [
            { bank_id: 'garden', name: 'Garden notes', fact_count: 0 },
            { bank_id: 'nomad-rl', name: 'NOMAD RL', fact_count: 2187 },
          ],
          folder: '/Users/example/nomad-memory',
          serverURL: 'http://127.0.0.1:8888',
          paused: [],
        },
        section: 'sources',
        data: {
          folder: '/Users/example/nomad-memory',
          canCollect: true,
          catalogRevision: `${state.bank}-1`,
          boundBank: 'nomad-rl',
          bankMismatch: mismatch,
          bank: state.bank,
          catalogMissing: false,
          catalog: {
            records: mismatch
              ? rows
              : rows.map((r) => ({
                  ...r,
                  memory: {
                    ...r.memory,
                    state: 'current',
                    enabled: true,
                    stored: true,
                    locked: false,
                    reason: '',
                  },
                })),
            projects: [{ id: 'nomad', name: 'NOMAD' }],
            sources: [
              { id: 'docs', kind: 'documents', status: 'ok', count: 40, project: 'nomad' },
              { id: 'wandb', kind: 'wandb', status: 'disabled', count: 0, project: 'nomad' },
            ],
            generated_at: '2026-11-05T00:22:00Z',
          },
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
        if (command === 'bank.select') state.bank = args.id;
        return snapshot();
      },
    };
  }, process.env.THEME || '');
  await page.goto(`http://127.0.0.1:${port}/#sources`);
  const banner = page.getByRole('alert').filter({ hasText: 'This folder belongs to' });
  await expect(banner).toContainText(
    'This folder belongs to the “NOMAD RL” memory bank, not “Garden notes”.',
  );
  await expect(page.locator('.archive-heading')).toContainText('“NOMAD RL” memory bank');
  await expect(page.getByRole('button', { name: 'Prepare upload to Hindsight' })).toBeDisabled();
  const stats = page.locator('.archive-stats');
  await expect(stats).toContainText('Catalog sources');
  await expect(stats).toContainText('In “Garden notes”');
  await expect(stats.locator('div').nth(1).locator('strong')).toHaveText('0');
  await expect(page.locator('.source-row').first()).toContainText('Other memory bank');
  await expect(page.locator('.collector-card')).toContainText('1 active');
  if (process.env.SCREENSHOT) await page.screenshot({ path: process.env.SCREENSHOT });
  await banner.getByRole('button', { name: 'Switch to “NOMAD RL”' }).click();
  await expect(banner).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Prepare upload to Hindsight' })).toBeEnabled();
  const switched = await page.evaluate(() =>
    window.__bankTest.requests.some((r) => r.command === 'bank.select' && r.args.id === 'nomad-rl'),
  );
  if (!switched) throw new Error('The switch button did not select the folder’s bank');
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    JSON.stringify({ otherBankBanner: 'passed', uploadBlocked: 'passed', switchBank: 'passed' }),
  );
} finally {
  await browser?.close();
  server.kill();
}
