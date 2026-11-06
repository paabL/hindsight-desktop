import assert from 'node:assert/strict';
import { chromium, expect } from '@playwright/test';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

const root = fileURLToPath(new URL('../', import.meta.url));
const port = Number(process.env.HINDSIGHT_MODEL_TEST_PORT || 16471);
assert.ok(Number.isInteger(port) && port >= 16450 && port < 65536);
const base = `http://127.0.0.1:${port}`;
const server = spawn(
  process.execPath,
  ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'],
  { cwd: root, stdio: 'ignore' },
);
let browser;
const errors = [];
const P = 'HINDSIGHT_API_';
const cases = [];
function check(name, fn) {
  cases.push({ name, fn });
}

async function open(page, mode = 'server') {
  await page.goto(`${base}/tests/support/model-workflow-fixture.html?mode=${mode}`);
  await expect.poll(() => page.evaluate(() => !!window.modelFixture?.update)).toBe(true);
}
async function calls(page) {
  return page.evaluate(() => window.modelFixture.calls);
}
const prepare = (dialog) =>
  dialog.getByRole('button', { name: 'Prepare these changes', exact: true });
const dialog = (page) => page.getByRole('dialog');
async function openRole(page, title) {
  await page
    .locator('.role-card')
    .filter({ has: page.getByRole('heading', { name: title, exact: true }) })
    .click();
  await expect(dialog(page)).toBeVisible();
  return dialog(page);
}

