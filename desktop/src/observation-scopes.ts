// Portées des observations, mêmes choix partout (lecteur de document, réglages de la banque).
// Le serveur accepte aussi des listes explicites d'étiquettes ; elles se règlent par l'API.
export const OBSERVATION_SCOPES: { value: string; fr: string; en: string }[] = [
  { value: 'shared', fr: 'Partagée', en: 'Shared' },
  { value: 'combined', fr: 'Combinée', en: 'Combined' },
  { value: 'per_tag', fr: 'Par étiquette', en: 'Per tag' },
  { value: 'all_combinations', fr: 'Toutes les combinaisons', en: 'All combinations' },
];

export const isListedScope = (value: unknown): value is string =>
  typeof value === 'string' && OBSERVATION_SCOPES.some((scope) => scope.value === value);
