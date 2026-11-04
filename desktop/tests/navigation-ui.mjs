import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const base = 'http://127.0.0.1:1428';
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '1428', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
const errors = [];

// Expected destinations are a product contract, independent of navigation metadata.
const routes = [
  { id: 'dashboard', group: 'Overview' },
  { id: 'facts', group: 'Memory', list: 'Memory views', tab: 'Facts' },
  { id: 'documents', group: 'Memory', list: 'Memory views', tab: 'Documents' },
  { id: 'timeline', group: 'Memory', list: 'Memory views', tab: 'Timeline' },
  { id: 'graph', group: 'Memory', list: 'Memory views', tab: 'Graph' },
  { id: 'models', group: 'Knowledge' },
  { id: 'search', group: 'Search' },
  { id: 'sources', group: 'Sources', list: 'Source views', tab: 'Catalog' },
  { id: 'coverage', group: 'Sources', list: 'Source views', tab: 'Tracked folders' },
  { id: 'hermes', group: 'Sources', list: 'Source views', tab: 'Imports' },
  { id: 'operations', group: 'Activity', list: 'Activity views', tab: 'Processing' },
  { id: 'consumption', group: 'Activity', list: 'Activity views', tab: 'Usage' },
  { id: 'audit', group: 'Activity', list: 'Activity views', tab: 'Logs' },
  { id: 'settings', group: 'Settings', list: 'Settings views', tab: 'Application' },
  { id: 'admin', group: 'Settings', list: 'Settings views', tab: 'Memory bank' },
  { id: 'memory', group: 'Settings', list: 'Settings views', tab: 'Memory behavior' },
  { id: 'server', group: 'Settings', list: 'Settings views', tab: 'Server & models' },
];

async function hasRoute(page, id) {
  await expect.poll(() => page.evaluate(() => location.hash)).toBe(`#${id}`);
  await expect(page.locator('.page-header h1')).toBeVisible();
  await expect(page.getByText('This view could not be displayed', { exact: true })).toHaveCount(0);
}

async function selectedGroup(page, label, french = false) {
  const button =
    label === 'Settings' || label === 'Réglages'
      ? page.locator('.sidebar').getByRole('button', { name: new RegExp(`^${label}`) })
      : page
          .getByRole('navigation', { name: french ? 'Navigation principale' : 'Main navigation' })
          .getByRole('button', { name: new RegExp(`^${label}`) });
  await expect(button).toHaveClass(/active/);
}

