import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect as baseExpect } from '@playwright/test';
import { createServer } from 'vite';

// Consolidation has one place, Memory › Consolidation: its state, the action that launches it, its scopes
// and what it changed in the observations. The Overview links to it and agrees with it; Processing no
// longer launches it. Renders the three pages with fictional data; no native bridge or Hindsight server.
const fixture = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Dashboard } from '/src/pages/Explore.tsx';
import Operations from '/src/pages/Operations.tsx';
import Consolidation from '/src/pages/Consolidation.tsx';
import { exampleSnapshot } from '/src/demo.ts';
import { takeMemoryTab } from '/src/memory-tab.ts';
import { I18nProvider } from '/src/i18n.tsx';
import '/src/styles.css';

const dashboard = exampleSnapshot('dashboard').data;
const operations = exampleSnapshot('operations').data;
const consolidationView = exampleSnapshot('consolidation').data;
const controls = (window.__consolidationFixture = { requests: [], navigations: [], refreshes: [] });
const raw = 37831;
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
  const [readOnly, setReadOnly] = useState(false);
  controls.setPhase = setPhase;
  controls.setReadOnly = setReadOnly;
  const consolidation = status(phase);
  // The cached server statistics disagree on purpose: both pages must show the live counts.
  const overview = { ...dashboard, snapshot: { ...dashboard.snapshot,
    stats: { ...dashboard.snapshot.stats, pending_operations: 109, failed_operations: 9 },
    operationCounts: { pending: 73, processing: 8, failed: 2 }, consolidation } };
  const processing = { ...operations, counts: { pending: 73, processing: 8, failed: 2 } };
  const pending = consolidation.pendingFacts;
  const view = { ...consolidationView, status: consolidation, rawFacts: raw,
    consolidatedFacts: raw - pending - consolidation.failedFacts,
    pace: pending ? { factsPerHour: 297, measuredSeconds: 3600, remainingSeconds: (pending / 297) * 3600 } : null,
    canLoadMore: true, consultationOnly: readOnly };
  async function run(command, args = {}) {
    controls.requests.push({ command, args });
    if (command === 'consolidation.sources')
      return { sources: [
        { id: 'fact-a', text: 'Source fact A', type: 'world' },
        { id: 'fact-b', text: 'Source fact B', type: 'experience', context: 'meeting' },
      ] };
    return {};
  }
  const navigate = (section) => controls.navigations.push({ section, tab: takeMemoryTab('none') });
  const refresh = async (args = {}) => { controls.refreshes.push(args); return {}; };
  const props = { run, busy: false, demo: false, navigate, refresh,
    notify: (message) => { throw new Error(message); } };
  return React.createElement('div', null,
    React.createElement('section', { 'data-view': 'overview' },
      React.createElement(Dashboard, { ...props, data: overview })),
    React.createElement('section', { 'data-view': 'processing' },
      React.createElement(Operations, { ...props, data: processing })),
    React.createElement('section', { 'data-view': 'consolidation' },
      React.createElement(Consolidation, { ...props, data: view })));
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
  console.error('Consolidation regression exceeded 90 seconds.');
  process.exitCode = 1;
  void browser?.close();
  void server.close();
  setTimeout(() => process.exit(1), 2000).unref();
}, 90_000);
const expect = baseExpect.configure({ timeout: 5000 });
// French and English group digits differently (narrow no-break space or comma).
const digits = (text) => new RegExp(text.replace(/(\d)(\d{3})$/, '$1[\\s\\u00a0\\u202f,.]?$2'));
const bigNumber = digits('27619');

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
    // React reports invalid markup (a block inside a button, a missing key) as console errors.
    page.on('console', (message) => message.type() === 'error' && errors.push(message.text()));
    await page.goto(`${base}/__consolidation-test`);
    const overview = page.locator('[data-view="overview"]');
    const processing = page.locator('[data-view="processing"]');
    const view = page.locator('[data-view="consolidation"]');
    const queue = overview.locator('.queue-overview');
    const line = queue.locator('> button.queue-row-link');
    const consolidateButton = view.getByRole('button', {
      name: tr('Consolider', 'Consolidate'),
      exact: true,
    });
    const reconsolidate = view.getByRole('button', {
      name: tr('Reconsolider 3 faits', 'Reconsolidate 3 facts'),
    });
    const headline = view.locator('.consolidation-headline');
    const fixtureState = () => page.evaluate(() => window.__consolidationFixture);
    const lastRequest = async () => (await fixtureState()).requests.at(-1);
    const lastNavigation = async () => (await fixtureState()).navigations.at(-1);
    const setPhase = (phase) =>
      page.evaluate((value) => window.__consolidationFixture.setPhase(value), phase);
    // Processing lists operations; it no longer launches or resumes consolidation.
    const processingOffersNoConsolidation = async () => {
      await expect(
        processing.getByRole('button', { name: /^(Consolider|Consolidate)$/ }),
      ).toHaveCount(0);
      await expect(processing.getByRole('button', { name: /Reconsolid/ })).toHaveCount(0);
      await expect(processing.locator('.consolidation-state')).toHaveCount(0);
      await expect(processing.locator('.notice.consolidation-off')).toHaveCount(0);
    };

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
    await expect(line).toContainText(tr('Désactivée', 'Turned off'));
    await expect(line).toContainText(tr('Dernière le 23 oct.', 'Last on Oct 23'));
    await expect(headline).toContainText(tr('Désactivée', 'Turned off'));
    await expect(consolidateButton).toHaveCount(0);
    await expect(reconsolidate).toHaveCount(0);
    await expect(view.getByRole('progressbar')).toHaveCount(0);
    await expect(view.locator('.observation-scopes')).toHaveCount(0);
    await expect(headline.getByRole('button', { name: tr('Réglages', 'Settings') })).toHaveCount(0);
    const notice = view.locator('.notice.consolidation-off');
    await expect(notice).toContainText(
      tr('La consolidation est désactivée pour cette banque', 'Consolidation is turned off'),
    );
    await notice.getByRole('button', { name: tr('Ouvrir le réglage', 'Open the setting') }).click();
    assert.deepEqual(await lastNavigation(), { section: 'memory', tab: 'observations' });
    await processingOffersNoConsolidation();

    // The Overview line leads to the consolidation view.
    await line.click();
    assert.deepEqual(await lastNavigation(), { section: 'consolidation', tab: 'none' });

    // Facts waiting: the same wording and number on the Overview, the action and its progress here.
    await setPhase('pending');
    await expect(line).toContainText(bigNumber);
    await expect(line).toContainText(tr('faits à consolider', 'facts to consolidate'));
    await expect(headline).toContainText(bigNumber);
    await expect(notice).toHaveCount(0);
    const progress = view.getByRole('progressbar');
    await expect(progress).toHaveAttribute('aria-valuenow', String(37831 - 27619 - 3));
    await expect(progress).toHaveAttribute('aria-valuemax', '37831');
    const advance = view.locator('.consolidation-advance');
    await expect(advance).toContainText(digits('10209'));
    await expect(advance).toContainText(digits('37831'));
    await expect(advance).toContainText(tr('faits consolidés sur', 'facts consolidated'));
    await expect(advance).toContainText(tr('27 %', '27%'));
    await expect(view.locator('.consolidation-pace')).toContainText(
      tr('297 faits par heure', '297 facts per hour'),
    );
    await expect(view.locator('.consolidation-pace')).toContainText(
      tr('il reste environ 3 j 21 h', 'about 3 d 21 h remain'),
    );
    await expect(view.locator('.observation-scopes')).toContainText(
      tr('Portées des observations', 'Observation scopes'),
    );
    await expect(view.locator('.observation-scopes .badge')).toHaveText(
      tr('6 portées', '6 scopes'),
    );
    await expect(consolidateButton).toBeEnabled();
    await consolidateButton.click();
    assert.equal((await lastRequest()).command, 'consolidation.consolidate');
    await expect(reconsolidate).toBeEnabled();
    await reconsolidate.click();
    assert.equal((await lastRequest()).command, 'consolidation.recover');
    await headline.getByRole('button', { name: tr('Réglages', 'Settings') }).click();
    assert.deepEqual(await lastNavigation(), { section: 'memory', tab: 'observations' });
    await processingOffersNoConsolidation();

    // Read-only connection: shown, not offered.
    await page.evaluate(() => window.__consolidationFixture.setReadOnly(true));
    await expect(consolidateButton).toBeDisabled();
    await expect(reconsolidate).toBeDisabled();
    await page.evaluate(() => window.__consolidationFixture.setReadOnly(false));

    // Already running: visible but not offered twice.
    await setPhase('running');
    await expect(line).toContainText(tr('En cours', 'Processing'));
    await expect(headline).toContainText(tr('En cours', 'Processing'));
    await expect(consolidateButton).toBeDisabled();

    // Already queued: same, and the state does not claim it is running.
    await setPhase('queued');
    await expect(line).toContainText(tr('En attente', 'Pending'));
    await expect(headline).toContainText(tr('En attente', 'Pending'));
    await expect(consolidateButton).toBeDisabled();

    // Nothing left: no action, no remaining time, and the state says so.
    await setPhase('upToDate');
    await expect(line).toContainText(tr('À jour', 'Up to date'));
    await expect(headline).toContainText(tr('À jour', 'Up to date'));
    await expect(consolidateButton).toHaveCount(0);
    await expect(reconsolidate).toHaveCount(0);
    await expect(view.locator('.consolidation-pace')).toHaveCount(0);
    await processingOffersNoConsolidation();
    // A consolidation covers the whole bank: its row in Processing shows no technical identifier.
    await expect(processing.locator('.operation-row').filter({ hasText: 'op-1' })).toHaveCount(0);

    // What consolidation changed, in Hindsight's words: observations created or updated, with their source facts.
    const changes = view.locator('.observation-changes');
    await expect(changes.locator('.card-header')).toContainText(
      tr(
        'Dernières 24 heures : 14 observations créées, 9 mises à jour.',
        'Last 24 hours: 14 observations created, 9 updated.',
      ),
    );
    const rows = changes.locator('.change-row');
    await expect(rows).toHaveCount(4);
    await expect(rows.nth(0).locator('.badge')).toHaveText([tr('Créée', 'Created')]);
    await expect(rows.nth(0)).toContainText(tr('Issue de 2 faits', 'Derived from 2 facts'));
    await expect(rows.nth(1).locator('.badge')).toHaveText([tr('Mise à jour', 'Updated')]);
    await expect(rows.nth(1)).toContainText(
      tr('Texte modifié · 1 fait source ajouté', 'Text rewritten · 1 source fact added'),
    );
    await expect(rows.nth(2).locator('.badge')).toHaveText([
      tr('Mise à jour', 'Updated'),
      tr('3 valeurs retirées', '3 values removed'),
    ]);
    await expect(rows.nth(3)).toContainText(
      tr('Texte inchangé · 1 fait source ajouté', 'Text unchanged · 1 source fact added'),
    );

    // A created observation reads its source facts once, when first opened.
    await rows.nth(0).locator('.change-row-head').click();
    assert.deepEqual(await lastRequest(), {
      command: 'consolidation.sources',
      args: { id: 'obs-created' },
    });
    await expect(rows.nth(0).locator('.change-detail h3')).toHaveText([
      tr('Faits sources', 'Source facts'),
    ]);
    await expect(rows.nth(0).locator('.change-sources li')).toHaveCount(2);
    await expect(rows.nth(0).locator('.change-sources')).toContainText('Source fact B');

    // A rewritten observation shows its text before and after, word by word; one row is open at a time.
    await rows.nth(1).locator('.change-row-head').click();
    await expect(changes.locator('.change-row.open')).toHaveCount(1);
    await expect(rows.nth(1).locator('.change-row-head')).toHaveAttribute('aria-expanded', 'true');
    const diff = rows.nth(1).locator('.text-diff');
    await expect(diff.locator('.diff-added')).not.toHaveCount(0);
    await expect(diff.locator('.diff-removed')).not.toHaveCount(0);
    const rebuilt = await diff.evaluate((element) => {
      const read = (kinds) =>
        [...element.children]
          .filter((span) => kinds.some((kind) => span.classList.contains(`diff-${kind}`)))
          .map((span) => span.textContent)
          .join('')
          .trim();
      return { after: read(['same', 'added']), before: read(['same', 'removed']) };
    });
    assert.equal(
      rebuilt.after,
      (await rows.nth(1).locator('.change-text').textContent()).trim(),
      'the unchanged and added words make the current text',
    );
    assert.notEqual(rebuilt.before, rebuilt.after);
    assert.equal(
      (await fixtureState()).requests.filter((r) => r.command === 'consolidation.sources').length,
      1,
    );

    // Values present before and missing now are named, with where to find them again.
    await rows.nth(2).locator('.change-row-head').click();
    await expect(rows.nth(2).locator('.notice.removed-values')).toContainText('12, 2026-10-14, 30');
    await expect(rows.nth(2).locator('.notice.removed-values')).toContainText(
      tr('historique de l’observation', 'observation’s history'),
    );

    // An unchanged text with a new source fact: no diff, the added fact from the history.
    await rows.nth(3).locator('.change-row-head').click();
    await expect(rows.nth(3).locator('.text-diff')).toHaveCount(0);
    await expect(rows.nth(3).locator('.change-detail h3')).toHaveText([
      tr('Faits sources ajoutés', 'Source facts added'),
    ]);
    await expect(rows.nth(3).locator('.change-sources li')).toHaveCount(1);
    assert.equal(
      (await fixtureState()).requests.filter((r) => r.command === 'consolidation.sources').length,
      1,
    );
    await rows.nth(3).locator('.change-row-head').click();
    await expect(changes.locator('.change-row.open')).toHaveCount(0);

    // Another period reloads the view; more changes come from the same window.
    await changes.getByRole('tab', { name: tr('7 jours', '7 days') }).click();
    assert.deepEqual((await fixtureState()).refreshes.at(-1), { period: 'week' });
    await changes
      .getByRole('button', { name: tr('Afficher plus de changements', 'Show more changes') })
      .click();
    assert.equal((await lastRequest()).command, 'consolidation.more');

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
