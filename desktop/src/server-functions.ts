import { translate as t } from './i18n-core.ts';

/**
 * Nom d'une fonction du serveur (`retain`, `recall`…) avec le vocabulaire de l'app : le même dans la
 * barre latérale, la consommation et les journaux. Une valeur inconnue reste telle que le serveur l'écrit.
 */
export function serverFunctionLabel(key?: string | null): string {
  switch (key) {
    case 'retain':
      return t('Extraction des faits', 'Fact extraction');
    case 'consolidation':
      return t('Consolidation', 'Consolidation');
    case 'recall':
      return t('Recherche', 'Search');
    case 'reflect':
      return t('Réponses', 'Answers');
    case 'mental_model':
    case 'refresh_mental_model':
      return t('Connaissances', 'Knowledge');
    case 'vlm':
      return t('Vision (VLM)', 'Vision (VLM)');
    default:
      return key || '';
  }
}
