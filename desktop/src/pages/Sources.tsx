import { useI18n } from '../i18n';
import { translate as t, getLocale } from '../i18n-core';
import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowDownToLine,
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
  MessageSquare,
  Search,
  Sparkles,
  WandSparkles,
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

export default function Sources({
  data,
  run,
  busy,
  notify,
  demo,
  navigate,
  serverConnected,
  banks = [],
  onExploreExample,
  contextKey,
}: PageProps & {
  serverConnected: boolean;
  banks?: Row[];
  onExploreExample: () => void;
  contextKey?: string;
}) {
  useI18n();

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
  // Le dossier appartient à la banque déclarée dans sa politique ; une autre banque ne fait que le consulter.
  const bankName = (id: unknown) =>
    bankLabel(banks.find((x) => x.bank_id === id)) || String(id || '');
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

  async function choose() {
    try {
      const path = await pickDirectory();
      if (path) await run('folder.choose', { path });
    } catch (error) {
      notify(String((error as Error).message));
    }
  }
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

  if (!demo && !data.folder && !hasCatalog)
    return (
      <>
        <PageHeader
          title={t('Catalogue', 'Catalog')}
          description={t(
            'Parcourez le catalogue de ce Mac et choisissez ce que vous souhaitez envoyer à la banque Hindsight sélectionnée.',
            'Browse this Mac’s source catalog and choose what to send to the selected Hindsight bank.',
          )}
        />
        <ErrorNotice message={data.error} />
        <section className="card">
          <Empty
            icon={BookOpen}
            title={t(
              'Commencez avec votre serveur ou un exemple',
              'Start with your server or an example',
            )}
            description={t(
              'Hindsight Desktop est une interface pour un serveur Hindsight séparé. L’exemple permet de découvrir l’application avec des données fictives.',
              'Hindsight Desktop connects to a separate Hindsight server. Explore the example to try the app with fictional data.',
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
        <section className="card settings-card">
          <CardHeader
            title={t('Vous avez déjà un dossier mémoire ?', 'Already have a memory folder?')}
            subtitle={t(
              'Ouvrez un catalogue existant pour parcourir ses sources, même sans connexion au serveur.',
              'Open an existing catalog to browse its sources, even without a server connection.',
            )}
          />
          <Button icon={FolderOpen} disabled={busy} onClick={choose}>
            {t('Choisir le dossier mémoire', 'Choose a memory folder')}
          </Button>
          <p className="form-hint">
            {t(
              'Le choix du dossier permet sa lecture. L’envoi de contenu au serveur demande votre confirmation.',
              'Choosing a folder allows the app to read it. Sending content to the server requires your confirmation.',
            )}
          </p>
        </section>
      </>
    );

  return (
    <>
      <PageHeader
        title={t('Catalogue', 'Catalog')}
        description={t(
          'Le catalogue de ce Mac et l’état de ses sources dans la banque Hindsight sélectionnée.',
          'This Mac’s source catalog and the status of its sources in the selected Hindsight bank.',
        )}
        actions={
          <>
            <IconButton
              icon={FolderOpen}
              label={t('Choisir le dossier mémoire', 'Choose a memory folder')}
              onClick={choose}
              disabled={busy || data.collecting}
            />
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
          </>
        }
      />
      <ErrorNotice message={mismatch ? null : data.error} />
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
            <Button icon={FolderOpen} disabled={busy || data.collecting} onClick={choose}>
              {t('Choisir un autre dossier', 'Choose another folder')}
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
              <h2>{data.folder ? shortName(data.folder) : t('Dossier local', 'Local folder')}</h2>
              <Badge>
                {!hasCatalog
                  ? t('Non configuré', 'Not configured')
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
      </section>

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
                  : data.folder
                    ? t('Aucune source collectée', 'No sources collected')
                    : t('Aucun dossier sélectionné', 'No folder selected')
              }
              description={
                allRecords.length
                  ? t(
                      'Essayez un autre filtre. Les validations internes et exports vides restent accessibles dans Archives à part.',
                      'Try another filter. Internal reviews and empty exports remain available in Separate archives.',
                    )
                  : data.folder
                    ? t(
                        'Collectez les sources définies dans la configuration du dossier.',
                        'Collect the sources defined in the folder configuration.',
                      )
                    : t(
                        'Choisissez votre dossier mémoire pour consulter ses conversations, commits, notes et rapports.',
                        'Choose your memory folder to browse its conversations, commits, notes, and reports.',
                      )
              }
              action={
                !data.folder && (
                  <Button icon={FolderOpen} onClick={choose}>
                    {t('Choisir le dossier mémoire', 'Choose a memory folder')}
                  </Button>
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
