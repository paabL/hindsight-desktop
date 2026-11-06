import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect } from '@playwright/test';
import { createServer } from 'vite';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = 16464;
const fixture = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import Sources from '/src/pages/Sources.tsx';
import { I18nProvider } from '/src/i18n.tsx';
import '/src/styles.css';

const controls = window.__sourceFixture = { pending: [], requests: [], manual: false };
const rows = Array.from({ length: 12000 }, (_, i) => ({
  id: String(i), title: i === 0 ? 'Alpha source' : i === 1 ? 'Beta source' : 'Source ' + String(i).padStart(5, '0'),
  kind: 'documents', project: 'fixture', repository: 'repo', source_updated_at: '2026-11-04T12:00:00Z',
  files: { 'original.md': 'original-' + i + '.md', 'document.md': i + '.md' },
  memory: { state: 'current', enabled: true, stored: true, locked: false, can_remove: true,
    document_id: String(i), hash: 'local-' + i, stored_hash: 'stored-' + i },
}));
rows.push(...['excluded', 'current'].map((state, i) => ({
  id: 'review-' + i, title: 'Technical ' + state, kind: 'conversations', project: 'fixture',
  context: { conversation_kind: 'internal_review' }, files: { 'document.md': 'review-' + i + '.md' },
  memory: { state, enabled: false, locked: true, stored: false, document_id: 'review-' + i },
})));
function Fixture() {
  const [data, setData] = useState({ folder: '/Fixture', canCollect: true,
    catalog: { records: rows, projects: [{ id: 'fixture', name: 'Fixture' }], sources: [] } });
  const [context, setContext] = useState('server-a|bank-a|/Fixture');
  controls.setContext = setContext;
  controls.latest = data;
  controls.mutate = (id, change) => setData((previous) => ({ ...previous,
    catalog: { ...previous.catalog, records: previous.catalog.records.flatMap((row) => row.id !== id ? [row] :
      change === 'remove' ? [] : [{ ...row, memory: { ...row.memory, hash: 'changed' } }]) } }));
  controls.setFolder = (folder) => setData((previous) => ({ ...previous, folder }));
  async function run(command, args = {}) {
    controls.requests.push({ command, args });
    if (command === 'folder.enabled') {
      setData((previous) => ({ ...previous, catalog: { ...previous.catalog,
        records: previous.catalog.records.map((row) => row.id !== args.id ? row : {
          ...row, memory: { ...row.memory, enabled: args.enabled, state: args.enabled ? 'current' : 'excluded' },
        }),
      } }));
      return {};
    }
    if (command === 'folder.read' || command === 'folder.stored') {
      if (controls.manual) return await new Promise((resolve, reject) => controls.pending.push({ command, args, resolve, reject }));
      const record = controls.latest.catalog.records.find((row) => row.id + '.md' === args.path);
      return { text: args.path?.startsWith('original-') ? '# WRONG original export' :
        '# ' + (record?.memory.hash === 'changed' ? 'Changed Alpha' : args.path === '0.md' ? 'Alpha local' : 'Beta local') };
    }
    return {};
  }
  return React.createElement(Sources, { data, contextKey: context, run, busy: false, demo: false,
    notify: () => {}, navigate: () => {}, refresh: async () => {}, serverConnected: true, onExploreExample: () => {} });
}
createRoot(document.getElementById('root')).render(React.createElement(I18nProvider, null, React.createElement(Fixture)));
`;

const server = await createServer({
  root,
  logLevel: 'error',
  server: { host: '127.0.0.1', port, strictPort: true, hmr: false, watch: null },
  plugins: [
    {
      name: 'source-race-fixture',
      resolveId(id) {
        if (id === '/__sources-fixture.tsx') return '\0sources-fixture.tsx';
      },
      load(id) {
        if (id === '\0sources-fixture.tsx') return fixture;
      },
      configureServer(vite) {
        vite.middlewares.use(async (request, response, next) => {
          if (request.url !== '/__sources-test') return next();
          try {
            const html = await vite.transformIndexHtml(
              request.url,
              '<html><head></head><body><div id="root"></div><script type="module" src="/__sources-fixture.tsx"></script></body></html>',
            );
            response.setHeader('Content-Type', 'text/html');
            response.end(html);
          } catch (error) {
            next(error);
          }
        });
      },
    },
  ],
});
let browser;
try {
  await server.listen();
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1100 },
    reducedMotion: 'reduce',
  });
  page.setDefaultTimeout(10000);
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => localStorage.setItem('hindsight-desktop-language', 'en'));
  await page.goto(`http://127.0.0.1:${port}/__sources-test`);
  const list = page.locator('.source-list').first();
  const filter = page.getByRole('textbox', { name: 'Filter sources' });
  async function openSource(title) {
    await filter.fill(title);
    await expect(list.locator('.source-row')).toHaveCount(1);
    await expect(list.locator('.source-row')).toContainText(title);
    await list.locator('.source-row').click();
  }
  await expect(list.locator('.source-row')).toHaveCount(30);
  await page.getByRole('button', { name: 'Refresh Hindsight status', exact: true }).click();
  const check = await page.evaluate(() => window.__sourceFixture.requests.at(-1));
  assert.deepEqual(check, { command: 'section', args: { section: 'sources' } });
  const start = performance.now();
  for (let i = 0; i < 20; i++) await filter.fill(`Source ${String(11980 + i).padStart(5, '0')}`);
  await expect(list.locator('.source-row')).toHaveCount(1);
  await expect(list.locator('.source-row')).toContainText('Source 11999');
  const filterMs = Math.round(performance.now() - start);

  await openSource('Alpha source');
  await expect(page.locator('.modal .markdown')).toContainText('Alpha local');
  const included = page.getByRole('checkbox', { name: 'Include in updates' });
  for (let i = 0; i < 10; i++) await included.click();
  await expect(included).toBeChecked();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('button', { name: 'Close', exact: true }).click();

  await page.evaluate(() => (window.__sourceFixture.manual = true));
  const burst = performance.now();
  for (let i = 0; i < 12; i++) {
    await openSource(i % 2 === 0 ? 'Alpha source' : 'Beta source');
    if (i !== 11) await page.getByRole('button', { name: 'Close', exact: true }).click();
  }
  await page.evaluate(() => {
    const pending = window.__sourceFixture.pending;
    pending.at(-1).resolve({ text: '# Beta newest' });
    for (let i = pending.length - 2; i >= 0; i--)
      pending[i].resolve({ text: '# Stale Alpha ' + i });
  });
  await expect(page.locator('.modal .markdown')).toContainText('Beta newest');
  await expect(page.locator('.modal .markdown')).not.toContainText('Stale Alpha');
  const outOfOrderMs = Math.round(performance.now() - burst);

  await page.getByRole('button', { name: 'Stored version', exact: true }).click();
  await page.evaluate(() => window.__sourceFixture.mutate('1', 'remove'));
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.evaluate(() => {
    window.__sourceFixture.pending.at(-1).resolve({ text: '# Removed Beta — late' });
    window.__sourceFixture.manual = false;
  });
  await expect(page.getByRole('dialog')).toHaveCount(0);

  for (const nextContext of ['server-a|bank-b|/Fixture', 'server-b|bank-b|/Fixture']) {
    await openSource('Alpha source');
    await page.evaluate(() => (window.__sourceFixture.manual = true));
    await page.getByRole('button', { name: 'Stored version', exact: true }).click();
    await page.evaluate((context) => window.__sourceFixture.setContext(context), nextContext);
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(filter).toHaveValue('');
    await page.evaluate(() => {
      window.__sourceFixture.pending.at(-1).resolve({ text: '# Private old context' });
      window.__sourceFixture.manual = false;
    });
    await expect(page.getByRole('dialog')).toHaveCount(0);
  }

  await openSource('Alpha source');
  await page.evaluate(() => window.__sourceFixture.mutate('0', 'change'));
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await list.locator('.source-row').click();
  await expect(page.locator('.modal .markdown')).toContainText('Changed Alpha');
  await page.evaluate(() => (window.__sourceFixture.manual = true));
  await page.getByRole('button', { name: 'Stored version', exact: true }).click();
  await page.evaluate(() =>
    window.__sourceFixture.pending.at(-1).reject(new Error('Stored fixture unavailable')),
  );
  await expect(page.getByRole('dialog')).toContainText('Stored fixture unavailable');
  await expect(page.getByText('Loading source…', { exact: true })).toHaveCount(0);
  await page.evaluate(() => window.__sourceFixture.setFolder('/Other fixture'));
  await expect(page.getByRole('dialog')).toHaveCount(0);

  await filter.fill('');
  await page.getByRole('combobox', { name: 'Filter by memory status' }).selectOption('current');
  await page.getByText('Separate archives (2)', { exact: true }).click();
  const archives = page.locator('details.source-list');
  await expect(archives.locator('.source-row')).toHaveCount(1);
  await expect(archives.locator('.source-row')).toContainText('Technical current');
  const requests = await page.evaluate(() => window.__sourceFixture.requests);
  assert.equal(
    requests.filter(
      (request) =>
        !['section', 'folder.read', 'folder.stored', 'folder.enabled'].includes(request.command),
    ).length,
    0,
  );
  assert.deepEqual(errors, []);
  console.log(
    JSON.stringify({
      records: 12002,
      filterChanges: 20,
      filterMs,
      outOfOrderReplies: 12,
      outOfOrderMs,
      repeatedToggles: 10,
      contextChanges: 3,
      removedReader: 'passed',
      sourceVersion: 'passed',
      archiveFilter: 'passed',
    }),
  );
} finally {
  await browser?.close();
  await server.close();
}
