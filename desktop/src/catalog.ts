import { translate as t, getLocale } from './i18n-core.ts';
import type { Row } from './types';
export type SourceKind = 'conversation' | 'git' | 'note' | 'report' | 'document';
export function sourceKind(kind: string): SourceKind {
  const value = (kind || '').toLowerCase();
  if (/conversation|codex|claude|hermes|chat/.test(value)) return 'conversation';
  if (/commit|git/.test(value)) return 'git';
  if (/wandb|note|run/.test(value)) return 'note';
  if (/report|rapport|benchmark/.test(value)) return 'report';
  return 'document';
}
export const kindLabels: Record<SourceKind, string> = {
  get conversation() {
    return t('Conversation', 'Conversation');
  },
  get git() {
    return t('Commit Git', 'Git commit');
  },
  get note() {
    return t('Note de recherche', 'Research note');
  },
  get report() {
    return t('Rapport', 'Report');
  },
  get document() {
    return t('Document', 'Document');
  },
};

export function catalogRecords(catalog: Row | null): Row[] {
  return Array.isArray(catalog?.records) ? catalog.records : [];
}

// The collector classifies normalized exports. A title is never enough to hide a source.
export function isAsideRecord(record: Row): boolean {
  return ['internal_review', 'empty_export'].includes(record.context?.conversation_kind);
}

export function asideLabel(record: Row): string {
  return record.context?.conversation_kind === 'empty_export'
    ? t('Export vide ou interrompu', 'Empty or interrupted export')
    : t('Validation interne de Codex', 'Internal Codex review');
}

export function sourceTextPath(record: Row): string | null {
  const files = record.files;
  if (!files) return null;
  // Match the core's upload source even when original/raw files precede it in the manifest.
  if (!Array.isArray(files) && typeof files === 'object') {
    const document = files['document.md'];
    if (typeof document === 'string') return document;
    if (document && typeof document.path === 'string') return document.path;
  }
  const candidates: unknown[] =
    typeof files === 'string'
      ? [files]
      : Array.isArray(files)
        ? files
        : Object.keys(files)
            .sort()
            .map((key) => files[key]);
  const paths = candidates.flatMap((file) =>
    typeof file === 'string'
      ? [file]
      : file && typeof file === 'object' && 'path' in file
        ? [String(file.path)]
        : [],
  );
  return (
    paths.find((p) => /\.(md|txt|markdown|tex)$/i.test(p)) ||
    paths.find((p) => /\.json$/i.test(p)) ||
    null
  );
}

/** A status toggle preserves the reader; a changed source or stored version invalidates it. */
export function sourceReaderKey(record: Row): string {
  return JSON.stringify([
    record.id,
    sourceTextPath(record),
    sourceOriginalPath(record),
    record.source_updated_at,
    record.memory?.document_id,
    record.memory?.hash,
    record.memory?.stored_hash,
  ]);
}

const normalized = (value: unknown) =>
  String(value || '')
    .normalize('NFC')
    .toLocaleLowerCase('fr');
// Champs consultables de chaque source, normalisés à la première recherche puis gardés tant que
// la réponse du moteur (et donc l'objet) reste la même : la frappe suivante ne les recalcule pas.
const searchFields = new WeakMap<Row, string[]>();
function fieldsOf(r: Row): string[] {
  let fields = searchFields.get(r);
  if (!fields) {
    fields = [
      r.title,
      r.repository,
      r.project,
      r.project_name,
      r.id,
      r.source_id,
      JSON.stringify(r.context || {}),
    ].map(normalized);
    if (typeof r === 'object') searchFields.set(r, fields);
  }
  return fields;
}

export function filterRecords(
  records: Row[],
  query: string,
  kind: string,
  project: string,
  repository = 'all',
): Row[] {
  const q = normalized(query.trim());
  let sorted = sortedRecords.get(records);
  if (!sorted) {
    sorted = [...records].sort((a, b) =>
      String(b.source_updated_at || b.collected_at || '').localeCompare(
        String(a.source_updated_at || a.collected_at || ''),
      ),
    );
    sortedRecords.set(records, sorted);
  }
  return sorted.filter(
    (r) =>
      (kind === 'all' ||
        (kind === 'research' && ['note', 'report', 'document'].includes(sourceKind(r.kind))) ||
        sourceKind(r.kind) === kind) &&
      (project === 'all' || r.project === project) &&
      (repository === 'all' || r.repository === repository) &&
      (!q || fieldsOf(r).some((v) => v.includes(q))),
  );
}
const sortedRecords = new WeakMap<Row[], Row[]>();

// Configured projects remain selectable before their first source is collected.
export function catalogProjects(catalog: Row | null): [string, string][] {
  const projects = new Map<string, string>();
  for (const r of catalogRecords(catalog))
    if (r.project) projects.set(r.project, r.project_name || r.project);
  for (const p of catalog?.projects || []) if (p.id) projects.set(p.id, p.name || p.id);
  return [...projects].sort((a, b) => a[1].localeCompare(b[1], getLocale()));
}

export function sourceOriginalPath(record: Row): string | null {
  if (record.kind !== 'documents') return null;
  return (
    (Object.values(record.files || {}).find(
      (p) => typeof p === 'string' && /\.(md|tex|pdf)$/i.test(p),
    ) as string) || null
  );
}
