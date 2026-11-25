import { useEffect, useState } from 'react';
import { ArrowDownToLine, Check, Pause, Play, RotateCcw, Trash2 } from 'lucide-react';
import { useI18n } from '../i18n';
import { localDecisionStateLabel } from '../model-field-options';
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

/**
 * Modèles › Modèles Hindsight : le seul endroit des modèles spécialisés. D'abord où chacun tourne
 * (Hindsight Cloud, ce Mac ou rien), puis, sur ce Mac, le choix de chaque rôle (installé, testé, activé et
 * vérifié en un clic) et le service du modèle de décision.
 */
export function HindsightModels({
  models,
  run,
  busy,
}: Pick<PageProps, 'run' | 'busy'> & { models: Row }) {
  const { t } = useI18n();
  const local: Row = models.local || {};
  const running = local.phase === 'running';
  const old = !models.serverIs120;
  const manager: Row = models.localModels || {};
  const status: Row = manager.status || {};
  const job: Row | undefined = status.job || undefined;
  const working = job?.status === 'running';
  return (
    <section className="card hindsight-models" data-model-tools>
      <CardHeader
        title={t('Modèles Hindsight', 'Hindsight models')}
        subtitle={t(
          'Modèles spécialisés, sur Hindsight Cloud (facturés au compte) ou sur ce Mac. Le choix Cloud ou Mac prépare le script : enregistrez-le, puis redémarrez le serveur.',
          'Specialized models, on Hindsight Cloud (billed to your account) or on this Mac. The Cloud or Mac choice prepares the script: save it, then restart the server.',
        )}
      />
      {old && (
        <div className="notice">
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
              {t('Modèle de décision · hs-decide-1-flash', 'Decision model · hs-decide-1-flash')}
            </strong>
            <p>
              {t(
                'Tranche les choix de la consolidation, des Réponses et des pages de connaissance sans appel LLM : moins de jetons et moins d’attente.',
                'Makes consolidation, Answers and knowledge page decisions without LLM calls: fewer tokens and less waiting.',
              )}
              {models.decision === 'other' &&
                t(
                  ' Réglage personnalisé dans le rôle plus bas.',
                  ' Custom settings in the role below.',
                )}
            </p>
          </div>
          <SourceChoices
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
              {t(
                'Classe les résultats de recherche, sans ré-indexation.',
                'Ranks search results without reindexing.',
              )}
              {models.reranker === 'other' &&
                t(' Autre reranker configuré.', ' Another reranker is configured.')}
            </p>
          </div>
          <SourceChoices
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
          {t(
            'Connectez le compte Hindsight Cloud plus bas : sans sa clé, le serveur refusera de démarrer avec ces choix.',
            'Connect your Hindsight Cloud account below: without its key, the server cannot start with these choices.',
          )}
        </div>
      )}
      <h3 className="hindsight-models-local">{t('Sur ce Mac', 'On this Mac')}</h3>
      <DecisionService local={local} run={run} busy={busy} />
      {manager.available && (
        <>
          <p className="local-models-intro">
            {t(
              'Un clic télécharge le modèle choisi, le teste sur une vraie recherche, l’active quand rien ne tourne, redémarre ce qui en dépend et vérifie la recherche. En cas d’échec, le choix actuel revient tout seul.',
              'One click downloads the chosen model, tests it on a real search, activates it when nothing is running, restarts what depends on it and checks search. On failure, the current choice comes back on its own.',
            )}
          </p>
          <ErrorNotice message={manager.problem} />
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
        </>
      )}
    </section>
  );
}

function SourceChoices({
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

/** Service du modèle de décision sur ce Mac (127.0.0.1:8766) : installer, démarrer, arrêter, journal. */
function DecisionService({ local, run, busy }: Pick<PageProps, 'run' | 'busy'> & { local: Row }) {
  const { t } = useI18n();
  const running = local.phase === 'running';
  return (
    <>
      <div className="local-decision">
        <div>
          <strong>{t('Service du modèle de décision', 'Decision model service')}</strong>
          <p>
            {local.summary}
            {local.installed
              ? t(
                  ' · 127.0.0.1:8766, chargé à la première demande, libéré après 20 min sans demande',
                  ' · 127.0.0.1:8766, loaded on the first request, released after 20 idle minutes',
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
            {t('Installer…', 'Install…')}
          </Button>
        ) : running ? (
          <Button
            icon={Pause}
            disabled={busy || local.busy}
            onClick={() => void run('decision.stop')}
          >
            {t('Arrêter', 'Stop')}
          </Button>
        ) : (
          <Button
            icon={Play}
            disabled={busy || local.busy}
            onClick={() => void run('decision.start')}
          >
            {t('Démarrer', 'Start')}
          </Button>
        )}
      </div>
      <ErrorNotice message={local.problem} />
      {(local.log || local.installed) && (
        <details className="advanced-details local-decision-log">
          <summary>{t('Journal du service de décision', 'Decision service log')}</summary>
          <pre className="json-view">
            {local.log || t('Aucun journal disponible.', 'No log available.')}
          </pre>
          <p>
            {t('Dossier :', 'Folder:')} {local.root} {t('· journal :', '· log:')} {local.logPath}
          </p>
          {local.installed && (
            <Button
              kind="danger"
              icon={Trash2}
              disabled={busy || local.busy}
              onClick={() => void run('decision.uninstall')}
            >
              {t('Désinstaller le modèle local', 'Uninstall local model')}
            </Button>
          )}
        </details>
      )}
    </>
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
