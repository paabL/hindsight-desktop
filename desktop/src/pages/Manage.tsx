import { useI18n } from '../i18n';
import { translate as tr } from '../i18n-core';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import {
  ArrowDownToLine,
  BookOpen,
  Check,
  ChevronDown,
  Copy,
  Database,
  FileArchive,
  FlaskConical,
  FolderOpen,
  HardDrive,
  Layers3,
  Pause,
  Play,
  Plus,
  RotateCcw,
  RotateCw,
  Save,
  Search,
  Server,
  Settings2,
  ShieldCheck,
  Sparkles,
  Trash2,
  Upload,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
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
  Tabs,
  bankLabel,
  date,
  number,
} from '../ui';
import { saveExport } from '../transport';
import { takeMemoryTab } from '../memory-tab';
import { OBSERVATION_SCOPES } from '../observation-scopes';
import {
  chooseProvider,
  modelOptions,
  providerOptions,
  visibleRoleFields,
  isBooleanField,
  decisionProviderValue,
  localDecisionURL,
  localDecisionStateLabel,
} from '../model-field-options';

const memoryFields = {
  retainMission: 'retain_mission',
  extractionMode: 'retain_extraction_mode',
  customInstructions: 'retain_custom_instructions',
  chunkSize: 'retain_chunk_size',
  enableObservations: 'enable_observations',
  enableAutoConsolidation: 'enable_auto_consolidation',
  observationsMission: 'observations_mission',
  maxObservationsPerScope: 'max_observations_per_scope',
  reflectMission: 'reflect_mission',
  skepticism: 'disposition_skepticism',
  literalism: 'disposition_literalism',
  empathy: 'disposition_empathy',
  enableTextSearch: 'enable_text_search',
  enableTemporalRetrieval: 'enable_temporal_retrieval',
  enableGraphRetrieval: 'enable_graph_retrieval',
  enableReranking: 'enable_reranking',
  storeDocumentText: 'store_document_text',
  entitiesAllowFreeForm: 'entities_allow_free_form',
  defaultObservationScopes: 'default_observation_scopes',
  recallDecisionModelPrune: 'recall_decision_model_prune',
  recallDecisionModelDedup: 'recall_decision_model_dedup',
  recallPreferObservations: 'recall_prefer_observations',
} as const;

