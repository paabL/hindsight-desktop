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
