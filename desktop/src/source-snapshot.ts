import type { Row } from './types';

/** Keep unchanged row objects (and their search indexes) across status updates. */
export function mergeSourceSnapshot(previous: Row | undefined, incoming: Row): Row {
  if (incoming.catalogUnchanged || incoming.catalogDelta) {
    if (
      !previous ||
      !Object.hasOwn(previous, 'catalog') ||
      (Object.hasOwn(incoming, 'folder') && previous.folder !== incoming.folder)
    )
      throw new Error('Actualisez la liste des sources.');
  }
  if (incoming.catalogUnchanged) {
    if (!previous || previous.catalogRevision !== incoming.catalogRevision)
      throw new Error('Actualisez la liste des sources.');
    return { ...incoming, catalog: previous.catalog };
  }
  if (!incoming.catalogDelta) return incoming;
  if (!previous || incoming.catalogDelta.baseRevision !== previous.catalogRevision)
    throw new Error('Actualisez la liste des sources.');
  if (!Array.isArray(previous.catalog?.records))
    throw new Error('Catalogue de sources incomplet ; actualisez la liste.');
  if (new Set(incoming.catalogDelta.ids).size !== incoming.catalogDelta.ids.length)
    throw new Error('Catalogue de sources incomplet ; actualisez la liste.');
  const byID = new Map((previous.catalog?.records || []).map((row: Row) => [row.id, row]));
  for (const row of incoming.catalogDelta.records) byID.set(row.id, row);
  const records = incoming.catalogDelta.ids.map((id: string) => {
    const row = byID.get(id);
    if (!row) throw new Error('Catalogue de sources incomplet ; actualisez la liste.');
    return row;
  });
  return { ...incoming, catalog: { ...incoming.catalog, records } };
}