check(
  'admin rejects keep input for retry, and a delayed reply cannot close a newly opened dialog',
  async (page) => {
    await open(page, 'admin');
    const create = page.getByRole('button', { name: 'New bank', exact: true });
    await create.click();
    const editor = dialog(page);
    await editor.getByRole('textbox', { name: 'Name', exact: true }).fill('First bank');
    await editor.getByRole('textbox', { name: 'New bank ID', exact: true }).fill('bank-a');
    await page.evaluate(() => {
      window.modelFixture.failure = 'bank.create';
    });
    await editor.getByRole('button', { name: 'Continue', exact: true }).click();
    await expect.poll(() => page.evaluate(() => window.modelFixture.completed)).toBe(1);
    await expect(editor.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(
      'First bank',
    );
    await page.evaluate(() => {
      window.modelFixture.failure = '';
      window.modelFixture.delay = 220;
      const form = document.querySelector('.modal form');
      for (let i = 0; i < 25; i++) form.requestSubmit();
    });
    await expect.poll(async () => (await calls(page)).length).toBe(2);
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    await create.click();
    await editor.getByRole('textbox', { name: 'Name', exact: true }).fill('New unsaved bank');
    await expect.poll(() => page.evaluate(() => window.modelFixture.completed)).toBe(2);
    await expect(editor.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(
      'New unsaved bank',
    );
    assert.equal((await calls(page)).length, 2, 'rapid submissions send one request for the retry');
  },
);

check(
  'coverage waits for roots and offers the existing catalog folder only as an explicit action',
  async (page) => {
    await open(page, 'coverage');
    await expect(page.getByRole('status')).toContainText('Loading tracked folders');
    await expect(
      page.getByRole('heading', { name: 'Choose a folder to track', exact: true }),
    ).toHaveCount(0);
    assert.deepEqual(await calls(page), []);
    await page.evaluate(() =>
      window.modelFixture.update({
        roots: [],
        catalogFolder: '/fictional/catalog/',
        loaded: true,
      }),
    );
    const track = page.getByRole('button', { name: 'Track this folder', exact: true });
    await expect(track).toBeVisible();
    await expect(page.locator('.root-row')).toHaveCount(0);
    await expect(page.getByText('/fictional/catalog/', { exact: true })).toBeVisible();
    assert.deepEqual(await calls(page), [], 'opening a catalog must not register or collect it');
    await page.evaluate(() => {
      window.modelFixture.delay = 180;
      const button = [...document.querySelectorAll('button')].find((el) =>
        el.textContent.includes('Track this folder'),
      );
      for (let i = 0; i < 25; i++) button.click();
    });
    await expect(page.locator('.root-row')).toHaveCount(1);
    await expect(track).toHaveCount(0);
    assert.deepEqual(await calls(page), [
      { command: 'coverage.add', args: { paths: ['/fictional/catalog/'] } },
    ]);
  },
);

check(
  'coverage recognizes normalized tracked paths and never replaces an error with empty onboarding',
  async (page) => {
    await open(page, 'coverage');
    await page.evaluate(() =>
      window.modelFixture.update({
        roots: [{ path: '/fictional/catalog', allFiles: true, autoSync: false }],
        catalogFolder: '/fictional/./catalog///',
      }),
    );
    await expect(page.locator('.root-row')).toContainText('/fictional/catalog');
    await expect(page.getByRole('button', { name: 'Track this folder', exact: true })).toHaveCount(
      0,
    );
    await page.evaluate(() => window.modelFixture.update({ roots: [], loaded: false }));
    await expect(page.getByRole('status')).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Choose a folder to track', exact: true }),
    ).toHaveCount(0);
    await page.evaluate(() =>
      window.modelFixture.update({ loaded: true, error: 'Fixture cannot load tracked folders' }),
    );
    await expect(page.getByRole('alert')).toContainText('Fixture cannot load');
    await expect(
      page.getByRole('heading', { name: 'Choose a folder to track', exact: true }),
    ).toHaveCount(0);
    assert.deepEqual(await calls(page), []);
  },
);

check(
  'coverage failures preserve the proposed folder and refreshed selections never submit vanished IDs',
  async (page) => {
    await open(page, 'coverage');
    await page.evaluate(() => {
      window.modelFixture.failure = 'coverage.add';
      window.modelFixture.update({ roots: [], catalogFolder: '/fictional/catalog', loaded: true });
    });
    const track = page.getByRole('button', { name: 'Track this folder', exact: true });
    await track.click();
    await expect(page.getByRole('alert')).toContainText('Fixture rejects');
    await expect(track).toBeEnabled();
    await page.evaluate(() => {
      window.modelFixture.failure = '';
      window.modelFixture.update({
        // Le bouton n’annonce que les fichiers réellement envoyables (`canSend`, fourni par le moteur).
        items: [{ id: 'obsolete-id', title: 'Old source', state: 'modified', canSend: true }],
      });
    });
    await page.getByRole('checkbox', { name: 'Select all', exact: true }).check();
    await expect(page.getByRole('button', { name: 'Send (1)', exact: true })).toBeEnabled();
    await page.evaluate(() =>
      window.modelFixture.update({
        items: [{ id: 'new-id', title: 'New source', state: 'current' }],
      }),
    );
    await expect(page.getByRole('button', { name: 'Send (0)', exact: true })).toBeDisabled();
    await page.evaluate(() =>
      window.modelFixture.mount(
        'coverage',
        {
          roots: [{ path: '/fictional/bank-b', allFiles: false, autoSync: false }],
          catalogFolder: '/fictional/bank-b/',
          items: [{ id: 'new-id', title: 'Bank B source', state: 'current' }],
        },
        'bank-b',
      ),
    );
    await expect(page.locator('.root-row')).toContainText('/fictional/bank-b');
    await expect(page.getByRole('button', { name: 'Send (0)', exact: true })).toBeDisabled();
    assert.deepEqual(await calls(page), []);
  },
);

check('decision tabs support arrows, Home and End without preparing changes', async (page) => {
  await open(page);
  const editor = await openRole(page, 'Décision');
  await editor.getByRole('tab', { name: 'Model', exact: true }).focus();
  await page.keyboard.press('ArrowRight');
  await expect(editor.getByRole('tab', { name: 'Search', exact: true })).toBeFocused();
  await expect(
    editor.getByRole('combobox', { name: 'Recherche : fournisseur', exact: true }),
  ).toBeVisible();
  await page.keyboard.press('End');
  await expect(editor.getByRole('tab', { name: 'Knowledge', exact: true })).toHaveAttribute(
    'aria-selected',
    'true',
  );
  await page.keyboard.press('Home');
  await expect(editor.getByRole('tab', { name: 'Model', exact: true })).toBeFocused();
  assert.deepEqual(await calls(page), []);
});

check(
  'common action buttons do not submit forms; explicit and implicit submits still work',
  async (page) => {
    await open(page, 'controls');
    await page.getByRole('button', { name: 'Action', exact: true }).click();
    await page.getByRole('button', { name: 'Icon action', exact: true }).click();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 0);
    assert.equal(await page.evaluate(() => window.modelFixture.actions), 2);
    await expect(page.getByRole('button', { name: 'Disabled action', exact: true })).toBeDisabled();
    await page.getByRole('button', { name: 'Submit', exact: true }).click();
    await page.getByRole('button', { name: 'Explicit submit', exact: true }).click();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 2);
  },
);

