import { useI18n } from '../i18n';
import { translate as t, getLocale } from '../i18n-core';
import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowDownToLine,
  ArrowLeft,
  RefreshCw,
  ArrowRight,
  BookOpen,
  ChevronDown,
  CircleCheck,
  Clock3,
  FileChartColumnIncreasing,
  FileText,
  Folder,
  FolderOpen,
  FolderPlus,
  FolderSync,
  GitCommitHorizontal,
  Library,
  MessageSquare,
  Search,
  Send,
  Sparkles,
  Trash2,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
import {
  catalogRecords,
  catalogProjects,
  sourceOriginalPath,
  filterRecords,
  isAsideRecord,
  asideLabel,
  kindLabels,
  sourceKind,
  sourceTextPath,
  sourceReaderKey,
} from '../catalog';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  IconButton,
  Markdown,
  Modal,
  PageHeader,
  Step,
  bankLabel,
  date,
  number,
  shortName,
} from '../ui';
import { nativeSourceReason } from '../native-messages';
import { pickDirectory, pickDocuments } from '../transport';

type SourcesProps = PageProps & {
  serverConnected: boolean;
  banks?: Row[];
  onExploreExample: () => void;
  contextKey?: string;
};

/** Mêmes chemins malgré une barre finale ou une autre forme Unicode de « é ». */
function samePath(a: unknown, b: unknown): boolean {
  const normalized = (value: unknown) =>
    String(value || '')
      .normalize('NFC')
      .replace(/\/+$/, '');
  return Boolean(a) && normalized(a) === normalized(b);
}

function bankNamer(banks: Row[]) {
  return (id: unknown) => bankLabel(banks.find((x) => x.bank_id === id)) || String(id || '');
}

/** Retour à la liste des dossiers de la banque. */
function BackToSources({ run, busy }: { run: PageProps['run']; busy: boolean }) {
  return (
    <button className="back-link" disabled={busy} onClick={() => void run('folder.close')}>
      <ArrowLeft size={14} />
      {t('Toutes les sources', 'All sources')}
    </button>
  );
}

/**
 * Sources : les dossiers de ce Mac qui alimentent la banque choisie. Un dossier ordinaire montre ses fichiers
 * comparés à la banque ; un dossier à catalogue (collect.py) montre son catalogue.
 */
export default function Sources(props: SourcesProps) {
  useI18n();
  if (props.data.openKind === 'catalog') return <CatalogFolder {...props} />;
  if (props.data.openKind === 'folder') return <PlainFolder key={props.data.open} {...props} />;
  return <FolderList {...props} />;
}

const memoryLabels: Record<string, string> = {
  get new() {
    return t('À ajouter', 'To add');
  },
  get current() {
    return t('À jour', 'Up to date');
  },
  get modified() {
    return t('À mettre à jour', 'Update needed');
  },
  get queued() {
    return t('En cours', 'In progress');
  },
  get error() {
    return t('Source illisible', 'Unreadable source');
  },
  get failed() {
    return t('Échec du dernier envoi', 'Last upload failed');
  },
  get unsupported() {
    return t('Format non envoyable', 'Format not uploadable');
  },
  get unknown() {
    return t('État non vérifié', 'Unchecked status');
  },
  get excluded() {
    return t('Exclu des envois', 'Excluded from uploads');
  },
  get unlinked() {
    return t('Source à relier', 'Link this source');
  },
  get missing() {
    return t('Source absente du catalogue', 'Source missing from catalog');
  },
  get other_bank() {
    return t('Autre banque', 'Other memory bank');
  },
};

// Les documents de la banque hors catalogue n'ont pas de projet : le moteur les marque « En mémoire ».
function projectLabel(record: Row): string {
  if (String(record.id).startsWith('bank:')) return t('En mémoire', 'In memory');
  return String(record.project_name || record.project || '');
}

function collectorStatus(status: unknown): string {
  const value = String(status || '');
  if (/^(ok|success)/.test(value)) return t('OK', 'OK');
  if (/disabled/.test(value)) return t('Désactivé', 'Disabled');
  if (/partial/.test(value)) return t('Partiel', 'Partial');
  if (/error|fail/.test(value)) return t('Erreur', 'Error');
  if (/skip/.test(value)) return t('Ignoré', 'Skipped');
  return value || '—';
}

const kindIcons = {
  conversation: MessageSquare,
  git: GitCommitHorizontal,
  note: Sparkles,
  report: FileChartColumnIncreasing,
  document: FileText,
};

