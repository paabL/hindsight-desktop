export type Language = 'fr' | 'en';
export const languageStorageKey = 'hindsight-desktop-language';

function preferredLanguage(): Language {
  try {
    const saved =
      typeof window === 'undefined' ? null : window.localStorage.getItem(languageStorageKey);
    if (saved === 'fr' || saved === 'en') return saved;
  } catch {}
  return 'en';
}

let language = preferredLanguage();
export const getLanguage = () => language;
export const getLocale = () => (language === 'fr' ? 'fr-CA' : 'en-CA');
/** Espaces insécables du français : un « ? », un « ; » ou un « : » ne commence jamais une ligne. */
export const frenchSpacing = (text: string) =>
  text
    .replace(/ ([;?!])/g, '\u202f$1')
    .replace(/ ([:»])/g, '\u00a0$1')
    .replace(/« /g, '«\u00a0');
export const translate = (fr: string, en: string) => (language === 'fr' ? frenchSpacing(fr) : en);

export function setLanguage(next: Language) {
  language = next;
  try {
    if (typeof window !== 'undefined') window.localStorage.setItem(languageStorageKey, next);
  } catch {}
}
