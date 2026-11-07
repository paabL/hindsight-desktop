import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { chromium, expect } from '@playwright/test';
import { createServer } from 'vite';

const server = await createServer({
  root: fileURLToPath(new URL('../', import.meta.url)),
  logLevel: 'error',
  server: { host: '127.0.0.1', port: 16471, strictPort: true, hmr: false, watch: null },
});
let browser;
try {
  await server.listen();
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.addInitScript(() => {
    localStorage.setItem('hindsight-desktop-language', 'en');
    const fixture = (window.__stateFixture = {
      section: 'operations',
      bank: 'a',
      status: 'all',
      requests: [],
      pending: [],
      details: [],
      hold: false,
      // Chaque banque a ses propres dossiers ; un dossier ouvert l'est dans la banque choisie.
      folders: {
        a: [{ path: '/Fixture/a-notes', name: 'a-notes', kind: 'folder', files: 3, toSend: 1 }],
        b: [{ path: '/Fixture/b-notes', name: 'b-notes', kind: 'folder', files: 2, toSend: 0 }],
      },
      open: null,
    });
    const rows = Array.from({ length: 20000 }, (_, i) => ({
      id: `operation-${i}`,
      task_type: 'retain',
      status: i % 2 ? 'failed' : 'completed',
      document_id: `Document ${i}`,
      created_at: '2026-11-04T12:00:00Z',
    }));
    window.__TAURI_INTERNALS__ = {
      invoke: async (_command, args) => {
        const request = args?.request || {};
        fixture.requests.push(request);
        if (request.command === 'operation.open')
          return new Promise((resolve) => fixture.details.push({ id: request.args.id, resolve }));
        if (request.command === 'section') {
          fixture.section = request.args.section;
          if (request.args.status) fixture.status = request.args.status;
        }
        if (request.command === 'bank.select') {
          fixture.bank = request.args.id;
          fixture.status = 'all';
          fixture.open = null;
        }
        if (request.command === 'folder.choose') fixture.open = request.args.path;
        if (request.command === 'folder.close') fixture.open = null;
        const { exampleSnapshot } = await import('/src/demo.ts');
        const result = structuredClone(exampleSnapshot(fixture.section));
        result.app = {
          ...result.app,
          connected: true,
          connectionError: null,
          serverURL: 'http://127.0.0.1:9999',
          folder: null,
          bank: fixture.bank,
          banks: ['a', 'b'].map((id) => ({ bank_id: id, name: `Bank ${id}`, fact_count: 20000 })),
        };
        result.confirmations = [];
        result.messages = [];
        if (fixture.section === 'operations') {
          const items = rows
            .filter((row) => fixture.status === 'all' || row.status === fixture.status)
            .map((row) => ({ ...row, document_id: `Bank ${fixture.bank}: ${row.document_id}` }));
          result.data = {
            items,
            total: items.length,
            canLoadMore: false,
            statusFilter: fixture.status,
            counts: { failed: 10000, completed: 10000 },
            error: null,
          };
        }
        if (fixture.section === 'sources') {
          const folders = fixture.folders[fixture.bank] || [];
          const open = folders.find((folder) => folder.path === fixture.open);
          result.data = {
            bank: fixture.bank,
            listBank: fixture.bank,
            folders,
            open: open ? open.path : null,
            openKind: open ? 'folder' : null,
            foldersLoading: false,
            ...(open && {
              compared: true,
              items: [{ id: 'note', title: 'note.md', state: 'notSent', canSend: true }],
            }),
          };
        }
        if (fixture.hold && request.command === 'section')
          return new Promise((resolve) =>
            fixture.pending.push({ request, resolve: () => resolve(result) }),
          );
        return result;
      },
    };
  });
  const start = performance.now();
  await page.goto('http://127.0.0.1:16471/#operations');
  await expect(page.locator('.operation-row')).toHaveCount(100);
  const firstPaintMs = Math.round(performance.now() - start);
  await expect(page.locator('.operations-list')).toContainText('20,000');
  await page.getByRole('button', { name: 'Show more', exact: true }).click();
  await expect(page.locator('.operation-row')).toHaveCount(200);

  // Every request captures its own result, then the network delivers replies in reverse order.
  await page.evaluate(() => (window.__stateFixture.hold = true));
  for (let i = 0; i < 12; i++) {
    await page.getByRole('tab', { name: i % 2 ? 'Completed' : 'Failed', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.__stateFixture.pending.length)).toBe(i + 1);
  }
  await page.evaluate(() => {
    const fixture = window.__stateFixture;
    fixture.hold = false;
    for (const pending of fixture.pending.splice(0).reverse()) pending.resolve();
  });
  await expect(page.getByRole('tab', { name: 'Completed', exact: true })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await expect(page.locator('.operation-row')).toHaveCount(100);
  await expect(page.locator('.operation-row .badge').first()).toHaveText('Completed');
  assert.equal(
    await page.locator('.operation-row .badge').filter({ hasText: 'Failed' }).count(),
    0,
  );

  // Two detail reads finish in reverse order; closing the current modal cannot reopen the old one.
  const detailButtons = page.getByRole('button', { name: 'Operation details', exact: true });
  await detailButtons.nth(0).click();
  await detailButtons.nth(1).click();
  await expect.poll(() => page.evaluate(() => window.__stateFixture.details.length)).toBe(2);
  await page.evaluate(() => window.__stateFixture.details[1].resolve({ id: 'newest-detail' }));
  await expect(page.getByRole('dialog')).toContainText('newest-detail');
  await page.getByRole('button', { name: 'Close', exact: true }).click();
  await page.evaluate(() => window.__stateFixture.details[0].resolve({ id: 'stale-detail' }));
  await expect(page.getByRole('dialog')).toHaveCount(0);

  await page.evaluate(() => (window.__stateFixture.hold = true));
  await page.getByRole('tab', { name: 'Failed', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.__stateFixture.pending.length)).toBe(1);
  await page.locator('.workspace-switch').click();
  await page.locator('.bank-menu').getByRole('button', { name: 'Bank b', exact: true }).click();
  await expect(page.locator('.workspace-switch')).toContainText('Bank b');
  await page.evaluate(() => {
    const fixture = window.__stateFixture;
    fixture.hold = false;
    for (const pending of fixture.pending.splice(0).reverse()) pending.resolve();
  });
  await expect(page.locator('.operation-row').first()).toContainText('Bank b:');
  await expect(page.locator('.operations-list')).not.toContainText('Bank a:');

  // The old « Tracked folders » link opens Sources, which waits for the bank's folders instead of
  // showing an empty list, and never tracks a folder by itself.
  await page.evaluate(() => (window.__stateFixture.hold = true));
  await page.evaluate(() => (location.hash = '#coverage'));
  await expect(page).toHaveURL(/#sources$/);
  await expect(page.getByText('Loading sources…', { exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.__stateFixture.pending.length)).toBe(1);
  await expect(page.getByText(/No folder feeds/)).toHaveCount(0);
  await page.evaluate(() => {
    const fixture = window.__stateFixture;
    fixture.hold = false;
    for (const pending of fixture.pending.splice(0)) pending.resolve();
  });
  const folderRows = page.locator('.folder-row');
  await expect(folderRows).toHaveCount(1);
  await expect(folderRows).toContainText('b-notes');
  await expect(folderRows).toContainText('2 files · up to date');

  // A folder opens on its files, and the back link returns to the bank's list.
  await folderRows.click();
  await expect(page.getByRole('heading', { name: 'b-notes', exact: true })).toBeVisible();
  await expect(page.getByRole('checkbox', { name: 'Select note.md' })).toBeVisible();
  await page.getByRole('button', { name: 'All sources', exact: true }).click();
  await expect(folderRows).toHaveCount(1);

  // Switching bank from an open folder closes it and lists only the other bank's folders.
  await folderRows.click();
  await expect(page.getByRole('heading', { name: 'b-notes', exact: true })).toBeVisible();
  for (const [bank, own, other] of [
    ['a', 'a-notes', 'b-notes'],
    ['b', 'b-notes', 'a-notes'],
  ]) {
    await page.locator('.workspace-switch').click();
    await page
      .locator('.bank-menu')
      .getByRole('button', { name: `Bank ${bank}`, exact: true })
      .click();
    await expect(folderRows).toHaveCount(1);
    await expect(folderRows).toContainText(own);
    await expect(page.locator('.source-folders')).not.toContainText(other);
  }
  assert.equal(
    await page.evaluate(
      () => window.__stateFixture.requests.filter((r) => r.command === 'coverage.add').length,
    ),
    0,
  );

  await page.evaluate(() => (location.hash = '#operations'));
  await expect(page.locator('.operation-row')).toHaveCount(100);
  await page.evaluate(() => (window.__stateFixture.hold = true));
  await page.getByRole('tab', { name: 'Failed', exact: true }).click();
  await expect.poll(() => page.evaluate(() => window.__stateFixture.pending.length)).toBe(1);
  await page
    .locator('.sidebar-bottom')
    .getByRole('button', { name: /Settings/ })
    .click();
  await page.getByRole('button', { name: 'Explore the example', exact: true }).click();
  await expect(page.locator('.demo-badge')).toBeVisible();
  await page.evaluate(() => {
    window.__stateFixture.hold = false;
    for (const pending of window.__stateFixture.pending.splice(0)) pending.resolve();
  });
  await expect(page.locator('.workspace-switch')).not.toContainText('Bank b');
  await expect(page.locator('.workspace-switch')).not.toContainText('Bank b');
  await expect(page.locator('.demo-badge')).toBeVisible();
  assert.deepEqual(errors, []);
  console.log(
    JSON.stringify({
      scenarios: 8,
      syntheticOperations: 20000,
      initiallyRendered: 100,
      firstPaintMs,
      reversedFilterReplies: 12,
      contextChanges: 4,
      autoTrackedFolders: 0,
    }),
  );
} finally {
  await browser?.close();
  await server.close();
}
