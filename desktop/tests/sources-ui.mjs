import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '16429', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch('http://127.0.0.1:16429')).ok) break;
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
    let section = 'sources',
      revision = 'one',
      collectingUntil = 0;
    let rows = Array.from({ length: 12000 }, (_, i) => ({
      id: String(i),
      title:
        i === 0 ? 'Alpha source' : i === 1 ? 'Beta source' : `Source ${String(i).padStart(5, '0')}`,
      kind: 'documents',
      project: 'fixture',
      repository: 'repository',
      source_updated_at: '2026-11-04T12:00:00Z',
      files: { 'document.md': `${i}.md` },
      memory: {
        state: 'current',
        enabled: true,
        stored: true,
        locked: false,
        can_remove: true,
        document_id: String(i),
      },
    }));
    const app = {
      connected: true,
      bank: 'fixture',
      banks: [{ bank_id: 'fixture', name: 'Fixture' }],
      folder: '/Fixture',
      serverURL: 'http://127.0.0.1:8888',
      pause: { all: false, banks: [] },
    };
    const testState = (window.__sourceTest = { slow: 0, requests: [] });
    function snapshot(args = {}) {
      let data = {};
      if (section === 'sources') {
        data = {
          folder: '/Fixture',
          bank: 'fixture',
          listBank: 'fixture',
          open: '/Fixture',
          openKind: 'catalog',
          folders: [{ path: '/Fixture', name: 'Fixture', kind: 'catalog', sources: 12000 }],
          canCollect: true,
          catalogRevision: revision,
          collecting: performance.now() < collectingUntil,
        };
        if (args.sourceRevision === revision) data.catalogUnchanged = true;
        else
          data.catalog = {
            records: rows,
            projects: [{ id: 'fixture', name: 'Fixture' }],
            sources: [],
          };
      }
      return structuredClone({ app, section, data, confirmations: [], messages: [] });
    }
    window.__TAURI_INTERNALS__ = {
      invoke: async (cmd, payload) => {
        if (cmd !== 'bridge') throw new Error('Unexpected native call');
        const { command, args = {} } = payload.request;
        testState.requests.push(command);
        if (command === 'section') {
          section = args.section;
          if (section === 'sources' && testState.slow)
            await new Promise((r) => setTimeout(r, testState.slow));
        }
        if (command === 'folder.read') {
          await new Promise((r) => setTimeout(r, 20));
          return { text: args.path === '0.md' ? '# Alpha local' : '# Beta local' };
        }
        if (command === 'folder.stored') {
          await new Promise((r) => setTimeout(r, 400));
          return { text: '# Alpha stored — late reply' };
        }
        if (command === 'folder.enabled') {
          const base = revision;
          revision = 'two';
          rows = rows.map((r) =>
            r.id === args.id
              ? {
                  ...r,
                  memory: {
                    ...r.memory,
                    enabled: args.enabled,
                    state: args.enabled ? 'current' : 'excluded',
                  },
                }
              : r,
          );
          const result = snapshot();
          result.data.catalog = { sources: [], projects: [{ id: 'fixture', name: 'Fixture' }] };
          result.data.catalogDelta = {
            baseRevision: base,
            ids: rows.map((r) => r.id),
            records: rows.filter((r) => r.id === args.id),
          };
          return result;
        }
        if (command === 'folder.refresh') collectingUntil = performance.now() + 1000;
        return snapshot(args);
      },
    };
  });
  await page.goto('http://127.0.0.1:16429/#sources');
  await expect(page.locator('.source-row')).toHaveCount(30);
  const filter = page.getByRole('textbox', { name: 'Filter sources' });
  const start = Date.now();
  await filter.fill('Source 11999');
  await expect(page.locator('.source-row')).toHaveCount(1);
  const filterMs = Date.now() - start;
  await filter.fill('Alpha source');
  await page.locator('.source-row').click();
  await expect(page.locator('.modal .markdown')).toContainText('Alpha local');
  await page.getByRole('button', { name: 'Stored version', exact: true }).click();
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await filter.fill('Beta source');
  await page.locator('.source-row').click();
  await expect(page.locator('.modal .markdown')).toContainText('Beta local');
  await page.waitForTimeout(450);
  await expect(page.locator('.modal .markdown')).toContainText('Beta local');
  const included = page.getByRole('checkbox', { name: 'Include in updates' });
  await included.click();
  await expect(included).not.toBeChecked();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.getByRole('dialog')).toContainText('Excluded from uploads');
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await page.getByRole('button', { name: 'Collect sources', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Collecting…', exact: true })).toBeDisabled();
  await expect(filter).toBeEnabled();
  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  await nav.getByRole('button', { name: /^Overview/ }).click();
  await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toBeVisible();
  await page.evaluate(() => (window.__sourceTest.slow = 800));
  const back = Date.now();
  await nav.getByRole('button', { name: /^Documents/ }).click();
  await expect(page.locator('.source-row').first()).toBeVisible({ timeout: 500 });
  const reopenMs = Date.now() - back;
  await expect(page.getByRole('button', { name: 'Collect sources', exact: true })).toBeEnabled();
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    JSON.stringify({
      records: 12000,
      filterMs,
      reopenMs,
      staleReader: 'passed',
      deltaSelection: 'passed',
      backgroundNavigation: 'passed',
    }),
  );
} finally {
  await browser?.close();
  server.kill();
}
