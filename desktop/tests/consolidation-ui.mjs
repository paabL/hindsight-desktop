import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect as baseExpect } from '@playwright/test';
import { createServer } from 'vite';

// The Overview and Processing must say the same thing about consolidation and the queue.
// Renders both pages with fictional data; no native bridge or Hindsight server is involved.
const fixture = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Dashboard } from '/src/pages/Explore.tsx';
import Operations from '/src/pages/Operations.tsx';
import { exampleSnapshot } from '/src/demo.ts';
import { takeMemoryTab } from '/src/memory-tab.ts';
import { I18nProvider } from '/src/i18n.tsx';
import '/src/styles.css';

const dashboard = exampleSnapshot('dashboard').data;
const operations = exampleSnapshot('operations').data;
const controls = (window.__consolidationFixture = { requests: [], navigations: [] });
const status = (phase) => ({
  enabled: phase !== 'disabled',
  automatic: false,
  pendingFacts: phase === 'upToDate' ? 0 : 27619,
  failedFacts: phase === 'upToDate' ? 0 : 3,
  lastConsolidatedAt: '2026-10-23T11:29:00Z',
  running: phase === 'running' ? 1 : 0,
  queued: phase === 'queued' ? 1 : 0,
  active: phase === 'running' || phase === 'queued' ? 1 : 0,
  phase,
});
function Fixture() {
  const [phase, setPhase] = useState('disabled');
  controls.setPhase = setPhase;
  const consolidation = status(phase);
  // The cached server statistics disagree on purpose: both pages must show the live counts.
  const overview = { ...dashboard, snapshot: { ...dashboard.snapshot,
    stats: { ...dashboard.snapshot.stats, pending_operations: 109, failed_operations: 9 },
    operationCounts: { pending: 73, processing: 8, failed: 2 }, consolidation } };
  const processing = { ...operations, counts: { pending: 73, processing: 8, failed: 2 },
    failedConsolidation: consolidation.failedFacts, consolidation };
  async function run(command, args = {}) {
    controls.requests.push({ command, args });
    return {};
  }
  const navigate = (section) => controls.navigations.push({ section, tab: takeMemoryTab('none') });
  const props = { run, busy: false, demo: false, navigate, refresh: async () => ({}),
    notify: (message) => { throw new Error(message); } };
  return React.createElement('div', null,
    React.createElement('section', { 'data-view': 'overview' },
      React.createElement(Dashboard, { ...props, data: overview })),
    React.createElement('section', { 'data-view': 'processing' },
      React.createElement(Operations, { ...props, data: processing })));
}
createRoot(document.getElementById('root')).render(
  React.createElement(I18nProvider, null, React.createElement(Fixture)));