function CatalogFolder({
  data,
  run,
  busy,
  notify,
  demo,
  serverConnected,
  banks = [],
  contextKey,
}: SourcesProps) {
  const [query, setQuery] = useState('');
  const [memoryFilter, setMemoryFilter] = useState('all');
  const [linkSource, setLinkSource] = useState('');
  const [kind, setKind] = useState('all');
  const [project, setProject] = useState('all');
  const [repository, setRepository] = useState('all');
  const [asideOpen, setAsideOpen] = useState(false);
  const [asideLimit, setAsideLimit] = useState(30);
  const [limit, setLimit] = useState(30);
  const [selection, setSelected] = useState<Row | null>(null);
  const [selectionContext, setSelectionContext] = useState('');
  const [text, setText] = useState<string | null>(null);
  const [reading, setReading] = useState(false);
  const [readError, setReadError] = useState<string | null>(null);
  const readRequest = useRef(0);
  const [collectorsOpen, setCollectorsOpen] = useState(false);
  const [importFiles, setImportFiles] = useState<string[]>([]);
  const [importProject, setImportProject] = useState('');
  const [importError, setImportError] = useState<string | null>(null);
  useEffect(() => {
    readRequest.current++;
    setQuery('');
    setMemoryFilter('all');
    setLinkSource('');
    setKind('all');
    setProject('all');
    setRepository('all');
    setLimit(30);
    setAsideLimit(30);
    setAsideOpen(false);
    setSelected(null);
    setText(null);
    setReadError(null);
    setReading(false);
    setImportFiles([]);
    setImportProject('');
    setImportError(null);
    setCollectorsOpen(false);
  }, [data.folder, contextKey]);
  useEffect(
    () => () => {
      readRequest.current++;
    },
    [],
  );
  const searchQuery = useDeferredValue(query);
  const allRecords = useMemo(() => catalogRecords(data.catalog), [data.catalog]);
  const byID = useMemo(() => new Map(allRecords.map((r) => [r.id, r])), [allRecords]);
  const readerContext = JSON.stringify([data.folder, contextKey]);
  const currentSelection = selection ? byID.get(selection.id) : null;
  const selected =
    selection &&
    currentSelection &&
    selectionContext === readerContext &&
    sourceReaderKey(selection) === sourceReaderKey(currentSelection)
      ? currentSelection
      : null;
  useEffect(() => {
    if (selection && !selected) closeSource();
  }, [selection, selected]);
  const records = useMemo(() => allRecords.filter((r) => !isAsideRecord(r)), [allRecords]);
  const archives = useMemo(() => allRecords.filter(isAsideRecord), [allRecords]);
  const filteredArchives = useMemo(
    () =>
      asideOpen
        ? filterRecords(archives, searchQuery, kind, project, repository).filter(
            (r) => memoryFilter === 'all' || r.memory?.state === memoryFilter,
          )
        : [],
    [archives, searchQuery, kind, project, repository, memoryFilter, asideOpen],
  );
  const filtered = useMemo(
    () =>
      filterRecords(records, searchQuery, kind, project, repository).filter(
        (r) => memoryFilter === 'all' || r.memory?.state === memoryFilter,
      ),
    [records, searchQuery, kind, project, repository, memoryFilter],
  );
  // Comptes et listes dérivés du catalogue : recalculés à chaque réponse du moteur, pas à chaque rendu.
  const projects = useMemo(() => catalogProjects(data.catalog), [data.catalog]);
  const repositories = useMemo(
    () =>
      [
        ...new Set(
          allRecords
            .filter((r) => project === 'all' || r.project === project)
            .map((r) => r.repository)
            .filter(Boolean),
        ),
      ].sort((a, b) => a.localeCompare(b, getLocale())),
    [allRecords, project],
  );
  const counts = useMemo(
    () =>
      records.reduce<Record<string, number>>((acc, r) => {
        const k = sourceKind(r.kind);
        acc[k] = (acc[k] || 0) + 1;
        return acc;
      }, {}),
    [records],
  );
  // Le filtre d'état s'applique aussi aux archives à part : ses comptes les incluent.
  const stateCounts = useMemo(() => {
    const byState = new Map<unknown, number>();
    for (const r of allRecords)
      byState.set(r.memory?.state, (byState.get(r.memory?.state) || 0) + 1);
    return byState;
  }, [allRecords]);
  const enabledCount = useMemo(() => filtered.filter((r) => r.memory?.enabled).length, [filtered]);
  const toggleable = useMemo(
    () => filtered.filter((r) => !String(r.id).startsWith('bank:') && !r.memory?.locked),
    [filtered],
  );
  const toInclude = toggleable.filter((r) => !r.memory?.enabled);
  const toExclude = toggleable.filter((r) => r.memory?.enabled);
  const sources: Row[] = data.catalog?.sources || [];
  const activeSources = sources.filter((s) => !/disabled/.test(String(s.status || '')));
  // Sans catalogue lisible, le pont ne renvoie que les documents de la banque : rien à préparer.
  const hasCatalog = Boolean(data.catalog) && !data.catalogMissing;
  // Catalogue disparu depuis l'ouverture (fichier supprimé ou déplacé) : rien à collecter ni à préparer.
  const noCatalog = !demo && Boolean(data.folder) && Boolean(data.catalogMissing) && !data.error;
  // Le dossier appartient à la banque déclarée dans sa politique ; une autre banque ne fait que le consulter.
  const bankName = bankNamer(banks);
  const folderRow = (data.folders || []).find((row: Row) => samePath(row.path, data.open));
  const mismatch = !demo && Boolean(data.bankMismatch && data.boundBank);
  const boundBankExists = banks.some((b) => b.bank_id === data.boundBank);
  const catalogCount = useMemo(
    () => records.filter((r) => !String(r.id).startsWith('bank:')).length,
    [records],
  );
  const storedCount = useMemo(
    () => records.filter((r) => !String(r.id).startsWith('bank:') && r.memory?.stored).length,
    [records],
  );
  const problems = sources.filter((s) => /error|fail|partial/.test(s.status));

  async function chooseDocuments() {
    try {
      const paths = await pickDocuments();
      if (!paths.length) return;
      setImportFiles(paths);
      setImportProject(project !== 'all' ? project : projects[0]?.[0] || '');
      setImportError(null);
    } catch (error) {
      notify((error as Error).message);
    }
  }
  async function addDocuments() {
    setImportError(null);
    const result = await run('folder.import', { paths: importFiles, project: importProject });
    if (result.error || result.data?.error) {
      setImportError(result.error || result.data.error);
    } else if (result.confirmations?.length) {
      setImportFiles([]);
      setProject(importProject);
      setRepository('all');
      setQuery('');
      setKind('document');
      setLimit(30);
    }
  }
  function closeSource() {
    readRequest.current++;
    setSelected(null);
    setText(null);
    setReadError(null);
    setReading(false);
    setLinkSource('');
  }
  async function open(record: Row, stored = false) {
    const request = ++readRequest.current;
    setSelected(record);
    setSelectionContext(readerContext);
    setText(null);
    setReadError(null);
    setReading(false);
    const path = sourceTextPath(record);
    if (stored || (!path && record.memory?.stored)) {
      setReading(true);
      try {
        const result = await run('folder.stored', { id: record.id });
        if (request === readRequest.current) {
          setText(result.text || null);
          setReadError(result.error || null);
        }
      } catch (e) {
        if (request === readRequest.current) setReadError((e as Error).message);
      } finally {
        if (request === readRequest.current) setReading(false);
      }
      return;
    }
    if (!path) {
      if (!sourceOriginalPath(record))
        setReadError(
          t(
            'Cette source ne contient pas de version texte consultable.',
            'This source has no readable text version.',
          ),
        );
      return;
    }
    setReading(true);
    try {
      const result = await run('folder.read', { path });
      if (request !== readRequest.current) return;
      if (result.error) setReadError(result.error);
      else setText(result.text);
    } catch (e) {
      if (request === readRequest.current) setReadError((e as Error).message);
    } finally {
      if (request === readRequest.current) setReading(false);
    }
  }

  if (
    !demo &&
    !data.catalog &&
    (data.refreshing || busy || (data.folder && data.catalog === undefined))
  )
    return (
      <div className="loading-state" role="status">
        {t('Chargement des sources…', 'Loading sources…')}
      </div>
    );

  return (
    <>
      <BackToSources run={run} busy={busy} />
      <PageHeader
        title={data.folder ? shortName(data.folder) : t('Catalogue', 'Catalog')}
        description={
          data.bank
            ? t(
                `Catalogue de ce dossier : les conversations, commits, rapports et documents rassemblés par son collecteur, et leur état dans « ${bankName(data.bank)} ».`,
                `This folder’s catalog: conversations, commits, reports and documents gathered by its collector, and their status in “${bankName(data.bank)}”.`,
              )
            : t(
                'Catalogue de ce dossier : les conversations, commits, rapports et documents rassemblés par son collecteur.',
                'This folder’s catalog: conversations, commits, reports and documents gathered by its collector.',
              )
        }
        actions={
          <>
            {!noCatalog && (
              <>
                <Button
                  icon={FolderPlus}
                  disabled={busy || data.collecting || !data.canCollect || !projects.length || demo}
                  onClick={() => void chooseDocuments()}
                >
                  {t('Ajouter des documents', 'Add documents')}
                </Button>
                <Button
                  icon={FolderSync}
                  disabled={busy || data.collecting || !data.canCollect || demo}
                  title={t(
                    'Lance le collecteur du dossier : met à jour le catalogue de ce Mac, sans rien envoyer à Hindsight.',
                    'Runs the folder’s collector: updates this Mac’s catalog without uploading anything to Hindsight.',
                  )}
                  onClick={() => void run('folder.refresh')}
                >
                  {data.collecting && !data.importing
                    ? t('Collecte en cours…', 'Collecting…')
                    : t('Collecter les sources', 'Collect sources')}
                </Button>
                <Button
                  icon={ArrowDownToLine}
                  kind="primary"
                  disabled={
                    busy || data.collecting || !hasCatalog || !serverConnected || demo || mismatch
                  }
                  title={
                    mismatch
                      ? t(
                          `Ce dossier appartient à la banque « ${bankName(data.boundBank)} ».`,
                          `This folder belongs to the “${bankName(data.boundBank)}” memory bank.`,
                        )
                      : undefined
                  }
                  onClick={() => void run('folder.prepare')}
                >
                  {t('Préparer l’envoi à Hindsight', 'Prepare upload to Hindsight')}
                </Button>
              </>
            )}
            <IconButton
              icon={RefreshCw}
              label={t('Actualiser l’état dans Hindsight', 'Refresh Hindsight status')}
              disabled={
                busy ||
                data.collecting ||
                data.refreshing ||
                !serverConnected ||
                !data.catalog ||
                demo
              }
              onClick={() => void run('section', { section: 'sources' })}
            />
            {folderRow && data.bank && !demo && (
              <IconButton
                icon={Trash2}
                label={t(
                  `Ne plus suivre ce dossier pour « ${bankName(data.bank)} »`,
                  `Stop tracking this folder for “${bankName(data.bank)}”`,
                )}
                disabled={busy || data.collecting}
                onClick={() => void run('coverage.removeRoot', { id: folderRow.path })}
              />
            )}
          </>
        }
      />
      <ErrorNotice message={mismatch ? null : data.error} />
      {noCatalog && (
        <section className="notice" role="status">
          <p>
            {t(
              'Ce dossier n’a plus de catalogue (catalog.json introuvable). Revenez aux sources : il y apparaît désormais comme un dossier ordinaire.',
              'This folder no longer has a catalog (catalog.json not found). Return to the sources: it now appears as an ordinary folder.',
            )}
          </p>
        </section>
      )}
      {mismatch && (
        <section className="bank-mismatch" role="alert">
          <p>
            <strong>
              {t(
                `Ce dossier appartient à la banque « ${bankName(data.boundBank)} », pas à « ${bankName(data.bank)} ».`,
                `This folder belongs to the “${bankName(data.boundBank)}” memory bank, not “${bankName(data.bank)}”.`,
              )}
            </strong>{' '}
            {t(
              'Son catalogue reste consultable ici, mais ses sources ne peuvent être ni envoyées ni retirées depuis cette banque.',
              'You can browse its catalog here, but its sources cannot be uploaded or removed from this memory bank.',
            )}
          </p>
          <div className="bank-mismatch-actions">
            {boundBankExists && (
              <Button
                kind="primary"
                disabled={busy}
                onClick={() => void run('bank.select', { id: data.boundBank })}
              >
                {t(
                  `Passer à « ${bankName(data.boundBank)} »`,
                  `Switch to “${bankName(data.boundBank)}”`,
                )}
              </Button>
            )}
            <Button icon={ArrowLeft} disabled={busy} onClick={() => void run('folder.close')}>
              {t('Toutes les sources', 'All sources')}
            </Button>
          </div>
        </section>
      )}
      {data.refreshing && (
        <p className="form-hint" role="status">
          {t(
            'Vérification des sources avec la banque…',
            'Checking sources against the memory bank…',
          )}
        </p>
      )}
      {data.collecting && (
        <p className="form-hint" role="status">
          {t(
            'Collecte en cours. Vous pouvez continuer à parcourir l’app.',
            'Collection in progress. You can keep browsing the app.',
          )}
        </p>
      )}
      {data.memoryMessage && (
        <p role="status" className="form-hint">
          {data.memoryMessage}
        </p>
      )}
      <section className="archive-panel">
        <div className="archive-identity">
          <span className="archive-icon">
            <Folder size={25} strokeWidth={1.35} />
          </span>
          <div>
            <div className="archive-heading">
              {/* Le nom du dossier est le titre de la page : ce bloc dit ce qu’il contient. */}
              <h2>{t('Catalogue', 'Catalog')}</h2>
              <Badge>
                {!hasCatalog
                  ? t('Sans catalogue', 'No catalog')
                  : data.boundBank
                    ? t(
                        `Banque « ${bankName(data.boundBank)} »`,
                        `“${bankName(data.boundBank)}” memory bank`,
                      )
                    : t('Rattaché au premier envoi', 'Linked on first upload')}
              </Badge>
            </div>
            <p>
              {data.folder ||
                t(
                  'Sélectionnez le dépôt commun ou son dossier collection.',
                  'Select the shared repository or its collection folder.',
                )}
            </p>
          </div>
          <Button
            kind="ghost"
            icon={FolderOpen}
            disabled={!data.folder}
            onClick={() => void run('folder.reveal')}
          >
            {t('Ouvrir le dossier', 'Open folder')}
          </Button>
        </div>
        {!noCatalog && (
          <div className="archive-stats">
            <div>
              <span>{t('Sources du catalogue', 'Catalog sources')}</span>
              <strong>{number(catalogCount)}</strong>
            </div>
            <div>
              <span>
                {data.bank
                  ? t(`Dans « ${bankName(data.bank)} »`, `In “${bankName(data.bank)}”`)
                  : t('Dans la banque', 'In the memory bank')}
              </span>
              <strong>{serverConnected || demo ? number(storedCount) : '—'}</strong>
            </div>
            <div>
              <span>{t('Projets', 'Projects')}</span>
              <strong>{number(projects.length)}</strong>
            </div>
            <div className="archive-updated">
              <span>{t('Dernière collecte du catalogue', 'Last catalog collection')}</span>
              <strong>
                {data.catalog?.generated_at
                  ? date(data.catalog.generated_at, true)
                  : t('Aucune collecte', 'No collection yet')}
              </strong>
            </div>
          </div>
        )}
      </section>

      {!noCatalog && (
        <div className="source-layout">
          <section className="card source-list">
            <CardHeader
              title={t('Sources et mémoire', 'Sources and memory')}
              subtitle={t(
                `${number(records.length)} sources${projects.length ? ` dans ${number(projects.length)} projet${projects.length > 1 ? 's' : ''}` : ''}`,
                `${number(records.length)} sources${projects.length ? ` in ${number(projects.length)} project${projects.length > 1 ? 's' : ''}` : ''}`,
              )}
              action={
                <span className="subtle-label">
                  <Clock3 size={13} />
                  {data.catalog?.generated_at
                    ? t(
                        `Collecté le ${date(data.catalog.generated_at)}`,
                        `Collected on ${date(data.catalog.generated_at)}`,
                      )
                    : t('Prêt à collecter', 'Ready to collect')}
                </span>
              }
            />
            <div className="list-toolbar source-filters">
              <div className="input-with-icon">
                <Search size={16} />
                <input
                  aria-label={t('Filtrer les sources', 'Filter sources')}
                  placeholder={t('Retrouver une source…', 'Find a source…')}
                  value={query}
                  onChange={(e) => {
                    setQuery(e.target.value);
                    setLimit(30);
                  }}
                />
              </div>
              <select
                aria-label={t('Filtrer par état mémoire', 'Filter by memory status')}
                value={memoryFilter}
                onChange={(e) => {
                  setMemoryFilter(e.target.value);
                  setLimit(30);
                }}
              >
                <option value="all">{t('Tous les états', 'All statuses')}</option>
                {Object.entries(memoryLabels).map(([id, label]) => (
                  <option key={id} value={id}>
                    {label} ({stateCounts.get(id) || 0})
                  </option>
                ))}
              </select>
              <select
                aria-label={t('Filtrer par projet', 'Filter by project')}
                value={project}
                onChange={(e) => {
                  setProject(e.target.value);
                  setRepository('all');
                  setLimit(30);
                  setAsideLimit(30);
                }}
              >
                <option value="all">{t('Tous les projets', 'All projects')}</option>
                {projects.map(([id, title]) => (
                  <option value={id} key={id}>
                    {title}
                  </option>
                ))}
              </select>
              <select
                aria-label={t('Filtrer par dépôt', 'Filter by repository')}
                value={repository}
                onChange={(e) => {
                  setRepository(e.target.value);
                  setLimit(30);
                  setAsideLimit(30);
                }}
              >
                <option value="all">{t('Tous les dépôts', 'All repositories')}</option>
                {repositories.map((id) => (
                  <option value={id} key={id}>
                    {id}
                  </option>
                ))}
              </select>
            </div>
            <div className="workspace-bulk">
              <span>
                {number(enabledCount)}
                {t(' activées sur ', ' enabled of ')}
                {number(filtered.length)}
                {t(' dans ce filtre · ', ' in this filter · ')}
                {number(toggleable.length)}
                {t(' modifiables', ' editable')}
              </span>
              <Button
                disabled={busy || data.collecting || demo || !toInclude.length}
                onClick={() =>
                  void run('folder.enabled', { ids: toInclude.map((r) => r.id), enabled: true })
                }
              >
                {t('Inclure ce filtre', 'Include matching sources')}
              </Button>
              <Button
                disabled={busy || data.collecting || demo || !toExclude.length}
                onClick={() =>
                  void run('folder.enabled', { ids: toExclude.map((r) => r.id), enabled: false })
                }
              >
                {t('Exclure ce filtre', 'Exclude matching sources')}
              </Button>
            </div>
            <div className="filter-chips">
              {[
                { id: 'all', title: t('Toutes', 'All') },
                { id: 'conversation', title: t('Conversations', 'Conversations') },
                { id: 'git', title: t('Commits', 'Commits') },
                { id: 'note', title: t('Notes', 'Notes') },
                { id: 'report', title: t('Rapports', 'Reports') },
                { id: 'document', title: t('Documents', 'Documents') },
              ].map((k) => (
                <button
                  key={k.id}
                  onClick={() => {
                    setKind(k.id);
                    setLimit(30);
                  }}
                  className={kind === k.id ? 'active' : ''}
                >
                  {k.title}
                  {k.id === 'all' && <span>{number(records.length)}</span>}
                </button>
              ))}
            </div>
            {filtered.length ? (
              <SourceRows records={filtered.slice(0, limit)} onOpen={open} />
            ) : (
              <Empty
                icon={records.length ? Search : Folder}
                title={
                  allRecords.length
                    ? t('Aucune source de projet ne correspond', 'No matching project sources')
                    : t('Aucune source collectée', 'No sources collected')
                }
                description={
                  allRecords.length
                    ? t(
                        'Essayez un autre filtre. Les validations internes et exports vides restent accessibles dans Archives à part.',
                        'Try another filter. Internal reviews and empty exports remain available in Separate archives.',
                      )
                    : t(
                        'Collectez les sources définies dans la configuration du dossier.',
                        'Collect the sources defined in the folder configuration.',
                      )
                }
              />
            )}
            {filtered.length > limit && (
              <div className="card-footer">
                <Button kind="ghost" icon={ChevronDown} onClick={() => setLimit(limit + 50)}>
                  {t('Afficher plus de sources', 'Show more sources')}
                </Button>
                <span>
                  {number(limit)}
                  {t(' sur ', ' of ')}
                  {number(filtered.length)}
                </span>
              </div>
            )}
          </section>
          <aside className="source-aside">
            <section className="card collector-card">
              <CardHeader
                title={t('État des collectes', 'Collection status')}
                action={
                  <Badge>
                    {t(
                      `${number(activeSources.length)} actifs`,
                      `${number(activeSources.length)} active`,
                    )}
                  </Badge>
                }
              />
              <div className="collector-status-list">
                {activeSources.slice(0, 5).map((source) => (
                  <div key={source.id}>
                    <span
                      className={`status-dot ${/error|fail|partial/.test(source.status) ? 'warning' : /ok|success/.test(source.status) ? 'green' : ''}`}
                    />
                    <div>
                      <strong>
                        {source.repository
                          ? shortName(source.repository)
                          : kindLabels[sourceKind(source.kind)]}
                      </strong>
                      <span>
                        {kindLabels[sourceKind(source.kind)]} · {number(source.count)}{' '}
                        {source.count === 1 ? 'source' : 'sources'}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
              {!sources.length && (
                <p className="collector-empty">
                  {t(
                    'Les collecteurs apparaîtront après le choix d’un catalogue.',
                    'Collectors will appear once you choose a catalog.',
                  )}
                </p>
              )}
              {!!sources.length && !activeSources.length && (
                <p className="collector-empty">
                  {t('Aucun collecteur actif.', 'No active collector.')}
                </p>
              )}
              {!!sources.length && (
                <button className="collector-more" onClick={() => setCollectorsOpen(true)}>
                  {t(
                    `Voir les ${number(sources.length)} collecteurs`,
                    `View all ${number(sources.length)} collectors`,
                  )}
                  {sources.length > activeSources.length &&
                    t(
                      ` (${number(sources.length - activeSources.length)} désactivés)`,
                      ` (${number(sources.length - activeSources.length)} disabled)`,
                    )}
                  <ArrowRight size={14} />
                </button>
              )}
            </section>
            <section className="card processing-note">
              <div>
                <LayersIcon />
                <h3>{t('Sources et mémoire', 'Sources and memory')}</h3>
              </div>
              <p>
                {t(
                  'Collecter les sources lance le collecteur du dossier et met à jour le catalogue de ce Mac, sans rien envoyer à Hindsight. Actualiser (↻) relit l’état de la banque, sans collecter ni envoyer. Préparer l’envoi compare les sources collectées à la mémoire : vous validez chaque ajout ou mise à jour, puis Hindsight en extrait les faits. Retirer conserve le fichier et l’exclut des envois futurs.',
                  'Collect sources runs the folder’s collector and updates this Mac’s catalog without uploading anything to Hindsight. Refresh (↻) rereads the memory bank’s status without collecting or uploading. Prepare upload compares collected sources with memory: you approve every addition or update, then Hindsight extracts their facts. Remove keeps the file and excludes it from future uploads.',
                )}
              </p>
            </section>
            {problems.map((p) => (
              <div className="notice error" key={p.id}>
                {p.message ||
                  t(`${p.kind} : collecte incomplète`, `${p.kind}: incomplete collection`)}
              </div>
            ))}
          </aside>
        </div>
      )}
      {!!archives.length && (
        <details
          className="card log-details source-list"
          open={asideOpen}
          onToggle={(e) => setAsideOpen(e.currentTarget.open)}
        >
          <summary>
            {t('Archives à part (', 'Separate archives (')}
            {number(archives.length)})
          </summary>
          {asideOpen && (
            <>
              <p className="form-hint">
                {t(
                  'Validations internes de Codex et exports vides ou interrompus, conservés pour diagnostic. Ils ne figurent pas dans les sources du projet à traiter. Les filtres ci-dessus s’appliquent aussi à cette liste.',
                  'Internal Codex reviews and empty or interrupted exports, kept for troubleshooting. They are excluded from project sources to process. The filters above also apply to this list.',
                )}
              </p>
              {filteredArchives.length ? (
                <SourceRows
                  records={filteredArchives.slice(0, asideLimit)}
                  onOpen={open}
                  archived
                />
              ) : (
                <p className="form-hint">
                  {t(
                    'Aucune archive ne correspond aux filtres.',
                    'No archives match these filters.',
                  )}
                </p>
              )}
              {filteredArchives.length > asideLimit && (
                <div className="card-footer">
                  <Button
                    kind="ghost"
                    icon={ChevronDown}
                    onClick={() => setAsideLimit(asideLimit + 50)}
                  >
                    {t('Afficher plus d’archives', 'Show more archives')}
                  </Button>
                  <span>
                    {number(asideLimit)}
                    {t(' sur ', ' of ')}
                    {number(filteredArchives.length)}
                  </span>
                </div>
              )}
            </>
          )}
        </details>
      )}
      {!!data.output && (
        <details className="card log-details">
          <summary>{t('Dernière collecte', 'Last collection')}</summary>
          <pre>{data.output}</pre>
        </details>
      )}

      {collectorsOpen && (
        <Modal
          title={t('État des collectes', 'Collection status')}
          subtitle={t(
            'Statuts enregistrés dans le catalogue local',
            'Statuses saved in the local catalog',
          )}
          onClose={() => setCollectorsOpen(false)}
          wide
        >
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>{t('Dépôt / source', 'Repository / source')}</th>
                  <th>{t('Projet', 'Project')}</th>
                  <th>{t('Sources', 'Sources')}</th>
                  <th>{t('État', 'Status')}</th>
                  <th>{t('Dernier succès', 'Last success')}</th>
                </tr>
              </thead>
              <tbody>
                {sources.map((source) => (
                  <tr key={source.id}>
                    <td>
                      {source.repository
                        ? shortName(source.repository)
                        : kindLabels[sourceKind(source.kind)]}
                    </td>
                    <td>{source.project}</td>
                    <td>{number(source.count)}</td>
                    <td>
                      <Badge>{collectorStatus(source.status)}</Badge>
                    </td>
                    <td>{date(source.last_success_at, true)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Modal>
      )}
      {!!importFiles.length && (
        <Modal
          title={t('Ajouter des documents', 'Add documents')}
          subtitle={t(
            'Une copie locale, avant tout traitement mémoire.',
            'A local copy, before any memory processing.',
          )}
          onClose={() => {
            if (!busy) setImportFiles([]);
          }}
        >
          <div className="document-import">
            <label htmlFor="document-project">{t('Projet', 'Project')}</label>
            <select
              id="document-project"
              value={importProject}
              onChange={(e) => setImportProject(e.target.value)}
              disabled={busy}
            >
              {projects.map(([id, title]) => (
                <option value={id} key={id}>
                  {title}
                </option>
              ))}
            </select>
            <p className="muted">
              {t('Destination : documents/', 'Destination: documents/')}
              {importProject}
              {t('/ dans le dossier commun.', '/ in the shared folder.')}
            </p>
            <ul>
              {importFiles.map((path) => (
                <li key={path} title={path}>
                  <FileText size={15} />
                  <span>{shortName(path)}</span>
                </li>
              ))}
            </ul>
            <p className="muted">
              {t(
                'Les originaux restent à leur emplacement. Les copies rejoignent le catalogue, sans envoi ni traitement Hindsight.',
                'Original files stay where they are. Copies are added to the catalog without uploading or Hindsight processing.',
              )}
            </p>
            <ErrorNotice message={importError} />
          </div>
          <div className="modal-actions">
            <Button disabled={busy} onClick={() => setImportFiles([])}>
              {t('Annuler', 'Cancel')}
            </Button>
            <Button
              kind="primary"
              disabled={busy || !importProject}
              onClick={() => void addDocuments()}
            >
              {t('Ajouter ', 'Add ')}
              {number(importFiles.length)}
              {t(' document', ' document')}
              {importFiles.length > 1 ? 's' : ''}
            </Button>
          </div>
        </Modal>
      )}
      {selected && (
        <Modal
          title={selected.title || t('Source', 'Source')}
          subtitle={`${projectLabel(selected)} · ${kindLabels[sourceKind(selected.kind)]}`}
          wide
          onClose={closeSource}
        >
          <div className="reader-meta">
            <Badge>{kindLabels[sourceKind(selected.kind)]}</Badge>
            <span>
              {t('Collecté le ', 'Collected on ')}
              {date(selected.collected_at, true)}
            </span>
            {sourceOriginalPath(selected) && (
              <Button
                icon={FolderOpen}
                disabled={busy}
                onClick={() => void run('folder.open', { path: sourceOriginalPath(selected) })}
              >
                {selected.context?.format === 'pdf'
                  ? t('Ouvrir le PDF', 'Open PDF')
                  : t('Ouvrir l’original', 'Open original')}
              </Button>
            )}
            {demo && <Badge tone="amber">{t('Données fictives', 'Fictional data')}</Badge>}
          </div>
          {selected.memory && (
            <section className="workspace-actions">
              {String(selected.id).startsWith('bank:') && !selected.memory.locked && (
                <div className="form-stack">
                  <label>
                    {t('Relier à une source du catalogue', 'Link to a catalog source')}
                    <select value={linkSource} onChange={(e) => setLinkSource(e.target.value)}>
                      <option value="">{t('Choisir une source…', 'Choose a source…')}</option>
                      {allRecords
                        .filter(
                          (r) =>
                            !String(r.id).startsWith('bank:') &&
                            !r.memory?.stored &&
                            !r.memory?.locked,
                        )
                        .map((r) => (
                          <option key={r.id} value={r.id}>
                            {r.title}
                          </option>
                        ))}
                    </select>
                  </label>
                  <Button
                    disabled={busy || !linkSource || demo}
                    onClick={async () => {
                      await run('folder.link', {
                        id: linkSource,
                        document: selected.memory.document_id,
                      });
                      setLinkSource('');
                      setSelected(null);
                    }}
                  >
                    {t('Relier et comparer les versions', 'Link and compare versions')}
                  </Button>
                </div>
              )}
              <Badge>
                {memoryLabels[selected.memory.state] || t('État non vérifié', 'Unchecked status')}
              </Badge>
              <p className="form-hint">{nativeSourceReason(selected.memory.reason)}</p>
              {!String(selected.id).startsWith('bank:') && (
                <label>
                  <input
                    type="checkbox"
                    checked={!!selected.memory.enabled}
                    disabled={busy || data.collecting || selected.memory.locked || demo}
                    onChange={async (e) => {
                      await run('folder.enabled', { id: selected.id, enabled: e.target.checked });
                    }}
                  />{' '}
                  {t('Inclure dans les mises à jour', 'Include in updates')}
                </label>
              )}
              {selected.memory.state === 'queued' && (
                <Button
                  disabled={busy || demo}
                  onClick={async () => {
                    await run('folder.retry', { id: selected.id });
                    setSelected(null);
                  }}
                >
                  {t('Vérifier / reprendre l’envoi', 'Check / resume upload')}
                </Button>
              )}
              {selected.memory.stored && (
                <Button disabled={busy || demo} onClick={() => void open(selected, true)}>
                  {t('Version mémorisée', 'Stored version')}
                </Button>
              )}
              {sourceTextPath(selected) && (
                <Button disabled={busy} onClick={() => void open(selected)}>
                  {t('Source actuelle', 'Current source')}
                </Button>
              )}
              <Button
                disabled={busy || !selected.memory.can_remove || demo}
                onClick={async () => {
                  await run('folder.remove', { id: selected.id });
                  setSelected(null);
                }}
              >
                {t('Retirer de la mémoire', 'Remove from memory')}
              </Button>
            </section>
          )}
          <ErrorNotice message={readError} />
          {reading ? (
            <div className="loading-state">{t('Lecture de la source…', 'Loading source…')}</div>
          ) : text ? (
            /\.tex$/i.test(sourceTextPath(selected) || '') ? (
              <pre className="source-code">{text}</pre>
            ) : (
              <Markdown text={text} />
            )
          ) : (
            sourceOriginalPath(selected) && (
              <p className="muted">
                {selected.context?.format === 'pdf'
                  ? t(
                      'Original conservé dans le dossier commun. Aucun texte n’a été extrait de ce PDF.',
                      'Original kept in the shared folder. No text has been extracted from this PDF.',
                    )
                  : t(
                      'Original conservé dans le dossier commun. Ouvrez le fichier pour le consulter.',
                      'Original kept in the shared folder. Open the file to read it.',
                    )}
              </p>
            )
          )}
          <details className="provenance">
            <summary>{t('Provenance et métadonnées', 'Provenance and metadata')}</summary>
            <dl>
              <dt>{t('Identifiant', 'ID')}</dt>
              <dd>{selected.id}</dd>
              {selected.source_id && (
                <>
                  <dt>{t('Identifiant d’origine', 'Original ID')}</dt>
                  <dd>{selected.source_id}</dd>
                </>
              )}
              {isAsideRecord(selected) && (
                <>
                  <dt>{t('Classement', 'Category')}</dt>
                  <dd>{asideLabel(selected)}</dd>
                </>
              )}
              <dt>{t('Dépôt', 'Repository')}</dt>
              <dd>{selected.repository || '—'}</dd>
              <dt>{t('Fichier', 'File')}</dt>
              <dd>{sourceOriginalPath(selected) || sourceTextPath(selected) || '—'}</dd>
              {selected.context?.original_path && (
                <>
                  <dt>{t('Emplacement d’origine', 'Original location')}</dt>
                  <dd>{selected.context.original_path}</dd>
                  <dt>{t('Copie dans le dossier commun', 'Copy in shared folder')}</dt>
                  <dd>{selected.context.managed_path}</dd>
                </>
              )}
              <dt>{t('Date de la source', 'Source date')}</dt>
              <dd>{date(selected.source_updated_at, true)}</dd>
              <dt>{t('Collecté le', 'Collected on')}</dt>
              <dd>{date(selected.collected_at, true)}</dd>
            </dl>
          </details>
        </Modal>
      )}
    </>
  );
}

function LayersIcon() {
  return <BookOpen size={17} strokeWidth={1.6} />;
}

function SourceRows({
  records,
  onOpen,
  archived = false,
}: {
  records: Row[];
  onOpen: (record: Row) => Promise<void>;
  archived?: boolean;
}) {
  return (
    <div className="source-rows">
      {records.map((record) => {
        const type = sourceKind(record.kind);
        const Icon = kindIcons[type];
        return (
          <button className="source-row" onClick={() => void onOpen(record)} key={record.id}>
            <span className={`file-icon ${type}`}>
              <Icon size={19} strokeWidth={1.6} />
            </span>
            <span className="source-row-main">
              <strong>{record.title || record.id}</strong>
              <span>
                {projectLabel(record)}
                <span className="middot">·</span>
                {archived
                  ? asideLabel(record)
                  : record.kind === 'documents' && record.context?.format
                    ? `Document ${String(record.context.format).toUpperCase()}`
                    : kindLabels[type]}
                {record.repository && (
                  <>
                    <span className="middot">·</span>
                    {record.repository}
                  </>
                )}
              </span>
            </span>
            {record.memory && (
              <Badge>
                {memoryLabels[record.memory.state] || t('État non vérifié', 'Unchecked status')}
                {record.memory.state === 'excluded' && record.memory.stored
                  ? t(' · En mémoire', ' · In memory')
                  : ''}
              </Badge>
            )}
            <span className="source-date">
              {record.source_updated_at
                ? date(record.source_updated_at)
                : t(
                    `Collecté le ${date(record.collected_at)}`,
                    `Collected on ${date(record.collected_at)}`,
                  )}
            </span>
            <ArrowRight size={15} />
          </button>
        );
      })}
    </div>
  );
}

/** Ce que contient un dossier et ce qu’il reste à envoyer, en une ligne. */
function folderSummary(folder: Row, comparing: boolean, offline: boolean): string {
  if (folder.exists === false)
    return t('Dossier introuvable sur ce Mac', 'Folder not found on this Mac');
  if (folder.kind === 'catalog') {
    if (folder.unreadable) return t('Catalogue illisible', 'Unreadable catalog');
    const count = Number(folder.sources || 0);
    const collected = folder.collectedAt
      ? t(
          ` · collecté le ${date(folder.collectedAt)}`,
          ` · collected on ${date(folder.collectedAt)}`,
        )
      : '';
    return (
      t(
        `${number(count)} source${count > 1 ? 's' : ''} collectée${count > 1 ? 's' : ''}`,
        `${number(count)} collected source${count === 1 ? '' : 's'}`,
      ) + collected
    );
  }
  if (folder.files === undefined || folder.files === null)
    return offline
      ? t('Comparaison à la connexion du serveur', 'Compared once the server is connected')
      : comparing
        ? t('Comparaison avec la banque…', 'Comparing with the memory bank…')
        : t('Pas encore comparé', 'Not compared yet');
  const files = Number(folder.files);
  if (!files) return t('Aucun document', 'No documents');
  const toSend = Number(folder.toSend || 0);
  const parts = [
    t(
      `${number(files)} fichier${files > 1 ? 's' : ''}`,
      `${number(files)} file${files === 1 ? '' : 's'}`,
    ),
    toSend
      ? t(`${number(toSend)} à envoyer`, `${number(toSend)} to upload`)
      : t('à jour', 'up to date'),
  ];
  if (folder.queued)
    parts.push(t(`${number(folder.queued)} en file`, `${number(folder.queued)} queued`));
  return parts.join(' · ');
}

/** Liste des dossiers qui alimentent la banque choisie. */
function FolderList({
  data,
  run,
  busy,
  demo,
  navigate,
  serverConnected,
  banks = [],
  onExploreExample,
}: SourcesProps) {
  const bankName = bankNamer(banks);
  const [actionError, setActionError] = useState('');
  const folders: Row[] = Array.isArray(data.folders) ? data.folders : [];
  const listBank = data.listBank;
  const offline = !demo && !data.bank && Boolean(listBank);
  const comparing = Boolean(data.foldersLoading);
  const hasCatalog = folders.some((folder) => folder.kind === 'catalog');
  // Un double-clic n’ouvre le dossier qu’une fois.
  const opening = useRef(false);
  function openFolder(path: string) {
    if (opening.current) return;
    opening.current = true;
    void run('folder.choose', { path }).finally(() => (opening.current = false));
  }
  async function add() {
    setActionError('');
    try {
      const path = await pickDirectory(
        t(
          `Ajouter un dossier à « ${bankName(listBank)} »`,
          `Add a folder to “${bankName(listBank)}”`,
        ),
      );
      if (!path) return;
      const result = await run('coverage.add', { paths: [path] });
      if (result?.error) setActionError(String(result.error));
    } catch (error) {
      setActionError(error instanceof Error ? error.message : String(error));
    }
  }

  // Pendant un changement de banque ou de dossier, la vue attend la réponse au lieu d’afficher un état vide.
  if (data.folders === undefined)
    return (
      <div className="loading-state" role="status">
        {t('Chargement des sources…', 'Loading sources…')}
      </div>
    );

  if (!listBank)
    return (
      <>
        <PageHeader
          title={t('Sources', 'Sources')}
          description={t(
            'Les dossiers de ce Mac qui alimentent une banque Hindsight.',
            'The folders on this Mac that feed a Hindsight memory bank.',
          )}
        />
        <section className="card">
          <Empty
            icon={BookOpen}
            title={
              serverConnected
                ? t('Choisissez ou créez une banque', 'Choose or create a memory bank')
                : t(
                    'Commencez avec votre serveur ou un exemple',
                    'Start with your server or an example',
                  )
            }
            description={t(
              'Chaque banque a ses propres sources : les dossiers de ce Mac dont les fichiers l’alimentent. L’exemple permet de découvrir l’application avec des données fictives.',
              'Each memory bank has its own sources: the folders on this Mac whose files feed it. Explore the example to try the app with fictional data.',
            )}
            action={
              <div className="action-row">
                <Button
                  kind="primary"
                  onClick={() => navigate(serverConnected ? 'admin' : 'settings')}
                >
                  {serverConnected
                    ? t('Gérer mes banques', 'Manage my banks')
                    : t('Connecter mon serveur', 'Connect my server')}
                </Button>
                <Button icon={Sparkles} onClick={onExploreExample}>
                  {t('Explorer l’exemple', 'Explore the example')}
                </Button>
              </div>
            }
          />
        </section>
      </>
    );

  return (
    <>
      <PageHeader
        title={t('Sources', 'Sources')}
        description={t(
          `Les dossiers de ce Mac qui alimentent « ${bankName(listBank)} ».`,
          `The folders on this Mac that feed “${bankName(listBank)}”.`,
        )}
        actions={
          <Button
            icon={FolderPlus}
            kind="primary"
            disabled={busy || (!data.bank && !demo)}
            onClick={() => void add()}
          >
            {t('Ajouter un dossier', 'Add a folder')}
          </Button>
        }
      />
      {offline && (
        <div className="notice" role="status">
          {t(
            `Serveur déconnecté : voici les dossiers de « ${bankName(listBank)} », la dernière banque choisie. La comparaison avec la banque reprendra à la connexion.`,
            `Server disconnected: these are the folders of “${bankName(listBank)}”, the last memory bank you selected. Comparison with the bank resumes once connected.`,
          )}
        </div>
      )}
      <ErrorNotice message={data.foldersError} />
      <ErrorNotice message={actionError} />
      <section className="card source-folders">
        {folders.length ? (
          <div className="folder-rows">
            {folders.map((folder) => {
              const content = (
                <>
                  <span className={`file-icon folder-icon ${folder.kind}`}>
                    {folder.kind === 'catalog' ? (
                      <Library size={18} strokeWidth={1.6} />
                    ) : (
                      <Folder size={18} strokeWidth={1.6} />
                    )}
                  </span>
                  <span className="folder-row-main">
                    <span className="folder-row-title">
                      <strong>{folder.name || shortName(folder.path)}</strong>
                      {folder.kind === 'catalog' && (
                        <Badge tone="accent">{t('Catalogue', 'Catalog')}</Badge>
                      )}
                    </span>
                    <span className="folder-row-path">{folder.path}</span>
                  </span>
                  <span className="folder-row-summary">
                    {folderSummary(folder, comparing, offline)}
                  </span>
                </>
              );
              // Un dossier introuvable ne s’ouvre pas ; il peut seulement ne plus être suivi.
              return folder.exists === false ? (
                <div className="folder-row missing" key={folder.path}>
                  {content}
                  {data.bank && (
                    <IconButton
                      icon={Trash2}
                      label={t(
                        `Ne plus suivre ce dossier pour « ${bankName(data.bank)} »`,
                        `Stop tracking this folder for “${bankName(data.bank)}”`,
                      )}
                      disabled={busy}
                      onClick={() => void run('coverage.removeRoot', { id: folder.path })}
                    />
                  )}
                </div>
              ) : (
                <button
                  className="folder-row"
                  key={folder.path}
                  disabled={busy}
                  onClick={() => openFolder(folder.path)}
                >
                  {content}
                  <ArrowRight size={15} />
                </button>
              );
            })}
          </div>
        ) : (
          <Empty
            icon={FolderPlus}
            title={t(
              `Aucun dossier n’alimente « ${bankName(listBank)} »`,
              `No folder feeds “${bankName(listBank)}” yet`,
            )}
            description={t(
              'Ajoutez un dossier de ce Mac : ses fichiers seront comparés aux documents de la banque, puis vous choisirez ce qu’il faut envoyer.',
              'Add a folder from this Mac: its files are compared with the bank’s documents, then you choose what to upload.',
            )}
            action={
              data.bank || demo ? (
                <Button icon={FolderPlus} disabled={busy} onClick={() => void add()}>
                  {t('Ajouter un dossier', 'Add a folder')}
                </Button>
              ) : undefined
            }
          />
        )}
      </section>
      <p className="form-hint sources-hint">
        {t(
          'Un même dossier peut alimenter plusieurs banques ; chacune garde son propre état. Rien n’est envoyé sans votre confirmation.',
          'A folder can feed several memory banks; each keeps its own status. Nothing is uploaded without your confirmation.',
        )}
        {hasCatalog &&
          ' ' +
            t(
              'Un dossier à catalogue passe par son catalogue : conversations, commits et rapports rassemblés par son collecteur (collect.py).',
              'A folder with a catalog goes through its catalog: conversations, commits and reports gathered by its collector (collect.py).',
            )}
      </p>
      {(data.warnings || []).map((warning: string) => (
        <div key={warning} className="notice">
          {warning}
        </div>
      ))}
    </>
  );
}

const fileStates: Record<string, { fr: string; en: string; tone: string }> = {
  current: { fr: 'À jour', en: 'Up to date', tone: 'sage' },
  notSent: { fr: 'Non envoyé', en: 'Not sent', tone: 'amber' },
  modified: { fr: 'Modifié', en: 'Modified', tone: 'amber' },
  noFacts: { fr: 'Sans fait', en: 'No facts', tone: 'amber' },
  fileMissing: { fr: 'Fichier disparu', en: 'File missing', tone: 'neutral' },
  queued: { fr: 'En file', en: 'Queued', tone: 'blue' },
  stored: { fr: 'En mémoire', en: 'In memory', tone: 'neutral' },
};

/** Dossier ordinaire : ses fichiers comparés aux documents de la banque, envoi et retrait après confirmation. */
function PlainFolder({ data, run, busy, demo, banks = [] }: SourcesProps) {
  const bankName = bankNamer(banks);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [working, setWorking] = useState(false);
  const [actionError, setActionError] = useState('');
  const pending = useRef(false);
  const folder: Row = (data.folders || []).find((row: Row) => samePath(row.path, data.open)) || {
    path: data.open,
    name: shortName(String(data.open || '')),
  };
  const items: Row[] = Array.isArray(data.items) ? data.items : [];
  const offline = !demo && !data.bank;
  const comparing = !offline && (Boolean(data.foldersLoading) || data.compared === false);
  const disabled = busy || working || comparing || offline;
  const itemID = (item: Row, index: number) => String(item.id || item.key || index);
  const itemIDs = items.map(itemID);
  const currentSelection = new Set(itemIDs.filter((id) => selected.has(id)));
  const selectedItems = items.filter((item, index) => currentSelection.has(itemID(item, index)));
  const sendable = selectedItems.filter((item) => item.canSend);
  const removable = selectedItems.filter((item) => (item.documents || []).length > 0);
  const toSend = items.filter((item) => item.canSend).length;
  async function perform(action: () => Promise<any>) {
    if (busy || pending.current) return;
    pending.current = true;
    setWorking(true);
    setActionError('');
    try {
      const result = await action();
      if (result?.error) setActionError(String(result.error));
    } catch (error) {
      setActionError(error instanceof Error ? error.message : String(error));
    } finally {
      pending.current = false;
      setWorking(false);
    }
  }
  return (
    <>
      <BackToSources run={run} busy={busy} />
      <PageHeader
        title={folder.name || shortName(String(folder.path || ''))}
        description={
          data.bank
            ? t(
                `Dossier suivi pour « ${bankName(data.bank)} » : ses fichiers sont comparés aux documents de la banque. Choisissez ce qu’il faut envoyer ; chaque envoi reste à confirmer.`,
                `Folder tracked for “${bankName(data.bank)}”: its files are compared with the bank’s documents. Choose what to upload; every upload still needs confirmation.`,
              )
            : t(
                'Dossier suivi : ses fichiers seront comparés aux documents de la banque à la connexion du serveur.',
                'Tracked folder: its files are compared with the bank’s documents once the server is connected.',
              )
        }
        actions={
          <>
            <Button
              kind="ghost"
              icon={FolderOpen}
              disabled={busy || working}
              onClick={() => void perform(() => run('folder.reveal', { path: folder.path }))}
            >
              {t('Afficher dans le Finder', 'Show in Finder')}
            </Button>
            {data.bank && (
              <IconButton
                icon={Trash2}
                label={t(
                  `Ne plus suivre ce dossier pour « ${bankName(data.bank)} »`,
                  `Stop tracking this folder for “${bankName(data.bank)}”`,
                )}
                disabled={busy || working}
                onClick={() => void perform(() => run('coverage.removeRoot', { id: folder.path }))}
              />
            )}
          </>
        }
      />
      <p className="folder-path-line">{folder.path}</p>
      <ErrorNotice message={data.foldersError} />
      <ErrorNotice message={actionError} />
      <div className="folder-options">
        <label className="checkbox-label">
          <input
            type="checkbox"
            checked={Boolean(folder.allFiles)}
            disabled={disabled || demo}
            onChange={(e) =>
              void perform(() =>
                run('coverage.allFiles', { id: folder.path, enabled: e.target.checked }),
              )
            }
          />{' '}
          {t(
            'Inclure tous les fichiers texte (code, données…), pas seulement les documents',
            'Include all text files (code, data…), not only documents',
          )}
        </label>
        {folder.autoSync && (
          <Button
            kind="ghost"
            disabled={disabled}
            title={t(
              'La synchronisation automatique est suspendue : chaque envoi demande une validation.',
              'Automatic sync is suspended: every upload needs approval.',
            )}
            onClick={() =>
              void perform(() => run('coverage.auto', { id: folder.path, enabled: false }))
            }
          >
            {t('Désactiver l’ancienne synchro auto.', 'Turn off legacy auto-sync')}
          </Button>
        )}
      </div>
      <section className="card">
        <CardHeader
          title={t('Fichiers', 'Files')}
          subtitle={
            items.length
              ? t(
                  `${number(items.length)} fichier${items.length > 1 ? 's' : ''} · ${number(toSend)} à envoyer`,
                  `${number(items.length)} file${items.length === 1 ? '' : 's'} · ${number(toSend)} to upload`,
                )
              : undefined
          }
          action={
            <div className="action-row">
              <Button
                icon={Send}
                kind="primary"
                disabled={disabled || !sendable.length}
                onClick={() =>
                  void perform(() => run('coverage.send', { ids: [...currentSelection] }))
                }
              >
                {t(`Envoyer (${sendable.length})`, `Upload (${sendable.length})`)}
              </Button>
              <Button
                icon={Trash2}
                kind="danger"
                disabled={disabled || !removable.length}
                onClick={() =>
                  void perform(() => run('coverage.remove', { ids: [...currentSelection] }))
                }
              >
                {t(
                  `Retirer de la mémoire (${removable.length})`,
                  `Remove from memory (${removable.length})`,
                )}
              </Button>
            </div>
          }
        />
        {offline ? (
          <p className="notice" role="status">
            {t(
              'Connectez le serveur pour comparer ce dossier à la banque.',
              'Connect the server to compare this folder with the memory bank.',
            )}
          </p>
        ) : comparing && !items.length ? (
          <p className="notice" role="status">
            {t('Comparaison avec la banque…', 'Comparing with the memory bank…')}
          </p>
        ) : !items.length ? (
          <Empty
            icon={FileText}
            title={t('Aucun document dans ce dossier', 'No documents in this folder')}
            description={
              folder.allFiles
                ? t(
                    'Ce dossier ne contient aucun fichier texte à comparer.',
                    'This folder contains no text files to compare.',
                  )
                : t(
                    'Seuls les documents (Markdown, TeX, texte, HTML, PDF, Word, PowerPoint, Excel) sont comparés. Cochez l’option ci-dessus pour inclure les autres fichiers texte.',
                    'Only documents (Markdown, TeX, text, HTML, PDF, Word, PowerPoint, Excel) are compared. Tick the option above to include other text files.',
                  )
            }
          />
        ) : (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>
                    <input
                      type="checkbox"
                      aria-label={t('Tout sélectionner', 'Select all')}
                      checked={!!items.length && currentSelection.size === items.length}
                      disabled={disabled}
                      onChange={(e) => setSelected(e.target.checked ? new Set(itemIDs) : new Set())}
                    />
                  </th>
                  <th>{t('Fichier', 'File')}</th>
                  <th>{t('État', 'Status')}</th>
                  <th>{t('Faits', 'Facts')}</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item, index) => {
                  const id = itemID(item, index);
                  const state = fileStates[item.state] || fileStates.stored;
                  return (
                    <tr key={id}>
                      <td>
                        <input
                          type="checkbox"
                          aria-label={`${t('Sélectionner', 'Select')} ${item.title || id}`}
                          checked={selected.has(id)}
                          disabled={disabled}
                          onChange={() =>
                            setSelected((old) => {
                              const next = new Set(old);
                              if (next.has(id)) next.delete(id);
                              else next.add(id);
                              return next;
                            })
                          }
                        />
                      </td>
                      <td className="file-cell">
                        <strong>{item.title || item.entry?.file?.path || id}</strong>
                        {item.location && <small>{item.location}</small>}
                      </td>
                      <td>
                        <Badge tone={state.tone}>{t(state.fr, state.en)}</Badge>
                      </td>
                      <td>{number(item.facts ?? 0)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {(data.warnings || []).map((warning: string) => (
        <div key={warning} className="notice">
          {warning}
        </div>
      ))}
    </>
  );
}
