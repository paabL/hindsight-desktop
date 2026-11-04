import { translate as t, useI18n } from '../i18n';
import { useState } from 'react';
import {
  ArrowRight,
  Check,
  Clock3,
  Layers3,
  ListTodo,
  RefreshCw,
  RotateCcw,
  Sparkles,
  Trash2,
  X,
} from 'lucide-react';
import type { PageProps, Row } from '../types';
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

export default function Operations({ data, run, busy, refresh }: PageProps) {
  useI18n();
  const labels: Record<string, string> = {
    pending: t('En attente', 'Pending'),
    processing: t('En cours', 'Processing'),
    completed: t('Terminée', 'Completed'),
    failed: t('En échec', 'Failed'),
    cancelled: t('Annulée', 'Cancelled'),
  };
  const typeNames: Record<string, string> = {
    retain: t('Extraction de faits', 'Fact extraction'),
    batch_retain: t('Extraction par lot', 'Batch extraction'),
    consolidation: t('Consolidation', 'Consolidation'),
    refresh_mental_model: t('Synthèse', 'Knowledge page'),
    reprocess_document: t('Retraitement', 'Reprocessing'),
    file_convert_retain: t('Conversion et extraction', 'Conversion and extraction'),
  };

  const [filter, setFilter] = useState('all');
  const [selected, setSelected] = useState<Row | null>(null);
  const items: Row[] = data.items || [];
  return (
    <>
      <PageHeader
        eyebrow={t('Ce qui se passe en coulisses', 'Behind the scenes')}
        title={t('Opérations', 'Operations')}
        description={t(
          'Suivez les traitements et intervenez quand c’est utile.',
          'Follow processing and act when needed.',
        )}
        actions={
          <>
            <PauseTools run={run} busy={busy} />
            <Button
              icon={Layers3}
              kind="primary"
              disabled={busy || data.consultationOnly}
              onClick={() => void run('operations.consolidate')}
            >
              {t('Consolider', 'Consolidate')}
            </Button>
          </>
        }
      />
      {data.consultationOnly && (
        <div className="notice">
          {t(
            'Le serveur est en mode consultation. Les traitements sont désactivés.',
            'The server is in read-only mode. Processing is disabled.',
          )}
        </div>
      )}
      <div className="operations-summary">
        <div>
          <span className="status-dot warning" />
          <strong>{items.filter((i) => i.status === 'pending').length}</strong>
          <span>{t('en attente', 'pending')}</span>
        </div>
        <div>
          <span className="status-dot green" />
          <strong>{items.filter((i) => i.status === 'processing').length}</strong>
          <span>{t('en cours', 'processing')}</span>
        </div>
        <div>
          <span className="status-dot red" />
          <strong>{items.filter((i) => i.status === 'failed').length}</strong>
          <span>{t('en échec', 'failed')}</span>
        </div>
        <span className="spacer" />
        <Button
          kind="ghost"
          icon={RotateCcw}
          disabled={busy}
          onClick={() => void run('operations.retryFailed')}
        >
          {t('Relancer les échecs', 'Retry failed operations')}
        </Button>
        <Button kind="ghost" disabled={busy} onClick={() => void run('operations.recover')}>
          {t('Récupérer la consolidation', 'Recover consolidation')}
        </Button>
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
                  <p>{item.document_id || item.mental_model_id || item.filename || item.id}</p>
                  {item.progress && (
                    <small>
                      {item.progress.stage}
                      {item.progress.total != null &&
                        ` · ${number(item.progress.processed)} / ${number(item.progress.total)}`}
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
                      icon={RefreshCw}
                      label={t('Relancer cette opération', 'Retry this operation')}
                      disabled={busy}
                      onClick={() => void run('operation.retry', { id: item.id })}
                    />
                  )}
                  {item.status === 'pending' && (
                    <>
                      <IconButton
                        icon={Sparkles}
                        label={t('Exécuter maintenant', 'Run now')}
                        disabled={busy}
                        onClick={() => void run('operation.now', { id: item.id })}
                      />
                      <IconButton
                        icon={X}
                        label={t('Annuler cette opération', 'Cancel this operation')}
                        disabled={busy}
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
                      disabled={busy}
                      onClick={() => void run('operation.delete', { id: item.id })}
                    />
                  )}
                  <IconButton
                    icon={ArrowRight}
                    label={t('Détail de l’opération', 'Operation details')}
                    onClick={() => void run('operation.open', { id: item.id }).then(setSelected)}
                  />
                </div>
              </article>
            );
          })
        ) : (
          <Empty
            icon={ListTodo}
            title={t('La file est vide', 'The queue is empty')}
            description={t(
              'Les extractions, consolidations et générations de synthèses apparaîtront ici.',
              'Extractions, consolidations and knowledge-page generation will appear here.',
            )}
          />
        )}
        {data.canLoadMore && (
          <div className="card-footer">
            <Button onClick={() => void run('operations.more')}>
              {t('Afficher la suite', 'Load more')}
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
          onClose={() => setSelected(null)}
          wide
        >
          <pre className="json-view">{JSON.stringify(selected, null, 2)}</pre>
        </Modal>
      )}
    </>
  );
}