export function MemoryDesign({ data, run, busy, notify }: PageProps) {
  const { t } = useI18n();
  // Un autre écran peut demander un onglet précis (Traitements → « Créer des observations »).
  const [tab, setTab] = useState(() => takeMemoryTab('retain'));
  const [draft, setDraft] = useState<Row>({});
  const [sample, setSample] = useState('');
  const [advanced, setAdvanced] = useState('');
  const baseline = useRef<Row>({});
  useEffect(() => {
    if (!data.draft) return;
    const previous = baseline.current;
    const next = data.draft;
    baseline.current = next;
    setDraft((current) => ({
      ...next,
      ...Object.fromEntries(
        Object.entries(current).filter(([key, value]) => value !== previous[key]),
      ),
    }));
  }, [data.draft]);
  const set = (key: string, value: unknown) => setDraft((old) => ({ ...old, [key]: value }));
  function config() {
    const changes: Row = {};
    for (const [key, value] of Object.entries(draft))
      if (key in memoryFields && value !== data.draft?.[key])
        changes[memoryFields[key as keyof typeof memoryFields]] = value;
    if (advanced.trim()) {
      const parsed = JSON.parse(advanced);
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed))
        throw new Error('Expected a JSON object');
      Object.assign(changes, parsed);
    }
    return changes;
  }
  function action(command: string) {
    try {
      void run(command, { config: config(), sample });
    } catch {
      notify(
        t(
          'Les réglages avancés doivent contenir un objet JSON valide.',
          'Advanced settings must contain a valid JSON object.',
        ),
      );
    }
  }
  // Ce qui n'est pas encore enregistré, et ce que la banque règle autrement que le serveur.
  const pending = new Set(
    Object.keys(memoryFields).filter((key) => key in draft && draft[key] !== data.draft?.[key]),
  );
  const overridden = new Set<string>(
    Array.isArray(data.overridden) ? data.overridden : Object.keys(data.config?.overrides || {}),
  );
  // La pause a coupé la consolidation automatique : ce n'est pas un réglage de la banque.
  const pauseCut = !!data.pauseCutAutoConsolidation;
  if (pauseCut) overridden.delete('enable_auto_consolidation');
  const customized = (key: string) =>
    overridden.has(memoryFields[key as keyof typeof memoryFields]);
  const changeCount = pending.size + (advanced.trim() ? 1 : 0);
  // Toutes les clés propres à la banque, y compris celles que cette page ne montre pas : le retour au serveur les efface toutes.
  const customCount = overridden.size;
  const [openAdvanced, setOpenAdvanced] = useState<Record<string, boolean>>({});
  function discard() {
    setDraft({ ...baseline.current });
    setAdvanced('');
  }
  // Repère visuel seulement : le nom du champ reste celui que lisent les lecteurs d'écran.
  const mark = (key: string) =>
    pending.has(key) ? (
      <span className="setting-mark pending" aria-hidden="true">
        {t('modifié', 'changed')}
      </span>
    ) : customized(key) ? (
      <span
        className="setting-mark"
        aria-hidden="true"
        title={t(
          'Réglage propre à cette banque ; les autres suivent le serveur.',
          'Set for this bank only; other settings follow the server.',
        )}
      >
        {t('propre à la banque', 'bank-specific')}
      </span>
    ) : null;
  const textField = (key: string, title: string, placeholder: string) => (
    <label>
      <span className="setting-label">
        {title}
        {mark(key)}
      </span>
      <textarea
        rows={4}
        value={draft[key] || ''}
        onChange={(e) => set(key, e.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
  const toggle = (key: string, title: string, help: string, disabled = false) => (
    <label className={`setting-toggle ${disabled ? 'is-disabled' : ''}`}>
      <div>
        <strong>
          {title}
          {mark(key)}
        </strong>
        <span>{help}</span>
      </div>
      <input
        type="checkbox"
        role="switch"
        checked={draft[key] ?? false}
        disabled={disabled}
        onChange={(e) => set(key, e.target.checked)}
      />
    </label>
  );
  // Le réglage fin reste sur la page, replié : le titre dit s'il contient une valeur modifiée ou propre à la banque.
  const advancedSection = (keys: string[], children: ReactNode) => {
    const changed = keys.filter((key) => pending.has(key)).length;
    const own = keys.filter(customized).length;
    return (
      <details
        className="settings-advanced"
        open={openAdvanced[tab] ?? changed > 0}
        onToggle={(e) => {
          const open = e.currentTarget.open;
          setOpenAdvanced((old) => (old[tab] === open ? old : { ...old, [tab]: open }));
        }}
      >
        <summary>
          {t('Options avancées', 'Advanced options')}
          {changed > 0 ? (
            <span className="setting-mark pending">
              {t(`${changed} modifiée${changed > 1 ? 's' : ''}`, `${changed} changed`)}
            </span>
          ) : own > 0 ? (
            <span className="setting-mark">
              {t(`${own} propre${own > 1 ? 's' : ''} à la banque`, `${own} bank-specific`)}
            </span>
          ) : null}
        </summary>
        <div className="form-stack">{children}</div>
      </details>
    );
  };
  return (
    <>
      <PageHeader
        eyebrow={t('Une mémoire à votre image', 'Memory that works for you')}
        title={t('Comportement de la mémoire', 'Memory behavior')}
        description={t(
          'Ce que la banque sélectionnée retient, comment elle relie ses faits et comment elle répond. L’essentiel est visible ; le détail est dans « Options avancées ».',
          'What the selected bank remembers, how it connects its facts and how it answers. The essentials are visible; details are under “Advanced options”.',
        )}
        actions={
          <div className="action-row">
            {changeCount > 0 && (
              <Button kind="ghost" disabled={busy} onClick={discard}>
                {t('Annuler les changements', 'Discard changes')}
              </Button>
            )}
            <Button
              kind="primary"
              icon={Save}
              disabled={busy || !changeCount || data.configWritable === false}
              onClick={() => action('memory.save')}
            >
              {changeCount
                ? t(`Enregistrer (${changeCount})`, `Save (${changeCount})`)
                : t('Enregistrer', 'Save')}
            </Button>
          </div>
        }
      />
      <ErrorNotice message={data.error} />
      {data.configWritable === false && <ReadOnlyConfigNotice />}
      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          { id: 'retain', label: 'Extraction' },
          { id: 'observations', label: 'Consolidation' },
          { id: 'reflect', label: t('Réponses', 'Answers') },
          { id: 'recall', label: t('Recherche', 'Search') },
          { id: 'advanced', label: t('Expert', 'Expert') },
        ]}
      />
      <section className="card settings-card memory-settings">
        <div className="form-stack">
          {tab === 'retain' && (
            <>
              <h2>{t('Ce qui mérite d’être retenu', 'What is worth remembering')}</h2>
              <p className="muted">
                {t(
                  'La mission aide le modèle à choisir les faits utiles dans vos documents.',
                  'The mission helps the model choose useful facts from your documents.',
                )}
              </p>
              {textField(
                'retainMission',
                t('Mission de mémorisation', 'Memory mission'),
                t(
                  'Conserver les décisions, les raisons des choix et les connaissances durables.',
                  'Keep decisions, the reasons behind them, and lasting knowledge.',
                ),
              )}
              <label className="setting-compact">
                <span className="setting-label">
                  {t('Style d’extraction', 'Extraction style')}
                  {mark('extractionMode')}
                </span>
                <select
                  value={draft.extractionMode || 'concise'}
                  onChange={(e) => set('extractionMode', e.target.value)}
                >
                  {[
                    ['concise', t('Concis', 'Concise')],
                    ['verbose', t('Détaillé', 'Detailed')],
                    ['custom', t('Personnalisé', 'Custom')],
                    ['verbatim', 'Verbatim'],
                    ['chunks', t('Segments', 'Chunks')],
                  ].map(([id, label]) => (
                    <option value={id} key={id}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              {draft.extractionMode === 'custom' &&
                textField(
                  'customInstructions',
                  t('Instructions d’extraction', 'Extraction instructions'),
                  t('Ce que le modèle doit extraire…', 'What the model should extract…'),
                )}
              {advancedSection(
                ['chunkSize', 'storeDocumentText', 'entitiesAllowFreeForm'],
                <>
                  <label className="setting-compact">
                    <span className="setting-label">
                      {t('Taille des segments en caractères', 'Chunk size in characters')}
                      {mark('chunkSize')}
                    </span>
                    <input
                      type="number"
                      min="100"
                      value={draft.chunkSize || 3000}
                      onChange={(e) => set('chunkSize', Number(e.target.value))}
                    />
                  </label>
                  {toggle(
                    'storeDocumentText',
                    t('Conserver le texte des documents', 'Store document text'),
                    t(
                      'Permet de remonter des faits vers le document d’origine.',
                      'Lets you trace facts back to the original document.',
                    ),
                  )}
                  {toggle(
                    'entitiesAllowFreeForm',
                    t('Autoriser les entités libres', 'Allow free-form entities'),
                    t(
                      'Le modèle peut identifier des entités hors du vocabulaire défini.',
                      'The model can identify entities outside the defined vocabulary.',
                    ),
                  )}
                </>,
              )}
            </>
          )}
          {tab === 'observations' && (
            <>
              <h2>{t('Relier et consolider les faits', 'Connect and consolidate facts')}</h2>
              {toggle(
                'enableObservations',
                t('Créer des observations', 'Create observations'),
                t(
                  'Les faits retenus sont consolidés en observations, des synthèses plus générales. Désactivé, aucune consolidation n’a lieu.',
                  'Stored facts are consolidated into observations, broader summaries. When off, no consolidation runs.',
                ),
              )}
              {/* Sans observations, la consolidation automatique n'aurait rien à faire. */}
              {toggle(
                'enableAutoConsolidation',
                t('Consolider automatiquement', 'Consolidate automatically'),
                pauseCut
                  ? t(
                      'Coupée par la pause de cette banque : elle retrouvera son réglage à la reprise.',
                      'Turned off by this bank’s pause: it returns to its setting when processing resumes.',
                    )
                  : draft.enableObservations === false
                    ? t(
                        'Sans effet tant que « Créer des observations » est désactivé.',
                        'Has no effect while “Create observations” is off.',
                      )
                    : t(
                        'Après chaque extraction, le serveur consolide les nouveaux faits (appels LLM). Désactivé, lancez la consolidation depuis Mémoire › Consolidation.',
                        'After each extraction, the server consolidates new facts (LLM calls). When off, run consolidation from Memory › Consolidation.',
                      ),
                pauseCut || draft.enableObservations === false,
              )}
              {textField(
                'observationsMission',
                t('Mission de consolidation', 'Consolidation mission'),
                t(
                  'Les liens, les tendances ou les règles à faire émerger.',
                  'The connections, patterns, or rules to uncover.',
                ),
              )}
              {advancedSection(
                ['maxObservationsPerScope', 'defaultObservationScopes'],
                <>
                  <label className="setting-compact">
                    <span className="setting-label">
                      {t('Maximum d’observations par portée', 'Maximum observations per scope')}
                      {mark('maxObservationsPerScope')}
                    </span>
                    <input
                      type="number"
                      min="-1"
                      value={draft.maxObservationsPerScope ?? -1}
                      onChange={(e) => set('maxObservationsPerScope', Number(e.target.value))}
                    />
                    <small>
                      {t(
                        '−1 laisse le serveur choisir sa limite.',
                        '−1 lets the server choose its limit.',
                      )}
                    </small>
                  </label>
                  <label className="setting-compact">
                    <span className="setting-label">
                      {t('Portée des observations par défaut', 'Default observation scope')}
                      {mark('defaultObservationScopes')}
                    </span>
                    <select
                      value={draft.defaultObservationScopes || ''}
                      onChange={(e) => set('defaultObservationScopes', e.target.value)}
                    >
                      <option value="">
                        {t('Défaut du serveur (combinée)', 'Server default (combined)')}
                      </option>
                      {OBSERVATION_SCOPES.map((scope) => (
                        <option key={scope.value} value={scope.value}>
                          {t(scope.fr, scope.en)}
                        </option>
                      ))}
                    </select>
                    <small>
                      {t(
                        'Pour les documents envoyés sans portée.',
                        'For documents sent without a scope.',
                      )}
                    </small>
                  </label>
                </>,
              )}
            </>
          )}
          {tab === 'reflect' && (
            <>
              <h2>{t('Une façon de répondre', 'How to answer')}</h2>
              {textField(
                'reflectMission',
                t('Mission de réponse', 'Answer mission'),
                t(
                  'Répondre en français, clairement, en citant les faits utilisés.',
                  'Answer clearly in English, citing the facts used.',
                ),
              )}
              {[
                ['skepticism', t('Esprit critique', 'Critical thinking')],
                ['literalism', t('Interprétation littérale', 'Literal interpretation')],
                ['empathy', t('Empathie', 'Empathy')],
              ].map(([key, label]) => (
                <label className="range-label" key={key}>
                  <span className="setting-label">
                    {label}
                    {mark(key)}
                  </span>
                  <span>{draft[key] ?? 3} / 5</span>
                  <input
                    type="range"
                    min="1"
                    max="5"
                    value={draft[key] ?? 3}
                    onChange={(e) => set(key, Number(e.target.value))}
                  />
                </label>
              ))}
            </>
          )}
          {tab === 'recall' && (
            <>
              <h2>{t('Les chemins vers le bon contexte', 'Paths to the right context')}</h2>
              {toggle(
                'enableTextSearch',
                t('Recherche textuelle', 'Text search'),
                t('Trouve les faits par leurs mots.', 'Finds facts by their words.'),
              )}
              {toggle(
                'enableTemporalRetrieval',
                t('Recherche temporelle', 'Temporal search'),
                t(
                  'Tenir compte des dates et des événements.',
                  'Take dates and events into account.',
                ),
              )}
              {toggle(
                'enableGraphRetrieval',
                t('Recherche par relations', 'Relationship search'),
                t(
                  'Suivre les connexions du graphe de mémoire.',
                  'Follow connections in the memory graph.',
                ),
              )}
              {toggle(
                'enableReranking',
                t('Réordonner les résultats', 'Rerank results'),
                t('Affiner la pertinence après la recherche.', 'Refine relevance after searching.'),
              )}
              {toggle(
                'recallPreferObservations',
                t('Préférer les observations', 'Prefer observations'),
                t(
                  'Quand une observation qui résume un fait est trouvée, le fait est retiré des résultats. Les faits pas encore consolidés restent.',
                  'When an observation that sums up a fact is found, the fact is removed from the results. Facts not yet consolidated stay.',
                ),
              )}
              <SearchPool
                pool={data.searchPool}
                preferred={Boolean(draft.recallPreferObservations)}
              />
              {data.serverIs120 &&
                advancedSection(
                  ['recallDecisionModelPrune', 'recallDecisionModelDedup'],
                  <>
                    {toggle(
                      'recallDecisionModelPrune',
                      t('Écarter les faits inutiles', 'Remove irrelevant facts'),
                      t(
                        'Le modèle de décision retire ce qui n’aide pas la requête, sans requête de plus.',
                        'The decision model removes irrelevant facts without an extra request.',
                      ),
                    )}
                    {toggle(
                      'recallDecisionModelDedup',
                      t('Retirer les doublons', 'Remove duplicates'),
                      t(
                        'Un fait répété n’est rendu qu’une fois ; une requête de plus par recherche.',
                        'Repeated facts appear only once; adds one request per search.',
                      ),
                    )}
                    <p className="form-hint">
                      {t(
                        'Sans effet tant que le serveur n’a pas de modèle de décision pour la recherche.',
                        'Has no effect until the server has a decision model configured for search.',
                      )}
                    </p>
                  </>,
                )}
            </>
          )}
          {tab === 'advanced' && (
            <>
              <h2>{t('Clés de configuration', 'Configuration keys')}</h2>
              <p className="muted">
                {t(
                  'Pour les réglages que cette page ne présente pas (vocabulaire d’entités, stratégies d’extraction…) : saisissez les clés à modifier. Les valeurs non indiquées sont conservées.',
                  'For settings this page does not show (entity vocabulary, extraction strategies…): enter the keys to change. Unspecified values are kept.',
                )}
              </p>
              <textarea
                className="code-input"
                rows={12}
                aria-label={t('Configuration avancée JSON', 'Advanced JSON configuration')}
                value={advanced}
                onChange={(e) => setAdvanced(e.target.value)}
                placeholder={'{\n  "entity_labels": [],\n  "retain_strategies": []\n}'}
              />
            </>
          )}
        </div>
      </section>
      <section className="card settings-card">
        <CardHeader
          title={t('Essayer avant d’enregistrer', 'Try before saving')}
          subtitle={t(
            'Testez l’extraction sur un court extrait, avec le brouillon actuel.',
            'Test extraction on a short excerpt using the current draft.',
          )}
        />
        <div className="form-stack">
          <textarea
            rows={4}
            value={sample}
            onChange={(e) => setSample(e.target.value)}
            placeholder={t(
              'Collez un extrait représentatif de vos sources…',
              'Paste a representative excerpt from your sources…',
            )}
            aria-label={t('Extrait pour l’essai à blanc', 'Excerpt for dry run')}
          />
          <Button
            icon={FlaskConical}
            disabled={busy || !sample.trim()}
            onClick={() => action('memory.trial')}
          >
            {t('Préparer un essai à blanc', 'Prepare a dry run')}
          </Button>
          <ErrorNotice message={data.trialError} />
          {data.trial && <pre className="json-view">{JSON.stringify(data.trial, null, 2)}</pre>}
        </div>
      </section>
      {data.problems?.map((problem: string) => (
        <ErrorNotice key={problem} message={problem} />
      ))}
      {/* Le retour au défaut : visible, avec ce qu'il défait. */}
      <div className="settings-reset">
        <p>
          {customCount
            ? t(
                `Cette banque règle ${number(customCount)} option${customCount > 1 ? 's' : ''} autrement que le serveur.`,
                `This bank sets ${number(customCount)} option${customCount === 1 ? '' : 's'} differently from the server.`,
              )
            : t(
                'Cette banque suit les réglages du serveur.',
                'This bank follows the server settings.',
              )}
        </p>
        <Button
          kind="ghost"
          icon={RotateCcw}
          disabled={busy || !customCount || data.configWritable === false}
          onClick={() => void run('memory.reset')}
        >
          {t('Revenir aux réglages du serveur', 'Reset to server settings')}
        </Button>
      </div>
    </>
  );
}

export function Admin({
  data,
  run,
  busy,
  notify,
  demo,
  bank,
  banks = [],
}: PageProps & { bank?: Row; banks?: Row[] }) {
  const { t } = useI18n();
  const [modal, setModal] = useState<string | null>(null);
  const modalGeneration = useRef(0);
  const pendingModal = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  function showModal(value: string | null) {
    modalGeneration.current++;
    setModal(value);
  }
  // Nom et identifiant : la fusion agit sur des banques existantes, jamais sur un identifiant à retaper.
  const bankOption = (b: Row) => {
    const label = bankLabel(b);
    return label && label !== b.bank_id ? `${label} · ${b.bank_id}` : String(b.bank_id);
  };
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const [target, setTarget] = useState('');
  const [key, setKey] = useState('');
  const [value, setValue] = useState('');
  const [source, setSource] = useState('');
  async function exportFile(command: string) {
    const file = await run(command);
    if (file?.base64) {
      const saved = await saveExport(file.filename, file.base64);
      if (saved) notify(t('Export enregistré.', 'Export saved.'));
    }
  }
  async function importFile(file?: File) {
    if (!file) return;
    if (file.size > 11_500_000) {
      notify(
        t(
          'Choisissez une archive de moins de 11 Mo pour ce transfert.',
          'Choose an archive smaller than 11 MB for this transfer.',
        ),
      );
      return;
    }
    const data = new Uint8Array(await file.arrayBuffer());
    let text = '';
    for (let i = 0; i < data.length; i += 8192)
      text += String.fromCharCode(...data.subarray(i, i + 8192));
    await run(file.name.endsWith('.json') ? 'admin.template.validate' : 'admin.import', {
      base64: btoa(text),
      filename: file.name,
    });
  }
  return (
    <>
      <PageHeader
        eyebrow={t('Les outils de votre banque', 'Tools for your bank')}
        title={t('Banque', 'Memory bank')}
        description={t(
          'Gérez l’identité, les directives et les sauvegardes de la banque sélectionnée.',
          'Manage the selected bank’s identity, directives and backups.',
        )}
        actions={
          // Créer une banque n'est l'action principale que s'il n'y en a pas encore de choisie.
          <Button
            icon={Plus}
            kind={bank ? undefined : 'primary'}
            onClick={() => {
              showModal('create');
              setName('');
              setTarget('');
              setContent('');
            }}
          >
            {' '}
            {t('Nouvelle banque', 'New bank')}
          </Button>
        }
      />
      <ErrorNotice message={data.error} />
      {bank ? (
        <>
          <section className="card settings-card">
            <CardHeader
              title={t('Identité de la banque', 'Bank identity')}
              subtitle={t(
                'Un nom clair pour retrouver le bon contexte.',
                'A clear name to find the right context.',
              )}
            />
            <dl className="bank-identity">
              <dt>{t('Nom', 'Name')}</dt>
              <dd>{bank?.name || '—'}</dd>
              <dt>{t('Identifiant', 'ID')}</dt>
              <dd>{bank?.bank_id}</dd>
              {bank?.display_alias && (
                <>
                  <dt>{t('Alias affiché', 'Display alias')}</dt>
                  <dd>{bank.display_alias}</dd>
                </>
              )}
            </dl>
            <p className="form-hint">
              {t(
                'Renommer change seulement le nom affiché. L’identifiant reste celui qu’utilisent les clients (MCP, scripts).',
                'Renaming changes only the displayed name. Clients (MCP, scripts) keep using the ID.',
              )}
            </p>
            <div className="action-row">
              <Button
                icon={Database}
                onClick={() => {
                  setName(String(bank?.name || ''));
                  showModal('rename');
                }}
              >
                {' '}
                {t('Renommer', 'Rename')}
              </Button>
              <Button
                icon={Copy}
                onClick={() => {
                  setTarget('');
                  showModal('clone');
                }}
              >
                {' '}
                {t('Cloner', 'Clone')}
              </Button>
              <Button
                icon={Layers3}
                disabled={banks.length < 2}
                onClick={() => {
                  setSource(String(bank?.bank_id || ''));
                  setTarget(String(banks.find((b) => b.bank_id !== bank?.bank_id)?.bank_id || ''));
                  showModal('merge');
                }}
              >
                {' '}
                {t('Fusionner des banques', 'Merge banks')}
              </Button>
            </div>
          </section>
          <section className="card">
            <CardHeader
              title="Directives"
              subtitle={t(
                'Des consignes explicites pour guider les réponses.',
                'Explicit instructions to guide answers.',
              )}
              action={
                <Button
                  icon={Plus}
                  onClick={() => {
                    setName('');
                    setContent('');
                    showModal('directive');
                  }}
                >
                  {' '}
                  {t('Ajouter', 'Add')}
                </Button>
              }
            />
            {data.directives?.length ? (
              data.directives.map((directive: Row) => (
                <div className="directive-row" key={directive.id}>
                  <span className="category-icon sage">
                    <ShieldCheck size={20} />
                  </span>
                  <div>
                    <strong>{directive.name}</strong>
                    <p>{directive.content}</p>
                  </div>
                  <label className="checkbox-label">
                    <input
                      type="checkbox"
                      checked={directive.is_active ?? true}
                      onChange={(e) =>
                        void run('directive.update', { id: directive.id, active: e.target.checked })
                      }
                    />
                    Active
                  </label>
                  <IconButton
                    icon={Trash2}
                    label={t('Supprimer la directive', 'Delete directive')}
                    onClick={() => void run('directive.delete', { id: directive.id })}
                  />
                </div>
              ))
            ) : (
              <Empty
                icon={ShieldCheck}
                title={t('Aucune directive', 'No directives')}
                description={t(
                  'Les directives donnent des consignes persistantes au modèle de réponse.',
                  'Directives provide persistent instructions to the answer model.',
                )}
              />
            )}
          </section>
          <section className="card settings-card">
            <CardHeader
              title={t('Sauvegarder et transférer', 'Back up and transfer')}
              subtitle={t(
                'Conservez une archive, ou réutilisez les réglages de la banque ailleurs grâce à son gabarit de configuration.',
                'Keep an archive, or reuse the bank’s settings elsewhere with its configuration template.',
              )}
            />
            <div className="transfer-grid">
              <button onClick={() => void exportFile('admin.export')}>
                <FileArchive size={24} />
                <strong>{t('Exporter la banque', 'Export bank')}</strong>
                <span>{t('Données et configuration', 'Data and configuration')}</span>
              </button>
              <button onClick={() => void exportFile('admin.template')}>
                <BookOpen size={24} />
                <strong>{t('Exporter le gabarit', 'Export template')}</strong>
                <span>{t('Gabarit de configuration JSON', 'JSON configuration template')}</span>
              </button>
              <label className="file-upload">
                <Upload size={24} />
                <strong>{t('Importer une archive', 'Import archive')}</strong>
                <span>{t('Archive ZIP ou gabarit JSON', 'ZIP archive or JSON template')}</span>
                <input
                  type="file"
                  accept=".zip,.json"
                  onChange={(e) => void importFile(e.target.files?.[0])}
                />
              </label>
            </div>
            {data.templateDryRun && (
              <div className="form-stack">
                <p className="form-hint">{templateEffect(data.templateDryRun)}</p>
                <details>
                  <summary>{t('Détail', 'Details')}</summary>
                  <pre className="json-view">{JSON.stringify(data.templateDryRun, null, 2)}</pre>
                </details>
                <Button icon={Check} onClick={() => void run('admin.template.apply')}>
                  {' '}
                  {t('Appliquer ce gabarit', 'Apply this template')}
                </Button>
              </div>
            )}
          </section>
          <details className="card advanced-details">
            <summary>
              {' '}
              {t('Configuration avancée de la banque', 'Advanced bank configuration')}
            </summary>
            <div className="form-stack">
              <pre className="json-view">
                {JSON.stringify(data.config?.overrides || {}, null, 2)}
              </pre>
              <div className="two-fields">
                <label>
                  {' '}
                  {t('Clé', 'Key')}
                  <input
                    value={key}
                    onChange={(e) => setKey(e.target.value)}
                    placeholder="retain_mission"
                  />
                </label>
                <label>
                  {' '}
                  {t('Valeur', 'Value')}
                  <input
                    value={value}
                    onChange={(e) => setValue(e.target.value)}
                    placeholder={t('Texte ou valeur JSON', 'Text or JSON value')}
                  />
                </label>
              </div>
              {data.configWritable === false && <ReadOnlyConfigNotice />}
              <Button
                icon={Save}
                disabled={busy || !key.trim() || data.configWritable === false}
                onClick={() => void run('admin.override', { key, value })}
              >
                {' '}
                {t('Préparer la modification', 'Prepare change')}
              </Button>
              <small>
                {t(
                  'Pour supprimer tous les réglages propres à la banque : Comportement de la mémoire › Revenir aux réglages du serveur.',
                  'To remove every bank-specific setting: Memory behavior › Reset to server settings.',
                )}
              </small>
            </div>
          </details>
          <details className="card danger-zone">
            <summary>{t('Actions de suppression', 'Delete actions')}</summary>
            <p>
              {' '}
              {t(
                'Ces actions effacent des faits, des observations ou toute la banque. Une confirmation séparée précisera ce qui sera supprimé.',
                'These actions erase facts, observations or the whole memory bank. A separate confirmation will explain what will be deleted.',
              )}
            </p>
            <div className="action-row">
              {/* Rien à effacer : le bouton reste visible mais inactif, avec le compte qui l'explique. */}
              <Button
                kind="danger"
                disabled={busy || data.observationTotal === 0}
                onClick={() => void run('admin.clearObservations')}
              >
                {' '}
                {typeof data.observationTotal === 'number'
                  ? t(
                      `Effacer les observations (${number(data.observationTotal)})`,
                      `Clear observations (${number(data.observationTotal)})`,
                    )
                  : t('Effacer les observations', 'Clear observations')}
              </Button>
              <Button
                kind="danger"
                disabled={busy || data.factTotal === 0}
                onClick={() => void run('admin.deleteMemories')}
              >
                {' '}
                {typeof data.factTotal === 'number'
                  ? t(
                      `Effacer tous les faits (${number(data.factTotal)})`,
                      `Clear all facts (${number(data.factTotal)})`,
                    )
                  : t('Effacer tous les faits', 'Clear all facts')}
              </Button>
              <Button kind="danger" icon={Trash2} onClick={() => void run('admin.deleteBank')}>
                {' '}
                {t('Supprimer la banque', 'Delete memory bank')}
              </Button>
            </div>
          </details>
        </>
      ) : (
        <Empty
          icon={Database}
          title={
            banks.length
              ? t('Aucune banque sélectionnée', 'No memory bank selected')
              : t('Aucune banque sur ce serveur', 'No memory banks on this server')
          }
          description={
            banks.length
              ? t(
                  'Choisissez une banque dans la barre latérale pour gérer son identité, ses directives et ses sauvegardes.',
                  'Select a memory bank in the sidebar to manage its identity, directives and backups.',
                )
              : t(
                  'Créez une banque avec « Nouvelle banque » pour commencer à mémoriser vos sources.',
                  'Create a memory bank with New bank to start remembering your sources.',
                )
          }
        />
      )}
      {modal && (
        <Modal
          title={
            {
              create: t('Une nouvelle banque', 'A new bank'),
              rename: t('Renommer la banque', 'Rename bank'),
              clone: t('Cloner la banque', 'Clone bank'),
              merge: t('Fusionner deux banques', 'Merge two banks'),
              directive: t('Une nouvelle directive', 'A new directive'),
            }[modal] || ''
          }
          onClose={() => showModal(null)}
        >
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
              if (busy || pendingModal.current) return;
              pendingModal.current = true;
              setSubmitting(true);
              const generation = modalGeneration.current;
              const commands: Record<string, string> = {
                create: 'bank.create',
                rename: 'bank.rename',
                clone: 'admin.clone',
                merge: 'bank.merge',
                directive: 'directive.create',
              };
              void run(commands[modal], {
                id: target,
                name,
                mission: content,
                content,
                target,
                source,
              })
                .then((result) => {
                  // Une demande valide ouvre une confirmation ; un refus (identifiant pris, même nom…)
                  // n’arrive que comme message : le formulaire reste ouvert pour être corrigé.
                  const accepted = demo || !!result?.confirmations?.length;
                  if (!result?.error && accepted && generation === modalGeneration.current)
                    showModal(null);
                })
                .catch((error) => notify(error instanceof Error ? error.message : String(error)))
                .finally(() => {
                  pendingModal.current = false;
                  setSubmitting(false);
                });
            }}
          >
            {['create', 'rename', 'directive'].includes(modal) && (
              <label>
                {' '}
                {t('Nom', 'Name')}
                <input required value={name} onChange={(e) => setName(e.target.value)} />
              </label>
            )}
            {['create', 'clone'].includes(modal) && (
              <label>
                {t('Identifiant de la nouvelle banque', 'New bank ID')}
                <input
                  required
                  pattern="[A-Za-z0-9][A-Za-z0-9._-]*"
                  value={target}
                  onChange={(e) => setTarget(e.target.value)}
                  placeholder={t('mon-projet', 'my-project')}
                />
              </label>
            )}
            {modal === 'clone' && bank && (
              <p className="form-hint">
                {t(
                  `Copie de « ${bankOption(bank)} » dans une nouvelle banque, qui ne doit pas encore exister.`,
                  `Copies “${bankOption(bank)}” into a new bank, which must not exist yet.`,
                )}
              </p>
            )}
            {modal === 'merge' && (
              <>
                <label>
                  {t('Banque source', 'Source bank')}
                  <select
                    required
                    value={source}
                    onChange={(e) => {
                      setSource(e.target.value);
                      if (e.target.value === target)
                        setTarget(
                          String(banks.find((b) => b.bank_id !== e.target.value)?.bank_id || ''),
                        );
                    }}
                  >
                    {banks.map((b) => (
                      <option key={b.bank_id} value={b.bank_id}>
                        {bankOption(b)}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  {t('Banque de destination', 'Destination bank')}
                  <select required value={target} onChange={(e) => setTarget(e.target.value)}>
                    {banks
                      .filter((b) => b.bank_id !== source)
                      .map((b) => (
                        <option key={b.bank_id} value={b.bank_id}>
                          {bankOption(b)}
                        </option>
                      ))}
                  </select>
                </label>
                <p className="form-hint">
                  {t(
                    'Les documents de la source sont ajoutés à la destination. La confirmation suivante détaille le volume et ce qui advient de la source.',
                    'Documents from the source are added to the destination. The next confirmation shows the volume and what happens to the source.',
                  )}
                </p>
              </>
            )}
            {['create', 'directive'].includes(modal) && (
              <label>
                {modal === 'create'
                  ? t('Mission de réponse (facultative)', 'Answer mission (optional)')
                  : t('Consigne', 'Instruction')}
                <textarea
                  required={modal === 'directive'}
                  value={content}
                  onChange={(e) => setContent(e.target.value)}
                  rows={4}
                />
              </label>
            )}
            <div className="modal-actions">
              <Button type="button" onClick={() => showModal(null)}>
                {' '}
                {t('Annuler', 'Cancel')}
              </Button>
              <Button kind="primary" disabled={busy || submitting}>
                {' '}
                {t('Continuer', 'Continue')}
              </Button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}

function ModelChoices({
  value,
  options,
  onChange,
  disabled,
}: {
  value: string;
  options: { id: string; label: string; disabled?: boolean }[];
  onChange: (id: string) => void;
  disabled: boolean;
}) {
  return (
    <div className="model-choices" role="radiogroup">
      {options.map((option) => (
        <button
          key={option.id}
          type="button"
          role="radio"
          aria-checked={value === option.id}
          disabled={disabled || option.disabled}
          onClick={() => value !== option.id && onChange(option.id)}
        >
          {value === option.id && <Check size={13} />}
          {option.label}
        </button>
      ))}
    </div>
  );
}

// Choix préparés dans le script : rien ne change avant l’enregistrement et le redémarrage du serveur.
function HindsightModels({ models, run, busy }: Pick<PageProps, 'run' | 'busy'> & { models: Row }) {
  const { t } = useI18n();
  const local = models.local || {};
  const running = local.phase === 'running';
  const old = !models.serverIs120;
  return (
    <section className="card hindsight-models">
      <CardHeader
        title={t('Modèles Hindsight', 'Hindsight models')}
        subtitle={t(
          'Modèles spécialisés, sur Hindsight Cloud (facturés au compte) ou sur ce Mac. Chaque choix prépare le script : enregistrez-le, puis redémarrez le serveur.',
          'Specialized models, on Hindsight Cloud (billed to your account) or on this Mac. Each choice prepares the script: save it, then restart the server.',
        )}
      />
      {old && (
        <div className="notice">
          {' '}
          {t(
            'Ces modèles demandent le serveur Hindsight 1.2.0 ; seul le reranker local est déjà disponible.',
            'These models require Hindsight server 1.2.0; only the local reranker is available on older versions.',
          )}
        </div>
      )}
      <div className="model-rows">
        <div>
          <div>
            <strong>
              {' '}
              {t('Modèle de décision · hs-decide-1-flash', 'Decision model · hs-decide-1-flash')}
            </strong>
            <p>
              {' '}
              {t(
                'Tranche les choix de la consolidation, des Réponses et des pages de connaissance sans appel LLM : moins de jetons et moins d’attente.',
                'Makes consolidation, Answers and knowledge page decisions without LLM calls: fewer tokens and less waiting.',
              )}
              {models.decision === 'other' &&
                t(
                  ' Réglage personnalisé dans le rôle ci-dessous.',
                  ' Custom settings in the role below.',
                )}
            </p>
          </div>
          <ModelChoices
            value={models.decision}
            disabled={busy}
            onChange={(source) => void run('server.decision', { source })}
            options={[
              { id: 'cloud', label: 'Hindsight Cloud', disabled: old },
              { id: 'local', label: t('Sur ce Mac', 'On this Mac'), disabled: old || !running },
              { id: 'off', label: t('Désactivé', 'Off') },
            ]}
          />
        </div>
        <div>
          <div>
            <strong>Reranker · hs-rerank-1</strong>
            <p>
              {' '}
              {t(
                'Classe les résultats de recherche, sans ré-indexation. Sur ce Mac, le serveur le télécharge à son premier démarrage.',
                'Ranks search results without reindexing. On this Mac, the server downloads it at first startup.',
              )}
              {models.reranker === 'other' &&
                t(' Autre reranker configuré.', ' Another reranker is configured.')}
            </p>
          </div>
          <ModelChoices
            value={models.reranker}
            disabled={busy}
            onChange={(source) => void run('server.reranker', { source })}
            options={[
              { id: 'cloud', label: 'Hindsight Cloud', disabled: old },
              { id: 'local', label: t('Sur ce Mac', 'On this Mac') },
            ]}
          />
        </div>
      </div>
      {models.needsCloudAccount && (
        <div className="notice">
          {' '}
          {t(
            'Connectez le compte Hindsight Cloud ci-dessus : sans sa clé, le serveur refusera de démarrer avec ces choix.',
            'Connect your Hindsight Cloud account above: without its key, the server cannot start with these choices.',
          )}
        </div>
      )}
      {models.decision === 'local' && !running && (
        <div className="notice">
          {' '}
          {t(
            'Le modèle de décision de ce Mac n’est pas en marche : démarrez-le avant le serveur.',
            'The decision model on this Mac is not running: start it before the server.',
          )}
        </div>
      )}
      <div className="local-decision">
        <div>
          <strong>{t('Modèle de décision sur ce Mac', 'Decision model on this Mac')}</strong>
          <p>
            {local.summary}
            {local.installed
              ? t(
                  ' · 127.0.0.1:8766, environ 2 Go de mémoire',
                  ' · 127.0.0.1:8766, about 2 GB of memory',
                )
              : t(
                  ' · environ 2 Go à télécharger, puis rien ne sort du Mac',
                  ' · about 2 GB to download, then processing stays on this Mac',
                )}
          </p>
        </div>
        <Badge tone={running ? 'sage' : local.installed ? 'amber' : 'neutral'}>
          <span className={`status-dot ${running ? 'green' : 'warning'}`} />
          {localDecisionStateLabel(local.phase)}
        </Badge>
        {!local.installed ? (
          <Button
            icon={ArrowDownToLine}
            disabled={busy || local.busy}
            onClick={() => void run('decision.install')}
          >
            {' '}
            {t('Installer…', 'Install…')}
          </Button>
        ) : running ? (
          <Button
            icon={Pause}
            disabled={busy || local.busy}
            onClick={() => void run('decision.stop')}
          >
            {' '}
            {t('Arrêter', 'Stop')}
          </Button>
        ) : (
          <Button
            icon={Play}
            disabled={busy || local.busy}
            onClick={() => void run('decision.start')}
          >
            {' '}
            {t('Démarrer', 'Start')}
          </Button>
        )}
      </div>
      <ErrorNotice message={local.problem} />
      {(local.log || local.installed) && (
        <details className="advanced-details local-decision-log">
          <summary>{t('Journal du modèle local', 'Local model log')}</summary>
          <pre className="json-view">
            {local.log || t('Aucun journal disponible.', 'No log available.')}
          </pre>
          <p>
            {' '}
            {t('Dossier :', 'Folder:')} {local.root} {t('· journal :', '· log:')} {local.logPath}
          </p>
          {local.installed && (
            <Button
              kind="danger"
              icon={Trash2}
              disabled={busy || local.busy}
              onClick={() => void run('decision.uninstall')}
            >
              {' '}
              {t('Désinstaller le modèle local', 'Uninstall local model')}
            </Button>
          )}
        </details>
      )}
    </section>
  );
}

/** Réglages › Serveur : l'adresse du serveur et, s'il tourne sur ce Mac, son service, son script et ses sauvegardes. */
export function ServerSettings({
  data,
  run,
  busy,
  connection,
}: PageProps & { connection?: ReactNode }) {
  const { t } = useI18n();
  const [scriptPath, setScriptPath] = useState('');
  const service = data.service || {};
  const serviceBusy = busy || service.busy;
  // État unique du moteur (prêt, arrêté, démarrage, arrêt, échec) ; à défaut, déduit des champs.
  const phase: string =
    service.phase ||
    (service.busy
      ? 'starting'
      : service.error
        ? 'failed'
        : service.reachable
          ? 'ready'
          : 'stopped');
  return (
    <>
      <PageHeader
        eyebrow={t('Le moteur de votre mémoire', 'The engine behind your memory')}
        title={t('Serveur', 'Server')}
        description={t(
          'L’adresse du serveur Hindsight et, s’il tourne sur ce Mac, son service, son script de lancement et ses sauvegardes. Les modèles se règlent dans Modèles.',
          'The Hindsight server address and, when it runs on this Mac, its service, launch script and backups. Models are set in Models.',
        )}
      />
      {connection}
      <section className="card service-card">
        <div className="service-identity">
          <span className="service-symbol">
            <Server size={26} strokeWidth={1.5} />
          </span>
          <div>
            <h2>{t('Service Hindsight', 'Hindsight service')}</h2>
            {/* Texte et badge lisent le même état du moteur : jamais « fonctionne » à côté de « Hors connexion ». */}
            <p>
              {phase === 'starting'
                ? t('Démarrage en cours…', 'Starting…')
                : phase === 'stopping'
                  ? t('Arrêt en cours…', 'Stopping…')
                  : phase === 'failed'
                    ? t(
                        'La dernière action sur le service a échoué',
                        'The last service action failed',
                      )
                    : phase === 'ready'
                      ? service.running
                        ? t('Le serveur fonctionne sur ce Mac', 'The server is running on this Mac')
                        : t(
                            'Le serveur répond, lancé hors du service de l’app',
                            'The server responds, started outside the app’s service',
                          )
                      : service.running
                        ? t(
                            'Le service tourne mais le serveur ne répond pas encore',
                            'The service is running but the server does not respond yet',
                          )
                        : service.installed
                          ? t(
                              'Le service est installé et arrêté',
                              'The service is installed and stopped',
                            )
                          : t('Le service n’est pas installé', 'The service is not installed')}
            </p>
          </div>
          <Badge tone={phase === 'failed' ? 'red' : phase === 'ready' ? 'sage' : 'amber'}>
            <span
              className={`status-dot ${phase === 'failed' ? 'red' : phase === 'ready' ? 'green' : 'warning'}`}
            />
            {phase === 'starting'
              ? t('Démarrage…', 'Starting…')
              : phase === 'stopping'
                ? t('Arrêt…', 'Stopping…')
                : phase === 'failed'
                  ? t('Échec', 'Failed')
                  : phase === 'ready'
                    ? t('Accessible', 'Reachable')
                    : t('Hors connexion', 'Offline')}
          </Badge>
        </div>
        <div className="service-actions">
          {service.installed ? (
            <>
              <Button
                icon={Play}
                disabled={serviceBusy || !service.canStart}
                onClick={() => void run('service.start')}
              >
                {' '}
                {t('Démarrer', 'Start')}
              </Button>
              <Button
                icon={Pause}
                disabled={serviceBusy || !service.canStop}
                onClick={() => void run('service.stop')}
              >
                {' '}
                {t('Arrêter', 'Stop')}
              </Button>
              <Button
                icon={RotateCw}
                disabled={serviceBusy}
                onClick={() => void run('service.restart')}
              >
                {' '}
                {t('Redémarrer', 'Restart')}
              </Button>
            </>
          ) : (
            <Button icon={Plus} disabled={busy} onClick={() => void run('service.install')}>
              {' '}
              {t('Installer le service…', 'Install service…')}
            </Button>
          )}
          <span className="spacer" />
          {service.installed && (
            <label className="checkbox-label">
              <input
                type="checkbox"
                disabled={serviceBusy}
                checked={service.atLogin || false}
                onChange={(e) => void run('service.atLogin', { enabled: e.target.checked })}
              />{' '}
              {t('À l’ouverture de session', 'At login')}
            </label>
          )}
        </div>
        <ErrorNotice message={service.error} />
        <ErrorNotice message={service.scriptWarning} />
      </section>
      <ErrorNotice message={data.error} />
      {data.needsRestart && (
        <div className="notice">
          {' '}
          {t(
            'Des réglages ont été enregistrés. Redémarrez le serveur pour les appliquer.',
            'Settings were saved. Restart the server to apply them.',
          )}
        </div>
      )}
      <details className="card advanced-details">
        <summary>{t('Script, sauvegardes et journal', 'Script, backups, and log')}</summary>
        <div className="form-stack">
          <label>
            {' '}
            {t('Script de lancement', 'Launch script')}
            <input
              value={scriptPath || data.scriptPath || ''}
              onChange={(e) => setScriptPath(e.target.value)}
              placeholder="~/.hindsight/start-api.sh"
            />
          </label>
          <Button
            icon={FolderOpen}
            onClick={() => void run('server.script', { path: scriptPath || data.scriptPath })}
          >
            {' '}
            {t('Charger ce script', 'Load this script')}
          </Button>
          {data.backups?.map((backup: Row) => (
            <div className="backup-row" key={backup.url}>
              <span>{date(backup.date, true)}</span>
              <Button
                disabled={busy}
                onClick={() => void run('server.restore', { path: backup.url })}
              >
                {' '}
                {t('Restaurer cette sauvegarde', 'Restore this backup')}
              </Button>
            </div>
          ))}
          <h3>{t('Journal du service', 'Service log')}</h3>
          <pre className="json-view">
            {service.log || t('Aucun journal disponible.', 'No log available.')}
          </pre>
          {service.installed && (
            <Button kind="danger" onClick={() => void run('service.uninstall')}>
              {' '}
              {t('Désinstaller le service', 'Uninstall service')}
            </Button>
          )}
        </div>
      </details>
    </>
  );
}

export type ModelRequest = { kind: 'role' | 'tools'; id?: string; nonce: number };

/** Tout ce qui touche aux modèles, sous le schéma de la page Modèles : comptes, rôles et installation. */
export function ModelManagement({
  data,
  run,
  busy,
  request,
}: PageProps & { request?: ModelRequest }) {
  const { t } = useI18n();
  const [role, setRole] = useState<Row | null>(null);
  const [fields, setFields] = useState<Row>({});
  const [customModels, setCustomModels] = useState<Set<string>>(new Set());
  const [modelToolsOpen, setModelToolsOpen] = useState(false);
  const [rolesOpen, setRolesOpen] = useState(false);
  const accountsRef = useRef<HTMLElement>(null);
  const rolesRef = useRef<HTMLDetailsElement>(null);
  const [decisionTab, setDecisionTab] = useState('general');
  const [decisionLocation, setDecisionLocation] = useState<string | null>(null);
  const [roleSaving, setRoleSaving] = useState(false);
  const savingRole = useRef(false);
  const [roleError, setRoleError] = useState('');
  const [roleRevision, setRoleRevision] = useState<string>();
  const [roleScriptPath, setRoleScriptPath] = useState<string>();
  const latestData = useRef(data);
  latestData.current = data;
  const roleStale =
    role && (roleScriptPath !== data.scriptPath || roleRevision !== data.modelWorkflow?.revision);
  const staleMessage = t(
    'Les réglages ont changé. Fermez cette fenêtre et rouvrez le rôle avant de réessayer.',
    'Settings changed. Close this window and reopen the role before trying again.',
  );
  useEffect(() => {
    setDecisionTab('general');
    setDecisionLocation(null);
  }, [role?.id]);
  async function saveRole() {
    if (!role || busy || savingRole.current || !Object.keys(fields).length) return;
    if (roleStale) {
      setRoleError(staleMessage);
      return;
    }
    savingRole.current = true;
    setRoleSaving(true);
    setRoleError('');
    async function apply(command: string, args: Row) {
      if (latestData.current.scriptPath !== roleScriptPath) throw new Error(staleMessage);
      const result = await run(command, args);
      if (result?.error) throw new Error(String(result.error));
      if (latestData.current.scriptPath !== roleScriptPath) throw new Error(staleMessage);
      if (result?.data) setRoleRevision(result.data.modelWorkflow?.revision);
    }
    try {
      if (role.id === 'decision' && decisionLocation)
        await apply('server.decision', { source: decisionLocation });
      const provider = role.fields.find((field: Row) => field.name.endsWith('_PROVIDER'))?.name;
      // Provider presets may reset the model. Apply explicit fields afterwards, including
      // advanced overrides entered after choosing the local or Cloud preset.
      if (role.isModelRole && Object.hasOwn(fields, provider))
        await apply('server.provider', { role: role.id, provider: fields[provider] });
      for (const [name, value] of Object.entries(fields)) {
        if (name === provider && (role.isModelRole || (role.id === 'decision' && decisionLocation)))
          continue;
        if (!(
          value === '' && role.fields.some((field: Row) => field.name === name && field.secret)
        ))
          await apply('server.field', { name, value });
      }
      setRole(null);
    } catch (error) {
      setRoleError(error instanceof Error ? error.message : String(error));
    } finally {
      savingRole.current = false;
      setRoleSaving(false);
    }
  }
  function openRole(item: Row) {
    setRole(item);
    setFields({});
    setCustomModels(new Set());
    setRoleError('');
    setRoleRevision(data.modelWorkflow?.revision);
    setRoleScriptPath(data.scriptPath);
  }
  // Le schéma ouvre le rôle sur place, ou montre les comptes et l'installation, sans quitter la page.
  useEffect(() => {
    if (!request) return;
    if (request.kind === 'role') {
      const item = (data.roles || []).find((r: Row) => r.id === request.id);
      if (item) {
        openRole(item);
        return;
      }
      setRolesOpen(true);
      rolesRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } else {
      setModelToolsOpen(true);
      accountsRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [request?.nonce]);
  return (
    <>
      {(data.configurationProblems || []).map((problem: string) => (
        <ErrorNotice key={problem} message={problem} />
      ))}
      <section className="card account-card" ref={accountsRef}>
        <CardHeader
          title={t('Connexions aux comptes', 'Account connections')}
          subtitle={t(
            'Sessions des clients officiels, conservées sur ce Mac.',
            'Official client sessions, kept on this Mac.',
          )}
        />
        <div className="account-rows">
          {(data.accounts || []).map((account: Row) => (
            <div
              key={account.id}
              data-state={account.state || (account.connected ? 'connected' : 'unknown')}
            >
              <span className="account-status-dot" aria-hidden="true" />
              <div>
                <strong>{account.title}</strong>
                <p>{account.status}</p>
              </div>
              {data.connectingAccount === account.id && data.authorizationURL && (
                <Button
                  kind="ghost"
                  onClick={() => void run('external.open', { url: data.authorizationURL })}
                >
                  {' '}
                  {t('Rouvrir la page', 'Reopen page')}
                </Button>
              )}
              {account.connected && account.canDisconnect ? (
                <Button
                  disabled={busy || !!data.connectingAccount}
                  onClick={() => void run('account.disconnect', { account: account.id })}
                >
                  {' '}
                  {t('Se déconnecter', 'Disconnect')}
                </Button>
              ) : (
                <Button
                  disabled={busy || !!data.connectingAccount}
                  onClick={() => void run('account.connect', { account: account.id })}
                >
                  {' '}
                  {account.connected ? t('Reconnecter', 'Reconnect') : t('Se connecter', 'Connect')}
                </Button>
              )}
            </div>
          ))}
        </div>
      </section>
      <details
        className="card advanced-details"
        ref={rolesRef}
        open={rolesOpen}
        onToggle={(e) => setRolesOpen(e.currentTarget.open)}
      >
        <summary>
          {t('Tous les rôles et réglages avancés', 'All roles and advanced settings')}
        </summary>
        <div className="section-heading">
          <div>
            <h2>{t('Un modèle pour chaque usage', 'A model for each task')}</h2>
            <p>
              {' '}
              {t(
                'Les rôles héritent des valeurs globales tant que vous ne les personnalisez pas.',
                'Roles inherit global values until you customize them.',
              )}
            </p>
            {data.testModelsBlocked && <p className="form-hint">{data.testModelsBlocked}</p>}
          </div>
          <Button
            disabled={busy || data.canTestModels === false}
            icon={FlaskConical}
            onClick={() => void run('diagnostic.llm')}
          >
            {' '}
            {t('Tester les modèles', 'Test models')}
          </Button>
        </div>
        {Array.isArray(data.diagnostic) && (
          <div className="model-test" data-model-test>
            <p className="model-test-title">
              <strong>{t('Dernier test des modèles', 'Last model test')}</strong>
              {data.diagnosticAt && <span>{date(data.diagnosticAt, true)}</span>}
            </p>
            {data.diagnostic.length ? (
              <ul>
                {data.diagnostic.map((row: Row) => (
                  <li key={row.role}>
                    <Badge tone={row.ok ? 'sage' : 'red'}>{row.status}</Badge>
                    <span>{row.title}</span>
                    {typeof row.latencyMs === 'number' && (
                      <small>{number(Math.round(row.latencyMs))} ms</small>
                    )}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="form-hint">
                {t(
                  'Le serveur n’a renvoyé aucun résultat pour le test des modèles.',
                  'The server returned no result for the model test.',
                )}
              </p>
            )}
          </div>
        )}
        <ErrorNotice message={data.diagnosticError} />
        <div className="server-roles">
          {(data.roles || []).map((item: Row) => (
            <button
              key={item.id}
              className="card role-card"
              disabled={busy || roleSaving}
              onClick={() => openRole(item)}
            >
              <span className="role-icon">
                <Sparkles size={21} />
              </span>
              <div>
                <h3>{item.title}</h3>
                <p>
                  {item.effective ||
                    t('Hérite des réglages du serveur', 'Inherits server settings')}
                </p>
              </div>
              <Settings2 size={17} />
            </button>
          ))}
        </div>
        {!data.roles?.length && (
          <Empty
            icon={Server}
            title={t('Choisissez le script du serveur', 'Choose the server script')}
            description={t(
              'Le script de lancement contient les modèles et leurs fournisseurs.',
              'The launch script contains the models and their providers.',
            )}
          />
        )}
      </details>
      {data.hindsightModels && (
        <details
          className="card advanced-details"
          data-model-tools
          open={modelToolsOpen}
          onToggle={(e) => setModelToolsOpen(e.currentTarget.open)}
        >
          <summary>
            {t('Installation et services des modèles', 'Model installation and services')}
          </summary>
          <HindsightModels models={data.hindsightModels} run={run} busy={busy} />
        </details>
      )}
      {data.hasChanges && (
        <details className="card advanced-details">
          <summary>{t('Détail des modifications préparées', 'Prepared changes in detail')}</summary>
          <pre className="json-view">
            {(data.diff || [])
              .map(
                (line: Row) =>
                  `${line.kind === 'added' ? '+ ' : line.kind === 'removed' ? '− ' : '  '}${line.text || line.line || ''}`,
              )
              .join('\n')}
          </pre>
        </details>
      )}
      {data.warnings?.map((warning: string) => (
        <div className="notice" key={warning}>
          {warning}
        </div>
      ))}
      {role && (
        <Modal
          title={role.id === 'decision' ? t('Modèle de décision', 'Decision model') : role.title}
          onClose={() => {
            if (savingRole.current) return;
            setRole(null);
            setDecisionTab('general');
          }}
        >
          <form
            className="form-stack model-editor"
            onSubmit={(e) => {
              e.preventDefault();
              void saveRole();
            }}
          >
            {role.id === 'decision' && (
              <Tabs
                value={decisionTab}
                onChange={setDecisionTab}
                items={[
                  { id: 'general', label: t('Modèle', 'Model') },
                  { id: 'recall', label: t('Recherche', 'Search') },
                  { id: 'reflect', label: t('Réponses', 'Answers') },
                  { id: 'consolidation', label: t('Consolidation', 'Consolidation') },
                  { id: 'pages', label: t('Connaissances', 'Knowledge') },
                ]}
              />
            )}
            <fieldset className="model-editor-fields" disabled={busy || roleSaving || !!roleStale}>
              {(() => {
                const all = visibleRoleFields(role, fields, data);
                const selected =
                  role.id !== 'decision'
                    ? all
                    : all.filter((field: Row) =>
                        decisionTab === 'general'
                          ? field.name.startsWith('HINDSIGHT_API_DECISION_MODEL_')
                          : decisionTab === 'pages'
                            ? field.name.startsWith('HINDSIGHT_API_MENTAL_MODEL_')
                            : field.name.startsWith(`HINDSIGHT_API_${decisionTab.toUpperCase()}_`),
                      );
                const essential = (field: Row) =>
                  /_(PROVIDER|MODEL|PRUNE|DEDUP)$|_USE_DECISION_MODEL$/.test(field.name);
                const groups = [
                  { advanced: false, fields: selected.filter(essential) },
                  { advanced: true, fields: selected.filter((field: Row) => !essential(field)) },
                ];
                return groups
                  .filter((group) => group.fields.length)
                  .map((group) => {
                    const content = (
                      <div className="form-stack">
                        {group.fields.map((field: Row) => (
                          <label key={field.name}>
                            {field.label}
                            {field.secret && <Badge>Secret</Badge>}
                            {/PROVIDER$/.test(field.name) ? (
                              <select
                                aria-label={field.label}
                                value={
                                  field.name === 'HINDSIGHT_API_DECISION_MODEL_PROVIDER'
                                    ? decisionProviderValue(role, fields)
                                    : (fields[field.name] ?? field.value ?? '')
                                }
                                onChange={(e) => {
                                  if (field.name === 'HINDSIGHT_API_DECISION_MODEL_PROVIDER') {
                                    const location =
                                      e.target.value === '__hindsight_local__'
                                        ? 'local'
                                        : e.target.value === 'hindsight'
                                          ? 'cloud'
                                          : null;
                                    if (e.target.value === '__hindsight_custom__') return;
                                    setDecisionLocation(location);
                                    if (location) {
                                      setFields((old) => {
                                        const next = chooseProvider(
                                          role,
                                          field,
                                          'hindsight',
                                          old,
                                          data,
                                        );
                                        next.HINDSIGHT_API_DECISION_MODEL_MODEL = '';
                                        next.HINDSIGHT_API_DECISION_MODEL_BASE_URL =
                                          location === 'local' ? localDecisionURL : '';
                                        delete next.HINDSIGHT_API_DECISION_MODEL_API_KEY;
                                        return next;
                                      });
                                      return;
                                    }
                                  }
                                  setCustomModels((old) => {
                                    const next = new Set(old);
                                    next.delete(field.name.replace(/PROVIDER$/, 'MODEL'));
                                    return next;
                                  });
                                  setFields((old) =>
                                    chooseProvider(role, field, e.target.value, old, data),
                                  );
                                }}
                              >
                                <option value="">
                                  {t('Hériter des réglages', 'Inherit settings')}
                                </option>
                                {field.name === 'HINDSIGHT_API_DECISION_MODEL_PROVIDER' && (
                                  <>
                                    <option value="__hindsight_local__">
                                      {t('Sur ce Mac · Hindsight', 'On this Mac · Hindsight')}
                                    </option>
                                    {decisionProviderValue(role, fields) ===
                                      '__hindsight_custom__' && (
                                      <option value="__hindsight_custom__">
                                        {t(
                                          'Hindsight · URL personnalisée',
                                          'Hindsight · custom endpoint',
                                        )}
                                      </option>
                                    )}
                                  </>
                                )}
                                {providerOptions(role, field, data).map((option) => (
                                  <option key={option.id} value={option.id}>
                                    {option.id === 'local'
                                      ? t('Local · sur ce Mac', 'Local · on this Mac')
                                      : option.id === 'hindsight' &&
                                          field.name === 'HINDSIGHT_API_DECISION_MODEL_PROVIDER'
                                        ? 'Hindsight Cloud'
                                        : option.title}
                                  </option>
                                ))}
                              </select>
                            ) : isBooleanField(field) ? (
                              <select
                                aria-label={field.label}
                                value={fields[field.name] ?? field.value ?? ''}
                                onChange={(e) =>
                                  setFields((old) => ({ ...old, [field.name]: e.target.value }))
                                }
                              >
                                <option value="">{t('Défaut du serveur', 'Server default')}</option>
                                <option value="true">{t('Activé', 'Enabled')}</option>
                                <option value="false">{t('Désactivé', 'Off')}</option>
                                {field.value && !['true', 'false'].includes(field.value) && (
                                  <option value={field.value}>{field.value}</option>
                                )}
                              </select>
                            ) : /MODEL$/.test(field.name) ? (
                              <>
                                <select
                                  aria-label={field.label}
                                  value={
                                    customModels.has(field.name)
                                      ? '__custom_model__'
                                      : (fields[field.name] ?? field.value ?? '')
                                  }
                                  onChange={(e) => {
                                    if (e.target.value === '__custom_model__')
                                      setCustomModels((old) => new Set(old).add(field.name));
                                    else {
                                      setCustomModels((old) => {
                                        const next = new Set(old);
                                        next.delete(field.name);
                                        return next;
                                      });
                                      setFields((old) => ({
                                        ...old,
                                        [field.name]: e.target.value,
                                      }));
                                    }
                                  }}
                                >
                                  <option value="">
                                    {t(
                                      'Hérité / défaut du fournisseur',
                                      'Inherited / provider default',
                                    )}
                                  </option>
                                  {modelOptions(role, field, fields, data).map((option) => (
                                    <option key={option.id} value={option.id}>
                                      {option.id === 'local'
                                        ? t('Local · sur ce Mac', 'Local · on this Mac')
                                        : option.title}
                                    </option>
                                  ))}
                                  <option value="__custom_model__">
                                    {t('Autre modèle…', 'Other model…')}
                                  </option>
                                </select>
                                {customModels.has(field.name) && (
                                  <input
                                    aria-label={`${field.label} · ${t('Nom personnalisé', 'Custom name')}`}
                                    value={fields[field.name] ?? field.value ?? ''}
                                    autoComplete="off"
                                    placeholder={t('Nom exact du modèle', 'Exact model name')}
                                    onChange={(e) =>
                                      setFields((old) => ({
                                        ...old,
                                        [field.name]: e.target.value,
                                      }))
                                    }
                                  />
                                )}
                              </>
                            ) : (
                              <input
                                aria-label={field.label}
                                type={field.secret ? 'password' : 'text'}
                                value={fields[field.name] ?? field.value ?? ''}
                                autoComplete="off"
                                placeholder={
                                  field.secret && field.configured
                                    ? t(
                                        'Secret configuré · laisser vide pour le conserver',
                                        'Secret configured · leave empty to keep it',
                                      )
                                    : t('Hérite du serveur', 'Inherits from server')
                                }
                                onChange={(e) => {
                                  setFields((old) => ({ ...old, [field.name]: e.target.value }));
                                }}
                              />
                            )}
                            {(field.help || field.dynamic) && (
                              <details className="field-explanation">
                                <summary>{t('À propos', 'About')}</summary>
                                <small>
                                  {field.help}
                                  {field.dynamic
                                    ? t(
                                        ' Valeur définie par l’environnement.',
                                        ' Value set by the environment.',
                                      )
                                    : ''}
                                </small>
                              </details>
                            )}
                          </label>
                        ))}
                      </div>
                    );
                    return group.advanced ? (
                      <details key="advanced" className="model-advanced">
                        <summary>{t('Options avancées', 'Advanced options')}</summary>
                        {content}
                      </details>
                    ) : (
                      <div key="essential">{content}</div>
                    );
                  });
              })()}
            </fieldset>
            <ErrorNotice message={roleError || (roleStale && !roleSaving ? staleMessage : '')} />
            <div className="modal-actions">
              <Button type="button" disabled={roleSaving} onClick={() => setRole(null)}>
                {' '}
                {t('Annuler', 'Cancel')}
              </Button>
              <Button
                kind="primary"
                disabled={busy || roleSaving || !!roleStale || !Object.keys(fields).length}
              >
                {' '}
                {t('Préparer ces changements', 'Prepare these changes')}
              </Button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}

/** Serveur qui refuse les réglages par banque (`bank_config_api`) : la page se lit, rien ne s’enregistre. */
function ReadOnlyConfigNotice() {
  const { t } = useI18n();
  return (
    <div className="notice">
      {t(
        'Ce serveur n’accepte pas les réglages par banque : cette page est en lecture seule. Pour les activer, ajoutez HINDSIGHT_API_ENABLE_BANK_CONFIG_API=true au script de lancement, puis redémarrez le serveur.',
        'This server does not accept per-bank settings, so this page is read-only. To enable them, add HINDSIGHT_API_ENABLE_BANK_CONFIG_API=true to the launch script, then restart the server.',
      )}
    </div>
  );
}

/** Effet prévu d’un gabarit (essai sans écriture), dit en une phrase plutôt qu’en JSON. */
function templateEffect(dry: Row) {
  const names = (value: unknown) => (Array.isArray(value) ? value.length : 0);
  const parts: string[] = [];
  if (dry.config_applied) parts.push(tr('la configuration de la banque', 'the bank configuration'));
  const created = names(dry.mental_models_created);
  const updated = names(dry.mental_models_updated);
  const directivesCreated = names(dry.directives_created);
  const directivesUpdated = names(dry.directives_updated);
  if (created)
    parts.push(
      tr(
        `${created} modèle${created > 1 ? 's' : ''} ${created > 1 ? 'mentaux créés' : 'mental créé'}`,
        `${created} mental model${created > 1 ? 's' : ''} created`,
      ),
    );
  if (updated)
    parts.push(
      tr(
        `${updated} modèle${updated > 1 ? 's' : ''} ${updated > 1 ? 'mentaux' : 'mental'} mis à jour`,
        `${updated} mental model${updated > 1 ? 's' : ''} updated`,
      ),
    );
  if (directivesCreated)
    parts.push(
      tr(
        `${directivesCreated} directive${directivesCreated > 1 ? 's créées' : ' créée'}`,
        `${directivesCreated} directive${directivesCreated > 1 ? 's' : ''} created`,
      ),
    );
  if (directivesUpdated)
    parts.push(
      tr(
        `${directivesUpdated} directive${directivesUpdated > 1 ? 's mises' : ' mise'} à jour`,
        `${directivesUpdated} directive${directivesUpdated > 1 ? 's' : ''} updated`,
      ),
    );
  return parts.length
    ? tr(
        `Ce gabarit modifiera : ${parts.join(', ')}.`,
        `This template will change: ${parts.join(', ')}.`,
      )
    : tr(
        'Ce gabarit ne change rien à cette banque.',
        'This template changes nothing in this memory bank.',
      );
}

/** Ce dans quoi la recherche puise, selon « Préférer les observations » : le choix en cours est mis en avant. */
function SearchPool({ pool, preferred }: { pool?: Row; preferred: boolean }) {
  const { t } = useI18n();
  if (!pool) return null;
  const facts = Number(pool.facts) || 0;
  const observations = Number(pool.observations) || 0;
  const pending = Number(pool.notYetConsolidated) || 0;
  const plural = (n: number, fr: [string, string], en: [string, string]) =>
    `${number(n)} ${t(n > 1 ? fr[1] : fr[0], n === 1 ? en[0] : en[1])}`;
  const factsLabel = (n: number) => plural(n, ['fait', 'faits'], ['fact', 'facts']);
  const observationsLabel = plural(
    observations,
    ['observation', 'observations'],
    ['observation', 'observations'],
  );
  const pendingLabel = plural(
    pending,
    ['fait pas encore consolidé', 'faits pas encore consolidés'],
    ['fact not yet consolidated', 'facts not yet consolidated'],
  );
  return (
    <div
      className="search-pool"
      aria-label={t('Ce dans quoi la recherche puise', 'What search draws from')}
    >
      <div className={preferred ? '' : 'is-current'}>
        <span>{t('Sans', 'Off')}</span>
        <strong>{number(facts + observations)}</strong>
        <small>
          {factsLabel(facts)} + {observationsLabel}
        </small>
      </div>
      <div className={preferred ? 'is-current' : ''}>
        <span>{t('Avec', 'On')}</span>
        <strong>{number(observations + pending)}</strong>
        <small>
          {observationsLabel} + {pendingLabel}
        </small>
      </div>
    </div>
  );
}
