// Public documentation captures: current frontend, fictional data, no native bridge.
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = fileURLToPath(new URL('../../docs/images/', import.meta.url));
const origin = 'http://127.0.0.1:16430';
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', '16430', '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(origin)).ok) break;
    } catch {}
    if (i === 99 || server.exitCode != null) throw new Error('Preview server did not start');
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  await mkdir(output, { recursive: true });
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1100 },
    deviceScaleFactor: 1,
    locale: 'en-US',
    timezoneId: 'UTC',
  });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.route('**/*', (route) =>
    new URL(route.request().url()).origin === origin ? route.continue() : route.abort(),
  );
  await page.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    localStorage.setItem('hindsight-desktop-theme-v2', 'dark');
    const names = [
      'Designing a simpler workspace',
      'Choosing a durable architecture',
      'Prototype feedback and next steps',
      'First evaluation results',
      'Clarifying the source collection workflow',
      'Adding provenance to search results',
      'Comparing memory strategies',
      'Design decisions — November',
      'Preparing a reproducible evaluation',
      'Reference model performance report',
      'Notes on thermal comfort',
      'Preserving context between sessions',
    ];
    window.__TAURI_INTERNALS__ = {
      invoke: async (command, payload) => {
        if (command !== 'bridge')
          throw new Error('Native access is disabled in documentation captures');
        const { exampleSnapshot, exampleRequest } = await import('/src/demo.ts');
        const { command: action, args = {} } = payload?.request || {};
        // L’exemple garde le dossier ouvert ; les captures montrent ses chemins en anglais.
        if (action === 'folder.choose' || action === 'folder.close')
          await exampleRequest(
            action,
            { ...args, path: args.path?.replace('/Example/', '/Exemple/') },
            'sources',
          );
        const route = args.section || location.hash.slice(1) || 'dashboard';
        const snapshot = JSON.parse(
          JSON.stringify(exampleSnapshot(route)).replaceAll('/Exemple/', '/Example/'),
        );
        snapshot.app.banks = [{ bank_id: 'horizon', name: 'Horizon Project', fact_count: 2648 }];
        for (const folder of snapshot.data.folders || [])
          if (folder.collectedAt) folder.collectedAt = '2026-11-04T14:30:00Z';
        if (route === 'sources' && snapshot.data.openKind === 'catalog') {
          snapshot.data.refreshing = false;
          snapshot.data.catalog.generated_at = '2026-11-04T14:30:00Z';
          snapshot.data.catalog.projects = [
            { id: 'horizon', name: 'Horizon Project' },
            { id: 'workshop', name: 'Workshop' },
          ];
          snapshot.data.catalog.records = names.map((title, i) => ({
            id: `public-example-${i}`,
            title,
            kind: ['conversations', 'github', 'wandb', 'benchmarks'][i % 4],
            project: i % 4 === 0 ? 'workshop' : 'horizon',
            project_name: i % 4 === 0 ? 'Workshop' : 'Horizon Project',
            repository: i % 3 === 0 ? 'horizon-app' : 'horizon-research',
            collected_at: '2026-11-04T14:30:00Z',
            source_updated_at: '2026-11-04T12:00:00Z',
            files: { 'document.md': `examples/${i}/document.md` },
            memory: {
              state: i === 11 ? 'excluded' : i % 4 === 0 ? 'new' : 'current',
              enabled: i !== 11,
              locked: false,
              stored: i % 4 !== 0,
            },
          }));
          snapshot.data.catalog.sources = ['conversations', 'github', 'wandb', 'benchmarks'].map(
            (kind, i) => ({
              id: `collector-${i}`,
              kind,
              status: 'ok',
              count: 3,
              project: 'horizon',
              last_success_at: '2026-11-04T14:30:00Z',
            }),
          );
        }
        if (route === 'server') {
          snapshot.data.accounts.find((account) => account.id === 'hindsight').status =
            'Connecté à Example';
        }
        return snapshot;
      },
    };
  });
  await page.goto(`${origin}/#model-settings`);
  const workflow = page.getByRole('region', { name: 'Model settings' });
  await expect(workflow).toBeVisible();
  await expect(workflow.locator('[data-edge="decision-query"]')).toHaveCount(1);
  await expect(workflow.getByRole('combobox', { name: 'Decision model', exact: true })).toHaveValue(
    'local',
  );
  await expect(workflow.getByRole('button', { name: 'Save', exact: true })).toBeDisabled();
  await page.mouse.move(1420, 20);
  await page.screenshot({
    path: path.join(output, 'hindsight-desktop.png'),
    animations: 'disabled',
  });

  await page
    .getByRole('navigation', { name: 'Main navigation' })
    .getByRole('button', { name: /^Sources/ })
    .click();
  await expect(page.locator('.folder-row')).toHaveCount(2);
  await page.getByRole('button', { name: 'Use light theme', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.mouse.move(1420, 20);
  await page.screenshot({
    path: path.join(output, 'hindsight-sources.png'),
    animations: 'disabled',
  });
  await page.locator('.folder-row').filter({ hasText: 'horizon-memory' }).click();
  await expect(page.locator('.source-row')).toHaveCount(12);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.mouse.move(1420, 20);
  await page.screenshot({
    path: path.join(output, 'hindsight-catalog.png'),
    animations: 'disabled',
  });

  await page
    .getByRole('navigation', { name: 'Server and app settings' })
    .getByRole('button', { name: /^Models/ })
    .click();
  await page.getByRole('button', { name: 'Manage models', exact: true }).click();
  await expect(page.locator('.account-status-dot')).toHaveCount(3);
  await page
    .locator('.account-card')
    .screenshot({ path: path.join(output, 'hindsight-accounts.png'), animations: 'disabled' });
  if (errors.length) throw new Error(errors.join('\n'));
  console.log(
    'Documentation screenshots updated: Models, Sources, a catalog, account status. Fictional data only.',
  );
} finally {
  await browser?.close();
  server.kill();
}
