import { translate as t } from './i18n-core.ts';

/** Libellés des types de faits Hindsight : une seule table pour toutes les vues. */
export function factTypeLabel(type?: string | null) {
  switch (type) {
    case 'world':
      return t('Fait du monde', 'World fact');
    case 'experience':
      return t('Expérience', 'Experience');
    case 'observation':
      return t('Observation', 'Observation');
    case 'opinion':
      return t('Opinion', 'Opinion');
    default:
      return t('Fait', 'Fact');
  }
}

/** Forme plurielle, pour les filtres et les répartitions par type. */
export function factTypePluralLabel(type?: string | null) {
  switch (type) {
    case 'world':
      return t('Faits du monde', 'World facts');
    case 'experience':
      return t('Expériences', 'Experiences');
    case 'observation':
      return t('Observations', 'Observations');
    case 'opinion':
      return t('Opinions', 'Opinions');
    default:
      return t('Faits', 'Facts');
  }
}