check(
  'modal keyboard focus skips hidden and disabled controls and restores its trigger',
  async (page) => {
    await open(page, 'controls');
    const trigger = page.getByRole('button', { name: 'Open dialog', exact: true });
    await trigger.click();
    await expect(page.getByRole('textbox', { name: 'Visible input', exact: true })).toBeFocused();
    await dialog(page).getByRole('button', { name: 'Finish', exact: true }).focus();
    await page.keyboard.press('Tab');
    await expect(dialog(page).getByRole('button', { name: 'Close', exact: true })).toBeFocused();
    await page.keyboard.press('Shift+Tab');
    await expect(dialog(page).getByRole('button', { name: 'Finish', exact: true })).toBeFocused();
    await page
      .getByRole('textbox', { name: 'Outside input', exact: true })
      .evaluate((el) => el.focus());
    await page.keyboard.press('Tab');
    await expect(dialog(page).getByRole('button', { name: 'Close', exact: true })).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(dialog(page)).toHaveCount(0);
    await expect(trigger).toBeFocused();
    assert.equal(await page.evaluate(() => window.modelFixture.submits), 0);
  },
);

check(
  'cancelling role edits sends nothing and reopening uses the unchanged provider',
  async (page) => {
    await open(page);
    let editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    assert.deepEqual(await calls(page), []);
    editor = await openRole(page, 'Réponses');
    await expect(editor.getByRole('combobox', { name: 'Fournisseur', exact: true })).toHaveValue(
      'claude-code',
    );
  },
);

check(
  'a delayed rejected field stops the batch, retains the editor and accepts one retry',
  async (page) => {
    await open(page);
    const editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await editor.locator('.model-advanced > summary').click();
    await editor
      .getByRole('textbox', { name: 'Endpoint', exact: true })
      .fill('https://llm.fixture.invalid');
    await page.evaluate(() => {
      window.modelFixture.delay = 80;
      window.modelFixture.failure = 'HINDSIGHT_API_REFLECT_LLM_MODEL';
      const form = document.querySelector('.model-editor');
      for (let i = 0; i < 30; i++) form.requestSubmit();
    });
    await expect(editor.getByRole('alert')).toContainText('Fixture rejects this change');
    assert.deepEqual(
      (await calls(page)).map((c) => c.command),
      ['server.provider', 'server.field'],
    );
    assert.equal((await calls(page))[1].args.name, P + 'REFLECT_LLM_MODEL');
    await expect(editor.getByRole('textbox', { name: 'Endpoint', exact: true })).toHaveValue(
      'https://llm.fixture.invalid',
    );
    await page.evaluate(() => {
      window.modelFixture.failure = '';
    });
    await prepare(editor).click();
    await expect(editor).toHaveCount(0);
    assert.ok((await calls(page)).some((c) => c.args.name === P + 'REFLECT_LLM_BASE_URL'));
  },
);

check(
  'local and Cloud selection updates the URL immediately and preserves later explicit advanced fields',
  async (page) => {
    await open(page);
    const editor = await openRole(page, 'Décision');
    const provider = editor.getByRole('combobox', { name: 'Fournisseur', exact: true });
    await expect(provider).toHaveValue('__hindsight_local__');
    await provider.selectOption('hindsight');
    await editor.locator('.model-advanced > summary').click();
    const url = editor.getByRole('textbox', { name: 'URL de base', exact: true });
    await expect(url).toHaveValue('');
    await provider.selectOption('__hindsight_local__');
    await expect(url).toHaveValue('http://127.0.0.1:8766');
    await provider.selectOption('hindsight');
    await editor.getByLabel('API key', { exact: true }).fill('fixture-explicit-key');
    await url.fill('https://decision.fixture.invalid');
    await expect(provider).toHaveValue('__hindsight_custom__');
    await prepare(editor).click();
    await expect(editor).toHaveCount(0);
    const requests = await calls(page);
    assert.equal(requests[0].command, 'server.decision');
    assert.equal(requests[0].args.source, 'cloud');
    assert.ok(
      requests.some(
        (c) =>
          c.args.name === P + 'DECISION_MODEL_BASE_URL' &&
          c.args.value === 'https://decision.fixture.invalid',
      ),
    );
    assert.ok(
      requests.some(
        (c) =>
          c.args.name === P + 'DECISION_MODEL_API_KEY' && c.args.value === 'fixture-explicit-key',
      ),
    );
  },
);

check(
  'changed script/revision blocks stale edits, including a context change during a delayed response',
  async (page) => {
    await open(page);
    let editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await page.evaluate(() =>
      window.modelFixture.update({
        modelWorkflow: { ...window.modelFixture.data.modelWorkflow, revision: 'external-change' },
      }),
    );
    await expect(prepare(editor)).toBeDisabled();
    await expect(editor.getByRole('alert')).toContainText('Settings changed');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    editor = await openRole(page, 'Réponses');
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    await page.evaluate(() => {
      window.modelFixture.delay = 200;
      window.modelFixture.applyReplies = false;
    });
    await prepare(editor).click();
    await expect.poll(async () => (await calls(page)).length).toBe(1);
    await page.evaluate(() => window.modelFixture.update({ scriptPath: '/fictional/other.sh' }));
    await expect(editor.getByRole('alert')).toContainText('Settings changed');
    assert.equal(
      (await calls(page)).length,
      1,
      'the old batch must not write its remaining fields into a new script',
    );
  },
);