`;

const server = await createServer({
  root: fileURLToPath(new URL('../', import.meta.url)),
  logLevel: 'error',
  server: { host: '127.0.0.1', port: 0, strictPort: true, hmr: false, watch: null },
  plugins: [
    {
      name: 'consolidation-fixture',
      resolveId(id) {
        if (id === '/__consolidation-fixture.tsx') return '\0consolidation-fixture.tsx';
      },
      load(id) {
        if (id === '\0consolidation-fixture.tsx') return fixture;
      },
      configureServer(vite) {
        vite.middlewares.use(async (request, response, next) => {
          if (request.url !== '/__consolidation-test') return next();
          try {
            const html = await vite.transformIndexHtml(
              request.url,
              '<html><body><div id="root"></div><script type="module" src="/__consolidation-fixture.tsx"></script></body></html>',
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
const deadline = setTimeout(() => {
  console.error('Consolidation regression exceeded 60 seconds.');
  process.exitCode = 1;
  void browser?.close();
  void server.close();
  setTimeout(() => process.exit(1), 2000).unref();
}, 60_000);
const expect = baseExpect.configure({ timeout: 5000 });
// French and English group digits differently (narrow no-break space or comma).
const bigNumber = /27[\s  ,.]?619/;

try {
  await server.listen();
  const base = `http://127.0.0.1:${server.httpServer.address().port}`;
  browser = await chromium.launch({
    headless: true,
    ...(process.env.HINDSIGHT_BROWSER_EXECUTABLE
      ? { executablePath: process.env.HINDSIGHT_BROWSER_EXECUTABLE }
      : { channel: 'chrome' }),
    timeout: 15_000,
  });
  for (const language of ['en', 'fr']) {
    const fr = language === 'fr';
    const tr = (french, english) => (fr ? french : english);
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1400 },
      serviceWorkers: 'block',
    });
    await context.route('**/*', (route) =>
      new URL(route.request().url()).origin === base ? route.continue() : route.abort(),
    );
    await context.addInitScript(
      (lang) => localStorage.setItem('hindsight-desktop-language', lang),
      language,
    );
    const page = await context.newPage();
    page.setDefaultTimeout(5000);
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(`${base}/__consolidation-test`);
    const overview = page.locator('[data-view="overview"]');
    const processing = page.locator('[data-view="processing"]');
    const queue = overview.locator('.queue-overview');
    const consolidateButton = processing.getByRole('button', {
      name: tr('Consolider', 'Consolidate'),
      exact: true,
    });
    const reconsolidate = processing.getByRole('button', {
      name: tr('Reconsolider 3 faits', 'Reconsolidate 3 facts'),
    });
    const setPhase = (phase) =>
      page.evaluate((value) => window.__consolidationFixture.setPhase(value), phase);

    // Live queue counts, the same on both pages, not the cached statistics (109 pending, 9 failed).
    await expect(queue.locator('> div').nth(0)).toContainText(tr('En attente', 'Pending'));
    await expect(queue.locator('> div').nth(0).locator('strong')).toHaveText('73');
    await expect(queue.locator('> div').nth(1)).toContainText(tr('En cours', 'Processing'));
    await expect(queue.locator('> div').nth(1).locator('strong')).toHaveText('8');
    await expect(queue.locator('> div').nth(2).locator('strong')).toHaveText('2');
    await expect(processing.locator('.operations-summary')).toContainText(
      tr('73en attente', '73pending'),
    );

    // Consolidation turned off for the bank: nothing to launch, and the reason with a way to the setting.
    const line = queue.locator('> div').nth(3);
    await expect(line).toContainText(tr('Désactivée', 'Turned off'));
    await expect(line).toContainText(tr('Dernière le 23 oct.', 'Last on Oct 23'));
    await expect(processing.locator('.consolidation-state')).toContainText(
      tr('Désactivée', 'Turned off'),
    );
    await expect(consolidateButton).toHaveCount(0);
    await expect(reconsolidate).toHaveCount(0);
    const notice = processing.locator('.notice.consolidation-off');
    await expect(notice).toContainText(
      tr('La consolidation est désactivée pour cette banque', 'Consolidation is turned off'),
    );
    await notice.getByRole('button', { name: tr('Ouvrir le réglage', 'Open the setting') }).click();
    assert.deepEqual(await page.evaluate(() => window.__consolidationFixture.navigations.at(-1)), {
      section: 'memory',
      tab: 'observations',
    });

    // Facts waiting: the same wording and number on both pages, and the action is offered.
    await setPhase('pending');
    await expect(line).toContainText(bigNumber);
    await expect(line).toContainText(tr('faits à consolider', 'facts to consolidate'));
    await expect(processing.locator('.consolidation-state')).toContainText(bigNumber);
    await expect(notice).toHaveCount(0);
    await expect(consolidateButton).toBeEnabled();
    await expect(reconsolidate).toBeVisible();
    await consolidateButton.click();
    assert.equal(
      await page.evaluate(() => window.__consolidationFixture.requests.at(-1).command),
      'operations.consolidate',
    );

    // Already running: visible but not offered twice.
    await setPhase('running');
    await expect(line).toContainText(tr('En cours', 'Processing'));
    await expect(consolidateButton).toBeDisabled();

    // Already queued: same, and the state does not claim it is running.
    await setPhase('queued');
    await expect(line).toContainText(tr('En attente', 'Pending'));
    await expect(processing.locator('.consolidation-state')).toContainText(
      tr('En attente', 'Pending'),
    );
    await expect(consolidateButton).toBeDisabled();

    // Nothing left: no action, and the state says so.
    await setPhase('upToDate');
    await expect(line).toContainText(tr('À jour', 'Up to date'));
    await expect(processing.locator('.consolidation-state')).toContainText(
      tr('À jour', 'Up to date'),
    );
    await expect(consolidateButton).toHaveCount(0);

    // A consolidation covers the whole bank: its row shows no technical identifier.
    await expect(processing.locator('.operation-row').filter({ hasText: 'op-1' })).toHaveCount(0);
    assert.deepEqual(errors, []);
    await context.close();
  }
  console.log('Consolidation regression passed in English and French.');
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  clearTimeout(deadline);
  await browser?.close();
  await server.close();
}
