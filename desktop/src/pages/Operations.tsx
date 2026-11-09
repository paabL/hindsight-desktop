import { translate as t, useI18n } from '../i18n';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ArrowRight, Check, Clock3, ListTodo, RotateCcw, Sparkles, Trash2, X } from 'lucide-react';
import type { PageProps, PauseState, Row } from '../types';
import {
  Badge,
  Button,
  Empty,
  ErrorNotice,
  IconButton,
  Modal,
  PageHeader,
  Tabs,
  date,
  number,
} from '../ui';
import { PauseTools } from './Consumption';

export default function Operations({
  data,
  run,
  busy,
  refresh,
  pause,
  bank,
}: PageProps & { pause?: PauseState; bank?: string | null }) {
  useI18n();
  const labels: Record<string, string> = {
    pending: t('En attente', 'Pending'),
    processing: t('En cours', 'Processing'),
    completed: t('Terminée', 'Completed'),
    failed: t('En échec', 'Failed'),
    cancelled: t('Annulée', 'Cancelled'),
  };
  const typeNames: Record<string, string> = {
    // Mêmes noms que l’écran Consommation et les confirmations du moteur (OperationRow.typeTitle).
    retain: t('Extraction des faits', 'Fact extraction'),
    batch_retain: t('Extraction par lot', 'Batch extraction'),
    consolidation: t('Consolidation', 'Consolidation'),
    refresh_mental_model: t('Régénération des connaissances', 'Knowledge regeneration'),
    reprocess_document: t('Retraitement', 'Reprocessing'),
    file_convert_retain: t('Conversion et extraction', 'Conversion and extraction'),
    webhook_delivery: t('Envoi de webhook', 'Webhook delivery'),
    bank_export: t('Export', 'Export'),
    export: t('Export', 'Export'),
    bank_import: t('Import', 'Import'),
    import: t('Import', 'Import'),
    bank_clone: t('Clonage', 'Clone'),
    clone: t('Clonage', 'Clone'),
  };

  const typeName = (item: Row): string =>
    typeNames[item.operation_type || item.task_type] || item.operation_type || item.task_type || '';
  // « Extraction des faits · Extraction des faits · 24 / 24 » : l'étape n'est montrée que si elle apporte quelque chose.
  const stageLabel = (item: Row): string => {
    const stage = String(item.progress?.stage || '').trim();
    const name = typeName(item).toLocaleLowerCase();
    return !stage || (name && stage.toLocaleLowerCase().startsWith(name.split(' ')[0]))
      ? ''
      : stage;
  };
  const [filter, setFilter] = useState(data.statusFilter || 'all');
  useEffect(() => {
    if (data.statusFilter) setFilter(data.statusFilter);
  }, [data.statusFilter]);
  const [selected, setSelected] = useState<Row | null>(null);
  const detailRequest = useRef(0);
  const [detailLoading, setDetailLoading] = useState(false);
  useEffect(
    () => () => {
      detailRequest.current++;
    },
    [],
  );
  const allItems: Row[] = data.items || [];
  // Mode consultation : le moteur ignore toute écriture, les actions sont donc désactivées.
  const readOnly = !!data.consultationOnly;
  // « Exécuter maintenant » ne concerne que les opérations dont le moteur accepte l’avance.
  const runNow = useMemo(() => new Set<string>(data.runNowIDs || []), [data.runNowIDs]);
  const [visibleLimit, setVisibleLimit] = useState(100);
  useEffect(() => {
    setVisibleLimit(100);
  }, [filter]);
  const matching = useMemo(
    () => (filter === 'all' ? allItems : allItems.filter((item) => item.status === filter)),
    [allItems, filter],
  );
  const items = matching.slice(0, visibleLimit);
  const loadedCounts = useMemo(() => {
    const result: Record<string, number> = {};
    for (const item of allItems) result[item.status] = (result[item.status] || 0) + 1;
    return result;
  }, [allItems]);
  const count = (status: string) =>
    data.counts ? (data.counts[status] ?? 0) : (loadedCounts[status] ?? 0);
  async function loadMore() {
    if (visibleLimit >= matching.length && data.canLoadMore) await run('operations.more');
    setVisibleLimit((value) => value + 100);
  }
  async function openDetail(id: string) {
    const request = ++detailRequest.current;
    setSelected(null);
    setDetailLoading(true);
    try {
      const result = await run('operation.open', { id });
      if (request === detailRequest.current && result && !result.error) setSelected(result);
    } finally {
      if (request === detailRequest.current) setDetailLoading(false);
    }
  }
  return (
    <>
      <PageHeader
        eyebrow={t('Ce qui se passe en coulisses', 'Behind the scenes')}
        title={t('Traitements', 'Processing')}
        description={t(
          'Suivez les traitements et intervenez quand c’est utile.',
          'Follow processing and act when needed.',
        )}
        actions={<PauseTools run={run} busy={busy} pause={pause} bank={bank} readOnly={readOnly} />}
      />
      {(pause?.frozen || pause?.workerOff) && (
        <div className="notice">
          {pause?.frozen
            ? t(
                'La file du serveur est gelée : les opérations attendent jusqu’au dégel (⋯ › Dégeler).',
                'The server queue is frozen: operations wait until it is unfrozen (⋯ › Unfreeze).',
              )
            : t(
                'Le worker du serveur est arrêté par sa configuration : les opérations attendent.',
                'The server worker is turned off by its configuration: operations wait.',
              )}
        </div>
      )}
      <div className="operations-summary">
        <div>
          <span className="status-dot warning" />
          <strong>{count('pending')}</strong>
          <span>{t('en attente', 'pending')}</span>
        </div>
        <div>
          <span className="status-dot green" />
          <strong>{count('processing')}</strong>
          <span>{t('en cours', 'processing')}</span>
        </div>
        <div>
          <span className="status-dot red" />
          <strong>{count('failed')}</strong>
          <span>{t('en échec', 'failed')}</span>
        </div>
        {!data.counts && (
          <small>{t('Parmi les opérations chargées', 'Among loaded operations')}</small>
        )}
        <span className="spacer" />
        {count('failed') > 0 && (
          <Button
            kind="ghost"
            icon={RotateCcw}
            disabled={busy || readOnly}
            title={t(
              'Remet en file les opérations en échec.',
              'Puts failed operations back in the queue.',
            )}
            onClick={() => void run('operations.retryFailed')}
          >
            {t('Relancer les échecs', 'Retry failed operations')}
          </Button>
        )}
      </div>
      <Tabs
        value={filter}
        onChange={(value) => {
          setFilter(value);
          void refresh({ status: value });
        }}
        items={[
          { id: 'all', label: t('Toutes', 'All') },
          ...Object.entries(labels).map(([id, label]) => ({ id, label })),
        ]}
      />
      <ErrorNotice message={data.error} />
      {data.refreshing && <p role="status">{t('Actualisation…', 'Refreshing…')}</p>}
      {detailLoading && <p role="status">{t('Chargement du détail…', 'Loading details…')}</p>}
      <section className="card operations-list">
        {items.length ? (
          items.map((item) => {
            const withoutWork =
              item.status === 'completed' &&
              item.progress?.processed === 0 &&
              item.progress?.total > 0;
            const active = item.status === 'pending' || item.status === 'processing';
            return (
              <article key={item.id} className="operation-row">
                <span className={`operation-icon ${item.status}`}>
                  {item.status === 'completed' ? (
                    <Check size={19} />
                  ) : item.status === 'failed' ? (
                    <X size={19} />
                  ) : (
                    <Clock3 size={19} />
                  )}
                </span>
                <div className="operation-main">
                  <div>
                    <strong>
                      {typeNames[item.operation_type || item.task_type] ||
                        item.operation_type ||
                        item.task_type}
                    </strong>
                    <Badge
                      tone={
                        item.status === 'failed'
                          ? 'red'
                          : item.status === 'completed'
                            ? 'sage'
                            : active
                              ? 'amber'
                              : 'neutral'
                      }
                    >
                      {withoutWork
                        ? t('Sans effet', 'No effect')
                        : labels[item.status] || item.status}
                    </Badge>
                  </div>
                  {/* L'identifiant technique reste dans le détail ; une consolidation porte sur toute la banque. */}
                  {(item.document_id || item.mental_model_id || item.filename) && (
                    <p>{item.document_id || item.mental_model_id || item.filename}</p>
                  )}
                  {item.progress && (
                    <small>
                      {[
                        stageLabel(item),
                        item.progress.total != null
                          ? `${number(item.progress.processed)} / ${number(item.progress.total)}`
                          : '',
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </small>
                  )}
                  {item.error_message && (
                    <div className={`operation-error ${active ? 'previous' : ''}`}>
                      {active && <strong>{t('Dernière tentative : ', 'Last attempt: ')}</strong>}
                      {item.error_message}
                    </div>
                  )}
                </div>
                <span className="operation-date">
                  {date(item.updated_at || item.created_at, true)}
                </span>
                <div className="operation-actions">
                  {item.status === 'failed' && (
                    <IconButton
                      icon={RotateCcw}
                      label={t('Relancer cette opération', 'Retry this operation')}
                      disabled={busy || readOnly}
                      onClick={() => void run('operation.retry', { id: item.id })}
                    />
                  )}
                  {item.status === 'pending' && (
                    <>
                      {runNow.has(item.id) && (
                        <IconButton
                          icon={Sparkles}
                          label={t('Exécuter maintenant', 'Run now')}
                          disabled={busy || readOnly}
                          onClick={() => void run('operation.now', { id: item.id })}
                        />
                      )}
                      <IconButton
                        icon={X}
                        label={t('Annuler cette opération', 'Cancel this operation')}
                        disabled={busy || readOnly}
                        onClick={() => void run('operation.cancel', { id: item.id })}
                      />
                    </>
                  )}
                  {!active && (
                    <IconButton
                      icon={Trash2}
                      label={t(
                        'Supprimer l’historique de cette opération',
                        'Delete this operation history',
                      )}
                      disabled={busy || readOnly}
                      onClick={() => void run('operation.delete', { id: item.id })}
                    />
                  )}
                  <IconButton
                    icon={ArrowRight}
                    label={t('Détail de l’opération', 'Operation details')}
                    onClick={() => void openDetail(item.id)}
                  />
                </div>
              </article>
            );
          })
        ) : (
          <Empty
            icon={ListTodo}
            title={
              filter === 'all'
                ? t('La file est vide', 'The queue is empty')
                : t('Aucune opération dans ce filtre', 'No operations match this filter')
            }
            description={t(
              'Les extractions de faits, consolidations et régénérations des connaissances apparaîtront ici.',
              'Fact extractions, consolidations and knowledge regenerations will appear here.',
            )}
          />
        )}
        {(items.length < matching.length || data.canLoadMore) && (
          <div className="card-footer">
            <Button
              disabled={busy || data.loadingMore || data.refreshing}
              onClick={() => void loadMore()}
            >
              {t('Afficher la suite', 'Show more')}
            </Button>
            <span>
              {number(items.length)} {t('sur', 'of')} {number(data.total)}
            </span>
          </div>
        )}
      </section>
      {selected && (
        <Modal
          title={t('Détail de l’opération', 'Operation details')}
          onClose={() => {
            detailRequest.current++;
            setSelected(null);
            setDetailLoading(false);
          }}
          wide
        >
          <pre className="json-view">{JSON.stringify(selected, null, 2)}</pre>
        </Modal>
      )}
    </>
  );
}
