import { getLocale, useI18n } from '../i18n';
import { translate as tr } from '../i18n-core';
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
  Pencil,
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
import { OBSERVATION_SCOPES, isListedScope } from '../observation-scopes';
import { factTypeLabel, factTypePluralLabel } from '../fact-types';
import DocumentContent from './DocumentContent';

/** Événements de l’historique d’un document (`kind` du serveur), avec les mots de l’app. */
const documentEvents: Record<string, [string, string]> = {
  retain: ['Envoi', 'Upload'],
  append: ['Texte ajouté', 'Text appended'],
  reprocess: ['Retraitement', 'Reprocessing'],
  retag: ['Étiquettes modifiées', 'Tags changed'],
  fact_edited: ['Fait corrigé', 'Fact corrected'],
  fact_invalidated: ['Fait invalidé', 'Fact invalidated'],
  fact_restored: ['Fait rétabli', 'Fact restored'],
  fact_deleted: ['Fait supprimé', 'Fact deleted'],
  observations_cleared: ['Observations effacées', 'Observations cleared'],
  consolidation: ['Consolidation', 'Consolidation'],
};
function documentEventTitle(kind: unknown) {
  const label = documentEvents[String(kind)];
  return label ? tr(label[0], label[1]) : String(kind || tr('Événement', 'Event'));
}
/** « +12 faits · 3 observations créées » : ce que l’événement a changé, sans le JSON. */
function documentEventSummary(event: Row) {
  const parts: string[] = [];
  const n = (value: unknown) => Number(value) || 0;
  const plural = (count: number) => (count > 1 ? 's' : '');
  if (n(event.facts_added))
    parts.push(
      tr(
        `+${number(n(event.facts_added))} fait${plural(n(event.facts_added))}`,
        `+${number(n(event.facts_added))} fact${plural(n(event.facts_added))}`,
      ),
    );
  if (n(event.facts_removed))
    parts.push(
      tr(
        `−${number(n(event.facts_removed))} fait${plural(n(event.facts_removed))}`,
        `−${number(n(event.facts_removed))} fact${plural(n(event.facts_removed))}`,
      ),
    );
  for (const [key, fr, en] of [
    ['observations_created', 'créée', 'created'],
    ['observations_updated', 'mise à jour', 'updated'],
    ['observations_removed', 'retirée', 'removed'],
  ]) {
    const count = n(event[key]?.count);
    if (count)
      parts.push(
        tr(
          `${number(count)} observation${plural(count)} ${count > 1 && fr !== 'mise à jour' ? fr + 's' : count > 1 ? 'mises à jour' : fr}`,
          `${number(count)} observation${plural(count)} ${en}`,
        ),
      );
  }
  return parts.join(' · ');
}

