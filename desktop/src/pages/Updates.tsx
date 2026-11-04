import { useState } from 'react';
import { Download, RefreshCw, FolderOpen, RotateCcw } from 'lucide-react';
import type { Request, Row } from '../types';
import { Badge, Button, CardHeader, ErrorNotice, date } from '../ui';
import { pickDirectory, host } from '../transport';
import { useI18n } from '../i18n';

export default function Updates({ data, run, demo }: { data: Row; run: Request; demo: boolean }) {
  const { t } = useI18n();
  demo = demo || host !== 'Tauri';
  const [path, setPath] = useState('');
  const working = !!data.working;
  async function choose() {
    try {
      const value = await pickDirectory(
        t(
          'Choisir le dépôt source de Hindsight Desktop',
          'Choose the Hindsight Desktop source repository',
        ),
      );
      if (value) setPath(value);
    } catch (error) {
      setError(error instanceof Error ? error.message : String(error));
    }
  }
  const [error, setError] = useState<string | null>(null);
  return (
    <section className="card settings-card">
      <CardHeader
        title={t('Mises à jour de l’application', 'Application updates')}
        subtitle={
          data.version
            ? t(`Version installée : ${data.version}`, `Installed version: ${data.version}`)
            : undefined
        }
        action={
          <Badge>
            {working
              ? t('En cours', 'In progress')
              : data.state === 'ready'
                ? t('Installée', 'Installed')
                : 'Tauri'}
          </Badge>
        }
      />
      <p>
        {t(
          'Retrouvez les nouvelles versions et leurs instructions d’installation sur la page du projet.',
          'Find new versions and installation instructions on the project page.',
        )}
      </p>
      <div className="action-row">
        <Button
          icon={Download}
          disabled={demo}
          onClick={() =>
            void run('external.open', {
              url: 'https://github.com/paabL/hindsight-desktop/releases',
            })
          }
        >
          {t('Voir les versions', 'View releases')}
        </Button>
      </div>
      <details
        open={working || data.state === 'failed' || data.state === 'ready' ? true : undefined}
      >
        <summary>
          {t('Construire depuis les sources (avancé)', 'Build from source (advanced)')}
        </summary>
        <p className="form-hint">
          {t(
            'Cette option s’adresse aux personnes qui ont installé les outils de développement et une copie du code source.',
            'This option requires development tools and a local copy of the source code.',
          )}
        </p>
        <div className="form-stack">
          <ErrorNotice message={error} />
          <label>
            {t('Dossier du projet', 'Project folder')}
            <div className="inline-form">
              <input
                style={{ flex: 1 }}
                aria-label={t('Dossier source des mises à jour', 'Update source folder')}
                value={path || data.repository || ''}
                onChange={(e) => setPath(e.target.value)}
                disabled={working || demo}
                placeholder={t(
                  'Choisir le dépôt Hindsight Desktop',
                  'Choose the Hindsight Desktop repository',
                )}
              />
              <Button icon={FolderOpen} disabled={working || demo} onClick={() => void choose()}>
                {t('Choisir', 'Choose')}
              </Button>
            </div>
          </label>
          {data.state === 'failed' ? (
            <ErrorNotice message={data.message} />
          ) : (
            <p role="status">
              {data.message ||
                t(
                  'Recherchez les commits disponibles avant de préparer l’installation.',
                  'Check for available changes before preparing the installation.',
                )}
            </p>
          )}
          {data.dirty && (
            <p className="form-hint">
              {t(
                'La copie locale contient des modifications. L’application de commits distants est bloquée ; vous pouvez reconstruire cette copie après confirmation.',
                'This local copy has changes. Remote changes cannot be applied; you can rebuild this copy after confirmation.',
              )}
            </p>
          )}
          {!!data.commits?.length && (
            <div className="update-commits">
              {data.commits.map((commit: Row) => (
                <div key={commit.sha}>
                  <code>{commit.sha.slice(0, 7)}</code>
                  <span>{commit.subject}</span>
                  <small>
                    {commit.author} · {commit.date}
                  </small>
                </div>
              ))}
            </div>
          )}
          <div className="action-row">
            <Button
              icon={RefreshCw}
              disabled={working || demo}
              onClick={() => void run('updates.check', { path: path || data.repository })}
            >
              {t('Rechercher les mises à jour', 'Check for updates')}
            </Button>
            {data.state === 'available' && (
              <Button
                kind="primary"
                icon={Download}
                disabled={working || demo || data.dirty || (!!path && path !== data.repository)}
                onClick={() => void run('updates.install')}
              >
                {t('Installer la mise à jour', 'Install update')}
              </Button>
            )}
            <Button
              icon={RotateCcw}
              disabled={working || demo || !(path || data.repository)}
              onClick={() => void run('updates.rebuild', { path: path || data.repository })}
            >
              {t('Recompiler cette copie', 'Rebuild this copy')}
            </Button>
            {data.state === 'ready' && (
              <Button
                kind="primary"
                disabled={working || demo}
                onClick={() => void run('updates.relaunch')}
              >
                {t('Relancer l’application', 'Relaunch application')}
              </Button>
            )}
          </div>
          {working && (
            <div className="notice" role="status">
              {data.message}{' '}
              {t(
                'Vous pouvez laisser cette fenêtre ouverte pendant la compilation.',
                'You can leave this window open while the app builds.',
              )}
            </div>
          )}
          {!!data.log && (
            <details open={data.state === 'failed'}>
              <summary>{t('Journal de mise à jour', 'Update log')}</summary>
              <pre className="json-view">{data.log}</pre>
            </details>
          )}
          <p className="form-hint">
            {t(
              'La version est reconstruite sur ce Mac avant de remplacer l’app ouverte. Node.js, Xcode et Rust sont nécessaires. Le code téléchargé sera exécuté avec vos droits après confirmation.',
              'The version is built on this Mac before replacing the open app. Node.js, Xcode and Rust are required. Downloaded code runs with your permissions after confirmation.',
            )}
          </p>
          {data.checkedAt && (
            <p className="page-footnote">
              {t('Dernière vérification :', 'Last checked:')} {date(data.checkedAt, true)}
            </p>
          )}
        </div>
      </details>
    </section>
  );
}
