import { useEffect, useState } from 'react';
import { ArrowDownToLine, RotateCcw } from 'lucide-react';
import { useI18n } from '../i18n';
import type { PageProps, Row } from '../types';
import { Badge, Button, CardHeader, ErrorNotice } from '../ui';

const ROLES = [
  {
    id: 'reranker',
    title: ['Reranker du recall', 'Recall reranker'],
    help: [
      'Classe les candidats de chaque recherche. Qualité : nDCG@10 sur 15 vraies requêtes étiquetées.',
      'Orders the candidates of every search. Quality: nDCG@10 on 15 real labeled queries.',
    ],
  },
  {
    id: 'embeddings',
    title: ['Embeddings', 'Embeddings'],
    help: [
      'Vecteurs des faits et des requêtes. Seuls des moteurs du même modèle sont proposés : pas de réindexation.',
      'Vectors of facts and queries. Only engines of the same model are offered: no reindexing.',
    ],
  },
  {
    id: 'decision',
    title: ['Modèle de décision', 'Decision model'],
    help: [
      'Consolidation, Réponses et pages de connaissance : hs-decide-1-flash (PyTorch ou MLX) ou un modèle System One ouvert, mesuré sur vos données.',
      'Consolidation, Answers and knowledge pages: hs-decide-1-flash (PyTorch or MLX) or an open System One model, measured on your data.',
    ],
  },
] as const;

const STEP_TONE: Record<string, string> = {
  ok: 'sage',
  running: 'amber',
  failed: 'red',
  pending: 'neutral',
};

/** Modèles › Modèles sur ce Mac : un choix par rôle, installé, testé, activé et vérifié en un clic. */
export function LocalModels({
  models,
  run,
  busy,
}: Pick<PageProps, 'run' | 'busy'> & { models: Row }) {
  const { t } = useI18n();
  const status: Row = models.status || {};
  const job: Row | undefined = status.job || undefined;
  const working = job?.status === 'running';
  if (!models.available) return null;
  return (
    <section className="card local-models">
      <CardHeader
        title={t('Modèles sur ce Mac', 'Models on this Mac')}
        subtitle={t(
          'Un clic télécharge le modèle choisi, le teste sur une vraie recherche, l’active quand rien ne tourne, redémarre ce qui en dépend et vérifie la recherche. En cas d’échec, le choix actuel revient tout seul.',
          'One click downloads the chosen model, tests it on a real search, activates it when nothing is running, restarts what depends on it and checks search. On failure, the current choice comes back on its own.',
        )}
      />
      <ErrorNotice message={models.problem} />
      {!status.hook && status.catalog && (
        <div className="notice">
          {t(
            'Le script de lancement du serveur ne lit pas encore ces choix : le premier changement l’y ajoutera (sauvegarde datée avant).',
            'The server launch script does not read these choices yet: the first change adds it (dated backup first).',
          )}
        </div>
      )}
      <div className="model-rows">
        {ROLES.map((role) => (
          <RoleRow
            key={role.id}
            role={role}
            status={status}
            disabled={busy || working}
            run={run}
            title={t(role.title[0], role.title[1])}
            help={t(role.help[0], role.help[1])}
          />
        ))}
      </div>
      {job && <JobView job={job} status={status} />}
      <p className="local-models-files">
        {t('Sélection :', 'Selection:')} {status.selectionFile}
        {status.updated ? ` · ${t('modifiée le', 'changed')} ${status.updated}` : ''}
      </p>
    </section>
  );
}

function RoleRow({
  role,
  status,
  disabled,
  run,
  title,
  help,
}: {
  role: (typeof ROLES)[number];
  status: Row;
  disabled: boolean;
  run: PageProps['run'];
  title: string;
  help: string;
}) {
  const { t } = useI18n();
  const options: Row[] = status.catalog?.[role.id] || [];
  const active: string = status.selection?.[role.id] || '';
  const [choice, setChoice] = useState(active);
  useEffect(() => setChoice(active), [active]);
  const chosen = options.find((o) => o.id === choice);
  const current = options.find((o) => o.id === active);
  const previous = options.find((o) => o.id === status.previous?.[role.id]);
  const server = status.servers?.[current?.engine === 'external' ? 'decision-alt' : role.id] || {};
  const facts = (o?: Row) =>
    o
      ? [
          o.quality != null && `${t('qualité', 'quality')} ${String(o.quality).replace('.', ',')}`,
          o.latency,
          o.memory,
        ]
          .filter(Boolean)
          .join(' · ')
      : '';
  return (
    <div className="local-model-row">
      <div>
        <strong>{title}</strong>
        <p>
          {help}{' '}
          {current && (
            <>
              <br />
              {t('Actif :', 'Active:')} {current.label} — {facts(current)}
              {current.engine !== 'cpu' &&
                (server.running ? ' ✓' : t(' · serveur arrêté', ' · server stopped'))}
            </>
          )}
        </p>
        {chosen && chosen.id !== active && (
          <p className="local-model-note">
            {facts(chosen)}. {chosen.note}
          </p>
        )}
      </div>
      <select
        value={choice}
        disabled={disabled}
        onChange={(e) => setChoice(e.target.value)}
        aria-label={title}
      >
        {options.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
            {o.id === active ? t(' (actif)', ' (active)') : ''}
          </option>
        ))}
      </select>
      <Button
        kind="primary"
        icon={ArrowDownToLine}
        disabled={disabled || !choice || choice === active}
        onClick={() => void run('models.local.apply', { role: role.id, option: choice })}
      >
        {t('Installer et activer', 'Install and activate')}
      </Button>
      {previous && (
        <Button
          icon={RotateCcw}
          disabled={disabled}
          title={t(`Revenir à ${previous.label}`, `Go back to ${previous.label}`)}
          onClick={() => void run('models.local.rollback', { role: role.id })}
        >
          {t('Revenir', 'Go back')}
        </Button>
      )}
    </div>
  );
}

function JobView({ job, status }: { job: Row; status: Row }) {
  const { t } = useI18n();
  const label =
    (status.catalog?.[job.role] || []).find((o: Row) => o.id === job.option)?.label || job.option;
  const tone =
    job.status === 'ok'
      ? 'sage'
      : job.status === 'running'
        ? 'amber'
        : job.status === 'rolled_back'
          ? 'amber'
          : 'red';
  const verdict: Record<string, string> = {
    running: t('en cours', 'running'),
    ok: t('actif et vérifié', 'active and verified'),
    rolled_back: t('échec, retour automatique', 'failed, rolled back'),
    failed: t('échec', 'failed'),
  };
  return (
    <div className="local-model-job">
      <div className="local-model-job-head">
        <strong>
          {t('Dernier changement :', 'Last change:')} {label}
        </strong>
        <Badge tone={tone}>{verdict[job.status] || job.status}</Badge>
      </div>
      <ol>
        {(job.steps || []).map((s: Row) => (
          <li key={s.id}>
            <Badge tone={STEP_TONE[s.status] || 'neutral'}>{s.title}</Badge>
            {s.detail && <span>{s.detail}</span>}
          </li>
        ))}
      </ol>
      {job.message && <p>{job.message}</p>}
      <details className="advanced-details">
        <summary>{t('Journal', 'Log')}</summary>
        <pre className="json-view">{(job.log || []).join('\n')}</pre>
      </details>
    </div>
  );
}