export function DocumentReader({
  reader: opened,
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
  // Lecteur affiché : celui reçu à l'ouverture, puis relu après chaque action (étiquettes, portée,
  // retraitement) pour ne jamais garder des faits ou des étiquettes que le serveur n'a plus.
  const [reader, setCurrent] = useState<Row>(opened);
  useEffect(() => setCurrent(opened), [opened]);
  const document = reader.document || {};
  const savedTags = (document.tags || []).join(', ');
  const [tags, setTags] = useState<string>(savedTags);
  useEffect(() => setTags(savedTags), [savedTags]);
  const [find, setFind] = useState('');
  const [acting, setActing] = useState(false);
  const facts: Row[] = reader.facts || [];
  const factsTotal = Math.max(Number(reader.factsTotal) || 0, facts.length);
  // Une action du lecteur passe par une confirmation. Une suppression confirmée ferme le lecteur côté
  // moteur : la fenêtre se ferme avec lui ; toute autre issue (faite, refusée, annulée) relit le document.
  useEffect(() => {
    if (!acting || busy) return;
    let active = true;
    void run('document.status', { id: document.id, polling: true }).then(async (status) => {
      if (!active || typeof status?.open !== 'boolean') return;
      if (!status.open) return onClose();
      if (status.confirming) return;
      setActing(false);
      const fresh = await run('document.open', { id: document.id });
      if (active && fresh && !fresh.error && fresh.document?.id === document.id) setCurrent(fresh);
    });
    return () => {
      active = false;
    };
  }, [acting, busy]);
  function act(command: string, args: Row) {
    setActing(true);
    void run(command, { id: document.id, ...args });
  }
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
                  <strong>{documentEventTitle(event.kind)}</strong>
                  <p>
                    {date(event.created_at || event.timestamp, true)}
                    {documentEventSummary(event) && ` · ${documentEventSummary(event)}`}
                  </p>
                  <details>
                    <summary>{t('Détail', 'Details')}</summary>
                    <pre>{JSON.stringify(event, null, 2)}</pre>
                  </details>
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
              act('document.tags', {
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
          {/* La portée n'agit que si la banque crée des observations, et ne change qu'avec un serveur 1.1.0. */}
          {reader.scopeEditable !== false && reader.observations !== false && (
            <label>
              {t('Portée des observations', 'Observation scope')}
              <select
                value={isListedScope(reader.scopeMode) ? reader.scopeMode : ''}
                disabled={busy}
                onChange={(e) => {
                  if (e.target.value) act('document.scope', { scope: e.target.value });
                }}
              >
                {!isListedScope(reader.scopeMode) && (
                  <option value="" disabled>
                    {reader.scope ? nativeSystemMessage(reader.scope) : t('Inconnue', 'Unknown')}
                  </option>
                )}
                {OBSERVATION_SCOPES.map((scope) => (
                  <option key={scope.value} value={scope.value}>
                    {t(scope.fr, scope.en)}
                  </option>
                ))}
              </select>
              <small>
                {t(
                  'Décide quels faits peuvent se fondre dans les mêmes observations. Les faits ne sont pas réextraits.',
                  'Decides which facts can merge into the same observations. Facts are not extracted again.',
                )}
              </small>
            </label>
          )}
          <div className="action-row">
            {/* Le serveur réextrait le texte original stocké : sans lui, le retraitement est impossible. */}
            {reader.canReprocess !== false && (
              <Button
                icon={RotateCcw}
                disabled={busy}
                title={t(
                  'Relance l’extraction des faits de ce document (appels LLM).',
                  'Runs fact extraction again for this document (LLM calls).',
                )}
                onClick={() => act('document.reprocess', {})}
              >
                {' '}
                {t('Retraiter le document', 'Reprocess document')}
              </Button>
            )}
            <Button
              icon={Trash2}
              kind="danger"
              disabled={busy}
              onClick={() => act('document.delete', {})}
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
  // Nom et question modifiés depuis la page ouverte ; la fenêtre se referme quand la page relue les porte.
  const [editing, setEditing] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [draftQuery, setDraftQuery] = useState('');
  const [submitted, setSubmitted] = useState<{ name: string; query: string } | null>(null);
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
    setEditing(false);
  }
  // Après une modification, le moteur relit la page ouverte : son nom et sa question à jour priment.
  const shown: Row | null =
    model && data.openModel?.id === model.id ? { ...model, ...data.openModel } : model;
  const currentQuery = (shown?.source_query || '').trim();
  // Une question vidée n'est pas une nouvelle question : elle ne s'enregistre pas.
  const queryEmptied = !draftQuery.trim() && !!currentQuery;
  const requery = !queryEmptied && draftQuery.trim() !== currentQuery;
  const changed = !!shown && (draftName.trim() !== shown.name || requery);
  function startEdit() {
    if (!shown) return;
    setDraftName(shown.name);
    setDraftQuery(shown.source_query || '');
    setSubmitted(null);
    setEditing(true);
  }
  useEffect(() => {
    if (
      submitted &&
      shown &&
      shown.name === submitted.name &&
      (shown.source_query || '').trim() === submitted.query
    ) {
      setEditing(false);
      setSubmitted(null);
    }
  }, [shown, submitted]);
  // Régénération en attente ou en cours (opérations de Traitements) : l'état prime sur « À régénérer ».
  const refreshing = new Set<string>(Array.isArray(data.refreshing) ? data.refreshing : []);
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
          'Ce que la banque sait d’un sujet, rédigé à partir de ses faits : les pages de connaissance, tenues par le serveur, et les modèles mentaux, des questions que vous suivez.',
          'What the bank knows about a topic, written from its facts: knowledge pages, kept by the server, and mental models, questions you follow.',
        )}
        actions={
          <Button kind="primary" icon={Plus} onClick={() => setCreate(true)}>
            {' '}
            {t('Nouveau modèle mental', 'New mental model')}
          </Button>
        }
      />
      <div className="list-toolbar knowledge-toolbar">
        <div className="standalone-search input-with-icon">
          <Search size={17} />
          <input
            aria-label={t('Filtrer les connaissances', 'Filter knowledge')}
            placeholder={t('Retrouver une connaissance…', 'Find knowledge…')}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        {allModels && (
          <span className="toolbar-count" role="status">
            {query.trim() && models.length !== allModels.length
              ? t(
                  `${number(models.length)} sur ${number(allModels.length)}`,
                  `${number(models.length)} of ${number(allModels.length)}`,
                )
              : t(
                  `${number(allModels.length)} élément${allModels.length > 1 ? 's' : ''}`,
                  `${number(allModels.length)} item${allModels.length === 1 ? '' : 's'}`,
                )}
          </span>
        )}
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
                <Badge
                  tone={
                    refreshing.has(m.id)
                      ? 'blue'
                      : refreshFailed(m)
                        ? 'red'
                        : m.is_stale
                          ? 'amber'
                          : 'sage'
                  }
                >
                  {refreshing.has(m.id)
                    ? t('Régénération en cours', 'Regenerating')
                    : refreshFailed(m)
                      ? t('Échec de la génération', 'Generation failed')
                      : m.is_stale
                        ? t('À régénérer', 'Needs regenerating')
                        : m.last_refreshed_at
                          ? t('À jour', 'Up to date')
                          : t('Jamais générée', 'Never generated')}
                </Badge>
              </div>
              <span className="model-kind">
                {m.is_knowledge_page
                  ? t('Page de connaissance', 'Knowledge page')
                  : t('Modèle mental', 'Mental model')}
              </span>
              <h2>{m.name}</h2>
              <p>
                {m.source_query ||
                  t('Construite à partir des faits de la banque.', "Built from the bank's facts.")}
              </p>
              <div className="model-card-bottom">
                <span>
                  <Clock3 size={13} />
                  {/* Une connaissance jamais générée n'a pas de date de génération : on dit quand elle a été créée. */}
                  {m.last_refreshed_at
                    ? date(m.last_refreshed_at)
                    : `${t('Créée le', 'Created on')} ${date(m.created_at)}`}
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
      {model && shown && (
        <Modal
          title={shown.name}
          subtitle={shown.source_query}
          wide
          onClose={() => {
            setModel(null);
            setEditing(false);
          }}
        >
          <div className="reader-meta">
            <Badge>
              {shown.is_knowledge_page
                ? t('Page de connaissance', 'Knowledge page')
                : t('Modèle mental', 'Mental model')}
            </Badge>
            <span>
              {shown.last_refreshed_at
                ? `${t('Générée le', 'Generated on')} ${date(shown.last_refreshed_at, true)}`
                : t('Jamais générée', 'Never generated')}
            </span>
            {refreshFailed(shown) && (
              <Badge tone="red">
                {t('Échec de la dernière génération', 'Last generation failed')}
              </Badge>
            )}
            <div className="spacer" />
            {/* Pendant la modification, son formulaire porte la seule action principale. */}
            {!editing && (
              <>
                <Button
                  icon={WandSparkles}
                  disabled={busy || refreshing.has(shown.id)}
                  title={
                    refreshing.has(shown.id)
                      ? t(
                          'Une régénération est déjà en cours ou en file (Activité › Traitements).',
                          'A regeneration is already running or queued (Activity › Processing).',
                        )
                      : t(
                          'Fait réécrire cette connaissance par le LLM à partir des faits actuels (appel LLM).',
                          'Has the LLM rewrite this knowledge item from the current facts (LLM call).',
                        )
                  }
                  onClick={() => void run('model.refresh', { id: shown.id })}
                >
                  {' '}
                  {refreshing.has(shown.id)
                    ? t('Régénération en cours', 'Regenerating')
                    : t('Régénérer', 'Regenerate')}
                </Button>
                <IconButton
                  icon={Pencil}
                  label={t('Modifier le nom et la question', 'Edit the name and question')}
                  disabled={busy}
                  onClick={startEdit}
                />
                <IconButton
                  icon={Trash2}
                  label={t('Supprimer cette connaissance', 'Delete this knowledge item')}
                  disabled={busy}
                  onClick={() => void run('model.delete', { id: shown.id })}
                />
              </>
            )}
          </div>
          {editing && (
            <form
              className="form-stack knowledge-edit"
              aria-label={t('Modifier le nom et la question', 'Edit the name and question')}
              onSubmit={(e) => {
                e.preventDefault();
                if (!changed || !draftName.trim() || queryEmptied) return;
                setSubmitted({ name: draftName.trim(), query: draftQuery.trim() });
                void run('model.update', { id: shown.id, name: draftName, query: draftQuery });
              }}
            >
              <label>
                {shown.is_knowledge_page
                  ? t('Nom de la page de connaissance', 'Knowledge page name')
                  : t('Nom du modèle mental', 'Mental model name')}
                <input required value={draftName} onChange={(e) => setDraftName(e.target.value)} />
              </label>
              <label>
                {t('La question à explorer', 'The question to explore')}
                <textarea
                  value={draftQuery}
                  onChange={(e) => setDraftQuery(e.target.value)}
                  rows={6}
                />
              </label>
              <p className="form-hint">
                {requery
                  ? t(
                      'Une nouvelle question régénère le contenu par le LLM. L’estimation sera présentée avant confirmation.',
                      'A new question has the LLM regenerate the content. An estimate will be shown before you confirm.',
                    )
                  : t(
                      'Changer le nom ne touche pas au contenu.',
                      'Changing the name leaves the content as it is.',
                    )}
              </p>
              <div className="modal-actions">
                <Button type="button" onClick={() => setEditing(false)}>
                  {t('Annuler', 'Cancel')}
                </Button>
                <Button
                  kind="primary"
                  icon={requery ? WandSparkles : Check}
                  disabled={busy || !changed || !draftName.trim() || queryEmptied}
                >
                  {requery
                    ? t('Enregistrer et régénérer', 'Save and regenerate')
                    : t('Enregistrer', 'Save')}
                </Button>
              </div>
            </form>
          )}
          {shown.content ? (
            <Markdown text={shown.content} />
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
                'La génération utilise le modèle des Connaissances (Modèles). L’estimation sera présentée avant confirmation.',
                'Generation uses the Knowledge model (Models). An estimate will be shown before you confirm.',
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
                    'Une réponse rédigée à partir des faits · utilise le modèle des Réponses (Modèles)',
                    'An answer based on facts · uses the Answers model (Models)',
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
                      'Sans effet tant que le serveur n’a pas de modèle de décision pour la recherche (Modèles). Retirer les doublons ajoute une requête ; les faits peuvent être envoyés au fournisseur choisi sur le serveur.',
                      'Has no effect until the server has a decision model configured for search (Models). Removing duplicates adds a request; facts may be sent to the provider selected on the server.',
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
                      {t(
                        `${Math.round(hit.score * 100)} % de pertinence`,
                        `${Math.round(hit.score * 100)}% relevance`,
                      )}
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

// Au-delà, trier toute la banque demanderait trop de pages : le tri porte sur ce qui est chargé, et le dit.
const sortLoadLimit = 2000;

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
  // « projet:horizon » se lit « horizon » : la clé de l'étiquette n'aide pas à reconnaître un document.
  const tagLabel = (tag: string) => tag.replace(/^[^:\s]+:/, '');
  return (
    <>
      <PageHeader
        eyebrow={t('La mémoire et ses origines', 'Memory and its sources')}
        title="Documents"
        description={t(
          'Les documents conservés par la banque, et les faits qui en ont été extraits.',
          'The documents kept by the bank, and the facts extracted from them.',
        )}
      />
      <section className="card">
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
            onChange={(e) => {
              const value = e.target.value;
              setSort(value);
              // Un tri autre que chronologique porte sur toute la banque, pas sur la première page.
              if (value !== 'recent' && data.canLoadMore && Number(data.total) <= sortLoadLimit)
                void run('documents.all');
            }}
          >
            <option value="recent">{t('Les plus récents', 'Most recent')}</option>
            <option value="name">{t('Par nom', 'By name')}</option>
            <option value="facts">{t('Nombre de faits', 'Fact count')}</option>
          </select>
          {typeof data.total === 'number' && (
            <span className="toolbar-count" role="status">
              {data.totalIsEstimate
                ? t(
                    `Au moins ${number(data.total)} document${data.total > 1 ? 's' : ''}`,
                    `At least ${number(data.total)} document${data.total === 1 ? '' : 's'}`,
                  )
                : t(
                    `${number(data.total)} document${data.total > 1 ? 's' : ''}`,
                    `${number(data.total)} document${data.total === 1 ? '' : 's'}`,
                  )}
              {sort !== 'recent' && data.canLoadMore
                ? t(
                    ` · tri parmi les ${number(items.length)} chargés`,
                    ` · sorted among the ${number(items.length)} loaded`,
                  )
                : ''}
            </span>
          )}
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
                  <th>{t('Longueur', 'Length')}</th>
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
                          <small>
                            {(item.tags || []).slice(0, 2).map(tagLabel).join(' · ') || item.id}
                          </small>
                        </span>
                      </button>
                    </td>
                    <td>
                      <Badge tone={item.memory_unit_count ? 'sage' : 'amber'}>
                        {number(item.memory_unit_count)}{' '}
                        {t(
                          item.memory_unit_count > 1 ? 'faits' : 'fait',
                          item.memory_unit_count === 1 ? 'fact' : 'facts',
                        )}
                      </Badge>
                    </td>
                    <td className="muted">
                      {t(
                        `${number(item.text_length || 0)} signe${(item.text_length || 0) > 1 ? 's' : ''}`,
                        `${number(item.text_length || 0)} character${(item.text_length || 0) === 1 ? '' : 's'}`,
                      )}
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
              {t('Afficher plus de documents', 'Show more documents')}
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
