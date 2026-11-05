import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeSourceSnapshot } from '../src/source-snapshot.ts';

test('source deltas preserve unchanged rows, apply edits, additions, removals and server order', () => {
  const one = { id: 'one', memory: { enabled: true } },
    two = { id: 'two' },
    removed = { id: 'removed' };
  const old = { catalogRevision: 'a', catalog: { records: [one, two, removed] } };
  const changed = { id: 'one', memory: { enabled: false } },
    added = { id: 'added' };
  const incoming = {
    catalogRevision: 'b',
    catalog: { generated_at: 'now' },
    catalogDelta: { baseRevision: 'a', records: [changed, added], ids: ['two', 'one', 'added'] },
  };
  const merged = mergeSourceSnapshot(old, incoming);
  assert.deepEqual(merged.catalog.records, [two, changed, added]);
  assert.strictEqual(merged.catalog.records[0], two);
  assert.equal(old.catalog.records[0].memory.enabled, true);
  assert.equal(merged.catalog.generated_at, 'now');
  const poll = mergeSourceSnapshot(merged, {
    catalogRevision: 'b',
    catalogUnchanged: true,
    refreshing: false,
  });
  assert.strictEqual(poll.catalog, merged.catalog);
  assert.throws(
    () =>
      mergeSourceSnapshot(old, {
        ...incoming,
        catalogDelta: { ...incoming.catalogDelta, baseRevision: 'stale' },
      }),
    /Actualisez/,
  );
  assert.throws(
    () =>
      mergeSourceSnapshot(old, {
        ...incoming,
        catalogDelta: { ...incoming.catalogDelta, ids: ['unknown'] },
      }),
    /incomplet/,
  );
});

test('les deltas et réponses inchangées ne réutilisent jamais le catalogue d’un autre dossier', () => {
  const old = {
    folder: '/fixture/one',
    catalogRevision: 'a',
    catalog: { records: [{ id: 'one' }] },
  };
  for (const update of [
    { folder: '/fixture/two', catalogRevision: 'a', catalogUnchanged: true },
    {
      folder: '/fixture/two',
      catalogRevision: 'b',
      catalogDelta: { baseRevision: 'a', ids: ['one'], records: [] },
    },
  ])
    assert.throws(() => mergeSourceSnapshot(old, update), /Actualisez/);
  assert.throws(
    () =>
      mergeSourceSnapshot(
        { catalogRevision: 'a' },
        { catalogRevision: 'a', catalogUnchanged: true },
      ),
    /Actualisez/,
  );
});

test('un delta incomplet ou avec des identifiants répétés ne publie pas de catalogue partiel', () => {
  const delta = { baseRevision: 'a', ids: ['one', 'one'], records: [] };
  for (const catalog of [null, { records: [{ id: 'one' }] }]) {
    assert.throws(
      () =>
        mergeSourceSnapshot(
          { catalogRevision: 'a', catalog },
          { catalogRevision: 'b', catalogDelta: delta },
        ),
      /incomplet/,
    );
  }
});

test('vingt mille lignes et cinquante deltas conservent les identités et l’ordre exacts', () => {
  const rows = Array.from({ length: 20000 }, (_, i) => ({ id: String(i), title: `Source ${i}` }));
  let snapshot = { catalogRevision: '0', catalog: { records: rows } };
  const start = performance.now();
  for (let i = 1; i <= 50; i++) {
    const updated = { id: String(i), title: `Updated ${i}` };
    snapshot = mergeSourceSnapshot(snapshot, {
      catalogRevision: String(i),
      catalog: { generated_at: String(i) },
      catalogDelta: { baseRevision: String(i - 1), ids: rows.map((r) => r.id), records: [updated] },
    });
    assert.strictEqual(snapshot.catalog.records[19999], rows[19999]);
    assert.strictEqual(snapshot.catalog.records[i], updated);
    assert.equal(snapshot.catalog.records.length, 20000);
  }
  assert.equal(snapshot.catalog.records[1].title, 'Updated 1');
  console.log(
    JSON.stringify({
      sourceDeltaRows: rows.length,
      updates: 50,
      elapsedMs: Math.round(performance.now() - start),
    }),
  );
});
