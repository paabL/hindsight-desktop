import { useI18n } from '../i18n';
import { useEffect, useState } from 'react';
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
  RefreshCw,
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
  date,
  number,
} from '../ui';
import { saveExport } from '../transport';
import {
  chooseProvider,
  modelOptions,
  providerOptions,
  visibleRoleFields,
  isBooleanField,
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
  consolidationUseDecisionModel: 'consolidation_use_decision_model',
  reflectUseDecisionModel: 'reflect_use_decision_model',
  mentalModelRefreshUseDecisionModel: 'mental_model_refresh_use_decision_model',
  mentalModelDeltaUseDecisionModel: 'mental_model_delta_use_decision_model',
  recallDecisionModelPrune: 'recall_decision_model_prune',
  recallDecisionModelDedup: 'recall_decision_model_dedup',
} as const;

export function MemoryDesign({ data, run, busy, notify }: PageProps) {
  const { t } = useI18n();
  const [tab, setTab] = useState('retain');
  const [draft, setDraft] = useState<Row>({});
  const [sample, setSample] = useState('');
  const [advanced, setAdvanced] = useState('');
  useEffect(() => {
    if (data.draft) setDraft(data.draft);
  }, [data.draft]);
  const set = (key: string, value: unknown) => setDraft((old) => ({ ...old, [key]: value }));
  function config() {
    const changes: Row = {};
    for (const [key, value] of Object.entries(draft))
      if (key in memoryFields && value !== data.draft?.[key])
        changes[memoryFields[key as keyof typeof memoryFields]] = value;
    if (advanced.trim()) Object.assign(changes, JSON.parse(advanced));
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
  const textField = (key: string, title: string, placeholder: string) => (
    <label>
      {title}
      <textarea
        rows={4}
        value={draft[key] || ''}
        onChange={(e) => set(key, e.target.value)}
        placeholder={placeholder}
      />
    </label>
  );
  const toggle = (key: string, title: string, help: string) => (
    <label className="setting-toggle">
      <div>
        <strong>{title}</strong>
        <span>{help}</span>
      </div>
      <input
        type="checkbox"
        role="switch"
        checked={draft[key] ?? false}
        onChange={(e) => set(key, e.target.checked)}
      />
    </label>
  );
  return (
    <>
      <PageHeader
        eyebrow={t('Une mémoire à votre image', 'Memory that works for you')}
        title={t('Comportement de la mémoire', 'Memory behavior')}
        description={t(
          'Choisissez ce que la banque sélectionnée retient, comment elle consolide ses souvenirs et répond aux questions.',
          'Choose what the selected bank remembers, how it consolidates memories and answers questions.',
        )}
        actions={
          <Button kind="primary" icon={Save} disabled={busy} onClick={() => action('memory.save')}>
            {' '}
            {t('Enregistrer les changements', 'Save changes')}
          </Button>
        }
      />
      <ErrorNotice message={data.error} />
      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          { id: 'retain', label: 'Extraction' },
          { id: 'observations', label: 'Consolidation' },
          { id: 'reflect', label: t('Réponses', 'Answers') },
          { id: 'recall', label: t('Recherche', 'Search') },
          { id: 'advanced', label: t('Avancé', 'Advanced') },
        ]}
      />
      <section className="card settings-card">
        <div className="form-stack">
          {tab === 'retain' && (
            <>
              <h2>{t('Ce qui mérite d’être retenu', 'What is worth remembering')}</h2>
              <p className="muted">
                {' '}
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
              <label>
                {' '}
                {t('Style d’extraction', 'Extraction style')}
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
              <label>
                {' '}
                {t('Taille des segments en caractères', 'Chunk size in characters')}
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
            </>
          )}
          {tab === 'observations' && (
            <>
              <h2>{t('Relier et consolider les faits', 'Connect and consolidate facts')}</h2>
              {toggle(
                'enableObservations',
                t('Créer des observations', 'Create observations'),
                t(
                  'Des connaissances plus générales émergent des faits retenus.',
                  'Broader knowledge emerges from stored facts.',
                ),
              )}
              {toggle(
                'enableAutoConsolidation',
                t('Consolider automatiquement', 'Consolidate automatically'),
                t(
                  'Le serveur peut lancer de nouveaux traitements après les envois.',
                  'The server can start new processing after documents are sent.',
                ),
              )}
              {textField(
                'observationsMission',
                t('Mission de consolidation', 'Consolidation mission'),
                t(
                  'Les liens, les tendances ou les règles à faire émerger.',
                  'The connections, patterns, or rules to uncover.',
                ),
              )}
              <label>
                {' '}
                {t('Maximum d’observations par portée', 'Maximum observations per scope')}
                <input
                  type="number"
                  min="-1"
                  value={draft.maxObservationsPerScope ?? -1}
                  onChange={(e) => set('maxObservationsPerScope', Number(e.target.value))}
                />
                <small>
                  {' '}
                  {t(
                    '−1 laisse le serveur choisir sa limite.',
                    '−1 lets the server choose its limit.',
                  )}
                </small>
              </label>
              <label>
                {' '}
                {t('Portée par défaut', 'Default scope')}
                <select
                  value={draft.defaultObservationScopes || ''}
                  onChange={(e) => set('defaultObservationScopes', e.target.value)}
                >
                  <option value="">{t('Défaut du serveur', 'Server default')}</option>
                  <option value="shared">{t('Partagée', 'Shared')}</option>
                  <option value="combined">{t('Combinée', 'Combined')}</option>
                </select>
              </label>
              {toggle(
                'consolidationUseDecisionModel',
                t('Trier avec le modèle de décision', 'Filter with the decision model'),
                t(
                  'Les redites et le bavardage sont réglés sans appel LLM, si le serveur a un modèle de décision.',
                  'Repetition and chatter are handled without an LLM call if the server has a decision model.',
                ),
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
                  {label}
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
              {toggle(
                'reflectUseDecisionModel',
                t(
                  'Reflect : trier avec le modèle de décision',
                  'Reflect: filter with the decision model',
                ),
                t(
                  'Il élague les preuves et juge quand elles suffisent ; moins cher, un peu moins précis.',
                  'It trims evidence and decides when there is enough; lower cost, slightly lower accuracy.',
                ),
              )}
              {toggle(
                'mentalModelRefreshUseDecisionModel',
                t(
                  'Pages de connaissance : rafraîchir avec le modèle de décision',
                  'Knowledge pages: refresh with the decision model',
                ),
                t(
                  'Même tri que reflect pendant une régénération complète.',
                  'The same filtering as reflect during a full regeneration.',
                ),
              )}
              {toggle(
                'mentalModelDeltaUseDecisionModel',
                t(
                  'Pages de connaissance : ignorer les mémoires sans effet',
                  'Knowledge pages: skip memories that make no difference',
                ),
                t(
                  'Une mise à jour dont aucune nouvelle mémoire ne change la page ne fait aucun appel LLM.',
                  'An update makes no LLM call when no new memories change the page.',
                ),
              )}
            </>
          )}
          {tab === 'recall' && (
            <>
              <h2>{t('Les chemins vers le bon contexte', 'Paths to the right context')}</h2>
              {toggle(
                'enableTextSearch',
                t('Recherche textuelle', 'Text search'),
                t('Retrouver des faits par leurs mots.', 'Find facts by their words.'),
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
              {data.serverIs120 && (
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
                    {' '}
                    {t(
                      'Sans effet tant que le serveur n’a pas de modèle de décision pour recall.',
                      'Has no effect until the server has a decision model configured for recall.',
                    )}
                  </p>
                </>
              )}
            </>
          )}
          {tab === 'advanced' && (
            <>
              <h2>
                {' '}
                {t('Vocabulaire et stratégies avancées', 'Advanced vocabulary and strategies')}
              </h2>
              <p className="muted">
                {' '}
                {t(
                  'Saisissez les clés de configuration de la banque à modifier. Les valeurs non indiquées sont conservées.',
                  'Enter the bank configuration keys to change. Unspecified values are kept.',
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
              <Button kind="danger" icon={RefreshCw} onClick={() => void run('memory.reset')}>
                {' '}
                {t('Revenir aux réglages du serveur', 'Reset to server settings')}
              </Button>
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
            {' '}
            {t('Préparer un essai à blanc', 'Prepare a dry run')}
          </Button>
          <ErrorNotice message={data.trialError} />
          {data.trial && <pre className="json-view">{JSON.stringify(data.trial, null, 2)}</pre>}
        </div>
      </section>
      {data.problems?.map((problem: string) => (
        <ErrorNotice key={problem} message={problem} />
      ))}
    </>
  );
}

export function Admin({ data, run, busy, notify }: PageProps) {
  const { t } = useI18n();
  const [modal, setModal] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [content, setContent] = useState('');
  const [target, setTarget] = useState('');
  const [key, setKey] = useState('');
  const [value, setValue] = useState('');
  const [source, setSource] = useState('');
  const [syncScript, setSyncScript] = useState('');
  const [syncIds, setSyncIds] = useState('');
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
          <Button
            icon={Plus}
            kind="primary"
            onClick={() => {
              setModal('create');
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
      <section className="card settings-card">
        <CardHeader
          title={t('Identité de la banque', 'Bank identity')}
          subtitle={t(
            'Un nom clair pour retrouver le bon contexte.',
            'A clear name to find the right context.',
          )}
        />
        <div className="action-row">
          <Button
            icon={Database}
            onClick={() => {
              setName('');
              setModal('rename');
            }}
          >
            {' '}
            {t('Renommer', 'Rename')}
          </Button>
          <Button
            icon={Copy}
            onClick={() => {
              setTarget('');
              setModal('clone');
            }}
          >
            {' '}
            {t('Cloner', 'Clone')}
          </Button>
          <Button
            icon={Layers3}
            onClick={() => {
              setSource('');
              setTarget('');
              setModal('merge');
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
                setModal('directive');
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
            'Conservez une archive ou réutilisez la structure dans une autre banque.',
            'Keep an archive or reuse the structure in another bank.',
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
            <strong>{t('Exporter la structure', 'Export structure')}</strong>
            <span>{t('Modèle de configuration JSON', 'JSON configuration template')}</span>
          </button>
          <label className="file-upload">
            <Upload size={24} />
            <strong>{t('Importer une archive', 'Import archive')}</strong>
            <span>{t('Archive ZIP ou structure JSON', 'ZIP archive or JSON structure')}</span>
            <input
              type="file"
              accept=".zip,.json"
              onChange={(e) => void importFile(e.target.files?.[0])}
            />
          </label>
        </div>
        {data.templateDryRun && (
          <div className="form-stack">
            <pre className="json-view">{JSON.stringify(data.templateDryRun, null, 2)}</pre>
            <Button icon={Check} onClick={() => void run('admin.template.apply')}>
              {' '}
              {t('Appliquer ce modèle', 'Apply this template')}
            </Button>
          </div>
        )}
      </section>
      <details className="card advanced-details">
        <summary>{t('Synchronisation du dossier commun', 'Shared folder sync')}</summary>
        <div className="form-stack">
          <p className="muted">
            {' '}
            {t(
              'Prépare un aperçu avec le script de synchronisation du projet, puis présente le volume et le coût avant l’envoi.',
              "Prepares a preview using the project's sync script, then shows the volume and cost before sending.",
            )}
          </p>
          <label>
            {' '}
            {t('Script de synchronisation', 'Sync script')}
            <input
              value={syncScript || data.syncScript || ''}
              onChange={(e) => setSyncScript(e.target.value)}
              placeholder={t('/chemin/du/projet/sync.py', '/path/to/project/sync.py')}
            />
          </label>
          <label>
            {' '}
            {t(
              'Identifiants à inclure (facultatif, un par ligne)',
              'IDs to include (optional, one per line)',
            )}
            <textarea
              value={syncIds}
              onChange={(e) => setSyncIds(e.target.value)}
              placeholder={t(
                'Laisser vide pour examiner tous les candidats',
                'Leave empty to review all candidates',
              )}
            />
          </label>
          <Button
            disabled={busy || !(syncScript || data.syncScript)}
            onClick={() =>
              void run('sync.script', { path: syncScript || data.syncScript }).then(() =>
                run('sync.run', {
                  ids: syncIds
                    .split('\n')
                    .map((id) => id.trim())
                    .filter(Boolean),
                }),
              )
            }
          >
            {' '}
            {t('Préparer la synchronisation', 'Prepare sync')}
          </Button>
        </div>
      </details>
      <details className="card advanced-details">
        <summary> {t('Configuration avancée de la banque', 'Advanced bank configuration')}</summary>
        <div className="form-stack">
          <pre className="json-view">{JSON.stringify(data.config?.overrides || {}, null, 2)}</pre>
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
          <Button
            icon={Save}
            disabled={busy || !key.trim()}
            onClick={() => void run('admin.override', { key, value })}
          >
            {' '}
            {t('Préparer la modification', 'Prepare change')}
          </Button>
          <Button kind="ghost" onClick={() => void run('admin.reset')}>
            {' '}
            {t('Réinitialiser les surcharges', 'Reset overrides')}
          </Button>
        </div>
      </details>
      <details className="card danger-zone">
        <summary>{t('Actions de suppression', 'Delete actions')}</summary>
        <p>
          {' '}
          {t(
            'Ces actions retirent des connaissances. Une confirmation séparée précisera ce qui sera supprimé.',
            'These actions remove knowledge. A separate confirmation will explain what will be deleted.',
          )}
        </p>
        <div className="action-row">
          <Button kind="danger" onClick={() => void run('admin.clearObservations')}>
            {' '}
            {t('Effacer les observations', 'Clear observations')}
          </Button>
          <Button kind="danger" onClick={() => void run('admin.deleteMemories')}>
            {' '}
            {t('Effacer tous les faits', 'Clear all facts')}
          </Button>
          <Button kind="danger" icon={Trash2} onClick={() => void run('admin.deleteBank')}>
            {' '}
            {t('Supprimer la banque', 'Delete bank')}
          </Button>
        </div>
      </details>
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
          onClose={() => setModal(null)}
        >
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
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
              }).then(() => setModal(null));
            }}
          >
            {['create', 'rename', 'directive'].includes(modal) && (
              <label>
                {' '}
                {t('Nom', 'Name')}
                <input required value={name} onChange={(e) => setName(e.target.value)} />
              </label>
            )}
            {['create', 'clone', 'merge'].includes(modal) && (
              <label>
                {modal === 'merge'
                  ? t('Identifiant de la banque de destination', 'Destination bank ID')
                  : t('Identifiant de la nouvelle banque', 'New bank ID')}
                <input
                  required
                  pattern="[A-Za-z0-9][A-Za-z0-9._-]*"
                  value={target}
                  onChange={(e) => setTarget(e.target.value)}
                  placeholder={t('mon-projet', 'my-project')}
                />
              </label>
            )}
            {modal === 'merge' && (
              <label>
                {' '}
                {t('Identifiant de la banque source', 'Source bank ID')}
                <input required value={source} onChange={(e) => setSource(e.target.value)} />
              </label>
            )}
            {['create', 'directive'].includes(modal) && (
              <label>
                {modal === 'create'
                  ? t('Mission (facultative)', 'Mission (optional)')
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
              <Button type="button" onClick={() => setModal(null)}>
                {' '}
                {t('Annuler', 'Cancel')}
              </Button>
              <Button kind="primary" disabled={busy}>
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
                'Tranche les choix de la consolidation, de reflect et des pages de connaissance sans appel LLM : moins de jetons et moins d’attente.',
                'Makes consolidation, reflect, and knowledge page decisions without LLM calls: fewer tokens and less waiting.',
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
            'The decision model on this Mac is stopped: start it before the server.',
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
          {running
            ? t('En marche', 'Running')
            : local.installed
              ? t('Arrêté', 'Stopped')
              : t('Non installé', 'Not installed')}
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

export function ServerSettings({ data, run, busy, notify, navigate }: PageProps) {
  const { t } = useI18n();
  const [scriptPath, setScriptPath] = useState('');
  const [role, setRole] = useState<Row | null>(null);
  const [fields, setFields] = useState<Row>({});
  const [customModels, setCustomModels] = useState<Set<string>>(new Set());
  const [modelToolsOpen, setModelToolsOpen] = useState(false);
  const service = data.service || {};
  const serviceBusy = busy || service.busy;
  const [decisionTab, setDecisionTab] = useState('general');
  const [decisionLocation, setDecisionLocation] = useState<string | null>(null);
  useEffect(() => {
    setDecisionTab('general');
    setDecisionLocation(null);
  }, [role?.id]);
  async function saveRole() {
    if (role?.id === 'decision' && decisionLocation) {
      const result = await run('server.decision', { source: decisionLocation });
      if (result?.error) return;
    }
    // Changing provider can reset the model: apply explicit model choices afterwards.
    for (const [name, value] of Object.entries(fields))
      if (
        role?.isModelRole &&
        name === role.fields.find((field: Row) => field.name.endsWith('_PROVIDER'))?.name
      )
        await run('server.provider', { role: role?.id, provider: value });
    for (const [name, value] of Object.entries(fields)) {
      if (
        role?.id === 'decision' &&
        decisionLocation &&
        [
          'HINDSIGHT_API_DECISION_MODEL_PROVIDER',
          'HINDSIGHT_API_DECISION_MODEL_BASE_URL',
          'HINDSIGHT_API_DECISION_MODEL_API_KEY',
        ].includes(name)
      )
        continue;
      if (
        role?.isModelRole &&
        name === role.fields.find((field: Row) => field.name.endsWith('_PROVIDER'))?.name
      )
        continue;
      if (!(value === '' && role?.fields.some((field: Row) => field.name === name && field.secret)))
        await run('server.field', { name, value });
    }
    setRole(null);
  }
  return (
    <>
      <PageHeader
        eyebrow={t('Le moteur de votre mémoire', 'The engine behind your memory')}
        title={t('Serveur & modèles', 'Server & models')}
        description={t(
          'Gérez les fournisseurs, les modèles installés et la connexion au serveur.',
          'Manage providers, installed models and the server connection.',
        )}
        actions={
          <Button icon={Sparkles} onClick={() => navigate('model-settings')}>
            {t('Choix rapide des modèles', 'Quick model selection')}
          </Button>
        }
      />
      <section className="card service-card">
        <div className="service-identity">
          <span className="service-symbol">
            <Server size={26} strokeWidth={1.5} />
          </span>
          <div>
            <h2>{t('Service Hindsight', 'Hindsight service')}</h2>
            <p>
              {service.busy
                ? t('Démarrage ou arrêt en cours…', 'Starting or stopping…')
                : service.error
                  ? t('Le démarrage a échoué', 'Startup failed')
                  : service.running
                    ? t('Le serveur fonctionne sur ce Mac', 'The server is running on this Mac')
                    : service.reachable
                      ? t('Le serveur est accessible', 'The server is reachable')
                      : service.installed
                        ? t(
                            'Le service est installé et arrêté',
                            'The service is installed and stopped',
                          )
                        : t('Le service n’est pas installé', 'The service is not installed')}
            </p>
          </div>
          <Badge tone={service.error ? 'rose' : service.reachable ? 'sage' : 'amber'}>
            <span
              className={`status-dot ${service.error ? 'red' : service.reachable ? 'green' : 'warning'}`}
            />
            {service.busy
              ? t('En cours…', 'Working…')
              : service.error
                ? t('Échec', 'Failed')
                : service.reachable
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
                icon={RefreshCw}
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
        {service.frozen && (
          <div className="notice">
            {' '}
            {t(
              'Le traitement de la file est gelé. L’API reste accessible.',
              'Queue processing is frozen. The API remains available.',
            )}
          </div>
        )}
        <ErrorNotice message={service.scriptWarning} />
      </section>
      <ErrorNotice message={data.error} />
      {(data.configurationProblems || []).map((problem: string) => (
        <ErrorNotice key={problem} message={problem} />
      ))}
      {data.needsRestart && (
        <div className="notice">
          {' '}
          {t(
            'Des réglages ont été enregistrés. Redémarrez le serveur pour les appliquer.',
            'Settings were saved. Restart the server to apply them.',
          )}
        </div>
      )}
      <section className="card account-card">
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
      {data.hindsightModels && (
        <details
          className="advanced-details"
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
      <details className="card advanced-details" open>
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
          </div>
          <Button disabled={busy} icon={FlaskConical} onClick={() => void run('diagnostic.llm')}>
            {' '}
            {t('Tester les modèles', 'Test models')}
          </Button>
        </div>
        <div className="server-roles">
          {(data.roles || []).map((item: Row) => (
            <button
              key={item.id}
              className="card role-card"
              onClick={() => {
                setRole(item);
                setFields({});
                setCustomModels(new Set());
              }}
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
      {data.hasChanges && (
        <section className="card settings-card">
          <CardHeader
            title={t('Modifications préparées', 'Prepared changes')}
            subtitle={t(
              'Vérifiez les changements avant d’enregistrer le script.',
              'Review changes before saving the script.',
            )}
          />
          <pre className="json-view">
            {(data.diff || [])
              .map(
                (line: Row) =>
                  `${line.kind === 'added' ? '+ ' : line.kind === 'removed' ? '− ' : '  '}${line.text || line.line || ''}`,
              )
              .join('\n')}
          </pre>
          <div className="action-row">
            <Button
              kind="primary"
              icon={Save}
              disabled={busy}
              onClick={() => void run('server.save')}
            >
              {' '}
              {t('Vérifier et enregistrer', 'Review and save')}
            </Button>
            <Button onClick={() => void run('server.revert')}>
              {' '}
              {t('Abandonner le brouillon', 'Discard draft')}
            </Button>
          </div>
        </section>
      )}
      {data.diagnostic && (
        <details className="card advanced-details">
          <summary>{t('Résultat du test des modèles', 'Model test result')}</summary>
          <pre className="json-view">{JSON.stringify(data.diagnostic, null, 2)}</pre>
        </details>
      )}
      <ErrorNotice message={data.diagnosticError} />
      {data.warnings?.map((warning: string) => (
        <div className="notice" key={warning}>
          {warning}
        </div>
      ))}
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
      {role && (
        <Modal
          title={role.id === 'decision' ? t('Modèle de décision', 'Decision model') : role.title}
          onClose={() => {
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
                  { id: 'reflect', label: t('Réponse', 'Answer') },
                  { id: 'consolidation', label: t('Consolidation', 'Consolidation') },
                  { id: 'pages', label: t('Pages', 'Pages') },
                ]}
              />
            )}
            <div className="model-editor-fields">
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
                                  field.name === 'HINDSIGHT_API_DECISION_MODEL_PROVIDER' &&
                                  (fields[field.name] ?? field.value) === 'hindsight' &&
                                  (decisionLocation === 'local' ||
                                    (!decisionLocation &&
                                      (fields.HINDSIGHT_API_DECISION_MODEL_BASE_URL ??
                                        role.fields.find(
                                          (f: Row) =>
                                            f.name === 'HINDSIGHT_API_DECISION_MODEL_BASE_URL',
                                        )?.value) === 'http://127.0.0.1:8766'))
                                    ? '__hindsight_local__'
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
                                    setDecisionLocation(location);
                                    if (location) {
                                      setFields((old) =>
                                        chooseProvider(role, field, 'hindsight', old, data),
                                      );
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
                                  <option value="__hindsight_local__">
                                    {t('Sur ce Mac · Hindsight', 'On this Mac · Hindsight')}
                                  </option>
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
                                <option value="false">{t('Désactivé', 'Disabled')}</option>
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
                                      setFields((old) => ({ ...old, [field.name]: e.target.value }))
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
                                  if (field.name === 'HINDSIGHT_API_DECISION_MODEL_BASE_URL')
                                    setDecisionLocation(null);
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
            </div>
            <div className="modal-actions">
              <Button type="button" onClick={() => setRole(null)}>
                {' '}
                {t('Annuler', 'Cancel')}
              </Button>
              <Button kind="primary" disabled={busy || !Object.keys(fields).length}>
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

export function Hermes({ data, run, busy }: PageProps) {
  const { t } = useI18n();
  const [selection, setSelection] = useState<Set<string>>(new Set());
  const [preview, setPreview] = useState<Row | null>(null);
  return (
    <>
      <PageHeader
        eyebrow={t('Import de conversations', 'Conversation import')}
        title={t('Imports', 'Imports')}
        description={t(
          'Prévisualisez les conversations Hermes de ce Mac avant de préparer leur envoi à la banque sélectionnée.',
          'Preview this Mac’s Hermes conversations before preparing an upload to the selected bank.',
        )}
        actions={
          <Button
            icon={Upload}
            disabled={busy || !data.plan}
            onClick={() => void run('hermes.import')}
          >
            {' '}
            {t('Importer le plan préparé', 'Import prepared plan')}
          </Button>
        }
      />
      <div className="notice">
        <BookOpen size={17} />{' '}
        {t(
          'Les conversations Codex et Claude Code passent par Agent Dump et le catalogue de sources. Cet import direct concerne Hermes.',
          'Codex and Claude Code conversations go through Agent Dump and the source catalog. This direct import is for Hermes.',
        )}
      </div>
      <ErrorNotice message={data.error} />
      <section className="card">
        <CardHeader
          title={t('Conversations Hermes disponibles', 'Available Hermes conversations')}
          action={
            <Button
              icon={Check}
              disabled={busy || !selection.size}
              onClick={() => void run('hermes.plan', { ids: [...selection] })}
            >
              {' '}
              {t('Préparer l’import (', 'Prepare import (')}
              {selection.size})
            </Button>
          }
        />
        {data.items?.length ? (
          data.items.map((item: Row) => (
            <div className="hermes-row" key={item.id}>
              <input
                type="checkbox"
                aria-label={`${t('Sélectionner', 'Select')} ${item.title || item.id}`}
                checked={selection.has(item.id)}
                onChange={() =>
                  setSelection((old) => {
                    const next = new Set(old);
                    if (next.has(item.id)) next.delete(item.id);
                    else next.add(item.id);
                    return next;
                  })
                }
              />
              <div>
                <strong>{item.title || item.firstUserMessage || item.id}</strong>
                <p>{date(item.sortDate || item.updatedAt, true)}</p>
              </div>
              <Button
                onClick={() =>
                  void run('hermes.preview', { id: item.id }).then((result: Row) =>
                    setPreview(result.data?.preview),
                  )
                }
              >
                {' '}
                {t('Prévisualiser', 'Preview')}
              </Button>
            </div>
          ))
        ) : (
          <Empty
            icon={BookOpen}
            title={t('Aucune session Hermes', 'No Hermes sessions')}
            description={t(
              'L’import lit la base locale Hermes lorsqu’elle est disponible sur ce Mac.',
              'Import reads the local Hermes database when available on this Mac.',
            )}
          />
        )}
      </section>
      {data.plan && (
        <section className="card settings-card">
          <CardHeader
            title={t('Plan d’import', 'Import plan')}
            subtitle={t(
              'Relisez le volume et les éléments choisis avant l’envoi.',
              'Review the volume and selected items before sending.',
            )}
          />
          <pre className="json-view">{JSON.stringify(data.plan, null, 2)}</pre>
        </section>
      )}
      {data.sendErrors?.map((e: string) => (
        <ErrorNotice key={e} message={e} />
      ))}
      {preview && (
        <Modal
          title={t('Prévisualisation de la conversation', 'Conversation preview')}
          onClose={() => setPreview(null)}
          wide
        >
          <pre className="json-view">{JSON.stringify(preview, null, 2)}</pre>
        </Modal>
      )}
    </>
  );
}
