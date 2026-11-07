import { getLocale, useI18n } from '../i18n';
import { useEffect, useState } from 'react';
import {
  ArrowDownToLine,
  ArrowRight,
  BookOpen,
  Check,
  CircleHelp,
  Clock3,
  FileText,
  FolderPlus,
  Layers3,
  Plus,
  RotateCcw,
  Search,
  Sparkles,
  Tag,
  Trash2,
  WandSparkles,
} from 'lucide-react';
import type { PageProps, Request, Row } from '../types';
import {
  Badge,
  Button,
  CardHeader,
  Empty,
  ErrorNotice,
  IconButton,
  Loading,
  Markdown,
  Modal,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { nativeSystemMessage } from '../native-messages';
import { factTypeLabel, factTypePluralLabel } from '../fact-types';
import DocumentContent from './DocumentContent';

export function DocumentReader({
  reader,
  run,
  onClose,
  busy,
}: {
  reader: Row;
  run: Request;
  onClose: () => void;
  busy: boolean;
}) {
  const { t } = useI18n();
  const [tab, setTab] = useState('text');
  const [tags, setTags] = useState<string>((reader.document?.tags || []).join(', '));
  const document = reader.document || {};
  const [find, setFind] = useState('');
  const [deleting, setDeleting] = useState(false);
  const facts: Row[] = reader.facts || [];
  const factsTotal = Math.max(Number(reader.factsTotal) || 0, facts.length);
  // Une suppression confirmée ferme le lecteur côté moteur : la fenêtre se ferme avec lui.
  useEffect(() => {
    if (!deleting || busy) return;
    let current = true;
    void run('document.status', { id: document.id, polling: true }).then((status) => {
      if (!current || typeof status?.open !== 'boolean') return;
      if (!status.open) onClose();
      else if (!status.confirming) setDeleting(false);
    });
    return () => {
      current = false;
    };
  }, [deleting, busy]);
  return (
    <Modal
      title={document.document_metadata?.title || document.id || 'Document'}
      subtitle={t(
        'Document en mémoire · provenance conservée',
        'Stored document · source preserved',
      )}
      onClose={() => {
        void run('document.close');
        onClose();
      }}
      wide
    >
      <div className="reader-meta">
        <Badge tone="sage">{t('En mémoire', 'In memory')}</Badge>
        <span>{date(document.updated_at || document.created_at, true)}</span>
        <span>
          {number(facts.length)}
          {factsTotal > facts.length ? ` ${t('sur', 'of')} ${number(factsTotal)}` : ''}{' '}
          {t('faits affichés', 'facts shown')}
        </span>
      </div>
      <ErrorNotice message={reader.error && nativeSystemMessage(reader.error)} />
      {reader.note && <div className="notice">{nativeSystemMessage(reader.note)}</div>}
      <Tabs
        value={tab}
        onChange={setTab}
        items={[
          { id: 'text', label: 'Document' },
          { id: 'facts', label: t('Faits', 'Facts'), count: factsTotal },
          { id: 'history', label: t('Historique', 'History') },
          { id: 'manage', label: t('Gérer', 'Manage') },
        ]}
      />
      {tab === 'text' && (
        <div className="reader-find input-with-icon">
          <Search size={15} />
          <input
            value={find}
            onChange={(e) => setFind(e.target.value)}
            placeholder={t('Rechercher dans le document…', 'Search this document…')}
            aria-label={t('Rechercher dans le document', 'Search this document')}
          />
        </div>
      )}
      {tab === 'text' &&
        (reader.text ? (
          <DocumentContent reader={reader} run={run} find={find} />
        ) : (
          !reader.error && (
            <Empty
              title={t('Texte non conservé', 'Text not stored')}
              description={t(
                'Cette banque ne contient que les faits extraits du document.',
                'This bank only contains facts extracted from the document.',
              )}
            />
          )
        ))}
      {tab === 'facts' && (
        <>
          <ErrorNotice message={reader.factsError && nativeSystemMessage(reader.factsError)} />
          {facts.length ? (
            <div className="fact-list">
              {facts.map((fact: Row) => (
                <article className="fact-card" key={fact.id}>
                  <Badge>{factTypeLabel(fact.fact_type)}</Badge>
                  <p>{fact.text}</p>
                </article>
              ))}
            </div>
          ) : (
            !reader.factsError &&
            !reader.error && (
              <Empty
                title={t('Aucun fait extrait', 'No extracted facts')}
                description={t(
                  'Aucun fait de la mémoire ne provient de ce document.',
                  'No fact in memory comes from this document.',
                )}
              />
            )
          )}
        </>
      )}
      {tab === 'history' &&
        (reader.history?.length ? (
          <div className="activity-list">
            {reader.history.map((event: Row, i: number) => (
              <div key={event.id || i}>
                <Clock3 size={16} />
                <div>
                  <strong>
                    {event.event_type || event.type || event.action || t('Événement', 'Event')}
                  </strong>
                  <p>{date(event.created_at || event.timestamp, true)}</p>
                  <pre>{JSON.stringify(event, null, 2)}</pre>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <Empty
            icon={Clock3}
            title={t('Aucun historique disponible', 'No history available')}
            description={t(
              'L’historique nécessite un serveur compatible et des événements enregistrés.',
              'History requires a compatible server and recorded events.',
            )}
          />
        ))}
      {tab === 'manage' && (
        <div className="form-stack">
          <label>
            {' '}
            {t('Étiquettes', 'Tags')}
            <input
              value={tags}
              onChange={(e) => setTags(e.target.value)}
              placeholder={t('projet:horizon, architecture', 'project:horizon, architecture')}
            />
          </label>
          <Button
            icon={Tag}
            disabled={busy}
            onClick={() =>
              void run('document.tags', {
                id: document.id,
                tags: tags
                  .split(',')
                  .map((t) => t.trim())
                  .filter(Boolean),
              })
            }
          >
            {' '}
            {t('Enregistrer les étiquettes', 'Save tags')}
          </Button>
          <label>
            {' '}
            {t('Portée de consolidation', 'Consolidation scope')}
            <select
              defaultValue=""
              onChange={(e) => {
                if (e.target.value)
                  void run('document.scope', { id: document.id, scope: e.target.value });
              }}
            >
              <option value="">{t('Choisir une portée…', 'Choose a scope…')}</option>
              <option value="shared">{t('Partagée', 'Shared')}</option>
              <option value="combined">{t('Combinée', 'Combined')}</option>
              <option value="per_tag">{t('Par étiquette', 'Per tag')}</option>
            </select>
          </label>
          <div className="action-row">
            <Button
              icon={RotateCcw}
              disabled={busy}
              title={t(
                'Relance l’extraction des faits de ce document (appels LLM).',
                'Runs fact extraction again for this document (LLM calls).',
              )}
              onClick={() => void run('document.reprocess', { id: document.id })}
            >
              {' '}
              {t('Retraiter le document', 'Reprocess document')}
            </Button>
            <Button
              icon={Trash2}
              kind="danger"
              disabled={busy}
              onClick={() => {
                setDeleting(true);
                void run('document.delete', { id: document.id });
              }}
            >
              {' '}
              {t('Supprimer', 'Delete')}
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
}

export function Models({ data, run, busy, notify }: PageProps) {
  const { t } = useI18n();
  const [query, setQuery] = useState('');
  const [model, setModel] = useState<Row | null>(null);
  const [create, setCreate] = useState(false);
  const [name, setName] = useState('');
  const [question, setQuestion] = useState('');
  const allModels: Row[] | undefined = Array.isArray(data.models) ? data.models : undefined;
  const models: Row[] = (allModels || []).filter((m: Row) =>
    `${m.name} ${m.source_query}`.toLocaleLowerCase('fr').includes(query.toLocaleLowerCase('fr')),
  );
  const modelError = data.modelError ? nativeSystemMessage(data.modelError) : null;
  // Après une suppression confirmée, la liste rechargée ne contient plus l’élément ouvert.
  useEffect(() => {
    if (model && allModels && !modelError && !allModels.some((m) => m.id === model.id))
      setModel(null);
  }, [allModels, model, modelError]);
  async function open(id: string) {
    const result = await run('model.open', { id });
    if (result?.error) throw new Error(nativeSystemMessage(result.error));
    setModel(result.model);
  }
  const refreshFailed = (m: Row) =>
    !!m.last_refresh_failed_at &&
    (!m.last_refreshed_at ||
      Date.parse(m.last_refresh_failed_at) > Date.parse(m.last_refreshed_at));
  return (
    <>
      <PageHeader
        eyebrow={t('Le savoir qui se construit', 'Knowledge that grows')}
        title={t('Connaissances', 'Knowledge')}
        description={t(
          'Pages de connaissance et modèles mentaux construits à partir des faits de la banque sélectionnée.',
          'Knowledge pages and mental models built from the selected bank’s facts.',
        )}
        actions={
          <Button kind="primary" icon={Plus} onClick={() => setCreate(true)}>
            {' '}
            {t('Nouveau modèle mental', 'New mental model')}
          </Button>
        }
      />
      <div className="section-callout">
        <span className="callout-icon">
          <BookOpen size={21} />
        </span>
        <div>
          <strong>
            {t('Pages de connaissance et modèles mentaux', 'Knowledge pages and mental models')}
          </strong>
          <p>
            {' '}
            {t(
              'Chacune rassemble ce que votre banque sait d’un sujet, à partir des faits mémorisés.',
              'Each one brings together what your bank knows about a topic, using its stored facts.',
            )}
          </p>
        </div>
        <Badge>
          {query.trim() && allModels && models.length !== allModels.length
            ? `${number(models.length)} ${t('sur', 'of')} `
            : ''}
          {number(allModels?.length || 0)} {t('éléments', 'items')}
        </Badge>
      </div>
      <div className="standalone-search input-with-icon">
        <Search size={17} />
        <input
          aria-label={t('Filtrer les connaissances', 'Filter knowledge')}
          placeholder={t('Retrouver une connaissance…', 'Find knowledge…')}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
      </div>
      <ErrorNotice message={modelError} />
      {!allModels && !modelError ? (
        <Loading />
      ) : models.length ? (
        <div className="model-grid">
          {models.map((m, i) => (
            <button
              key={m.id}
              className="model-card"
              onClick={() =>
                void open(m.id).catch((error: unknown) =>
                  notify(
                    error instanceof Error && error.message
                      ? error.message
                      : t('Impossible d’ouvrir cet élément.', 'This item could not be opened.'),
                  ),
                )
              }
            >
              <div className="model-card-top">
                <span className={`model-glyph color-${i % 4}`}>
                  <BookOpen size={23} strokeWidth={1.5} />
                </span>
                <Badge tone={refreshFailed(m) ? 'red' : m.is_stale ? 'amber' : 'sage'}>
                  {refreshFailed(m)
                    ? t('Échec de la génération', 'Generation failed')
                    : m.is_stale
                      ? t('À régénérer', 'Needs regenerating')
                      : m.last_refreshed_at
                        ? t('À jour', 'Up to date')
                        : t('Jamais générée', 'Never generated')}
                </Badge>
              </div>
              <h2>{m.name}</h2>
              <p>
                {m.source_query ||
                  t('Construite à partir des faits de la banque.', "Built from the bank's facts.")}
              </p>
              <div className="model-card-bottom">
                <span>
                  <Clock3 size={13} />
                  {date(m.last_refreshed_at || m.created_at)}
                </span>
                <ArrowRight size={17} />
              </div>
            </button>
          ))}
        </div>
      ) : modelError ? null : (
        <Empty
          icon={BookOpen}
          title={
            query
              ? t('Aucune connaissance ne correspond', 'No matching knowledge')
              : t('Faites émerger le savoir', 'Bring knowledge together')
          }
          description={t(
            'Posez une question durable, comme les décisions d’architecture ou les priorités d’un projet.',
            'Ask a lasting question, such as architecture decisions or project priorities.',
          )}
          action={
            <Button icon={Plus} onClick={() => setCreate(true)}>
              {' '}
              {t('Créer un modèle mental', 'Create a mental model')}
            </Button>
          }
        />
      )}
      {model && (
        <Modal title={model.name} subtitle={model.source_query} wide onClose={() => setModel(null)}>
          <div className="reader-meta">
            <Badge>
              {model.is_knowledge_page
                ? t('Page de connaissance', 'Knowledge page')
                : t('Modèle mental', 'Mental model')}
            </Badge>
            <span>
              {model.last_refreshed_at
                ? `${t('Générée le', 'Generated on')} ${date(model.last_refreshed_at, true)}`
                : t('Jamais générée', 'Never generated')}
            </span>
            {refreshFailed(model) && (
              <Badge tone="red">
                {t('Échec de la dernière génération', 'Last generation failed')}
              </Badge>
            )}
            <div className="spacer" />
            <Button
              icon={WandSparkles}
              disabled={busy}
              title={t(
                'Fait réécrire cette connaissance par le LLM à partir des faits actuels (appel LLM).',
                'Has the LLM rewrite this knowledge item from the current facts (LLM call).',
              )}
              onClick={() => void run('model.refresh', { id: model.id })}
            >
              {' '}
              {t('Régénérer', 'Regenerate')}
            </Button>
            <IconButton
              icon={Trash2}
              label={t('Supprimer cette connaissance', 'Delete this knowledge item')}
              disabled={busy}
              onClick={() => void run('model.delete', { id: model.id })}
            />
          </div>
          {model.content ? (
            <Markdown text={model.content} />
          ) : (
            <Empty
              icon={Sparkles}
              title={t(
                'Ce contenu attend sa première génération',
                'This content has not been generated yet',
              )}
              description={t(
                'Utilisez « Régénérer » pour produire son contenu à partir de la mémoire.',
                'Use “Regenerate” to produce its content from memory.',
              )}
            />
          )}
        </Modal>
      )}
      {create && (
        <Modal
          title={t('Un nouveau modèle mental', 'A new mental model')}
          subtitle={t(
            'Une question durable pour relier vos connaissances.',
            'A lasting question to connect your knowledge.',
          )}
          onClose={() => setCreate(false)}
        >
          <form
            className="form-stack"
            onSubmit={(e) => {
              e.preventDefault();
              void run('model.create', { name, query: question }).then(() => setCreate(false));
            }}
          >
            <label>
              {' '}
              {t('Nom du modèle mental', 'Mental model name')}
              <input
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={t('Les décisions d’architecture', 'Architecture decisions')}
              />
            </label>
            <label>
              {' '}
              {t('La question à explorer', 'The question to explore')}
              <textarea
                required
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                placeholder={t(
                  'Quelles décisions structurent le projet, et pourquoi ?',
                  'Which decisions shape the project, and why?',
                )}
                rows={4}
              />
            </label>
            <p className="form-hint">
              {' '}
              {t(
                'La génération utilise le modèle de la banque. L’estimation sera présentée avant confirmation.',
                "Generation uses the bank's model. An estimate will be shown before you confirm.",
              )}
            </p>
            <div className="modal-actions">
              <Button onClick={() => setCreate(false)} type="button">
                {' '}
                {t('Annuler', 'Cancel')}
              </Button>
              <Button
                kind="primary"
                icon={Sparkles}
                disabled={!name.trim() || !question.trim() || busy}
              >
                {' '}
                {t('Créer le modèle mental', 'Create mental model')}
              </Button>
            </div>
          </form>
        </Modal>
      )}
    </>
  );
}

export function SearchPage({ data, run, busy, notify }: PageProps) {
  const { t } = useI18n();
  const [mode, setMode] = useState('recall');
  const [query, setQuery] = useState('');
  const [tags, setTags] = useState('');
  const [budget, setBudget] = useState('mid');
  const [prune, setPrune] = useState('');
  const [dedup, setDedup] = useState('');
  const [filters, setFilters] = useState(false);
  const [type, setType] = useState('');
  const [entity, setEntity] = useState('');
  const [task, setTask] = useState('');
  const [start, setStart] = useState('');
  const [end, setEnd] = useState('');
  const [searched, setSearched] = useState(false);
  const [reader, setReader] = useState<Row | null>(null);
  const suggestions = [
    t('Les dernières décisions', 'Recent decisions'),
    t('Les problèmes déjà résolus', 'Problems already solved'),
    t('Les prochaines étapes', 'Next steps'),
  ];
  const hits: Row[] = data.hits || [];
  // Réponses (reflect) n’applique ni l’entité ni la période : ces filtres sont masqués.
  const reflect = mode === 'reflect';
  async function search(text = query) {
    setQuery(text);
    setSearched(true);
    await run('search', {
      query: text,
      mode,
      budget,
      prune: prune === '' ? null : prune === 'true',
      dedup: dedup === '' ? null : dedup === 'true',
      tags: tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean),
      types: type ? [type] : [],
      entity: reflect ? '' : entity,
      task,
      start: !reflect && start ? new Date(start + 'T00:00:00').toISOString() : null,
      end:
        !reflect && end
          ? new Date(new Date(end + 'T00:00:00').getTime() + 86400000).toISOString()
          : null,
    });
  }
  return (
    <>
      <PageHeader
        eyebrow={t('Retrouvez le fil', 'Pick up the thread')}
        title={t('Recherche', 'Search')}
        description={t(
          'Recherche sémantique, texte exact ou réponse générée à partir des faits.',
          'Semantic search, exact text, or an answer generated from facts.',
        )}
      />
      <div className="search-workspace card">
        <Tabs
          value={mode}
          onChange={setMode}
          items={[
            { id: 'recall', label: t('Recherche par le sens', 'Search by meaning') },
            { id: 'text', label: t('Texte exact', 'Exact text') },
            { id: 'reflect', label: t('Réponses', 'Answers') },
          ]}
        />
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void search();
          }}
        >
          <div className="search-large">
            <Search size={24} strokeWidth={1.4} />
            <input
              aria-label={t('Votre recherche', 'Your search')}
              placeholder={
                mode === 'reflect'
                  ? t('Que souhaitez-vous comprendre ?', 'What would you like to understand?')
                  : t(
                      'Rechercher un fait, une décision, un sujet…',
                      'Search for a fact, a decision, a topic…',
                    )
              }
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
            <Button
              kind="primary"
              icon={mode === 'reflect' ? Sparkles : ArrowRight}
              disabled={busy || !query.trim()}
            >
              {mode === 'reflect'
                ? t('Obtenir une réponse', 'Get an answer')
                : t('Rechercher', 'Search')}
            </Button>
          </div>
          <div className="search-bottom">
            <span>
              <CircleHelp size={14} />
              {mode === 'reflect'
                ? t(
                    'Une réponse rédigée à partir des faits · utilise le modèle de la banque',
                    "An answer based on facts · uses the bank's model",
                  )
                : mode === 'text'
                  ? t('Recherche les mots exacts dans les faits', 'Search for exact words in facts')
                  : t(
                      'Recherche sémantique · sans génération de réponse',
                      'Semantic search · no answer generation',
                    )}
            </span>
            <button className="text-button" type="button" onClick={() => setFilters(!filters)}>
              <Tag size={14} />
              {t('Filtres', 'Filters')}
            </button>
          </div>
          {filters && (
            <div className="filter-form">
              <label>
                {' '}
                {t('Étiquettes', 'Tags')}
                <input
                  value={tags}
                  onChange={(e) => setTags(e.target.value)}
                  placeholder={t('projet:horizon, décision', 'project:horizon, decision')}
                />
              </label>
              <label>
                {' '}
                {t('Profondeur', 'Depth')}
                <select value={budget} onChange={(e) => setBudget(e.target.value)}>
                  <option value="low">{t('Rapide', 'Quick')}</option>
                  <option value="mid">{t('Équilibrée', 'Balanced')}</option>
                  <option value="high">{t('Approfondie', 'Thorough')}</option>
                </select>
              </label>
              <label>
                {' '}
                {t('Type de fait', 'Fact type')}
                <select value={type} onChange={(e) => setType(e.target.value)}>
                  <option value="">{t('Tous les types', 'All types')}</option>
                  <option value="world">{factTypePluralLabel('world')}</option>
                  <option value="experience">{factTypePluralLabel('experience')}</option>
                  <option value="observation">{factTypePluralLabel('observation')}</option>
                </select>
              </label>
              {!reflect && (
                <label>
                  {' '}
                  {t('Entité', 'Entity')}
                  <select value={entity} onChange={(e) => setEntity(e.target.value)}>
                    <option value="">{t('Toutes les entités', 'All entities')}</option>
                    {(data.entities || []).map((item: Row) => (
                      <option value={item.id} key={item.id}>
                        {item.canonical_name}
                      </option>
                    ))}
                  </select>
                </label>
              )}
              <label>
                {' '}
                {t('Tâche', 'Task')}
                <input
                  value={task}
                  onChange={(e) => setTask(e.target.value)}
                  placeholder={t('Numéro de tâche', 'Task number')}
                />
              </label>
              {!reflect && (
                <>
                  <label>
                    {' '}
                    {t('À partir du', 'From')}
                    <input type="date" value={start} onChange={(e) => setStart(e.target.value)} />
                  </label>
                  <label>
                    {' '}
                    {t('Jusqu’au', 'Until')}
                    <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} />
                  </label>
                </>
              )}
              {mode === 'recall' && data.serverIs120 && (
                <>
                  <label>
                    {' '}
                    {t('Écarter les faits inutiles', 'Remove irrelevant facts')}
                    <select value={prune} onChange={(e) => setPrune(e.target.value)}>
                      <option value="">{t('Réglage de la banque', 'Bank setting')}</option>
                      <option value="true">
                        {' '}
                        {t('Activer pour cette recherche', 'Enable for this search')}
                      </option>
                      <option value="false">
                        {' '}
                        {t('Désactiver pour cette recherche', 'Disable for this search')}
                      </option>
                    </select>
                  </label>
                  <label>
                    {' '}
                    {t('Retirer les doublons', 'Remove duplicates')}
                    <select value={dedup} onChange={(e) => setDedup(e.target.value)}>
                      <option value="">{t('Réglage de la banque', 'Bank setting')}</option>
                      <option value="true">
                        {' '}
                        {t('Activer pour cette recherche', 'Enable for this search')}
                      </option>
                      <option value="false">
                        {' '}
                        {t('Désactiver pour cette recherche', 'Disable for this search')}
                      </option>
                    </select>
                  </label>
                  <p className="form-hint">
                    {' '}
                    {t(
                      'Ces options demandent un modèle de décision configuré pour recall. Le dédoublonnage ajoute un appel ; les faits peuvent être envoyés au fournisseur choisi sur le serveur.',
                      'These options require a decision model configured for recall. Deduplication adds a request; facts may be sent to the provider selected on the server.',
                    )}
                  </p>
                </>
              )}
            </div>
          )}
        </form>
      </div>
      <ErrorNotice message={data.error} />
      {!searched && !hits.length && (
        <div className="search-welcome">
          <span className="search-welcome-icon">
            <Sparkles size={28} strokeWidth={1.2} />
          </span>
          <h2>{t('Rechercher dans la mémoire', 'Search memory')}</h2>
          <p>
            {' '}
            {t(
              'Saisissez une requête ou sélectionnez une recherche suggérée.',
              'Enter a query or choose a suggested search.',
            )}
          </p>
          <div className="suggestion-chips">
            {suggestions.map((s) => (
              <button onClick={() => void search(s)} key={s}>
                {s}
                <ArrowRight size={14} />
              </button>
            ))}
          </div>
        </div>
      )}
      {data.answer && (
        <section className="card answer-card">
          <CardHeader
            title={t('Ce que votre mémoire en dit', 'What your memory says')}
            action={
              <Badge tone="accent">
                <Sparkles size={12} />
                {t('Réponse générée', 'Generated answer')}
              </Badge>
            }
          />
          <Markdown text={data.answer.text} />
        </section>
      )}
      {!!hits.length && (
        <>
          <div className="results-heading">
            <h2>
              {data.answer
                ? t('Les faits à l’origine de la réponse', 'Facts behind the answer')
                : t('Dans votre mémoire', 'In your memory')}
            </h2>
            <span>
              {number(data.total ?? hits.length)} {t('résultats', 'results')}
            </span>
          </div>
          <div className="fact-list">
            {hits.map((hit) => (
              <article key={hit.id} className="fact-card">
                <div className="fact-card-top">
                  <Badge tone={hit.type === 'observation' ? 'lavender' : 'sage'}>
                    {factTypeLabel(hit.type)}
                  </Badge>
                  <span>{date(hit.occurredStart || hit.mentionedAt)}</span>
                  {hit.score != null && (
                    <span className="match-score">
                      {Math.round(hit.score * 100)} {t('% de pertinence', '% relevance')}
                    </span>
                  )}
                </div>
                <p>{hit.text}</p>
                <div className="fact-card-bottom">
                  <div className="tag-list">
                    {(hit.tags || []).slice(0, 4).map((t: string) => (
                      <span key={t}>#{t}</span>
                    ))}
                  </div>
                  {(hit.documentID || hit.document_id) && (
                    <button
                      className="text-button"
                      onClick={() =>
                        void run('document.open', { id: hit.documentID || hit.document_id })
                          .then(setReader)
                          .catch(() => {})
                      }
                    >
                      {' '}
                      {t('Voir le document source', 'View source document')}
                      <ArrowRight size={14} />
                    </button>
                  )}
                </div>
              </article>
            ))}
          </div>
          {data.canLoadMore && (
            <Button disabled={busy} onClick={() => void run('search.more')}>
              {' '}
              {t('Afficher plus de résultats', 'Show more results')}
            </Button>
          )}
        </>
      )}
      {searched && !hits.length && !busy && !data.error && !data.answer && (
        <Empty
          icon={Search}
          title={t('Pas encore de résultat', 'No results yet')}
          description={t(
            'Essayez une autre formulation ou élargissez les filtres.',
            'Try different wording or broaden the filters.',
          )}
        />
      )}
      {reader && (
        <DocumentReader reader={reader} run={run} busy={busy} onClose={() => setReader(null)} />
      )}
    </>
  );
}

export function Documents({ data, run, busy, refresh, navigate }: PageProps) {
  const { t } = useI18n();
  const [query, setQuery] = useState('');
  const [reader, setReader] = useState<Row | null>(null);
  const [sort, setSort] = useState('recent');
  const documentName = (item: Row): string =>
    item.document_metadata?.title || item.title || item.id;
  const items: Row[] = [...(data.items || [])].sort((a, b) =>
    sort === 'facts'
      ? b.memory_unit_count - a.memory_unit_count
      : sort === 'name'
        ? documentName(a).localeCompare(documentName(b), getLocale(), {
            numeric: true,
            sensitivity: 'base',
          })
        : 0,
  );
  // Requête réellement appliquée par le moteur (le champ peut avoir été modifié depuis).
  const activeQuery = (typeof data.query === 'string' ? data.query : query).trim();
  return (
    <>
      <PageHeader
        eyebrow={t('La mémoire et ses origines', 'Memory and its sources')}
        title="Documents"
        description={t(
          'Consultez ce qui est en mémoire et remontez jusqu’aux sources.',
          'Browse stored documents and trace them back to their sources.',
        )}
        actions={
          <Button icon={FolderPlus} onClick={() => navigate('sources')}>
            {' '}
            {t('Sources', 'Sources')}
          </Button>
        }
      />
      <section className="card">
        <CardHeader
          title={t('Bibliothèque', 'Library')}
          subtitle={t('Les documents conservés par Hindsight', 'Documents stored by Hindsight')}
          action={<Badge>{number(data.total)} documents</Badge>}
        />
        <form
          className="list-toolbar"
          onSubmit={(e) => {
            e.preventDefault();
            void refresh({ query });
          }}
        >
          <div className="input-with-icon">
            <Search size={16} />
            <input
              aria-label={t('Rechercher un document', 'Search for a document')}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('Rechercher un document…', 'Search for a document…')}
            />
          </div>
          <Button icon={Search} disabled={busy}>
            {' '}
            {t('Rechercher', 'Search')}
          </Button>
          <select
            aria-label={t('Trier les documents', 'Sort documents')}
            value={sort}
            onChange={(e) => setSort(e.target.value)}
          >
            <option value="recent">{t('Les plus récents', 'Most recent')}</option>
            <option value="name">{t('Par nom', 'By name')}</option>
            <option value="facts">{t('Nombre de faits', 'Fact count')}</option>
          </select>
        </form>
        <ErrorNotice message={data.error} />
        {!data.items && !data.error ? (
          <Loading />
        ) : items.length ? (
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>Document</th>
                  <th>{t('Faits extraits', 'Extracted facts')}</th>
                  <th>{t('Taille', 'Size')}</th>
                  <th>{t('Mis à jour', 'Updated')}</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id}>
                    <td>
                      <button
                        className="document-cell"
                        onClick={() =>
                          void run('document.open', { id: item.id })
                            .then(setReader)
                            .catch(() => {})
                        }
                      >
                        <span className="file-icon document">
                          <FileText size={19} />
                        </span>
                        <span>
                          <strong>{documentName(item)}</strong>
                          <small>{(item.tags || []).slice(0, 2).join(' · ') || item.id}</small>
                        </span>
                      </button>
                    </td>
                    <td>
                      <Badge tone={item.memory_unit_count ? 'sage' : 'amber'}>
                        {number(item.memory_unit_count)} {t('faits', 'facts')}
                      </Badge>
                    </td>
                    <td className="muted">
                      {number((item.text_length || 0) / 1000)} {t('kcar.', 'k chars')}
                    </td>
                    <td className="muted">{date(item.updated_at || item.created_at)}</td>
                    <td>
                      <IconButton
                        icon={ArrowRight}
                        label={`${t('Lire', 'Read')} ${documentName(item)}`}
                        onClick={() =>
                          void run('document.open', { id: item.id })
                            .then(setReader)
                            .catch(() => {})
                        }
                      />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : data.error ? null : activeQuery ? (
          <Empty
            icon={Search}
            title={t('Aucun document ne correspond', 'No matching document')}
            description={t(
              'Essayez un autre mot ou effacez la recherche.',
              'Try another word or clear the search.',
            )}
          />
        ) : (
          <Empty
            title={t('La bibliothèque est vide', 'The library is empty')}
            description={t(
              'Ajoutez un dossier dans Sources pour comparer vos fichiers à la mémoire, puis choisissez ce que vous souhaitez envoyer.',
              'Add a folder in Sources to compare files with memory, then choose what to upload.',
            )}
            action={
              <Button icon={FolderPlus} onClick={() => navigate('sources')}>
                {' '}
                {t('Ajouter des sources', 'Add sources')}
              </Button>
            }
          />
        )}
        {data.canLoadMore && (
          <div className="card-footer">
            <Button onClick={() => void run('documents.more')} disabled={busy}>
              {' '}
              {t('Charger plus de documents', 'Load more documents')}
            </Button>
            <span>
              {number(items.length)} {t('sur', 'of')} {number(data.total)}
            </span>
          </div>
        )}
      </section>
      {reader && (
        <DocumentReader reader={reader} run={run} busy={busy} onClose={() => setReader(null)} />
      )}
    </>
  );
}
