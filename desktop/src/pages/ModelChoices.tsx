import { useState } from 'react';
import { Settings2 } from 'lucide-react';
import { ModelWorkflowSettings } from '../components/ModelWorkflow';
import { useI18n } from '../i18n';
import type { PageProps } from '../types';
import { Button, Empty, ErrorNotice, Loading, PageHeader } from '../ui';
import { ModelManagement, type ModelRequest } from './Manage';

/**
 * Modèles : le seul endroit où se règlent les modèles. Le schéma porte le choix rapide et la barre
 * d'enregistrement ; dessous, les comptes, tous les rôles et l'installation.
 */
export default function ModelChoices(props: PageProps) {
  const { data, run, busy, navigate } = props;
  const { t } = useI18n();
  const [request, setRequest] = useState<ModelRequest>();
  const configure = (id: string) => setRequest({ kind: 'role', id, nonce: Date.now() });
  const tools = () => setRequest({ kind: 'tools', nonce: Date.now() });
  const configured = Boolean(data.modelWorkflow || data.roles?.length || data.accounts?.length);
  return (
    <>
      <PageHeader
        title={t('Modèles', 'Models')}
        description={t(
          'Le modèle de chaque fonction de la mémoire. Choisissez sur le schéma ; les comptes, tous les rôles et l’installation sont plus bas.',
          'The model behind each memory function. Choose on the diagram; accounts, every role and installation are further down.',
        )}
      />
      <ErrorNotice message={data.error} />
      {data.modelWorkflow ? (
        <ModelWorkflowSettings
          data={data}
          run={run}
          busy={busy}
          quick
          configure={configure}
          tools={tools}
        />
      ) : busy && !configured ? (
        <Loading />
      ) : (
        <Empty
          icon={Settings2}
          title={t('Choisissez le script du serveur', 'Choose the server script')}
          description={t(
            'Les modèles et leurs fournisseurs sont lus dans le script de lancement du serveur, à choisir dans Réglages › Serveur.',
            'Models and their providers are read from the server launch script, chosen in Settings › Server.',
          )}
          action={
            <Button onClick={() => navigate('server')}>
              {t('Ouvrir Réglages › Serveur', 'Open Settings › Server')}
            </Button>
          }
        />
      )}
      {configured && <ModelManagement {...props} request={request} />}
    </>
  );
}
