import { Settings2 } from 'lucide-react';
import { ModelWorkflowSettings } from '../components/ModelWorkflow';
import { useI18n } from '../i18n';
import type { PageProps } from '../types';
import { Button, Empty, ErrorNotice, Loading, PageHeader } from '../ui';

export default function ModelChoices({ data, run, busy, navigate }: PageProps) {
  const { t } = useI18n();
  const manage = () => navigate('server');
  return (
    <>
      <PageHeader
        title={t('Modèles', 'Models')}
        description={t(
          'Choisissez vos modèles et voyez leur rôle dans la mémoire.',
          'Choose your models and see how they work in memory.',
        )}
        actions={
          <Button icon={Settings2} onClick={manage}>
            {t('Gérer les modèles', 'Manage models')}
          </Button>
        }
      />
      <ErrorNotice message={data.error} />
      {data.modelWorkflow ? (
        <ModelWorkflowSettings
          data={data}
          run={run}
          busy={busy}
          quick
          configure={manage}
          tools={manage}
        />
      ) : busy ? (
        <Loading />
      ) : (
        <Empty
          icon={Settings2}
          title={t('Configurez vos modèles', 'Configure your models')}
          description={t(
            'Ajoutez vos fournisseurs et choisissez le script du serveur dans « Serveur & modèles ».',
            'Add your providers and choose the server script in Server & models.',
          )}
          action={
            <Button onClick={manage}>
              {t('Ouvrir Serveur & modèles', 'Open Server & models')}
            </Button>
          }
        />
      )}
    </>
  );
}