try {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    if (server.exitCode != null || attempt === 99)
      throw new Error('Navigation test server did not start.');
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
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(`${base}/?demo=1`);
  await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toBeVisible();
  const nav = page.getByRole('navigation', { name: 'Main navigation' });
  await expect(nav.getByRole('button')).toHaveCount(6);
  await expect(nav).toContainText('Overview');
  await expect(nav).toContainText('Memory');
  await expect(nav).toContainText('Knowledge');
  await expect(nav).toContainText('Search');
  await expect(nav).toContainText('Sources');
  await expect(nav).toContainText('Activity');
  await expect(page.getByRole('button', { name: 'Advanced', exact: true })).toHaveCount(0);
  await selectedGroup(page, 'Overview');

  // Every existing deep link keeps its destination and reveals the owning group.
  for (const route of routes) {
    await page.goto(`${base}/?demo=1#${route.id}`);
    await hasRoute(page, route.id);
    await selectedGroup(page, route.group);
    if (route.list) {
      const tabs = page.getByRole('tablist', { name: route.list, exact: true });
      await expect(tabs).toBeVisible();
      await expect(tabs.getByRole('tab', { name: route.tab, exact: true })).toHaveAttribute(
        'aria-selected',
        'true',
      );
    }
  }

  // Group clicks restore the last tab; numbered shortcuts select group defaults.
  await page.goto(`${base}/?demo=1#graph`);
  await hasRoute(page, 'graph');
  await nav.getByRole('button', { name: /^Search/ }).click();
  await hasRoute(page, 'search');
  await nav.getByRole('button', { name: /^Memory/ }).click();
  await hasRoute(page, 'graph');
  await page.keyboard.press('Meta+2');
  await hasRoute(page, 'facts');
  await nav.getByRole('button', { name: /^Sources/ }).click();
  await page
    .getByRole('tablist', { name: 'Source views' })
    .getByRole('tab', { name: 'Imports', exact: true })
    .click();
  await hasRoute(page, 'hermes');
  await nav.getByRole('button', { name: /^Overview/ }).click();
  await nav.getByRole('button', { name: /^Sources/ }).click();
  await hasRoute(page, 'hermes');
  for (const [index, id] of [
    'dashboard',
    'facts',
    'models',
    'search',
    'sources',
    'operations',
  ].entries()) {
    await page.keyboard.press(`Meta+${index + 1}`);
    await hasRoute(page, id);
  }
  await page.keyboard.press('Meta+9');
  await hasRoute(page, 'operations');

  // Memory shows stored facts, with type filters and a route back to source text.
  await page.keyboard.press('Meta+2');
  await expect(page.locator('.fact-card')).toHaveCount(12);
  await page.getByRole('combobox', { name: 'Fact type', exact: true }).selectOption('observation');
  await expect(page.locator('.fact-card')).toHaveCount(4);
  await page
    .getByRole('textbox', { name: 'Filter loaded facts', exact: true })
    .fill('Une décision');
  await expect(page.locator('.fact-card')).toHaveCount(1);
  await page.getByRole('button', { name: 'Open source document', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.locator('.modal .markdown')).toContainText('Ceci est un document fictif');
  await page.getByRole('button', { name: 'Close', exact: true }).click();

  // Hash history must change the rendered view, selected tab and active group together.
  await page.goto(`${base}/?demo=1#graph`);
  await nav.getByRole('button', { name: /^Sources/ }).click();
  await hasRoute(page, 'sources');
  await page
    .getByRole('tablist', { name: 'Source views' })
    .getByRole('tab', { name: 'Tracked folders', exact: true })
    .click();
  await hasRoute(page, 'coverage');
  await page.goBack();
  await hasRoute(page, 'sources');
  await page.goBack();
  await hasRoute(page, 'graph');
  await selectedGroup(page, 'Memory');
  await page.goForward();
  await hasRoute(page, 'sources');
  await selectedGroup(page, 'Sources');

  await page.keyboard.press('Meta+k');
  await expect(page.locator('.command-list button')).toHaveCount(routes.length);
  await page.keyboard.press('Escape');
  await page.goto(`${base}/?demo=1#memory`);
  await page.reload();
  await hasRoute(page, 'memory');
  await selectedGroup(page, 'Settings');
  await page.keyboard.press('Meta+,');
  await page.getByRole('combobox', { name: 'Interface language' }).selectOption('fr');
  await expect(page.getByRole('navigation', { name: 'Navigation principale' })).toContainText(
    'Connaissances',
  );
  await page.keyboard.press('Meta+2');
  await hasRoute(page, 'facts');
  await selectedGroup(page, 'Mémoire', true);
  const memory = page.getByRole('tablist', { name: 'Vues de la mémoire', exact: true });
  await expect(memory.getByRole('tab', { name: 'Faits', exact: true })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await memory.getByRole('tab', { name: 'Chronologie', exact: true }).click();
  await hasRoute(page, 'timeline');
  await page.keyboard.press('Meta+6');
  await expect(page.getByRole('tablist', { name: 'Vues de l’activité' })).toBeVisible();
  await page.keyboard.press('Meta+,');
  await expect(page.getByRole('tablist', { name: 'Vues des réglages' })).toBeVisible();
  await page.keyboard.press('Meta+k');
  await page.getByRole('textbox', { name: 'Rechercher une vue', exact: true }).fill('reglages');
  await expect(page.locator('.command-list button')).toHaveCount(4);
  await page.keyboard.press('Escape');

  // The minimum supported size keeps all groups available without page overflow.
  for (const width of [1440, 1200, 980]) {
    await page.setViewportSize({ width, height: 680 });
    await expect(
      page.getByRole('navigation', { name: 'Navigation principale' }).getByRole('button'),
    ).toHaveCount(6);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(
      true,
    );
  }
  // A separate native fixture distinguishes loaded data from the bank's total,
  // and verifies that typing locally does not silently query the server.
  const factsPage = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  factsPage.on('pageerror', (error) => errors.push(error.message));
  await factsPage.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    const facts = [
      {
        id: 'fictional-fact-1',
        text: 'A stable architecture decision.',
        type: 'world',
        documentID: 'fictional-document',
      },
      { id: 'fictional-fact-2', text: 'The team prefers concise notes.', type: 'observation' },
    ];
    const fixture = { queries: [] };
    window.__navigationFixture = fixture;
    window.__TAURI_INTERNALS__ = {
      invoke: async (_command, args) => {
        const request = args?.request;
        let query = '';
        let type = 'all';
        if (request?.command === 'section' && typeof request.args.query === 'string') {
          query = request.args.query;
          type = request.args.type;
          fixture.queries.push({ query, type });
        }
        return {
          app: {
            connected: true,
            bank: 'fictional-bank',
            banks: [{ bank_id: 'fictional-bank', name: 'Fictional bank', fact_count: 45 }],
            serverURL: 'http://127.0.0.1:8888',
            paused: [],
          },
          section: 'facts',
          data: {
            facts: facts.filter(
              (fact) =>
                (!query || fact.text.includes(query)) && (type === 'all' || fact.type === type),
            ),
            total: 45,
            truncated: true,
            query,
            type,
          },
          confirmations: [],
          messages: [],
        };
      },
    };
  });
  await factsPage.goto(`${base}/#facts`);
  await expect(factsPage.locator('.fact-card')).toHaveCount(2);
  await expect(factsPage.getByRole('status')).toContainText('2 loaded out of 45');
  await expect(
    factsPage.getByText('Only the first 2 items out of 45 were loaded.', { exact: false }),
  ).toBeVisible();
  const localFilter = factsPage.getByRole('textbox', { name: 'Filter loaded facts', exact: true });
  await localFilter.fill('architecture');
  await expect(factsPage.locator('.fact-card')).toHaveCount(1);
  expect(await factsPage.evaluate(() => window.__navigationFixture.queries)).toEqual([]);
  await factsPage
    .getByRole('combobox', { name: 'Fact type', exact: true })
    .selectOption('observation');
  await expect(factsPage.locator('.fact-card')).toHaveCount(0);
  expect(await factsPage.evaluate(() => window.__navigationFixture.queries)).toEqual([]);
  await localFilter.fill('prefers');
  await expect(factsPage.locator('.fact-card')).toHaveCount(1);
  await factsPage.getByRole('button', { name: 'Search the bank', exact: true }).click();
  await expect
    .poll(() => factsPage.evaluate(() => window.__navigationFixture.queries))
    .toEqual([{ query: 'prefers', type: 'observation' }]);
  await expect(factsPage.locator('.fact-card')).toHaveCount(1);
  await expect(factsPage.locator('.fact-card')).toContainText('concise notes');
  await expect(factsPage.getByRole('status')).toContainText('Bank type: Observation');
  await factsPage.getByRole('button', { name: 'Clear search', exact: true }).click();
  await expect(localFilter).toHaveValue('');
  await expect(factsPage.getByRole('combobox', { name: 'Fact type', exact: true })).toHaveValue(
    'all',
  );
  await expect(factsPage.locator('.fact-card')).toHaveCount(2);
  expect(await factsPage.evaluate(() => window.__navigationFixture.queries)).toEqual([
    { query: 'prefers', type: 'observation' },
    { query: '', type: 'all' },
  ]);
  await factsPage.close();
  expect(errors).toEqual([]);
  console.log(
    'Navigation verified: six groups, seventeen deep links, contextual tabs, history, remembered tabs, shortcuts and both languages.',
  );
} finally {
  await browser?.close();
  server.kill();
}
