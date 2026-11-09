import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect as baseExpect } from '@playwright/test';
import { createServer } from 'vite';

// Render only the usage page with fictional data and an in-memory command recorder.
// No native bridge, account client, model or installed Hindsight app is involved.
const fixture = `
import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import Consumption from '/src/pages/Consumption.tsx';
import { exampleSnapshot } from '/src/demo.ts';
import { I18nProvider } from '/src/i18n.tsx';
import '/src/styles.css';

const sample = exampleSnapshot('consumption').data;
const controls = window.__consumptionFixture = {
  requests: [], demoKeys: Object.keys(sample), budgetKeys: Object.keys(sample.budgets),
};
function Fixture() {
  const [data, setData] = useState(sample);
  controls.installLegacy = () => setData(previous => ({ ...previous,
    codexQuota: { primary: { usedPercent: 95 } },
    claudeQuota: { primary: { usedPercent: 85 } },
    quotaProblems: ['Fictional quota problem'],
    budgets: { ...previous.budgets, codexQuotaPercent: 90,
      subscriptions: { 'openai-codex': { tokens5h: 1000 }, 'claude-code': { tokensWeek: 2000 } } },
    gauges: [
      { id: 'dollars.day', title: 'Daily USD', used: 0.42, limit: 5 },
      { id: 'codex.primary', title: 'Quota Codex', used: 95, limit: 90 },
      { id: 'sub.claude-code.week', title: 'Claude Code tokens', used: 400, limit: 2000 },
    ],
  }));
  async function run(command, args = {}) {
    controls.requests.push({ command, args });
    if (command === 'budget.save') setData(previous => ({ ...previous, budgets: args.budget }));
    else if (command === 'prices.save') setData(previous => ({ ...previous, prices: args.prices }));
    else throw new Error('Unexpected fixture command: ' + command);
    return {};
  }
  return React.createElement(Consumption, { data, run, busy: false, demo: false,
    notify: message => { throw new Error(message); } });
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
      name: 'consumption-fixture',
      resolveId(id) {
        if (id === '/__consumption-fixture.tsx') return '\0consumption-fixture.tsx';
      },
      load(id) {
        if (id === '\0consumption-fixture.tsx') return fixture;
      },
      configureServer(vite) {
        vite.middlewares.use(async (request, response, next) => {
          if (request.url !== '/__consumption-test') return next();
          try {
            const html = await vite.transformIndexHtml(
              request.url,
              '<html><body><div id="root"></div><script type="module" src="/__consumption-fixture.tsx"></script></body></html>',
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
// Bound the entire standalone check as well as individual browser operations.
const deadline = setTimeout(() => {
  console.error('Usage regression exceeded 60 seconds.');
  process.exitCode = 1;
  void browser?.close();
  void server.close();
  setTimeout(() => process.exit(1), 2000).unref();
}, 60_000);
const expect = baseExpect.configure({ timeout: 5000 });

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
    const context = await browser.newContext({
      viewport: { width: 1440, height: 1100 },
      serviceWorkers: 'block',
    });
    const external = [];
    await context.route('**/*', (route) => {
      if (new URL(route.request().url()).origin === base) return route.continue();
      external.push(route.request().url());
      return route.abort();
    });
    await context.addInitScript(
      (lang) => localStorage.setItem('hindsight-desktop-language', lang),
      language,
    );
    const page = await context.newPage();
    page.setDefaultTimeout(5000);
    page.setDefaultNavigationTimeout(10_000);
    const errors = [];
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(`${base}/__consumption-test`);
    await expect(
      page.getByRole('heading', { name: fr ? 'Consommation' : 'Usage', exact: true }),
    ).toBeVisible();
    await expect(page.locator('html')).toHaveAttribute('lang', language);

    const keys = await page.evaluate(() => window.__consumptionFixture);
    assert.ok(!keys.demoKeys.some((key) => /quota/i.test(key)));
    assert.ok(!keys.budgetKeys.some((key) => /quota|subscriptions/i.test(key)));
    const tokens = page
      .locator('.metric')
      .filter({ hasText: fr ? 'Jetons sur abonnement' : 'Subscription tokens' });
    await expect(tokens.locator(':scope > strong')).toContainText('206');
    await expect(page.locator('.chart-bar').first()).toBeVisible();
    await page.getByRole('tab', { name: fr ? '7 jours' : '7 days', exact: true }).click();
    await expect(
      page.getByRole('tab', { name: fr ? '7 jours' : '7 days', exact: true }),
    ).toHaveAttribute('aria-selected', 'true');
    await expect(page.getByRole('table')).toContainText('hs-decide-1-flash');
    await expect(page.getByRole('table')).toContainText('hs-rerank-1');
    await expect(page.getByRole('table')).toContainText('hs-embed-1');

    await page.evaluate(() => window.__consumptionFixture.installLegacy());
    // Seul le plafond en dollars par jour reste, lu sous le coût du jour qu'il borne.
    const today = page
      .locator('.metric')
      .filter({ hasText: fr ? 'Coût estimé aujourd’hui' : 'Estimated cost today' });
    await expect(today).toContainText(fr ? /Plafond : 5,00\s/ : /Limit: (US)?\$5\.00 per day/);
    await expect(today).toContainText(fr ? 'par jour (8 %)' : 'per day (8%)');
    await expect(page.locator('body')).not.toContainText(/Claude Code tokens|Quota Codex/);
    async function noQuotas() {
      await expect(page.locator('.quota-card, .quota-grid, .subscription-limits')).toHaveCount(0);
      await expect(page.locator('body')).not.toContainText(
        /quota|Limits per subscription|Plafonds par abonnement|Fictional quota problem/i,
      );
      await expect(
        page.getByRole('button', { name: /Check subscription quotas|Vérifier les quotas/ }),
      ).toHaveCount(0);
    }
    await noQuotas();

    const limits = () =>
      page.getByRole('button', { name: fr ? 'Mes plafonds' : 'My limits', exact: true }).click();
    const dialog = page.getByRole('dialog');
    const daily = dialog.getByRole('spinbutton', {
      name: fr ? 'Budget quotidien en dollars US' : 'Daily budget in US dollars',
      exact: true,
    });
    const save = () =>
      dialog
        .getByRole('button', { name: fr ? 'Enregistrer les plafonds' : 'Save limits', exact: true })
        .click();
    await limits();
    await noQuotas();
    await expect(dialog.getByRole('spinbutton')).toHaveCount(1);
    await expect(daily).toHaveValue('5');
    await daily.fill('12.5');
    await dialog.getByRole('checkbox').check();
    // Une seule action automatique : la pause. Plus de gel de la file.
    await expect(dialog.getByRole('combobox')).toHaveCount(0);
    await save();
    await expect(dialog).toHaveCount(0);
    let requests = await page.evaluate(() => window.__consumptionFixture.requests);
    assert.deepEqual(requests, [
      {
        command: 'budget.save',
        args: {
          budget: {
            dailyDollars: 12.5,
            warnAt: 0.8,
            action: 'softPause',
            actionConfirmed: true,
          },
        },
      },
    ]);

    await limits();
    await expect(daily).toHaveValue('12.5');
    await expect(dialog.getByRole('checkbox')).toBeChecked();
    await daily.fill('');
    await dialog.getByRole('checkbox').uncheck();
    await save();
    await expect(dialog).toHaveCount(0);
    requests = await page.evaluate(() => window.__consumptionFixture.requests);
    assert.deepEqual(requests.at(-1).args.budget, {
      dailyDollars: null,
      warnAt: 0.8,
      action: 'alert',
      actionConfirmed: false,
    });

    await page
      .getByRole('button', { name: fr ? 'Consulter les tarifs' : 'View prices', exact: true })
      .click();
    const priceText = dialog.getByRole('textbox', {
      name: fr ? 'Grille tarifaire JSON' : 'Price list JSON',
      exact: true,
    });
    await expect(priceText).toHaveValue(JSON.stringify({ models: [] }, null, 2));
    await priceText.fill('{"models":[],"fixture":true}');
    await dialog.getByRole('button', { name: fr ? 'Enregistrer' : 'Save', exact: true }).click();
    await expect(dialog).toHaveCount(0);
    requests = await page.evaluate(() => window.__consumptionFixture.requests);
    assert.equal(requests.length, 3);
    assert.deepEqual(requests.at(-1), {
      command: 'prices.save',
      args: { prices: { models: [], fixture: true } },
    });
    assert.ok(requests.every((request) => request.command !== 'subscription.refresh'));
    // La pause se règle dans Traitements, à un seul endroit.
    await expect(
      page.getByRole('button', { name: fr ? 'Mettre en pause' : 'Pause', exact: true }),
    ).toHaveCount(0);
    await noQuotas();
    assert.deepEqual(errors, []);
    assert.deepEqual(external, []);
    await context.close();
  }
  console.log(
    'Usage EN/FR: no quota controls or fixtures; subscription totals, charts, services, daily USD budget, legacy clearing and prices verified offline.',
  );
} finally {
  clearTimeout(deadline);
  await browser?.close();
  await server.close();
}