check(
  'workflow blocks repeated same-turn commands and keeps request errors visible',
  async (page) => {
    await open(page, 'workflow');
    await page.evaluate(() => {
      window.modelFixture.delay = 120;
      window.modelFixture.failure = 'server.models.prepare';
      const toggle = document.querySelector('input[role="switch"]');
      for (let i = 0; i < 40; i++) toggle.click();
    });
    await expect(page.getByRole('alert')).toContainText('Fixture rejects this change');
    assert.equal((await calls(page)).length, 1);
    await expect(page.getByRole('switch')).toBeEnabled();
  },
);

check(
  'memory polling preserves local edits, rejects non-object JSON and resets on bank remount',
  async (page) => {
    await open(page, 'memory');
    await page.evaluate(() =>
      window.modelFixture.update({ draft: { retainMission: 'Server mission' } }),
    );
    const mission = page.getByRole('textbox', { name: 'Memory mission', exact: true });
    await mission.fill('Local mission');
    await page.evaluate(() =>
      window.modelFixture.update({ draft: { retainMission: 'Server mission' } }),
    );
    await expect(mission).toHaveValue('Local mission');
    await page.getByRole('tab', { name: 'Advanced', exact: true }).click();
    const advanced = page.getByRole('textbox', {
      name: 'Advanced JSON configuration',
      exact: true,
    });
    for (const value of ['null', '[]', '42', '"text"']) {
      await advanced.fill(value);
      await page.getByRole('button', { name: 'Save changes', exact: true }).click();
    }
    assert.deepEqual(await calls(page), []);
    assert.equal(await page.evaluate(() => window.modelFixture.notifications.length), 4);
    await advanced.fill('{"retain_chunk_size": 1200}');
    await page.getByRole('button', { name: 'Save changes', exact: true }).click();
    const request = (await calls(page))[0];
    assert.equal(request.args.config.retain_mission, 'Local mission');
    assert.equal(request.args.config.retain_chunk_size, 1200);
    await page.evaluate(() =>
      window.modelFixture.mount('memory', { draft: { retainMission: 'Bank B mission' } }, 'bank-b'),
    );
    await expect(mission).toHaveValue('Bank B mission');
  },
);

check(
  'a large synthetic catalog keeps the selected custom model and changes providers coherently',
  async (page) => {
    await open(page);
    await page.evaluate(() => {
      const f = window.modelFixture;
      const models = Array.from({ length: 8000 }, (_, i) => ({
        id: `synthetic-${i}`,
        title: `Synthetic ${i}`,
      }));
      f.update({ modelsByProvider: { ...f.data.modelsByProvider, gemini: models } });
    });
    const editor = await openRole(page, 'Réponses');
    const start = performance.now();
    await editor.getByRole('combobox', { name: 'Fournisseur', exact: true }).selectOption('gemini');
    const models = editor.getByRole('combobox', { name: 'Modèle', exact: true });
    await expect(models).toHaveValue('synthetic-0');
    await models.selectOption('synthetic-7999');
    await expect(models).toHaveValue('synthetic-7999');
    await editor
      .getByRole('combobox', { name: 'Fournisseur', exact: true })
      .selectOption('claude-code');
    await expect(models).toHaveValue('claude-sonnet-5-5');
    assert.equal(await models.locator('option[value^="synthetic-"]').count(), 0);
    console.log(
      `  8,000-model selection/provider round trip: ${Math.round(performance.now() - start)} ms`,
    );
  },
);

try {
  for (let i = 0; i < 100; i++) {
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    if (server.exitCode != null || i === 99)
      throw new Error('Isolated model test server did not start');
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
  for (const { name, fn } of cases) {
    const page = await browser.newPage({ viewport: { width: 1100, height: 800 } });
    page.on('pageerror', (error) => errors.push(error.message));
    const started = performance.now();
    try {
      await fn(page);
      console.log(`PASS ${name} (${Math.round(performance.now() - started)} ms)`);
    } finally {
      await page.close();
    }
  }
  assert.deepEqual(errors, []);
  console.log(
    `${cases.length} isolated model/settings regressions passed; no bridge, app build or screenshots used.`,
  );
} finally {
  await browser?.close();
  server.kill();
}
